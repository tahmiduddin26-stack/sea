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
local Remotes = require(Shared.Remotes)
local Stats = require(Shared.Stats)

local UI = require(script.Parent.UI)
local State = require(script.Parent.State)
local Hud = require(script.Parent.Hud)
local Sound = require(script.Parent.Sound)
local Platform = require(script.Parent.Platform)
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

local lastStep = 0

-- Do you own enough monsters of one level to fuse (Stats.fuseNeeded: 2 for Lv1-2, then the level)?
local function canFuseNow(snap: any): boolean
	if not snap or not snap.monsters then
		return false
	end
	local byLevel: { [number]: number } = {}
	for _, m in snap.monsters do
		local l = m.lvl :: number
		byLevel[l] = (byLevel[l] or 0) + 1
	end
	for l, n in byLevel do
		if l < Config.MAX_LEVEL and n >= Stats.fuseNeeded(l) then
			return true
		end
	end
	return false
end

-- True while the guide should show nothing: a fight is running, you are not on your own ship, or the
-- camera is facing the arena (out to starboard) from the deck. `ignoreLook` skips that last check:
-- the Fuse helper points at monsters on your own deck, and hiding it whenever the camera happened
-- to swing toward the arena made the arrow vanish at some angles.
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
	if math.abs(rel.X) > Config.SHIP_WIDTH / 2 + 8 or math.abs(rel.Z) > Config.SHIP_LENGTH / 2 + 8 then
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
	fuseTagLbl = UI.label({ Text = "", MaxText = 24, Size = UDim2.new(1, -24, 1, -14), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Stroke = 2, ZIndex = 21, Parent = fuseTag })
	fuseTagTail = UI.label({ Text = "▶", TextColor3 = Color3.fromRGB(40, 140, 235), Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, 14, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 19, Parent = fuseTag })

	Remotes.event("Tutorial").OnClientEvent:Connect(function(step)
		if step > 1 then
			Sound.play("Click", 0.5, 1.4)
		end
		if step == Config.TUTORIAL_DONE then
			task.delay(3, function()
				Hud.splash("THE HARBOUR IS OPEN!", C.Gold)
				Hud.toast("Walk the dock to the island: shops, spells, eggs and more!", C.Deep)
			end)
		end
	end)

	RunService.RenderStepped:Connect(function()
		local snap = State.snapshot
		local t = os.clock()
		local step = if snap then snap.tutorial else 0
		local info = Config.TUTORIAL[step]
		-- Stay completely quiet (no banner, trail, arrows or tags) while you are watching a fight, away
		-- from your ship, or looking out toward the arena from the deck: the prompts only belong to
		-- the ship, and they used to sit right over the battle and its depth bar.
		-- a helper (the open Fuse tray) takes over the banner, trail and arrow while it is open; it
		-- ignores where the camera looks (you opened the tray, so you want the way shown)
		local helper = Guide.helper
		-- HUD targets (FIGHT, Fuse) point at a button, not the deck, so where the camera looks doesn't
		-- matter: the FIGHT prompt used to vanish whenever the camera faced the arena
		local hudStep = info ~= nil and (info.target == "fight" or info.target == "fuse")
		local quiet = isQuiet(helper ~= nil or hudStep)
		-- the Fuse prompt (tag + arrow) only makes sense when something CAN be fused right now
		local noFuse = info ~= nil and info.target == "fuse" and not canFuseNow(snap)
		local active = info ~= nil and not State.cinematic and not Hud.inBattle and not State.revealing and not quiet and not noFuse
		local helping = helper ~= nil and not State.cinematic and not Hud.inBattle and not State.revealing and not quiet
		-- the Fuse step shows beside the Fuse button instead of in the top banner
		local tagText: string? = nil
		if quiet then
			Hud.banner(nil)
		elseif helping and helper then
			Hud.banner(helper.text())
		elseif not info or State.cinematic then
			Hud.banner(nil)
		elseif active and info.target == "fuse" then
			Hud.banner(nil)
			tagText = (string.gsub(info.text, "{PRESS}", Platform.press()))
		elseif active then
			Hud.banner((string.gsub(info.text, "{PRESS}", Platform.press())))
		else
			Hud.banner(nil)
		end
		if step ~= lastStep then
			lastStep = step
		end
		local target = if active and info then info.target else nil
		local part = if helping and helper then helper.world() else worldTarget(target)
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
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
