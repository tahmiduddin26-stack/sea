--!strict
-- The tutorial, drawn: the banner line for the current step (gold key word), a trail of
-- glowing red chevrons along the deck from you to the target, a big bobbing arrow over the
-- target, and for HUD targets (FIGHT, FUSE) a bouncing arrow + pulse on the button.
-- The server owns the step (snapshot.tutorial); this only shows the way.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Stats = require(Shared.Stats)

local UI = require(script.Parent.UI)
local State = require(script.Parent.State)
local Hud = require(script.Parent.Hud)
local Menus = require(script.Parent.Menus)
local Sound = require(script.Parent.Sound)
local ShipView = require(script.Parent.ShipView)

local Guide = {}

local player = Players.LocalPlayer
local C = UI.Colors

local ARROW = Color3.fromRGB(255, 60, 60)
local SPACING = 3.2

local folder = Instance.new("Folder")
folder.Name = "GuideTrail"
local chevrons: { { BasePart } } = {}
local marker: Model
local guiArrow: TextLabel
-- the Fuse hint is a little tag beside the Fuse button, not the big top banner
local fuseTag: Frame
local fuseTagLbl: TextLabel
local fuseTagTail: TextLabel

local function emptySideNest(ship: Model?, root: BasePart?): BasePart?
	local best: BasePart? = nil
	local distance = math.huge
	if ship and root then
		for i, slot in Config.NEST_SLOTS do
			if slot.sideBay then
				local pad = ship:FindFirstChild("Nest" .. i) :: BasePart?
				if pad and pad:GetAttribute("State") == "empty" then
					local gap = (root.Position - pad.Position).Magnitude
					if gap < distance then best, distance = pad, gap end
				end
			end
		end
	end
	return best
end

local function bar(): BasePart
	local b = Instance.new("Part")
	b.Anchored = true
	b.CanCollide = false
	b.CanQuery = false
	b.CanTouch = false
	b.CastShadow = false
	b.Material = Enum.Material.Neon
	b.Color = ARROW
	b.Size = Vector3.new(0.5, 0.15, 1.9)
	b.Parent = folder
	return b
end

local function placeChevron(bars: { BasePart }, cf: CFrame)
	bars[1].CFrame = cf * CFrame.new(-0.62, 0, 0.1) * CFrame.Angles(0, math.rad(-40), 0)
	bars[2].CFrame = cf * CFrame.new(0.62, 0, 0.1) * CFrame.Angles(0, math.rad(40), 0)
end

local function buildMarker(): Model
	local m = Instance.new("Model")
	m.Name = "Marker"
	local function piece(size: Vector3, cf: CFrame, color: Color3)
		local p = bar()
		p.Size = size
		p.Color = color
		p.CFrame = cf
		p.Parent = m
	end
	-- a chunky down arrow
	piece(Vector3.new(0.8, 1.6, 0.8), CFrame.new(0, 1.3, 0), ARROW)
	piece(Vector3.new(0.6, 1.5, 0.8), CFrame.new(-0.45, 0.35, 0) * CFrame.Angles(0, 0, math.rad(45)), ARROW)
	piece(Vector3.new(0.6, 1.5, 0.8), CFrame.new(0.45, 0.35, 0) * CFrame.Angles(0, 0, math.rad(-45)), ARROW)
	m.WorldPivot = CFrame.new()
	m.Parent = folder
	return m
end

local function myShip(): Model?
	local idx = player:GetAttribute("Ship")
	local world = workspace:FindFirstChild("World")
	return if idx and world then world:FindFirstChild("Ship" .. idx) :: Model? else nil
end

-- where the current step points in the world (nil = a HUD target or nothing)
local function worldTarget(target: string?): BasePart?
	local ship = myShip()
	if not ship or not target then
		return nil
	end
	if target == "winch" then
		return ship:FindFirstChild("Winch", true) :: BasePart?
	elseif target == "pedestal" then
		for _, d in ship:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("PedestalIndex") and d:GetAttribute("Sp") then
				return d
			end
		end
	elseif target == "nest" or target == "egg" then
		local best: BasePart? = nil
		for _, d in ship:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("NestIndex") then
				local state = d:GetAttribute("State")
				if target == "nest" and state == "empty" then
					if not best or (d:GetAttribute("NestIndex") :: number) < (best:GetAttribute("NestIndex") :: number) then
						best = d
					end
				elseif target == "egg" and state == "egg" then
					return d
				end
			end
		end
		return best
	end
	return nil
end

local function hudTarget(target: string?): GuiObject?
	if target == "fight" then
		return Hud.fightButton()
	elseif target == "fuse" then
		return Hud.fuseButton()
	end
	return nil
end

-- Do you own enough monsters of one level to fuse (Stats.fuseNeeded: 2 for Lv1-2, then the level)?
local function canFuseNow(snap: any): boolean
	if not snap or not snap.monsters then
		return false
	end
	local byKey: { [string]: number } = {}
	for _, m in snap.monsters do
		local l = m.lvl :: number
		if l < Stats.maxLevel(m.sp) then
			local k = Stats.fuseKey(m.sp, l)
			byKey[k] = (byKey[k] or 0) + 1
			if byKey[k] >= Stats.fuseNeeded(l, m.sp) then
				return true
			end
		end
	end
	return false
end

-- True while the guide should show nothing: a fight is running, you are not on your own ship, or the
-- camera is facing the arena (out to starboard) from the deck. The tutorial and Fuse
-- helper skip the camera check so turning around never removes the current instruction.
local function isQuiet(ignoreLook: boolean?): boolean
	if Hud.inBattle then
		return true
	end
	local ship = myShip()
	local shipCf = if ship then ship:GetAttribute("ShipCf") :: CFrame? else nil
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not shipCf or not root then
		return false
	end
	-- off the ship (the arena side, the water, the harbour): only the ship gets prompts
	local rel = shipCf:PointToObjectSpace(root.Position)
	local width = Config.SHIP_WIDTH / 2 + 8
	for _, span in Config.NEST_BAY_SPANS do
		if rel.Z >= span[1] and rel.Z <= span[2] then width = Config.SHIP_WIDTH / 2 + Config.NEST_BAY_WIDTH end
	end
	if math.abs(rel.X) > width or math.abs(rel.Z) > Config.SHIP_LENGTH / 2 + 8 then
		return true
	end
	if ignoreLook then
		return false
	end
	-- on the deck but looking out at the arena
	local cam = workspace.CurrentCamera
	local arena = shipCf:PointToWorldSpace(Vector3.new(Config.ARENA_OFFSET, 0, Config.ARENA_OFFSET_Z))
	local toArena = Vector3.new(arena.X - cam.CFrame.Position.X, 0, arena.Z - cam.CFrame.Position.Z)
	local look = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
	if toArena.Magnitude > 1 and look.Magnitude > 0.01 and toArena.Magnitude < 150 and look.Unit:Dot(toArena.Unit) > 0.6 then
		return true
	end
	return false
end

-- An on-demand helper, set by a view while it is open (the Fuse tray): the same red trail, bobbing
-- arrow and banner as the tutorial, but driven by what the view says is the next thing to do.
--   text()  the banner line
--   world() a part in the world to walk / look at (or nil)
--   gui()   a button on screen to press (or nil)
Guide.helper = nil :: { text: () -> string, world: () -> BasePart?, gui: () -> GuiObject? }?

function Guide.init(screen: ScreenGui)
	marker = buildMarker()
	guiArrow = UI.label({ Text = "▼", TextColor3 = ARROW, Size = UDim2.fromOffset(60, 60), AnchorPoint = Vector2.new(0.5, 1), Visible = false, ZIndex = 20, Parent = screen })
	fuseTag = UI.panel({ Size = UDim2.fromOffset(250, 78), AnchorPoint = Vector2.new(1, 0.5), Color = Color3.fromRGB(40, 140, 235), Radius = 18, Visible = false, ZIndex = 20, Parent = screen })
	fuseTagLbl = UI.label({ Text = "", MaxText = 24, TextWrapped = true, Size = UDim2.new(1, -24, 1, -14), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Stroke = 2, ZIndex = 21, Parent = fuseTag })
	fuseTagTail = UI.label({ Text = "▶", TextColor3 = Color3.fromRGB(40, 140, 235), Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, 14, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 19, Parent = fuseTag })
	local nextStep: ("unlock" | "fish" | "place" | "cove")? = nil
	local selectedNest: BasePart? = nil
	local previousEggs: { [string]: boolean } = {}
	local bayEntry = Instance.new("Part") -- a waypoint on the deck side of the bay opening
	bayEntry.Size = Vector3.one * 0.1
	local function showUnlock()
		local _, body = Menus.openWindow("SHIP UPGRADE", Vector2.new(540, 310), C.Gold)
		local badge = UI.plank({ Color = C.Kelp, Size = UDim2.new(1, -44, 0, 70), Position = UDim2.fromOffset(22, 16), Radius = 18, Parent = body })
		UI.label({ Text = "4 NEW NESTS!", MaxText = 36, Size = UDim2.new(1, -12, 1, -8), Position = UDim2.fromOffset(6, 4), Parent = badge })
		UI.label({ Text = "Two on each side of your ship.", TextColor3 = C.Ink, Stroke = 0, MaxText = 24, Size = UDim2.new(1, -32, 0, 38), Position = UDim2.fromOffset(16, 95), Parent = body })
		UI.button({ Name = "FishForEgg", Text = "Fish for an Egg", Color = C.Sea, Size = UDim2.new(1, -84, 0, 60), Position = UDim2.new(0, 42, 1, -76), Parent = body }, function()
			Menus.close()
			nextStep = "fish"
		end)
	end
	local function showActivities()
		local _, body = Menus.openWindow("EGG IN THE NEST", Vector2.new(560, 244), C.Kelp)
		UI.label({ Text = "Open it when the timer ends.", TextColor3 = C.Ink, Stroke = 0, MaxText = 25, Size = UDim2.new(1, -28, 0, 46), Position = UDim2.fromOffset(14, 12), Parent = body })
		UI.button({ Name = "FightWhileHatching", Text = "FIGHT!", Color = C.Coral, Size = UDim2.new(0.48, -8, 0, 58), Position = UDim2.new(0.02, 0, 1, -78), Parent = body }, function()
			Menus.close()
			Hud.press("Fight")
		end)
		UI.button({ Name = "VisitCrabCove", Text = "Visit Crab Cove", Color = C.Sea, Size = UDim2.new(0.48, -8, 0, 58), Position = UDim2.new(0.52, 0, 1, -78), Parent = body }, function()
			Menus.close()
			nextStep = "cove"
		end)
	end

	Remotes.event("Tutorial").OnClientEvent:Connect(function(step)
		if step > 1 then
			Sound.play("Click", 0.5, 1.4)
		end
		if step == Config.TUTORIAL_DONE then
			nextStep = "unlock"
		end
	end)

	RunService.RenderStepped:Connect(function()
		local snap = State.snapshot
		local t = os.clock()
		local step = if snap then snap.tutorial else 0
		local info = Config.TUTORIAL[step]
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local freeToGuide = not State.cinematic and not State.revealing and not Hud.inBattle and not Menus.isOpen() and not Guide.helper
		if snap and step >= Config.TUTORIAL_DONE and freeToGuide then
			if nextStep == "unlock" then
				nextStep = nil
				showUnlock()
			elseif nextStep == "fish" and snap.carrying then
				nextStep = "place"
				selectedNest = nil
				table.clear(previousEggs)
				for _, nest in snap.nests do
					if nest.kind == "egg" and nest.egg.saleId then previousEggs[nest.egg.saleId] = true end
				end
			elseif nextStep == "place" and not snap.carrying then
				nextStep = "fish" -- putting the egg back is also allowed
				for _, nest in snap.nests do
					if nest.kind == "egg" and nest.egg.saleId and not previousEggs[nest.egg.saleId] then
						nextStep = nil
						showActivities()
						break
					end
				end
			end
		end
		-- Hide the banner during battles. Keep tutorial instructions visible from any deck camera angle.
		local helper = Guide.helper
		local quiet = isQuiet(helper ~= nil or info ~= nil or nextStep ~= nil)
		-- the Fuse prompt (tag + arrow) only makes sense when something CAN be fused right now
		local noFuse = info ~= nil and info.target == "fuse" and not canFuseNow(snap)
		local fishing = info ~= nil and info.target == "winch" and player:GetAttribute("Fishing") == true
		local active = info ~= nil and (not State.cinematic or fishing) and not Hud.inBattle and not State.revealing and not quiet and not noFuse
		local helping = helper ~= nil and not State.cinematic and not Hud.inBattle and not State.revealing and not quiet
		local target = if active and info and not fishing then info.target else nil
		local part = if helping and helper then helper.world() else worldTarget(target)
		local nextText: string? = nil
		if freeToGuide and not Menus.isOpen() and step >= Config.TUTORIAL_DONE and not info then
			if nextStep == "fish" and not quiet then
				local egg = worldTarget("pedestal")
				part = egg or worldTarget("winch")
				nextText = if egg then "Choose <TAKE> to pick up your egg." else "Follow the arrows and choose <FISH>."
			elseif nextStep == "place" and root and not quiet then
				local ship = myShip()
				if not selectedNest or not selectedNest.Parent or selectedNest:GetAttribute("State") ~= "empty" then
					selectedNest = emptySideNest(ship, root) or worldTarget("nest")
				end
				part = selectedNest
				local cf = ship and ship:GetAttribute("ShipCf") :: CFrame?
				if cf and part and math.abs(cf:PointToObjectSpace(part.Position).X) > Config.SHIP_WIDTH / 2 then
					local to = cf:PointToObjectSpace(part.Position)
					local from = cf:PointToObjectSpace(root.Position)
					if math.abs(from.Z - to.Z) > 4.5 and math.abs(from.X) < Config.SHIP_WIDTH / 2 then
						bayEntry.Position = cf:PointToWorldSpace(Vector3.new(math.sign(to.X) * (Config.SHIP_WIDTH / 2 - 4), to.Y, to.Z))
						part = bayEntry
					end
				end
				nextText = if part then "Follow the arrows and choose <PLACE EGG>." else "Make room in a nest for your egg."
			elseif nextStep == "cove" and root then
				local ship = myShip()
				local world = workspace:FindFirstChild("World")
				local covePrompt = world and world:FindFirstChild("CardsPrompt", true)
				local host = covePrompt and covePrompt.Parent
				local harbour = world and world:FindFirstChild("Harbour")
				local shore = harbour and snap and harbour:FindFirstChild("ShoreRamp" .. tostring(snap.shipIndex)) :: BasePart?
				local cf = ship and ship:GetAttribute("ShipCf") :: CFrame?
				if host and host:IsA("BasePart") then
					if player:GetAttribute("InCrabCove") or (root.Position - host.Position).Magnitude < 13 then
						nextStep = nil
					else
						part = host
						if cf and shore then
							local z = cf:PointToObjectSpace(root.Position).Z
							if z > -79 then part = ship and ship:FindFirstChild("ShipGate") :: BasePart?
							elseif z > cf:PointToObjectSpace(shore.Position).Z then part = shore end
						end
						nextText = "Follow the arrows to <CRAB COVE>."
					end
				end
			end
		end
		-- the Fuse step shows beside the Fuse button instead of in the top banner
		local tagText: string? = nil
		if nextText then
			Hud.banner(nextText)
		elseif quiet then
			Hud.banner(nil)
		elseif helping and helper then
			Hud.banner(helper.text())
		elseif not info or (State.cinematic and not fishing) then
			Hud.banner(nil)
		elseif active and info.target == "fuse" then
			Hud.banner(nil)
			tagText = info.text
		elseif active then
			local readyAt = if target == "egg" and part then part:GetAttribute("ReadyAt") :: number? else nil
			local left = if readyAt then math.ceil(readyAt - State.now()) else 0
			local price = if target == "pedestal" and part then part:GetAttribute("Price") :: number? else nil
			Hud.banner(if fishing then "Your hook is bringing up an <EGG>!"
				elseif left > 0 then "Your egg is warming up. <OPEN> in " .. left .. "s."
				elseif price and price > 0 then "Choose <TAKE> to buy this egg for " .. Format.abbrev(price) .. " coins."
				else info.text)
		else
			Hud.banner(nil)
		end
		-- carrying an egg changes "nest" targets from the winch side; fine as is
		if part and root then
			folder.Parent = workspace
			local top = part.Position.Y + part.Size.Y / 2
			-- above the monster on the nest, however big it has grown
			local monTop = ShipView.monsterTopY(part)
			if monTop then
				top = math.max(top, monTop - 2)
			end
			marker:PivotTo(CFrame.new(part.Position.X, top + 4 + math.abs(math.sin(t * 3)) * 1.2, part.Position.Z) * CFrame.Angles(0, t * 2, 0))
			local floorY = root.Position.Y - 2.9
			local from = Vector3.new(root.Position.X, floorY, root.Position.Z)
			local to = Vector3.new(part.Position.X, floorY, part.Position.Z)
			local gap = to - from
			local dist = gap.Magnitude
			local dir = if dist > 0.1 then gap.Unit else Vector3.zAxis
			local count = math.clamp(math.floor((dist - 3) / SPACING), 0, 40)
			for i = 1, math.max(count, #chevrons) do
				if i <= count then
					local bars = chevrons[i] or { bar(), bar() }
					chevrons[i] = bars
					local glow = (math.sin(t * 7 - i * 0.7) + 1) / 2
					for _, b in bars do
						b.Transparency = 0.5 - glow * 0.45
					end
					local p = from + dir * (1.5 + i * SPACING)
					placeChevron(bars, CFrame.lookAt(p, p + dir)) -- the V points toward the target
				elseif chevrons[i] then
					for _, b in chevrons[i] do
						b:Destroy()
					end
					chevrons[i] = nil
				end
			end
		else
			folder.Parent = nil
		end
		-- HUD target: bouncing arrow over the button
		local gui = if helping and helper then helper.gui() else hudTarget(target)
		if gui and gui.Visible then
			guiArrow.Visible = true
			local pos = gui.AbsolutePosition
			local size = gui.AbsoluteSize
			local inset = screen.AbsolutePosition
			local scale = 1
			local sc = screen:FindFirstChildOfClass("UIScale")
			if sc then
				scale = sc.Scale
			end
			local x = (pos.X - inset.X + size.X / 2) / scale
			local y = (pos.Y - inset.Y) / scale
			local above = target == "fuse" or (helping and helper ~= nil)
			local bob = math.abs(math.sin(t * 4)) * 10
			if above then
				guiArrow.Rotation = 0
				guiArrow.AnchorPoint = Vector2.new(0.5, 1)
				guiArrow.Position = UDim2.fromOffset(x, y - 4 - bob)
			else
				-- beside the button (pointing at it), not under it: under the FIGHT button sit
				-- "Team Power" and the tutorial banner, and the arrow landed on top of their words
				guiArrow.Rotation = 90 -- the down arrow turned to point left, at the button
				guiArrow.AnchorPoint = Vector2.new(0.5, 0.5)
				guiArrow.Position = UDim2.fromOffset(x + size.X / scale / 2 + 34 + bob, y + size.Y / scale / 2)
			end
		else
			guiArrow.Visible = false
		end
		-- the tag: sits to the left of the Fuse button, pointing at it
		local fuseGui = Hud.fuseButton()
		if tagText and fuseGui.Visible then
			local sc = screen:FindFirstChildOfClass("UIScale")
			local scale = if sc then sc.Scale else 1
			local inset = screen.AbsolutePosition
			local pos, size = fuseGui.AbsolutePosition, fuseGui.AbsoluteSize
			local new = UI.keyword(tagText)
			if fuseTagLbl.Text ~= new or not fuseTag.Visible then
				fuseTagLbl.Text = new
				fuseTag.Visible = true
				UI.pop(fuseTag, 0.85)
			end
			local bob = math.abs(math.sin(t * 4)) * 6
			fuseTag.Position = UDim2.fromOffset((pos.X - inset.X) / scale - 30 - bob, (pos.Y - inset.Y + size.Y / 2) / scale)
		else
			fuseTag.Visible = false
		end
		local _ = C
	end)
end

return Guide
