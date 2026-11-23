--!strict
-- Cinematics, all client-side with letterbox bars and a scripted camera:
--   Cinema.intro()      first join: babies on deck, they fuse, flyover of the harbour,
--                       Maw rises and drags your monster under, "Reach DEPTH <FINAL_DEPTH>" card
--   Cinema.bossIntro()  a short "BOSS: name" shot when a boss surfaces in your fight
-- The camera is re-applied every frame above the default camera's priority.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MonsterModels = require(Shared.MonsterModels)
local Remotes = require(Shared.Remotes)

local UI = require(script.Parent.UI)
local State = require(script.Parent.State)
local Sound = require(script.Parent.Sound)

local Cinema = {}

local player = Players.LocalPlayer
local C = UI.Colors
local BIND = "TideCinema"

local layer: Frame
local topBar: Frame
local bottomBar: Frame
local caption: TextLabel
local speaker: TextLabel
local black: Frame
local blackText: TextLabel
local skipBtn: TextButton

local camCf: CFrame? = nil
local camFov = 60
local skipping = false
local playing = false

local function setCamera(cf: CFrame, fov: number?)
	camCf = cf
	camFov = fov or camFov
end

local function startCamera()
	RunService:BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value + 1, function()
		local cam = workspace.CurrentCamera
		if camCf then
			cam.CameraType = Enum.CameraType.Scriptable
			cam.CFrame = camCf
			cam.FieldOfView = camFov
		end
	end)
end

local function stopCamera()
	pcall(function()
		RunService:UnbindFromRenderStep(BIND)
	end)
	camCf = nil
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	cam.FieldOfView = 70
	-- put the follow camera back behind the player at a normal distance
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if root and hum then
		cam.CameraSubject = hum
		cam.CFrame = CFrame.lookAt((root.CFrame * CFrame.new(0, 9, 18)).Position, root.Position)
	end
end

local function bars(on: boolean)
	local h = if on then 0.12 else 0
	layer.Visible = true
	-- the bars are oversized and slide in from beyond the screen edges, so they also
	-- cover the top bar inset at any UI scale
	local topPos = if on then UDim2.fromScale(0.5, h) else UDim2.new(0.5, 0, 0, -160)
	local botPos = if on then UDim2.fromScale(0.5, 1 - h) else UDim2.new(0.5, 0, 1, 160)
	TweenService:Create(topBar, TweenInfo.new(0.4), { Position = topPos }):Play()
	TweenService:Create(bottomBar, TweenInfo.new(0.4), { Position = botPos }):Play()
end

local function say(text: string?, who: string?, color: Color3?)
	if not text then
		caption.Visible = false
		speaker.Visible = false
		return
	end
	caption.Visible = true
	caption.Text = UI.keyword(text)
	caption.TextColor3 = color or C.White
	UI.pop(caption, 0.8)
	speaker.Visible = who ~= nil
	speaker.Text = who or ""
end

-- wait that ends early when skipped
local function hold(seconds: number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds and not skipping do
		task.wait()
	end
end

-- move the camera from a to b over time (eased), while the scene keeps animating
local function glide(a: CFrame, b: CFrame, time: number, fov: number?)
	local t0 = os.clock()
	while not skipping do
		local k = math.clamp((os.clock() - t0) / time, 0, 1)
		local e = k * k * (3 - 2 * k)
		setCamera(a:Lerp(b, e), fov)
		if k >= 1 then
			break
		end
		task.wait()
	end
end

-- a posed rig that keeps animating until stopped
local function actor(id: string, scale: number, cf: CFrame, swim: boolean?): (MonsterModels.Rig?, () -> (), (CFrame) -> ())
	local rig = MonsterModels.build(id, scale)
	if not rig then
		return nil, function() end, function() end
	end
	local r = rig :: MonsterModels.Rig
	r.model.Parent = workspace
	local where = cf * CFrame.new(0, MonsterModels.footDepth(r), 0)
	local conn = RunService.RenderStepped:Connect(function()
		MonsterModels.pose(r, where, os.clock(), swim, true)
	end)
	return r, function()
		conn:Disconnect()
		r.model:Destroy()
	end, function(newCf: CFrame)
		where = newCf * CFrame.new(0, MonsterModels.footDepth(r), 0)
	end
end

local function myShip(): Model?
	local idx = player:GetAttribute("Ship")
	local world = workspace:FindFirstChild("World")
	return if idx and world then world:FindFirstChild("Ship" .. idx) :: Model? else nil
end

local function hearts(pos: Vector3, color: Color3)
	for _ = 1, 16 do
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.Material = Enum.Material.Neon
		p.Color = color
		p.Size = Vector3.new(0.5, 0.5, 0.5)
		p.CFrame = CFrame.new(pos)
		p.Parent = workspace
		local dir = Vector3.new(math.random() - 0.5, math.random() * 0.9 + 0.3, math.random() - 0.5).Unit
		TweenService:Create(p, TweenInfo.new(0.8), { CFrame = CFrame.new(pos + dir * 6), Size = Vector3.new(0.05, 0.05, 0.05) }):Play()
		task.delay(0.85, function()
			p:Destroy()
		end)
	end
end

---------------------------------------------------------------------------
-- Intro
---------------------------------------------------------------------------
function Cinema.intro()
	if playing then
		return
	end
	local ship = myShip()
	if not ship then
		return
	end
	playing = true
	skipping = false
	State.cinematic = true
	local Hud = require(script.Parent.Hud) :: any
	Hud.refresh()
	skipBtn.Visible = true
	bars(true)
	startCamera()
	Sound.music("Music")

	-- the scene plays on the harbour beach facing your ship, the lighthouse behind
	local shipCf = ship:GetAttribute("ShipCf") :: CFrame
	local hub = Vector3.new(0, Config.SEA_LEVEL, 0)
	local dir = ((shipCf.Position - hub) * Vector3.new(1, 0, 1)).Unit
	local grassY = Config.SEA_LEVEL + 5
	local stagePos = hub + dir * 30 + Vector3.new(0, grassY, 0)
	local camPos = stagePos + dir * 15 + Vector3.new(0, 4, 0)
	-- deck = the spot the babies stand on, facing the camera
	local deck = CFrame.lookAt(stagePos, Vector3.new(camPos.X, stagePos.Y, camPos.Z))
	local cleanup: { () -> () } = {}

	-- 1. babies on the beach
	local _, stopA = actor("Splashfin", 1.4, deck * CFrame.new(-2.6, 0, 0) * CFrame.Angles(0, math.rad(-20), 0))
	local _, stopB = actor("Zapjelly", 1.4, deck * CFrame.new(2.6, 0, 0) * CFrame.Angles(0, math.rad(20), 0))
	table.insert(cleanup, stopA)
	table.insert(cleanup, stopB)
	local camA = CFrame.lookAt((deck * CFrame.new(-7, 4, -13)).Position, (deck * CFrame.new(0, 2, 0)).Position)
	local camB = CFrame.lookAt((deck * CFrame.new(6, 3, -12)).Position, (deck * CFrame.new(0, 2, 0)).Position)
	setCamera(camA, 50)
	say("Raise your <SEA MONSTERS>!")
	glide(camA, camB, 3.2, 50)

	-- 2. they fuse
	if not skipping then
		say("<FUSE> them into something stronger!")
		hold(1.2)
		hearts((deck * CFrame.new(0, 2.5, 0)).Position, Color3.fromRGB(255, 120, 180))
		Sound.play("Fuse", 0.8)
		stopA()
		stopB()
		local _, stopC = actor("Thunderwhale", 1.6, deck * CFrame.Angles(0, math.rad(180), 0))
		table.insert(cleanup, stopC)
		hearts((deck * CFrame.new(0, 2.5, 0)).Position, Color3.fromRGB(255, 230, 80))
		hold(1.6)
	end

	-- 3. flyover of the harbour
	if not skipping then
		say("Battle in the <OPEN SEA>!")
		local a = CFrame.lookAt(Vector3.new(-150, 60, -150), Vector3.new(0, 10, 0))
		local b = CFrame.lookAt(Vector3.new(140, 45, -120), Vector3.new(0, 10, 0))
		glide(a, b, 3.6, 60)
	end

	-- 4. Maw rises and steals the whale
	if not skipping then
		say(nil)
		-- open water between the beach and your ship; Maw faces the beach
		-- (beside the dock, in open water: the dock and the bow of the ship are straight ahead)
		local side = dir:Cross(Vector3.yAxis)
		-- 28 studs short of the bow, 30 to one side of the dock. The island is a square, so pick the
		-- side that is open water for this ship (the other one can still be on the sand)
		local bowR = Config.SHIP_RING_RADIUS - Config.SHIP_LENGTH / 2
		local function inWater(p: Vector3): boolean
			return math.max(math.abs(p.X), math.abs(p.Z)) > Config.HUB_RADIUS + 14
		end
		local lateral = side * 30
		if not inWater(hub + dir * (bowR - 28) + lateral) then
			lateral = -lateral
		end
		local seaPos = hub + dir * (bowR - 28) + lateral
		local seaSpot = CFrame.lookAt(seaPos, Vector3.new(stagePos.X, seaPos.Y, stagePos.Z)) * CFrame.Angles(0, math.rad(90), 0)
		-- high and to the dock side so the palms don't block the view of Maw
		local camC = CFrame.lookAt(stagePos + dir * 16 + side * -10 + Vector3.new(0, 10, 0), seaPos + Vector3.new(0, 10, 0))
		-- palms (and other small things standing on the island) between the camera and Maw hide for this
		-- shot only, so nothing blocks him: we cast rays from the camera to Maw's whole rise and make every
		-- blocker see-through (just for this player), then put them back when the scene ends
		do
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.IgnoreWater = true
			local ignore: { Instance } = {}
			for _, m in (workspace:FindFirstChild("World") :: Instance):GetChildren() do
				if m:GetAttribute("ShipIndex") then
					table.insert(ignore, m) -- ships never hide
				end
			end
			params.FilterDescendantsInstances = ignore
			local hidden: { BasePart } = {}
			local from = camC.Position
			local targets = {}
			for _, up in { 2, 8, 14, 20, 28 } do
				for _, off in { -10, 0, 10 } do
					table.insert(targets, seaPos + Vector3.new(0, up, 0) + side * off)
				end
			end
			for _, to in targets do
				for _ = 1, 25 do
					local hit = workspace:Raycast(from, to - from, params)
					if not hit then
						break
					end
					local part = hit.Instance :: BasePart
					if not part:IsA("Terrain") and part.Size.Magnitude < 14 and part.Position.Y > grassY + 0.8 then
						part.LocalTransparencyModifier = 1
						table.insert(hidden, part)
					end
					table.insert(ignore, part) -- (hidden or not, look past it)
					params.FilterDescendantsInstances = ignore
				end
			end
			table.insert(cleanup, function()
				for _, p in hidden do
					if p.Parent then
						p.LocalTransparencyModifier = 0
					end
				end
			end)
		end
		setCamera(camC, 60)
		local rig, stopM, moveM = actor("Maw", 2.6, seaSpot * CFrame.new(0, -24, 0) * CFrame.Angles(0, math.rad(-90), 0), true)
		table.insert(cleanup, stopM)
		Sound.play("BossIntro", 0.9)
		local t0 = os.clock()
		while os.clock() - t0 < 2.2 and not skipping do
			local k = math.clamp((os.clock() - t0) / 2, 0, 1)
			moveM(seaSpot * CFrame.new(0, -24 + 27 * (1 - (1 - k) ^ 3) + math.sin(os.clock() * 8) * 0.3 * (1 - k), 0) * CFrame.Angles(0, math.rad(-90), 0))
			task.wait()
		end
		say("Want your friend back? Find me at <DEPTH " .. Config.FINAL_DEPTH .. ">!", "Maw, the Abyss King", Color3.fromRGB(255, 120, 120))
		hold(2.6)
		-- dives, taking the whale
		if not skipping then
			for _, f in cleanup do
				-- stop the whale (index 3), Maw keeps going
				local _ = f
			end
			local whaleStop = cleanup[3]
			if whaleStop then
				whaleStop()
				cleanup[3] = function() end
			end
			local _, stopW, moveW = actor("Thunderwhale", 1.6, deck)
			table.insert(cleanup, stopW)
			local t1 = os.clock()
			while os.clock() - t1 < 1.4 and not skipping do
				local k = math.clamp((os.clock() - t1) / 1.3, 0, 1)
				local p = deck.Position:Lerp(seaSpot.Position + Vector3.new(0, -4, 0), k) + Vector3.new(0, math.sin(k * math.pi) * 10, 0)
				moveW(CFrame.new(p) * CFrame.Angles(k * 4, 0, k * 3))
				moveM(seaSpot * CFrame.new(0, -2 - k * 22, 0) * CFrame.Angles(0, math.rad(-90), 0))
				task.wait()
			end
		end
		local _ = rig
	end

	-- 5. black card
	say(nil)
	bars(false)
	black.Visible = true
	black.BackgroundTransparency = 1
	blackText.Text = UI.keyword("Reach <DEPTH " .. Config.FINAL_DEPTH .. "> to rescue your monster...")
	TweenService:Create(black, TweenInfo.new(0.5), { BackgroundTransparency = 0 }):Play()
	task.wait(0.5)
	for _, f in cleanup do
		f()
	end
	stopCamera()
	if not skipping then
		hold(2.4)
	end
	TweenService:Create(black, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(blackText, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
	task.wait(0.6)
	black.Visible = false
	blackText.TextTransparency = 0
	skipBtn.Visible = false
	layer.Visible = false
	State.cinematic = false
	playing = false
	Remotes.event("IntroSeen"):FireServer()
	Hud.refresh()
end

---------------------------------------------------------------------------
-- Boss intro
---------------------------------------------------------------------------
function Cinema.bossIntro(model: Model, name: string)
	if playing then
		return
	end
	playing = true
	skipping = false
	bars(true)
	startCamera()
	Sound.play("BossIntro", 0.8)
	local t0 = os.clock()
	say("BOSS: " .. name, nil, Color3.fromRGB(255, 90, 90))
	-- frame the whole boss: the camera distance comes from its size (bosses are several times
	-- bigger than normal enemies), with a little margin, and drifts slightly closer
	local FOV = 55
	local fit = 1 / math.tan(math.rad(FOV / 2))
	while os.clock() - t0 < 2.4 do
		local pivot = model.Parent and model:GetPivot()
		if pivot then
			local _, size = model:GetBoundingBox()
			local radius = math.max(size.Magnitude / 2, 4)
			local dist = radius * fit * 1.15
			local k = (os.clock() - t0) / 2.4
			-- aim at the middle of the body; it is still rising out of the water at first
			local focus = pivot.Position + Vector3.new(0, size.Y * 0.25, 0)
			local from = pivot * CFrame.new(math.sin(k * 1.2) * radius * 0.3, radius * 0.35, -dist * (1 - k * 0.12))
			setCamera(CFrame.lookAt(from.Position, focus), FOV)
		end
		task.wait()
	end
	say(nil)
	bars(false)
	stopCamera()
	task.delay(0.4, function()
		if not playing then
			layer.Visible = false
		end
	end)
	playing = false
end

function Cinema.isPlaying(): boolean
	return playing
end

function Cinema.init(screen: ScreenGui)
	layer = UI.new("Frame", { Name = "Cinema", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 50, Visible = false, Parent = screen })
	topBar = UI.new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -160), Size = UDim2.fromScale(3, 2), ZIndex = 50, Parent = layer })
	bottomBar = UI.new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 160), Size = UDim2.fromScale(3, 2), ZIndex = 50, Parent = layer })
	speaker = UI.label({ Text = "", TextColor3 = C.Gold, Size = UDim2.new(0.6, 0, 0, 30), Position = UDim2.new(0.5, 0, 1, -112), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 52, Visible = false, Parent = layer })
	caption = UI.label({ Text = "", MaxText = 36, Size = UDim2.new(0.8, 0, 0, 52), Position = UDim2.new(0.5, 0, 1, -78), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 52, Visible = false, Parent = layer })
	black = UI.new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(3, 3), ZIndex = 60, Visible = false, Parent = layer })
	blackText = UI.label({ Text = "", MaxText = 44, Size = UDim2.new(0.24, 0, 0, 60), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 61, Stroke = 0, Parent = black })
	-- a bright gold pill on the black bar (a dark one disappeared into the letterbox)
	skipBtn = UI.button({ Text = "SKIP  >>", Color = C.Gold, Size = UDim2.fromOffset(150, 52), Position = UDim2.new(1, -20, 0, 16), AnchorPoint = Vector2.new(1, 0), ZIndex = 70, Visible = false, Parent = layer }, function()
		skipping = true
	end)
	-- keyboard and controller can skip too: Space / Enter, or A / B / Start on a pad
	game:GetService("UserInputService").InputBegan:Connect(function(input)
		if not skipBtn.Visible or skipping then
			return
		end
		local k = input.KeyCode
		if k == Enum.KeyCode.Space or k == Enum.KeyCode.Return or k == Enum.KeyCode.ButtonA or k == Enum.KeyCode.ButtonB or k == Enum.KeyCode.ButtonStart then
			skipping = true
		end
	end)
	skipBtn.ZIndex = 70
	for _, d in skipBtn:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 71
		end
	end
end

return Cinema
