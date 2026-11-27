--!strict
-- Tap to help in your own fight (Phase 2): click / tap anywhere on the world while your team
-- battles and you hit the enemy too (the server decides the damage, Config.TAP). Every tap fills
-- the RAGE meter at the bottom; when it is full the big SUPER SPLASH! button lights up.
-- Also owns the screen-wide drama: the combo counter, screen shake, the red ENRAGED tint with
-- faster music, and the white flash on a boss's final blow. BattleView draws the world effects
-- and calls in here for the HUD bits.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local UI = require(script.Parent.UI)
local Hud = require(script.Parent.Hud)
local Sound = require(script.Parent.Sound)
local State = require(script.Parent.State)

local TapFight = {}

local player = Players.LocalPlayer
local C = UI.Colors

local root: Frame
local rageBack: Frame
local rageFill: Frame
local rageLbl: TextLabel
local superBtn: TextButton
local hintLbl: TextLabel
local comboLbl: TextLabel
local flashFrame: Frame
local tint: ColorCorrectionEffect

local rage = 0
local lastSend = 0
local combo = 0
local lastTapAt = 0
local tappedThisFight = false
local shakeAmt = 0
local wasInBattle = false
local enraged = false

local function full(): boolean
	return rage >= Config.TAP.rageMax
end

local function canTap(): boolean
	if not Hud.inBattle or State.cinematic or State.revealing then
		return false
	end
	local Menus = require(script.Parent.Menus) :: any
	return not Menus.isOpen()
end

-- a short camera wobble (amount in studs, fades out by itself)
function TapFight.shake(amount: number)
	shakeAmt = math.max(shakeAmt, amount)
end

function TapFight.setRage(v: number)
	rage = math.clamp(v, 0, Config.TAP.rageMax)
	local k = rage / Config.TAP.rageMax
	UI.tween(rageFill, 0.12, { Size = UDim2.fromScale(k, 1) })
	rageLbl.Text = if full() then "RAGE FULL!" else "RAGE"
	superBtn.Visible = full() and Hud.inBattle
	if superBtn.Visible and not superBtn:GetAttribute("Popped") then
		superBtn:SetAttribute("Popped", true)
		UI.pop(superBtn, 0.5)
		Sound.play("ZoneChime", 0.8, 1.3)
	elseif not superBtn.Visible then
		superBtn:SetAttribute("Popped", nil)
	end
end

-- Send a tap (mouse, touch or RB). Client-side limit matches the server's.
function TapFight.tap()
	if not canTap() then
		return
	end
	local now = os.clock()
	if now - lastSend < 1 / Config.TAP.maxPerSecond then
		return
	end
	lastSend = now
	Remotes.event("Tap"):FireServer("tap")
end

function TapFight.super()
	if not canTap() or not full() then
		return
	end
	Remotes.event("Tap"):FireServer("super")
end

-- The server accepted one of my taps
function TapFight.onMyTap(crit: boolean, newRage: number)
	local now = os.clock()
	combo = if now - lastTapAt < 1.2 then combo + 1 else 1
	lastTapAt = now
	if not tappedThisFight then
		tappedThisFight = true
		hintLbl.Visible = false
	end
	TapFight.setRage(newRage)
	TapFight.shake(if crit then 0.45 else 0.12)
	if combo >= 5 then
		comboLbl.Text = "x" .. combo .. " COMBO!"
		comboLbl.TextColor3 = if combo >= 40 then C.Coral elseif combo >= 20 then C.Gold else C.White
		comboLbl.Visible = true
		comboLbl.Rotation = math.random(-6, 6)
		UI.pop(comboLbl, 0.15)
	end
	Sound.play("Hit", if crit then 0.6 else 0.3, if crit then 0.8 else 1 + math.min(0.5, combo * 0.01))
end

function TapFight.onMySuper()
	TapFight.setRage(0)
	TapFight.shake(1.2)
	Hud.splash("SUPER SPLASH!", C.Sea)
	Sound.play("Super", 1, 0.85)
	Sound.play("Splash", 1, 0.8)
end

-- A boss hit 25% health: red screen tint + faster music
function TapFight.onMyEnrage(name: string?)
	enraged = true
	Hud.splash("BOSS ENRAGED!", C.Coral)
	Hud.toast((if name then string.upper(name) else "THE BOSS") .. " IS ENRAGED! Tap fast!", C.Coral)
	TweenService:Create(tint, TweenInfo.new(0.6), { TintColor = Color3.fromRGB(255, 205, 200), Saturation = 0.15 }):Play()
	Sound.setMusicSpeed(1.25)
	TapFight.shake(0.8)
	Sound.play("EnemyDie", 0.7, 0.6)
end

local function calm()
	if enraged then
		enraged = false
		TweenService:Create(tint, TweenInfo.new(1), { TintColor = Color3.new(1, 1, 1), Saturation = 0 }):Play()
		Sound.setMusicSpeed(1)
	end
end

-- The killing blow on a boss: white flash, a big shake, a camera punch-in
function TapFight.finalBlow()
	calm()
	flashFrame.BackgroundTransparency = 0.15
	flashFrame.Visible = true
	TweenService:Create(flashFrame, TweenInfo.new(0.8, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
	task.delay(0.85, function()
		flashFrame.Visible = false
	end)
	TapFight.shake(1.6)
	Hud.splash("FINAL BLOW!", C.Gold)
	local cam = workspace.CurrentCamera
	local fov = cam.FieldOfView
	TweenService:Create(cam, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { FieldOfView = fov - 12 }):Play()
	task.delay(0.6, function()
		TweenService:Create(cam, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { FieldOfView = fov }):Play()
	end)
end

local function fightStarted()
	tappedThisFight = false
	combo = 0
	hintLbl.Visible = true
	UI.pop(hintLbl, 0.4)
	TapFight.setRage(0)
end

local function fightEnded()
	calm()
	comboLbl.Visible = false
	hintLbl.Visible = false
	TapFight.setRage(0)
end

function TapFight.init(screen: ScreenGui)
	tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "EnrageTint"
	tint.Parent = Lighting

	root = UI.new("Frame", { Name = "TapFight", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = screen })
	flashFrame = UI.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 30, Visible = false, Parent = screen })

	-- the rage meter + SUPER button sit on the right, above the jump button (toasts own the bottom centre)
	rageBack = UI.new("Frame", { Size = UDim2.fromOffset(240, 24), Position = UDim2.new(1, -30, 1, -180), AnchorPoint = Vector2.new(1, 1), BackgroundColor3 = Color3.fromRGB(40, 30, 50), Parent = root }, { UI.corner(10), UI.stroke(3) })
	rageFill = UI.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.White, Parent = rageBack }, { UI.corner(10), UI.gradient(C.Sea) })
	rageLbl = UI.label({ Text = "RAGE", Size = UDim2.fromScale(1, 0.85), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 3, Parent = rageBack })

	hintLbl = UI.label({ Text = "TAP THE SCREEN TO HELP!", TextColor3 = C.Gold, Stroke = 3, Size = UDim2.fromOffset(420, 30), Position = UDim2.new(0.5, 0, 1, -66), AnchorPoint = Vector2.new(0.5, 1), Visible = false, Parent = root })

	superBtn = UI.button({ Text = "SUPER SPLASH!", Color = C.Sea, Size = UDim2.fromOffset(240, 64), Position = UDim2.new(1, -30, 1, -212), AnchorPoint = Vector2.new(1, 1), Visible = false, Parent = root }, function()
		TapFight.super()
	end)

	comboLbl = UI.label({ Text = "", TextColor3 = C.White, Stroke = 4, MaxText = 44, Size = UDim2.fromOffset(260, 50), Position = UDim2.new(0.5, 230, 0.5, -40), AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, Parent = root })

	-- taps: any click / touch on the world (GUI clicks are "processed" and never count)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			TapFight.tap()
		end
	end)

	RunService.Heartbeat:Connect(function()
		local on = Hud.inBattle
		if on ~= wasInBattle then
			wasInBattle = on
			if on then
				fightStarted()
			else
				fightEnded()
			end
		end
		root.Visible = on and not State.cinematic and not State.revealing
		-- the combo fades if you stop tapping
		if comboLbl.Visible and os.clock() - lastTapAt > 1.2 then
			comboLbl.Visible = false
			combo = 0
		end
		-- the SUPER button breathes while it waits
		if superBtn.Visible then
			local s = 1 + math.sin(os.clock() * 8) * 0.04
			superBtn.Size = UDim2.fromOffset(240 * s, 64 * s)
		end
	end)

	-- screen shake, applied after the camera has moved this frame
	RunService:BindToRenderStep("TapFightShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
		if shakeAmt <= 0.01 then
			shakeAmt = 0
			return
		end
		local cam = workspace.CurrentCamera
		local a = shakeAmt
		cam.CFrame = cam.CFrame * CFrame.new((math.random() - 0.5) * a, (math.random() - 0.5) * a, 0) * CFrame.Angles(0, 0, (math.random() - 0.5) * a * 0.02)
		shakeAmt = math.max(0, shakeAmt - dt * 4)
	end)
	local _ = player
end

return TapFight
