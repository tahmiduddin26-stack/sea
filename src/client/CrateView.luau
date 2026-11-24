--!strict
-- What everyone sees of the live crates and the Cannon Gallery (server/CrateService):
--   cannons   the Blender "Cannon" rig on both gallery platforms of every ship, turned to the last aim
--             its gunner fired with (your own cannon follows your live aim, CannonView.setAim)
--   crates    the server's crates (workspace.LiveCrates) bob on the water, with a far-visible tag and
--             a health bar; hits flash them, breaks blow them apart
--   shots     every player's cannonball flies the shared arc (shared/Ballistics) and splashes
--   CrateUI   "Crate drop in 0:30!", "5 crates dropped!" and "<name> smashed a Golden Chest!"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Ballistics = require(Shared.Ballistics)
local MonsterModels = require(Shared.MonsterModels)

local UI = require(script.Parent.UI)
local Sound = require(script.Parent.Sound)

local CrateView = {}

local player = Players.LocalPlayer
local C = UI.Colors
local L = Config.LIVE_CRATES
local DRAW_DIST = 420

type Gun = { rig: MonsterModels.Rig, base: CFrame, yaw: number, pitch: number, kick: number }
local guns: { [string]: Gun } = {} -- "ship:side"
local fxFolder = Instance.new("Folder")
fxFolder.Name = "CannonFx"
fxFolder.Parent = workspace

local screen: ScreenGui? = nil
local feed: Frame? = nil
local countdown: TextLabel? = nil

---------------------------------------------------------------------------
-- cannons
---------------------------------------------------------------------------
-- pose a gun: carriage turned by yaw, barrel (bone 2 and its children) tilted by pitch
local function poseGun(g: Gun)
	local rig = g.rig
	local S = rig.scale
	local origin = g.base * CFrame.Angles(0, g.yaw, 0) * CFrame.new(0, 0, g.kick)
	local piv = CFrame.new(Ballistics.PIVOT * S)
	local tilt = origin * piv * CFrame.Angles(g.pitch, 0, 0) * piv:Inverse()
	for k, _ in rig.parts do
		rig.cframes[k] = (if rig.bone[k] >= 2 then tilt else origin) * rig.localCf[k]
	end
	workspace:BulkMoveTo(rig.parts, rig.cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

local function buildGuns()
	local world = workspace:WaitForChild("World")
	local function watch(m: Instance)
		local idx = m:GetAttribute("ShipIndex")
		local cf = m:GetAttribute("ShipCf") :: CFrame?
		if not idx or not cf then
			return
		end
		for side in Config.CANNON_GAME_POS do
			local key = idx .. ":" .. side
			if not guns[key] then
				local rig = MonsterModels.build("Cannon", Ballistics.SCALE)
				if rig then
					rig.model.Parent = fxFolder
					guns[key] = { rig = rig, base = Ballistics.base(cf, side), yaw = 0, pitch = math.rad(8), kick = 0 }
					poseGun(guns[key])
				end
			end
		end
	end
	for _, m in world:GetChildren() do
		watch(m)
	end
	world.ChildAdded:Connect(function(m)
		task.defer(watch, m)
	end)
end

function CrateView.gun(ship: number, side: string): Gun?
	return guns[ship .. ":" .. side]
end

function CrateView.setAim(ship: number, side: string, yaw: number, pitch: number)
	local g = guns[ship .. ":" .. side]
	if g then
		g.yaw, g.pitch = yaw, pitch
		poseGun(g)
	end
end

---------------------------------------------------------------------------
-- effects
---------------------------------------------------------------------------
local function burst(at: Vector3, color: Color3, size: number, neon: boolean)
	local s = Instance.new("Part")
	s.Shape = Enum.PartType.Ball
	s.Anchored, s.CanCollide, s.CanQuery, s.CanTouch, s.CastShadow = true, false, false, false, false
	s.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	s.Color = color
	s.Size = Vector3.one * 1.5
	s.Position = at
	s.Parent = fxFolder
	TweenService:Create(s, TweenInfo.new(0.4), { Size = Vector3.one * size, Transparency = 1 }):Play()
	task.delay(0.45, function()
		s:Destroy()
	end)
end

-- a water splash: a white column that rises and falls
local function splash(at: Vector3)
	local p = Vector3.new(at.X, Config.SEA_LEVEL, at.Z)
	local col = Instance.new("Part")
	col.Anchored, col.CanCollide, col.CanQuery, col.CanTouch, col.CastShadow = true, false, false, false, false
	col.Shape = Enum.PartType.Cylinder
	col.Color = Color3.fromRGB(225, 245, 255)
	col.Transparency = 0.25
	col.Size = Vector3.new(1, 3, 3)
	col.CFrame = CFrame.new(p) * CFrame.Angles(0, 0, math.rad(90))
	col.Parent = fxFolder
	TweenService:Create(col, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Size = Vector3.new(9, 4, 4), CFrame = CFrame.new(p + Vector3.new(0, 4.5, 0)) * CFrame.Angles(0, 0, math.rad(90)), Transparency = 1 }):Play()
	burst(p, Color3.fromRGB(235, 250, 255), 7, false)
	task.delay(0.55, function()
		col:Destroy()
	end)
end

-- a cannonball flying the shared arc; `onEnd(pos, hitCrate?)` when it lands or meets a crate
function CrateView.flyBall(p0: Vector3, v0: Vector3, onEnd: ((Vector3, BasePart?) -> ())?)
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Anchored, ball.CanCollide, ball.CanQuery, ball.CanTouch = true, false, false, false
	-- big and glowing so it reads against the sea and the sky from the gun
	ball.Size = Vector3.one * 2.6
	ball.Color = Color3.fromRGB(40, 40, 52)
	ball.Material = Enum.Material.Metal
	ball.Position = p0
	ball.Parent = fxFolder
	local glow = Instance.new("Part")
	glow.Shape = Enum.PartType.Ball
	glow.Anchored, glow.CanCollide, glow.CanQuery, glow.CanTouch, glow.CastShadow = true, false, false, false, false
	glow.Size = Vector3.one * 3.6
	glow.Material = Enum.Material.Neon
	glow.Color = Color3.fromRGB(255, 150, 50)
	glow.Transparency = 0.55
	glow.Parent = ball
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 170, 80)
	light.Range = 14
	light.Brightness = 3
	light.Parent = ball
	local hl = Instance.new("Highlight")
	hl.FillTransparency = 1
	hl.OutlineColor = Color3.fromRGB(255, 230, 120)
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = ball
	local trail = Instance.new("Trail")
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Position, a1.Position = Vector3.new(0, 1.2, 0), Vector3.new(0, -1.2, 0)
	a0.Parent, a1.Parent = ball, ball
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime = 0.6
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 90, 40))
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.Parent = ball
	burst(p0, Color3.fromRGB(255, 200, 90), 6, true)
	local crates = workspace:FindFirstChild("LiveCrates")
	local t0 = os.clock()
	task.spawn(function()
		local pos = p0
		local hit: BasePart? = nil
		while true do
			local t = os.clock() - t0
			pos = Ballistics.at(p0, v0, t)
			ball.Position = pos
			glow.Position = pos
			if crates then
				for _, c in crates:GetChildren() do
					local cp = c :: BasePart
					if (cp:GetAttribute("Hp") :: number? or 0) > 0 and (cp.Position - pos).Magnitude < math.max(cp.Size.X, cp.Size.Y, cp.Size.Z) / 2 + L.hitPad then
						hit = cp
					end
				end
			end
			if hit or pos.Y < Config.SEA_LEVEL or t > 8 then
				break
			end
			RunService.Heartbeat:Wait()
		end
		ball:Destroy()
		if hit then
			burst(pos, Color3.fromRGB(255, 170, 70), 9, true)
		else
			splash(pos)
		end
		local cam = workspace.CurrentCamera.CFrame.Position
		if (pos - cam).Magnitude < 260 then
			Sound.play(if hit then "Hit" else "Place", 0.5, if hit then 1 else 0.6)
		end
		if onEnd then
			onEnd(pos, hit)
		end
	end)
end

---------------------------------------------------------------------------
-- crates: bob, tag, health bar
---------------------------------------------------------------------------
local KIND_COL: { [string]: Color3 } = { Crate = Color3.fromRGB(255, 225, 160), Barrel = Color3.fromRGB(255, 130, 110), Gold = Color3.fromRGB(255, 215, 70) }
local tagged: { [BasePart]: { rest: CFrame, phase: number, bar: Frame? } } = {}

local function tag(c: BasePart)
	if tagged[c] then
		return
	end
	local kind = c:GetAttribute("Kind") :: string
	local bb = UI.new("BillboardGui", { Size = UDim2.fromOffset(110, 44), StudsOffsetWorldSpace = Vector3.new(0, c.Size.Y / 2 + 3, 0), AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 700, Parent = c })
	UI.label({ Text = if kind == "Gold" then "GOLD!" elseif kind == "Barrel" then "BARREL" else "CRATE", TextColor3 = KIND_COL[kind] or C.White, MaxText = 20, Size = UDim2.new(1, 0, 0, 24), Parent = bb })
	local back = UI.new("Frame", { BackgroundColor3 = C.Ink, Size = UDim2.new(0.8, 0, 0, 9), Position = UDim2.new(0.1, 0, 0, 28), BorderSizePixel = 0, Parent = bb }, { UI.corner(4) })
	local bar = UI.new("Frame", { BackgroundColor3 = KIND_COL[kind] or C.Gold, Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, Parent = back }, { UI.corner(4) })
	back.Visible = ((c:GetAttribute("MaxHp") :: number?) or 1) > 1
	tagged[c] = { rest = c.CFrame, phase = math.random() * 6, bar = bar }
	c.AncestryChanged:Connect(function()
		if not c.Parent then
			tagged[c] = nil
		end
	end)
	c:GetAttributeChangedSignal("Hp"):Connect(function()
		local hp = (c:GetAttribute("Hp") :: number?) or 0
		local max = (c:GetAttribute("MaxHp") :: number?) or 1
		UI.tween(bar, 0.2, { Size = UDim2.fromScale(math.max(0, hp / max), 1) })
	end)
end

---------------------------------------------------------------------------
-- a crate breaking open: walls fall outwards, the lid flies off spinning, and the loot (coins, plus
-- pearls in barrels and golden chests) sprays up out of it and falls into the sea. Scripted arcs
-- (anchored parts), so it looks the same on every screen.
---------------------------------------------------------------------------
local function fling(p: BasePart, from: CFrame, vel: Vector3, spin: Vector3, life: number, fade: boolean)
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.CFrame = from
	p.Parent = fxFolder
	local t0 = os.clock()
	task.spawn(function()
		while p.Parent do
			local t = os.clock() - t0
			if t > life then
				break
			end
			local pos = from.Position + vel * t + Vector3.new(0, -0.5 * 70 * t * t, 0)
			p.CFrame = CFrame.new(pos) * from.Rotation * CFrame.Angles(spin.X * t, spin.Y * t, spin.Z * t)
			if fade then
				p.Transparency = math.clamp((t / life - 0.6) / 0.4, 0, 1)
			end
			if pos.Y < Config.SEA_LEVEL - 2 then
				break
			end
			RunService.Heartbeat:Wait()
		end
		p:Destroy()
	end)
end

local function breakOpen(cp: BasePart, kind: string)
	local cf = cp.CFrame
	local s = cp.Size
	local col = cp.Color
	local mat = cp.Material
	burst(cf.Position, Color3.fromRGB(255, 220, 120), 16, true)
	-- the four walls hinge outwards
	for i = 0, 3 do
		local a = i * math.pi / 2
		local wall = Instance.new("Part")
		wall.Size = Vector3.new(s.X, s.Y, 0.5)
		wall.Color = col
		wall.Material = mat
		local face = cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -s.Z / 2)
		local out = (face.Position - cf.Position).Unit
		fling(wall, face, out * 14 + Vector3.new(0, 10, 0), Vector3.new(-3, 0, 0), 1.6, true)
	end
	-- the lid pops high and spins
	local lid = Instance.new("Part")
	lid.Size = Vector3.new(s.X + 0.4, 0.6, s.Z + 0.4)
	lid.Color = col:Lerp(Color3.new(0, 0, 0), 0.15)
	lid.Material = mat
	fling(lid, cf * CFrame.new(0, s.Y / 2, 0), Vector3.new(math.random(-6, 6), 42, math.random(-6, 6)), Vector3.new(6, 3, 4), 2.2, true)
	-- the loot
	local n = if kind == "Gold" then 22 elseif kind == "Barrel" then 14 else 9
	for i = 1, n do
		local pearl = kind ~= "Crate" and i % 3 == 0
		local coin = Instance.new("Part")
		coin.Shape = if pearl then Enum.PartType.Ball else Enum.PartType.Cylinder
		coin.Size = if pearl then Vector3.one * 1.1 else Vector3.new(0.3, 1.6, 1.6)
		coin.Color = if pearl then Color3.fromRGB(240, 235, 255) else Color3.fromRGB(255, 205, 50)
		coin.Material = if pearl then Enum.Material.SmoothPlastic else Enum.Material.Neon
		local dir = CFrame.Angles(0, math.random() * math.pi * 2, 0).LookVector
		fling(coin, cf, dir * math.random(6, 16) + Vector3.new(0, math.random(28, 46), 0), Vector3.new(0, 10, 0), 2.5, false)
	end
	local cam = workspace.CurrentCamera.CFrame.Position
	if (cf.Position - cam).Magnitude < 300 then
		Sound.play(if kind == "Gold" then "Super" else "Coin", 0.8)
	end
end

---------------------------------------------------------------------------
-- the little feed + drop countdown (top centre, under the HUD's top bar)
---------------------------------------------------------------------------
local function post(text: string, color: Color3?)
	local f = feed
	if not f then
		return
	end
	local l = UI.label({ Text = text, TextColor3 = color or C.White, MaxText = 24, Size = UDim2.new(1, 0, 0, 28), Parent = f })
	task.delay(5, function()
		UI.tween(l, 0.4, { TextTransparency = 1 })
		task.wait(0.45)
		l:Destroy()
	end)
end

local KIND_NAME: { [string]: string } = {}
for _, k in L.kinds do
	KIND_NAME[k.id] = k.name
end

function CrateView.init(root: ScreenGui)
	screen = root
	local holder = UI.new("Frame", { Name = "CrateFeed", BackgroundTransparency = 1, Size = UDim2.fromOffset(560, 120), Position = UDim2.new(0.5, 0, 0, 150), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 30, Parent = root })
	UI.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = holder })
	feed = holder
	countdown = UI.label({ Name = "CrateCountdown", Text = "", TextColor3 = C.Gold, MaxText = 30, Visible = false, Size = UDim2.fromOffset(460, 36), Position = UDim2.new(0.5, 0, 0, 112), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 30, Parent = root })

	task.spawn(buildGuns)

	local crates = workspace:WaitForChild("LiveCrates")
	for _, c in crates:GetChildren() do
		tag(c :: BasePart)
	end
	crates.ChildAdded:Connect(function(c)
		task.defer(tag, c :: BasePart)
	end)

	Remotes.event("Crates").OnClientEvent:Connect(function(kind: string, a: any, b: any, c: any, d: any, e: any, f: any, g: any)
		if kind == "shot" then
			-- someone else's shot (our own is drawn the moment we fire, CannonView)
			if a ~= player.UserId then
				local gun = guns[tostring(d) .. ":" .. tostring(e)]
				if gun then
					gun.yaw, gun.pitch, gun.kick = f, g, 1
				end
				local cam = workspace.CurrentCamera.CFrame.Position
				if ((b :: Vector3) - cam).Magnitude < DRAW_DIST then
					CrateView.flyBall(b, c)
					if ((b :: Vector3) - cam).Magnitude < 200 then
						Sound.play("Cannon", 0.4, 0.9 + math.random() * 0.2)
					end
				end
			end
		elseif kind == "hit" then
			for cp, _ in tagged do
				if cp:GetAttribute("Id") == a then
					local old = cp.Color
					cp.Color = Color3.new(1, 1, 1)
					task.delay(0.12, function()
						cp.Color = old
					end)
				end
			end
		elseif kind == "break" then
			for cp, _ in tagged do
				if cp:GetAttribute("Id") == a then
					breakOpen(cp, c)
					cp.Transparency = 1
					local gui = cp:FindFirstChildOfClass("BillboardGui")
					if gui then
						gui.Enabled = false
					end
				end
			end
			post(tostring(b) .. " smashed a " .. (KIND_NAME[c] or "crate") .. "!", if c == "Gold" then C.Gold else C.White)
		elseif kind == "drop" then
			if (a :: number) > 0 then
				post(tostring(a) .. " crates dropped in the sea! Get in a cannon!", C.Gold)
				Sound.play("ZoneChime", 0.6)
			end
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local t = os.clock()
		-- crates bob and rock (client-side only; the server's position is the rest pose)
		for cp, info in tagged do
			if cp.Transparency < 1 then
				cp.CFrame = info.rest * CFrame.new(0, math.sin(t * 1.8 + info.phase) * 0.7, 0) * CFrame.Angles(math.sin(t + info.phase) * 0.12, 0, math.cos(t * 1.3 + info.phase) * 0.12)
			end
		end
		-- other gunners' recoil settles back
		for _, g in guns do
			if g.kick > 0 then
				g.kick = math.max(0, g.kick - dt * 3)
				poseGun(g)
			end
		end
		-- drop countdown in the last LIVE_CRATES.warn seconds
		local at = workspace:GetAttribute("CrateDropAt") :: number?
		local cd = countdown
		if cd then
			local left = if at then at - workspace:GetServerTimeNow() else math.huge
			cd.Visible = left > 0 and left <= L.warn
			if cd.Visible then
				cd.Text = "Crate drop in " .. Format.time(math.ceil(left)) .. "!"
			end
		end
	end)
end

return CrateView
