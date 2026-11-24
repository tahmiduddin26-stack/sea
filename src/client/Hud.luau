--!strict
-- The always-on HUD, laid out like the reference game so it reads instantly:
--   left column   big 3D icons with labels + red badges: Shop, Event, Index, Team (n/cap), Gifts
--   right column  Starter Pack (creature art) + one rotating Robux offer, each with a price chip
--   top centre    FIGHT + swords "Team Power: N" when idle; the Depth bar (15 dots, skull
--                 mini-boss, crowned boss), enemy name + HP, boss timer, speed + Retreat in a fight
--   top banner    one tutorial line with a gold key word (Guide drives it)
--   bottom left   pearl + coin icons with big numbers and "+N" pops; the Powers card above
--   bottom centre big heart "Fuse!" button and the egg hotbar slot
-- Menus/offers stay hidden until the tutorial reaches Config.HUD_UNLOCK_STEP.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Stats = require(Shared.Stats)
local MonsterModels = require(Shared.MonsterModels)

local UI = require(script.Parent.UI)
local State = require(script.Parent.State)
local Platform = require(script.Parent.Platform)

local Hud = {}

local C = UI.Colors
local I = Config.ICONS
local player = Players.LocalPlayer

local root: Frame
local fightBtn: TextButton
local teamBtn: TextButton -- "Pick Team", beside FIGHT
local slotBadge: Frame -- the red "!" on it when you can afford your next team slot
local slotPromptedFor = -1 -- the team size we last told the player about (once per new slot)
local powerLbl: TextLabel
local depthBar: Frame
local depthLbl: TextLabel
local stageLbl: TextLabel
local dots: { Frame } = {}
local enemyFill: Frame
local enemyName: TextLabel
local enemyHpLbl: TextLabel
local bossTimer: Frame
local bossFill: Frame
local speedBtn: GuiButton
local speedLbl: TextLabel
local coinLbl: TextLabel
local pearlLbl: TextLabel
local leftCol: Frame
local rightCol: Frame
local rightLayout: UIListLayout
local fuseBtn: ImageButton
local sellBtn: ImageButton
local banner: Frame
local bannerLbl: TextLabel
local toastHolder: Frame
local offerBtn: ImageButton
local offerIcon: ImageLabel
local offerTitle: TextLabel
local offerPrice: TextLabel
local starterBtn: GuiObject
local badges: { [string]: TextLabel } = {}
local teamCount: TextLabel
local hotbar: Frame
local hotbarSlot: Frame
local powersCard: TextButton
local giftLbl: TextLabel
local spellRow: Frame
local fuseRing: UIStroke -- the ring around the Fuse heart that pulses while a fuse is possible
local settingsBtn: TextButton -- the gear: music / sound volume (always shown, even mid-tutorial)

local handlers: { [string]: () -> () } = {}
function Hud.on(name: string, fn: () -> ())
	handlers[name] = fn
end
local function fire(name: string)
	local h = handlers[name]
	if h then
		h()
	end
end
Hud.press = fire

Hud.inBattle = false
Hud.fuseOpen = false -- FuseView's tray is open (the heart button gives way to it)
Hud.indexSeen = 0
local bossEnds = 0
local bossTotal = 0

---------------------------------------------------------------------------
-- Building blocks
---------------------------------------------------------------------------
-- A floating 3D icon with a stroked label under it and an optional red badge.
local function iconButton(parent: Instance, icon: string, text: string, size: number, onClick: () -> ()): ImageButton
	local b = UI.new("ImageButton", { BackgroundTransparency = 1, Image = icon, Size = UDim2.fromOffset(size, size), ScaleType = Enum.ScaleType.Fit, Parent = parent })
	local sc = UI.new("UIScale", { Parent = b })
	UI.label({ Name = "Label", Text = text, Size = UDim2.new(1.4, 0, 0, 24), Position = UDim2.new(0.5, 0, 1, -18), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 3, Parent = b })
	b.MouseEnter:Connect(function()
		UI.tween(sc, 0.12, { Scale = 1.1 })
	end)
	b.MouseLeave:Connect(function()
		UI.tween(sc, 0.12, { Scale = 1 })
	end)
	b.MouseButton1Down:Connect(function()
		UI.tween(sc, 0.08, { Scale = 0.88 })
	end)
	b.MouseButton1Up:Connect(function()
		UI.tween(sc, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	b.Activated:Connect(function()
		local Sound = require(script.Parent.Sound) :: any
		Sound.play("Click")
		onClick()
	end)
	return b
end

local function badge(parent: GuiObject, key: string): TextLabel
	local f = UI.new("Frame", { Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, -14, 0, -2), BackgroundColor3 = C.Coral, Visible = false, ZIndex = 4, Parent = parent }, { UI.corner(13), UI.stroke(2.5) })
	local l = UI.label({ Text = "", Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.1), ZIndex = 5, Parent = f })
	badges[key] = l
	return l
end

local function setBadge(key: string, n: number)
	local l = badges[key]
	if l then
		(l.Parent :: GuiObject).Visible = n > 0
		l.Text = if n > 9 then "9+" else tostring(n)
	end
end

-- Green price chip: Robux tag icon + "69"
local function priceChip(parent: GuiObject, price: number, y: number): TextLabel
	local chip = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(90, 28), Position = UDim2.new(0.5, 0, 0, y), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 4, Parent = parent })
	UI.new("ImageLabel", { BackgroundTransparency = 1, Image = I.Robux, Size = UDim2.fromOffset(28, 28), ZIndex = 4, Parent = chip })
	return UI.label({ Text = tostring(price), TextColor3 = Color3.fromRGB(120, 240, 120), TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -32, 1, 0), Position = UDim2.fromOffset(32, 0), ZIndex = 4, Parent = chip })
end

-- Two creatures in a viewport (offer art)
local function creatureArt(parent: GuiObject, ids: { string }, size: UDim2): ViewportFrame
	local vp = UI.new("ViewportFrame", { BackgroundTransparency = 1, Size = size, Ambient = Color3.fromRGB(210, 210, 220), LightDirection = Vector3.new(-1, -1, -1), ZIndex = 2, Parent = parent })
	for i, id in ids do
		local rig = MonsterModels.build(id, 1)
		if rig then
			local x = (i - (#ids + 1) / 2) * 2.6
			MonsterModels.pose(rig, CFrame.new(x, 0, i * 0.6) * CFrame.Angles(0, math.rad(-20 + i * 25), 0), i, false, false)
			rig.model.Parent = vp
		end
	end
	local cam = Instance.new("Camera")
	cam.FieldOfView = 34
	cam.CFrame = CFrame.lookAt(Vector3.new(-2, 2.5, -9.5), Vector3.new(0, 0.6, 0.6))
	cam.Parent = vp
	vp.CurrentCamera = cam
	return vp
end

---------------------------------------------------------------------------
-- Toasts
---------------------------------------------------------------------------
function Hud.toast(text: string, color: Color3?)
	if not toastHolder then
		return
	end
	local t = UI.panel({ Size = UDim2.fromOffset(480, 46), Color = color or C.Deep, Parent = toastHolder })
	UI.label({ Text = text, Size = UDim2.new(1, -24, 0.7, 0), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = t })
	UI.pop(t, 0.7)
	task.delay(3.2, function()
		UI.tween(t, 0.3, { BackgroundTransparency = 1 })
		for _, d in t:GetDescendants() do
			if d:IsA("TextLabel") then
				UI.tween(d, 0.3, { TextTransparency = 1 })
			elseif d:IsA("UIStroke") then
				UI.tween(d, 0.3, { Transparency = 1 })
			end
		end
		task.wait(0.35)
		t:Destroy()
	end)
end

---------------------------------------------------------------------------
-- Banner (tutorial): big stroked words on a soft dark ribbon
---------------------------------------------------------------------------
function Hud.banner(text: string?)
	if not text then
		banner.Visible = false
		return
	end
	local new = UI.keyword(text)
	if bannerLbl.Text ~= new or not banner.Visible then
		bannerLbl.Text = new
		banner.Visible = true
		UI.pop(banner, 0.85)
	end
end

---------------------------------------------------------------------------
-- Currency pops
---------------------------------------------------------------------------
local shown = { coins = -1, pearls = -1, shells = -1, best = -1 }
local shellLbl: TextLabel -- Tide Festival shells (only shown while the festival runs)
local tickShown = -1
local tickTarget = 0
local screenRoot: ScreenGui

-- Big centre splash ("NEW BEST: DEPTH 20!", "LEGENDARY!") that pops and floats away
function Hud.splash(text: string, color: Color3?)
	if not root then
		return
	end
	local l = UI.label({ Text = text, TextColor3 = color or C.Gold, MaxText = 56, Stroke = 4, Size = UDim2.fromOffset(700, 70), Position = UDim2.fromScale(0.5, 0.36), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 20, Parent = root })
	UI.pop(l, 0.3)
	task.delay(1.4, function()
		UI.tween(l, 0.5, { Position = UDim2.fromScale(0.5, 0.3), TextTransparency = 1 })
		local st = l:FindFirstChildOfClass("UIStroke")
		if st then
			UI.tween(st, 0.5, { Transparency = 1 })
		end
		task.wait(0.55)
		l:Destroy()
	end)
end

-- A small card under the banner: one short line and one button. Returns the card (destroy it
-- to dismiss). Pressing the button runs onClick and dismisses it.
function Hud.callout(text: string, buttonText: string, onClick: () -> ()): Frame?
	if not root then
		return nil
	end
	local card = UI.panel({ Size = UDim2.fromOffset(430, 116), Position = UDim2.new(0.5, 0, 0, 176), AnchorPoint = Vector2.new(0.5, 0), Radius = 18, ZIndex = 20, Parent = root })
	UI.label({ Text = text, Stroke = 0, TextColor3 = C.Ink, MaxText = 26, Size = UDim2.new(1, -24, 0, 36), Position = UDim2.fromOffset(12, 10), ZIndex = 21, Parent = card })
	UI.button({ Text = buttonText, Color = C.Kelp, Size = UDim2.fromOffset(200, 50), Position = UDim2.new(0.5, 0, 1, -12), AnchorPoint = Vector2.new(0.5, 1), ZIndex = 21, Parent = card }, function()
		card:Destroy()
		onClick()
	end)
	UI.pop(card, 0.6)
	return card
end

local function spellDef(id: string): any
	for _, sp in Config.SPELLS do
		if sp.id == id then
			return sp
		end
	end
	return nil
end

-- Casting a spell, in the ship's own style (planks, brass, rope, parchment, wax): the sea dims, a
-- parchment scroll with wooden rollers unrolls, the spell sits in a brass porthole, its name hangs
-- on a plank sign, a wax seal in the spell's rarity colour stamps down and bubbles drift up. Then
-- the scroll rolls up and flies to the buff row at the top right. Drawn on the screen itself
-- (above every menu), so it plays right over the Spellbook.
function Hud.spellCast(id: string)
	local sp = spellDef(id)
	if not sp or not screenRoot then
		return
	end
	local Sound = require(script.Parent.Sound) :: any
	local r = Config.RARITY[sp.rarity]
	local col: Color3 = r.color
	local Z = 900
	local holder = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = Z, Parent = screenRoot })
	-- the sea dims behind the scroll (a plain dark blue, no flash)
	local dim = UI.new("Frame", { BackgroundColor3 = Color3.fromRGB(8, 22, 44), BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = Z, Parent = holder })
	UI.tween(dim, 0.25, { BackgroundTransparency = 0.55 })

	local W, H = 380, 310
	local scroll = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(W + 30, H + 40), Position = UDim2.fromScale(0.5, 0.45), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = Z + 1, Parent = holder })
	local sc = UI.new("UIScale", { Scale = 0.85, Parent = scroll })
	UI.tween(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	-- the parchment grows downward from the top roller, clipped so its contents are revealed as it unrolls
	local paper = UI.new("Frame", { BackgroundColor3 = C.Panel, BorderSizePixel = 0, ClipsDescendants = true, Size = UDim2.fromOffset(W, 0), Position = UDim2.new(0.5, 0, 0, 20), AnchorPoint = Vector2.new(0.5, 0), ZIndex = Z + 1, Parent = scroll }, { UI.stroke(3) })
	local function roller(y: number): Frame
		local bar = UI.new("Frame", { BackgroundColor3 = C.PlankDark, Size = UDim2.fromOffset(W + 30, 24), Position = UDim2.new(0.5, 0, 0, y), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = Z + 4, Parent = scroll }, { UI.corner(10), UI.stroke(3) })
		for _, sx in { 0, 1 } do
			-- brass caps on both ends
			UI.new("Frame", { BackgroundColor3 = C.Brass, Size = UDim2.fromOffset(18, 30), Position = UDim2.new(sx, if sx == 0 then 4 else -4, 0.5, 0), AnchorPoint = Vector2.new(sx, 0.5), ZIndex = Z + 5, Parent = bar }, { UI.corner(8), UI.stroke(2.5) })
		end
		return bar
	end
	roller(20) -- top (stays put)
	local bottom = roller(20) -- bottom (travels down as the scroll unrolls)
	UI.tween(paper, 0.45, { Size = UDim2.fromOffset(W, H) }, Enum.EasingStyle.Quad)
	UI.tween(bottom, 0.45, { Position = UDim2.new(0.5, 0, 0, 20 + H) }, Enum.EasingStyle.Quad)
	Sound.play("Click", 0.6, 0.9)

	-- the spell in a brass porthole (like the menus' close button ring)
	local ring = UI.new("Frame", { BackgroundColor3 = C.Brass, Size = UDim2.fromOffset(120, 120), Position = UDim2.new(0.5, 0, 0, 16), AnchorPoint = Vector2.new(0.5, 0), ZIndex = Z + 2, Parent = paper }, { UI.corner(120), UI.stroke(4) })
	local glass = UI.new("Frame", { BackgroundColor3 = Color3.fromRGB(32, 96, 150), Size = UDim2.fromOffset(98, 98), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = Z + 2, Parent = ring }, { UI.corner(98), UI.stroke(3) })
	UI.new("ImageLabel", { BackgroundTransparency = 1, Image = I[sp.icon], Size = UDim2.fromOffset(84, 84), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = Z + 3, Parent = glass })
	-- the name hangs on a plank sign
	UI.plank({ Text = sp.name, Color = C.Plank, MaxText = 28, TextColor = C.Brass, Size = UDim2.fromOffset(300, 44), Position = UDim2.new(0.5, 0, 0, 148), AnchorPoint = Vector2.new(0.5, 0), ZIndex = Z + 2, Parent = paper })
	UI.label({ Text = sp.desc, Stroke = 0, TextColor3 = C.Ink, MaxText = 24, Size = UDim2.fromOffset(W - 40, 30), Position = UDim2.new(0.5, 0, 0, 204), AnchorPoint = Vector2.new(0.5, 0), ZIndex = Z + 2, Parent = paper })
	UI.label({ Text = "for " .. sp.minutes .. " min", Stroke = 0, TextColor3 = C.Deep, MaxText = 20, Size = UDim2.fromOffset(W - 40, 24), Position = UDim2.new(0.5, 0, 0, 238), AnchorPoint = Vector2.new(0.5, 0), ZIndex = Z + 2, Parent = paper })
	-- the wax seal: rarity colour, its stars pressed in, stamped on after the scroll is open
	local seal = UI.new("Frame", { BackgroundColor3 = col:Lerp(Color3.new(0, 0, 0), 0.15), Size = UDim2.fromOffset(62, 62), Position = UDim2.new(1, -52, 1, -46), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = Z + 3, Visible = false, Parent = paper }, { UI.corner(62), UI.stroke(3) })
	UI.label({ Text = string.rep("★", sp.rarity), TextColor3 = col:Lerp(Color3.new(1, 1, 1), 0.65), Stroke = 1.5, MaxText = 20, Size = UDim2.fromScale(0.8, 0.5), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = Z + 4, Parent = seal })
	local sealScale = UI.new("UIScale", { Scale = 2.2, Parent = seal })
	task.delay(0.5, function()
		if not seal.Parent then
			return
		end
		seal.Visible = true
		UI.tween(sealScale, 0.16, { Scale = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.16, function()
			if sc.Parent then
				sc.Scale = 1.04 -- a small thump as it lands
				UI.tween(sc, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
			end
			Sound.play("Upgrade", 0.8)
		end)
	end)
	-- bubbles drift up the scroll (round, see-through, white rim)
	for k = 1, 14 do
		task.delay(0.3 + k * 0.06, function()
			if not holder.Parent then
				return
			end
			local d = math.random(10, 26)
			local x = math.random(-W / 2 + 20, W / 2 - 20)
			local b = UI.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.75, Size = UDim2.fromOffset(d, d), Position = UDim2.new(0.5, x, 0.45, H / 2 - 10), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = Z + 6, Parent = holder }, { UI.corner(d), UI.stroke(2, Color3.new(1, 1, 1)) })
			UI.tween(b, 1.3, { Position = UDim2.new(0.5, x + math.random(-30, 30), 0.45, -H / 2 - 20), BackgroundTransparency = 1 }, Enum.EasingStyle.Sine)
			local st = b:FindFirstChildOfClass("UIStroke")
			if st then
				UI.tween(st, 1.3, { Transparency = 1 })
			end
			task.delay(1.4, function()
				b:Destroy()
			end)
		end)
	end
	-- hold, roll up, then it flies to the buff row (top right)
	task.delay(1.7, function()
		UI.tween(dim, 0.3, { BackgroundTransparency = 1 })
		UI.tween(paper, 0.3, { Size = UDim2.fromOffset(W, 0) }, Enum.EasingStyle.Quad)
		UI.tween(bottom, 0.3, { Position = UDim2.new(0.5, 0, 0, 20) }, Enum.EasingStyle.Quad)
		task.wait(0.32)
		UI.tween(sc, 0.4, { Scale = 0.12 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		UI.tween(scroll, 0.4, { Position = UDim2.new(1, -50, 0, 36) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.wait(0.42)
		holder:Destroy()
	end)
end

-- A spell card drops: it pops up big in the middle, then shrinks away to the top right
function Hud.spellDrop(id: string)
	local sp = spellDef(id)
	if not sp or not root then
		return
	end
	local r = Config.RARITY[sp.rarity]
	local card = UI.panel({ Size = UDim2.fromOffset(190, 230), Position = UDim2.fromScale(0.5, 0.42), AnchorPoint = Vector2.new(0.5, 0.5), Color = Color3.fromRGB(255, 248, 230), ZIndex = 25, Parent = root })
	local st = card:FindFirstChildOfClass("UIStroke")
	if st then
		st.Color = r.color
		st.Thickness = 6
	end
	UI.label({ Text = "NEW SPELL!", TextColor3 = C.Gold, MaxText = 26, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, -38), ZIndex = 26, Parent = card })
	UI.new("ImageLabel", { BackgroundTransparency = 1, Image = I[sp.icon], Size = UDim2.fromOffset(110, 110), Position = UDim2.new(0.5, 0, 0, 12), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 26, Parent = card })
	UI.label({ Text = sp.name, TextColor3 = r.color, MaxText = 24, Size = UDim2.new(1, -12, 0, 30), Position = UDim2.fromOffset(6, 128), ZIndex = 26, Parent = card })
	UI.label({ Text = string.upper(r.name), TextColor3 = r.color, Stroke = 0, MaxText = 16, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 160), ZIndex = 26, Parent = card })
	UI.label({ Text = sp.desc, Stroke = 0, TextColor3 = C.Ink, MaxText = 16, Size = UDim2.new(1, -12, 0, 22), Position = UDim2.fromOffset(6, 186), ZIndex = 26, Parent = card })
	UI.pop(card, 0.3)
	local Sound = require(script.Parent.Sound) :: any
	Sound.play(if sp.rarity >= 3 then "Win" else "Coin", 0.7)
	task.delay(1.6, function()
		local sc = card:FindFirstChildOfClass("UIScale")
		if sc then
			UI.tween(sc, 0.4, { Scale = 0.2 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
		UI.tween(card, 0.4, { Position = UDim2.new(1, -60, 0, 40) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.wait(0.42)
		card:Destroy()
	end)
end

-- Coin icons burst from a world point and fly into the coin counter
function Hud.flyCoins(worldPos: Vector3, count: number)
	if not root or not screenRoot then
		return
	end
	local cam = workspace.CurrentCamera
	local sp, onScreen = cam:WorldToViewportPoint(worldPos)
	if not onScreen then
		return
	end
	local inset = screenRoot.AbsolutePosition
	local sc = screenRoot:FindFirstChildOfClass("UIScale")
	local scale = if sc then sc.Scale else 1
	local target = coinLbl.Parent :: GuiObject
	local tx = (target.AbsolutePosition.X - inset.X + 28) / scale
	local ty = (target.AbsolutePosition.Y - inset.Y + 28) / scale
	local sx, sy = (sp.X - inset.X) / scale, (sp.Y - inset.Y) / scale
	for k = 1, math.clamp(count, 1, 8) do
		local img = UI.new("ImageLabel", { BackgroundTransparency = 1, Image = I.Coin, Size = UDim2.fromOffset(34, 34), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(sx, sy), ZIndex = 15, Parent = root })
		local mid = UDim2.fromOffset(sx + math.random(-70, 70), sy + math.random(-70, 10))
		task.spawn(function()
			UI.tween(img, 0.22, { Position = mid }, Enum.EasingStyle.Quad)
			task.wait(0.22 + k * 0.04)
			UI.tween(img, 0.45, { Position = UDim2.fromOffset(tx, ty), Size = UDim2.fromOffset(22, 22) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.wait(0.46)
			img:Destroy()
			local cs = target:FindFirstChildOfClass("UIScale") or UI.new("UIScale", { Parent = target })
			cs.Scale = 1.15
			UI.tween(cs, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
		end)
	end
end
local function popNumber(lbl: TextLabel, delta: number, color: Color3)
	local p = UI.label({ Text = "+" .. Format.abbrev(delta), TextColor3 = color, Size = UDim2.fromOffset(120, 30), Position = UDim2.new(0, lbl.TextBounds.X + 10, 0, 2), TextXAlignment = Enum.TextXAlignment.Left, Parent = lbl })
	UI.tween(p, 0.9, { Position = UDim2.new(0, lbl.TextBounds.X + 10, 0, -26), TextTransparency = 1 })
	task.delay(0.95, function()
		p:Destroy()
	end)
	local sc = lbl:FindFirstChildOfClass("UIScale") or UI.new("UIScale", { Parent = lbl })
	sc.Scale = 1.2
	UI.tween(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
end

local function currency(y: number, icon: string, size: number, infoName: string): TextLabel
	local f = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(260, size), Position = UDim2.new(0, 14, 1, y), Parent = root })
	UI.new("ImageLabel", { BackgroundTransparency = 1, Image = icon, Size = UDim2.fromOffset(size, size), Parent = f })
	-- tap the chip (or its little "?") to learn what this currency is and where to get it
	local hit = UI.new("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = f })
	hit.Activated:Connect(function()
		fire(infoName)
	end)
	local q = UI.new("Frame", { Name = "Info", BackgroundColor3 = C.Brass, Size = UDim2.fromOffset(22, 22), Position = UDim2.new(0, 120, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 4, Parent = f }, { UI.corner(22), UI.stroke(2) })
	UI.label({ Text = "?", Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Stroke = 1.5, ZIndex = 5, Parent = q })
	local amount = UI.label({ Text = "0", TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(190, size * 0.78), Position = UDim2.new(0, size + 6, 0.11, 0), Stroke = 3, MaxText = 40, Parent = f })
	-- keep the "?" snug against the number as it grows (788K, 1.2M ...)
	-- (TextBounds is useless for scaled text, so the width is estimated from the digit count)
	amount:GetPropertyChangedSignal("Text"):Connect(function()
		local fs = math.min(40, size * 0.78)
		q.Position = UDim2.new(0, size + 6 + #amount.Text * 0.56 * fs + 8, 0.5, 0)
	end)
	return amount
end

---------------------------------------------------------------------------
-- Depth bar
---------------------------------------------------------------------------
local function buildDepthBar()
	depthBar = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(600, 150), Position = UDim2.new(0.5, 0, 0, 4), AnchorPoint = Vector2.new(0.5, 0), Visible = false, Parent = root })
	depthLbl = UI.label({ Text = "Depth 1", Size = UDim2.fromOffset(200, 36), Position = UDim2.new(0.5, 0, 0, 0), AnchorPoint = Vector2.new(0.5, 0), Stroke = 3, Parent = depthBar })
	stageLbl = UI.label({ Text = "", TextColor3 = Color3.fromRGB(150, 225, 255), Size = UDim2.fromOffset(260, 18), Position = UDim2.new(0.5, 0, 0, 34), AnchorPoint = Vector2.new(0.5, 0), Parent = depthBar })
	UI.new("Frame", { BackgroundColor3 = C.Ink, Size = UDim2.fromOffset(470, 6), Position = UDim2.new(0.5, 0, 0, 70), AnchorPoint = Vector2.new(0.5, 0.5), Parent = depthBar }, { UI.corner(3) })
	for i = 1, Config.STAGE_LENGTH do
		local x = (i - 1) / (Config.STAGE_LENGTH - 1)
		local pos = UDim2.new(0.5, -235 + x * 470, 0, 70)
		if i == Config.MINIBOSS_AT or i == Config.STAGE_LENGTH then
			local img = UI.new("ImageLabel", { BackgroundColor3 = Color3.fromRGB(60, 70, 95), Image = if i == Config.STAGE_LENGTH then I.Boss else I.Skull, Size = UDim2.fromOffset(34, 34), Position = pos, AnchorPoint = Vector2.new(0.5, 0.5), Parent = depthBar }, { UI.corner(8), UI.stroke(2.5) })
			dots[i] = img
		else
			dots[i] = UI.new("Frame", { Size = UDim2.fromOffset(18, 18), Position = pos, AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(60, 70, 95), Parent = depthBar }, { UI.corner(9), UI.stroke(2.5) })
		end
	end
	local enemyBar = UI.new("Frame", { Size = UDim2.fromOffset(400, 26), Position = UDim2.new(0.5, 0, 0, 98), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = Color3.fromRGB(40, 30, 50), Parent = depthBar }, { UI.corner(8), UI.stroke(3) })
	enemyFill = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.White, Parent = enemyBar }, { UI.corner(8), UI.gradient(C.Coral) })
	enemyName = UI.label({ Text = "", TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(0.7, 0, 0.8, 0), Position = UDim2.new(0, 10, 0.1, 0), ZIndex = 2, Parent = enemyBar })
	enemyHpLbl = UI.label({ Text = "", TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.new(0.3, -10, 0.8, 0), Position = UDim2.new(0.7, 0, 0.1, 0), ZIndex = 2, Parent = enemyBar })
	bossTimer = UI.new("Frame", { Size = UDim2.fromOffset(300, 12), Position = UDim2.new(0.5, 0, 0, 130), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = Color3.fromRGB(40, 30, 50), Visible = false, Parent = depthBar }, { UI.corner(6), UI.stroke(2.5) })
	bossFill = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Gold, Parent = bossTimer }, { UI.corner(6) })
	-- restart-style speed button + Retreat, to the right of the title like the reference
	speedBtn = UI.button({ Text = "", Color = C.Gold, Size = UDim2.fromOffset(70, 36), Position = UDim2.new(0.5, 118, 0, 0), Parent = depthBar }, function()
		fire("Speed")
	end)
	UI.new("ImageLabel", { BackgroundTransparency = 1, Image = I.Speed, Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(4, 3), ZIndex = 3, Parent = speedBtn })
	speedLbl = UI.label({ Text = "x1", Size = UDim2.new(0, 30, 0.7, 0), Position = UDim2.new(0, 36, 0.15, 0), ZIndex = 3, Parent = speedBtn })
	UI.button({ Text = "Retreat", Color = C.Coral, Size = UDim2.fromOffset(104, 36), Position = UDim2.new(0.5, 196, 0, 0), Parent = depthBar }, function()
		fire("Retreat")
	end)
end

function Hud.setDepth(depth: number, stage: string)
	depthLbl.Text = 'Depth <font color="#7CFF7C">' .. depth .. "</font>"
	stageLbl.Text = stage
	local inStage = (depth - 1) % Config.STAGE_LENGTH + 1
	for i, d in dots do
		if i < inStage then
			d.BackgroundColor3 = C.Kelp
		elseif i == inStage then
			d.BackgroundColor3 = C.Gold
			UI.pop(d, 1.5)
		else
			d.BackgroundColor3 = Color3.fromRGB(60, 70, 95)
		end
	end
end

function Hud.setEnemy(name: string, hp: number, maxHp: number, boss: boolean, bossTime: number?)
	enemyName.Text = (if boss then "BOSS  " else "") .. name
	Hud.setEnemyHp(hp, maxHp)
	bossTimer.Visible = bossTime ~= nil
	if bossTime then
		bossTotal = bossTime
		bossEnds = os.clock() + bossTime
	end
end

function Hud.setEnemyHp(hp: number, maxHp: number)
	enemyHpLbl.Text = Format.abbrev(hp) .. "/" .. Format.abbrev(maxHp)
	UI.tween(enemyFill, 0.15, { Size = UDim2.fromScale(math.clamp(hp / maxHp, 0, 1), 1) })
end

function Hud.setBattle(on: boolean)
	Hud.inBattle = on
	depthBar.Visible = on
	Hud.refresh()
end

---------------------------------------------------------------------------
-- Rotating offer
---------------------------------------------------------------------------
local OFFER_INDEX = 1
local OFFER_ICON = { DoubleCoins = "Coin", FuseLuck = "LuckEgg", FastFuse = "Heart", FastBattle = "Speed", InsaneLuck = "LuckEgg", Luck30 = "LuckEgg", DoubleLuck = "LuckEgg" }
local function currentOffer(): string
	return Config.OFFER_ROTATION[(OFFER_INDEX - 1) % #Config.OFFER_ROTATION + 1]
end

local function offerInfo(name: string): (string, number)
	local pass = Config.GAMEPASSES[name]
	if pass then
		return pass.name, pass.price
	end
	local prod = Config.PRODUCTS[name]
	return prod.name, prod.price
end

local function refreshOffer()
	-- skip passes the player already owns
	for _ = 1, #Config.OFFER_ROTATION do
		local o = currentOffer()
		local info = Config.GAMEPASSES[o] or Config.PRODUCTS[o]
		-- skip passes already owned, and anything not created on Roblox yet (id 0) outside Studio
		if (Config.GAMEPASSES[o] and State.hasPass(o)) or (info and info.id == 0 and not game:GetService("RunService"):IsStudio()) then
			OFFER_INDEX += 1
		else
			break
		end
	end
	local name = currentOffer()
	local title, price = offerInfo(name)
	offerTitle.Text = title
	offerPrice.Text = tostring(price)
	offerIcon.Image = Config.STORE_ICONS[name] or I[OFFER_ICON[name] or "Coin"]
end

function Hud.offerName(): string
	return currentOffer()
end

---------------------------------------------------------------------------
-- Refresh from the snapshot
---------------------------------------------------------------------------
function Hud.refresh()
	local snap = State.snapshot
	if not snap or not root then
		return
	end
	root.Visible = not State.cinematic and not State.revealing
	if shown.coins >= 0 and snap.coins > shown.coins then
		popNumber(coinLbl, snap.coins - shown.coins, C.Gold)
	end
	if shown.pearls >= 0 and snap.pearls > shown.pearls then
		popNumber(pearlLbl, snap.pearls - shown.pearls, C.Pearl)
	end
	if shown.best >= 0 and snap.bestDepth > shown.best and Hud.inBattle and snap.bestDepth % 5 == 0 then
		Hud.splash("NEW BEST: DEPTH " .. snap.bestDepth .. "!", C.Gold)
	end
	shown.best = snap.bestDepth
	shown.coins, shown.pearls = snap.coins, snap.pearls
	-- festival shells: a counter of their own while the Tide Festival runs
	local shells = snap.shells or 0
	local festival = State.now() < Config.EVENT.endsAt
	;(shellLbl.Parent :: GuiObject).Visible = festival
	if festival and shown.shells >= 0 and shells > shown.shells then
		popNumber(shellLbl, shells - shown.shells, Color3.fromRGB(255, 160, 60))
	end
	shown.shells = shells
	shellLbl.Text = Format.abbrev(shells)
	-- coins tick up smoothly towards the real value (the ticker)
	tickTarget = snap.coins
	if tickShown < 0 then
		tickShown = snap.coins
		coinLbl.Text = Format.abbrev(snap.coins)
	end
	pearlLbl.Text = Format.abbrev(snap.pearls)
	local unlocked = snap.tutorial >= Config.HUD_UNLOCK_STEP
	leftCol.Visible = false -- menus live at vendors in the world now
	rightCol.Visible = unlocked
	powersCard.Visible = false -- the Power Shrine vendor in the harbour
	starterBtn.Visible = not snap.starterBought
	local monsters = 0
	for _ in snap.monsters do
		monsters += 1
	end
	-- the heart is replaced by the fuse tray while the tray is open
	fuseBtn.Visible = snap.tutorial >= 10 and not Hud.inBattle and not Hud.fuseOpen
	-- the ring pulses when some level has enough monsters to fuse (Stats.fuseNeeded)
	local byLvl: { [number]: number } = {}
	local canFuse = false
	for _, m in snap.monsters do
		if m.lvl < Config.MAX_LEVEL then
			byLvl[m.lvl] = (byLvl[m.lvl] or 0) + 1
			if byLvl[m.lvl] >= Stats.fuseNeeded(m.lvl) then
				canFuse = true
			end
		end
	end
	local ringHolder = fuseRing.Parent :: GuiObject
	ringHolder.Visible = canFuse
	-- Sell sits beside it once the tutorial is done (the server won't sell before that)
	sellBtn.Visible = snap.tutorial >= Config.TUTORIAL_DONE and monsters > 0 and not Hud.inBattle and not Hud.fuseOpen
	-- toasts ride above the tray so the two never overlap
	if toastHolder then
		toastHolder.Position = UDim2.new(0.5, 0, 1, if Hud.fuseOpen then -176 else -140)
	end
	fightBtn.Visible = not Hud.inBattle and snap.tutorial >= 5 and monsters > 0 and not snap.carrying
	-- "Pick Team" sits beside FIGHT once the tutorial is done (same moments FIGHT shows)
	teamBtn.Visible = fightBtn.Visible and snap.tutorial >= Config.TUTORIAL_DONE
	-- Enough coins for the next team slot? Show a red "!" on Pick Team and say so once per slot.
	local slotPrice = Config.TEAM_SLOT_PRICES[snap.teamSlots - Config.TEAM_START + 1]
	local canBuySlot = snap.tutorial >= Config.TUTORIAL_DONE and snap.teamSlots < Config.TEAM_MAX and slotPrice ~= nil and snap.coins >= slotPrice
	slotBadge.Visible = canBuySlot
	if canBuySlot and slotPromptedFor ~= snap.teamSlots and not Hud.inBattle then
		slotPromptedFor = snap.teamSlots
		Hud.toast("You can afford a new team slot! (" .. Format.abbrev(slotPrice) .. " coins) Open Pick Team to buy it", C.Gold)
	end
	-- team power (the team that will actually fight)
	local power = 0
	local team = 0
	local list = {}
	for uid, m in snap.monsters do
		table.insert(list, { uid = uid, m = m, p = Stats.power(m.sp, m.lvl, m.stars, m.v, m.x6) })
	end
	if #snap.team > 0 then
		for _, uid in snap.team do
			local m = snap.monsters[uid]
			if m and team < snap.teamSlots then
				team += 1
				power += Stats.power(m.sp, m.lvl, m.stars, m.v, m.x6)
			end
		end
	else
		table.sort(list, function(a, b)
			return a.p > b.p
		end)
		for i = 1, math.min(#list, snap.teamSlots) do
			team += 1
			power += list[i].p
		end
	end
	powerLbl.Text = "Team Power: " .. Format.abbrev(power)
	teamCount.Text = team .. "/" .. snap.teamSlots
	speedBtn.Visible = State.hasPass("FastBattle")
	speedLbl.Text = "x" .. (snap.battleSpeed or 1)
	-- hotbar: the egg you carry
	hotbarSlot:ClearAllChildren()
	hotbar.Visible = snap.carrying ~= nil
	if snap.carrying then
		local egg = MonsterModels.buildEgg(snap.carrying.sp, 1)
		local vp = UI.new("ViewportFrame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Ambient = Color3.fromRGB(200, 200, 210), Parent = hotbarSlot })
		egg.Parent = vp
		local cam = Instance.new("Camera")
		cam.FieldOfView = 30
		cam.CFrame = CFrame.lookAt(Vector3.new(0, 1, -5.5), Vector3.new(0, 0.1, 0))
		cam.Parent = vp
		vp.CurrentCamera = cam
	end
	-- badges
	local found = 0
	for _ in snap.index do
		found += 1
	end
	setBadge("Index", found - Hud.indexSeen)
	setBadge("Event", if snap.shells >= 50 and os.time() < Config.EVENT.endsAt then 1 else 0)
	local ready = 0
	local played = State.now() - (snap.sessionStart or State.now())
	for i, g in Config.GIFTS do
		if not (snap.giftsClaimed and snap.giftsClaimed[i]) and played >= g.min * 60 then
			ready += 1
		end
	end
	if snap.dailyDay ~= State.now() // 86400 then
		ready += 1
	end
	setBadge("Gifts", ready)
	-- powers card
	local unlockedPowers = snap.bestDepth >= Config.POWERS_UNLOCK_DEPTH
	local sub = powersCard:FindFirstChild("Sub") :: TextLabel
	sub.Text = if unlockedPowers then (snap.spins > 0 and (snap.spins .. " free spins!") or "Spin for a Power!") else ("Reach Depth " .. Config.POWERS_UNLOCK_DEPTH .. " to unlock")
	sub.TextColor3 = if unlockedPowers then C.Kelp else Color3.fromRGB(255, 110, 110)
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
function Hud.init(screen: ScreenGui)
	root = UI.new("Frame", { Name = "Hud", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = screen })

	-- FIGHT gently pulses while it is waiting to be pressed (grows and shrinks a few percent)
	task.spawn(function()
		local small, big = UDim2.fromOffset(190, 58), UDim2.fromOffset(204, 62)
		local up = true
		while true do
			if fightBtn and fightBtn.Visible and not Hud.inBattle and fightBtn.Parent then
				UI.tween(fightBtn, 0.7, { Size = if up then big else small }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
				up = not up
			end
			task.wait(0.75)
		end
	end)
	-- FIGHT + Team Power
	fightBtn = UI.button({ Text = "FIGHT!", Color = C.Coral, Size = UDim2.fromOffset(190, 58), Position = UDim2.new(0.5, 0, 0, 8), AnchorPoint = Vector2.new(0.5, 0), Visible = false, Parent = root }, function()
		fire("Fight")
	end)
	-- Pick Team: to the right of FIGHT, same height, a different colour so the two read apart
	teamBtn = UI.button({ Text = "Pick Team", Color = C.Sea, Size = UDim2.fromOffset(150, 58), Position = UDim2.new(0.5, 205, 0, 8), AnchorPoint = Vector2.new(0.5, 0), Visible = false, Parent = root }, function()
		fire("Team")
	end)
	slotBadge = UI.new("Frame", { BackgroundColor3 = C.Coral, Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, -6, 0, 2), AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, ZIndex = 5, Parent = teamBtn }, { UI.corner(14), UI.stroke(2.5) })
	UI.label({ Text = "!", Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.1), ZIndex = 6, Parent = slotBadge })
	local pwr = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(240, 30), Position = UDim2.new(0.5, 0, 1, 6), AnchorPoint = Vector2.new(0.5, 0), Parent = fightBtn })
	UI.new("ImageLabel", { BackgroundTransparency = 1, Image = I.Swords, Size = UDim2.fromOffset(30, 30), Parent = pwr })
	powerLbl = UI.label({ Text = "", TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -36, 1, 0), Position = UDim2.fromOffset(36, 0), Parent = pwr })
	buildDepthBar()

	-- banner
	-- a solid rounded sea-blue pill: no dark fade behind the words, so they stay crisp
	banner = UI.panel({ Size = UDim2.fromOffset(600, 50), Position = UDim2.new(0.5, 0, 0, 116), AnchorPoint = Vector2.new(0.5, 0), Color = Color3.fromRGB(40, 140, 235), Radius = 25, Visible = false, Parent = root })
	bannerLbl = UI.label({ Text = "", MaxText = 28, Size = UDim2.new(1, -40, 0.72, 0), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Stroke = 2.5, Parent = banner })

	-- settings gear (placed by Hud.setMode below)
	settingsBtn = UI.button({ Text = "", Color = C.Plank, Radius = 28, Size = UDim2.fromOffset(56, 56), Position = UDim2.new(1, -14, 1, -14), AnchorPoint = Vector2.new(1, 1), Parent = root }, function()
		fire("Settings")
	end)
	UI.new("ImageLabel", { BackgroundTransparency = 1, Image = "rbxasset://textures/ui/Settings/MenuBarIcons/GameSettingsTab.png", ImageColor3 = C.Panel, ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromScale(0.62, 0.62), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 2, Parent = settingsBtn })

	-- currencies (pearls above coins, coins bigger)
	pearlLbl = currency(-118, I.Pearl, 44, "InfoPearls")
	coinLbl = currency(-68, I.Coin, 56, "InfoCoins")
	shellLbl = currency(-162, I.Shell, 40, "InfoShells")
	shellLbl.TextColor3 = Color3.fromRGB(255, 200, 150)
	-- Platform tells us the input mode ("key" | "touch" | "pad"). Phones: the currencies go up
	-- top-left (the thumbstick lives bottom-left) and the Robux offers sit just under the spell
	-- row, clear of the jump button at the bottom right.
	function Hud.setMode(m: string)
		local touch = m == "touch"
		local pf, cf = pearlLbl.Parent :: Frame, coinLbl.Parent :: Frame
		local sf = shellLbl.Parent :: Frame
		if touch then
			-- the HUD runs to the top edge on phones; only the top-left (Roblox's own menu and
			-- chat buttons) is left clear. Coins and pearls sit side by side under those buttons,
			-- the missions below them, and nothing reaches the thumbstick (bottom-left).
			local off = Platform.topInset()
			cf.Size = UDim2.fromOffset(206, 56)
			pf.Size = UDim2.fromOffset(150, 44)
			cf.Position = UDim2.new(0, 14, 0, off + 2)
			pf.Position = UDim2.new(0, 14 + 210, 0, off + 8)
			sf.Size = UDim2.fromOffset(140, 40)
			sf.Position = UDim2.new(0, 14 + 210 + 154, 0, off + 10)
			-- the Starter Pack and the offer stay in a column down the right edge (the jump button
			-- is small and sits lower), starting under the top-right row
			-- the gear sits at the top of that column (the jump button owns the bottom right),
			-- so the column starts one gear lower
			settingsBtn.AnchorPoint = Vector2.new(1, 0)
			settingsBtn.Position = UDim2.new(1, -14, 0, 70)
			rightCol.AnchorPoint = Vector2.new(1, 0)
			rightCol.Position = UDim2.new(1, -10, 0, 134)
			rightCol.Size = UDim2.fromOffset(140, 300)
			rightLayout.FillDirection = Enum.FillDirection.Vertical
		else
			-- PC / console: the gear in the empty bottom-right corner
			settingsBtn.AnchorPoint = Vector2.new(1, 1)
			settingsBtn.Position = UDim2.new(1, -14, 1, -14)
			cf.Size = UDim2.fromOffset(260, 56)
			pf.Size = UDim2.fromOffset(260, 44)
			rightCol.Size = UDim2.fromOffset(140, 300)
			rightLayout.FillDirection = Enum.FillDirection.Vertical
			pf.Position = UDim2.new(0, 14, 1, -118)
			cf.Position = UDim2.new(0, 14, 1, -68)
			sf.Size = UDim2.fromOffset(260, 40)
			sf.Position = UDim2.new(0, 14, 1, -162)
			rightCol.AnchorPoint = Vector2.new(1, 0.5)
			rightCol.Position = UDim2.new(1, -10, 0.5, -30)
		end
	end

	-- left column
	leftCol = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(100, 400), Position = UDim2.new(0, 12, 0, 70), Visible = false, Parent = root })
	UI.new("UIListLayout", { Padding = UDim.new(0, 18), HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = leftCol })
	iconButton(leftCol, I.Shop, "Shop", 60, function()
		fire("Shop")
	end)
	badge(iconButton(leftCol, I.Event, "Event", 60, function()
		fire("Event")
	end), "Event")
	badge(iconButton(leftCol, I.Index, "Index", 60, function()
		fire("Index")
	end), "Index")
	local teamBtn = iconButton(leftCol, I.Team, "Team", 60, function()
		fire("Team")
	end)
	teamCount = UI.label({ Text = "0/3", TextColor3 = C.Gold, Size = UDim2.fromOffset(40, 20), Position = UDim2.new(1, -20, 0, -6), ZIndex = 4, Parent = teamBtn })
	local giftBtn = iconButton(leftCol, I.Gift, "Gifts", 60, function()
		fire("Gifts")
	end)
	badge(giftBtn, "Gifts")
	giftLbl = teamCount -- (kept for refresh symmetry)

	-- right column: Starter Pack (creature art) + rotating offer
	rightCol = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(140, 300), Position = UDim2.new(1, -10, 0.5, -30), AnchorPoint = Vector2.new(1, 0.5), Visible = false, Parent = root })
	rightLayout = UI.new("UIListLayout", { Padding = UDim.new(0, 18), HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Top, Parent = rightCol })
	local sb = UI.new("ImageButton", { BackgroundTransparency = 1, Image = "", Size = UDim2.fromOffset(130, 120), Parent = rightCol })
	creatureArt(sb, { "Kelpdrake", "Splashfin" }, UDim2.new(1, 0, 0, 92))
	priceChip(sb, Config.PRODUCTS.StarterPack.price, -12)
	UI.label({ Text = "Starter\nPack", Size = UDim2.new(1, 0, 0, 44), Position = UDim2.new(0, 0, 1, -40), ZIndex = 4, Parent = sb })
	sb.Activated:Connect(function()
		fire("Starter")
	end)
	starterBtn = sb
	offerBtn = UI.new("ImageButton", { BackgroundTransparency = 1, Image = "", Size = UDim2.fromOffset(130, 120), Parent = rightCol })
	offerIcon = UI.new("ImageLabel", { BackgroundTransparency = 1, Image = I.Coin, Size = UDim2.fromOffset(80, 80), Position = UDim2.new(0.5, 0, 0, 12), AnchorPoint = Vector2.new(0.5, 0), Parent = offerBtn })
	offerPrice = priceChip(offerBtn, 0, -12)
	offerTitle = UI.label({ Text = "", Size = UDim2.new(1.2, 0, 0, 40), Position = UDim2.new(0.5, 0, 1, -36), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 4, Parent = offerBtn })
	offerBtn.Activated:Connect(function()
		fire("Offer")
	end)
	refreshOffer()
	task.spawn(function()
		while true do
			task.wait(0.5)
			Hud.tickRest()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Config.OFFER_ROTATE)
			OFFER_INDEX += 1
			refreshOffer()
			UI.pop(offerBtn, 0.8)
		end
	end)

	-- active spells: a row of small icons with timers at the top right
	spellRow = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(360, 56), Position = UDim2.new(1, -12, 0, 8), AnchorPoint = Vector2.new(1, 0), Parent = root })
	UI.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 6), Parent = spellRow })
	task.spawn(function()
		while true do
			local snap = State.snapshot
			for _, ch in spellRow:GetChildren() do
				if ch:IsA("GuiObject") then
					ch:Destroy()
				end
			end
			local friends = tonumber(player:GetAttribute("Friends")) or 0
			if friends > 0 then
				local chip = UI.new("Frame", { BackgroundColor3 = Color3.fromRGB(20, 30, 60), BackgroundTransparency = 0.2, Size = UDim2.fromOffset(52, 56) }, { UI.corner(10), UI.stroke(2.5, C.Kelp) })
				UI.new("ImageLabel", { BackgroundTransparency = 1, Image = I.Team, Size = UDim2.fromOffset(34, 34), Position = UDim2.new(0.5, 0, 0, 2), AnchorPoint = Vector2.new(0.5, 0), Parent = chip })
				UI.label({ Text = "+" .. math.floor(friends * Config.FRIEND_BOOST * 100) .. "%", TextColor3 = C.Kelp, MaxText = 14, Size = UDim2.new(1, -4, 0, 16), Position = UDim2.fromOffset(2, 37), Parent = chip })
				chip.LayoutOrder = -2
				chip.Parent = spellRow
			end
			-- bought luck boosts (Fuse Luck / Insane Fuse Luck, x2 Luck 30m): icon, "x2" and a countdown,
			-- with a gold edge so they read as the Robux boosts they are
			local function boostChip(icon: string, mult: number, left: number)
				local chip = UI.new("Frame", { BackgroundColor3 = Color3.fromRGB(20, 30, 60), BackgroundTransparency = 0.2, Size = UDim2.fromOffset(52, 56), LayoutOrder = -1 }, { UI.corner(10), UI.stroke(2.5, C.Gold) })
				UI.new("ImageLabel", { BackgroundTransparency = 1, Image = icon, Size = UDim2.fromOffset(34, 34), Position = UDim2.new(0.5, 0, 0, 2), AnchorPoint = Vector2.new(0.5, 0), Parent = chip })
				UI.label({ Text = "x" .. mult, TextColor3 = C.Gold, MaxText = 14, Size = UDim2.fromOffset(26, 16), Position = UDim2.new(1, -2, 0, 0), AnchorPoint = Vector2.new(1, 0), ZIndex = 2, Parent = chip })
				UI.label({ Text = Format.time(left), MaxText = 14, Size = UDim2.new(1, -4, 0, 16), Position = UDim2.fromOffset(2, 37), Parent = chip })
				chip.Parent = spellRow
			end
			if snap then
				local now = State.now()
				local fuseLeft = (snap.luckUntil or 0) - now
				if fuseLeft > 0 then
					local m = snap.luckMult or 2
					boostChip(if m >= Config.INSANE_LUCK_MULT then Config.STORE_ICONS.InsaneLuck else Config.STORE_ICONS.FuseLuck, m, fuseLeft)
				end
				local luck30Left = (snap.luck30Until or 0) - now
				if luck30Left > 0 then
					boostChip(Config.STORE_ICONS.Luck30, 2, luck30Left)
				end
			end
			if snap and snap.spellUntil then
				for _, sp in Config.SPELLS do
					local left = (snap.spellUntil[sp.id] or 0) - State.now()
					if left > 0 then
						-- a little wooden tag with a brass edge and a bar in the spell's rarity colour
						local chip = UI.new("Frame", { BackgroundColor3 = C.Plank, Size = UDim2.fromOffset(52, 56) }, { UI.corner(10), UI.stroke(3, C.Ink) })
						UI.new("Frame", { BackgroundColor3 = Config.RARITY[sp.rarity].color, BorderSizePixel = 0, Size = UDim2.new(1, -16, 0, 4), Position = UDim2.new(0.5, 0, 0, 3), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 3, Parent = chip }, { UI.corner(2) })
						UI.new("ImageLabel", { BackgroundTransparency = 1, Image = I[sp.icon], Size = UDim2.fromOffset(34, 34), Position = UDim2.new(0.5, 0, 0, 2), AnchorPoint = Vector2.new(0.5, 0), Parent = chip })
						UI.label({ Text = Format.time(left), MaxText = 14, Size = UDim2.new(1, -4, 0, 16), Position = UDim2.fromOffset(2, 37), Parent = chip })
						chip.Parent = spellRow
					end
				end
			end
			task.wait(1)
		end
	end)

	-- Powers card (bottom left, above the currencies)
	powersCard = UI.new("TextButton", { Text = "", BackgroundColor3 = Color3.fromRGB(10, 20, 40), BackgroundTransparency = 0.3, Size = UDim2.fromOffset(250, 62), Position = UDim2.new(0, 10, 1, -194), Visible = false, Parent = root }, { UI.corner(12), UI.stroke(2.5) })
	UI.new("ImageLabel", { BackgroundTransparency = 1, Image = I.Power, Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(4, 3), Parent = powersCard })
	UI.label({ Text = "Tide Powers", TextColor3 = C.Gold, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -70, 0, 28), Position = UDim2.fromOffset(64, 4), Parent = powersCard })
	UI.label({ Name = "Sub", Text = "", TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -70, 0, 22), Position = UDim2.fromOffset(64, 34), Parent = powersCard })
	powersCard.Activated:Connect(function()
		fire("Powers")
	end)

	-- big heart Fuse button + hotbar slot under it
	fuseBtn = iconButton(root, I.Heart, "", 116, function()
		fire("Fuse")
	end)
	fuseBtn.Position = UDim2.new(0.5, 0, 1, -14)
	fuseBtn.AnchorPoint = Vector2.new(0.5, 1)
	fuseBtn.Visible = false
	local fl = fuseBtn:FindFirstChild("Label") :: TextLabel
	fl.Text = "Fuse!"
	fl.TextColor3 = C.Gold
	fl.Size = UDim2.new(1.2, 0, 0, 34)
	fl.Position = UDim2.new(0.5, 0, 0.55, 0)
	-- Sell button left of the heart: opens the team screen in Sell mode (tap a monster twice to sell it)
	-- on the LEFT edge, just under the middle (below the Missions board, clear of the bottom-left
	-- thumbstick on phones), not in the centre with Fuse
	sellBtn = iconButton(root, I.Coin, "", 84, function()
		fire("Sell")
	end)
	sellBtn.Position = UDim2.new(0, 66, 0.5, 30)
	sellBtn.AnchorPoint = Vector2.new(0.5, 0)
	sellBtn.Visible = false
	local sl = sellBtn:FindFirstChild("Label") :: TextLabel
	-- a round ring around the heart; its line fades in and out (the heart itself doesn't move)
	local ring = UI.new("Frame", { Name = "FuseRing", BackgroundTransparency = 1, Size = UDim2.new(1, 8, 1, 8), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, ZIndex = 0, Parent = fuseBtn }, { UI.corner(999) })
	fuseRing = UI.new("UIStroke", { Thickness = 5, Color = Color3.fromRGB(255, 150, 210), ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = ring })
	task.spawn(function()
		while fuseRing.Parent do
			if ring.Visible then
				UI.tween(fuseRing, 0.6, { Transparency = 0.85 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut).Completed:Wait()
				UI.tween(fuseRing, 0.6, { Transparency = 0 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut).Completed:Wait()
			else
				fuseRing.Transparency = 0
				task.wait(0.5)
			end
		end
	end)
	sl.Text = "Sell!"
	sl.TextColor3 = C.Gold
	sl.Size = UDim2.new(1.2, 0, 0, 30)
	sl.Position = UDim2.new(0.5, 0, 0.62, 0)
	hotbar = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(70, 70), Position = UDim2.new(0.5, 90, 1, -16), AnchorPoint = Vector2.new(0, 1), Visible = false, Parent = root })
	hotbarSlot = UI.new("Frame", { BackgroundColor3 = Color3.fromRGB(20, 40, 80), BackgroundTransparency = 0.25, Size = UDim2.fromScale(1, 1), Parent = hotbar }, { UI.corner(10), UI.stroke(3, Color3.fromRGB(80, 200, 255)) })
	UI.label({ Text = "1", Size = UDim2.fromOffset(16, 16), Position = UDim2.fromOffset(4, 2), ZIndex = 3, Parent = hotbar })

	-- toasts
	-- on the screen itself (not the HUD frame) with a huge ZIndex so a message is never hidden
	-- behind a menu, e.g. the "not enough pearls" error over the Egg Shop
	toastHolder = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(480, 200), Position = UDim2.new(0.5, 0, 1, -140), AnchorPoint = Vector2.new(0.5, 1), ZIndex = 1000, Parent = screen })
	UI.new("UIListLayout", { Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = toastHolder })

	State.Changed:Connect(Hud.refresh)
	screenRoot = screen
	local lastBadge = 0
	RunService.Heartbeat:Connect(function(dt)
		-- coin ticker: ease the shown number towards the real one
		if tickShown >= 0 and tickShown ~= tickTarget then
			local diff = tickTarget - tickShown
			local stepv = diff * math.min(1, dt * 6)
			if math.abs(stepv) < 1 then
				stepv = diff
			end
			tickShown += stepv
			coinLbl.Text = Format.abbrev(math.floor(tickShown + 0.5))
		end
		if bossTimer.Visible and bossTotal > 0 then
			local left = math.max(0, bossEnds - os.clock())
			bossFill.Size = UDim2.fromScale(left / bossTotal, 1)
		end
		-- gift badges tick over with time
		if os.clock() - lastBadge > 5 then
			lastBadge = os.clock()
			Hud.refresh()
		end
	end)
	local _ = player
	local _g = giftLbl
end

function Hud.fuseButton(): GuiObject
	return fuseBtn
end

function Hud.teamButton(): GuiObject
	return teamBtn
end

function Hud.sellButton(): GuiObject
	return sellBtn
end

function Hud.fightButton(): GuiObject
	return fightBtn
end

-- After a defeat the fainted monsters rest: the FIGHT button counts down until one is ready
function Hud.tickRest()
	local snap = State.snapshot
	if not snap or not fightBtn then
		return
	end
	local left = math.ceil((snap.fightReadyAt or 0) - State.now())
	local resting = left > 0 and not Hud.inBattle
	UI.setText(fightBtn, if resting then ("Resting " .. left .. "s") else "FIGHT!")
	fightBtn.AutoButtonColor = false
	local grad = fightBtn:FindFirstChildOfClass("UIGradient")
	if grad then
		grad.Enabled = not resting
	end
	fightBtn.BackgroundColor3 = if resting then C.Muted else Color3.new(1, 1, 1)
end

return Hud
