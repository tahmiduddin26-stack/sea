--!strict
-- The Lighthouse Climb. Walk in through the lighthouse door and you arrive inside a HUGE old brick
-- tower (built far away at Config.LIGHTHOUSE.origin, so the inside is many times bigger than the
-- outside). Wooden stair-planks on iron brackets spiral up the wall round the stone lamp column:
-- rotten planks that drop away, barrel trampolines and swinging ship anchors, with two flag
-- checkpoints. At the top, under the great lamp: three treasure chests (Coins, Pearls, Mystery) that
-- each open once per Config.LIGHTHOUSE.chestCooldown, your climb time, and a door out.
--
-- Movement effects (anchor knock-back, barrel bounce, the anchors swinging, the lamp turning) run on
-- each player's client (client/LighthouseView): a character's physics belongs to its own client, so a
-- push set here on the server is simply overwritten. The server tags those parts with attributes.
-- Player attributes for the client: ObbyStart (server time the climb began), InLighthouse.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Stats = require(Shared.Stats)

local DataService = require(script.Parent.DataService)
local ExtrasService = require(script.Parent.ExtrasService)
local Analytics = require(script.Parent.Analytics)

local LighthouseService = {}

local L = Config.LIGHTHOUSE
local rng = Random.new()

-- an old whitewashed brick tower with red bands, wooden stairs and iron fittings
local BRICK = Color3.fromRGB(232, 222, 204)
local BRICK_RED = Color3.fromRGB(176, 52, 46)
local STONE = Color3.fromRGB(150, 146, 140)
local STONE_DARK = Color3.fromRGB(105, 100, 98)
local PLANK = Color3.fromRGB(166, 116, 70)
local PLANK_DARK = Color3.fromRGB(110, 74, 44)
local ROTTEN = Color3.fromRGB(122, 104, 78)
local IRON = Color3.fromRGB(58, 58, 64)
local BRASS = Color3.fromRGB(205, 160, 70)
local GOLD = Color3.fromRGB(255, 205, 60)
local INK = Color3.fromRGB(45, 32, 22)

local model: Model
local O: CFrame -- the inside's floor centre
local topY = 0 -- height of the top landing above the floor
local insideSpawn: CFrame
local outsideSpawn: CFrame
local checkpoints: { [Player]: CFrame } = {}
local lastPort: { [Player]: number } = {}

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.CastShadow = false -- ~2,000 parts: shadows from all of them would cost a phone dearly
	for k, v in props do
		if k ~= "Parent" then
			(p :: any)[k] = v
		end
	end
	p.Parent = (props.Parent or model) :: Instance
	return p
end

local function rootOf(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function playerFromHit(hit: BasePart): Player?
	local char = hit:FindFirstAncestorOfClass("Model")
	local p = char and Players:GetPlayerFromCharacter(char)
	if p then
		local hum = (char :: Model):FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			return p
		end
	end
	return nil
end

local function teleport(player: Player, cf: CFrame)
	local char = player.Character
	if not char then
		return
	end
	pcall(function()
		player:RequestStreamAroundAsync(cf.Position, 3)
	end)
	char:PivotTo(cf)
	local root = rootOf(player)
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

-- painted words on a wooden board (a SurfaceGui on the part's front face)
local function paint(board: BasePart, text: string, color: Color3?, face: Enum.NormalId?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.6
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(0.9, 0.84)
	l.Position = UDim2.fromScale(0.05, 0.08)
	l.Text = text
	l.TextScaled = true
	l.Font = Enum.Font.FredokaOne
	l.TextColor3 = color or Color3.fromRGB(255, 240, 210)
	local st = Instance.new("UIStroke")
	st.Thickness = 2
	st.Color = INK
	st.Parent = l
	l.Parent = gui
	gui.Parent = board
end

-- a wooden sign board with a darker frame (faces -Z of `cf`, i.e. towards whoever stands in front)
local function signBoard(cf: CFrame, size: Vector2, text: string, color: Color3?, parent: Instance?): Part
	local board = part({ Name = "Sign", Parent = parent, Size = Vector3.new(size.X, size.Y, 0.4), CFrame = cf, Color = PLANK, Material = Enum.Material.WoodPlanks })
	part({ Name = "SignFrame", Parent = parent, CanCollide = false, Size = Vector3.new(size.X + 0.5, size.Y + 0.5, 0.3), CFrame = cf * CFrame.new(0, 0, 0.15), Color = PLANK_DARK, Material = Enum.Material.Wood })
	paint(board, text, color)
	return board
end

local function lantern(cf: CFrame, parent: Instance?)
	part({ Name = "LanternCap", Parent = parent, CanCollide = false, Size = Vector3.new(1.3, 0.3, 1.3), CFrame = cf * CFrame.new(0, 0.9, 0), Color = IRON, Material = Enum.Material.Metal })
	local glass = part({ Name = "Lantern", Parent = parent, CanCollide = false, Size = Vector3.new(1, 1.4, 1), CFrame = cf, Color = Color3.fromRGB(255, 196, 110), Material = Enum.Material.Neon, Transparency = 0.15 })
	part({ Name = "LanternBase", Parent = parent, CanCollide = false, Size = Vector3.new(1.2, 0.3, 1.2), CFrame = cf * CFrame.new(0, -0.85, 0), Color = IRON, Material = Enum.Material.Metal })
	local pl = Instance.new("PointLight")
	pl.Range = 22
	pl.Brightness = 1.1
	pl.Color = Color3.fromRGB(255, 196, 130)
	pl.Shadows = false
	pl.Parent = glass
end

---------------------------------------------------------------------------
-- Going in and out
---------------------------------------------------------------------------
local function enter(player: Player)
	local now = os.clock()
	if now - (lastPort[player] or 0) < 2 then
		return
	end
	lastPort[player] = now
	local Drip = require(script.Parent.DripService)
	if not Drip.open(player, "lighthouse") then
		Remotes.event("Toast"):FireClient(player, Drip.waitText(player, "lighthouse"), Color3.fromRGB(255, 205, 60))
		return
	end
	checkpoints[player] = nil
	player:SetAttribute("InLighthouse", true)
	player:SetAttribute("ObbyStart", nil)
	teleport(player, insideSpawn)
end

local function leave(player: Player)
	local now = os.clock()
	if now - (lastPort[player] or 0) < 2 then
		return
	end
	lastPort[player] = now
	checkpoints[player] = nil
	player:SetAttribute("InLighthouse", nil)
	player:SetAttribute("ObbyStart", nil)
	teleport(player, outsideSpawn)
end

-- the Leave button on the climb screen: out through the door from anywhere inside, no matter where you
-- are on the stairs (falling only ever puts you back on a checkpoint, never outside)
function LighthouseService.leaveClimb(player: Player)
	if player:GetAttribute("InLighthouse") then
		lastPort[player] = nil -- (the 2 s guard is for the door trigger, not for a button press)
		leave(player)
	end
end

-- the climb timer starts on the first stair (not while you look round the floor)
local function startClimb(player: Player)
	if player:GetAttribute("InLighthouse") and not player:GetAttribute("ObbyStart") then
		player:SetAttribute("ObbyStart", workspace:GetServerTimeNow())
	end
end

local function finishClimb(player: Player)
	local start = player:GetAttribute("ObbyStart") :: number?
	if not start then
		return
	end
	player:SetAttribute("ObbyStart", nil)
	local secs = workspace:GetServerTimeNow() - start
	local data = DataService.get(player)
	if not data then
		return
	end
	local best = data.obbyBest :: number?
	local text = "You reached the top in " .. string.format("%.1f", secs) .. "s!"
	if not best or secs < best then
		data.obbyBest = secs
		DataService.changed(player)
		text ..= if best then " NEW BEST!" else ""
	end
	Remotes.event("Toast"):FireClient(player, text, GOLD)
	Analytics.event(player, "LighthouseClimb", math.floor(secs), {})
end

---------------------------------------------------------------------------
-- Treasure chests
---------------------------------------------------------------------------
local CHESTS = {
	{ id = "Coins", name = "Coin Chest", trim = GOLD },
	{ id = "Pearls", name = "Pearl Chest", trim = Color3.fromRGB(170, 215, 240) },
	{ id = "Mystery", name = "Mystery Chest", trim = Color3.fromRGB(175, 110, 235) },
}

local function openChest(player: Player, id: string, lid: Model, hinge: CFrame)
	local data = DataService.get(player)
	if not data then
		return
	end
	data.obbyAt = data.obbyAt or {}
	local ready = (data.obbyAt[id] or 0) + L.chestCooldown
	if os.time() < ready then
		Remotes.event("Toast"):FireClient(player, "This chest refills in " .. Format.time(ready - os.time()), Color3.fromRGB(240, 60, 70))
		return
	end
	data.obbyAt[id] = os.time()
	local prize = ""
	if id == "Coins" then
		local coins = math.max(1, math.floor(Stats.coinsPerMinute(data.bestDepth) * L.coinMinutes))
		data.coins += coins
		prize = Format.abbrev(coins) .. " coins!"
	elseif id == "Pearls" then
		local n = rng:NextInteger(L.pearls[1], L.pearls[2])
		data.pearls += n
		prize = n .. " pearls!"
	else
		if rng:NextNumber() < L.eggChance and ExtrasService.giveRandomEgg(player, nil, 0, 1) then
			prize = "a MONSTER EGG!"
			Remotes.event("Announce"):FireAllClients(player.DisplayName .. " found a MONSTER EGG at the top of the Lighthouse!", GOLD)
		else
			local sp = ExtrasService.giveSpell(player, "boss")
			prize = if sp then "a " .. sp.name .. " spell card!" else "a surprise!"
		end
	end
	DataService.changed(player)
	Analytics.event(player, "LighthouseChest", 1, { chest = id })
	require(script.Parent.MissionService).record(player, "lighthouse", 1)
	Remotes.event("Toast"):FireClient(player, "You opened the " .. id .. " chest: " .. prize, GOLD)
	-- the lid swings open on its hinge, then closes again
	local holder = Instance.new("CFrameValue")
	holder.Value = hinge
	local rest: { [BasePart]: CFrame } = {}
	for _, p in lid:GetChildren() do
		if p:IsA("BasePart") then
			rest[p] = hinge:ToObjectSpace(p.CFrame)
		end
	end
	local conn = holder.Changed:Connect(function(cf)
		for p, off in rest do
			p.CFrame = cf * off
		end
	end)
	TweenService:Create(holder, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Value = hinge * CFrame.Angles(math.rad(75), 0, 0) }):Play()
	task.delay(2.2, function()
		local t = TweenService:Create(holder, TweenInfo.new(0.4), { Value = hinge })
		t:Play()
		t.Completed:Wait()
		conn:Disconnect()
		holder:Destroy()
	end)
end

local function buildChest(c: any, base: CFrame)
	-- base: on the floor, facing -Z (the chest's front)
	local chest = Instance.new("Model")
	chest.Name = c.id .. "Chest"
	chest.Parent = model
	local W, D, H = 5, 3.2, 2.6
	local body = part({ Name = "Body", Parent = chest, Size = Vector3.new(W, H, D), CFrame = base * CFrame.new(0, H / 2, 0), Color = PLANK_DARK, Material = Enum.Material.WoodPlanks })
	for _, x in { -1.6, 1.6 } do
		part({ Name = "Strap", Parent = chest, CanCollide = false, Size = Vector3.new(0.45, H + 0.05, D + 0.1), CFrame = body.CFrame * CFrame.new(x, 0, 0), Color = c.trim, Material = Enum.Material.Metal })
	end
	part({ Name = "Rim", Parent = chest, CanCollide = false, Size = Vector3.new(W + 0.1, 0.3, D + 0.1), CFrame = body.CFrame * CFrame.new(0, H / 2 - 0.15, 0), Color = c.trim, Material = Enum.Material.Metal })
	-- treasure peeking out (shows when the lid opens)
	part({ Name = "Loot", Parent = chest, CanCollide = false, Size = Vector3.new(W - 0.6, 0.4, D - 0.6), CFrame = body.CFrame * CFrame.new(0, H / 2 - 0.1, 0), Color = c.trim, Material = Enum.Material.Neon })
	-- the rounded lid: a half-buried cylinder, hinged along the back edge
	local hinge = body.CFrame * CFrame.new(0, H / 2, D / 2)
	local lid = Instance.new("Model")
	lid.Name = "Lid"
	lid.Parent = chest
	part({ Name = "LidTop", Parent = lid, Shape = Enum.PartType.Cylinder, Size = Vector3.new(W, D, D), CFrame = body.CFrame * CFrame.new(0, H / 2, 0) * CFrame.Angles(0, 0, 0) * CFrame.fromAxisAngle(Vector3.zAxis, 0), Color = PLANK, Material = Enum.Material.WoodPlanks })
	for _, x in { -1.6, 1.6 } do
		part({ Name = "LidStrap", Parent = lid, CanCollide = false, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.45, D + 0.1, D + 0.1), CFrame = body.CFrame * CFrame.new(x, H / 2, 0), Color = c.trim, Material = Enum.Material.Metal })
	end
	part({ Name = "Lock", Parent = lid, CanCollide = false, Size = Vector3.new(0.8, 1, 0.3), CFrame = body.CFrame * CFrame.new(0, H / 2 - 0.2, -D / 2 - 0.1), Color = c.trim, Material = Enum.Material.Metal })
	-- its name on a board on a post behind it
	signBoard(base * CFrame.new(0, 5, D / 2 + 0.8), Vector2.new(4.6, 1.3), string.upper(c.name), c.trim)
	part({ Name = "SignPost", Parent = chest, Size = Vector3.new(0.4, 4.4, 0.4), CFrame = base * CFrame.new(0, 2.2, D / 2 + 1), Color = PLANK_DARK, Material = Enum.Material.Wood })
	body:SetAttribute("ChestId", c.id)
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "LighthouseChest"
	pp.ActionText = "Open"
	pp.ObjectText = c.name
	pp.HoldDuration = 0.6
	pp.MaxActivationDistance = 10
	pp.RequiresLineOfSight = false
	pp.Parent = body
	pp.Triggered:Connect(function(who)
		openChest(who, c.id, lid, hinge)
	end)
end

---------------------------------------------------------------------------
-- The inside
---------------------------------------------------------------------------
-- a ship's anchor hanging on a chain from a beam in the wall. The client swings it (attributes:
-- Pivot = the chain's top, Axis = swing axis, Phase) and knocks you off the stair if it hits you.
local function swingingAnchor(stairCf: CFrame, R: number, stepR: number, phase: number)
	local m = Instance.new("Model")
	m.Name = "SwingAnchor"
	m.Parent = model
	local pivot = stairCf * CFrame.new(0, 10, 0)
	-- the beam it hangs from, out of the wall
	part({ Name = "Beam", Parent = model, Size = Vector3.new(1.2, 1.2, R - stepR + 1.5), CFrame = pivot * CFrame.new(0, 0.8, (R - stepR) / 2), Color = PLANK_DARK, Material = Enum.Material.Wood })
	local function piece(name: string, size: Vector3, off: CFrame, color: Color3, shape: Enum.PartType?)
		local p = part({ Name = name, Parent = m, CanCollide = false, Size = size, CFrame = pivot * off, Color = color, Material = Enum.Material.Metal, Shape = shape or Enum.PartType.Block })
		p:SetAttribute("Offset", off)
		return p
	end
	-- chain: a few links
	for k = 0, 3 do
		local link = piece("Link", Vector3.new(0.25, 1.1, 0.6), CFrame.new(0, -0.6 - k * 0.95, 0) * CFrame.Angles(0, if k % 2 == 0 then 0 else math.pi / 2, 0), IRON)
		link:SetAttribute("Hits", false)
	end
	piece("Ring", Vector3.new(0.3, 1.2, 1.2), CFrame.new(0, -4.5, 0) * CFrame.Angles(0, 0, math.rad(90)), IRON, Enum.PartType.Cylinder)
	piece("Stock", Vector3.new(4.4, 0.5, 0.5), CFrame.new(0, -5.2, 0), IRON)
	piece("Shank", Vector3.new(0.7, 5.2, 0.7), CFrame.new(0, -7.6, 0), IRON)
	-- the curved arms: two angled bars meeting at the crown, each ending in a spade fluke
	piece("ArmL", Vector3.new(0.6, 3.2, 0.6), CFrame.new(0, -9.4, 0) * CFrame.Angles(math.rad(-55), 0, 0) * CFrame.new(0, 1.3, 0), IRON)
	piece("ArmR", Vector3.new(0.6, 3.2, 0.6), CFrame.new(0, -9.4, 0) * CFrame.Angles(math.rad(55), 0, 0) * CFrame.new(0, 1.3, 0), IRON)
	piece("FlukeL", Vector3.new(0.4, 1.3, 1.4), CFrame.new(0, -8.2, -2.4) * CFrame.Angles(math.rad(-35), 0, 0), IRON)
	piece("FlukeR", Vector3.new(0.4, 1.3, 1.4), CFrame.new(0, -8.2, 2.4) * CFrame.Angles(math.rad(35), 0, 0), IRON)
	piece("Crown", Vector3.new(1, 1, 1), CFrame.new(0, -9.6, 0), IRON, Enum.PartType.Ball)
	m:SetAttribute("Pivot", pivot)
	m:SetAttribute("Phase", phase)
	m:SetAttribute("Swing", 65)
end

local function build()
	model = Instance.new("Model")
	model.Name = "LighthouseInside"
	model.Parent = workspace
	O = CFrame.new(L.origin)
	local R = L.radius
	local steps = L.steps
	-- barrels throw you up to a higher stair
	local heights = {}
	local y = 3
	for i = 1, steps do
		y += L.stepRise + (if i > 1 and (i - 1) % 9 == 0 then 8 else 0)
		heights[i] = y
	end
	topY = y + L.stepRise + 1
	local H = topY + 30

	-- floor: big stone flags with a compass rose in the middle
	part({ Name = "Floor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, R * 2 + 4, R * 2 + 4), CFrame = O * CFrame.new(0, -1, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = STONE, Material = Enum.Material.Slate })
	for k = 0, 3 do
		part({ Name = "Rose", CanCollide = false, Size = Vector3.new(2.4, 0.1, 26), CFrame = O * CFrame.new(0, 0.02, 0) * CFrame.Angles(0, k * math.pi / 4, 0), Color = if k % 2 == 0 then Color3.fromRGB(40, 60, 110) else BRASS, Material = Enum.Material.Slate })
	end
	part({ Name = "RoseRing", CanCollide = false, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 15, 15), CFrame = O * CFrame.new(0, 0.03, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(200, 190, 170), Material = Enum.Material.Slate })

	-- the wall: whitewashed brick with thin red bands, arched windows to the sky
	local SEG = 28
	local w = 2 * math.pi * (R + 1) / SEG + 0.5
	local band = 5
	local rows = math.ceil(H / band)
	for row = 0, rows - 1 do
		local red = row % 6 == 3
		for s = 0, SEG - 1 do
			local a = s / SEG * math.pi * 2
			local cy = row * band + band / 2
			-- a window: every 7th column, in a few rows
			local win = (s % 7 == (row // 6) % 7) and row % 6 == 5 and row > 2 and row < rows - 4
			if win then
				local cf = O * CFrame.Angles(0, a, 0) * CFrame.new(0, cy, R + 1)
				part({ Name = "Window", Size = Vector3.new(w - 0.6, band - 0.4, 0.3), CFrame = cf, Color = Color3.fromRGB(170, 215, 240), Material = Enum.Material.Glass, Transparency = 0.45 })
				part({ Name = "WindowSill", Size = Vector3.new(w, 0.5, 2.4), CFrame = cf * CFrame.new(0, -band / 2 + 0.25, -0.4), Color = STONE, Material = Enum.Material.Slate })
				part({ Name = "WindowBar", CanCollide = false, Size = Vector3.new(0.25, band - 0.4, 0.4), CFrame = cf, Color = PLANK_DARK, Material = Enum.Material.Wood })
			else
				part({ Name = "Wall", Size = Vector3.new(w, band, 2), CFrame = O * CFrame.Angles(0, a, 0) * CFrame.new(0, cy, R + 1), Color = if red then BRICK_RED else BRICK, Material = Enum.Material.Brick })
			end
		end
	end
	-- ceiling with dark beams
	part({ Name = "Ceiling", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, R * 2 + 4, R * 2 + 4), CFrame = O * CFrame.new(0, H + 1, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = PLANK, Material = Enum.Material.WoodPlanks })
	for k = 0, 5 do
		part({ Name = "CeilingBeam", Size = Vector3.new(1.6, 1.6, R * 2), CFrame = O * CFrame.new(0, H - 0.8, 0) * CFrame.Angles(0, k * math.pi / 6, 0), Color = PLANK_DARK, Material = Enum.Material.Wood })
	end

	-- the stone lamp column up the middle
	part({ Name = "Column", Shape = Enum.PartType.Cylinder, Size = Vector3.new(topY, 9, 9), CFrame = O * CFrame.new(0, topY / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = STONE, Material = Enum.Material.Cobblestone })

	-- the great lamp on top: brass base, glass cage, glowing core, two beams that sweep round
	local lampY = topY + 0.7
	part({ Name = "LampBase", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 11, 11), CFrame = O * CFrame.new(0, lampY + 1, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = BRASS, Material = Enum.Material.Metal })
	part({ Name = "LampGlass", CanCollide = false, Shape = Enum.PartType.Cylinder, Size = Vector3.new(8, 9, 9), CFrame = O * CFrame.new(0, lampY + 6, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(255, 245, 220), Material = Enum.Material.Glass, Transparency = 0.6 })
	for k = 0, 5 do
		part({ Name = "LampBar", CanCollide = false, Size = Vector3.new(0.3, 8, 0.3), CFrame = O * CFrame.Angles(0, k * math.pi / 3, 0) * CFrame.new(0, lampY + 6, 4.5), Color = BRASS, Material = Enum.Material.Metal })
	end
	part({ Name = "LampRoof", CanCollide = false, Shape = Enum.PartType.Ball, Size = Vector3.new(10, 5, 10), CFrame = O * CFrame.new(0, lampY + 10.2, 0), Color = BRICK_RED, Material = Enum.Material.Metal })
	local core = part({ Name = "LampCore", CanCollide = false, Shape = Enum.PartType.Ball, Size = Vector3.new(4.5, 4.5, 4.5), CFrame = O * CFrame.new(0, lampY + 6, 0), Color = Color3.fromRGB(255, 236, 170), Material = Enum.Material.Neon })
	local glow = Instance.new("PointLight")
	glow.Range = 60
	glow.Brightness = 2.2
	glow.Color = Color3.fromRGB(255, 225, 150)
	glow.Parent = core
	for k = 0, 1 do
		local beam = part({ Name = "LampBeam", CanCollide = false, CastShadow = false, Size = Vector3.new(3, 3, R - 8), CFrame = O * CFrame.new(0, lampY + 6, 0) * CFrame.Angles(0, k * math.pi, 0) * CFrame.new(0, 0, (R - 8) / 2), Color = Color3.fromRGB(255, 240, 180), Material = Enum.Material.Neon, Transparency = 0.82 })
		beam:SetAttribute("LampBeam", k)
		beam:SetAttribute("Center", O * CFrame.new(0, lampY + 6, 0))
	end

	-- lanterns on the wall all the way up, so the climb is warm and lit
	for k = 0, math.floor(topY / 22) do
		local a = k * 2.4 + 0.5
		lantern(O * CFrame.Angles(0, a, 0) * CFrame.new(0, 8 + k * 22, R - 0.8))
	end

	-- the climb: wooden stair-planks on iron brackets
	local stepR = R - 14
	for i = 1, steps do
		local a = math.rad(i * L.stepAngle)
		local cf = O * CFrame.Angles(0, a, 0) * CFrame.new(0, heights[i], stepR)
		local kind = if i % 9 == 0 then "barrel" elseif i % 6 == 3 then "rotten" elseif i % 7 == 5 then "anchor" else "plank"
		if i == 12 or i == 24 then
			kind = "check"
		end
		local plank = part({ Name = "Step" .. i, Size = Vector3.new(11, 1, 7), CFrame = cf, Color = if kind == "rotten" then ROTTEN elseif kind == "check" then Color3.fromRGB(190, 140, 80) else PLANK, Material = if kind == "rotten" then Enum.Material.Wood else Enum.Material.WoodPlanks })
		-- iron brackets from the wall under the plank
		for _, x in { -3.8, 3.8 } do
			part({ Name = "Bracket", CanCollide = false, Size = Vector3.new(0.4, 0.4, 15), CFrame = cf * CFrame.new(x, -2.4, 7.2) * CFrame.Angles(math.rad(-14), 0, 0), Color = IRON, Material = Enum.Material.Metal })
			part({ Name = "BracketTop", CanCollide = false, Size = Vector3.new(0.4, 0.3, 7), CFrame = cf * CFrame.new(x, -0.65, 0), Color = IRON, Material = Enum.Material.Metal })
		end
		if i == 1 then
			signBoard(O * CFrame.Angles(0, a, 0) * CFrame.new(0, 8, R - 0.6), Vector2.new(7, 2), "START CLIMB  ↑")
			plank.Touched:Connect(function(hit)
				local p = playerFromHit(hit)
				if p then
					startClimb(p)
				end
			end)
		end
		if kind == "rotten" then
			-- an old cracked plank: it creaks, drops away under you, and is back a few seconds later
			for _, x in { -2.6, 1.9 } do
				part({ Name = "Crack", CanCollide = false, Size = Vector3.new(0.2, 0.05, 5), CFrame = cf * CFrame.new(x, 0.52, 0) * CFrame.Angles(0, math.rad(12), 0), Color = Color3.fromRGB(60, 45, 30) })
			end
			plank:SetAttribute("Rotten", true)
			local busy = false
			local rest = plank.CFrame
			plank.Touched:Connect(function(hit)
				if busy or not playerFromHit(hit) then
					return
				end
				busy = true
				for k = 1, 6 do
					plank.CFrame = rest * CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.rad(if k % 2 == 0 then 2 else -2))
					task.wait(0.08)
				end
				plank.CanCollide = false
				TweenService:Create(plank, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = rest * CFrame.new(0, -8, 0) * CFrame.Angles(math.rad(25), 0, 0), Transparency = 1 }):Play()
				task.wait(3)
				plank.CFrame = rest
				plank.Transparency = 0
				plank.CanCollide = true
				busy = false
			end)
		elseif kind == "barrel" then
			-- a barrel with a tight canvas top: jump on it to bounce up to the next (higher) stair
			local bcf = cf * CFrame.new(0, 0.5 + 1.4, 0)
			part({ Name = "Barrel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.8, 4.4, 4.4), CFrame = bcf * CFrame.Angles(0, 0, math.rad(90)), Color = PLANK, Material = Enum.Material.WoodPlanks })
			for _, hy in { -0.9, 0.9 } do
				part({ Name = "Hoop", CanCollide = false, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 4.55, 4.55), CFrame = bcf * CFrame.new(0, hy, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = IRON, Material = Enum.Material.Metal })
			end
			local top = part({ Name = "BounceTop", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 4.2, 4.2), CFrame = bcf * CFrame.new(0, 1.5, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(95, 200, 110), Material = Enum.Material.Fabric })
			local nextCf = O * CFrame.Angles(0, math.rad((i + 1) * L.stepAngle), 0) * CFrame.new(0, heights[math.min(steps, i + 1)], stepR)
			top:SetAttribute("Bounce", nextCf.Position)
			signBoard(cf * CFrame.new(0, 4.6, 3.2), Vector2.new(3.6, 1.1), "BOUNCE!", Color3.fromRGB(140, 240, 150))
		elseif kind == "anchor" then
			swingingAnchor(cf, R, stepR, i)
		elseif kind == "check" then
			-- a pirate flag on a pole
			local pole = part({ Name = "FlagPole", CanCollide = false, Size = Vector3.new(0.35, 8, 0.35), CFrame = cf * CFrame.new(4.6, 4.5, 2.6), Color = PLANK_DARK, Material = Enum.Material.Wood })
			part({ Name = "Flag", CanCollide = false, Size = Vector3.new(0.1, 2.4, 3.6), CFrame = pole.CFrame * CFrame.new(0, 2.6, -1.85), Color = Color3.fromRGB(30, 30, 36), Material = Enum.Material.Fabric })
			part({ Name = "FlagSkull", CanCollide = false, Shape = Enum.PartType.Ball, Size = Vector3.new(0.12, 1, 1), CFrame = pole.CFrame * CFrame.new(0.06, 2.7, -1.85), Color = Color3.fromRGB(240, 240, 235) })
			signBoard(cf * CFrame.new(0, 3.2, 3.4), Vector2.new(4.6, 1.2), "CHECKPOINT", GOLD)
			plank.Touched:Connect(function(hit)
				local p = playerFromHit(hit)
				if p and p:GetAttribute("InLighthouse") and checkpoints[p] ~= cf * CFrame.new(0, 4, 0) then
					checkpoints[p] = cf * CFrame.new(0, 4, 0)
					Remotes.event("Toast"):FireClient(p, "Checkpoint! Fall and you come back here.", GOLD)
				end
			end)
		end
	end

	-- the top: a wooden gallery round the lamp, with a railing (open where the stairs arrive)
	local landR = stepR - 5
	local arrive = math.rad((steps * L.stepAngle) % 360)
	part({ Name = "TopLanding", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, landR * 2, landR * 2), CFrame = O * CFrame.new(0, topY, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = PLANK, Material = Enum.Material.WoodPlanks })
	local finish = part({ Name = "FinishTrigger", CanCollide = false, Transparency = 1, Size = Vector3.new(landR * 2, 6, landR * 2), CFrame = O * CFrame.new(0, topY + 3.5, 0) })
	finish.Touched:Connect(function(hit)
		local p = playerFromHit(hit)
		if p then
			finishClimb(p)
		end
	end)
	local POSTS = 32
	for k = 0, POSTS - 1 do
		local a = k / POSTS * math.pi * 2
		local off = math.abs((a - arrive + math.pi) % (math.pi * 2) - math.pi)
		if off < math.rad(26) then
			continue
		end
		local pcf = O * CFrame.Angles(0, a, 0) * CFrame.new(0, topY + 2.3, landR - 0.5)
		part({ Name = "RailPost", Size = Vector3.new(0.4, 3.2, 0.4), CFrame = pcf, Color = IRON, Material = Enum.Material.Metal })
		local seg = 2 * math.pi * (landR - 0.5) / POSTS
		part({ Name = "Rail", CanCollide = false, Size = Vector3.new(seg + 0.3, 0.3, 0.3), CFrame = O * CFrame.Angles(0, a + math.pi / POSTS, 0) * CFrame.new(0, topY + 3.8, landR - 0.5), Color = IRON, Material = Enum.Material.Metal })
	end

	for k, c in CHESTS do
		local a = arrive + math.rad(20 + k * 70) -- 90 / 160 / 230 degrees round from the stairs; the door is at 290
		buildChest(c, O * CFrame.Angles(0, a, 0) * CFrame.new(0, topY + 0.7, landR - 7)) -- front (-Z) faces the lamp
	end

	-- the way out: a wooden door set in an arched stone frame, with a sign. Walk into it.
	local function exitDoor(cf: CFrame)
		-- cf: on the floor in front of the door, facing the door (-Z = into the door)
		local doorCf = cf * CFrame.new(0, 3.8, -1)
		part({ Name = "ExitDoor", Size = Vector3.new(5, 7.6, 0.6), CFrame = doorCf, Color = PLANK_DARK, Material = Enum.Material.WoodPlanks })
		for _, x in { -3, 3 } do
			part({ Name = "DoorFrame", Size = Vector3.new(1, 8.6, 1.2), CFrame = doorCf * CFrame.new(x, 0.5, 0.2), Color = STONE_DARK, Material = Enum.Material.Slate })
		end
		part({ Name = "DoorLintel", Size = Vector3.new(7, 1.1, 1.2), CFrame = doorCf * CFrame.new(0, 4.6, 0.2), Color = STONE_DARK, Material = Enum.Material.Slate })
		part({ Name = "DoorRing", CanCollide = false, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.15, 0.9, 0.9), CFrame = doorCf * CFrame.new(1.6, -0.3, 0.38) * CFrame.Angles(0, math.rad(90), 0), Color = IRON, Material = Enum.Material.Metal })
		signBoard(doorCf * CFrame.new(0, 6, 0.6) * CFrame.Angles(0, math.pi, 0), Vector2.new(4, 1.3), "EXIT")
		lantern(doorCf * CFrame.new(-4.3, 2.4, 0.9))
		local trig = part({ Name = "ExitTrigger", CanCollide = false, Transparency = 1, Size = Vector3.new(5, 7, 2.4), CFrame = doorCf * CFrame.new(0, 0, 1.4) })
		trig.Touched:Connect(function(hit)
			local p = playerFromHit(hit)
			if p then
				leave(p)
			end
		end)
	end
	exitDoor(O * CFrame.Angles(0, arrive + math.rad(290), 0) * CFrame.new(0, topY + 0.7, landR - 2.5) * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, 0, 1.2))
	exitDoor(O * CFrame.new(0, 0, R - 0.4) * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, 0, 1.2))

	-- far enough from the wall that the camera behind you isn't inside it, facing the column
	insideSpawn = O * CFrame.new(0, 4, R - 22)
	signBoard(O * CFrame.new(-11, 5, R - 30) * CFrame.Angles(0, math.rad(200), 0), Vector2.new(8, 3.2), "LIGHTHOUSE CLIMB\nTreasure at the top!", GOLD)
	part({ Name = "SignPost", Size = Vector3.new(0.6, 3.5, 0.6), CFrame = O * CFrame.new(-11, 1.75, R - 30), Color = PLANK_DARK, Material = Enum.Material.Wood })

	-- a lived-in floor: crates, barrels, rope and a little boat by the wall
	local props = {
		{ a = 200, kind = "crate" }, { a = 214, kind = "crate2" }, { a = 232, kind = "barrel" },
		{ a = 120, kind = "rope" }, { a = 135, kind = "barrel" }, { a = 300, kind = "boat" }, { a = 60, kind = "crate" },
	}
	for _, pr in props do
		local cf = O * CFrame.Angles(0, math.rad(pr.a), 0) * CFrame.new(0, 0, R - 5)
		if pr.kind == "crate" then
			part({ Name = "Crate", Size = Vector3.new(4, 4, 4), CFrame = cf * CFrame.new(0, 2, 0) * CFrame.Angles(0, 0.3, 0), Color = PLANK, Material = Enum.Material.WoodPlanks })
		elseif pr.kind == "crate2" then
			part({ Name = "Crate", Size = Vector3.new(3, 3, 3), CFrame = cf * CFrame.new(0, 1.5, 0) * CFrame.Angles(0, -0.4, 0), Color = PLANK, Material = Enum.Material.WoodPlanks })
			part({ Name = "Crate", Size = Vector3.new(2.6, 2.6, 2.6), CFrame = cf * CFrame.new(0.2, 4.3, 0) * CFrame.Angles(0, 0.2, 0), Color = PLANK_DARK, Material = Enum.Material.WoodPlanks })
		elseif pr.kind == "barrel" then
			part({ Name = "Barrel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.6, 3, 3), CFrame = cf * CFrame.new(0, 1.8, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = PLANK, Material = Enum.Material.WoodPlanks })
		elseif pr.kind == "rope" then
			for k = 0, 2 do
				part({ Name = "Rope", CanCollide = false, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 3.6 - k * 0.5, 3.6 - k * 0.5), CFrame = cf * CFrame.new(0, 0.3 + k * 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(200, 170, 120), Material = Enum.Material.Fabric })
			end
		elseif pr.kind == "boat" then
			part({ Name = "Boat", Size = Vector3.new(4, 1.8, 10), CFrame = cf * CFrame.new(0, 0.9, 0) * CFrame.Angles(0, math.rad(90), math.rad(8)), Color = Color3.fromRGB(70, 120, 170), Material = Enum.Material.WoodPlanks })
			part({ Name = "Oar", CanCollide = false, Size = Vector3.new(0.3, 0.3, 7), CFrame = cf * CFrame.new(1, 2.2, 0) * CFrame.Angles(0, math.rad(80), 0), Color = PLANK, Material = Enum.Material.Wood })
		end
	end

	-- falling to the floor puts you back on your last checkpoint (the floor itself is safe)
	local floorTrig = part({ Name = "FallTrigger", CanCollide = false, Transparency = 1, Size = Vector3.new(R * 2, 2, R * 2), CFrame = O * CFrame.new(0, 1.2, 0) })
	floorTrig.Touched:Connect(function(hit)
		local p = playerFromHit(hit)
		local cp = p and checkpoints[p]
		if p and cp then
			teleport(p, cp)
		end
	end)
end

-- the outside: lanterns either side of the big door, a plank sign over it, and the walk-in trigger
local function dressDoor(door: BasePart)
	local world = workspace:FindFirstChild("World") :: Instance
	-- the door part's -Z looks into the tower, so the sign is turned round to face outwards
	signBoard(door.CFrame * CFrame.new(0, 5.4, 0.7) * CFrame.Angles(0, math.pi, 0), Vector2.new(6.6, 1.6), "LIGHTHOUSE CLIMB", GOLD, world)
	for _, x in { -3.9, 3.9 } do
		lantern(door.CFrame * CFrame.new(x, 1.6, 0.7), world)
	end
	local glow = Instance.new("PointLight")
	glow.Range = 10
	glow.Brightness = 0.8
	glow.Color = Color3.fromRGB(255, 190, 120)
	glow.Parent = door
end

function LighthouseService.init()
	build()
	local world = workspace:WaitForChild("World")
	local door = world:FindFirstChild("LighthouseDoor", true) :: BasePart?
	if not door then
		warn("[Lighthouse] no LighthouseDoor")
		return
	end
	dressDoor(door)
	outsideSpawn = door.CFrame * CFrame.new(0, 0, 8) * CFrame.Angles(0, math.pi, 0)
	-- walk into the dark doorway to go in
	local trigger = part({ Name = "LighthouseEnter", Parent = world, CanCollide = false, Transparency = 1, Size = Vector3.new(4.4, 6, 2), CFrame = door.CFrame * CFrame.new(0, 0, 1) })
	trigger.Touched:Connect(function(hit)
		local p = playerFromHit(hit)
		if p then
			enter(p)
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		checkpoints[p] = nil
		lastPort[p] = nil
	end)
	-- left some other way (a respawn, a teleport): forget the climb
	task.spawn(function()
		while true do
			task.wait(1)
			for _, p in Players:GetPlayers() do
				if p:GetAttribute("InLighthouse") then
					local root = rootOf(p)
					if not root or (root.Position - O.Position).Magnitude > L.radius * 6 then
						p:SetAttribute("InLighthouse", nil)
						p:SetAttribute("ObbyStart", nil)
						checkpoints[p] = nil
					end
				end
			end
		end
	end)
end

return LighthouseService
