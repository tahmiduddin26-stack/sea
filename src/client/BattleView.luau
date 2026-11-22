--!strict
-- Draws every player's battle in their buoy arena from the Battle remote:
-- monsters fly from their nests out onto the water, swim in place and lunge to attack;
-- enemies rise out of the sea; hits flash, damage numbers pop, SUPER! for element wins,
-- element blasts for abilities; fainted monsters sink; slain enemies burst into coins.
-- For your own fight it also drives the HUD depth bar, boss intros and the end panel.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local MonsterModels = require(Shared.MonsterModels)
local Remotes = require(Shared.Remotes)

local UI = require(script.Parent.UI)
local Hud = require(script.Parent.Hud)
local Sound = require(script.Parent.Sound)
local Cinema = require(script.Parent.Cinema)

local BattleView = {}

local player = Players.LocalPlayer
local C = UI.Colors

local MON_SCALE = 1.6
local FX = Instance.new("Folder")
FX.Name = "BattleFx"
FX.Parent = workspace

type Unit = {
	rig: MonsterModels.Rig,
	home: CFrame, -- where it floats
	lunge: number, -- 0..1 attack lunge progress
	lungeT: number,
	flash: number,
	alive: boolean,
	sink: number,
	hpBar: Frame?,
	hpGui: BillboardGui?,
	maxHp: number,
	fly: { from: CFrame, t: number }?,
	phase: number,
	elements: { string },
}

type Fight = {
	owner: number,
	arena: CFrame,
	ship: Model?,
	team: { Unit },
	enemy: Unit?,
	enemyId: string?,
	enemyKind: string?,
	enemyMax: number,
	ending: boolean,
}

local fights: { [number]: Fight } = {}

local function shipOf(userId: number): Model?
	local world = workspace:FindFirstChild("World")
	if not world then
		return nil
	end
	for _, s in world:GetChildren() do
		if s:GetAttribute("Owner") == userId then
			return s :: Model
		end
	end
	return nil
end

local function waterY(): number
	return Config.SEA_LEVEL
end

local function hpBar(unit: Unit, color: Color3)
	-- sized in studs so it reads from the deck; anchored on the creature's first part
	local w = math.clamp(unit.rig.scale * 2.6, 3.5, 9)
	local gui = UI.new("BillboardGui", { Size = UDim2.fromScale(w, w * 0.16), StudsOffsetWorldSpace = Vector3.new(0, MonsterModels.height(unit.rig) + 0.8, 0), LightInfluence = 0, MaxDistance = 250, AlwaysOnTop = false, Adornee = unit.rig.parts[1], Parent = FX })
	local back = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(30, 30, 40), Parent = gui }, { UI.corner(6), UI.stroke(2) })
	local fill = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, Parent = back }, { UI.corner(6) })
	unit.hpBar = fill
	unit.hpGui = gui
end

local function setHp(unit: Unit, hp: number)
	if unit.hpBar then
		TweenService:Create(unit.hpBar, TweenInfo.new(0.15), { Size = UDim2.fromScale(math.clamp(hp / unit.maxHp, 0, 1), 1) }):Play()
	end
end

local function newUnit(id: string, scale: number, home: CFrame, maxHp: number): Unit?
	local rig = MonsterModels.build(id, scale)
	if not rig then
		return nil
	end
	rig.model.Parent = FX
	local def = Config.MONSTERS[id]
	if def then
		MonsterModels.addAura(rig, def.stars)
	end
	local unit: Unit = {
		rig = rig,
		home = home,
		lunge = 0,
		lungeT = 0,
		flash = 0,
		alive = true,
		sink = 0,
		hpBar = nil,
		hpGui = nil,
		maxHp = maxHp,
		fly = nil,
		phase = math.random() * 5,
		elements = if def then def.elements else {},
	}
	return unit
end

local function destroyUnit(u: Unit?)
	if u then
		u.rig.model:Destroy()
		if u.hpGui then
			u.hpGui:Destroy()
		end
	end
end

local function clearFight(f: Fight)
	for _, u in f.team do
		destroyUnit(u)
	end
	destroyUnit(f.enemy)
	f.team = {}
	f.enemy = nil
end

-- floating world text: damage numbers, SUPER!
local function popText(pos: Vector3, text: string, color: Color3, size: number?)
	local a = Instance.new("Part")
	a.Anchored = true
	a.CanCollide = false
	a.CanQuery = false
	a.Transparency = 1
	a.Size = Vector3.one
	a.Position = pos
	a.Parent = FX
	local gui = UI.new("BillboardGui", { Size = UDim2.fromOffset(160, 50), LightInfluence = 0, AlwaysOnTop = true, MaxDistance = 160, Parent = a })
	local l = UI.label({ Text = text, TextColor3 = color, Size = UDim2.fromScale(1, size or 0.8), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = gui })
	UI.pop(l, 0.4)
	TweenService:Create(a, TweenInfo.new(0.9, Enum.EasingStyle.Quad), { Position = pos + Vector3.new(math.random() * 2 - 1, 3.5, 0) }):Play()
	task.delay(0.55, function()
		TweenService:Create(l, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
		local st = l:FindFirstChildOfClass("UIStroke")
		if st then
			TweenService:Create(st, TweenInfo.new(0.35), { Transparency = 1 }):Play()
		end
	end)
	task.delay(1, function()
		a:Destroy()
	end)
end

-- a burst of blocky particles
local function burst(pos: Vector3, color: Color3, count: number, speed: number, neon: boolean?)
	for _ = 1, count do
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CastShadow = false
		p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
		p.Color = color
		local s = 0.3 + math.random() * 0.4
		p.Size = Vector3.new(s, s, s)
		p.CFrame = CFrame.new(pos)
		p.Parent = FX
		local dir = Vector3.new(math.random() - 0.5, math.random() * 0.8 + 0.4, math.random() - 0.5).Unit
		TweenService:Create(p, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { CFrame = CFrame.new(pos + dir * speed) * CFrame.Angles(math.random() * 6, math.random() * 6, 0), Size = Vector3.new(0.05, 0.05, 0.05) }):Play()
		task.delay(0.62, function()
			p:Destroy()
		end)
	end
end

-- a splash ring on the water
local function splash(pos: Vector3, size: number)
	local ring = Instance.new("Part")
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(220, 250, 255)
	ring.Transparency = 0.3
	ring.Size = Vector3.new(0.2, size * 0.4, size * 0.4)
	ring.CFrame = CFrame.new(pos.X, waterY() + 0.1, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = FX
	TweenService:Create(ring, TweenInfo.new(0.6), { Size = Vector3.new(0.2, size * 2, size * 2), Transparency = 1 }):Play()
	task.delay(0.65, function()
		ring:Destroy()
	end)
	burst(Vector3.new(pos.X, waterY() + 0.5, pos.Z), Color3.fromRGB(200, 240, 255), 8, size * 0.7)
end

-- an element blast flying from a monster to the enemy
local function blast(from: Vector3, to: Vector3, color: Color3)
	local orb = Instance.new("Part")
	orb.Anchored = true
	orb.CanCollide = false
	orb.CanQuery = false
	orb.Shape = Enum.PartType.Ball
	orb.Material = Enum.Material.Neon
	orb.Color = color
	orb.Size = Vector3.new(1.6, 1.6, 1.6)
	orb.Position = from
	orb.Parent = FX
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 10
	light.Parent = orb
	TweenService:Create(orb, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = to }):Play()
	task.delay(0.25, function()
		orb:Destroy()
		burst(to, color, 14, 4, true)
	end)
end

local function mine(f: Fight): boolean
	return f.owner == player.UserId
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function onStart(owner: number, payload: any)
	local ship = shipOf(owner)
	if not ship then
		return
	end
	local arena = ship:GetAttribute("ArenaCf") :: CFrame
	local old = fights[owner]
	if old then
		clearFight(old)
	end
	local f: Fight = { owner = owner, arena = arena, ship = ship, team = {}, enemy = nil, enemyId = nil, enemyKind = nil, enemyMax = 1, ending = false }
	fights[owner] = f
	local n = #payload.team
	for i, m in payload.team do
		-- rows of up to 4 on the ship side of the ring (+Z), facing the enemy (-Z)
		local row = (i - 1) // 4
		local inRow = math.min(4, n - row * 4)
		local col = (i - 1) % 4 + 1
		local x = (col - (inRow + 1) / 2) * 10
		local z = 8 + row * 9 + math.abs(col - (inRow + 1) / 2) * 1.5
		local home = arena * CFrame.new(x, 0, z)
		local u = newUnit(m.sp, MON_SCALE, home, m.maxHp)
		if u then
			MonsterModels.applyVariant(u.rig, m.v)
			-- float half in the water
			local foot = MonsterModels.footDepth(u.rig)
			u.home = home * CFrame.new(0, foot * 0.55, 0)
			hpBar(u, C.Kelp)
			setHp(u, m.hp)
			-- fly out from its nest
			local pad = ship:FindFirstChild("Nest" .. m.nest, true) :: BasePart?
			if pad then
				u.fly = { from = pad.CFrame * CFrame.new(0, 3, 0), t = 0 }
			end
			table.insert(f.team, u)
		end
	end
	if mine(f) then
		Hud.setBattle(true)
		Hud.setDepth(payload.depth, "")
		Sound.music("BattleMusic")
		Sound.play("Splash", 0.6)
	end
end

local function onWave(owner: number, p: any)
	local f = fights[owner]
	if not f then
		return
	end
	destroyUnit(f.enemy)
	local home = f.arena * CFrame.new(0, 0, -10) * CFrame.Angles(0, math.pi, 0)
	-- enemies read big on the water, like the reference's mobs next to your dragons
	local u = newUnit(p.id, p.scale * 2.3, home, p.maxHp)
	if not u then
		return
	end
	local foot = MonsterModels.footDepth(u.rig)
	local def = Config.ENEMIES[p.id]
	-- gulls fly, everything else floats half in the water
	local lift = if p.id == "Gull" then foot + 4 else foot * 0.55
	u.home = home * CFrame.new(0, lift, 0)
	u.sink = 1 -- rises out of the water
	hpBar(u, C.Coral)
	f.enemy = u
	f.enemyId = p.id
	f.enemyKind = p.kind
	f.enemyMax = p.maxHp
	splash(u.home.Position, 4 * p.scale)
	if mine(f) then
		Hud.setDepth(p.depth, p.stage)
		Hud.setEnemy(def and def.name or p.id, p.hp, p.maxHp, p.kind == "boss" or p.kind == "final", p.bossTime)
		if p.kind == "boss" or p.kind == "final" then
			Cinema.bossIntro(u.rig.model, def and def.name or p.id)
		elseif p.kind == "miniboss" then
			Hud.toast("MINI BOSS: " .. (def and def.name or p.id), C.Coral)
		end
	end
end

local function onHit(owner: number, p: any)
	local f = fights[owner]
	if not f or not f.enemy then
		return
	end
	local atk = f.team[p.from]
	if atk then
		atk.lungeT = 0.001
	end
	local e = f.enemy :: Unit
	local target = e.home.Position + Vector3.new(0, 2, 0)
	task.delay(if p.ability then 0.25 else 0.12, function()
		e.flash = 1
		setHp(e, p.hp)
		local near = (workspace.CurrentCamera.CFrame.Position - target).Magnitude < 140
		if near then
			local col = if p.super then C.Gold elseif p.weak then C.Muted else C.White
			popText(target + Vector3.new(0, 1, 0), (if p.ability then "BOOM " else "") .. Format.abbrev(p.dmg), col, if p.ability then 1 else 0.7)
			if p.super then
				popText(target + Vector3.new(0, 3.5, 0), "SUPER!", C.Gold, 0.9)
			end
		end
		if mine(f) then
			Hud.setEnemyHp(p.hp, f.enemyMax)
			Sound.play(if p.super then "Super" else "Hit", if p.ability then 0.8 else 0.45)
		end
	end)
	if p.ability and atk then
		BattleView.move(f, atk, e, p.move or atk.elements[1], p.heals)
	end
end

---------------------------------------------------------------------------
-- Signature moves: one big, readable effect per element
---------------------------------------------------------------------------
local function fxPart(props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = FX
	return p
end

local function moveName(pos: Vector3, text: string, color: Color3)
	popText(pos + Vector3.new(0, 5, 0), text .. "!", color, 1)
end

function BattleView.move(f: Fight, atk: Unit, e: Unit, element: string, heals: { [number]: number }?)
	local from = atk.home.Position + Vector3.new(0, 2, 0)
	local to = e.home.Position + Vector3.new(0, 2, 0)
	local col = Config.ELEMENTS[element] and Config.ELEMENTS[element].color or C.White
	local info = Config.MOVES[element]
	local near = (workspace.CurrentCamera.CFrame.Position - to).Magnitude < 160
	if info and near then
		moveName(from, info.name, col)
	end
	if element == "Tide" then
		-- a wave wall sweeps from the attacker to the enemy
		local dir = (to - from) * Vector3.new(1, 0, 1)
		local cf = CFrame.lookAt(Vector3.new(from.X, Config.SEA_LEVEL + 1, from.Z), Vector3.new(to.X, Config.SEA_LEVEL + 1, to.Z))
		local wave = fxPart({ Size = Vector3.new(8, 1, 2), CFrame = cf, Color = col, Transparency = 0.25, Material = Enum.Material.Glass })
		local crest = fxPart({ Size = Vector3.new(8.4, 0.8, 1), CFrame = cf * CFrame.new(0, 0.6, -0.6), Color = Color3.fromRGB(230, 250, 255) })
		local t = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local dest = cf + dir
		TweenService:Create(wave, t, { CFrame = dest * CFrame.new(0, 2.5, 0), Size = Vector3.new(10, 6, 2) }):Play()
		TweenService:Create(crest, t, { CFrame = dest * CFrame.new(0, 5.6, -0.6), Size = Vector3.new(10.4, 1, 1) }):Play()
		task.delay(0.45, function()
			wave:Destroy()
			crest:Destroy()
			splash(to, 7)
		end)
	elseif element == "Storm" then
		-- a zig-zag bolt from the sky onto the enemy, with a flash
		local top = to + Vector3.new(0, 26, 0)
		local last = top
		for k = 1, 6 do
			local nxt = top:Lerp(to, k / 6) + (if k < 6 then Vector3.new(math.random(-2, 2), 0, math.random(-2, 2)) else Vector3.zero)
			local seg = fxPart({ Size = Vector3.new(0.6, 0.6, (nxt - last).Magnitude), CFrame = CFrame.lookAt((last + nxt) / 2, nxt), Color = col })
			TweenService:Create(seg, TweenInfo.new(0.35), { Transparency = 1 }):Play()
			task.delay(0.36, function()
				seg:Destroy()
			end)
			last = nxt
		end
		local flash = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.new(3, 3, 3), Position = to, Color = Color3.fromRGB(255, 255, 220), Transparency = 0.1 })
		TweenService:Create(flash, TweenInfo.new(0.3), { Size = Vector3.new(12, 12, 12), Transparency = 1 }):Play()
		task.delay(0.31, function()
			flash:Destroy()
		end)
		burst(to, col, 16, 6, true)
	elseif element == "Abyss" then
		-- giant ink jaws snap shut on the enemy
		local cf = CFrame.lookAt(to, from)
		local jaws = {}
		for _, side in { 1, -1 } do
			local j = fxPart({ Size = Vector3.new(7, 1.4, 4), CFrame = cf * CFrame.new(0, side * 5, 0), Color = Color3.fromRGB(40, 20, 70), Material = Enum.Material.SmoothPlastic })
			for k = -2, 2 do
				local tooth = fxPart({ Size = Vector3.new(0.6, 1, 0.6), CFrame = j.CFrame * CFrame.new(k * 1.3, -side * 1.1, -1.5), Color = Color3.new(1, 1, 1), Material = Enum.Material.SmoothPlastic })
				tooth.Parent = j
			end
			table.insert(jaws, { part = j, side = side })
		end
		for _, jw in jaws do
			local start = jw.part.CFrame
			local goal = cf * CFrame.new(0, jw.side * 1.4, 0)
			local t0 = os.clock()
			task.spawn(function()
				while os.clock() - t0 < 0.22 do
					local k = (os.clock() - t0) / 0.22
					local now = start:Lerp(goal, k * k)
					local delta = now * jw.part.CFrame:Inverse()
					for _, ch in jw.part:GetChildren() do
						if ch:IsA("BasePart") then
							ch.CFrame = delta * ch.CFrame
						end
					end
					jw.part.CFrame = now
					task.wait()
				end
				task.wait(0.15)
				jw.part:Destroy()
			end)
		end
		task.delay(0.22, function()
			burst(to, Color3.fromRGB(150, 80, 230), 18, 6, true)
		end)
	elseif element == "Coral" then
		-- pink shield bubbles pop up on every teammate, and green heal numbers
		blast(from, to, col)
		for j, u in f.team do
			if u.alive then
				local b = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2, 2), Position = u.home.Position + Vector3.new(0, 1.5, 0), Color = col, Transparency = 0.5, Material = Enum.Material.ForceField })
				TweenService:Create(b, TweenInfo.new(0.5, Enum.EasingStyle.Back), { Size = Vector3.new(7, 7, 7) }):Play()
				task.delay(0.9, function()
					TweenService:Create(b, TweenInfo.new(0.3), { Transparency = 1 }):Play()
					task.wait(0.31)
					b:Destroy()
				end)
				if heals and heals[j] then
					setHp(u, heals[j])
					if near then
						popText(u.home.Position + Vector3.new(0, 4, 0), "+HP", C.Kelp, 0.7)
					end
				end
			end
		end
	else
		blast(from, to, col)
	end
	if mine(f) then
		Sound.play("Super", 0.7)
	end
end

local function onEnemyHit(owner: number, p: any)
	local f = fights[owner]
	if not f or not f.enemy then
		return
	end
	local e = f.enemy :: Unit
	e.lungeT = 0.001
	local u = f.team[p.to]
	if not u then
		return
	end
	task.delay(0.15, function()
		u.flash = -1
		setHp(u, p.hp)
		if (workspace.CurrentCamera.CFrame.Position - u.home.Position).Magnitude < 140 then
			popText(u.home.Position + Vector3.new(0, 3, 0), "-" .. Format.abbrev(p.dmg), C.Coral, 0.6)
		end
	end)
end

local function onFaint(owner: number, p: any)
	local f = fights[owner]
	local u = f and f.team[p.who]
	if u then
		u.alive = false
		if u.hpGui then
			u.hpGui.Enabled = false
		end
		splash(u.home.Position, 3)
	end
end

local function onKill(owner: number, p: any)
	local f = fights[owner]
	if not f or not f.enemy then
		return
	end
	local e = f.enemy :: Unit
	e.alive = false
	if e.hpGui then
		e.hpGui.Enabled = false
	end
	local pos = e.home.Position + Vector3.new(0, 1.5, 0)
	burst(pos, C.Gold, 12, 6, true)
	splash(e.home.Position, 5)
	if mine(f) then
		Sound.play("EnemyDie", 0.6)
		Sound.play("Coin", 0.5)
		Hud.flyCoins(pos, if f.enemyKind == "mob" then 3 else 8)
		if f.enemyKind == "boss" or f.enemyKind == "final" then
			Sound.play("Win", 0.8)
			Hud.toast("BOSS DEFEATED!", C.Gold)
		end
	end
	local dying = e
	task.delay(1.2, function()
		if f.enemy == dying then
			f.enemy = nil
		end
		destroyUnit(dying)
	end)
end

local function onEnd(owner: number, p: any)
	local f = fights[owner]
	if f then
		f.ending = true
		task.delay(1.8, function()
			if fights[owner] == f then
				clearFight(f)
				fights[owner] = nil
			end
		end)
	end
	if owner == player.UserId then
		Hud.setBattle(false)
		Sound.music("Music")
		Sound.play(if p.retreat then "Click" else "Lose", 0.7)
		BattleView.onMyEnd(p)
	end
end

BattleView.onMyEnd = function(_p: any) end

-- The egg rod. The cast and the final heave are the Blender animation (shared/RodAnim);
-- in between, the glowing hook dives down the trench past each zone (Config.FISH_ZONES) to
-- the zone the server rolled, grabs a black mystery egg, and rides back up. The owner's
-- camera follows the whole way and blends back to the normal camera at the end.
local RodAnim = require(Shared.RodAnim)
local casting: { [Model]: boolean } = {}
local castCount = 0

local function trackCf(name: string, t: number): (CFrame, number)
	local arr = RodAnim.Tracks[name]
	local f = math.clamp(t * RodAnim.FPS, 0, RodAnim.FRAMES - 1)
	local f0 = math.floor(f)
	local f1 = math.min(f0 + 1, RodAnim.FRAMES - 1)
	local stride = if name == "Cam" then 9 else 8
	local function at(i: number): (CFrame, number)
		local b = i * stride
		local S = Config.ROD_SCALE -- the rod on the ship is the Blender rod scaled up
		return CFrame.new(arr[b + 1] * S, arr[b + 2] * S, arr[b + 3] * S, arr[b + 4], arr[b + 5], arr[b + 6], arr[b + 7]), arr[b + 8]
	end
	local c0, s0 = at(f0)
	local c1, s1 = at(f1)
	local a = f - f0
	return c0:Lerp(c1, a), s0 + (s1 - s0) * a
end
local function camFov(t: number): number
	local arr = RodAnim.Tracks.Cam
	local f = math.clamp(math.floor(t * RodAnim.FPS + 0.5), 0, RodAnim.FRAMES - 1)
	return arr[f * 9 + 9]
end

function BattleView.castRod(ship: Model, count: number, zone: number, total: number, mine: boolean)
	local rod = ship:FindFirstChild("Rod") :: Model?
	local rodCf = if rod then rod:GetAttribute("RodCf") :: CFrame? else nil
	local shipCf = ship:GetAttribute("ShipCf") :: CFrame?
	if not rod or not rodCf or not shipCf or casting[rod] then
		return
	end
	casting[rod] = true
	local base = rodCf :: CFrame
	local rodParts: { [string]: BasePart } = {}
	for _, n in { "RodHandle", "RodS1", "RodS2", "RodS3", "RodReel" } do
		local p = rod:FindFirstChild(n) :: BasePart?
		if p then
			rodParts[n] = p
		end
	end
	local function poseRod(t: number)
		for n, p in rodParts do
			p.CFrame = base * (trackCf(n, t))
		end
	end
	local function tipPos(): Vector3
		local s3 = rodParts.RodS3
		return if s3 then (s3.CFrame * CFrame.new(0, 0, -s3.Size.Z / 2)).Position else base.Position
	end

	-- timeline (seconds)
	local H = Config.FISH_ZONE_HEIGHT
	local zdef = Config.FISH_ZONES[zone] or Config.FISH_ZONES[1]
	local CAST = RodAnim.SPLASH
	local GRAB = 0.75
	local FLY = 0.7
	local travel = math.max(1, total - CAST - GRAB - FLY)
	local DOWN = travel * 0.58
	local UP = travel - DOWN
	local tGrab = CAST + DOWN
	local tUp = tGrab + GRAB
	local tFly = tUp + UP

	local wp = Config.WINCH_POS
	local column = shipCf * CFrame.new(wp.X - 44, Config.SEA_LEVEL, wp.Z)
	local splashPos = (base * (trackCf("Hook", CAST))).Position
	local bottomY = Config.SEA_LEVEL - (zone - 1) * H - H + 7
	local stopPos = Vector3.new(column.X, bottomY, column.Z)

	-- effects
	local fx = Instance.new("Folder")
	fx.Name = "RodFx"
	fx.Parent = workspace
	local function part(props: { [string]: any }): Part
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CastShadow = false
		p.Material = Enum.Material.SmoothPlastic
		for k, v in props do
			(p :: any)[k] = v
		end
		p.Parent = fx
		return p
	end
	local hook = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.5, Color = Color3.fromRGB(120, 240, 255), Material = Enum.Material.Neon })
	local barb = part({ Size = Vector3.new(0.25, 1.4, 0.25), Color = Color3.fromRGB(220, 225, 235), Material = Enum.Material.Metal })
	local hookLight = Instance.new("PointLight")
	hookLight.Range = 18
	hookLight.Brightness = 3
	hookLight.Color = Color3.fromRGB(150, 240, 255)
	hookLight.Parent = hook
	local att0 = Instance.new("Attachment")
	att0.Position = Vector3.new(0, 0.5, 0)
	att0.Parent = hook
	local att1 = Instance.new("Attachment")
	att1.Position = Vector3.new(0, -0.5, 0)
	att1.Parent = hook
	local trail = Instance.new("Trail")
	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.Lifetime = 0.6
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(Color3.fromRGB(150, 240, 255), zdef.color)
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Parent = hook
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	bubbles.Color = ColorSequence.new(Color3.fromRGB(220, 250, 255))
	bubbles.LightEmission = 0.6
	bubbles.Size = NumberSequence.new(0.5, 0.1)
	bubbles.Rate = 0
	bubbles.Lifetime = NumberRange.new(0.8, 1.4)
	bubbles.Speed = NumberRange.new(2, 5)
	bubbles.EmissionDirection = Enum.NormalId.Top
	bubbles.SpreadAngle = Vector2.new(30, 30)
	bubbles.Parent = att0
	local line = part({ Size = Vector3.new(0.12, 0.12, 1), Color = Color3.fromRGB(250, 250, 250), Material = Enum.Material.Neon, Transparency = 0.2 })
	local eggs: { Model } = {}
	for i = 1, math.max(1, count) do
		local e = MonsterModels.buildEgg("Splashfin", 1.3, true)
		eggs[i] = e
	end
	local function drawLine(a: Vector3, b: Vector3)
		line.Size = Vector3.new(0.12, 0.12, math.max((b - a).Magnitude, 0.1))
		line.CFrame = CFrame.lookAt((a + b) / 2, b)
	end
	-- the captain holds the rod: both arms reach for the handle every frame, so they follow
	-- the Blender wind-up, whip and reel. Works on R15 rigs; restored when the cast ends.
	local owner = Players:GetPlayerByUserId(ship:GetAttribute("Owner") :: number? or 0)
	local holder = if owner then owner.Character else nil
	local arms: { { motor: any, c0: CFrame, grip: string } } = {}
	if holder then
		-- the shoulder joints by class (other things can share the name)
		for _, d in holder:GetDescendants() do
			-- classic avatars use Motor6D, newer ones AnimationConstraint: both have Part0/Part1/C0/C1/Transform
			if (d:IsA("Motor6D") or d.ClassName == "AnimationConstraint") and (d.Name == "RightShoulder" or d.Name == "LeftShoulder") then
				table.insert(arms, { motor = d :: any, c0 = (d :: any).C0, grip = d.Name })
			end
		end
	end
	local function poseArms()
		local handle = rodParts.RodHandle
		if not handle then
			return
		end
		for _, a in arms do
			local m = a.motor
			local p0, p1 = m.Part0, m.Part1
			if p0 and p1 then
				-- right hand up the handle, left hand lower down it
				local along = if a.grip == "RightShoulder" then -handle.Size.Z * 0.3 else handle.Size.Z * 0.3
				local grip = (handle.CFrame * CFrame.new(0, 0, along)).Position
				local shoulder = (p0.CFrame * a.c0).Position
				local d = grip - shoulder
				if d.Magnitude > 0.1 then
					local down = d.Unit
					local right = p0.CFrame.RightVector
					local back = right:Cross(-down).Unit
					right = (-down):Cross(back).Unit
					local rot = CFrame.fromMatrix(Vector3.zero, right, -down, back)
					local c1 = m.C1
					local p1cf = CFrame.new(shoulder - (rot * c1).Position) * rot
					-- C0 is read-only on avatars now; the joint's Transform (what animations set)
					-- is writable and is applied after the animator each frame
					local tr = a.c0:Inverse() * p0.CFrame:Inverse() * p1cf * c1
					m.Transform = tr.Rotation
				end
			end
		end
	end
	-- pose after the animator runs and before the physics step places the limbs
	-- (Stepped is the documented spot for overriding Motor6D.Transform), every frame of the cast
	local armConn: RBXScriptConnection? = nil
	if #arms > 0 then
		armConn = RunService.Stepped:Connect(function()
			pcall(poseArms) -- a missing limb must never stop the cast
		end)
	end
	local function releaseArms()
		if armConn then
			armConn:Disconnect()
		end
	end

	local function placeHook(pos: Vector3, t: number)
		hook.CFrame = CFrame.new(pos)
		barb.CFrame = CFrame.new(pos + Vector3.new(0, -1.2, 0)) * CFrame.Angles(0, t * 2, math.sin(t * 6) * 0.2)
	end

	-- the owner's camera follows the hook, blending in and out of the normal camera
	local camera = workspace.CurrentCamera
	local savedFov = camera.FieldOfView
	local camState = { cf = camera.CFrame, fov = savedFov }
	castCount += 1
	local bindName = "EggRodCam" .. castCount
	local t0 = os.clock()
	local passed = 0
	local State = require(script.Parent.State) :: any
	if mine then
		State.cinematic = true
		Hud.refresh()
		RunService:BindToRenderStep(bindName, Enum.RenderPriority.Camera.Value + 1, function()
			local t = os.clock() - t0
			local w = math.clamp(math.min(t / 0.35, (total - t) / 0.5), 0, 1)
			w = w * w * (3 - 2 * w)
			camera.CFrame = camera.CFrame:Lerp(camState.cf, w)
			camera.FieldOfView = savedFov + (camState.fov - savedFov) * w
		end)
	end

	---------------------------------------------------------------------------
	-- Dive scenery. Built around the column as the hook enters each zone: walls dressed to the
	-- zone, fish schools and jellyfish swimming past, swaying kelp / anemones, plankton, and a
	-- colour grade for the whole screen. Everything lives in `fx` and is removed at the end.
	---------------------------------------------------------------------------
	local dressAnims: { (number) -> () } = {}
	local zoneFolders: { [number]: Folder } = {}
	local rng = Random.new(os.clock() * 1000)
	local function mk(parent: Instance, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, ball: boolean?): Part
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = mat or Enum.Material.SmoothPlastic
		if ball then
			p.Shape = Enum.PartType.Ball
		end
		p.Parent = parent
		return p
	end
	local WALL = 23
	local function wallCf(side: number, along: number, y: number, depth: number): CFrame
		-- a spot on a wall of the shaft, local +Z faces the middle of the shaft
		return column * CFrame.Angles(0, side * math.pi / 2, 0) * CFrame.new(along, y, -WALL + depth)
	end
	-- a swaying stack of blocks (kelp, tentacles, anemones)
	local function sway(parent: Instance, base: CFrame, n: number, size: Vector3, colorA: Color3, colorB: Color3, amp: number, glowTip: boolean?)
		local parts: { Part } = {}
		for j = 1, n do
			local last = glowTip and j == n
			parts[j] = mk(parent, size, base, colorA:Lerp(colorB, (j - 1) / math.max(1, n - 1)), if last then Enum.Material.Neon else nil)
		end
		local phase = rng:NextNumber(0, 6)
		table.insert(dressAnims, function(t: number)
			local cf = base
			for j, p in parts do
				cf = cf * CFrame.Angles(math.sin(t * 1.3 + phase + j * 0.5) * amp, 0, math.cos(t * 1.1 + phase + j * 0.4) * amp)
				p.CFrame = cf * CFrame.new(0, size.Y / 2, 0)
				cf = cf * CFrame.new(0, size.Y * 0.92, 0)
			end
		end)
	end
	local function fishSchool(parent: Instance, n: number, y0: number, color: Color3, radius: number, speed: number)
		for i = 1, n do
			local body = mk(parent, Vector3.new(0.7, 0.9, 1.9), CFrame.new(), color, Enum.Material.SmoothPlastic)
			local tail = mk(parent, Vector3.new(0.15, 1.1, 0.8), CFrame.new(), color:Lerp(Color3.new(1, 1, 1), 0.3))
			local eye = mk(parent, Vector3.new(0.78, 0.2, 0.2), CFrame.new(), Color3.new(1, 1, 1))
			local a0 = i / n * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
			local r = radius + rng:NextNumber(-3, 3)
			local yy = y0 + rng:NextNumber(-5, 5)
			local sp = speed * rng:NextNumber(0.85, 1.15)
			table.insert(dressAnims, function(t: number)
				local a = a0 + t * sp
				local pos = column.Position + Vector3.new(math.cos(a) * r, yy + math.sin(t * 1.3 + i) * 1.2, math.sin(a) * r)
				local nxt = column.Position + Vector3.new(math.cos(a + 0.1) * r, yy + math.sin(t * 1.3 + i + 0.1) * 1.2, math.sin(a + 0.1) * r)
				local cf = CFrame.lookAt(pos, nxt)
				body.CFrame = cf
				eye.CFrame = cf * CFrame.new(0, 0.25, -0.7)
				tail.CFrame = cf * CFrame.new(0, 0, 1.15) * CFrame.Angles(0, math.sin(t * 9 + i) * 0.5, 0)
			end)
		end
	end
	local function jellyfish(parent: Instance, pos: Vector3, color: Color3, size: number)
		local bell = mk(parent, Vector3.new(size, size * 0.8, size), CFrame.new(pos), color, Enum.Material.Neon, true)
		bell.Transparency = 0.45
		local l = Instance.new("PointLight")
		l.Color = color
		l.Range = 14
		l.Brightness = 1.5
		l.Parent = bell
		local tents: { Part } = {}
		for j = 1, 5 do
			tents[j] = mk(parent, Vector3.new(0.18, size * 1.5, 0.18), CFrame.new(pos), color, Enum.Material.Neon)
			tents[j].Transparency = 0.3
		end
		local phase = rng:NextNumber(0, 6)
		table.insert(dressAnims, function(t: number)
			local bob = Vector3.new(math.sin(t * 0.7 + phase) * 2, math.sin(t * 1.4 + phase) * 1.5, math.cos(t * 0.6 + phase) * 2)
			local squeeze = 1 + math.sin(t * 3 + phase) * 0.12
			bell.CFrame = CFrame.new(pos + bob)
			bell.Size = Vector3.new(size * squeeze, size * 0.8 / squeeze, size * squeeze)
			for j, tp in tents do
				local a = j / 5 * math.pi * 2
				tp.CFrame = CFrame.new(pos + bob + Vector3.new(math.cos(a) * size * 0.3, -size * 0.9, math.sin(a) * size * 0.3)) * CFrame.Angles(math.sin(t * 2 + j + phase) * 0.25, 0, math.cos(t * 2 + j) * 0.25)
			end
		end)
	end
	local function spawnZone(k: number)
		local z = Config.FISH_ZONES[k]
		local top = Config.SEA_LEVEL - (k - 1) * H
		local f = Instance.new("Folder")
		f.Name = "Zone" .. k
		f.Parent = fx
		zoneFolders[k] = f
		local function yIn(): number
			return top - rng:NextNumber(3, H - 3)
		end
		local function onAnyWall(): (number, number)
			return rng:NextInteger(0, 3), rng:NextNumber(-WALL + 4, WALL - 4)
		end
		if z.id == "Shallows" then
			for _ = 1, 16 do
				local s, a = onAnyWall()
				local cf = wallCf(s, a, yIn(), rng:NextNumber(0, 2))
				mk(f, Vector3.new(rng:NextNumber(4, 8), rng:NextNumber(2, 5), 3), cf, Color3.fromRGB(240, 215, 150), Enum.Material.Sand)
				mk(f, Vector3.new(1.8, 0.4, 1.8), cf * CFrame.new(0, 2.6, 1.5) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), Color3.fromRGB(255, 130, 90))
				mk(f, Vector3.new(0.4, 1.8, 1.8), cf * CFrame.new(0, 2.6, 1.5) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), Color3.fromRGB(255, 130, 90))
				sway(f, cf * CFrame.new(rng:NextNumber(-2, 2), 2, 2), 4, Vector3.new(0.5, 1.6, 0.2), Color3.fromRGB(80, 200, 110), Color3.fromRGB(150, 240, 130), 0.18)
			end
			for r = 1, 6 do
				local ray = mk(f, Vector3.new(2.4, H, 0.3), CFrame.new(column.Position + Vector3.new(rng:NextNumber(-16, 16), top - H / 2, rng:NextNumber(-16, 16))) * CFrame.Angles(0, rng:NextNumber(0, 3), math.rad(10)), Color3.fromRGB(255, 250, 200), Enum.Material.Neon)
				ray.Transparency = 0.86
				table.insert(dressAnims, function(t: number)
					ray.Transparency = 0.82 + math.sin(t * 0.8 + r) * 0.06
				end)
			end
			fishSchool(f, 14, top - H / 2, Color3.fromRGB(255, 200, 70), 16, 0.9)
			fishSchool(f, 8, top - H * 0.7, Color3.fromRGB(90, 190, 255), 19, -0.7)
		elseif z.id == "Kelp" then
			for _ = 1, 22 do
				local s, a = onAnyWall()
				sway(f, wallCf(s, a, top - H, rng:NextNumber(0.5, 3)), rng:NextInteger(8, 12), Vector3.new(1.3, 3.6, 0.5), Color3.fromRGB(30, 120, 60), Color3.fromRGB(110, 230, 100), 0.1)
			end
			for _ = 1, 8 do
				local s, a = onAnyWall()
				local cf = wallCf(s, a, yIn(), 0)
				mk(f, Vector3.new(rng:NextNumber(4, 7), rng:NextNumber(3, 6), 4), cf, Color3.fromRGB(80, 110, 80), Enum.Material.Slate)
			end
			fishSchool(f, 16, top - H / 2, Color3.fromRGB(120, 230, 120), 16, 1.0)
			fishSchool(f, 6, top - H * 0.3, Color3.fromRGB(255, 220, 120), 20, -0.8)
			jellyfish(f, column.Position + Vector3.new(-9, top - H * 0.4, 7), Color3.fromRGB(170, 255, 190), 3.2)
		elseif z.id == "Reef" then
			local cols = { Color3.fromRGB(255, 110, 150), Color3.fromRGB(255, 165, 60), Color3.fromRGB(185, 100, 255), Color3.fromRGB(60, 225, 205) }
			for i = 1, 26 do
				local s, a = onAnyWall()
				local cf = wallCf(s, a, yIn(), rng:NextNumber(0, 2))
				local col = cols[i % 4 + 1]
				if i % 3 == 0 then
					for b = 1, 4 do
						mk(f, Vector3.one * rng:NextNumber(1.8, 3.4), cf * CFrame.new(rng:NextNumber(-2.5, 2.5), b * 1.1, rng:NextNumber(0, 2)), col, nil, true)
					end
				elseif i % 3 == 1 then
					for b = 0, 4 do
						mk(f, Vector3.new(0.8, 2.8, 0.8), cf * CFrame.new(b * 0.9 - 1.8, 1.4 + math.abs(b - 2) * 0.5, 1) * CFrame.Angles(0, 0, math.rad((b - 2) * 22)), col)
					end
				else
					sway(f, cf * CFrame.new(0, 0, 1.5), 3, Vector3.new(0.6, 1.4, 0.6), col, Color3.fromRGB(255, 255, 160), 0.22, true)
					sway(f, cf * CFrame.new(1.2, 0, 1.5), 3, Vector3.new(0.5, 1.2, 0.5), col, Color3.fromRGB(255, 255, 160), 0.26, true)
				end
			end
			fishSchool(f, 14, top - H / 2, Color3.fromRGB(255, 120, 60), 16, 1.1)
			fishSchool(f, 10, top - H * 0.65, Color3.fromRGB(80, 160, 255), 20, -0.9)
			jellyfish(f, column.Position + Vector3.new(8, top - H * 0.35, -8), Color3.fromRGB(255, 130, 200), 3.6)
			jellyfish(f, column.Position + Vector3.new(-10, top - H * 0.75, 6), Color3.fromRGB(150, 130, 255), 2.8)
		elseif z.id == "Wreck" then
			local WOODW = Color3.fromRGB(95, 70, 52)
			for i = 1, 7 do
				-- broken ship ribs curving out of the wall
				local s, a = onAnyWall()
				local cf = wallCf(s, a, top - H + 2, 2)
				for b = 0, 6 do
					mk(f, Vector3.new(0.9, 2.6, 0.9), cf * CFrame.new(0, 1.3 + b * 2.2 * 0.8, b * b * 0.18) * CFrame.Angles(math.rad(-b * 9), 0, 0), WOODW, Enum.Material.Wood)
				end
				local _ = i
			end
			for i = 1, 9 do
				local s, a = onAnyWall()
				local cf = wallCf(s, a, yIn(), rng:NextNumber(0, 2))
				if i % 3 == 0 then
					mk(f, Vector3.new(2.6, 2, 2), cf, Color3.fromRGB(120, 80, 40), Enum.Material.Wood)
					local g = mk(f, Vector3.new(2.2, 0.5, 1.6), cf * CFrame.new(0, 1.2, 0), Color3.fromRGB(255, 205, 60), Enum.Material.Neon)
					local l = Instance.new("PointLight")
					l.Color = Color3.fromRGB(255, 205, 90)
					l.Range = 12
					l.Parent = g
				elseif i % 3 == 1 then
					mk(f, Vector3.new(1.2, 4.5, 1.2), cf, Color3.fromRGB(60, 62, 75), Enum.Material.Metal) -- anchor shaft
					mk(f, Vector3.new(3.8, 0.9, 0.9), cf * CFrame.new(0, 1.8, 0), Color3.fromRGB(60, 62, 75), Enum.Material.Metal)
					mk(f, Vector3.new(3.6, 0.9, 0.9), cf * CFrame.new(0, -2.0, 0) * CFrame.Angles(0, 0, math.rad(25)), Color3.fromRGB(60, 62, 75), Enum.Material.Metal)
				else
					mk(f, Vector3.new(1.8, 2.2, 1.8), cf, Color3.fromRGB(130, 90, 55), Enum.Material.Wood, false) -- barrel
				end
			end
			for i = 1, 5 do
				local s, a = onAnyWall()
				sway(f, wallCf(s, a, yIn(), 1), 5, Vector3.new(0.35, 2.2, 0.2), Color3.fromRGB(70, 60, 55), Color3.fromRGB(120, 110, 100), 0.12) -- tattered rope
				local _ = i
			end
			fishSchool(f, 8, top - H / 2, Color3.fromRGB(190, 190, 205), 17, 0.7)
			jellyfish(f, column.Position + Vector3.new(7, top - H * 0.5, 9), Color3.fromRGB(190, 255, 255), 3)
		else
			-- the Abyss: black spires with glowing crystals, bioluminescent drifters, hanging tentacles
			for i = 1, 20 do
				local s, a = onAnyWall()
				local h = rng:NextNumber(6, 18)
				local cf = wallCf(s, a, top - H, rng:NextNumber(0, 3))
				mk(f, Vector3.new(rng:NextNumber(2, 4), h, rng:NextNumber(2, 4)), cf * CFrame.new(0, h / 2, 0), Color3.fromRGB(28, 22, 42), Enum.Material.Basalt)
				if i % 2 == 0 then
					local c = mk(f, Vector3.new(1.6, 3, 1.6), cf * CFrame.new(0, h + 1.2, 0) * CFrame.Angles(math.rad(25), math.rad(40), 0), z.color, Enum.Material.Neon)
					local l = Instance.new("PointLight")
					l.Color = z.color
					l.Range = 18
					l.Brightness = 2
					l.Parent = c
				end
			end
			for _ = 1, 10 do
				local s, a = onAnyWall()
				sway(f, wallCf(s, a, top - rng:NextNumber(2, 10), 1), 9, Vector3.new(0.5, 2.4, 0.5), Color3.fromRGB(40, 20, 70), Color3.fromRGB(190, 110, 255), 0.2, true)
			end
			for _ = 1, 6 do
				jellyfish(f, column.Position + Vector3.new(rng:NextNumber(-12, 12), yIn(), rng:NextNumber(-12, 12)), Color3.fromRGB(rng:NextInteger(120, 220), 90, 255), rng:NextNumber(2.4, 4.2))
			end
			fishSchool(f, 6, top - H / 2, Color3.fromRGB(150, 90, 255), 16, 0.8)
		end
	end
	-- colour grade of the whole screen, tweened per zone (owner only)
	local grade: ColorCorrectionEffect? = nil
	local grades = {
		Shallows = { tint = Color3.fromRGB(215, 250, 255), brightness = 0.04, contrast = 0.05, saturation = 0.25 },
		Kelp = { tint = Color3.fromRGB(190, 255, 205), brightness = 0, contrast = 0.08, saturation = 0.3 },
		Reef = { tint = Color3.fromRGB(255, 215, 235), brightness = 0.02, contrast = 0.1, saturation = 0.5 },
		Wreck = { tint = Color3.fromRGB(225, 200, 160), brightness = -0.06, contrast = 0.15, saturation = 0.05 },
		Abyss = { tint = Color3.fromRGB(165, 125, 255), brightness = -0.22, contrast = 0.25, saturation = 0.35 },
	}
	local function setGrade(id: string)
		if not mine then
			return
		end
		local Lighting = game:GetService("Lighting")
		if not grade then
			grade = Instance.new("ColorCorrectionEffect")
			grade.Name = "DiveGrade"
			grade.Parent = Lighting
		end
		local g = grades[id]
		if g and grade then
			UI.tween(grade, 0.9, { TintColor = g.tint, Brightness = g.brightness, Contrast = g.contrast, Saturation = g.saturation })
		end
	end
	-- plankton drifting past the camera as the hook sinks
	local plankton = Instance.new("ParticleEmitter")
	plankton.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	plankton.Color = ColorSequence.new(Color3.fromRGB(220, 250, 255))
	plankton.LightEmission = 0.8
	plankton.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.1) })
	plankton.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	plankton.Lifetime = NumberRange.new(2.5, 4)
	plankton.Speed = NumberRange.new(1, 3)
	plankton.SpreadAngle = Vector2.new(180, 180)
	plankton.Rate = 0
	plankton.Parent = att0

	-- the nest the hook pulls the egg from: a ring of rocks with three sleeping eggs
	local nestBase = Vector3.new(stopPos.X, bottomY - 4.6, stopPos.Z)
	local nestFolder = Instance.new("Folder")
	nestFolder.Name = "Nest"
	nestFolder.Parent = fx
	local decoyEggs: { Model } = {}
	local nestEggAt = nestBase + Vector3.new(0, 1.6, 0)
	do
		mk(nestFolder, Vector3.new(9, 1, 9), CFrame.new(nestBase), Color3.fromRGB(95, 100, 120), Enum.Material.Slate)
		for i = 0, 9 do
			local a = i / 10 * math.pi * 2
			mk(nestFolder, Vector3.new(2.2, rng:NextNumber(1.4, 2.6), 1.6), CFrame.new(nestBase + Vector3.new(math.cos(a) * 4.4, 1.2, math.sin(a) * 4.4)) * CFrame.Angles(0, -a, 0), Color3.fromRGB(110, 115, 135), Enum.Material.Slate)
		end
		for i, off in { Vector3.new(-2.2, 0, 1.4), Vector3.new(2.2, 0, 1.2) } do
			local e = MonsterModels.buildEgg("Splashfin", 1.2, true)
			e:PivotTo(CFrame.new(nestBase + Vector3.new(off.X, 1.5, off.Z)) * CFrame.Angles(0, i * 2, 0.15))
			e.Parent = nestFolder
			decoyEggs[i] = e
		end
		local glowPart = mk(nestFolder, Vector3.one, CFrame.new(nestEggAt + Vector3.new(0, 1, 0)), zdef.color, nil)
		glowPart.Transparency = 1
		local gl = Instance.new("PointLight")
		gl.Color = zdef.color
		gl.Range = 22
		gl.Brightness = 2.5
		gl.Parent = glowPart
	end
	nestFolder.Parent = nil

	local hookPos = splashPos
	task.spawn(function()
		local grabbed, flew, splashed, landedFx = false, false, false, false
		local popped = false
		while rod.Parent do
			local t = os.clock() - t0
			if t >= total then
				break
			end
			if t < CAST then
				-- Blender cast: wind up, whip, the hook arcs out to sea
				poseRod(t)
				hookPos = (base * (trackCf("Hook", t))).Position
				local cf = base * (trackCf("Cam", t))
				camState.cf = cf
				camState.fov = camFov(t)
			elseif t < tGrab then
				-- the dive: fast at first, easing into the stop zone
				if not splashed then
					splashed = true
					splash(splashPos, 6)
					bubbles.Rate = 40
					if mine then
						Sound.play("Splash", 0.8, 0.9)
					end
				end
				poseRod(CAST + math.sin(t * 3) * 0.05)
				if not nestFolder.Parent then
					nestFolder.Parent = fx
				end
				local u = (t - CAST) / DOWN
				local e = 1 - (1 - u) ^ 2.2
				local col = splashPos:Lerp(Vector3.new(column.X, splashPos.Y, column.Z), math.min(1, u * 4))
				hookPos = Vector3.new(col.X + math.sin(t * 4) * 1.2, splashPos.Y + (bottomY - splashPos.Y) * e, col.Z + math.cos(t * 3) * 1.2)
				-- crossing into a new zone: banner + ring flash
				local inZone = math.clamp(math.floor((Config.SEA_LEVEL - hookPos.Y) / H) + 1, 1, #Config.FISH_ZONES)
				if inZone > passed then
					passed = inZone
					local z = Config.FISH_ZONES[inZone]
					burst(hookPos, z.color, 16, 8, true)
					trail.Color = ColorSequence.new(Color3.fromRGB(150, 240, 255), z.color)
					hookLight.Color = z.color
					plankton.Color = ColorSequence.new(z.color:Lerp(Color3.new(1, 1, 1), 0.5))
					plankton.Rate = 45
					spawnZone(inZone)
					if zoneFolders[inZone - 2] then
						zoneFolders[inZone - 2]:Destroy()
					end
					setGrade(z.id)
					-- a glowing gate marks the zone boundary the hook flies through
					for g = 0, 7 do
						local ga = g / 8 * math.pi * 2
						local gate = mk(fx, Vector3.new(7, 0.6, 0.6), CFrame.new(Vector3.new(column.X, Config.SEA_LEVEL - (inZone - 1) * H, column.Z) + Vector3.new(math.cos(ga) * 14, 0, math.sin(ga) * 14)) * CFrame.Angles(0, -ga + math.pi / 2, 0), z.color, Enum.Material.Neon)
						gate.Transparency = 0.2
						UI.tween(gate, 1.4, { Transparency = 0.85 })
					end
					if mine then
						Hud.toast(string.upper(z.name), z.color)
						Sound.play("Click", 0.6, 0.8 + inZone * 0.12)
					end
				end
				-- the camera orbits the hook so the scenery slides by at different distances
				local ang = (t - CAST) * 0.55
				local orbit = Vector3.new(math.cos(ang) * 11, 5, math.sin(ang) * 11)
				camState.cf = CFrame.lookAt(hookPos + orbit, hookPos - Vector3.new(0, 3, 0))
				camState.fov = 68
			elseif t < tUp then
				-- the grab: the hook finds the egg, a flash in the zone's colour
				if not grabbed then
					grabbed = true
					bubbles.Rate = 10
					burst(hookPos, zdef.color, 30, 12, true)
					if mine then
						Hud.splash(string.upper(zdef.name) .. "!", zdef.color)
						Sound.play("Super", 0.8)
					end
					eggs[1].Parent = fx
				end
				-- the hook settles on the egg, the line tugs, the egg shakes in its nest and
				-- then POPS free in a puff of dust and rides up on the hook
				local u = (t - tGrab) / GRAB
				hookPos = stopPos + Vector3.new(0, math.sin(math.min(u * 1.6, 1) * math.pi) * -1.2, 0)
				local pull = math.clamp((u - 0.55) / 0.3, 0, 1)
				pull = pull * pull * (3 - 2 * pull)
				local shake = if u > 0.2 and u < 0.6 then math.sin(t * 60) * 0.18 * (u - 0.15) * 2.2 else 0
				local eggPos = nestEggAt:Lerp(hookPos + Vector3.new(0, -2.8, 0), pull) + Vector3.new(shake, 0, shake * 0.6)
				eggs[1]:PivotTo(CFrame.new(eggPos) * CFrame.Angles(shake * 1.5, t * (2 + pull * 6), shake))
				for i, de in decoyEggs do
					de:PivotTo(de:GetPivot() * CFrame.Angles(0, 0, math.sin(t * 40 + i) * 0.01 * (1 - pull)))
				end
				if u >= 0.58 and not popped then
					popped = true
					burst(nestEggAt, Color3.fromRGB(190, 190, 205), 26, 9, false)
					burst(nestEggAt, zdef.color, 18, 10, true)
					if mine then
						Sound.play("Hit", 0.7, 0.7)
					end
				end
				camState.cf = CFrame.lookAt(hookPos + Vector3.new(math.cos(t * 0.6) * 7, 1.5, math.sin(t * 0.6) * 7), nestEggAt + Vector3.new(0, 1, 0))
				camState.fov = 48
			elseif t < tFly then
				-- ride back up with the catch, the rod heaving
				bubbles.Rate = 60
				local u = (t - tUp) / UP
				local e = u * u * (3 - 2 * u)
				poseRod(RodAnim.GRAB + (RodAnim.HAULEND - RodAnim.GRAB) * e)
				local tip = tipPos()
				local top = tip + Vector3.new(0, -2.6, 0)
				hookPos = stopPos:Lerp(top, e)
				if hookPos.Y > Config.SEA_LEVEL and not landedFx then
					landedFx = true
					splash(Vector3.new(hookPos.X, Config.SEA_LEVEL, hookPos.Z), 7)
					burst(hookPos, zdef.color, 20, 10, true)
				end
				for i, eg in eggs do
					local a = (i - 1) / #eggs * math.pi * 2 + t * 4
					eg:PivotTo(CFrame.new(hookPos + Vector3.new(math.cos(a) * (#eggs > 1 and 1.6 or 0), -2.8, math.sin(a) * (#eggs > 1 and 1.6 or 0))) * CFrame.Angles(0, t * 5, 0))
				end
				camState.cf = CFrame.lookAt(hookPos - column.RightVector * 14 + Vector3.new(0, -4 + 10 * e, 0), hookPos)
				camState.fov = 66
			else
				-- the eggs fly off the hook onto the pedestals, still black
				if not flew then
					flew = true
					bubbles.Rate = 0
				end
				local u = math.clamp((t - tFly) / FLY, 0, 1)
				poseRod(RodAnim.HAULEND + (RodAnim.DURATION - RodAnim.HAULEND) * u)
				for i, eg in eggs do
					local ped = ship:FindFirstChild("Pedestal" .. i, true) :: BasePart?
					local dest = if ped then ped.Position + Vector3.new(0, 3.2, 0) else hookPos
					local p = hookPos:Lerp(dest, u) + Vector3.new(0, math.sin(u * math.pi) * 10, 0)
					eg:PivotTo(CFrame.new(p) * CFrame.Angles(0, u * 8, 0))
				end
				local ped1 = ship:FindFirstChild("Pedestal1", true) :: BasePart?
				if ped1 then
					camState.cf = CFrame.lookAt(ped1.Position - column.RightVector * 16 + Vector3.new(0, 14, 0), ped1.Position)
				end
			end
			placeHook(hookPos, t)
			for _, fn in dressAnims do
				fn(t)
			end
			-- surfacing: scenery fades out with the colour grade and the plankton stops
			if t >= tUp then
				plankton.Rate = 0
				if grade and grade.Parent and not (grade :: any):GetAttribute("Fading") then
					(grade :: any):SetAttribute("Fading", true)
					UI.tween(grade :: any, 0.8, { TintColor = Color3.new(1, 1, 1), Brightness = 0, Contrast = 0, Saturation = 0 })
				end
			end
			drawLine(tipPos(), hookPos + Vector3.new(0, 0.7, 0))
			task.wait()
		end
		poseRod(0)
		releaseArms()
		if grade then
			grade:Destroy()
		end
		for i = 1, #eggs do
			local ped = ship:FindFirstChild("Pedestal" .. i, true) :: BasePart?
			if ped then
				burst(ped.Position + Vector3.new(0, 3, 0), Color3.fromRGB(255, 230, 120), 14, 6, true)
			end
		end
		if mine then
			Sound.play("Winch", 0.6, 1.2)
			RunService:UnbindFromRenderStep(bindName)
			State.cinematic = false
			Hud.refresh()
			camera.FieldOfView = savedFov
		end
		fx:Destroy()
		casting[rod] = nil
	end)
end

-- Small reactions on the ship (fuse hearts, haul)
local function onShipEvent(owner: number, kind: string, p: any)
	local ship = shipOf(owner)
	if not ship then
		return
	end
	if kind == "haul" then
		BattleView.castRod(ship, (p and p.count) or 1, (p and p.zone) or 1, (p and p.time) or Config.FISH_TIME, owner == player.UserId)
	elseif kind == "fuse" then
		local a = ship:FindFirstChild("Nest" .. p.into, true) :: BasePart?
		if a then
			burst(a.Position + Vector3.new(0, 3, 0), Color3.fromRGB(255, 120, 180), 18, 5, true)
		end
		if owner == player.UserId then
			Sound.play("Fuse", 0.8)
		end
	elseif kind == "hatch" then
		local a = ship:FindFirstChild("Nest" .. p.nest, true) :: BasePart?
		if a then
			burst(a.Position + Vector3.new(0, 3, 0), MonsterModels.elementColor(p.sp), 20, 6, true)
		end
	end
end

---------------------------------------------------------------------------
-- Per-frame animation
---------------------------------------------------------------------------
local function animate(u: Unit, t: number, dt: number, towards: Vector3?)
	local cf = u.home
	if u.fly then
		local fl = u.fly
		fl.t += dt / 1.1
		local k = math.clamp(fl.t, 0, 1)
		local e = 1 - (1 - k) ^ 3
		local pos = fl.from.Position:Lerp(u.home.Position, e) + Vector3.new(0, math.sin(k * math.pi) * 14, 0)
		cf = CFrame.new(pos) * u.home.Rotation
		if k >= 1 then
			u.fly = nil
			splash(u.home.Position, 3)
		end
	end
	if u.lungeT > 0 then
		u.lungeT += dt
		local k = u.lungeT / 0.3
		if k >= 1 then
			u.lungeT = 0
		elseif towards then
			local dir = (towards - u.home.Position) * Vector3.new(1, 0, 1)
			if dir.Magnitude > 0.1 then
				cf = cf + dir.Unit * math.sin(k * math.pi) * 3.2
			end
		end
	end
	if u.sink > 0 then
		-- rising out of the water at spawn
		u.sink = math.max(0, u.sink - dt * 1.6)
		cf = cf * CFrame.new(0, -u.sink * 6, 0)
	end
	if not u.alive then
		u.sink = 0
		u.flash = 0
		u.phase += dt
		cf = cf * CFrame.new(0, -math.min(6, u.phase * 4), 0) * CFrame.Angles(0, 0, math.min(1.2, u.phase))
		MonsterModels.fade(u.rig, math.min(1, u.phase * 0.8))
	end
	if u.flash > 0 then
		MonsterModels.tint(u.rig, Color3.new(1, 1, 1), u.flash)
		u.flash = math.max(0, u.flash - dt * 6)
		if u.flash == 0 then
			MonsterModels.tint(u.rig, nil, 0)
		end
	elseif u.flash < 0 then
		MonsterModels.tint(u.rig, Color3.fromRGB(255, 60, 60), -u.flash)
		u.flash = math.min(0, u.flash + dt * 5)
		if u.flash == 0 then
			MonsterModels.tint(u.rig, nil, 0)
		end
	end
	MonsterModels.pose(u.rig, cf, t + u.phase, true, true)
end

function BattleView.init()
	Remotes.event("Battle").OnClientEvent:Connect(function(owner: number, kind: string, p: any)
		if kind == "start" then
			onStart(owner, p)
		elseif kind == "wave" then
			onWave(owner, p)
		elseif kind == "hit" then
			onHit(owner, p)
		elseif kind == "enemyHit" then
			onEnemyHit(owner, p)
		elseif kind == "faint" then
			onFaint(owner, p)
		elseif kind == "kill" then
			onKill(owner, p)
		elseif kind == "end" then
			onEnd(owner, p)
		else
			onShipEvent(owner, kind, p)
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		local t = os.clock()
		local cam = workspace.CurrentCamera.CFrame.Position
		for _, f in fights do
			local near = (f.arena.Position - cam).Magnitude < 350
			FX.Parent = workspace
			if near then
				local ePos = if f.enemy then f.enemy.home.Position else nil
				for _, u in f.team do
					animate(u, t, dt, ePos)
				end
				if f.enemy then
					local front = if #f.team > 0 then f.team[math.clamp(math.floor(#f.team / 2 + 0.5), 1, #f.team)].home.Position else nil
					animate(f.enemy, t, dt, front)
				end
			end
		end
	end)
end

return BattleView
