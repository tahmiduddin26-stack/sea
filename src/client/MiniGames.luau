--!strict
-- Crab Cove scenery is shared. Everything in CrabCovePrivate is created only on this client.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Cove = require(Shared.CrabCove)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local MonsterModels = require(Shared.MonsterModels)
local UI = require(script.Parent.UI)
local State = require(script.Parent.State)
local Hud = require(script.Parent.Hud)
local Menus = require(script.Parent.Menus)
local Sound = require(script.Parent.Sound)
local player = Players.LocalPlayer
local MiniGames = {}
local round: any = nil
local starting = false
local C = UI.Colors
local directions = { "↑", "↗", "→", "↘", "↓", "↙", "←", "↖" }

-- a short word that floats up over something and fades ("SNAP!", "OUCH!")
local function popAbove(adornee: BasePart?, text: string, color: Color3)
	if not adornee then
		return
	end
	local g = UI.new("BillboardGui", {
		Size = UDim2.fromOffset(170, 52),
		StudsOffset = Vector3.new(0, 4, 0),
		AlwaysOnTop = true,
		Adornee = adornee,
		Parent = player.PlayerGui,
	})
	local l = UI.label({ Text = text, TextColor3 = color, MaxText = 38, Size = UDim2.fromScale(1, 1), Parent = g })
	UI.tween(g, 0.6, { StudsOffset = Vector3.new(0, 7.5, 0) })
	UI.tween(l, 0.6, { TextTransparency = 1 })
	task.delay(0.65, function()
		g:Destroy()
	end)
end

local function cleanup()
	local run = round
	if not run then
		return
	end
	round = nil
	pcall(function()
		RunService:UnbindFromRenderStep("CoveShake")
	end)
	run.connection:Disconnect()
	run.folder:Destroy()
	run.screen:Destroy()
	run.beacon:Destroy()
	run.eggGuide:Destroy()
	local main = player.PlayerGui:FindFirstChild("TideUI")
	if main then
		(main :: ScreenGui).Enabled = run.mainEnabled
	end
end

local function startRound()
	if starting or round then
		return
	end
	starting = true
	local ok, msg = State.action("MiniStart", "cove")
	starting = false
	if not ok then
		Hud.toast(msg or "Cannot start", C.Coral)
		return
	end
	local started = tonumber(msg) or workspace:GetServerTimeNow()
	Menus.close()
	local screen = UI.new("ScreenGui", {
		Name = "CrabCoveUI",
		ResetOnSpawn = false,
		DisplayOrder = 30,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		Parent = player.PlayerGui,
	})
	local scale = UI.new("UIScale", { Parent = screen })
	local panel = UI.panel({
		Size = UDim2.fromOffset(660, 104),
		Position = UDim2.new(0.5, 0, 0, 10),
		AnchorPoint = Vector2.new(0.5, 0),
		Color = C.Deep,
		Parent = screen,
	})
	local status = UI.label({
		Text = "CRAB COVE",
		MaxText = 27,
		Size = UDim2.new(1, -125, 0, 38),
		Position = UDim2.fromOffset(12, 4),
		Parent = panel,
	})
	local boost = UI.label({
		Text = "Find glowing eggs around the island",
		MaxText = 19,
		Size = UDim2.new(1, -20, 0, 28),
		Position = UDim2.fromOffset(10, 40),
		Parent = panel,
	})
	local hint = UI.label({
		Text = "Walk into a glowing egg to pick it up!",
		MaxText = 17,
		Size = UDim2.new(1, -20, 0, 25),
		Position = UDim2.fromOffset(10, 72),
		Parent = panel,
	})
	UI.button({
		Text = "Leave",
		Color = C.Coral,
		Size = UDim2.fromOffset(98, 42),
		Position = UDim2.new(1, -110, 0, 6),
		Parent = panel,
	}, function()
		State.action("MiniFinish")
	end)
	local hearts = UI.label({
		Text = "♥ ♥ ♥",
		MaxText = 30,
		TextColor3 = C.Coral,
		Size = UDim2.fromOffset(170, 40),
		Position = UDim2.new(0.5, 0, 0, 115),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = screen,
	})
	local flash = UI.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Coral,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 0,
		Parent = screen,
	})
	local folder = Instance.new("Folder")
	folder.Name = "CrabCovePrivate"
	folder.Parent = workspace
	local prompt = workspace.World:FindFirstChild("CardsPrompt", true)
	local host = prompt and prompt.Parent :: BasePart?
	local keeper = if host then Cove.keeperCFrame(host).Position else nil
	-- a big sign over the Cove Keeper's stand that you can see from anywhere on the island
	local beacon = UI.new("BillboardGui", {
		Size = UDim2.fromOffset(420, 120),
		StudsOffset = Vector3.new(0, 16, 0),
		AlwaysOnTop = true,
		Adornee = host,
		Parent = player.PlayerGui,
		Enabled = false,
	})
	local beaconLabel = UI.label({
		Text = "BRING EGGS HERE!\n▼",
		TextColor3 = C.Gold,
		MaxText = 40,
		TextWrapped = true,
		Size = UDim2.fromScale(1, 1),
		Parent = beacon,
	})
	-- a tall glowing pillar of light where the eggs are delivered
	local pillar = Instance.new("Part")
	pillar.Name = "DeliveryPillar"
	pillar.Anchored = true
	pillar.CanCollide = false
	pillar.CanQuery = false
	pillar.CanTouch = false
	pillar.CastShadow = false
	pillar.Material = Enum.Material.Neon
	pillar.Color = C.Gold
	pillar.Shape = Enum.PartType.Cylinder
	pillar.Size = Vector3.new(90, 6, 6)
	pillar.Transparency = 1
	if keeper then
		pillar.CFrame = CFrame.new(keeper + Vector3.new(0, 45, 0)) * CFrame.Angles(0, 0, math.rad(90))
	end
	pillar.Parent = folder
	-- a glowing line from you to where you should go (the next egg, or the Keeper while you carry one)
	local fromPart = Instance.new("Part")
	fromPart.Anchored, fromPart.CanCollide, fromPart.CanQuery, fromPart.CanTouch = true, false, false, false
	fromPart.Transparency = 1
	fromPart.Size = Vector3.one * 0.2
	fromPart.Parent = folder
	local toPart = fromPart:Clone()
	toPart.Parent = folder
	local fromAtt = Instance.new("Attachment")
	fromAtt.Parent = fromPart
	local toAtt = Instance.new("Attachment")
	toAtt.Parent = toPart
	local guideBeam = Instance.new("Beam")
	guideBeam.Attachment0 = fromAtt
	guideBeam.Attachment1 = toAtt
	guideBeam.FaceCamera = true
	guideBeam.LightEmission = 1
	guideBeam.Width0 = 1.4
	guideBeam.Width1 = 1.4
	guideBeam.Transparency = NumberSequence.new(0.1)
	guideBeam.Segments = 1
	guideBeam.Enabled = false
	guideBeam.Parent = folder
	-- a huge instruction at the top of the screen, always saying the next thing to do
	local banner = UI.label({
		Text = "",
		TextColor3 = C.Gold,
		MaxText = 36,
		TextWrapped = true,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 176),
		Size = UDim2.fromOffset(820, 86),
		Parent = screen,
	})
	local bannerScale = UI.new("UIScale", { Parent = banner })
	local eggGuide = UI.new("BillboardGui", {
		Size = UDim2.fromOffset(170, 35),
		StudsOffset = Vector3.new(0, 3, 0),
		AlwaysOnTop = true,
		Parent = player.PlayerGui,
		Enabled = false,
	})
	local route = UI.label({
		Text = "",
		TextColor3 = C.Gold,
		MaxText = 22,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -36),
		Size = UDim2.fromOffset(380, 38),
		Parent = screen,
	})
	local crabWarning = UI.label({
		Text = "",
		TextColor3 = C.Coral,
		MaxText = 25,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 154),
		Size = UDim2.fromOffset(380, 35),
		Parent = screen,
	})
	UI.label({
		Text = "Walk into the egg!",
		TextColor3 = C.Gold,
		MaxText = 18,
		Size = UDim2.fromScale(1, 1),
		Parent = eggGuide,
	})
	local eggs = {}
	for i = 1, Cove.eggCount do
		local egg = MonsterModels.buildEgg("Splashfin", 1.3, false)
		eggs[i] = egg
	end
	local crabs = {}
	local warnings = {}
	local crabPositions = {}
	for i = 1, Cove.crabCount do
		local rig = MonsterModels.build("Crab", 1.8)
		if rig then
			crabs[i] = rig
			warnings[i] = UI.new("Highlight", {
				FillColor = C.Coral,
				OutlineColor = C.Gold,
				FillTransparency = 0.4,
				Adornee = rig.model,
				DepthMode = Enum.HighlightDepthMode.Occluded,
				Enabled = false,
				Parent = rig.model,
			})
		end
	end
	local main = player.PlayerGui:FindFirstChild("TideUI") :: ScreenGui?
	local run = {
		started = started,
		folder = folder,
		screen = screen,
		mainEnabled = if main then main.Enabled else true,
		state = nil,
		score = 0,
		lives = Cove.lives,
		carried = 0,
		hearts = hearts,
		flash = flash,
		beacon = beacon,
		eggGuide = eggGuide,
		crabs = crabs,
		snaps = {}, -- crab index -> when it last snapped (os.clock), for the lunge
		shakeUntil = 0,
	}
	round = run
	-- the screen shakes for a moment when a crab gets you
	RunService:BindToRenderStep("CoveShake", Enum.RenderPriority.Camera.Value + 2, function()
		local left = run.shakeUntil - os.clock()
		local camera = workspace.CurrentCamera
		if left > 0 and camera then
			local m = 0.55 * (left / 0.4)
			camera.CFrame = camera.CFrame * CFrame.new((math.random() - 0.5) * m, (math.random() - 0.5) * m, 0)
		end
	end)
	if main then
		main.Enabled = false
	end
	run.connection = RunService.RenderStepped:Connect(function(dt)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local viewport = camera.ViewportSize
		scale.Scale = math.min(viewport.X / 1280, viewport.Y / 720)
		local elapsed = workspace:GetServerTimeNow() - run.started
		local data = run.state
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if data then
			beacon.Enabled = root ~= nil and #data.carried > 0
			status.Text = "CRAB COVE   "
				.. math.max(0, math.ceil(Cove.duration - elapsed))
				.. "s   ·   "
				.. data.score
				.. " pts   ·   "
				.. #data.carried
				.. "/3"
			boost.Text = if data.boostEarned
				then "Hatch boost active · 1.5× · " .. Format.time(data.boostUntil - State.now()) .. " left"
				else "Eggs returned " .. data.delivered .. "/" .. Cove.hatchRewardEggs .. " · " .. Cove.hatchRewardText
			hint.Text = data.message
			local nearest: BasePart? = nil
			local nearestDistance = math.huge
			for i, egg in data.eggs do
				if egg.delivered then
					eggs[i].Parent = nil
					continue
				end
				local pos = egg.pos
				if egg.held and root then
					local slot = table.find(data.carried, i) or 1
					pos = root.Position + Vector3.new((slot - 2) * 1.6, 3, 0)
				end
				eggs[i]:PivotTo(
					CFrame.new(pos + Vector3.new(0, math.sin(elapsed * 3 + i) * 0.15, 0))
						* CFrame.Angles(0, elapsed * 0.4, 0)
				)
				if not eggs[i].Parent then
					eggs[i].Parent = folder
				end
				if root and not egg.held and #data.carried < 3 then
					local distance = (root.Position - pos).Magnitude
					if distance < nearestDistance then
						nearest = eggs[i].PrimaryPart
						nearestDistance = distance
					end
				end
				-- Regenerated golden eggs remain clearly identifiable.
				local highlight = eggs[i]:FindFirstChild("GoldenGlow") :: Highlight?
				if egg.golden and not highlight then
					highlight = Instance.new("Highlight")
					highlight.Name = "GoldenGlow"
					highlight.FillColor = C.Gold
					highlight.OutlineColor = C.Gold
					highlight.FillTransparency = 0.4
					highlight.Parent = eggs[i]
				elseif highlight then
					highlight.Enabled = egg.golden
				end
			end
			eggGuide.Adornee = nearest
			eggGuide.Enabled = nearest ~= nil and nearestDistance <= 40
			local returning = #data.carried > 0
			local target = if returning then keeper else nearest and nearest.Position
			route.Text = ""
			if root and target then
				local right = Vector3.new(camera.CFrame.RightVector.X, 0, camera.CFrame.RightVector.Z).Unit
				local forward = Vector3.yAxis:Cross(right)
				local delta = target - root.Position
				local angle = math.atan2(delta:Dot(right), delta:Dot(forward))
				local index = math.floor(angle / (math.pi / 4) + 0.5) % 8 + 1
				route.Text = directions[index]
					.. (if returning then " Cove Keeper · " else " Next egg · ")
					.. math.floor(delta.Magnitude)
					.. " studs"
			end
			-- the big instruction, the pillar and the line: what to do next, shown loud and clear
			local carrying = #data.carried > 0
			local goodGreen = Color3.fromRGB(130, 255, 160)
			-- the big guide is for the first round only (the server says so); after that it all stays hidden
			local guide = data.guide == true
			banner.Visible = guide
			beacon.Size = if guide then UDim2.fromOffset(420, 120) else UDim2.fromOffset(170, 35)
			beacon.StudsOffset = Vector3.new(0, if guide then 16 else 10, 0)
			banner.Text = if carrying
				then "YOU HAVE AN EGG!\nRun back to the Cove Keeper!"
				else "Find a glowing egg!\nFollow the green line to it"
			banner.TextColor3 = if carrying then C.Gold else goodGreen
			bannerScale.Scale = 1 + 0.05 * math.sin(elapsed * 7)
			beaconLabel.TextTransparency = if math.sin(elapsed * 6) > 0 then 0 else 0.35
			pillar.Transparency = if carrying and guide then 0.5 + 0.15 * math.sin(elapsed * 5) else 1
			local lineTarget = if carrying then keeper else nearest and nearest.Position
			if guide and root and lineTarget then
				fromPart.Position = root.Position + Vector3.new(0, 0.5, 0)
				toPart.Position = lineTarget + Vector3.new(0, if carrying then 1.5 else 0.5, 0)
				guideBeam.Color = ColorSequence.new(if carrying then C.Gold else goodGreen)
				guideBeam.Enabled = true
			else
				guideBeam.Enabled = false
			end
			local danger = false
			for i, rig in crabs do
				local crab = data.crabs[i]
				local pos = (crabPositions[i] or crab.pos):Lerp(crab.pos, 1 - math.exp(-dt * 14))
				crabPositions[i] = pos
				local windingUp = crab.strikeAt ~= nil
				warnings[i].Enabled = windingUp
				if root and windingUp and (root.Position - pos).Magnitude < 12 then
					danger = true
				end
				-- rearing up (0..1) in the instant before it snaps, from the server's strike time
				local rise = 0
				if windingUp then
					rise = math.clamp(1 - (crab.strikeAt - elapsed) / Cove.crabWarning, 0, 1)
				end
				-- the snap: lunge forward fast, then settle back, with the claws clacking
				local lunge = 0
				local clawTime: number? = nil
				local snapAt = run.snaps[i]
				if snapAt then
					local t = os.clock() - snapAt
					if t < 0.07 then
						lunge = 3 * t / 0.07
					elseif t < 0.32 then
						lunge = 3 * (1 - (t - 0.07) / 0.25)
					else
						run.snaps[i] = nil
					end
					clawTime = os.clock() * 16
				end
				local origin = CFrame.lookAt(pos, pos + crab.direction)
					* CFrame.new(0, 0.9 * rise, 0.45 * rise - lunge)
					* CFrame.Angles(math.rad(35 * rise), 0, 0)
				MonsterModels.pose(
					rig,
					origin,
					clawTime or (if windingUp then elapsed * 9 else elapsed * (if crab.chasing then 1.25 else 1)),
					true
				)
				if not rig.model.Parent then
					rig.model.Parent = folder
				end
			end
			crabWarning.Text = if danger then "Crab about to snap! Dodge sideways!" else ""
		end
	end)
end

local function hatchSticker(parent: GuiObject, y: number, title: string, detail: string, earned: boolean)
	local accent = if earned then Color3.fromRGB(184, 255, 163) else Color3.fromRGB(255, 226, 128)
	local sticker = UI.panel({
		Name = "HatchReward",
		Color = accent,
		Radius = 23,
		Rotation = -3,
		Size = UDim2.fromOffset(388, 108),
		Position = UDim2.new(0.5, 0, 0, y),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = parent,
	})
	local rim = sticker:FindFirstChildOfClass("UIStroke")
	if rim then
		rim.Color = Color3.fromRGB(255, 253, 241)
		rim.Thickness = 6
	end
	UI.new("ImageLabel", {
		Image = Config.ICONS.LuckEgg,
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(92, 92),
		Position = UDim2.fromOffset(12, 5),
		Rotation = -8,
		Parent = sticker,
	})
	UI.label({
		Text = title,
		TextColor3 = C.Ink,
		Stroke = 0,
		MaxText = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromOffset(245, 20),
		Position = UDim2.fromOffset(110, 9),
		Parent = sticker,
	})
	UI.label({
		Text = "1.5×",
		TextColor3 = C.Ink,
		Stroke = 0,
		MaxText = 43,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromOffset(112, 49),
		Position = UDim2.fromOffset(110, 25),
		Parent = sticker,
	})
	UI.label({
		Text = "HATCH SPEED",
		TextColor3 = C.Ink,
		Stroke = 0,
		MaxText = 19,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromOffset(154, 34),
		Position = UDim2.fromOffset(213, 34),
		Parent = sticker,
	})
	UI.label({
		Text = detail,
		TextColor3 = C.Ink,
		Stroke = 0,
		MaxText = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromOffset(264, 25),
		Position = UDim2.fromOffset(110, 73),
		Parent = sticker,
	})
	if earned then
		UI.pop(sticker, 0.82, 1)
	end
end

function MiniGames.cove()
	if starting or round then
		return
	end
	local _, body = Menus.openWindow("Cove Keeper", Vector2.new(570, 448), C.Sea)
	UI.label({
		Text = "The crabs stole our eggs!\nCan you bring them back?",
		MaxText = 28,
		TextColor3 = C.Ink,
		Stroke = 0,
		Size = UDim2.new(1, -32, 0, 62),
		Position = UDim2.fromOffset(16, 5),
		Parent = body,
	})
	hatchSticker(body, 82, "HATCH REWARD", "Return " .. Cove.hatchRewardEggs .. " eggs · 10 minutes", false)
	UI.label({
		Text = "Follow the arrow to find eggs all around the island.\nWalk into an egg, then bring it back to me!\nDodge when a crab glows. Three hits end your round.",
		MaxText = 21,
		TextColor3 = C.Ink,
		Stroke = 0,
		TextWrapped = true,
		Size = UDim2.new(1, -32, 0, 84),
		Position = UDim2.fromOffset(16, 207),
		Parent = body,
	})
	UI.button({
		Text = "Start Rescue",
		Color = C.Kelp,
		Size = UDim2.fromOffset(240, 52),
		Position = UDim2.new(0.5, 0, 1, -64),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = body,
	}, startRound)
end

-- "Your best: 14" + when full rewards are ready, over the Crab Cove stand (seen when nearby)
task.spawn(function()
	local world = workspace:WaitForChild("World")
	local prompt = world:FindFirstChild("CardsPrompt", true)
	local tries = 0
	while not prompt and tries < 60 do
		task.wait(1)
		tries += 1
		prompt = world:FindFirstChild("CardsPrompt", true)
	end
	local host = prompt and prompt.Parent :: BasePart?
	if not host then
		return
	end
	local bestGui = UI.new("BillboardGui", { ResetOnSpawn = false, Size = UDim2.fromOffset(260, 56), StudsOffset = Vector3.new(0, 10, 0), MaxDistance = 70, LightInfluence = 0, Adornee = host, Parent = player:WaitForChild("PlayerGui") })
	local bestLbl = UI.label({ Text = "", TextColor3 = C.Gold, Stroke = 3, MaxText = 26, Size = UDim2.fromScale(1, 0.55), Parent = bestGui })
	local readyLbl = UI.label({ Text = "", TextColor3 = C.White, Stroke = 2, MaxText = 18, Size = UDim2.fromScale(1, 0.45), Position = UDim2.fromScale(0, 0.55), Parent = bestGui })
	while bestGui.Parent do
		local s = State.snapshot
		if s then
			bestLbl.Text = "Your best: " .. (s.coveBest or 0)
			local at = (s.miniAt and s.miniAt.cove or 0) + Config.MINIGAMES.cove.cooldown
			local left = at - State.now()
			readyLbl.Text = if left > 0 then "Rewards in " .. Format.time(left) else "Rewards ready!"
			readyLbl.TextColor3 = if left > 0 then C.White else C.Kelp
		end
		task.wait(1)
	end
end)

Remotes.event("MiniGame").OnClientEvent:Connect(function(kind, data)
	if kind == "state" then
		if round then
			if data.boostEarned and not round.boostEarned then
				Sound.play("Hatch", 0.8)
			elseif data.score > round.score then
				Sound.play("Coin", 0.6)
			elseif #data.carried > round.carried then
				Sound.play("Hatch", 0.6)
			end
			if data.lives < round.lives then
				-- a heart is lost: the hearts pop big and flash white, and OUCH! floats over you
				Sound.play("Lose", 0.6)
				local char = player.Character
				popAbove(char and char:FindFirstChild("HumanoidRootPart") :: BasePart?, "OUCH! -1 ♥", C.Coral)
				local sc = round.hearts:FindFirstChildOfClass("UIScale") or UI.new("UIScale", { Parent = round.hearts })
				sc.Scale = 2
				UI.tween(sc, 0.55, { Scale = 1 }, Enum.EasingStyle.Back)
				round.hearts.TextColor3 = Color3.new(1, 1, 1)
				UI.tween(round.hearts, 0.7, { TextColor3 = C.Coral })
			end
			round.hearts.Text = string.rep("♥ ", data.lives) .. string.rep("♡ ", Cove.lives - data.lives)
			round.lives = data.lives
			round.carried = #data.carried
			round.score = data.score
			round.boostEarned = data.boostEarned
			round.state = data
		end
	elseif kind == "snap" then
		-- a crab snapped (the server says so the moment it happens): lunge, SNAP!, and if it hit you,
		-- a red flash and a screen shake
		if round then
			round.snaps[data.crab] = os.clock()
			local rig = round.crabs[data.crab]
			popAbove(rig and rig.model.PrimaryPart, "SNAP!", if data.hit then C.Coral else C.Gold)
			Sound.play("Hit", 0.8, 1.3)
			if data.hit then
				round.shakeUntil = os.clock() + 0.4
				round.flash.BackgroundTransparency = 0.5
				UI.tween(round.flash, 0.5, { BackgroundTransparency = 1 })
			end
		end
	elseif kind == "ended" then
		cleanup()
		if data.gameOver then
			Sound.play("Lose", 0.6)
		end
		local _, body = Menus.openWindow("Crab Cove", Vector2.new(540, 406), C.Sea)
		local boostLeft = data.boostUntil - State.now()
		UI.label({
			Text = if data.gameOver
				then "Game over! You lost all 3 hearts."
				elseif data.completed then "Time's up!"
				else "Back at the harbour",
			MaxText = 32,
			TextColor3 = C.Ink,
			Stroke = 0,
			Size = UDim2.new(1, 0, 0, 48),
			Parent = body,
		})
		local hatchTitle = if data.boostEarned
			then "BOOST EARNED!"
			elseif boostLeft > 0 then "BOOST STILL ACTIVE"
			else "HATCH REWARD"
		local hatchDetail = if boostLeft > 0
			then Format.time(boostLeft) .. " left"
			else data.delivered .. " / " .. Cove.hatchRewardEggs .. " eggs returned"
		hatchSticker(body, 66, hatchTitle, hatchDetail, data.boostEarned)
		UI.label({
			Text = data.score .. " points · Best " .. data.best .. (if data.reward ~= ""
				then "\n" .. data.reward
				else ""),
			MaxText = 23,
			TextColor3 = C.Ink,
			Stroke = 0,
			TextWrapped = true,
			Size = UDim2.new(1, -30, 0, 61),
			Position = UDim2.fromOffset(15, 194),
			Parent = body,
		})
		UI.button({
			Text = "Play Again",
			Color = C.Kelp,
			Size = UDim2.fromOffset(220, 52),
			Position = UDim2.new(0.5, 0, 1, -62),
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = body,
		}, startRound)
	end
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if round and not processed and input.KeyCode == Enum.KeyCode.ButtonB then
		State.action("MiniFinish")
	end
end)
return MiniGames
