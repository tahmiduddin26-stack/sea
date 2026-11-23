--!strict
-- Builds the whole map in code from Config numbers: the ocean (terrain water), the
-- harbour island with its lighthouse and docks, and SHIP_COUNT pirate ships. Each ship has
-- shell nests, an egg winch, egg pedestals, upgrade boards, a raised quarterdeck (Floor 2)
-- and a blue hole battle arena (ArenaBuilder) off its starboard side, with a lookout pier.
-- Rojo never wipes any of this because it lives only at runtime.

local Lighting = game:GetService("Lighting")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local Npc = require(ReplicatedStorage.Shared.Npc)
local ArenaBuilder = require(script.Parent.ArenaBuilder)

local WorldBuilder = {}

export type Ship = {
	index: number,
	cf: CFrame, -- ship origin at sea level, -Z = bow (towards the harbour)
	model: Model,
	nests: { BasePart }, -- nest pads, in Config.NEST_SLOTS order
	winch: BasePart,
	deepWinch: BasePart, -- the Deep Rod's hit box (DeepRodPrompt, DeepSign)
	abyssWinch: BasePart, -- the Abyss Rod's hit box on the Floor 3 balcony (AbyssRodPrompt, AbyssSign)
	pedestals: { BasePart },
	boards: { [string]: BasePart }, -- Floor (the rest of the upgrades are bought at the town's Dockyard)
	arenaCf: CFrame, -- arena centre at the water surface, -Z faces the enemy side
	spawnCf: CFrame,
	sign: BillboardGui,
	quarterBarrier: BasePart,
	floor3Barrier: BasePart, -- the gate at the foot of the stairs to Floor 3
	tierShown: number, -- Shipwright tier currently drawn on the ship (-1 = none yet)
}

WorldBuilder.ships = {} :: { Ship }
WorldBuilder.leaderboardFace = nil :: BasePart?
WorldBuilder.hubCenter = Vector3.new(0, Config.SEA_LEVEL, 0)

local WOOD = Color3.fromRGB(150, 96, 56)
local WOOD_DARK = Color3.fromRGB(105, 64, 38)
local WOOD_LIGHT = Color3.fromRGB(196, 140, 86)
local SAND = Color3.fromRGB(240, 214, 150)
local GRASS = Color3.fromRGB(110, 200, 90)
local SAIL = Color3.fromRGB(250, 246, 232)
local ROPE = Color3.fromRGB(205, 175, 120)

local function part(props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		if k ~= "Parent" then
			(p :: any)[k] = v
		end
	end
	p.Parent = props.Parent
	return p
end

-- a box placed by its centre in a local frame
local function box(parent: Instance, frame: CFrame, size: Vector3, pos: Vector3, color: Color3, mat: Enum.Material?, extra: { [string]: any }?): BasePart
	local props: { [string]: any } = { Size = size, CFrame = frame * CFrame.new(pos), Color = color, Material = mat or Enum.Material.SmoothPlastic, Parent = parent }
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return part(props)
end

local function label(parent: Instance, text: string, size: UDim2, offset: Vector3, color: Color3?): BillboardGui
	local bb = Instance.new("BillboardGui")
	-- sized in studs (22 px per stud) so it shrinks with distance like a real sign
	bb.Size = UDim2.fromScale(size.X.Offset / 22, size.Y.Offset / 22)
	bb.StudsOffset = offset
	bb.LightInfluence = 0
	bb.MaxDistance = 45 -- signs on a ship show only when you are near them
	bb.Parent = parent
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.Text = text
	t.TextColor3 = color or Color3.new(1, 1, 1)
	t.Parent = bb
	local st = Instance.new("UIStroke")
	st.Thickness = 3
	st.Color = Color3.fromRGB(16, 22, 44)
	st.Parent = t
	return bb
end

---------------------------------------------------------------------------
-- Ocean
---------------------------------------------------------------------------
local function buildOcean()
	local terrain = workspace.Terrain
	terrain.WaterColor = Config.WATER.color
	terrain.WaterTransparency = Config.WATER.transparency
	terrain.WaterWaveSize = 0.12
	terrain.WaterWaveSpeed = 8
	terrain.WaterReflectance = Config.WATER.reflectance
	local half = 640
	local step = 256
	local top = Config.SEA_LEVEL
	for x = -half, half - 1, step do
		for z = -half, half - 1, step do
			terrain:FillBlock(CFrame.new(x + step / 2, top - 14, z + step / 2), Vector3.new(step, 28, step), Enum.Material.Water)
			terrain:FillBlock(CFrame.new(x + step / 2, top - 32, z + step / 2), Vector3.new(step, 8, step), Enum.Material.Sand)
		end
		task.wait()
	end
end

---------------------------------------------------------------------------
-- Harbour island
---------------------------------------------------------------------------
local function prompt(parent: BasePart, action: string, object: string, hold: number?, dist: number?): ProximityPrompt
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = action
	pp.ObjectText = object
	pp.HoldDuration = hold or 0
	pp.MaxActivationDistance = dist or 10
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.Parent = parent
	return pp
end

---------------------------------------------------------------------------
-- The three fishing rods' looks (rodStation). Each style colours the five animated sections and
-- adds trim on them. Section frames: -Z runs towards the tip; the handle's butt is at +Z (z 2.5),
-- the blanks run z -3.8..3.8, the reel is a ball beside the handle (its axle is X).
---------------------------------------------------------------------------
local ROD_BRASS = Color3.fromRGB(255, 200, 70)
local NEON, METAL, GLASS, WOODM = Enum.Material.Neon, Enum.Material.Metal, Enum.Material.Glass, Enum.Material.Wood
local BALL, CYL = Enum.PartType.Ball, Enum.PartType.Cylinder
local ROD_STYLES: { [string]: any } = {
	-- the Egg Rod: a varnished wooden pirate rod with a leather grip, brass fittings, red thread
	-- wraps at the guides, a wooden reel with a brass crank and a glowing tip
	egg = {
		handle = Color3.fromRGB(150, 95, 55),
		handleMat = WOODM,
		blank = Color3.fromRGB(250, 235, 190),
		trim = function(trim, band, guide, crank, _along, ring, _tip)
			local LEATHER, THREAD = Color3.fromRGB(70, 42, 28), Color3.fromRGB(200, 40, 50)
			for _, z in { 0.5, 1.05, 1.6, 2.1 } do
				band("RodHandle", 0.98, z, 0.32, LEATHER)
			end
			trim("RodHandle", Vector3.new(1.15, 1.15, 1.15), Vector3.new(0, 0, 2.65), ROD_BRASS, METAL, { Shape = BALL })
			band("RodHandle", 1.02, -2.35, 0.3, ROD_BRASS, METAL)
			band("RodS1", 0.68, 3.65, 0.3, ROD_BRASS, METAL)
			band("RodS2", 0.62, 3.6, 0.28, ROD_BRASS, METAL)
			band("RodS3", 0.46, 3.65, 0.26, ROD_BRASS, METAL)
			for _, g in { { "RodS1", 0.55, -1.5 }, { "RodS2", 0.5, -1.2 }, { "RodS3", 0.35, -0.8 }, { "RodS3", 0.35, -3.2 } } do
				guide(g[1], g[2], g[3], ROD_BRASS, METAL)
				band(g[1], g[2] + 0.06, g[3] - 0.3, 0.14, THREAD)
				band(g[1], g[2] + 0.06, g[3] + 0.3, 0.14, THREAD)
			end
			for _, x in { -0.72, 0.72 } do
				trim("RodReel", Vector3.new(0.16, 1.95, 1.95), Vector3.new(x, 0, 0), Color3.fromRGB(90, 55, 32), WOODM, { Shape = CYL })
			end
			crank(ROD_BRASS, Color3.fromRGB(240, 230, 210), METAL)
			trim("RodS3", Vector3.new(0.45, 0.45, 0.45), Vector3.new(0, 0, -3.95), ring, NEON, { Shape = BALL })
		end,
	},
	-- the Deep Rod: sleek dark metal with glowing cyan rings, a violet crystal butt and grip fins,
	-- violet glowing guides, a glass reel with a glowing core, and a crystal shard at the tip
	deep = {
		handle = Color3.fromRGB(28, 30, 62),
		handleMat = METAL,
		blank = Color3.fromRGB(70, 56, 140),
		blankMat = METAL,
		reel = Color3.fromRGB(150, 220, 255),
		reelMat = GLASS,
		reelTransparency = 0.45,
		trim = function(trim, band, guide, crank, _along, _ring, _tip)
			local CYAN, VIOLET, GUN = Color3.fromRGB(120, 230, 255), Color3.fromRGB(150, 110, 255), Color3.fromRGB(50, 54, 100)
			for _, z in { 0.6, 1.3, 2.0 } do
				band("RodHandle", 0.96, z, 0.12, CYAN, NEON)
			end
			trim("RodHandle", Vector3.new(0.75, 0.75, 0.75), Vector3.new(0, 0, 2.85), VIOLET, GLASS, { Transparency = 0.15 },
				CFrame.Angles(math.rad(45), 0, math.rad(45)))
			band("RodHandle", 1.05, -2.35, 0.35, GUN, METAL)
			for _, x in { -1, 1 } do
				trim("RodHandle", Vector3.new(0.06, 0.55, 1.3), Vector3.new(x * 0.5, 0.15, -1.6), VIOLET, METAL, nil, CFrame.Angles(0, 0, math.rad(x * 25)))
			end
			for _, b in { { "RodS1", 0.55, { -2.5, 0, 2.5 } }, { "RodS2", 0.5, { -2.4, 0, 2.4 } }, { "RodS3", 0.35, { -1.5, 1.5 } } } do
				for _, z in b[3] do
					band(b[1], b[2] + 0.08, z, 0.1, CYAN, NEON)
				end
			end
			band("RodS1", 0.68, 3.65, 0.3, GUN, METAL)
			band("RodS2", 0.62, 3.6, 0.28, GUN, METAL)
			band("RodS3", 0.46, 3.65, 0.26, GUN, METAL)
			for _, g in { { "RodS1", 0.55, -1.2 }, { "RodS2", 0.5, -1.2 }, { "RodS3", 0.35, -0.5 }, { "RodS3", 0.35, -3.0 } } do
				guide(g[1], g[2], g[3], VIOLET, NEON)
			end
			trim("RodReel", Vector3.new(0.9, 0.9, 0.9), Vector3.zero, CYAN, NEON, { Shape = BALL })
			trim("RodReel", Vector3.new(1.9, 0.25, 0.25), Vector3.zero, GUN, METAL, { Shape = CYL })
			crank(GUN, CYAN, METAL, NEON)
			trim("RodS3", Vector3.new(0.4, 0.4, 1.0), Vector3.new(0, 0, -4.2), CYAN, GLASS, { Transparency = 0.1 }, CFrame.Angles(0, 0, math.rad(45)))
		end,
	},
	-- the Abyss Rod: black with pink glowing veins and bone fangs, a watching eye at the butt, an
	-- eyeball reel, and a glowing lure with thorns at the tip
	abyss = {
		handle = Color3.fromRGB(26, 18, 36),
		blank = Color3.fromRGB(42, 28, 58),
		reel = Color3.fromRGB(240, 235, 225),
		trim = function(trim, band, guide, crank, along, _ring, _tip)
			local PINK, BONE, VOID, PLUM = Color3.fromRGB(255, 60, 150), Color3.fromRGB(235, 225, 200), Color3.fromRGB(10, 5, 15), Color3.fromRGB(70, 30, 80)
			for _, z in { 0.4, 1.0, 1.6, 2.2 } do
				band("RodHandle", 0.96, z, 0.1, PINK, NEON)
			end
			for k = 0, 3 do
				local a = k * math.pi / 2 + math.pi / 4
				trim("RodHandle", Vector3.new(0.12, 0.55, 0.12), Vector3.new(math.cos(a) * 0.55, math.sin(a) * 0.55, -2.2), BONE, nil, nil,
					CFrame.Angles(0, 0, a - math.pi / 2) * CFrame.Angles(math.rad(-30), 0, 0))
			end
			trim("RodHandle", Vector3.new(1.1, 1.1, 1.1), Vector3.new(0, 0, 2.7), Color3.fromRGB(26, 18, 36), nil, { Shape = BALL })
			trim("RodHandle", Vector3.new(0.45, 0.45, 0.08), Vector3.new(0, 0, 3.24), PINK, NEON)
			trim("RodHandle", Vector3.new(0.14, 0.3, 0.06), Vector3.new(0, 0, 3.29), VOID)
			for _, b in { { "RodS1", 0.55, 7.6 }, { "RodS2", 0.5, 7.5 }, { "RodS3", 0.35, 7.6 } } do
				trim(b[1], Vector3.new(0.06, 0.06, b[3] * 0.85), Vector3.new(0, b[2] / 2 + 0.01, 0), PINK, NEON)
				trim(b[1], Vector3.new(0.06, 0.06, b[3] * 0.6), Vector3.new(b[2] / 2 + 0.01, 0, 0.5), PINK, NEON)
			end
			for _, f in { { "RodS1", 0.55, -2.6 }, { "RodS1", 0.55, 0.2 }, { "RodS1", 0.55, 2.6 }, { "RodS2", 0.5, -2.2 }, { "RodS2", 0.5, 1.0 } } do
				trim(f[1], Vector3.new(0.1, 0.4, 0.1), Vector3.new(0, -(f[2] / 2 + 0.15), f[3]), BONE, nil, nil, CFrame.Angles(math.rad(-25), 0, 0))
			end
			band("RodS1", 0.68, 3.65, 0.3, PLUM)
			band("RodS2", 0.62, 3.6, 0.28, PLUM)
			band("RodS3", 0.46, 3.65, 0.26, PLUM)
			for _, g in { { "RodS1", 0.55, -1.3 }, { "RodS2", 0.5, -0.6 }, { "RodS3", 0.35, -0.8 }, { "RodS3", 0.35, -3.0 } } do
				guide(g[1], g[2], g[3], BONE)
			end
			-- the reel is an eyeball looking up the rod: a pink iris with a slit pupil
			trim("RodReel", Vector3.new(0.08, 0.95, 0.95), Vector3.new(0, 0, -0.78), PINK, NEON, { Shape = CYL }, along)
			trim("RodReel", Vector3.new(0.2, 0.55, 0.08), Vector3.new(0, 0, -0.84), VOID)
			crank(PLUM, PINK, nil, NEON)
			-- the lure: a glowing orb past the tip, with two thorns
			trim("RodS3", Vector3.new(0.55, 0.55, 0.55), Vector3.new(0, 0, -4.15), PINK, NEON, { Shape = BALL })
			for _, s in { -1, 1 } do
				trim("RodS3", Vector3.new(0.08, 0.45, 0.08), Vector3.new(s * 0.22, 0.15, -3.6), BONE, nil, nil, CFrame.Angles(0, 0, math.rad(s * -35)))
			end
		end,
	},
}

local function buildHub(world: Folder)
	local hub = Instance.new("Model")
	hub.Name = "Harbour"
	hub.Parent = world
	local c = CFrame.new(WorldBuilder.hubCenter)
	-- stacked blocky island: sand ring then grass top
	local r = Config.HUB_RADIUS
	local TOWN_K = r / 78 -- how much roomier the island is than the layout the numbers below were drawn on
	box(hub, c, Vector3.new(r * 2, 6, r * 2), Vector3.new(0, -1, 0), SAND, Enum.Material.Sand)
	box(hub, c, Vector3.new(r * 1.7, 3, r * 1.7), Vector3.new(0, 3.5, 0), GRASS, Enum.Material.Grass)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		box(hub, c * CFrame.Angles(0, a, 0), Vector3.new(r * 0.9, 6, 18), Vector3.new(0, -1, r * 0.95), SAND, Enum.Material.Sand)
	end
	local STONE = Color3.fromRGB(205, 200, 190)
	local STONE_DARK = Color3.fromRGB(140, 142, 160)
	local function ball(m: Instance, f: CFrame, size: Vector3, pos: Vector3, color: Color3, mat: Enum.Material?, extra: { [string]: any }?): BasePart
		local p = box(m, f, size, pos, color, mat, extra)
		p.Shape = Enum.PartType.Ball
		return p
	end

	-- lighthouse: a compact red-and-white tower (about 70% of the old one). The Guide NPC
	-- stands at its door and tells new players how everything works.
	local LS = 0.7
	local lh = c * CFrame.new(0, 5, 0)
	for i = 0, 7 do
		local col = if i % 2 == 0 then Color3.fromRGB(240, 60, 60) else Color3.fromRGB(250, 250, 250)
		local w = (14 - i * 0.8) * LS
		box(hub, lh, Vector3.new(w, 5 * LS + 0.05, w), Vector3.new(0, (2.5 + i * 5) * LS, 0), col)
	end
	box(hub, lh, Vector3.new(11 * LS, 1, 11 * LS), Vector3.new(0, 40.5 * LS, 0), Color3.fromRGB(40, 44, 60))
	local lamp = box(hub, lh, Vector3.new(6 * LS, 5 * LS, 6 * LS), Vector3.new(0, 43.5 * LS, 0), Color3.fromRGB(255, 240, 150), Enum.Material.Neon)
	lamp.Name = "Lamp"
	local light = Instance.new("PointLight")
	light.Range = 48
	light.Brightness = 1.6
	light.Color = Color3.fromRGB(255, 230, 150)
	light.Parent = lamp
	box(hub, lh, Vector3.new(9 * LS, 3 * LS, 9 * LS), Vector3.new(0, 47.5 * LS, 0), Color3.fromRGB(240, 60, 60))
	-- door and a stone landing on the +Z face (where the Guide stands)
	local baseW = 14 * LS
	box(hub, lh, Vector3.new(3.2, 4.6, 0.5), Vector3.new(0, 2.3, baseW / 2 + 0.05), WOOD_DARK)
	box(hub, lh, Vector3.new(3.8, 0.5, 0.7), Vector3.new(0, 4.8, baseW / 2 + 0.05), Color3.fromRGB(255, 205, 60))
	box(hub, lh, Vector3.new(12, 0.6, 5), Vector3.new(0, 0.3, baseW / 2 + 3), STONE, Enum.Material.Slate)

	-- palms: a trunk that curves, a crown sitting right on top of it, and fronds that grow
	-- out of the crown (each frond is a chain of blocks that touch end to end)
	local function palm(base: CFrame, seed: number)
		local rng = Random.new(seed)
		-- one Model per palm, so the intro can hide a whole tree that stands in its shot (it hid
		-- them part by part before and left half a palm floating)
		local tree = Instance.new("Model")
		tree.Name = "Palm"
		tree.Parent = hub
		local cf = base * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		local bend = math.rad(rng:NextNumber(3, 5.5))
		for k = 0, 5 do
			local w = 2.1 - k * 0.14
			local h = 2.4
			box(tree, cf, Vector3.new(w, h + 0.25, w), Vector3.new(0, h / 2, 0), if k % 2 == 0 then WOOD_DARK else Color3.fromRGB(125, 78, 46))
			cf = cf * CFrame.new(0, h, 0) * CFrame.Angles(0, 0, -bend)
		end
		local crown = ball(tree, cf, Vector3.new(2.8, 2.4, 2.8), Vector3.new(0, 0.2, 0), Color3.fromRGB(55, 150, 60))
		crown.Name = "Crown"
		for k = 0, 2 do
			local a = k / 3 * math.pi * 2 + 0.4
			ball(tree, cf * CFrame.Angles(0, a, 0), Vector3.new(1.1, 1.1, 1.1), Vector3.new(0.7, -0.9, 0.5), Color3.fromRGB(110, 70, 40))
		end
		local fronds = 7
		local lens = { 4.2, 3.8, 3.2 }
		local widths = { 2.8, 2.3, 1.5 }
		local droop = { -14, -30, -42 }
		for k = 0, fronds - 1 do
			local a = k / fronds * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
			local fc = cf * CFrame.new(0, 0.4, 0) * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(8), 0, 0)
			for j = 1, 3 do
				local len = lens[j]
				box(tree, fc, Vector3.new(widths[j], 0.35, len + 0.15), Vector3.new(0, 0, -len / 2), if (k + j) % 2 == 0 then Color3.fromRGB(70, 175, 70) else Color3.fromRGB(55, 150, 60), nil, { CanCollide = false })
				fc = fc * CFrame.new(0, 0, -len) * CFrame.Angles(math.rad(droop[j]), 0, 0)
			end
		end
	end
	-- three palms in front of the outer vendors, and a ring near the shore that keeps clear of
	-- the docks (every 60 deg), the vendors (30 + 60k) and the striped towers (diagonals)
	for i, az in { 90, 210, 330 } do
		palm(c * CFrame.Angles(0, math.rad(az), 0) * CFrame.new(0, 5, 38 * TOWN_K), 100 + i)
	end
	for i, az in { 14, 74, 106, 166, 194, 254, 286, 346 } do
		palm(c * CFrame.Angles(0, math.rad(az), 0) * CFrame.new(0, 5, 58 * TOWN_K), 200 + i)
	end

	---------------------------------------------------------------------------
	-- Vendors. Each looks like what it is (a vault, a museum, a shrine, a tent...) and sits
	-- between the dock paths: six on the outer ring, three on the inner ring. Their fronts
	-- face the lighthouse (+Z of the frame). The town is 25% roomier than v1 (TOWN_SCALE).
	---------------------------------------------------------------------------
	-- `radius` is in the old (HUB_RADIUS 78) layout; TOWN_K spreads every vendor out with the island
	local function slot(angDeg: number, radius: number): CFrame
		return c * CFrame.Angles(0, math.rad(angDeg), 0) * CFrame.new(0, 5, -radius * TOWN_K)
	end
	-- the invisible anchor carries the prompt and the floating name
	local function vendorTag(m: Model, f: CFrame, title: string, sub: string, color: Color3, signY: number, promptName: string, action: string)
		local anchor = box(m, f, Vector3.new(12, 5, 8), Vector3.new(0, 2.5, 3), Color3.new(1, 1, 1), nil, { Transparency = 1, CanCollide = false, Name = "Anchor" })
		local bb = label(anchor, title, UDim2.fromOffset(320, 56), Vector3.new(0, signY, 0), color)
		bb.MaxDistance = 260
		if sub ~= "" then
			local s = Instance.new("TextLabel")
			s.Name = "Sub"
			s.BackgroundTransparency = 1
			s.Size = UDim2.fromScale(1, 0.6)
			s.Position = UDim2.fromScale(0, 1)
			s.Font = Enum.Font.FredokaOne
			s.TextScaled = true
			s.Text = sub
			s.TextColor3 = Color3.fromRGB(255, 255, 255)
			s.Parent = bb
			local st = Instance.new("UIStroke")
			st.Thickness = 3
			st.Color = Color3.fromRGB(16, 22, 44)
			st.Parent = s
		end
		local pp = prompt(anchor, action, title, 0, 14)
		pp.Name = promptName
		m:SetAttribute("Stand", m.Name)
	end
	local function newVendor(name: string): Model
		local m = Instance.new("Model")
		m.Name = name
		m.Parent = hub
		return m
	end
	local function glow(parent: Instance, part: BasePart, color: Color3, range: number, brightness: number?)
		local l = Instance.new("PointLight")
		l.Color = color
		l.Range = range
		l.Brightness = brightness or 1.5
		l.Parent = part
	end

	-- Treasure Shop (outer, gold): a pirate treasure hut with a gold hoard and a chest on the roof
	do
		local f = slot(30, 55)
		local m = newVendor("TreasureShop")
		local GOLD = Color3.fromRGB(255, 205, 60)
		box(m, f, Vector3.new(15, 1, 11), Vector3.new(0, 0.5, 0), STONE_DARK)
		box(m, f, Vector3.new(14, 8, 1), Vector3.new(0, 5, -4), WOOD)
		for _, x in { -6.5, 6.5 } do
			box(m, f, Vector3.new(1, 8, 7), Vector3.new(x, 5, -0.5), WOOD_DARK)
		end
		box(m, f, Vector3.new(16, 1.2, 10), Vector3.new(0, 9.6, -0.5), Color3.fromRGB(120, 60, 40))
		box(m, f, Vector3.new(13, 1.2, 8), Vector3.new(0, 10.7, -0.5), Color3.fromRGB(150, 80, 50))
		box(m, f, Vector3.new(10, 1.2, 6), Vector3.new(0, 11.8, -0.5), Color3.fromRGB(180, 100, 60))
		-- chest on the roof
		box(m, f, Vector3.new(6, 2.6, 3.6), Vector3.new(0, 14.1, -0.5), WOOD_DARK)
		box(m, f, Vector3.new(6.2, 1.6, 3.8), Vector3.new(0, 15.8, -0.5), GOLD, Enum.Material.Metal)
		box(m, f, Vector3.new(1, 4.4, 3.9), Vector3.new(0, 14.9, -0.5), GOLD, Enum.Material.Metal)
		-- counter, coin stacks, gems
		box(m, f, Vector3.new(12, 3, 2.4), Vector3.new(0, 2.5, 3), WOOD_LIGHT)
		for k = -2, 2 do
			local h = 1 + ((k + 3) % 3) * 0.7
			local coin = box(m, f, Vector3.new(1.8, h, 1.8), Vector3.new(k * 2.2, 4 + h / 2, 3), GOLD, Enum.Material.Metal)
			coin.Shape = Enum.PartType.Cylinder
			coin.CFrame = f * CFrame.new(k * 2.2, 4 + h / 2, 3) * CFrame.Angles(0, 0, math.rad(90))
			coin.Size = Vector3.new(h, 1.8, 1.8)
		end
		local gem = box(m, f * CFrame.Angles(math.rad(45), 0, math.rad(45)), Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 3.5, 3.8), Color3.fromRGB(120, 235, 255), Enum.Material.Neon)
		glow(m, gem, Color3.fromRGB(255, 220, 120), 16)
		for _, x in { -5.5, 5.5 } do
			ball(m, f, Vector3.new(2.4, 1.6, 2.4), Vector3.new(x, 1.6, 6), GOLD, Enum.Material.Metal)
		end
		vendorTag(m, f, "Treasure Shop", "Boosts, passes, codes", Color3.fromRGB(255, 200, 40), 19, "ShopPrompt", "Open")
	end

	-- Egg Shop (outer, blue): a straw nest holding one giant spotted egg
	do
		local f = slot(90, 55)
		local m = newVendor("EggShopStand")
		for i = 0, 11 do
			local a = i / 12 * math.pi * 2
			box(m, f * CFrame.Angles(0, a, 0), Vector3.new(3.4, 1.6, 1.4), Vector3.new(0, 0.8, 5.6), Color3.fromRGB(215, 175, 95), Enum.Material.Wood)
		end
		box(m, f, Vector3.new(10, 1, 10), Vector3.new(0, 0.5, 0), Color3.fromRGB(235, 205, 140), Enum.Material.Wood)
		local egg = ball(m, f, Vector3.new(8, 10.5, 8), Vector3.new(0, 6.4, -0.5), Color3.fromRGB(120, 200, 255))
		egg.Name = "GiantEgg"
		ball(m, f, Vector3.new(5.5, 6.5, 5.5), Vector3.new(0, 8.6, -0.5), Color3.fromRGB(150, 215, 255))
		for _, s in { { -2.4, 8, 2.8 }, { 2.6, 6, 2.6 }, { 0.4, 4.6, 3.6 }, { -1.6, 11, 2.1 }, { 2, 9.6, 2.6 } } do
			ball(m, f, Vector3.new(1.4, 1.4, 1.4), Vector3.new(s[1], s[2], s[3]), Color3.fromRGB(255, 255, 255))
		end
		for i = 0, 4 do
			box(m, f, Vector3.new(0.5, 1.3, 0.4), Vector3.new((i % 2 - 0.5) * 1.1, 11.8 + (i % 2) * 0.1, 3.4 - i * 0.2 + 0.4), Color3.fromRGB(255, 255, 255))
		end
		for _, x in { -6, 6 } do
			local e = ball(m, f, Vector3.new(2.2, 2.8, 2.2), Vector3.new(x, 2.4, 3.6), if x < 0 then Color3.fromRGB(255, 150, 190) else Color3.fromRGB(255, 220, 80))
			e.Name = "MiniEgg"
		end
		vendorTag(m, f, "Egg Shop", "Rare and Epic eggs", Color3.fromRGB(80, 170, 255), 15, "EggShopPrompt", "Open")
	end

	-- Event stand (outer, orange): a festival tent with bunting and lanterns
	do
		local f = slot(150, 55)
		local m = newVendor("EventStand")
		local col = Color3.fromRGB(255, 140, 40)
		for _, x in { -6, 6 } do
			for _, z in { -4, 4 } do
				box(m, f, Vector3.new(0.8, 9, 0.8), Vector3.new(x, 4.5, z), WOOD_DARK)
			end
		end
		for layer = 0, 3 do
			local w = 15 - layer * 3.4
			for k = 0, 5 do
				local sw = w / 6
				box(m, f, Vector3.new(sw, 1.2, 10.5 - layer * 2.4), Vector3.new(-w / 2 + sw * (k + 0.5), 9.6 + layer * 1.2, 0), if k % 2 == 0 then col else Color3.fromRGB(255, 255, 255))
			end
		end
		box(m, f, Vector3.new(1, 2.5, 1), Vector3.new(0, 14.8, 0), WOOD_DARK)
		local fl = box(m, f, Vector3.new(0.3, 2, 3), Vector3.new(0, 16.4, 1.5), Color3.fromRGB(240, 60, 60))
		fl.Name = "Pennant"
		box(m, f, Vector3.new(12, 3, 2.4), Vector3.new(0, 1.5, 0), WOOD)
		box(m, f, Vector3.new(12.6, 0.5, 3), Vector3.new(0, 3.2, 0), WOOD_LIGHT)
		for k = 0, 5 do
			local sh = ball(m, f, Vector3.new(1.4, 1.1, 1.4), Vector3.new(-4.5 + k * 1.8, 4, 0), Color3.fromRGB(255, 190 - k * 12, 200))
			sh.Name = "ShellPile"
		end
		for k = 0, 6 do
			box(m, f, Vector3.new(1.4, 1.8, 0.2), Vector3.new(-6 + k * 2, 8 - math.abs(k - 3) * -0.15, 5.4), if k % 2 == 0 then col else Color3.fromRGB(255, 230, 90))
		end
		for _, x in { -6, 6 } do
			local lamp = ball(m, f, Vector3.new(1.4, 1.4, 1.4), Vector3.new(x, 7.6, 4.8), Color3.fromRGB(255, 220, 130), Enum.Material.Neon)
			glow(m, lamp, Color3.fromRGB(255, 200, 120), 12)
		end
		vendorTag(m, f, Config.EVENT.name, "", col, 18, "EventPrompt", "Open")
	end

	-- Abyss Crate (outer, purple): a stone arch with a locked crate floating inside
	do
		local f = slot(210, 55)
		local m = newVendor("CrateStand")
		local P = Color3.fromRGB(150, 80, 230)
		for i = 0, 2 do
			box(m, f, Vector3.new(14 - i * 2, 1, 9 - i * 1.5), Vector3.new(0, 0.5 + i, 0), STONE_DARK)
		end
		for _, x in { -5, 5 } do
			box(m, f, Vector3.new(2.4, 13, 2.4), Vector3.new(x, 9, -1), Color3.fromRGB(70, 55, 110))
			box(m, f, Vector3.new(3, 1, 3), Vector3.new(x, 15.5, -1), STONE_DARK)
			local orb = ball(m, f, Vector3.new(1.4, 1.4, 1.4), Vector3.new(x, 17, -1), P, Enum.Material.Neon)
			glow(m, orb, P, 9, 1)
		end
		box(m, f, Vector3.new(14, 2, 3.2), Vector3.new(0, 16, -1), Color3.fromRGB(70, 55, 110))
		-- the crate hangs between the pillars on two chains
		for _, x in { -1.4, 1.4 } do
			box(m, f, Vector3.new(0.3, 5, 0.3), Vector3.new(x, 12.6, -1), Color3.fromRGB(60, 62, 80), Enum.Material.Metal)
		end
		local crate = box(m, f, Vector3.new(5, 4, 4), Vector3.new(0, 8.6, -1), Color3.fromRGB(90, 50, 150))
		crate.Name = "FloatingCrate"
		box(m, f, Vector3.new(5.3, 0.7, 4.3), Vector3.new(0, 7.1, -1), P, Enum.Material.Neon)
		box(m, f, Vector3.new(5.3, 0.7, 4.3), Vector3.new(0, 10.1, -1), P, Enum.Material.Neon)
		local q = box(m, f, Vector3.new(1.4, 1.4, 0.3), Vector3.new(0, 8.6, 1.2), Color3.fromRGB(255, 240, 150), Enum.Material.Neon)
		-- (one soft light on the crate is enough: three big overlapping point lights made the stand stutter)
		glow(m, q, P, 12, 1)
		vendorTag(m, f, "LIMITED: " .. Config.LIMITED.name, "5% Leviathan", P, 20, "LimitedPrompt", "Roll (" .. Config.LIMITED.pearls .. " Pearls)")
	end

	-- Bundle (outer, green): a gift shop with a huge present
	do
		local f = slot(270, 55)
		local m = newVendor("BundleStand")
		local G = Color3.fromRGB(60, 200, 120)
		box(m, f, Vector3.new(13, 1, 9), Vector3.new(0, 0.5, 0), Color3.fromRGB(240, 235, 215))
		box(m, f, Vector3.new(8, 8, 8), Vector3.new(0, 5, -1), G)
		box(m, f, Vector3.new(8.4, 1.4, 8.4), Vector3.new(0, 9.7, -1), Color3.fromRGB(45, 170, 100))
		box(m, f, Vector3.new(1.8, 8.2, 8.4), Vector3.new(0, 5, -1), Color3.fromRGB(255, 255, 255))
		box(m, f, Vector3.new(8.4, 8.2, 1.8), Vector3.new(0, 5, -1), Color3.fromRGB(255, 255, 255))
		box(m, f, Vector3.new(1.8, 1.6, 8.6), Vector3.new(0, 10.6, -1), Color3.fromRGB(255, 255, 255))
		for _, s in { -1, 1 } do
			box(m, f * CFrame.Angles(0, 0, math.rad(s * 35)), Vector3.new(4, 2.4, 1.6), Vector3.new(s * 2.2, 12.3, -1), Color3.fromRGB(255, 90, 120))
		end
		ball(m, f, Vector3.new(2, 2, 2), Vector3.new(0, 11.8, -1), Color3.fromRGB(255, 90, 120))
		for _, s in { { -5.2, 4, 1.8, 1.8, 1.8 }, { 5.2, 4, 2.2, 2.2, 2.2 }, { 4.4, 5.8, 1.5, 1.5, 1.5 } } do
			local gx = box(m, f, Vector3.new(s[3], s[4], s[5]), Vector3.new(s[1], 1 + s[4] / 2, s[2]), if s[1] < 0 then Color3.fromRGB(255, 205, 60) else Color3.fromRGB(100, 170, 255))
			box(m, f, Vector3.new(s[3] + 0.1, s[4] + 0.1, 0.4), Vector3.new(s[1], 1 + s[4] / 2, s[2]), Color3.new(1, 1, 1))
			local _ = gx
		end
		vendorTag(m, f, "Elemental Bundle", "4 eggs: Tide, Coral, Storm, Abyss | R$" .. Config.PRODUCTS.ElementBundle.price, G, 16, "BundlePrompt", "Buy")
	end

	-- Monster Museum (inner): a stone hall with columns, steps and glass display cases
	do
		local f = slot(210, 30)
		local m = newVendor("Museum")
		local BLUE = Color3.fromRGB(70, 150, 255)
		for i = 0, 2 do
			box(m, f, Vector3.new(17 - i * 1.6, 0.8, 10 - i * 1.6), Vector3.new(0, 0.4 + i * 0.8, 1 - i * 0.2), STONE)
		end
		box(m, f, Vector3.new(14, 10, 1.6), Vector3.new(0, 7.4, -4), Color3.fromRGB(170, 190, 225))
		for _, x in { -6, -2, 2, 6 } do
			box(m, f, Vector3.new(1.7, 9, 1.7), Vector3.new(x, 6.9, 1.6), STONE)
			box(m, f, Vector3.new(2.3, 0.7, 2.3), Vector3.new(x, 11.6, 1.6), STONE_DARK)
		end
		box(m, f, Vector3.new(16.5, 1.6, 6.4), Vector3.new(0, 12.3, 0.6), STONE)
		for i = 0, 2 do
			box(m, f, Vector3.new(13 - i * 4.2, 1.1, 5.4), Vector3.new(0, 13.7 + i * 1.1, 0.6), if i == 1 then BLUE else STONE)
		end
		-- a monster skeleton on display on the roof
		for k = 0, 4 do
			box(m, f, Vector3.new(0.5, 2.4 - math.abs(k - 2) * 0.35, 0.5), Vector3.new(-2 + k, 18.1, 0.6), Color3.fromRGB(250, 245, 225))
		end
		box(m, f, Vector3.new(5.4, 0.5, 0.5), Vector3.new(0, 17, 0.6), Color3.fromRGB(250, 245, 225))
		box(m, f, Vector3.new(1.8, 1.4, 1.2), Vector3.new(3.8, 17.7, 0.6), Color3.fromRGB(250, 245, 225))
		for _, x in { -3.6, 3.6 } do
			local case = box(m, f, Vector3.new(3, 4.2, 3), Vector3.new(x, 3.6, 4.4), Color3.fromRGB(190, 230, 255), Enum.Material.Glass, { Transparency = 0.45 })
			case.Name = "DisplayCase"
			local gem = box(m, f * CFrame.Angles(math.rad(45), 0, math.rad(45)), Vector3.new(1.3, 1.3, 1.3), Vector3.new(x, 3.6, 4.4), BLUE, Enum.Material.Neon)
			glow(m, gem, BLUE, 8)
		end
		vendorTag(m, f, "Monster Museum", "Your monster Index", BLUE, 21, "MuseumPrompt", "Open")
	end

	-- Power Shrine (inner): a stepped stone shrine with glowing pillars and a floating crystal
	do
		local f = slot(330, 30)
		local m = newVendor("PowerShrine")
		local O = Color3.fromRGB(255, 170, 40)
		for i = 0, 2 do
			box(m, f, Vector3.new(16 - i * 4, 1, 16 - i * 4), Vector3.new(0, 0.5 + i, 0), if i == 1 then Color3.fromRGB(165, 165, 185) else STONE_DARK, Enum.Material.Slate)
		end
		for _, x in { -3.2, 3.2 } do
			for _, z in { -3.2, 3.2 } do
				box(m, f, Vector3.new(1.4, 8, 1.4), Vector3.new(x, 7, z), Color3.fromRGB(110, 112, 135), Enum.Material.Slate)
				local lamp = ball(m, f, Vector3.new(1.3, 1.3, 1.3), Vector3.new(x, 11.6, z), Color3.fromRGB(240, 160, 50), Enum.Material.SmoothPlastic)
				glow(m, lamp, O, 7, 0.45)
			end
		end
		-- gate beams over the front pillars
		box(m, f, Vector3.new(10.4, 0.9, 1.9), Vector3.new(0, 11, 3.2), Color3.fromRGB(230, 70, 60))
		box(m, f, Vector3.new(11.6, 0.7, 2.2), Vector3.new(0, 12.1, 3.2), Color3.fromRGB(230, 70, 60))
		-- a faceted crystal that glows softly (not a floodlight)
		local crystal = box(m, f * CFrame.Angles(math.rad(35), math.rad(45), 0), Vector3.new(2.6, 2.6, 2.6), Vector3.new(0, 7.2, 0), Color3.fromRGB(235, 150, 45), Enum.Material.Glass, { Transparency = 0.15 })
		crystal.Name = "PowerCrystal"
		glow(m, crystal, O, 11, 0.55)
		local att = Instance.new("Attachment")
		att.Parent = crystal
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Color = ColorSequence.new(O, Color3.fromRGB(255, 240, 150))
		pe.LightEmission = 0.35
		pe.Rate = 4
		pe.Size = NumberSequence.new(0.35)
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		pe.Lifetime = NumberRange.new(1, 2)
		pe.Speed = NumberRange.new(1, 2)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Parent = att
		for k = 0, 7 do
			local a = k / 8 * math.pi * 2
			box(m, f * CFrame.Angles(0, a, 0), Vector3.new(0.8, 0.2, 0.8), Vector3.new(0, 3.1, 4.6), Color3.fromRGB(225, 150, 55))
		end
		vendorTag(m, f, "Power Shrine", "Spin Tide Powers", O, 17, "PowerPrompt", "Open")
	end

	-- Dockyard (inner, blue): the ship's store. A pier shed with a ship's wheel, an anchor, paint
	-- cans and a model ship on the counter. Egg Luck, Fast Reel, the Shipwright and the Ship
	-- Workshop are bought here (client Menus.dockyard) instead of from boards on the deck.
	-- Roof underside is 11 up and the Shipwright's hat ends near 9.5, so nothing clips.
	do
		local f = slot(150, 30)
		local m = newVendor("Dockyard")
		local NAVY = Color3.fromRGB(35, 70, 130)
		local BLUE = Color3.fromRGB(70, 150, 255)
		local METAL = Color3.fromRGB(70, 74, 96)
		local function cyl(x: number, y: number, z: number, h: number, d: number, color: Color3, mat: Enum.Material?): BasePart
			-- an upright cylinder (Roblox cylinders lie along X, so turn it up)
			local p = box(m, f, Vector3.new(h, d, d), Vector3.zero, color, mat)
			p.Shape = Enum.PartType.Cylinder
			p.CFrame = f * CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.rad(90))
			return p
		end
		-- pier deck and the shed: back wall, two back posts, two front posts, a stepped blue roof
		box(m, f, Vector3.new(26, 1, 17), Vector3.new(0, 0.5, 0), WOOD_LIGHT, Enum.Material.Wood)
		box(m, f, Vector3.new(22, 9.5, 1), Vector3.new(0, 5.75, -7), Color3.fromRGB(60, 110, 175))
		for _, x in { -11, 11 } do
			box(m, f, Vector3.new(1.2, 10.4, 1.2), Vector3.new(x, 6.2, -7), WOOD_DARK)
			box(m, f, Vector3.new(1.2, 10.4, 1.2), Vector3.new(x, 6.2, 6), WOOD_DARK)
		end
		box(m, f, Vector3.new(27, 1.2, 16.5), Vector3.new(0, 11.6, -0.5), NAVY)
		box(m, f, Vector3.new(23, 1.2, 12.5), Vector3.new(0, 12.8, -0.5), Color3.fromRGB(55, 105, 185))
		box(m, f, Vector3.new(17, 1.2, 8), Vector3.new(0, 14, -0.5), BLUE)
		-- white stripe along the front of the roof
		box(m, f, Vector3.new(27.2, 0.5, 0.5), Vector3.new(0, 11.6, 7.8), Color3.fromRGB(250, 250, 255))
		-- pennant on top
		box(m, f, Vector3.new(0.4, 4, 0.4), Vector3.new(0, 16.6, -0.5), WOOD_DARK)
		box(m, f, Vector3.new(0.3, 1.6, 3), Vector3.new(0, 17.6, 1.2), Color3.fromRGB(240, 60, 60))
		-- the ship's wheel on the back wall (right of the Shipwright)
		do
			local wc = Vector3.new(6.8, 7.4, -6.2)
			for _, deg in { 0, 45, 90, 135 } do
				box(m, f * CFrame.new(wc) * CFrame.Angles(0, 0, math.rad(deg)), Vector3.new(0.5, 5.4, 0.5), Vector3.zero, WOOD_DARK)
			end
			ball(m, f, Vector3.new(1.7, 1.7, 1.7), wc, WOOD)
			for _, deg in { 0, 45, 90, 135, 180, 225, 270, 315 } do
				local tip = f * CFrame.new(wc) * CFrame.Angles(0, 0, math.rad(deg)) * CFrame.new(0, 3, 0)
				ball(m, tip, Vector3.new(0.8, 0.8, 0.8), Vector3.zero, WOOD_LIGHT)
			end
		end
		-- a big anchor leaning on the back wall (left of the Shipwright)
		do
			local ax = -7.2
			box(m, f, Vector3.new(0.9, 8, 0.9), Vector3.new(ax, 5.2, -6), METAL, Enum.Material.Metal)
			box(m, f, Vector3.new(4.2, 0.9, 0.9), Vector3.new(ax, 8.6, -6), METAL, Enum.Material.Metal)
			box(m, f, Vector3.new(5.6, 0.9, 0.9), Vector3.new(ax, 2.2, -6), METAL, Enum.Material.Metal)
			for _, s in { -1, 1 } do
				box(m, f * CFrame.new(ax + s * 2.6, 3.2, -6) * CFrame.Angles(0, 0, math.rad(s * -35)), Vector3.new(0.9, 2.4, 0.9), Vector3.zero, METAL, Enum.Material.Metal)
			end
			ball(m, f, Vector3.new(1.4, 1.4, 1.4), Vector3.new(ax, 9.6, -6), METAL, Enum.Material.Metal)
		end
		-- counter (front), with a model ship, a blueprint and paint cans on top
		box(m, f, Vector3.new(15, 3, 2.4), Vector3.new(0, 2.5, 3.5), WOOD_LIGHT)
		box(m, f, Vector3.new(15.6, 0.5, 3), Vector3.new(0, 4.25, 3.5), WOOD)
		do
			box(m, f, Vector3.new(5, 1.1, 1.8), Vector3.new(4.5, 5.05, 3.5), Color3.fromRGB(150, 90, 50))
			box(m, f, Vector3.new(0.3, 3.8, 0.3), Vector3.new(4.5, 7.5, 3.5), WOOD_DARK)
			box(m, f, Vector3.new(2.8, 2.6, 0.2), Vector3.new(4.5, 7.7, 3.5), Color3.fromRGB(250, 246, 232))
			box(m, f, Vector3.new(2.8, 0.5, 0.25), Vector3.new(4.5, 7.7, 3.5), Color3.fromRGB(240, 60, 60))
			box(m, f, Vector3.new(2.6, 0.12, 1.6), Vector3.new(-4.6, 4.56, 3.5), Color3.fromRGB(190, 225, 255))
			local paints = { Color3.fromRGB(255, 150, 80), Color3.fromRGB(190, 90, 220), Color3.fromRGB(70, 210, 200) }
			for k, col in paints do
				cyl(-1.4 + (k - 1) * 1.6, 5.05, 3.4, 1.5, 1.2, col)
			end
		end
		-- barrels and crates just off the pier
		for _, x in { -14.2, 14.2 } do
			cyl(x, 1.3, 1, 2.6, 2.4, WOOD)
			cyl(x, 1.3, 1, 0.5, 2.55, WOOD_DARK)
			box(m, f, Vector3.new(3, 3, 3), Vector3.new(x, 1.5, -3.8), WOOD_LIGHT)
			box(m, f, Vector3.new(3.1, 0.4, 3.1), Vector3.new(x, 3, -3.8), WOOD_DARK)
		end
		-- lanterns on the front posts
		for _, x in { -11, 11 } do
			local lamp = ball(m, f, Vector3.new(1.5, 1.5, 1.5), Vector3.new(x, 9.2, 6.8), Color3.fromRGB(255, 220, 130), Enum.Material.Neon)
			glow(m, lamp, Color3.fromRGB(255, 200, 120), 12, 0.8)
		end
		vendorTag(m, f, "Dockyard", "Ship upgrades", BLUE, 19, "DockyardPrompt", "Open")
	end

	-- the Deepest Divers leaderboard: a big wooden board on two posts (outer ring)
	do
		local f = slot(330, 55)
		local lb = Instance.new("Model")
		lb.Name = "Leaderboard"
		lb.Parent = hub
		-- the posts end at the board's bottom edge (y = 3) instead of running up behind the face
		for _, x in { -6.5, 6.5 } do
			box(lb, f, Vector3.new(1, 3.1, 0.6), Vector3.new(x, 1.55, 0), WOOD_DARK)
		end
		local face = box(lb, f, Vector3.new(14, 14, 0.8), Vector3.new(0, 10, 0), Color3.fromRGB(25, 45, 85), nil, { Name = "BoardFace" })
		box(lb, f, Vector3.new(15, 1.2, 1.2), Vector3.new(0, 17.6, 0), WOOD)
		-- the face looks towards the lighthouse, where players walk
		face.CFrame = f * CFrame.new(0, 10, 0) * CFrame.Angles(0, math.rad(180), 0)
		WorldBuilder.leaderboardFace = face
	end

	-- the Spellbook (inner): a giant open book on a stone stand
	do
		local f = slot(90, 30)
		local book = Instance.new("Model")
		book.Name = "Spellbook"
		book.Parent = hub
		box(book, f, Vector3.new(8, 1, 8), Vector3.new(0, 0.5, 0), STONE_DARK)
		box(book, f, Vector3.new(4.2, 4, 4.2), Vector3.new(0, 3, 0), STONE)
		box(book, f, Vector3.new(6.6, 0.8, 5.4), Vector3.new(0, 5.4, 0), STONE)
		local tilt = CFrame.Angles(math.rad(-25), 0, 0)
		for _, sx in { -1, 1 } do
			box(book, f * CFrame.new(sx * 2.5, 6.5, 0) * tilt * CFrame.Angles(0, 0, math.rad(sx * -8)), Vector3.new(5, 0.4, 6), Vector3.zero, Color3.fromRGB(110, 50, 170))
			box(book, f * CFrame.new(sx * 2.45, 6.85, 0) * tilt * CFrame.Angles(0, 0, math.rad(sx * -8)), Vector3.new(4.5, 0.3, 5.5), Vector3.zero, Color3.fromRGB(250, 244, 225))
		end
		local rune = box(book, f * CFrame.new(0, 9.4, 0), Vector3.new(1.6, 1.6, 1.6), Vector3.zero, Color3.fromRGB(120, 230, 255), Enum.Material.Neon, { Name = "Rune", CanCollide = false })
		rune.Shape = Enum.PartType.Ball
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(150, 220, 255)
		light.Range = 18
		light.Parent = rune
		local att = Instance.new("Attachment")
		att.Parent = rune
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Color = ColorSequence.new(Color3.fromRGB(160, 230, 255), Color3.fromRGB(220, 160, 255))
		pe.LightEmission = 1
		pe.Rate = 12
		pe.Lifetime = NumberRange.new(1, 2)
		pe.Speed = NumberRange.new(1, 3)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Parent = att
		vendorTag(book, f, "SPELLBOOK", "", Color3.fromRGB(190, 150, 255), 12, "SpellPrompt", "Open")
	end

	-- townsfolk: every vendor has someone behind the counter (animated on the client, see
	-- client/NpcView), and Captain Coral at the lighthouse door is the game's Guide
	do
		local function stand(vendor: string, f: CFrame, pos: Vector3, yawDeg: number, spec: Npc.Spec, seed: number)
			local m = hub:FindFirstChild(vendor) or hub
			Npc.build(m, f * CFrame.new(pos) * CFrame.Angles(0, math.pi + math.rad(yawDeg), 0), spec, seed)
		end
		stand("TreasureShop", slot(30, 55), Vector3.new(0, 1, -0.5), 0, { name = "Pirate", scale = 1.0, anim = "present", shirt = Color3.fromRGB(190, 55, 55), hat = "tricorn", hatColor = Color3.fromRGB(40, 36, 50), beard = Color3.fromRGB(50, 34, 24), skin = Color3.fromRGB(224, 172, 120) }, 1)
		stand("EggShopStand", slot(90, 55), Vector3.new(0, 0, 8.6), 0, { name = "Egg Farmer", anim = "present", shirt = Color3.fromRGB(80, 160, 240), hat = "straw", pants = Color3.fromRGB(110, 80, 50) }, 2)
		stand("EventStand", slot(150, 55), Vector3.new(0, 0, -2.6), 0, { name = "Festival Host", scale = 0.9, anim = "wave", shirt = Color3.fromRGB(255, 140, 40), hat = "party", hatColor = Color3.fromRGB(255, 90, 90) }, 3)
		stand("CrateStand", slot(210, 55), Vector3.new(0, 3, 2), 0, { name = "Mystic", anim = "hover", shirt = Color3.fromRGB(110, 60, 180), hat = "hood", hatColor = Color3.fromRGB(80, 44, 140), skin = Color3.fromRGB(245, 195, 150) }, 4)
		stand("BundleStand", slot(270, 55), Vector3.new(0, 0, 6.2), 0, { name = "Gift Wrapper", anim = "present", shirt = Color3.fromRGB(60, 200, 120), hat = "cap", hatColor = Color3.fromRGB(255, 90, 120), prop = "gift" }, 5)
		stand("Museum", slot(210, 30), Vector3.new(0, 0.8, 5.4), 0, { name = "Curator", anim = "read", shirt = Color3.fromRGB(70, 150, 255), glasses = true, prop = "book", pants = Color3.fromRGB(50, 56, 90) }, 6)
		stand("PowerShrine", slot(330, 30), Vector3.new(0, 2, 5.2), 0, { name = "Shrine Keeper", anim = "hover", shirt = Color3.fromRGB(235, 150, 45), hat = "hood", hatColor = Color3.fromRGB(200, 110, 30), skin = Color3.fromRGB(176, 120, 80) }, 7)
		-- the Shipwright: behind the counter (z -1.5 keeps the forward-held arms clear of it) on the
		-- pier deck (top y = 1); the roof is 11 up so the cap fits under it
		stand("Dockyard", slot(150, 30), Vector3.new(0, 1, -1.5), 0, { name = "Shipwright", anim = "present", shirt = Color3.fromRGB(70, 150, 255), pants = Color3.fromRGB(40, 56, 100), hat = "cap", hatColor = Color3.fromRGB(35, 70, 130), beard = Color3.fromRGB(120, 78, 44), skin = Color3.fromRGB(224, 172, 120) }, 10)
		stand("Spellbook", slot(90, 30), Vector3.new(-6.2, 0, 3.4), -25, { name = "Wizard", anim = "read", shirt = Color3.fromRGB(110, 50, 170), hat = "wizard", hatColor = Color3.fromRGB(90, 44, 150), beard = Color3.fromRGB(240, 240, 245), prop = "scroll" }, 8)

		-- the Guide, at the lighthouse door
		local gm = Instance.new("Model")
		gm.Name = "GuideStand"
		gm.Parent = hub
		local gf = c * CFrame.new(0, 5, 5)
		Npc.build(gm, c * CFrame.new(0, 5.6, 8.2) * CFrame.Angles(0, math.pi, 0), { name = "Captain Coral", anim = "wave", shirt = Color3.fromRGB(40, 80, 170), pants = Color3.fromRGB(240, 240, 245), hat = "captain", hatColor = Color3.fromRGB(245, 245, 250), beard = Color3.fromRGB(235, 235, 240), scale = 1.3, skin = Color3.fromRGB(224, 172, 120) }, 9)
		vendorTag(gm, gf, "Captain Coral", "Ask me how to play!", Color3.fromRGB(255, 220, 90), 8.5, "GuidePrompt", "Talk")
	end


	-- town dressing: a plaza ring round the lighthouse, stone paths to every dock, tall
	-- striped towers, flower beds and lanterns so the harbour reads like a little village
	do
		local STONE = Color3.fromRGB(200, 195, 180)
		local grassTop = c * CFrame.new(0, 5.05, 0)
		for i = 0, 19 do
			local a = i / 20 * math.pi * 2
			box(hub, grassTop * CFrame.Angles(0, a, 0), Vector3.new(7.5, 0.2, 5.2), Vector3.new(0, 0, -17.5), STONE, Enum.Material.Slate)
		end
		for i = 1, Config.SHIP_COUNT do
			local a = (i - 1) / Config.SHIP_COUNT * math.pi * 2
			local f = grassTop * CFrame.Angles(0, a, 0)
			for k = 0, 11 do
				box(hub, f, Vector3.new(5.5, 0.2, 4), Vector3.new((k % 2) * 0.7 - 0.35, 0, 22 + k * 5.2), STONE, Enum.Material.Slate)
			end
		end
		local towerCols = { Color3.fromRGB(150, 90, 230), Color3.fromRGB(60, 160, 255), Color3.fromRGB(255, 120, 160), Color3.fromRGB(80, 200, 140) }
		for i = 0, 3 do
			local a = (i + 0.5) / 4 * math.pi * 2
			local tf = c * CFrame.Angles(0, a, 0) * CFrame.new(0, 5, -76)
			for k = 0, 4 do
				box(hub, tf, Vector3.new(6 - k * 0.3, 3, 6 - k * 0.3), Vector3.new(0, 1.5 + k * 3, 0), if k % 2 == 0 then Color3.fromRGB(245, 245, 250) else towerCols[i + 1])
			end
			for k = 0, 3 do
				box(hub, tf, Vector3.new(5 - k * 1.2, 1.6, 5 - k * 1.2), Vector3.new(0, 15.8 + k * 1.6, 0), towerCols[i + 1])
			end
			local tip = box(hub, tf, Vector3.new(1, 1, 1), Vector3.new(0, 22.6, 0), Color3.fromRGB(255, 230, 120), Enum.Material.Neon)
			local l = Instance.new("PointLight")
			l.Color = Color3.fromRGB(255, 230, 150)
			l.Range = 14
			l.Parent = tip
		end
		local flowerCols = { Color3.fromRGB(255, 90, 120), Color3.fromRGB(255, 210, 60), Color3.fromRGB(160, 110, 255), Color3.fromRGB(255, 255, 255) }
		for i = 0, 23 do
			local a = math.rad((i // 4) * 60 + (if i % 2 == 0 then 9 else -9))
			local ff = grassTop * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 34 + (i % 4) * 12)
			box(hub, ff, Vector3.new(0.8, 0.8, 0.8), Vector3.new(0, 0.4, 0), flowerCols[i % 4 + 1])
			box(hub, ff, Vector3.new(0.3, 0.5, 0.3), Vector3.new(0.9, 0.25, 0.4), Color3.fromRGB(70, 170, 70))
		end
		for i = 0, 15 do
			local a = (i + 0.5) / 16 * math.pi * 2
			local lf = grassTop * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -79)
			box(hub, lf, Vector3.new(0.5, 5, 0.5), Vector3.new(0, 2.5, 0), Color3.fromRGB(40, 44, 60))
			local lamp = box(hub, lf, Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 5.5, 0), Color3.fromRGB(255, 220, 130), Enum.Material.Neon)
			local pl = Instance.new("PointLight")
			pl.Color = Color3.fromRGB(255, 210, 140)
			pl.Range = 10
			pl.Brightness = 0.8
			pl.Parent = lamp
		end
	end

	-- docks from the island out towards every ship
	for i = 1, Config.SHIP_COUNT do
		local a = (i - 1) / Config.SHIP_COUNT * math.pi * 2
		local dirv = Vector3.new(math.sin(a), 0, math.cos(a))
		local from = WorldBuilder.hubCenter + dirv * (r - 4)
		local to = WorldBuilder.hubCenter + dirv * (Config.SHIP_RING_RADIUS - Config.SHIP_LENGTH / 2 - 3)
		local mid = (from + to) / 2
		local len = (to - from).Magnitude
		local dock = CFrame.lookAt(mid, to)
		box(hub, dock, Vector3.new(8, 1, len), Vector3.new(0, 2.5, 0), WOOD_LIGHT)
		for z = -len / 2 + 4, len / 2 - 4, 10 do
			for _, x in { -4.2, 4.2 } do
				box(hub, dock, Vector3.new(1.2, 6, 1.2), Vector3.new(x, 0.5, z), WOOD_DARK)
			end
		end
		-- a ramp up the bow so you can walk aboard
		local bow = WorldBuilder.hubCenter + dirv * (Config.SHIP_RING_RADIUS - Config.SHIP_LENGTH / 2 - 4)
		local top = WorldBuilder.hubCenter + dirv * (Config.SHIP_RING_RADIUS - Config.SHIP_LENGTH / 2 + 9)
		local p0 = bow + Vector3.new(0, 3, 0)
		local p1 = top + Vector3.new(0, Config.DECK_Y + 0.6, 0)
		local rmid = (p0 + p1) / 2
		box(hub, CFrame.lookAt(rmid, p1), Vector3.new(6, 0.8, (p1 - p0).Magnitude), Vector3.zero, WOOD)
	end

	-- a fallback spawn on the island
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = c * CFrame.new(0, 5.5, -26)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = hub
end

---------------------------------------------------------------------------
-- A ship
---------------------------------------------------------------------------
local function buildNest(parent: Instance, frame: CFrame, index: number): BasePart
	-- a shell nest: a sand pad with a ring of shell blocks
	local pad = box(parent, frame, Vector3.new(6, 0.6, 6), Vector3.new(0, 0.3, 0), Color3.fromRGB(245, 220, 170), Enum.Material.SmoothPlastic)
	pad.Name = "Nest" .. index
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local col = if i % 2 == 0 then Color3.fromRGB(255, 160, 170) else Color3.fromRGB(255, 205, 190)
		box(pad, frame * CFrame.Angles(0, a, 0), Vector3.new(2.6, 1.1, 1), Vector3.new(0, 0.85, 2.8), col)
	end
	pad:SetAttribute("NestIndex", index)
	return pad
end


local function boardPart(parent: Instance, frame: CFrame, pos: Vector3, name: string): BasePart
	-- a wooden notice board on two posts; the SurfaceGui is filled in by ShopService.
	-- The posts stop at the board's bottom edge (3.5 up; 0.1 tucked in, and thinner than the
	-- board) so no wood shows through the painted face.
	for _, x in { -3.6, 3.6 } do
		box(parent, frame, Vector3.new(0.5, 3.6, 0.4), pos + Vector3.new(x, 1.8, 0), WOOD_DARK)
	end
	local b = box(parent, frame, Vector3.new(8.6, 4.6, 0.5), pos + Vector3.new(0, 5.8, 0), WOOD_LIGHT)
	b.Name = name .. "Board"
	return b
end

-- Paint a title and a second line straight onto a board's front face (like the upgrade
-- boards), sized to the board so nothing stretches, floats or overlaps.
local function paintBoard(board: BasePart, title: string, sub: string, subColor: Color3)
	local g = Instance.new("SurfaceGui")
	g.Name = "Paint"
	g.Face = Enum.NormalId.Front
	g.CanvasSize = Vector2.new(math.floor(210 * board.Size.X / board.Size.Y), 210)
	g.LightInfluence = 0
	g.Parent = board
	local function line(text: string, y: number, h: number, color: Color3)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromOffset(22, y)
		t.Size = UDim2.new(1, -44, 0, h)
		t.Font = Enum.Font.FredokaOne
		t.TextScaled = true
		t.Text = text
		t.TextColor3 = color
		t.Parent = g
		local st = Instance.new("UIStroke")
		st.Thickness = 3
		st.Color = Color3.fromRGB(30, 20, 40)
		st.Parent = t
	end
	line(title, 22, 84, Color3.fromRGB(255, 255, 255))
	line(sub, 120, 64, subColor)
	-- a glowing neon rim says "this one is clickable"
	local S = board.Size
	local rimColor = Color3.fromRGB(255, 225, 60)
	local function bar(size: Vector3, offset: Vector3)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.Material = Enum.Material.Neon
		p.Color = rimColor
		p.Size = size
		p.CFrame = board.CFrame * CFrame.new(offset)
		p.Parent = board
	end
	local t, z = 0.35, -(S.Z / 2 + 0.05)
	bar(Vector3.new(S.X, t, 0.2), Vector3.new(0, S.Y / 2 - t / 2, z))
	bar(Vector3.new(S.X, t, 0.2), Vector3.new(0, -S.Y / 2 + t / 2, z))
	bar(Vector3.new(t, S.Y, 0.2), Vector3.new(S.X / 2 - t / 2, 0, z))
	bar(Vector3.new(t, S.Y, 0.2), Vector3.new(-S.X / 2 + t / 2, 0, z))
end

-- Boarding stairs: from the water (port side) up the hull (starboard has only the landing, for
-- the arena lookout pier)
-- to a gap in the rail, so nobody who jumped or swam off has to go round to the bow. Low visible
-- steps over a smooth invisible ramp (like the quarterdeck stairs). Crew only: invisible
-- "ShipGate<i>" walls (same collision group as the bow gate) close the foot and the open side.
-- Ship z values: ramp foot, ramp top / landing start, landing end (the rails stop at the same z).
local BOARD_Z0, BOARD_Z1, BOARD_Z2 = 4, 16.5, 23.5
-- Starboard has no stairs, only the landing the arena lookout pier leaves from: it sits on the
-- arena's centre line (Config.ARENA_OFFSET_Z), so the pier runs straight out at the hole.
local LAND_Z1, LAND_Z2 = Config.ARENA_OFFSET_Z - 3.5, Config.ARENA_OFFSET_Z + 3.5
local SHIP_BOW = 56 -- the straight hull (and the side rails) start this far forward of the middle

local function buildBoardingRamp(model: Model, cf: CFrame, index: number, sx: number, y0: number, stairs: boolean?)
	local W = Config.SHIP_WIDTH
	local top = Config.DECK_Y + 0.4 -- the deck planks
	if stairs == false then
		-- only the landing (starboard: the arena lookout pier leaves from its outer edge), railed
		-- along its bow and stern sides
		box(model, cf, Vector3.new(8, 0.8, LAND_Z2 - LAND_Z1), Vector3.new(sx * (W / 2 + 3), top - 0.4, (LAND_Z1 + LAND_Z2) / 2), WOOD_LIGHT)
		for _, z in { LAND_Z1 + 0.2, LAND_Z2 - 0.2 } do
			box(model, cf, Vector3.new(7, 0.4, 0.4), Vector3.new(sx * (W / 2 + 3.5), top + 2.6, z), WOOD_DARK, nil, { CanCollide = false })
			box(model, cf, Vector3.new(0.4, 2.8, 0.4), Vector3.new(sx * (W / 2 + 6.8), top + 1.4, z), WOOD_DARK, nil, { CanCollide = false })
			-- (an invisible wall under each rail: the drop to the sea is right below)
			box(model, cf, Vector3.new(7, 6, 0.4), Vector3.new(sx * (W / 2 + 3.5), top + 3, z), Color3.new(1, 1, 1), nil, { Transparency = 1, CanQuery = false, Name = "LandingWall" })
		end
		return
	end
	local rise = top - y0
	local run = BOARD_Z1 - BOARD_Z0
	local rw = 6.6
	local cx = sx * (W / 2 + 0.4 + rw / 2)
	local ox = sx * (W / 2 + 0.4 + rw - 0.2) -- the open (outer) edge
	local ramp = Instance.new("WedgePart")
	ramp.Name = "BoardRamp"
	ramp.Anchored = true
	ramp.Transparency = 1
	ramp.Size = Vector3.new(rw, rise, run)
	-- tallest at its +Z end: rises towards the stern, up to the landing
	ramp.CFrame = cf * CFrame.new(cx, y0 + rise / 2, BOARD_Z0 + run / 2)
	ramp.Parent = model
	for i = 0, 9 do
		local h = rise / 10 * (i + 1)
		box(model, cf, Vector3.new(rw, h, run / 10), Vector3.new(cx, y0 + h / 2, BOARD_Z0 + (i + 0.5) * run / 10), if i % 2 == 0 then WOOD_LIGHT else Color3.fromRGB(186, 130, 80), nil, { CanCollide = false })
	end
	-- landing slab, flush with the deck planks, spanning the gap in the rail
	box(model, cf, Vector3.new(8, 0.8, BOARD_Z2 - BOARD_Z1), Vector3.new(sx * (W / 2 + 3), top - 0.4, (BOARD_Z1 + BOARD_Z2) / 2), WOOD_LIGHT)
	-- handrail on the open side: sloped along the ramp, level along the landing, three posts
	local p0 = Vector3.new(ox, y0 + 2.6, BOARD_Z0)
	local p1 = Vector3.new(ox, top + 2.6, BOARD_Z1)
	box(model, cf * CFrame.lookAt((p0 + p1) / 2, p1), Vector3.new(0.4, 0.4, (p1 - p0).Magnitude), Vector3.zero, WOOD_DARK, nil, { CanCollide = false })
	box(model, cf, Vector3.new(0.4, 0.4, BOARD_Z2 - BOARD_Z1), Vector3.new(ox, top + 2.6, (BOARD_Z1 + BOARD_Z2) / 2), WOOD_DARK, nil, { CanCollide = false })
	box(model, cf, Vector3.new(8, 0.4, 0.4), Vector3.new(sx * (W / 2 + 3), top + 2.6, BOARD_Z2 - 0.2), WOOD_DARK, nil, { CanCollide = false })
	for _, post in { Vector3.new(ox, y0 + 1.4, BOARD_Z0), Vector3.new(ox, top + 1.4, BOARD_Z1), Vector3.new(ox, top + 1.4, BOARD_Z2 - 0.2) } do
		box(model, cf, Vector3.new(0.4, 2.8, 0.4), post, WOOD_DARK, nil, { CanCollide = false })
	end
	-- crew-only walls: the foot of the ramp and the whole open side
	local function gate(size: Vector3, pos: Vector3)
		box(model, cf, size, pos, Color3.new(1, 1, 1), nil, { Transparency = 1, CanQuery = false, Name = "RampGate", CollisionGroup = "ShipGate" .. index })
	end
	gate(Vector3.new(rw + 0.4, 24, 0.6), Vector3.new(cx, 10, BOARD_Z0))
	gate(Vector3.new(0.6, 24, BOARD_Z2 - BOARD_Z0 + 0.6), Vector3.new(sx * (W / 2 + 0.4 + rw + 0.3), 10, (BOARD_Z0 + BOARD_Z2) / 2))
end

-- The arena lookout: a pier off the starboard boarding landing that climbs to a railed platform
-- over the ship side of the reef, so the crew watch the fight from above, looking down into the
-- blue hole. Ship space: the starboard landing spans z LAND_Z1..LAND_Z2 and ends at x = W / 2 + 7.
-- pier, ramp, platform (ship x). A short pier: the platform sits at the reef's outer edge, 58
-- studs short of the arena's centre (the hole's rim is at 44), with your team just in front of it.
local LOOK_X0, LOOK_RAMP0, LOOK_RAMP1, LOOK_X1 = Config.SHIP_WIDTH / 2 + 7, 43, 46, Config.ARENA_OFFSET - 58
local LOOK_RISE = 2 -- the platform stands this much above the deck

local function buildLookout(parent: Instance, shipCf: CFrame, arenaCf: CFrame)
	local top = Config.DECK_Y + 0.4
	local high = top + LOOK_RISE
	local zc = (LAND_Z1 + LAND_Z2) / 2
	-- The landing sits on the arena's centre line, so the pier runs straight out along +X. (If the
	-- arena ever moves off that line, the pier still aims at its centre: it turns about its start.)
	local a = shipCf:PointToObjectSpace(arenaCf.Position)
	local yaw = math.atan2(-(a.Z - zc), a.X - LOOK_X0)
	local cf = shipCf * CFrame.new(LOOK_X0, 0, zc) * CFrame.Angles(0, yaw, 0) * CFrame.new(-LOOK_X0, 0, -zc)
	local pw = LAND_Z2 - LAND_Z1 -- pier width (z)
	local platW = 15 -- platform width (z)
	local function plank(size: Vector3, pos: Vector3, i: number)
		box(parent, cf, size, pos, if i % 2 == 0 then WOOD_LIGHT else Color3.fromRGB(186, 130, 80), Enum.Material.WoodPlanks)
	end
	-- the pier, level with the deck
	local n = math.max(1, math.floor((LOOK_RAMP0 - LOOK_X0) / 2))
	for i = 0, n - 1 do
		local x0 = LOOK_X0 + (LOOK_RAMP0 - LOOK_X0) * i / n
		local x1 = LOOK_X0 + (LOOK_RAMP0 - LOOK_X0) * (i + 1) / n
		plank(Vector3.new(x1 - x0 - 0.1, 0.8, pw), Vector3.new((x0 + x1) / 2, top - 0.4, zc), i)
	end
	-- the ramp up: visible steps over an invisible wedge (smooth to walk)
	local run = LOOK_RAMP1 - LOOK_RAMP0
	local ramp = Instance.new("WedgePart")
	ramp.Name = "LookoutRamp"
	ramp.Anchored = true
	ramp.Transparency = 1
	ramp.Size = Vector3.new(pw, LOOK_RISE, run)
	-- tallest at its +Z end, so its +Z must point out along +X (away from the ship)
	ramp.CFrame = cf * CFrame.new((LOOK_RAMP0 + LOOK_RAMP1) / 2, top + LOOK_RISE / 2, zc) * CFrame.Angles(0, math.pi / 2, 0)
	ramp.Parent = parent
	for i = 0, 9 do
		local h = LOOK_RISE / 10 * (i + 1)
		box(parent, cf, Vector3.new(run / 10, h, pw), Vector3.new(LOOK_RAMP0 + (i + 0.5) * run / 10, top + h / 2 - 0.4, zc), if i % 2 == 0 then WOOD_LIGHT else Color3.fromRGB(186, 130, 80), Enum.Material.WoodPlanks, { CanCollide = false })
	end
	-- the platform
	local px = (LOOK_RAMP1 + LOOK_X1) / 2
	local pl = LOOK_X1 - LOOK_RAMP1
	for i = 0, 3 do
		plank(Vector3.new(pl / 4 - 0.1, 0.8, platW), Vector3.new(LOOK_RAMP1 + (i + 0.5) * pl / 4, high - 0.4, zc), i)
	end
	-- rails: along both sides of the pier, the ramp and the platform; the platform's front, facing
	-- the hole, is left open (an invisible wall still keeps people on it)
	local railH = 2.8
	local function rail(a: Vector3, b: Vector3)
		box(parent, cf * CFrame.lookAt((a + b) / 2, b), Vector3.new(0.4, 0.4, (b - a).Magnitude), Vector3.zero, WOOD_DARK, nil, { CanCollide = false })
	end
	local function post(p: Vector3, h: number)
		box(parent, cf, Vector3.new(0.5, h, 0.5), p + Vector3.new(0, h / 2, 0), WOOD_DARK)
	end
	-- a ladder up each side of the platform, out of the sea, so anyone who fell or swam off can
	-- climb back up (the side rails and walls leave a gap at the top of it)
	local LADDER_W = 2.4 -- between the ladder's two uprights (x)
	local gap0, gap1 = px - LADDER_W / 2 - 0.3, px + LADDER_W / 2 + 0.3
	for _, s in { -1, 1 } do
		local z = zc + s * (pw / 2 - 0.2)
		rail(Vector3.new(LOOK_X0, top + railH, z), Vector3.new(LOOK_RAMP0, top + railH, z))
		rail(Vector3.new(LOOK_RAMP0, top + railH, z), Vector3.new(LOOK_RAMP1, high + railH, z))
		post(Vector3.new(LOOK_RAMP0, top, z), railH)
		local zp = zc + s * (platW / 2 - 0.2)
		rail(Vector3.new(LOOK_RAMP1, high + railH, zp), Vector3.new(gap0, high + railH, zp))
		rail(Vector3.new(gap1, high + railH, zp), Vector3.new(LOOK_X1, high + railH, zp))
		rail(Vector3.new(LOOK_RAMP1, high + railH, zp), Vector3.new(LOOK_RAMP1, high + railH, z))
		post(Vector3.new(LOOK_RAMP1, high, zp), railH)
		post(Vector3.new(LOOK_X1 - 0.2, high, zp), railH)

		-- The ladder hangs off the platform's edge. The climbing is an invisible TrussPart (Roblox
		-- climbs those on its own, even straight out of a swim); the wood you see sits inside it.
		local edge = zc + s * (platW / 2)
		local bottom = -6.6 -- well under the surface, so a swimmer bumps into it
		local trussH = high - bottom -- 18: TrussPart sizes snap to multiples of 2
		local truss = Instance.new("TrussPart")
		truss.Name = "LookoutLadder"
		truss.Anchored = true
		truss.Transparency = 1
		truss.CastShadow = false
		truss.Style = Enum.Style.NoSupports
		truss.Size = Vector3.new(2, trussH, 2)
		truss.CFrame = cf * CFrame.new(px, bottom + trussH / 2, edge + s * 1)
		truss.Parent = parent
		local lz = edge + s * 1.5 -- the visible ladder, near the truss's outer face
		-- two uprights from under the water to handrail height (they are the gap's rail posts too)
		for _, sxl in { -1, 1 } do
			local x = px + sxl * LADDER_W / 2
			local y1 = high + railH
			box(parent, cf, Vector3.new(0.4, y1 - bottom, 0.4), Vector3.new(x, (y1 + bottom) / 2, lz), WOOD_DARK, Enum.Material.Wood, { CanCollide = false })
		end
		-- rungs, from just under the surface up to the platform
		for y = -0.8, high - 0.6, 1.3 do
			box(parent, cf, Vector3.new(LADDER_W, 0.3, 0.3), Vector3.new(px, y, lz), WOOD_LIGHT, Enum.Material.Wood, { CanCollide = false })
		end
		-- A step at the ladder's foot, flush with the sea: Roblox can't start a climb from a swim, so
		-- a swimmer climbs out onto this (like the port boarding stairs' foot) and climbs from there.
		local stepZ = edge + s * 3.6
		box(parent, cf, Vector3.new(4.4, 0.6, 3.2), Vector3.new(px, 0.1, stepZ), WOOD_LIGHT, Enum.Material.WoodPlanks)
		for _, sxl in { -1, 1 } do
			-- on the inner edge (by the ladder), out of a swimmer's way
			box(parent, cf, Vector3.new(0.5, 6, 0.5), Vector3.new(px + sxl * 1.9, -3, stepZ - s * 1.2), WOOD_DARK, Enum.Material.Wood)
		end
		-- an invisible slope under the water up to the step, so a swimmer's feet always catch it
		-- (a bare 1-stud lip only worked some of the time)
		local slopeRun, slopeRise = 4, 3.4
		local slope = Instance.new("WedgePart")
		slope.Name = "LadderSlope"
		slope.Anchored = true
		slope.Transparency = 1
		slope.CanQuery = false
		slope.Size = Vector3.new(4.4, slopeRise, slopeRun)
		-- a wedge is tallest at its +Z end: face that end toward the step (in toward the platform)
		local slopeZ = stepZ + s * (1.6 + slopeRun / 2)
		slope.CFrame = cf * CFrame.new(px, 0.4 - slopeRise / 2, slopeZ) * CFrame.Angles(0, if s > 0 then math.pi else 0, 0)
		slope.Parent = parent
	end
	-- invisible walls keep everyone on the platform (the rails are only knee-high to a jump), with
	-- a gap on each side over the ladder
	local walls = { { Vector3.new(0.6, 8, platW), Vector3.new(LOOK_X1, high + 4, zc) } }
	for _, s in { -1, 1 } do
		local zw = zc + s * platW / 2
		table.insert(walls, { Vector3.new(gap0 - LOOK_RAMP1, 8, 0.6), Vector3.new((LOOK_RAMP1 + gap0) / 2, high + 4, zw) })
		table.insert(walls, { Vector3.new(LOOK_X1 - gap1, 8, 0.6), Vector3.new((gap1 + LOOK_X1) / 2, high + 4, zw) })
	end
	for _, w in walls do
		box(parent, cf, w[1], w[2], Color3.new(1, 1, 1), nil, { Transparency = 1, CanQuery = false, Name = "LookoutWall" })
	end
	-- stilts down into the sea
	for _, p in {
		Vector3.new(LOOK_RAMP0, 0, zc - pw / 2 + 0.4), Vector3.new(LOOK_RAMP0, 0, zc + pw / 2 - 0.4),
		Vector3.new(LOOK_RAMP1, 0, zc - platW / 2 + 0.6), Vector3.new(LOOK_RAMP1, 0, zc + platW / 2 - 0.6),
		Vector3.new(LOOK_X1 - 0.6, 0, zc - platW / 2 + 0.6), Vector3.new(LOOK_X1 - 0.6, 0, zc + platW / 2 - 0.6),
	} do
		local yTop = if p.X > LOOK_RAMP0 + 1 then high - 0.8 else top - 0.8
		box(parent, cf, Vector3.new(1.1, yTop + 6, 1.1), Vector3.new(p.X, (yTop - 6) / 2, p.Z), WOOD_DARK, Enum.Material.Wood)
	end
	-- lanterns on the platform's outer corners
	for _, s in { -1, 1 } do
		local base = Vector3.new(LOOK_X1 - 0.6, high, zc + s * (platW / 2 - 0.6))
		box(parent, cf, Vector3.new(0.5, 4.2, 0.5), base + Vector3.new(0, 2.1, 0), WOOD_DARK, Enum.Material.Wood)
		-- (not Neon: with the sky's bloom a Neon lamp this close to the camera glows into a blob)
		local lamp = box(parent, cf, Vector3.new(1.1, 1.3, 1.1), base + Vector3.new(0, 4.8, 0), Color3.fromRGB(255, 226, 150), Enum.Material.SmoothPlastic, { CanCollide = false })
		local light = Instance.new("PointLight")
		light.Range = 12
		light.Brightness = 1.2
		light.Color = Color3.fromRGB(255, 206, 120)
		light.Parent = lamp
		box(parent, cf, Vector3.new(1.4, 0.3, 1.4), base + Vector3.new(0, 5.6, 0), WOOD_DARK, nil, { CanCollide = false })
	end
end

local function buildShip(world: Folder, index: number): Ship
	local angle =(index - 1) / Config.SHIP_COUNT * math.pi * 2
	local center = Vector3.new(math.sin(angle) * Config.SHIP_RING_RADIUS, Config.SEA_LEVEL, math.cos(angle) * Config.SHIP_RING_RADIUS)
	local cf = CFrame.lookAt(center, Vector3.new(0, Config.SEA_LEVEL, 0))
	local model = Instance.new("Model")
	model.Name = "Ship" .. index
	model.Parent = world

	local L, W = Config.SHIP_LENGTH, Config.SHIP_WIDTH
	local deck = Config.DECK_Y
	local hullBottom = -6
	local hullH = deck - hullBottom
	local sternZ = L / 2
	local BOW = SHIP_BOW -- the straight hull starts this far forward of the middle
	-- main hull (z from -BOW to stern) and a bow narrowing in steps
	box(model, cf, Vector3.new(W, hullH, sternZ + BOW), Vector3.new(0, hullBottom + hullH / 2, (sternZ - BOW) / 2), WOOD)
	local bowSteps = { { z = -58.5, w = W - 10 }, { z = -63.5, w = W - 24 }, { z = -68.5, w = W - 40 }, { z = -73.5, w = 14 } }
	for _, s in bowSteps do
		box(model, cf, Vector3.new(s.w, hullH - 1, 5), Vector3.new(0, hullBottom + hullH / 2 + 0.5, s.z), WOOD)
		box(model, cf, Vector3.new(s.w - 1.5, 0.4, 5), Vector3.new(0, deck + 0.2, s.z), WOOD_LIGHT)
	end
	-- stripe and portholes
	-- the stripe sticks out 0.15 past both hull ends so its end faces are never coplanar with the
	-- hull's (that was the yellow flicker)
	box(model, cf, Vector3.new(W + 0.4, 1.4, sternZ + BOW + 0.3), Vector3.new(0, deck - 3, (sternZ - BOW) / 2), Color3.fromRGB(245, 205, 70), nil, { Name = "HullStripe" })
	for z = -48, 76, 8 do
		for _, sx in { -1, 1 } do
			box(model, cf, Vector3.new(0.4, 1.8, 1.8), Vector3.new(sx * (W / 2 + 0.1), deck - 6, z), Color3.fromRGB(40, 44, 70))
		end
	end
	-- deck planks, up to the quarterdeck: under it they were hidden, but their back ends stopped
	-- 0.1 short of the stern face and flickered through it
	-- (the last one may tuck a little under the quarterdeck's front so there's never a gap)
	for z = -BOW, Config.QUARTERDECK_Z - 2, 4 do
		box(model, cf, Vector3.new(W - 2, 0.4, 3.8), Vector3.new(0, deck + 0.2, z + 2), if (z // 4) % 2 == 0 then WOOD_LIGHT else Color3.fromRGB(186, 130, 80))
	end
	-- rails, with a gap on each side: port where the boarding stairs come up (BOARD_Z1..BOARD_Z2),
	-- starboard where the arena lookout pier leaves (LAND_Z1..LAND_Z2). They stop at the quarterdeck:
	-- running on inside it, their outer faces lay exactly on its side walls and flickered there
	-- (the quarterdeck's own walls close the main deck at the stern, so it needs no stern rail).
	for _, sx in { -1, 1 } do
		local g1, g2 = if sx < 0 then BOARD_Z1 else LAND_Z1, if sx < 0 then BOARD_Z2 else LAND_Z2
		for _, seg in { { -BOW, g1 }, { g2, Config.QUARTERDECK_Z } } do
			box(model, cf, Vector3.new(1, 3, seg[2] - seg[1]), Vector3.new(sx * (W / 2 - 0.5), deck + 1.9, (seg[1] + seg[2]) / 2), WOOD_DARK)
		end
	end

	-- quarterdeck (Floor 2): raised stern with stairs
	local qz0 = Config.QUARTERDECK_Z
	local qLen = sternZ - qz0
	local up = Config.UPPER_DECK_Y
	box(model, cf, Vector3.new(W, up - deck, qLen), Vector3.new(0, deck + (up - deck) / 2, qz0 + qLen / 2), WOOD)
	box(model, cf, Vector3.new(W - 2, 0.4, qLen - 1), Vector3.new(0, up + 0.2, qz0 + qLen / 2), WOOD_LIGHT)
	for _, sx in { -1, 1 } do
		box(model, cf, Vector3.new(1, 3, qLen), Vector3.new(sx * (W / 2 - 0.5), up + 1.9, qz0 + qLen / 2), WOOD_DARK)
	end
	box(model, cf, Vector3.new(W, 3, 1), Vector3.new(0, up + 1.9, sternZ - 0.5), WOOD_DARK)
	-- stairs: ten low steps you can see, and a smooth invisible ramp you actually walk on
	-- (tall block steps made characters stutter)
	local rise = up - deck
	for i = 0, 9 do
		local h = rise / 10 * (i + 1)
		box(model, cf, Vector3.new(12, h, 1.4), Vector3.new(0, deck + h / 2, qz0 - 14 + i * 1.4 + 0.7), if i % 2 == 0 then WOOD_LIGHT else Color3.fromRGB(186, 130, 80), nil, { CanCollide = false })
	end
	do
		local run = 14
		local ramp = Instance.new("WedgePart")
		ramp.Name = "StairRamp"
		ramp.Anchored = true
		ramp.Transparency = 1
		ramp.Size = Vector3.new(12, rise, run)
		-- a wedge is tallest at its +Z end, which is the stern side: it rises up to the quarterdeck
		ramp.CFrame = cf * CFrame.new(0, deck + rise / 2, qz0 - run / 2)
		ramp.Parent = model
	end
	-- A clean glass panel (not ForceField: its shimmer flickered). It sits in FRONT of the rail posts
	-- (they are at z qz0 - 14) and its feet are a hair above the deck, so nothing pokes through it or
	-- shares a plane with it; it is 12 wide, filling the gap between the stair side walls.
	local barrier = box(model, cf, Vector3.new(12, 11.9, 0.6), Vector3.new(0, deck + 0.05 + 11.9 / 2, qz0 - 15.2), Color3.fromRGB(150, 215, 255), Enum.Material.Glass, { Transparency = 0.5, Name = "Floor2Barrier" })
	-- the main mast stands right in front of this gate, so the sign draws over it (AlwaysOnTop;
	-- it still only shows within the label's MaxDistance)
	label(barrier, "FLOOR LOCKED", UDim2.fromOffset(190, 40), Vector3.new(0, 7.5, 0), Color3.fromRGB(255, 220, 80)).AlwaysOnTop = true
	-- Permanent, invisible, tall walls so the gate can't be hopped round (they never open, for anyone;
	-- the owner walks up the middle of the stairs between them): one along each side of the stairs,
	-- and one across the foot of the quarterdeck from the stairs to each rail, so nobody can jump
	-- onto the stairs from the sides or walk along a rail top and drop onto the quarterdeck.
	local function solid(size: Vector3, pos: Vector3, name: string)
		box(model, cf, size, pos, Color3.new(1, 1, 1), nil, { Transparency = 1, CanQuery = false, Name = name })
	end
	local stairLen = qz0 - (qz0 - 14.5) -- the barrier's z to the quarterdeck face
	for _, sx in { -1, 1 } do
		solid(Vector3.new(1, 24, stairLen), Vector3.new(sx * 6.5, deck + 9, qz0 - stairLen / 2), "StairWall")
		solid(Vector3.new(W / 2 - 6.5 + 0.5, 26, 1), Vector3.new(sx * ((W / 2 + 0.5 + 7) / 2), deck + 12, qz0), "QuarterFaceWall")
		-- a visible wooden rail along the open edge of the stairs
		local a = Vector3.new(sx * 6.3, deck + 3, qz0 - 14)
		local b = Vector3.new(sx * 6.3, up + 3, qz0)
		box(model, cf * CFrame.lookAt((a + b) / 2, b), Vector3.new(0.5, 0.5, (b - a).Magnitude), Vector3.zero, WOOD_DARK, nil, { CanCollide = false })
		box(model, cf, Vector3.new(0.6, 3.2, 0.6), Vector3.new(sx * 6.3, deck + 1.6, qz0 - 14), WOOD_DARK, nil, { CanCollide = false })
		box(model, cf, Vector3.new(0.6, 3.2, 0.6), Vector3.new(sx * 6.3, up + 1.6, qz0 - 0.4), WOOD_DARK, nil, { CanCollide = false })
	end

	-- Floor 3: the poop deck, a platform over the stern on posts, reached by starboard stairs that
	-- start on the quarterdeck. 4 nests live up here; a force-field gate keeps it shut until bought.
	local f3 = Config.FLOOR3_Y
	local p3z0 = 72 -- front edge of the platform
	local p3len = sternZ - p3z0
	local rise3 = f3 - up
	box(model, cf, Vector3.new(62, 1, p3len), Vector3.new(0, f3 - 0.5, p3z0 + p3len / 2), WOOD)
	box(model, cf, Vector3.new(60, 0.4, p3len - 1), Vector3.new(0, f3 + 0.2, p3z0 + p3len / 2), WOOD_LIGHT)
	for _, px in { -29, 0, 29 } do
		for _, pz in { p3z0 + 2, sternZ - 2 } do
			box(model, cf, Vector3.new(1.6, rise3 - 1, 1.6), Vector3.new(px, up + (rise3 - 1) / 2, pz), WOOD_DARK)
		end
	end
	-- rails: front (open at the stairs), port, starboard and stern
	box(model, cf, Vector3.new(53, 3, 0.6), Vector3.new(-4.5, f3 + 1.9, p3z0), WOOD_DARK)
	for _, sx in { -1, 1 } do
		box(model, cf, Vector3.new(0.6, 3, p3len), Vector3.new(sx * 31, f3 + 1.9, p3z0 + p3len / 2), WOOD_DARK)
	end
	-- the stern rail has a gap in the middle onto the Abyss Rod's balcony
	local BAL_HALF = 14
	local balZ1 = sternZ + 17 -- back edge of the balcony
	for _, sx in { -1, 1 } do
		box(model, cf, Vector3.new(31 - BAL_HALF, 3, 0.6), Vector3.new(sx * (31 + BAL_HALF) / 2, f3 + 1.9, sternZ - 0.3), WOOD_DARK)
	end
	-- the Abyss Rod balcony: hangs off the stern at Floor 3 height, held up by braces on the hull
	box(model, cf, Vector3.new(BAL_HALF * 2, 1, balZ1 - sternZ), Vector3.new(0, f3 - 0.5, (sternZ + balZ1) / 2), WOOD, nil, { Name = "AbyssBalcony" })
	box(model, cf, Vector3.new(BAL_HALF * 2 - 2, 0.4, balZ1 - sternZ - 1), Vector3.new(0, f3 + 0.2, (sternZ + balZ1) / 2 - 0.5), WOOD_LIGHT)
	for _, sx in { -1, 1 } do
		box(model, cf, Vector3.new(0.6, 3, balZ1 - sternZ), Vector3.new(sx * BAL_HALF, f3 + 1.9, (sternZ + balZ1) / 2), WOOD_DARK)
		-- a diagonal brace from the hull up under the balcony's back corner
		local a = Vector3.new(sx * (BAL_HALF - 2), deck - 4, sternZ - 0.5)
		local b = Vector3.new(sx * (BAL_HALF - 2), f3 - 1, balZ1 - 2)
		box(model, cf * CFrame.lookAt((a + b) / 2, b), Vector3.new(1.4, 1.4, (b - a).Magnitude), Vector3.zero, WOOD_DARK)
	end
	box(model, cf, Vector3.new(BAL_HALF * 2, 3, 0.6), Vector3.new(0, f3 + 1.9, balZ1 - 0.3), WOOD_DARK)
	-- stairs (ten visible steps and a smooth invisible ramp to walk on, like the quarterdeck's)
	for i = 0, 9 do
		local h = rise3 / 10 * (i + 1)
		box(model, cf, Vector3.new(5, h, 1.4), Vector3.new(28.5, up + h / 2, p3z0 - 14 + i * 1.4 + 0.7), if i % 2 == 0 then WOOD_LIGHT else Color3.fromRGB(186, 130, 80), nil, { CanCollide = false })
	end
	do
		local ramp3 = Instance.new("WedgePart")
		ramp3.Name = "StairRamp3"
		ramp3.Anchored = true
		ramp3.Transparency = 1
		ramp3.Size = Vector3.new(5, rise3, 14)
		ramp3.CFrame = cf * CFrame.new(28.5, up + rise3 / 2, p3z0 - 7)
		ramp3.Parent = model
	end
	-- the same clean glass gate (see Floor2Barrier): in front of the rail posts (z p3z0 - 14), 5 wide
	-- between the stair side walls (x 26..31), feet a hair above the quarterdeck
	local barrier3 = box(model, cf, Vector3.new(5, 11.9, 0.6), Vector3.new(28.5, up + 0.05 + 11.9 / 2, p3z0 - 15.2), Color3.fromRGB(150, 215, 255), Enum.Material.Glass, { Transparency = 0.5, Name = "Floor3Barrier" })
	label(barrier3, "FLOOR 3 LOCKED", UDim2.fromOffset(210, 40), Vector3.new(0, 7.5, 0), Color3.fromRGB(255, 220, 80)).AlwaysOnTop = true
	-- the same permanent invisible side walls for the Floor 3 stairs (x 26..31 on the quarterdeck;
	-- the outer one fills the gap up to the quarterdeck rail). They start at the gate and run up to
	-- the platform's front edge, and reach well above a jump from the quarterdeck rail top.
	do
		local z0, z1 = p3z0 - 15, p3z0
		local wallY = up + 9
		solid(Vector3.new(1, 24, z1 - z0), Vector3.new(25.5, wallY, (z0 + z1) / 2), "Stair3Wall")
		solid(Vector3.new(2.4, 24, z1 - z0), Vector3.new(32.2, wallY, (z0 + z1) / 2), "Stair3Wall")
		for _, x in { 26.3, 30.7 } do
			local a = Vector3.new(x, up + 3, p3z0 - 14)
			local b = Vector3.new(x, f3 + 3, p3z0)
			box(model, cf * CFrame.lookAt((a + b) / 2, b), Vector3.new(0.5, 0.5, (b - a).Magnitude), Vector3.zero, WOOD_DARK, nil, { CanCollide = false })
			box(model, cf, Vector3.new(0.6, 3.2, 0.6), Vector3.new(x, up + 1.6, p3z0 - 14), WOOD_DARK, nil, { CanCollide = false })
			box(model, cf, Vector3.new(0.6, 3.2, 0.6), Vector3.new(x, f3 + 1.6, p3z0 - 0.4), WOOD_DARK, nil, { CanCollide = false })
		end
	end

	-- mast and sail
	local mp = Config.MAST_POS
	box(model, cf, Vector3.new(2.6, 58, 2.6), Vector3.new(mp.X, deck + 29, mp.Z), WOOD_DARK)
	box(model, cf, Vector3.new(38, 1, 1), Vector3.new(mp.X, deck + 48, mp.Z), WOOD_DARK)
	box(model, cf, Vector3.new(36, 24, 0.4), Vector3.new(mp.X, deck + 36, mp.Z - 0.6), SAIL, nil, { Name = "SailCloth" })
	box(model, cf, Vector3.new(12, 12, 0.45), Vector3.new(mp.X, deck + 36, mp.Z - 0.65), Color3.fromRGB(40, 150, 230))
	box(model, cf, Vector3.new(7, 1, 7), Vector3.new(mp.X, deck + 52, mp.Z), WOOD)
	local flag = box(model, cf, Vector3.new(0.2, 4, 7), Vector3.new(mp.X, deck + 58, mp.Z + 3.5), Color3.fromRGB(240, 60, 60))
	flag.Name = "Flag"

	-- nests
	local nests = {}
	for i, slot in Config.NEST_SLOTS do
		local y = if slot.floor == 3 then Config.FLOOR3_Y elseif slot.floor == 2 then up else deck
		local frame = cf * CFrame.new(slot.pos.X, y + 0.4, slot.pos.Z)
		local pad = buildNest(model, frame, i)
		local pp = prompt(pad, "Place Egg", "Nest", 0, 9)
		pp.Name = "NestPrompt"
		nests[i] = pad
	end

	-- fishing station at the port rail: a rod on a stand that casts out to sea for eggs.
	-- The client animates the Rod model's parts (see BattleView "haul").
	-- built twice: the Egg Rod (port) and the Deep Rod (starboard, Config.DEEP_ROD)
	local function rodStation(wp: Vector3, yaw: number, rodName: string, hitName: string, promptName: string, objectText: string, signText: string, ringColor: Color3, rodColor: Color3, floorY: number?, style: string)
	local winchFrame = cf * CFrame.new(wp.X, (floorY or deck) + 0.4, wp.Z)
	local S = Config.ROD_SCALE
	local rodFrame = winchFrame * CFrame.new(0, 4.2 * S, 0) * CFrame.Angles(0, math.rad(yaw), 0) -- rod points -Z = out over the rail
	-- a round fishing platform with a glowing gold ring so the station stands out on deck
	local plat = box(model, winchFrame, Vector3.new(1.2, 12, 12), Vector3.new(0, 0.6, 0), WOOD_DARK)
	plat.Shape = Enum.PartType.Cylinder
	plat.CFrame = winchFrame * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(90))
	for k = 0, 15 do
		local a = k / 16 * math.pi * 2
		box(model, winchFrame * CFrame.Angles(0, a, 0), Vector3.new(2.2, 0.25, 0.5), Vector3.new(0, 1.3, 6.2), ringColor, Enum.Material.Neon, { CanCollide = false })
	end
	box(model, winchFrame, Vector3.new(1.4 * S, 4.2 * S - 1.2, 1.4 * S), Vector3.new(0, 1.2 + (4.2 * S - 1.2) / 2, 0), WOOD)
	local rod = Instance.new("Model")
	rod.Name = rodName
	rod.Parent = model
	rod:SetAttribute("RodCf", rodFrame)
	-- rest pose = frame 0 of the Blender rod animation (shared/RodAnim)
	local RodAnim = require(ReplicatedStorage.Shared.RodAnim)
	local function rest(name: string): CFrame
		local a = RodAnim.Tracks[name]
		return rodFrame * CFrame.new(a[1] * S, a[2] * S, a[3] * S, a[4], a[5], a[6], a[7])
	end
	local function rodPart(name: string, size: Vector3, color: Color3, mat: Enum.Material?): BasePart
		return part({ Name = name, Size = size * S, CFrame = rest(name), Color = color, Material = mat or Enum.Material.SmoothPlastic, CanCollide = false, Parent = rod })
	end
	local st = ROD_STYLES[style]
	rodPart("RodHandle", Vector3.new(0.9, 0.9, 5), st.handle, st.handleMat)
	rodPart("RodS1", Vector3.new(0.55, 0.55, 7.6), st.blank, st.blankMat)
	rodPart("RodS2", Vector3.new(0.5, 0.5, 7.5), st.blank, st.blankMat)
	rodPart("RodS3", Vector3.new(0.35, 0.35, 7.6), rodColor, st.tipMat)
	local reel = rodPart("RodReel", Vector3.new(1.6, 1.6, 1.6), st.reel or ringColor, st.reelMat)
	reel.Shape = Enum.PartType.Ball
	if st.reelTransparency then
		reel.Transparency = st.reelTransparency
	end
	-- trim: extra parts that ride on one section (the client re-poses them during the cast from
	-- their Follow + Offset attributes; Spin = the crank, which turns about the reel's axle)
	local function trim(seg: string, size: Vector3, pos: Vector3, color: Color3, mat: Enum.Material?, extra: { [string]: any }?, rot: CFrame?): BasePart
		local off = CFrame.new(pos * S) * (rot or CFrame.identity)
		local props: { [string]: any } = { Name = seg .. "Trim", Size = size * S, CFrame = rest(seg) * off, Color = color, Material = mat or Enum.Material.SmoothPlastic, CanCollide = false, CanQuery = false, CastShadow = false, Parent = rod }
		if extra then
			for k, v in extra do
				props[k] = v
			end
		end
		local p = part(props)
		p:SetAttribute("Follow", seg)
		p:SetAttribute("Offset", off)
		return p
	end
	local ALONG = CFrame.Angles(0, math.rad(90), 0) -- a cylinder's axis (X) turned to run along the rod (Z)
	-- a ring around a section (z: along the section, -Z is towards the tip)
	local function band(seg: string, width: number, z: number, len: number, color: Color3, mat: Enum.Material?)
		return trim(seg, Vector3.new(len, width, width), Vector3.new(0, 0, z), color, mat, { Shape = Enum.PartType.Cylinder }, ALONG)
	end
	-- a line guide: a little stand-off under the blank with an eyelet ring
	local function guide(seg: string, width: number, z: number, color: Color3, mat: Enum.Material?)
		trim(seg, Vector3.new(0.08, 0.28, 0.08), Vector3.new(0, -(width / 2 + 0.12), z), color, mat)
		trim(seg, Vector3.new(0.07, 0.34, 0.34), Vector3.new(0, -(width / 2 + 0.36), z), color, mat, { Shape = Enum.PartType.Cylinder }, ALONG)
	end
	-- the reel crank: an arm and a knob on the outside of the reel that winds during the haul
	local function crank(color: Color3, knob: Color3, mat: Enum.Material?, knobMat: Enum.Material?)
		trim("RodReel", Vector3.new(0.3, 0.55, 0.55), Vector3.new(0.92, 0, 0), color, mat, { Shape = Enum.PartType.Cylinder })
		trim("RodReel", Vector3.new(0.14, 1.1, 0.22), Vector3.new(1.08, 0.42, 0), color, mat, { Name = "CrankArm" }):SetAttribute("Spin", true)
		trim("RodReel", Vector3.new(0.4, 0.4, 0.4), Vector3.new(1.2, 0.9, 0), knob, knobMat, { Shape = Enum.PartType.Ball, Name = "CrankKnob" }):SetAttribute("Spin", true)
	end
	st.trim(trim, band, guide, crank, ALONG, ringColor, rodColor)
	local winch = box(model, winchFrame, Vector3.new(10, 8, 10), Vector3.new(0, 4, 0), Color3.new(1, 1, 1), nil, { Transparency = 1, CanCollide = false, Name = hitName })
	local wpp = prompt(winch, "Fish", objectText, 0.35, 14)
	wpp.Name = promptName
	local sign = label(winch, signText, UDim2.fromOffset(360, 70), Vector3.new(0, 13, 0), ringColor)
	sign.MaxDistance = 260
	return winch, sign
	end
	local winch = rodStation(Config.WINCH_POS, 90, "Rod", "Winch", "WinchPrompt", "Egg Rod", "FISH FOR EGGS!", Color3.fromRGB(255, 210, 70), Color3.fromRGB(255, 120, 90), nil, "egg")
	-- the Deep Rod: points out over the starboard rail. Its sign is rewritten by the owner's
	-- client (DeepRodView) with the unlock / cooldown countdown.
	local deepWinch, dsign = rodStation(Config.DEEP_ROD.pos, -90, "DeepRod", "DeepWinch", "DeepRodPrompt", "Deep Rod", "DEEP ROD", Color3.fromRGB(150, 110, 255), Color3.fromRGB(120, 230, 255), nil, "deep")
	dsign.Name = "DeepSign"
	-- the Abyss Rod: on the Floor 3 balcony, pointing straight out astern. Its sign is rewritten by
	-- the owner's client (ShipView) with Floor 3 / unlock / cooldown.
	local abyssWinch, asign = rodStation(Config.ABYSS_ROD.pos, 180, "AbyssRod", "AbyssWinch", "AbyssRodPrompt", "Abyss Rod", "ABYSS ROD", Color3.fromRGB(255, 60, 150), Color3.fromRGB(255, 120, 220), f3, "abyss")
	asign.Name = "AbyssSign"

	-- egg pedestals
	local pedestals = {}
	for i, pp in Config.PEDESTAL_POS do
		local frame = cf * CFrame.new(pp.X, deck + 0.4, pp.Z)
		local ped = box(model, frame, Vector3.new(3.4, 1.6, 3.4), Vector3.new(0, 0.8, 0), Color3.fromRGB(80, 170, 230))
		box(model, frame, Vector3.new(4, 0.5, 4), Vector3.new(0, 0.25, 0), Color3.fromRGB(240, 240, 250))
		ped.Name = "Pedestal" .. i
		ped:SetAttribute("PedestalIndex", i)
		local bpp = prompt(ped, "Buy", "Egg", 0, 8)
		bpp.Name = "BuyPrompt"
		bpp:SetAttribute("Live", false)
		pedestals[i] = ped
	end
	-- the Abyss Rod's own pedestal, on its balcony (index #PEDESTAL_POS + 1)
	do
		local i = #Config.PEDESTAL_POS + 1
		local ap = Config.ABYSS_ROD.pedestal
		local frame = cf * CFrame.new(ap.X, f3 + 0.4, ap.Z)
		local ped = box(model, frame, Vector3.new(3.4, 1.6, 3.4), Vector3.new(0, 0.8, 0), Color3.fromRGB(200, 60, 150))
		box(model, frame, Vector3.new(4, 0.5, 4), Vector3.new(0, 0.25, 0), Color3.fromRGB(240, 240, 250))
		ped.Name = "Pedestal" .. i
		ped:SetAttribute("PedestalIndex", i)
		local bpp = prompt(ped, "Buy", "Egg", 0, 8)
		bpp.Name = "BuyPrompt"
		bpp:SetAttribute("Live", false)
		pedestals[i] = ped
	end

	-- upgrade boards (by the winch) and the Floor 2 board (at the stairs)
	local boards = {}
	-- each board's front (-Z) faces the middle of the deck
	local function boardFrame(x: number, z: number, face: Vector3): CFrame
		local p = Vector3.new(x, deck + 0.4, z)
		return cf * CFrame.lookAt(p, p + face)
	end
	-- Egg Luck, Fast Reel, the Shipwright and the Ship Workshop moved to the Dockyard in town:
	-- only the Floor board is still on the deck, because it sits at the stairs
	boards.Floor = boardPart(model, boardFrame(-16, qz0 - 1.2, -Vector3.zAxis), Vector3.zero, "Floor")
	-- Gift Chest (playtime gifts + daily chest) on the starboard side, mid-deck
	do
		local gf = boardFrame(29, 10, -Vector3.xAxis)
		local chest = box(model, gf, Vector3.new(3.4, 2.2, 2.4), Vector3.new(0, 1.1, 0), Color3.fromRGB(40, 190, 200))
		chest.Name = "GiftChest"
		box(model, gf, Vector3.new(3.6, 0.9, 2.6), Vector3.new(0, 2.5, 0), Color3.fromRGB(30, 160, 175))
		box(model, gf, Vector3.new(0.5, 3.1, 2.65), Vector3.new(0, 1.55, 0), Color3.fromRGB(255, 205, 50))
		box(model, gf, Vector3.new(3.65, 0.4, 2.65), Vector3.new(0, 2.2, 0), Color3.fromRGB(255, 205, 50))
		label(chest, "GIFTS", UDim2.fromOffset(110, 30), Vector3.new(0, 3.4, 0), Color3.fromRGB(120, 255, 170))
		local gp = prompt(chest, "Open", "Gift Chest", 0, 10)
		gp.Name = "GiftPrompt"
	end
	-- Team Board on the port side, mid-deck
	do
		local tb = boardPart(model, boardFrame(-30, 12, Vector3.xAxis), Vector3.zero, "Team")
		-- a proper wooden sign on two posts (not a glowing purple slab), so it reads as a sign
		tb.Color = Color3.fromRGB(150, 100, 60)
		tb.Material = Enum.Material.Wood
		paintBoard(tb, "MANAGE YOUR TEAM", "Pick who fights", Color3.fromRGB(255, 240, 90))
		local tp = prompt(tb, "Open", "Your Team", 0, 10)
		tp.Name = "TeamPrompt"
	end
	-- Robux sign on the starboard side of the winch
	do
		local sf = boardFrame(29, -12, -Vector3.xAxis)
		local sb = boardPart(model, sf, Vector3.zero, "FuseLuck")
		sb.Color = Color3.fromRGB(40, 210, 80)
		paintBoard(sb, "x2 Fuse Luck", "R$" .. Config.PRODUCTS.FuseLuck.price .. "  ·  15 min", Color3.fromRGB(255, 230, 80))
		local rp = prompt(sb, "Buy", "Fuse Luck", 0, 10)
		rp.Name = "RobuxPrompt"
		rp:SetAttribute("Product", "FuseLuck")
	end
	for id, b in boards do
		local pp = prompt(b, "Upgrade", "", 0, 10)
		pp.Name = "UpgradePrompt"
		pp:SetAttribute("Upgrade", id)
	end

	-- arena: the blue hole off the starboard side (ArenaBuilder: its islets, rocks and surf here,
	-- its terrain in WorldBuilder.build once every ship exists)
	local arenaCenter = cf * CFrame.new(Config.ARENA_OFFSET, 0, Config.ARENA_OFFSET_Z)
	-- the arena faces the ship: player monsters on the ship side, enemies on the far side
	local arenaCf = CFrame.lookAt(arenaCenter.Position, arenaCenter.Position + (arenaCenter.Position - cf.Position).Unit)
	local ring = Instance.new("Model")
	ring.Name = "Arena"
	ring.Parent = model
	ArenaBuilder.props(ring, arenaCf)
	buildLookout(ring, cf, arenaCf)
	-- starboard: just the landing the lookout pier leaves from; port: boarding stairs up from the
	-- water, so anyone who jumped or swam off climbs back aboard there
	buildBoardingRamp(model, cf, index, 1, 0.8, false)
	buildBoardingRamp(model, cf, index, -1, 0.3)

	-- boarding gate: a see-through wall across the bow ramp that only this ship's crew can walk
	-- through (collision groups, see WorldBuilder.setCrew). Everyone else bounces off it, so
	-- nobody can wander onto another captain's deck. The owner's client hides it.
	do
		-- Visitors may walk aboard (see setupCollisionGroups), so the gate is built invisible, with no
		-- "CREW ONLY" label. The part stays in its collision group so crew-only can be switched back on.
		local gate = box(model, cf, Vector3.new(24, 26, 1.5), Vector3.new(0, 13, -80.5), Color3.fromRGB(120, 210, 255), Enum.Material.ForceField, { Transparency = 1, CanQuery = false, Name = "ShipGate", CollisionGroup = "ShipGate" .. index })
		gate:SetAttribute("ShipIndex", index)
	end

	-- owner sign
	local signPart = box(model, cf, Vector3.new(1, 1, 1), Vector3.new(0, deck + 66, mp.Z), Color3.new(1, 1, 1), nil, { Transparency = 1, CanCollide = false, Name = "SignAnchor" })
	local sign = label(signPart, "Free Ship", UDim2.fromOffset(360, 70), Vector3.zero, Color3.fromRGB(255, 255, 255))
	sign.MaxDistance = 600
	local best = Instance.new("TextLabel")
	best.Name = "Best"
	best.BackgroundTransparency = 1
	best.Size = UDim2.new(1, 0, 0.6, 0)
	best.Position = UDim2.fromScale(0, 1)
	best.Font = Enum.Font.FredokaOne
	best.TextScaled = true
	best.Text = ""
	best.TextColor3 = Color3.fromRGB(120, 230, 255)
	best.Parent = sign
	local st = Instance.new("UIStroke")
	st.Thickness = 3
	st.Color = Color3.fromRGB(16, 22, 44)
	st.Parent = best
	sign.Size = UDim2.fromScale(30, 9)
	sign.StudsOffset = Vector3.new(0, 0, 0)

	model:SetAttribute("ShipIndex", index)
	model:SetAttribute("ArenaCf", arenaCf)
	model:SetAttribute("ShipCf", cf)
	local ship: Ship = {
		index = index,
		cf = cf,
		model = model,
		nests = nests,
		winch = winch,
		deepWinch = deepWinch,
		abyssWinch = abyssWinch,
		pedestals = pedestals,
		boards = boards,
		arenaCf = arenaCf,
		spawnCf = cf * CFrame.new(Config.SPAWN_POS.X, deck + 3, Config.SPAWN_POS.Z) * CFrame.Angles(0, 0, 0),
		sign = sign,
		quarterBarrier = barrier,
		floor3Barrier = barrier3,
		tierShown = -1,
	}
	return ship
end

---------------------------------------------------------------------------
-- The egg trench: a deep shaft of water off each ship's port side where the rod dives.
-- Stacked zones (Config.FISH_ZONES), each dressed so the dive is worth watching.
-- Zone k spans y = top(k) .. top(k) - FISH_ZONE_HEIGHT, top(1) = SEA_LEVEL.
---------------------------------------------------------------------------
local TRENCH_HALF = 26

-- where the rod's line drops, in ship space (the client uses the same numbers)
-- kind: nil = Egg Rod, "deep" (or true) = Deep Rod, "abyss" = Abyss Rod (Config.rodInfo)
function WorldBuilder.trenchCenter(shipCf: CFrame, kind: any): CFrame
	local p = Config.rodInfo(kind).center
	return shipCf * CFrame.new(p.X, Config.SEA_LEVEL, p.Z)
end

-- The terrain of one trench, one pass at a time. Neighbouring ships' trenches overlap, so
-- WorldBuilder.build runs "walls" for every trench, then "floor" for every trench, then
-- "shaft" for every trench: water is always carved last and nothing fills it back in.
function WorldBuilder.trenchTerrain(ship: Ship, deep: any, pass: string)
	local info = Config.rodInfo(deep)
	local half = info.half
	local ZONES = info.zones
	local H = info.H
	local terrain = workspace.Terrain
	local center = WorldBuilder.trenchCenter(ship.cf, deep)
	local depth = #ZONES * H + 12
	local mid = center * CFrame.new(0, -depth / 2 - 6, 0)
	if pass == "walls" then
		-- four rock walls round an open water shaft (never one solid block, so the shaft stays water)
		local wallH = depth - 22
		for s = 0, 3 do
			local wf = mid * CFrame.new(0, -11, 0) * CFrame.Angles(0, s * math.pi / 2, 0) * CFrame.new(0, 0, -half - 10)
			terrain:FillBlock(wf, Vector3.new(half * 2 + 40, wallH, 20), Enum.Material.Slate)
		end
	elseif pass == "floor" then
		terrain:FillBlock(center * CFrame.new(0, -depth - 8, 0), Vector3.new(half * 2 + 40, 8, half * 2 + 40), Enum.Material.Sand)
	elseif pass == "shaft" then
		-- the shaft in slabs (big single fills can come out patchy)
		local n = math.ceil((depth + 8) / 60)
		local slab = (depth + 8) / n
		for k = 0, n - 1 do
			local f = center * CFrame.new(0, 2 - slab * (k + 0.5), 0)
			local size = Vector3.new(half * 2, slab, half * 2)
			-- water does NOT replace solid terrain (it only fills empty space round it), so clear
			-- the rock to air first, then flood it
			terrain:FillBlock(f, size, Enum.Material.Air)
			terrain:FillBlock(f, size, Enum.Material.Water)
		end
	end
end

-- deep = the Deep Rod's shaft (Config.DEEP_ZONES, narrower, DEEP_ZONE_HEIGHT per zone)
function WorldBuilder.buildTrench(ship: Ship, deep: any)
	local info = Config.rodInfo(deep)
	local TRENCH_HALF = info.half
	local ZONES = info.zones
	local terrain = workspace.Terrain
	local center = WorldBuilder.trenchCenter(ship.cf, deep)
	local H = info.H
	local depth = #ZONES * H + 12
	local mid = center * CFrame.new(0, -depth / 2 - 6, 0)
	-- four rock walls round an open water shaft (never one solid block, so the shaft stays water)
	-- the rock and water are filled by WorldBuilder.trenchTerrain (in passes over every ship, so a
	-- neighbour's walls can never fill this shaft back in)
	local _ = terrain
	local _ = mid

	local folder = Instance.new("Model")
	folder.Name = if info.kind == "abyss" then "AbyssTrench" elseif info.kind == "deep" then "DeepTrench" else "Trench"
	folder.Parent = ship.model
	local rng = Random.new(ship.index * 97 + (if info.kind == "abyss" then 11 elseif info.kind == "deep" then 5 else 0))
	local function wallSpot(y: number): (CFrame, number)
		-- a point on one of the four walls, facing into the shaft
		local side = rng:NextInteger(0, 3)
		local along = rng:NextNumber(-TRENCH_HALF + 4, TRENCH_HALF - 4)
		local f = center * CFrame.Angles(0, side * math.pi / 2, 0) * CFrame.new(along, y, -TRENCH_HALF + 1.5)
		return f, side
	end
	local function light(p: BasePart, color: Color3, range: number)
		local l = Instance.new("PointLight")
		l.Color = color
		l.Range = range
		l.Brightness = 2
		l.Parent = p
	end
	local function ball(f: CFrame, size: Vector3, color: Color3, mat: Enum.Material?): BasePart
		local p = box(folder, f, size, Vector3.zero, color, mat, { CanCollide = false, CastShadow = false })
		p.Shape = Enum.PartType.Ball
		return p
	end

	for k, zone in ZONES do
		local top = Config.SEA_LEVEL - (k - 1) * H
		local function y(): number
			return top - rng:NextNumber(4, H - 4)
		end
		local look = zone.look or zone.id
		-- a glowing zone ring at the top of each zone (the hook flies through these)
		if k > 1 then
			for s = 0, 3 do
				local rf = center * CFrame.Angles(0, s * math.pi / 2, 0) * CFrame.new(0, top, -TRENCH_HALF + 0.6)
				box(folder, rf, Vector3.new(TRENCH_HALF * 2, 0.8, 0.8), Vector3.zero, zone.color, Enum.Material.Neon, { CanCollide = false })
			end
		end
		-- a ledge with sleeping eggs: the zone's prize
		do
			local f = wallSpot(top - H + 6)
			box(folder, f, Vector3.new(14, 2, 6), Vector3.new(0, -1, 2), Color3.fromRGB(120, 120, 135), Enum.Material.Slate)
			for e = -1, 1 do
				local egg = ball(f * CFrame.new(e * 3.6, 1.4, 2), Vector3.new(2.2, 2.8, 2.2), Color3.fromRGB(25, 25, 35), Enum.Material.SmoothPlastic)
				egg.Name = "SleepingEgg"
				local glow = ball(f * CFrame.new(e * 3.6, 1.4, 2), Vector3.new(2.8, 3.4, 2.8), zone.color, Enum.Material.ForceField)
				glow.Transparency = 0.2
			end
		end
		if look == "Shallows" then
			for _ = 1, 10 do
				local f = wallSpot(y())
				box(folder, f, Vector3.new(rng:NextNumber(4, 9), rng:NextNumber(2, 4), 4), Vector3.zero, Color3.fromRGB(240, 215, 150), Enum.Material.Sand)
				local star = box(folder, f * CFrame.new(0, 2, 1.5) * CFrame.Angles(0, 0, rng:NextNumber(0, 6)), Vector3.new(1.8, 1.8, 0.4), Vector3.zero, Color3.fromRGB(255, 130, 90), nil, { CanCollide = false })
				star.Name = "Starfish"
			end
			for r = 0, 5 do
				local ray = box(folder, center * CFrame.new(rng:NextNumber(-18, 18), top - 18, rng:NextNumber(-18, 18)) * CFrame.Angles(0, 0, math.rad(12)), Vector3.new(2.5, 36, 0.4), Vector3.zero, Color3.fromRGB(255, 250, 200), Enum.Material.Neon, { CanCollide = false, Transparency = 0.8 })
				ray.Name = "SunRay" .. r
			end
		elseif look == "Kelp" then
			for _ = 1, 16 do
				local f = wallSpot(top - H + 1)
				local h = rng:NextInteger(5, 9)
				for s = 0, h do
					box(folder, f * CFrame.new(math.sin(s * 0.7) * 0.8, s * 3.2, 2), Vector3.new(1.1, 3.4, 1.1), Vector3.zero, Color3.fromRGB(50, 150 + s * 5, 70), nil, { CanCollide = false, Name = "Kelp" })
					if s % 2 == 0 then
						box(folder, f * CFrame.new(1.2, s * 3.2, 2) * CFrame.Angles(0, 0, math.rad(-30)), Vector3.new(2.2, 0.3, 1.2), Vector3.zero, Color3.fromRGB(80, 200, 90), nil, { CanCollide = false })
					end
				end
			end
			for _ = 1, 6 do
				local f = wallSpot(y())
				box(folder, f, Vector3.new(6, 4, 5), Vector3.zero, Color3.fromRGB(90, 110, 80), Enum.Material.Slate)
			end
		elseif look == "Reef" then
			local cols = { Color3.fromRGB(255, 110, 150), Color3.fromRGB(255, 160, 60), Color3.fromRGB(180, 100, 255), Color3.fromRGB(60, 220, 200) }
			for i = 1, 22 do
				local f = wallSpot(y())
				local col = cols[i % 4 + 1]
				if i % 3 == 0 then
					for b = 0, 3 do
						ball(f * CFrame.new(rng:NextNumber(-2, 2), b * 1.4, 2 + rng:NextNumber(0, 1.5)), Vector3.one * rng:NextNumber(1.5, 3), col)
					end
				else
					for b = 0, 4 do
						box(folder, f * CFrame.new(0, b * 1.6, 2) * CFrame.Angles(0, 0, math.rad((b % 2 - 0.5) * 50)), Vector3.new(0.7, 2.4, 0.7), Vector3.zero, col, nil, { CanCollide = false })
					end
				end
				if i % 4 == 0 then
					local a = ball(f * CFrame.new(0, 1, 3), Vector3.new(1.6, 1.6, 1.6), Color3.fromRGB(120, 255, 230), Enum.Material.Neon)
					light(a, Color3.fromRGB(120, 255, 230), 10)
				end
			end
		elseif look == "Wreck" then
			local WOODW = Color3.fromRGB(90, 70, 55)
			do
				local f = center * CFrame.new(-8, top - H + 8, 6) * CFrame.Angles(math.rad(20), math.rad(30), math.rad(-25))
				box(folder, f, Vector3.new(10, 8, 26), Vector3.zero, WOODW, Enum.Material.WoodPlanks)
				box(folder, f * CFrame.new(0, 10, -2) * CFrame.Angles(math.rad(-15), 0, 0), Vector3.new(1.4, 22, 1.4), Vector3.zero, WOODW, Enum.Material.Wood)
			end
			for i = 1, 8 do
				local f = wallSpot(y())
				if i % 2 == 0 then
					local cannon = box(folder, f * CFrame.new(0, 0, 2) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Vector3.new(4, 1.4, 1.4), Vector3.zero, Color3.fromRGB(45, 45, 55), Enum.Material.Metal)
					cannon.Shape = Enum.PartType.Cylinder
				else
					box(folder, f * CFrame.new(0, 0, 2), Vector3.new(3, 2, 2), Vector3.zero, Color3.fromRGB(120, 80, 40), Enum.Material.Wood)
					local gold = box(folder, f * CFrame.new(0, 1.2, 2), Vector3.new(2.6, 0.5, 1.6), Vector3.zero, Color3.fromRGB(255, 205, 60), Enum.Material.Neon, { CanCollide = false })
					light(gold, Color3.fromRGB(255, 200, 90), 10)
				end
			end
			for _ = 1, 5 do
				local f = wallSpot(y())
				box(folder, f * CFrame.new(0, 0, 2) * CFrame.Angles(0, 0, rng:NextNumber(-1, 1)), Vector3.new(8, 0.8, 1.2), Vector3.zero, WOODW, Enum.Material.WoodPlanks)
			end
		elseif look == "Ice" then
			-- frozen walls: pale ice blocks and glowing crystal spikes
			for i = 1, 14 do
				local f = wallSpot(y())
				box(folder, f * CFrame.new(0, 0, 1.5), Vector3.new(rng:NextNumber(4, 8), rng:NextNumber(3, 6), 3), Vector3.zero, Color3.fromRGB(210, 235, 250), Enum.Material.Ice)
				if i % 2 == 0 then
					local c = box(folder, f * CFrame.new(0, 3, 2.5) * CFrame.Angles(math.rad(-30), 0, math.rad(rng:NextNumber(-20, 20))), Vector3.new(1.4, 5, 1.4), Vector3.zero, zone.color, Enum.Material.Neon, { CanCollide = false })
					light(c, zone.color, 12)
				end
			end
		elseif look == "Vents" then
			-- volcanic vents: black rock chimneys with glowing lava tops
			for i = 1, 10 do
				local f = wallSpot(top - H + 1)
				local h = rng:NextNumber(5, 14)
				box(folder, f * CFrame.new(0, h / 2, 2), Vector3.new(3.5, h, 3.5), Vector3.zero, Color3.fromRGB(35, 30, 30), Enum.Material.Basalt)
				local lava = box(folder, f * CFrame.new(0, h + 0.4, 2), Vector3.new(2.6, 0.8, 2.6), Vector3.zero, zone.color, Enum.Material.Neon, { CanCollide = false })
				if i % 2 == 0 then
					light(lava, zone.color, 14)
				end
			end
		elseif look == "Abyss" then
			for i = 1, 14 do
				local f = wallSpot(top - H + 1)
				local h = rng:NextNumber(8, 22)
				box(folder, f * CFrame.new(0, h / 2, 2), Vector3.new(3, h, 3), Vector3.zero, Color3.fromRGB(30, 25, 45), Enum.Material.Basalt)
				if i % 2 == 0 then
					local c = box(folder, f * CFrame.new(0, h + 1, 2) * CFrame.Angles(math.rad(35), math.rad(45), 0), Vector3.new(2, 2, 2), Vector3.zero, zone.color, Enum.Material.Neon, { CanCollide = false })
					light(c, zone.color, 16)
				end
			end
			-- the eye in the dark
			local f = center * CFrame.new(0, top - H * 0.45, -TRENCH_HALF + 3)
			local eye = ball(f, Vector3.new(9, 6, 2), Color3.fromRGB(240, 235, 210))
			eye.Name = "AbyssEye"
			local iris = ball(f * CFrame.new(0, 0, 0.9), Vector3.new(3.6, 4.6, 1), Color3.fromRGB(255, 60, 90), Enum.Material.Neon)
			iris.Name = "AbyssIris"
			light(iris, Color3.fromRGB(255, 60, 90), 24)
		end
		-- zone light so every zone reads in its colour
		local lp = box(folder, center * CFrame.new(0, top - H / 2, 0), Vector3.one, Vector3.zero, zone.color, nil, { Transparency = 1, CanCollide = false, Name = "ZoneLight" .. k })
		light(lp, zone.color, 40)
	end
end

local function buildLighting()
	Lighting.ClockTime = 14
	Lighting.Brightness = 2.6
	Lighting.Ambient = Color3.fromRGB(120, 130, 150)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 160, 180)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.4
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmo.Density = 0.25
	atmo.Haze = 0.6
	atmo.Color = Color3.fromRGB(190, 230, 255)
	atmo.Decay = Color3.fromRGB(120, 180, 230)
	atmo.Parent = Lighting
	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect")
	cc.Saturation = 0.18
	cc.Contrast = 0.05
	cc.Parent = Lighting
end

---------------------------------------------------------------------------
-- Shipwright cosmetics: every tier bought on the Shipwright board adds something to the ship
-- (rebuilt cumulatively, so tier N shows tiers 1..N). Pure decoration: CanCollide off.
---------------------------------------------------------------------------
-- Ship Workshop paint: the sail cloth and the hull stripe take the owner's chosen colours
-- (nil = back to the defaults when the ship is free again)
function WorldBuilder.applyPaint(ship: Ship, paint: { sail: string?, stripe: string? }?)
	local function pick(list: { any }, id: string?): Color3
		for _, p in list do
			if p.id == id then
				return p.color
			end
		end
		return list[1].color
	end
	local sail = ship.model:FindFirstChild("SailCloth") :: BasePart?
	local stripe = ship.model:FindFirstChild("HullStripe") :: BasePart?
	if sail then
		sail.Color = pick(Config.PAINTS.Sail, if paint then paint.sail else nil)
	end
	if stripe then
		stripe.Color = pick(Config.PAINTS.Stripe, if paint then paint.stripe else nil)
	end
end

-- Deck cannons. Cannon n (1..MAX_CANNONS) is pair k = (n + 1) // 2, odd n on the port rail and even
-- n on the starboard rail, at Config.CANNON_Z[k]. The server owns whether it is loaded
-- (ship model attribute "Cannon<n>Loaded"): the owner loads it from its prompt, a battle start fires
-- every loaded one (FittingView plays the shot when the attribute goes true -> false) and empties it.
-- The cannon model itself is a Blender rig drawn on the client; the server builds the mount block
-- it stands on, the prompt, and the cannonball shown in the barrel while it is loaded.
local MAX_CANNONS = 2 * Config.FITTINGS.Cannons.max

local function setCannonLoaded(ship: Ship, n: number, loaded: boolean)
	ship.model:SetAttribute("Cannon" .. n .. "Loaded", loaded)
	local fittings = ship.model:FindFirstChild("Fittings")
	if not fittings then
		return
	end
	local ball = fittings:FindFirstChild("CannonBall" .. n) :: BasePart?
	if ball then
		ball.Transparency = if loaded then 0 else 1
	end
	local mount = fittings:FindFirstChild("CannonMount" .. n)
	local pp = if mount then (mount:FindFirstChild("CannonPrompt") :: ProximityPrompt?) else nil
	if pp then
		pp.Enabled = not loaded
		pp:SetAttribute("Live", not loaded) -- the client's prompt manager respects this too
	end
end

-- a battle starts: every loaded cannon fires and is empty again
function WorldBuilder.fireCannons(ship: Ship)
	for n = 1, MAX_CANNONS do
		if ship.model:GetAttribute("Cannon" .. n .. "Loaded") == true then
			setCannonLoaded(ship, n, false)
		end
	end
end

-- Ship Workshop fittings: Hull Plating (bands of riveted metal plates along both sides, one band
-- per level), plus the mounts, prompts and cannonballs of the deck cannons. The cannons, crow's nest
-- and figurehead themselves are Blender rigs drawn on the client (FittingView) from the Fit_* attributes.
function WorldBuilder.applyFittings(ship: Ship, fit: { [string]: number }?)
	local f = fit or {}
	local plate, cann = f.Hull or 0, f.Cannons or 0
	for _, id in { "Cannons", "CrowsNest", "Figurehead", "Hull" } do
		ship.model:SetAttribute("Fit_" .. id, f[id] or 0)
	end
	-- cannons that don't exist (any more) forget their load
	for n = 2 * cann + 1, MAX_CANNONS do
		ship.model:SetAttribute("Cannon" .. n .. "Loaded", nil)
	end
	local key = plate * 10 + cann
	if ship.model:GetAttribute("FitBuilt") == key and ship.model:FindFirstChild("Fittings") then
		return
	end
	ship.model:SetAttribute("FitBuilt", key)
	local old = ship.model:FindFirstChild("Fittings")
	if old then
		old:Destroy()
	end
	if plate <= 0 and cann <= 0 then
		return
	end
	local m = Instance.new("Model")
	m.Name = "Fittings"
	m.Parent = ship.model
	local cf = ship.cf
	local W = Config.SHIP_WIDTH
	local deck = Config.DECK_Y
	local PLATE = Color3.fromRGB(104, 116, 138)
	local RIVET = Color3.fromRGB(255, 205, 90)
	-- plate rows above the waterline (the hull shows y 0..9), dodging the yellow stripe at y 6
	local ROWS = { { 1.0, 1.4 }, { 2.7, 1.4 }, { 4.4, 1.4 }, { 7.4, 1.4 }, { 8.4, 0.7 } }
	for r = 1, plate do
		local y, ph = ROWS[r][1], ROWS[r][2]
		for _, sx in { -1, 1 } do
			for z = -52, 80, 6.6 do
				-- stay off the boarding stairs
				local blocked = sx < 0 and z + 3 > BOARD_Z0 - 3.1 and z + 3 < BOARD_Z2 + 3.1
				if not blocked then
					box(m, cf, Vector3.new(0.5, ph, 6.1), Vector3.new(sx * (W / 2 + 0.3), y, z + 3), PLATE, Enum.Material.Metal, { CanCollide = false })
					box(m, cf, Vector3.new(0.3, 0.4, 0.4), Vector3.new(sx * (W / 2 + 0.62), y, z + 1), RIVET, Enum.Material.Metal, { CanCollide = false })
					box(m, cf, Vector3.new(0.3, 0.4, 0.4), Vector3.new(sx * (W / 2 + 0.62), y, z + 5), RIVET, Enum.Material.Metal, { CanCollide = false })
				end
			end
		end
	end
	-- deck cannons: a raised wooden mount just inside each rail, a "Load Cannonball" prompt, and
	-- the ball that shows in the barrel while loaded (the barrel points out over the rail)
	local base = Config.CANNON_BASE
	local deckTop = deck + 0.4 -- the planks
	for n = 1, 2 * cann do
		local k = (n + 1) // 2
		local sx = if n % 2 == 1 then -1 else 1
		local z = Config.CANNON_Z[k]
		local mount = box(m, cf, Vector3.new(6, base, 4.2), Vector3.new(sx * Config.CANNON_X, deckTop + base / 2, z), Color3.fromRGB(110, 70, 42), Enum.Material.Wood, { Name = "CannonMount" .. n })
		box(m, cf, Vector3.new(6.2, 0.35, 4.4), Vector3.new(sx * Config.CANNON_X, deckTop + base - 0.17, z), WOOD_LIGHT, Enum.Material.Wood)
		-- same origin and yaw as FittingView: barrel along local -Z, turned to point out over the rail
		local origin = cf * CFrame.new(sx * Config.CANNON_X, deckTop + base, z) * CFrame.Angles(0, if sx < 0 then math.pi / 2 else -math.pi / 2, 0)
		local ball = box(m, origin, Vector3.new(1.15, 1.15, 1.15), Vector3.new(0, 1.88, -3.3), Color3.fromRGB(28, 28, 38), Enum.Material.Metal, { Name = "CannonBall" .. n, CanCollide = false, CanQuery = false, CastShadow = false })
		ball.Shape = Enum.PartType.Ball
		local pp = prompt(mount, "Load Cannonball", "Cannon", 0.3, 10)
		pp.Name = "CannonPrompt"
		pp.Triggered:Connect(function(player)
			-- only the captain loads their own guns, and only an empty one
			if ship.model:GetAttribute("Owner") ~= player.UserId then
				return
			end
			if ship.model:GetAttribute("Cannon" .. n .. "Loaded") == true then
				return
			end
			setCannonLoaded(ship, n, true)
		end)
		setCannonLoaded(ship, n, ship.model:GetAttribute("Cannon" .. n .. "Loaded") == true)
	end
end

function WorldBuilder.applyShipTier(ship: Ship, tier: number)
	if ship.tierShown == tier then
		return
	end
	ship.tierShown = tier
	local old = ship.model:FindFirstChild("Cosmetics")
	if old then
		old:Destroy()
	end
	if tier <= 0 then
		return
	end
	local m = Instance.new("Model")
	m.Name = "Cosmetics"
	m.Parent = ship.model
	local cf = ship.cf
	local deck, up = Config.DECK_Y, Config.UPPER_DECK_Y
	local W = Config.SHIP_WIDTH
	local mp = Config.MAST_POS
	local GOLD = Color3.fromRGB(255, 205, 60)
	local function b(size: Vector3, pos: Vector3, color: Color3, mat: Enum.Material?, extra: { [string]: any }?): BasePart
		local props: { [string]: any } = { CanCollide = false, CanQuery = false, CastShadow = false }
		if extra then
			for k, v in extra do
				props[k] = v
			end
		end
		return box(m, cf, size, pos, color, mat, props)
	end
	local function ball(size: Vector3, pos: Vector3, color: Color3, mat: Enum.Material?): BasePart
		local p = b(size, pos, color, mat)
		p.Shape = Enum.PartType.Ball
		return p
	end
	local function light(p: BasePart, color: Color3, range: number, brightness: number)
		local l = Instance.new("PointLight")
		l.Color = color
		l.Range = range
		l.Brightness = brightness
		l.Parent = p
	end

	-- 1 lantern posts along both rails
	if tier >= 1 then
		for z = -48, 80, 16 do
			for _, sx in { -1, 1 } do
				b(Vector3.new(0.4, 1.4, 0.4), Vector3.new(sx * (W / 2 - 0.5), deck + 4.1, z), Color3.fromRGB(40, 44, 60))
				b(Vector3.new(1.1, 1.1, 1.1), Vector3.new(sx * (W / 2 - 0.5), deck + 5.4, z), Color3.fromRGB(255, 220, 130), Enum.Material.Neon)
			end
		end
	end
	-- 2 brass rail caps: one per wooden rail segment (buildShip's side rails run from the bow
	-- corner to the quarterdeck, with gaps for the boarding stairs and the lookout pier). A single
	-- 160-long cap used to run past the bow corner out over the water and bridge both gaps.
	if tier >= 2 then
		for _, sx in { -1, 1 } do
			local g1, g2 = if sx < 0 then BOARD_Z1 else LAND_Z1, if sx < 0 then BOARD_Z2 else LAND_Z2
			for _, seg in { { -SHIP_BOW, g1 }, { g2, Config.QUARTERDECK_Z } } do
				b(Vector3.new(1.4, 0.35, seg[2] - seg[1]), Vector3.new(sx * (W / 2 - 0.5), deck + 3.55, (seg[1] + seg[2]) / 2), GOLD, Enum.Material.Metal)
			end
		end
		b(Vector3.new(W, 0.35, 1.4), Vector3.new(0, up + 3.55, 83.5), GOLD, Enum.Material.Metal)
	end
	-- 3 flags along the boom
	if tier >= 3 then
		local cols = { Color3.fromRGB(240, 60, 60), Color3.fromRGB(255, 205, 60), Color3.fromRGB(60, 160, 255), Color3.fromRGB(90, 220, 120), Color3.fromRGB(190, 110, 255) }
		for i, x in { -16, -8, 8, 16 } do
			b(Vector3.new(0.2, 3, 0.2), Vector3.new(x, deck + 50, mp.Z), Color3.fromRGB(60, 44, 30))
			b(Vector3.new(0.25, 2, 4), Vector3.new(x, deck + 51.2, mp.Z + 2), cols[i % #cols + 1])
		end
	end
	-- 4 a carved sea-dragon figurehead at the bow
	if tier >= 4 then
		local TEAL = Color3.fromRGB(40, 190, 190)
		b(Vector3.new(1.4, 6, 1.4), Vector3.new(0, deck + 4.5, -74.2), Color3.fromRGB(105, 64, 38))
		b(Vector3.new(3, 3, 4.4), Vector3.new(0, deck + 8.5, -75.8), TEAL)
		b(Vector3.new(2.2, 1.4, 2.4), Vector3.new(0, deck + 7.8, -78.6), Color3.fromRGB(120, 230, 220))
		for _, sx in { -1, 1 } do
			b(Vector3.new(0.7, 0.7, 0.4), Vector3.new(sx * 1.1, deck + 9.2, -77.9), Color3.fromRGB(255, 255, 255))
			b(Vector3.new(0.4, 0.4, 0.3), Vector3.new(sx * 1.1, deck + 9.2, -78.2), Color3.fromRGB(16, 22, 44))
			b(Vector3.new(0.5, 2, 0.5), Vector3.new(sx * 1.3, deck + 10.6, -74.8), GOLD)
		end
	end
	-- 5 a golden star on the sail
	if tier >= 5 then
		b(Vector3.new(8, 8, 0.3), Vector3.zero, GOLD, nil, { CFrame = cf * CFrame.new(0, deck + 36, mp.Z - 1) * CFrame.Angles(0, 0, math.rad(45)) })
		b(Vector3.new(8, 8, 0.3), Vector3.new(0, deck + 36, mp.Z - 1), GOLD)
		b(Vector3.new(3, 3, 0.35), Vector3.new(0, deck + 36, mp.Z - 1.1), Color3.fromRGB(240, 60, 60))
	end
	-- 6 cannons poking out of the hull
	if tier >= 6 then
		for z = -30, 60, 15 do
			for _, sx in { -1, 1 } do
				local c = b(Vector3.new(5, 1.7, 1.7), Vector3.new(sx * (W / 2 + 2.3), deck - 1.2, z), Color3.fromRGB(45, 45, 55), Enum.Material.Metal)
				c.Shape = Enum.PartType.Cylinder
				b(Vector3.new(1, 2.4, 2.4), Vector3.new(sx * (W / 2 + 4.9), deck - 1.2, z), Color3.fromRGB(30, 30, 40), Enum.Material.Metal)
			end
		end
	end
	-- 7 a second mast and sail over the quarterdeck
	if tier >= 7 then
		b(Vector3.new(2, 38, 2), Vector3.new(0, up + 19, 70), Color3.fromRGB(105, 64, 38))
		b(Vector3.new(24, 0.8, 0.8), Vector3.new(0, up + 33, 70), Color3.fromRGB(105, 64, 38))
		b(Vector3.new(22, 15, 0.4), Vector3.new(0, up + 25.5, 69.2), Color3.fromRGB(250, 246, 232))
		b(Vector3.new(22, 2.2, 0.45), Vector3.new(0, up + 21, 69.15), Color3.fromRGB(40, 150, 230))
	end
	-- 8 a crow's nest ring with a lantern on the main mast
	if tier >= 8 then
		for _, o in { { 0, -3.4, 7, 0.3 }, { 0, 3.4, 7, 0.3 } } do
			b(Vector3.new(o[3], 1.2, o[4]), Vector3.new(0, deck + 52.8, mp.Z + o[2]), Color3.fromRGB(105, 64, 38))
		end
		for _, sx in { -1, 1 } do
			b(Vector3.new(0.3, 1.2, 7), Vector3.new(sx * 3.4, deck + 52.8, mp.Z), Color3.fromRGB(105, 64, 38))
		end
		local lamp = ball(Vector3.new(2, 2, 2), Vector3.new(0, deck + 55.6, mp.Z), Color3.fromRGB(255, 240, 160), Enum.Material.Neon)
		light(lamp, Color3.fromRGB(255, 230, 150), 36, 0.9)
	end
	-- 9 coral growing on the hull
	if tier >= 9 then
		local cols = { Color3.fromRGB(255, 110, 150), Color3.fromRGB(255, 160, 60), Color3.fromRGB(180, 100, 255), Color3.fromRGB(60, 220, 200) }
		local i = 0
		for z = -62, 80, 9 do
			for _, sx in { -1, 1 } do
				i += 1
				ball(Vector3.new(2.2, 2.2, 2.2), Vector3.new(sx * (W / 2 + 0.6), deck - 9.4 + (i % 3) * 0.6, z), cols[i % 4 + 1])
				if i % 3 == 0 then
					b(Vector3.new(0.7, 2.6, 0.7), Vector3.new(sx * (W / 2 + 0.8), deck - 7.4, z + 1.5), cols[(i + 1) % 4 + 1])
				end
			end
		end
	end
	-- 10 a glowing wake along both sides at the waterline
	if tier >= 10 then
		for _, sx in { -1, 1 } do
			b(Vector3.new(0.7, 0.3, 150), Vector3.new(sx * (W / 2 + 1.4), 0.4, 4), Color3.fromRGB(80, 230, 255), Enum.Material.Neon, { Transparency = 0.35 })
		end
	end
	-- 11 gold trim round the sail
	if tier >= 11 then
		b(Vector3.new(36.6, 0.8, 0.5), Vector3.new(0, deck + 48.2, mp.Z - 0.9), GOLD, Enum.Material.Metal)
		b(Vector3.new(36.6, 0.8, 0.5), Vector3.new(0, deck + 23.8, mp.Z - 0.9), GOLD, Enum.Material.Metal)
		for _, sx in { -1, 1 } do
			b(Vector3.new(0.8, 24.6, 0.5), Vector3.new(sx * 18.2, deck + 36, mp.Z - 0.9), GOLD, Enum.Material.Metal)
		end
	end
	-- 12 the royal flagship: a crown on the mast, a rainbow pennant and a great stern lantern
	if tier >= 12 then
		b(Vector3.new(4, 1.4, 4), Vector3.new(0, deck + 61.4, mp.Z), GOLD, Enum.Material.Metal)
		for _, o in { { -1.5, -1.5 }, { 1.5, -1.5 }, { -1.5, 1.5 }, { 1.5, 1.5 }, { 0, 0 } } do
			b(Vector3.new(0.8, 1.8, 0.8), Vector3.new(o[1], deck + 63, mp.Z + o[2]), GOLD, Enum.Material.Metal)
		end
		local rainbow = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 170, 60), Color3.fromRGB(255, 235, 80), Color3.fromRGB(90, 220, 110), Color3.fromRGB(80, 170, 255), Color3.fromRGB(190, 110, 255) }
		for i, c in rainbow do
			b(Vector3.new(0.25, 0.9, 14), Vector3.new(0, deck + 64.4 - i * 0.9, mp.Z + 9), c, Enum.Material.Neon)
		end
		local lamp = ball(Vector3.new(3.4, 3.4, 3.4), Vector3.new(0, up + 6, 83), Color3.fromRGB(255, 220, 110), Enum.Material.Neon)
		light(lamp, Color3.fromRGB(255, 220, 130), 40, 1)
	end
end

---------------------------------------------------------------------------
-- Crew collision groups: ship i's gate lets through only players whose character is in
-- group "Crew<i>" (everyone else, including players with no ship yet, is blocked).
---------------------------------------------------------------------------
local crewOf: { [Player]: number } = {}
local crewHooked: { [Player]: boolean } = {}

local function setupCollisionGroups()
	for i = 1, Config.SHIP_COUNT do
		pcall(function()
			PhysicsService:RegisterCollisionGroup("Crew" .. i)
		end)
		pcall(function()
			PhysicsService:RegisterCollisionGroup("ShipGate" .. i)
		end)
	end
	-- Visitors are welcome: the gates and ramp walls let EVERYONE through (the owner's crew, other
	-- crews and players with no ship), so anyone can walk aboard and look at other captains'
	-- monsters. Nothing on a ship can be used by a visitor anyway: its prompts only show for the
	-- owner and the server checks ownership (FarmService.ownsShipOf). The groups stay registered so
	-- crew-only areas can be switched back on by flipping these flags.
	local CREW_ONLY = false
	for i = 1, Config.SHIP_COUNT do
		PhysicsService:CollisionGroupSetCollidable("ShipGate" .. i, "Default", CREW_ONLY)
		for j = 1, Config.SHIP_COUNT do
			PhysicsService:CollisionGroupSetCollidable("ShipGate" .. i, "Crew" .. j, CREW_ONLY and i ~= j)
		end
	end
end

local function groupFor(player: Player): string
	local i = crewOf[player]
	return if i and i > 0 then "Crew" .. i else "Default"
end

local function applyCrew(player: Player, char: Model)
	local group = groupFor(player)
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = group
		end
	end
end

-- Put `player`'s character on ship `index`'s crew (0 = nobody's)
function WorldBuilder.setCrew(player: Player, index: number)
	crewOf[player] = index
	if not crewHooked[player] then
		crewHooked[player] = true
		local function hook(char: Model)
			applyCrew(player, char)
			char.DescendantAdded:Connect(function(d)
				if d:IsA("BasePart") then
					d.CollisionGroup = groupFor(player)
				end
			end)
		end
		player.CharacterAdded:Connect(hook)
		if player.Character then
			hook(player.Character)
		end
		Players.PlayerRemoving:Connect(function(p)
			if p == player then
				crewOf[p] = nil
				crewHooked[p] = nil
			end
		end)
	elseif player.Character then
		applyCrew(player, player.Character)
	end
end

---------------------------------------------------------------------------
-- The swim limit: a ring of tall invisible walls round the whole play area (harbour, every ship,
-- its arena and egg trench) so nobody who jumps in can swim out to nowhere. Blocks everyone
-- (default collision group) and is never queried, so it can't get in the way of the camera.
---------------------------------------------------------------------------
local function buildSwimWall(world: Folder)
	local wall = Instance.new("Model")
	wall.Name = "SwimLimit"
	wall.Parent = world
	local R = Config.SWIM_RADIUS
	local n = 36
	local len = 2 * R * math.tan(math.pi / n) + 6 -- chord of one segment plus overlap so there are no gaps
	local c = CFrame.new(WorldBuilder.hubCenter)
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		-- from the sea floor to far above any jump
		box(wall, c * CFrame.Angles(0, a, 0), Vector3.new(len, 90, 4), Vector3.new(0, 10, -R), Color3.new(1, 1, 1), nil, { Transparency = 1, CanQuery = false, Name = "SwimWall" })
	end
end

function WorldBuilder.build()
	local old = workspace:FindFirstChild("World")
	if old then
		old:Destroy()
	end
	local base = workspace:FindFirstChild("Baseplate")
	if base then
		base:Destroy()
	end
	local world = Instance.new("Folder")
	world.Name = "World"
	world.Parent = workspace
	buildLighting()
	setupCollisionGroups()
	buildOcean()
	buildHub(world)
	buildSwimWall(world)
	for i = 1, Config.SHIP_COUNT do
		WorldBuilder.ships[i] = buildShip(world, i)
		WorldBuilder.buildTrench(WorldBuilder.ships[i])
		WorldBuilder.buildTrench(WorldBuilder.ships[i], "deep")
		WorldBuilder.buildTrench(WorldBuilder.ships[i], "abyss")
		task.wait()
	end
	-- the blue hole arenas' terrain, before the trenches (their shafts are carved after, so a
	-- neighbouring trench is never filled in by an arena's reef)
	ArenaBuilder.paintTerrain()
	for i = 1, Config.SHIP_COUNT do
		ArenaBuilder.terrain(WorldBuilder.ships[i].arenaCf)
		task.wait()
	end
	-- trench terrain in passes over EVERY ship (see trenchTerrain): walls, then floors, then water
	for _, pass in { "walls", "floor", "shaft" } do
		for i = 1, Config.SHIP_COUNT do
			WorldBuilder.trenchTerrain(WorldBuilder.ships[i], false, pass)
			WorldBuilder.trenchTerrain(WorldBuilder.ships[i], "deep", pass)
			WorldBuilder.trenchTerrain(WorldBuilder.ships[i], "abyss", pass)
		end
		task.wait()
	end
end

return WorldBuilder
