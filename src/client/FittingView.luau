--!strict
-- Draws the Ship Workshop fittings on every ship from the levels the server puts on the ship
-- model (Fit_Cannons, Fit_CrowsNest, Fit_Figurehead). The models are the Blender rigs
-- (assets/monsters/spec.py: Cannon, CrowsNest, Figurehead), built and animated here:
--   Cannons      2 per level (one a side), on raised mounts just inside the deck rails (the server builds
--                the mounts and a "Load Cannonball" prompt, WorldBuilder.applyFittings). When the
--                captain loads one (ship attribute Cannon<n>Loaded -> true) the ram slides home and a
--                ball sits in the barrel; when a battle starts the server empties every loaded
--                cannon (-> false) and each fires: recoil, muzzle flash, smoke, a flying ball, a
--                splash. Starboard guns shoot at the arena, port guns out to sea.
--   Crow's Nest  a lookout basket on the mast: lookout bobs, spyglass sweeps, flag flaps,
--                lantern swings; he scans frantically when a boss appears.
--   Figurehead   a golden sea dragon on the bow: jaw, whiskers, mane; it ROARS when an egg hatches.
-- Hull plating is plain parts built by the server (WorldBuilder.applyPlating).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MonsterModels = require(Shared.MonsterModels)
local Remotes = require(Shared.Remotes)

local Sound = require(script.Parent.Sound)

local FittingView = {}

local player = Players.LocalPlayer
local DRAW_DIST = 320
local MAX_CANNONS = 2 * Config.FITTINGS.Cannons.max

type Item = { rig: MonsterModels.Rig, origin: CFrame, phase: number, actionUntil: number, side: number? }
type ShipFx = {
	model: Model,
	cannons: { Item },
	byNum: { [number]: Item }, -- cannon number (see WorldBuilder.applyFittings) -> its rig
	loaded: { [number]: boolean }, -- last loaded state seen, to tell loading from firing
	nest: Item?,
	figure: Item?,
	levels: { [string]: number },
	lastFire: number,
}

local ships: { [Model]: ShipFx } = {}
local folder = Instance.new("Folder")
folder.Name = "FittingVisuals"
folder.Parent = workspace

local function clearItems(list: { Item })
	for _, it in list do
		it.rig.model:Destroy()
	end
	table.clear(list)
end

local function level(model: Model, id: string): number
	return (model:GetAttribute("Fit_" .. id) or 0) :: number
end

local function make(id: string, scale: number, origin: CFrame, side: number?): Item?
	local rig = MonsterModels.build(id, scale)
	if not rig then
		return nil
	end
	rig.model.Parent = folder
	return { rig = rig, origin = origin, phase = math.random() * 5, actionUntil = 0, side = side }
end

local function rebuild(fx: ShipFx)
	local model = fx.model
	local cf = model:GetAttribute("ShipCf") :: CFrame?
	if not cf then
		return
	end
	local deck = Config.DECK_Y
	local mp = Config.MAST_POS
	local cLvl, nLvl, fLvl = level(model, "Cannons"), level(model, "CrowsNest"), level(model, "Figurehead")
	local lv = fx.levels
	if lv.Cannons ~= cLvl then
		lv.Cannons = cLvl
		clearItems(fx.cannons)
		table.clear(fx.byNum)
		-- on the raised mount just inside the rail (same spot as the server's CannonMount<n> block),
		-- barrel pointing out over the rail: odd n port, even n starboard (towards the arena)
		for n = 1, 2 * cLvl do
			local side = if n % 2 == 1 then -1 else 1
			local yaw = if side < 0 then math.pi / 2 else -math.pi / 2
			local origin = cf * CFrame.new(side * Config.CANNON_X, deck + 0.4 + Config.CANNON_BASE, Config.CANNON_Z[(n + 1) // 2]) * CFrame.Angles(0, yaw, 0)
			local it = make("Cannon", 1.5, origin, side)
			if it then
				table.insert(fx.cannons, it)
				fx.byNum[n] = it
			end
		end
		for n = 1, MAX_CANNONS do
			fx.loaded[n] = model:GetAttribute("Cannon" .. n .. "Loaded") == true
		end
	end
	if lv.CrowsNest ~= nLvl then
		lv.CrowsNest = nLvl
		if fx.nest then
			fx.nest.rig.model:Destroy()
			fx.nest = nil
		end
		if nLvl > 0 then
			fx.nest = make("CrowsNest", 0.9 + 0.13 * nLvl, cf * CFrame.new(mp.X, deck + 53.2, mp.Z))
		end
	end
	if lv.Figurehead ~= fLvl then
		lv.Figurehead = fLvl
		if fx.figure then
			fx.figure.rig.model:Destroy()
			fx.figure = nil
		end
		if fLvl > 0 then
			fx.figure = make("Figurehead", 0.95 + 0.14 * fLvl, cf * CFrame.new(0, deck + 0.2, -77))
		end
	end
end

-- a cannonball, muzzle flash and smoke; at the end a splash where it lands
local function fire(fx: ShipFx, it: Item, target: Vector3)
	local now = os.clock()
	it.actionUntil = now + 0.5
	local muzzle = it.origin * CFrame.new(0, 1.25 * 1.5, -2.1 * 1.5)
	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 200, 90)
	flash.Size = Vector3.one * 1.2
	flash.CFrame = muzzle
	flash.Parent = workspace
	TweenService:Create(flash, TweenInfo.new(0.25), { Size = Vector3.one * 5, Transparency = 1 }):Play()
	task.delay(0.3, function()
		flash:Destroy()
	end)
	local smoke = Instance.new("Part")
	smoke.Anchored = true
	smoke.CanCollide = false
	smoke.Transparency = 1
	smoke.Size = Vector3.one
	smoke.CFrame = muzzle
	smoke.Parent = workspace
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
	pe.Color = ColorSequence.new(Color3.fromRGB(235, 235, 240), Color3.fromRGB(120, 120, 135))
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 5) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	pe.Lifetime = NumberRange.new(1, 1.6)
	pe.Speed = NumberRange.new(4, 9)
	pe.SpreadAngle = Vector2.new(25, 25)
	pe.Rate = 0
	pe.EmissionDirection = Enum.NormalId.Front
	pe.Parent = smoke
	pe:Emit(14)
	task.delay(2, function()
		smoke:Destroy()
	end)
	-- the ball
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.Size = Vector3.one * 1.3
	ball.Color = Color3.fromRGB(30, 30, 40)
	ball.Material = Enum.Material.Metal
	ball.Parent = workspace
	local from = muzzle.Position
	local t0 = os.clock()
	local dur = 0.75
	task.spawn(function()
		while true do
			local u = (os.clock() - t0) / dur
			if u >= 1 then
				break
			end
			ball.Position = from:Lerp(target, u) + Vector3.new(0, math.sin(u * math.pi) * 14, 0)
			task.wait()
		end
		ball:Destroy()
		local boom = Instance.new("Part")
		boom.Shape = Enum.PartType.Ball
		boom.Anchored = true
		boom.CanCollide = false
		boom.CanQuery = false
		boom.Material = Enum.Material.Neon
		boom.Color = Color3.fromRGB(255, 170, 70)
		boom.Size = Vector3.one * 2
		boom.Position = target
		boom.Parent = workspace
		TweenService:Create(boom, TweenInfo.new(0.35), { Size = Vector3.one * 9, Transparency = 1 }):Play()
		task.delay(0.4, function()
			boom:Destroy()
		end)
	end)
	local cam = workspace.CurrentCamera.CFrame.Position
	if (muzzle.Position - cam).Magnitude < 160 then
		Sound.play("Cannon", 0.5, 0.9 + math.random() * 0.2)
	end
	fx.lastFire = now
end

-- where a cannon shoots: starboard guns at the enemy in the middle of the arena, port guns out to sea
local function targetFor(fx: ShipFx, it: Item): Vector3
	if it.side == 1 then
		local arenaCf = fx.model:GetAttribute("ArenaCf") :: CFrame?
		if arenaCf then
			return (arenaCf * CFrame.new(0, 2, -Config.ARENA_ENEMY_Z)).Position
		end
	end
	local p = (it.origin * CFrame.new(0, 0, -70)).Position
	return Vector3.new(p.X, Config.SEA_LEVEL + 1, p.Z)
end

-- the server flipped Cannon<n>Loaded: true = the captain loaded it, false = a battle started and it
-- fired (nil = the ship was freed or the cannon removed: nothing to show)
local function onCannon(fx: ShipFx, n: number)
	local value = fx.model:GetAttribute("Cannon" .. n .. "Loaded")
	local now = value == true
	local was = fx.loaded[n] == true
	fx.loaded[n] = now
	local it = fx.byNum[n]
	if not it or now == was then
		return
	end
	if now then
		-- loading: the barrel slides back and home again with a thunk
		it.actionUntil = os.clock() + 0.5
		local cam = workspace.CurrentCamera.CFrame.Position
		if (it.origin.Position - cam).Magnitude < 90 then
			Sound.play("Place", 0.6, 0.8)
		end
	elseif value == false then
		-- a ripple of shots along the deck
		task.delay((n - 1) * 0.12, function()
			if it.rig.model.Parent then
				fire(fx, it, targetFor(fx, it))
			end
		end)
	end
end

local function watch(model: Model)
	if ships[model] or not model:GetAttribute("ShipIndex") then
		return
	end
	local fx: ShipFx = { model = model, cannons = {}, byNum = {}, loaded = {}, nest = nil, figure = nil, levels = {}, lastFire = 0 }
	ships[model] = fx
	for _, id in { "Cannons", "CrowsNest", "Figurehead" } do
		model:GetAttributeChangedSignal("Fit_" .. id):Connect(function()
			rebuild(fx)
		end)
	end
	rebuild(fx)
	for n = 1, MAX_CANNONS do
		model:GetAttributeChangedSignal("Cannon" .. n .. "Loaded"):Connect(function()
			onCannon(fx, n)
		end)
	end
end

function FittingView.init()
	local world = workspace:WaitForChild("World")
	for _, m in world:GetChildren() do
		watch(m :: Model)
	end
	world.ChildAdded:Connect(function(m)
		task.defer(watch, m :: Model)
	end)

	-- battle and egg events decide when things move
	Remotes.event("Battle").OnClientEvent:Connect(function(owner: number, kind: string, p: any)
		local who = Players:GetPlayerByUserId(owner)
		local idx = who and who:GetAttribute("Ship")
		local world2 = workspace:FindFirstChild("World")
		local model = if idx and world2 then world2:FindFirstChild("Ship" .. idx) else nil
		local fx = if model then ships[model :: Model] else nil
		if not fx then
			return
		end
		local now = os.clock()
		-- (cannons no longer fire on hits: only loaded ones, once, at the start of a battle: see onCannon)
		if kind == "hatch" and fx.figure then
			fx.figure.actionUntil = now + 1.4
		elseif kind == "boss" and fx.nest then
			fx.nest.actionUntil = now + 3
		end
		local _ = p
	end)

	local lastCull = 0
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		local cam = workspace.CurrentCamera.CFrame.Position
		for model, fx in ships do
			if not model.Parent then
				continue
			end
			local pivot = (model:GetAttribute("ShipCf") :: CFrame?)
			if not pivot or (pivot.Position - cam).Magnitude > DRAW_DIST + 100 then
				continue
			end
			local function pose(it: Item?)
				if not it then
					return
				end
				MonsterModels.pose(it.rig, it.origin, t + it.phase, t < it.actionUntil, true)
			end
			for _, it in fx.cannons do
				pose(it)
			end
			pose(fx.nest)
			pose(fx.figure)
		end
		local _ = lastCull
	end)
end

return FittingView
