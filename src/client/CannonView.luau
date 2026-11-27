--!strict
-- Riding a Cannon Gallery gun (server/CrateService): first person from behind the breech, the
-- player steers the cannon and fires real-arc cannonballs (shared/Ballistics) at the live crates.
--   PC      mouse turns the cannon (locked to the centre), left click fires
--   touch   drag to turn, the FIRE button fires
--   pad     right stick turns, RT / A fires
--   leave   the Leave button, Space, or B
-- While inside, every other screen GUI and proximity prompt is hidden: only the crosshair, reload
-- ring, the dotted aim guide and Leave show.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Format)
local Ballistics = require(Shared.Ballistics)

local UI = require(script.Parent.UI)
local State = require(script.Parent.State)
local Hud = require(script.Parent.Hud)
local Sound = require(script.Parent.Sound)
local CrateView = require(script.Parent.CrateView)
local Platform = require(script.Parent.Platform)
local PadStickers = require(script.Parent.PadStickers)

local CannonView = {}

local player = Players.LocalPlayer
local C = UI.Colors
local L = Config.LIVE_CRATES
local MOUSE_SENS = 0.0022 -- radians per pixel (slow and steady: easy aiming)
local TOUCH_SENS = 0.004
local PAD_SPEED = 1.1 -- radians per second at full stick
local GUIDE_DOTS = 30 -- the guide draws the whole arc, with a ring on the water where it lands

-- when the ball reaches the sea
local function landTime(p0: Vector3, v0: Vector3): number
	local g = L.gravity
	local h = p0.Y - Config.SEA_LEVEL
	return (v0.Y + math.sqrt(math.max(0, v0.Y * v0.Y + 2 * g * h))) / g
end

-- the live crate this arc would hit (nil = none)
local function aimedCrate(p0: Vector3, v0: Vector3): number?
	local crates = workspace:FindFirstChild("LiveCrates")
	if not crates then
		return nil
	end
	local best, id = math.huge, nil
	for _, c in crates:GetChildren() do
		local cp = c :: BasePart
		if ((cp:GetAttribute("Hp") :: number?) or 0) > 0 and (cp.Position - p0).Magnitude < 400 then
			local d = Ballistics.closest(p0, v0, cp.Position)
			if d < math.max(cp.Size.X, cp.Size.Y, cp.Size.Z) / 2 + L.hitPad and d < best then
				best, id = d, cp:GetAttribute("Id") :: number
			end
		end
	end
	return id
end

local active = false

function CannonView.isActive(): boolean
	return active
end

-- everything that has to be hidden while inside; returns a function that puts it all back
local function hideWorld(sign: BillboardGui?, char: Model?): () -> ()
	local hiddenGuis: { ScreenGui } = {}
	for _, g in player.PlayerGui:GetChildren() do
		if g:IsA("ScreenGui") and g.Enabled and g.Name ~= "CannonUI" then
			table.insert(hiddenGuis, g)
			g.Enabled = false
		end
	end
	local oldMax = ProximityPromptService.MaxPromptsVisible
	ProximityPromptService.MaxPromptsVisible = 0
	if sign then
		sign.Enabled = false
	end
	local faded: { BasePart } = {}
	local tags: { BillboardGui } = {} -- name tags over our head (VIP CAPTAIN, ...)
	local hum0 = if char then char:FindFirstChildOfClass("Humanoid") else nil
	local oldDisplay = if hum0 then hum0.DisplayDistanceType else nil
	if hum0 then
		hum0.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	if char then
		for _, d in char:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(faded, d)
			elseif d:IsA("BillboardGui") and d.Enabled then
				table.insert(tags, d)
				d.Enabled = false
			end
		end
	end
	-- LocalTransparencyModifier is reset by the default camera scripts each frame, so keep it at 1
	local keep = RunService.RenderStepped:Connect(function()
		for _, p in faded do
			p.LocalTransparencyModifier = 1
		end
	end)
	return function()
		keep:Disconnect()
		for _, g in tags do
			if g.Parent then
				g.Enabled = true
			end
		end
		if hum0 and hum0.Parent and oldDisplay then
			hum0.DisplayDistanceType = oldDisplay
		end
		for _, p in faded do
			if p.Parent then
				p.LocalTransparencyModifier = 0
			end
		end
		for _, g in hiddenGuis do
			if g.Parent then
				g.Enabled = true
			end
		end
		ProximityPromptService.MaxPromptsVisible = oldMax
		if sign then
			sign.Enabled = true
		end
	end
end

-- the cannon's own screen: crosshair, reload ring, Leave, FIRE (touch)
local function buildUi(): (ScreenGui, UIStroke, TextButton, TextButton?, TextLabel)
	local gui = UI.new("ScreenGui", { Name = "CannonUI", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 50, Parent = player.PlayerGui })
	local cross = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(64, 64), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = gui })
	for _, r in { { 0, -18, 3, 14 }, { 0, 18, 3, 14 }, { -18, 0, 14, 3 }, { 18, 0, 14, 3 } } do
		UI.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Size = UDim2.fromOffset(r[3], r[4]), Position = UDim2.new(0.5, r[1], 0.5, r[2]), AnchorPoint = Vector2.new(0.5, 0.5), Parent = cross }, { UI.stroke(1.5) })
	end
	local ring = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(52, 52), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = cross }, { UI.corner(26) })
	local ringStroke = UI.new("UIStroke", { Thickness = 3, Color = C.Gold, Parent = ring })
	local ammoLbl = UI.label({ Name = "Ammo", Text = "", TextColor3 = C.Gold, MaxText = 30, Size = UDim2.fromOffset(420, 40), Position = UDim2.new(0.5, 0, 1, -30), AnchorPoint = Vector2.new(0.5, 1), Parent = gui })
	local leaveBtn = UI.button({ Text = "Leave", Color = C.Coral, Size = UDim2.fromOffset(150, 52), Position = UDim2.new(1, -24, 1, -24), AnchorPoint = Vector2.new(1, 1), Parent = gui })
	-- phones and controllers get a big SHOOT button (a controller's shows its RT sticker; Leave shows B)
	local mode = Platform.mode()
	local fireBtn: TextButton? = nil
	if mode == "touch" or mode == "pad" then
		fireBtn = UI.button({ Text = "SHOOT", Color = C.Gold, Size = UDim2.fromOffset(140, 140), Position = UDim2.new(1, -40, 1, -96), AnchorPoint = Vector2.new(1, 1), Parent = gui })
		UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = fireBtn })
	end
	if mode == "pad" and fireBtn then
		PadStickers.attach(fireBtn, Enum.KeyCode.ButtonR2, { always = true, size = 44 })
		PadStickers.attach(leaveBtn, Enum.KeyCode.ButtonB, { always = true, size = 34 })
	end
	return gui, ringStroke, leaveBtn, fireBtn, ammoLbl
end

function CannonView.enter(side: string)
	if active then
		return
	end
	local idx = player:GetAttribute("Ship") :: number?
	local world = workspace:FindFirstChild("World")
	local ship = if idx and world then world:FindFirstChild("Ship" .. tostring(idx)) else nil
	local shipCf = if ship then ship:GetAttribute("ShipCf") :: CFrame? else nil
	if not idx or not ship or not shipCf then
		Hud.toast("Use the cannons on your own ship!", C.Coral)
		return
	end
	active = true -- (claimed before the server call so a double press can't enter twice)
	local ok, msg = State.action("CannonEnter", side)
	if not ok then
		active = false
		Hud.toast(msg or "Not now", C.Coral)
		return
	end
	local base = Ballistics.base(shipCf, side)
	local yaw, pitch = 0, math.rad(20)
	local lastShot = -math.huge
	local kick = 0
	local conns: { RBXScriptConnection } = {}
	local cam = workspace.CurrentCamera

	local plat = ship:FindFirstChild("CannonGame" .. side, true)
	local sign = if plat then plat:FindFirstChild("CannonSign") :: BillboardGui? else nil
	local char = player.Character
	local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
	local restore = hideWorld(sign, char)
	local oldSpeed, oldJump = 16, 50
	if hum then
		oldSpeed, oldJump = hum.WalkSpeed, hum.JumpPower
		hum.WalkSpeed, hum.JumpPower = 0, 0
	end
	local oldFov = cam.FieldOfView
	cam.CameraType = Enum.CameraType.Scriptable
	local gui, ringStroke, leaveBtn, fireBtn, ammoLbl = buildUi()
	CrateView.showTargetTags(true)
	local function outText(): string
		local at = (player:GetAttribute("CannonRefillAt") :: number?) or 0
		return "Out of cannonballs! More in " .. Format.time(at - workspace:GetServerTimeNow())
	end
	local touch = Platform.mode() == "touch"

	-- reward pops while inside (the normal toasts are hidden with the HUD)
	table.insert(conns, Remotes.event("Toast").OnClientEvent:Connect(function(text: string, color: Color3?)
		local l = UI.label({ Text = text, TextColor3 = color or C.Gold, MaxText = 34, Size = UDim2.fromOffset(640, 44), Position = UDim2.new(0.5, 0, 0.3, 0), AnchorPoint = Vector2.new(0.5, 0.5), Parent = gui })
		UI.pop(l)
		task.delay(2.4, function()
			if l.Parent then
				UI.tween(l, 0.4, { TextTransparency = 1 })
				task.wait(0.45)
				l:Destroy()
			end
		end)
	end))

	-- the short dotted aim guide
	local dots: { BasePart } = {}
	for i = 1, GUIDE_DOTS do
		local d = Instance.new("Part")
		d.Shape = Enum.PartType.Ball
		d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch, d.CastShadow = true, false, false, false, false
		d.Material = Enum.Material.Neon
		d.Color = C.Gold
		d.Size = Vector3.one * 0.7
		d.Transparency = 0.1 + i / GUIDE_DOTS * 0.4
		d.Parent = cam
		dots[i] = d
	end
	-- the landing ring on the water
	local marker = Instance.new("Part")
	marker.Shape = Enum.PartType.Cylinder
	marker.Anchored, marker.CanCollide, marker.CanQuery, marker.CanTouch, marker.CastShadow = true, false, false, false, false
	marker.Material = Enum.Material.Neon
	marker.Size = Vector3.new(0.3, 10, 10)
	marker.Transparency = 0.35
	marker.Parent = cam
	table.insert(dots, marker)

	local function stop()
		if not active then
			return
		end
		active = false
		CrateView.showTargetTags(false)
		for _, c in conns do
			c:Disconnect()
		end
		gui:Destroy()
		for _, d in dots do
			d:Destroy()
		end
		restore()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		cam.CameraType = Enum.CameraType.Custom
		cam.FieldOfView = oldFov
		if hum and hum.Parent then
			hum.WalkSpeed, hum.JumpPower = oldSpeed, oldJump
			cam.CameraSubject = hum
		end
		task.spawn(State.action, "CannonLeave")
	end

	local function fire()
		if not active or os.clock() - lastShot < L.reload then
			return
		end
		if ((player:GetAttribute("CannonAmmo") :: number?) or L.ammo) <= 0 then
			ammoLbl.Text = outText()
			Sound.play("Click", 0.5, 0.7)
			return
		end
		lastShot = os.clock()
		kick = 1
		local p0, v0 = Ballistics.launch(base, yaw, pitch)
		Sound.play("Cannon", 0.7, 0.95 + math.random() * 0.1)
		local sentYaw, sentPitch = yaw, pitch
		-- draw it now; when it meets a crate, tell the server which (it re-checks the same arc)
		CrateView.flyBall(p0, v0, nil)
		local target = aimedCrate(p0, v0)
		task.spawn(State.action, "CannonFire", { yaw = sentYaw, pitch = sentPitch, crate = target })
	end

	leaveBtn.Activated:Connect(stop)
	if fireBtn then
		fireBtn.Activated:Connect(fire)
	end

	-- input: mouse look / drag / stick, click / RT / A to fire, Space / B to leave
	-- (the stick is read every frame in RenderStepped, not from events: a missed "released" event
	-- left the last tilt applied and the cannon kept turning on its own)
	pcall(function()
		game:GetService("GamepadService"):DisableGamepadCursor()
	end)
	table.insert(conns, UserInputService.InputChanged:Connect(function(input, processed)
		-- with a controller in use, ignore mouse movement (the virtual cursor sends stray deltas)
		if input.UserInputType == Enum.UserInputType.MouseMovement and Platform.mode() ~= "pad" then
			yaw -= input.Delta.X * MOUSE_SENS
			pitch -= input.Delta.Y * MOUSE_SENS
		elseif input.UserInputType == Enum.UserInputType.Touch and not processed then
			yaw -= input.Delta.X * TOUCH_SENS
			pitch -= input.Delta.Y * TOUCH_SENS
		end
		yaw, pitch = Ballistics.clamp(yaw, pitch)
	end))
	table.insert(conns, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local k = input.KeyCode
		if input.UserInputType == Enum.UserInputType.MouseButton1 or k == Enum.KeyCode.ButtonR2 or k == Enum.KeyCode.ButtonA then
			fire()
		elseif k == Enum.KeyCode.Space or k == Enum.KeyCode.ButtonB then
			stop()
		end
	end))
	if hum then
		table.insert(conns, hum.Died:Connect(stop))
	end
	table.insert(conns, player:GetAttributeChangedSignal("InCannon"):Connect(function()
		if player:GetAttribute("InCannon") == nil then
			stop() -- the server let us out (respawn, battle, ...)
		end
	end))

	table.insert(conns, RunService.RenderStepped:Connect(function(dt)
		-- right stick, polled: a 0.25 dead zone (worn sticks rest off-centre), eased so small
		-- tilts turn slowly for fine aim
		local sx, sy = 0, 0
		for _, st in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
			if st.KeyCode == Enum.KeyCode.Thumbstick2 then
				sx, sy = st.Position.X, st.Position.Y
			end
		end
		local function ease(v: number): number
			local a = math.abs(v)
			if a < 0.25 then
				return 0
			end
			local u = (a - 0.25) / 0.75
			return math.sign(v) * u * u
		end
		sx, sy = ease(sx), ease(sy)
		if sx ~= 0 or sy ~= 0 then
			yaw -= sx * PAD_SPEED * dt
			pitch += sy * PAD_SPEED * dt
			yaw, pitch = Ballistics.clamp(yaw, pitch)
		end
		if not touch then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			UserInputService.MouseIconEnabled = false
		end
		kick = math.max(0, kick - dt * 3)
		-- the gun follows the aim (with a little recoil), the camera sits behind its breech
		local g = CrateView.gun(idx, side)
		if g then
			g.kick = kick * 0.8
			CrateView.setAim(idx, side, yaw, pitch)
		end
		local barrel = Ballistics.barrel(base, yaw, pitch)
		local S = Ballistics.SCALE
		-- high and well behind the gun (turning with it, not tilting), looking over the barrel out to
		-- sea: the whole cannon shows in the lower part of the screen, the crosshair sits on the water
		local turn = base * CFrame.Angles(0, yaw, 0)
		local eye = turn * CFrame.new(0, 5.2 * S, 8.5 * S + kick * 0.6)
		local look = (barrel * CFrame.new(0, 0, -90)).Position
		cam.CFrame = CFrame.lookAt(eye.Position, look)
		cam.FieldOfView = 70
		-- aim guide: the whole arc, and a ring where it lands (green when it would hit a crate)
		local p0, v0 = Ballistics.launch(base, yaw, pitch)
		local land = landTime(p0, v0)
		local onCrate = aimedCrate(p0, v0) ~= nil
		local col = if onCrate then Color3.fromRGB(90, 255, 120) else C.Gold
		for i, d in dots do
			d.Position = Ballistics.at(p0, v0, i / GUIDE_DOTS * land)
			d.Color = col
		end
		local lp = Ballistics.at(p0, v0, land)
		marker.CFrame = CFrame.new(lp.X, Config.SEA_LEVEL + 0.4, lp.Z) * CFrame.Angles(0, 0, math.rad(90))
		marker.Color = col
		local am = (player:GetAttribute("CannonAmmo") :: number?) or L.ammo
		ammoLbl.Text = if am > 0 then "Cannonballs: " .. am .. "/" .. L.ammo else outText()
		-- reload ring: grey while loading, gold when ready
		local r = math.clamp((os.clock() - lastShot) / L.reload, 0, 1)
		ringStroke.Color = if r >= 1 then C.Gold else Color3.fromRGB(120, 120, 130)
		ringStroke.Transparency = if r >= 1 then 0 else 0.6 - r * 0.4
	end))
end

return CannonView
