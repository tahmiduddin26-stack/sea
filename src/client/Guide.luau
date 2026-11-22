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

local UI = require(script.Parent.UI)
local State = require(script.Parent.State)
local Hud = require(script.Parent.Hud)
local Sound = require(script.Parent.Sound)

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
	elseif target == "mon" then
		-- point at a monster to pick (or the partner, once one is picked)
		local ShipView = require(script.Parent.ShipView) :: any
		for _, d in ship:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("NestIndex") and d:GetAttribute("State") == "mon" and ShipView.marks[d] ~= "picked" then
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

function Guide.init(screen: ScreenGui)
	marker = buildMarker()
	guiArrow = UI.label({ Text = "▼", TextColor3 = ARROW, Size = UDim2.fromOffset(60, 60), AnchorPoint = Vector2.new(0.5, 1), Visible = false, ZIndex = 20, Parent = screen })

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
		local active = info ~= nil and not State.cinematic and not Hud.inBattle and not State.revealing
		-- the "lose the first fight" step waits for the battle to finish
		if not info or State.cinematic then
			Hud.banner(nil)
		elseif active or Hud.inBattle then
			Hud.banner(info.text)
		end
		if step ~= lastStep then
			lastStep = step
		end
		local target = if active and info then info.target else nil
		local part = worldTarget(target)
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		-- carrying an egg changes "nest" targets from the winch side; fine as is
		if part and root then
			folder.Parent = workspace
			local top = part.Position.Y + part.Size.Y / 2
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
					placeChevron(bars, CFrame.lookAt(p, p - dir))
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
		local gui = hudTarget(target)
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
			local above = target == "fuse"
			guiArrow.Rotation = if above then 0 else 180
			guiArrow.AnchorPoint = if above then Vector2.new(0.5, 1) else Vector2.new(0.5, 0)
			local bob = math.abs(math.sin(t * 4)) * 10
			guiArrow.Position = if above then UDim2.fromOffset(x, y - 4 - bob) else UDim2.fromOffset(x, y + size.Y / scale + 30 + bob)
		else
			guiArrow.Visible = false
		end
		local _ = C
	end)
end

return Guide
