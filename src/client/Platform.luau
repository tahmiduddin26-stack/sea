--!strict
-- One layout for PC, phones and consoles (the same approach as Survive the Snow).
--   Scale     the whole UI is drawn in "design units" and one UIScale turns them into pixels,
--             worked out from the screen's real safe area (after the notch and Roblox's top
--             bar): PC / console fit a 1280 x 720 design (a TV goes up to 1.35x); touch fits
--             1180 x 540, so every phone layout has to fit in 540 units of height.
--   Mode      "key" | "touch" | "pad", decided by the device (touch screen without a mouse, or
--             a small touch screen) and, on a controller, by the last input used.
--   Gamepad   the few HUD buttons with a pad button (FIGHT, Fuse) wear a sticker of it
--             (PadStickers). Roblox's free cursor reaches everything else: the View / touchpad
--             button turns it on and off, and opening a menu turns it on by itself.
--             B closes the open menu. A one-time "Your Controller" card shows the map.
--   Preview   Player attribute PreviewDevice = "phone" (Studio): touch layout at a phone's
--             height (Roblox draws its own thumbstick and jump button.)

local ContextActionService = game:GetService("ContextActionService")
local GamepadService = game:GetService("GamepadService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent.UI)
local PadStickers = require(script.Parent.PadStickers)

local Platform = {}

local C = UI.Colors

local mode = "key" -- "key" | "touch" | "pad"
local screen: ScreenGui? = nil
local rootScale: UIScale? = nil
local TOUCH_W, TOUCH_H = 1180, 540

-- views that lay themselves out per input mode register here (Hud)
Platform.onMode = nil :: ((string) -> ())?
-- true while one of our pop-up menus is open (Menus tells us)
local menuIsOpen = false

local function preview(): boolean
	return Players.LocalPlayer:GetAttribute("PreviewDevice") == "phone"
end

-- A phone or tablet layout is decided by the device, not by the last key pressed (Studio's
-- phone emulator has a keyboard too; flipping layouts on every WASD press made the whole
-- UI jump in size)
local function isTouchOnly(): boolean
	if not UserInputService.TouchEnabled then
		return false
	end
	local vp = if workspace.CurrentCamera then workspace.CurrentCamera.ViewportSize else Vector2.new(1280, 720)
	return not UserInputService.KeyboardEnabled or not UserInputService.MouseEnabled or math.min(vp.X, vp.Y) < 600
end

local function startMode(): string
	if preview() or isTouchOnly() then
		return "touch"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "pad"
	end
	return "key"
end

---------------------------------------------------------------------------
-- Scale
---------------------------------------------------------------------------
local function rescale()
	local rs, sc = rootScale, screen
	if not rs or not sc then
		return
	end
	local size = sc.AbsoluteSize
	if size.X < 2 or size.Y < 2 then
		return
	end
	local s
	if preview() then
		s = size.Y / TOUCH_H
	elseif mode == "touch" then
		s = math.min(size.X / TOUCH_W, size.Y / TOUCH_H)
	else
		s = math.min(size.X / 1280, size.Y / 720)
	end
	rs.Scale = math.clamp(s, 0.4, 1.35)
end

-- The UI's size in design units right now (menus shrink to fit it)
function Platform.designSize(): Vector2
	local sc = screen
	local rs = rootScale
	if not sc or not rs or rs.Scale <= 0 then
		return Vector2.new(1280, 720)
	end
	return sc.AbsoluteSize / rs.Scale
end

-- A pop-up of `size` design units: the scale (<= 1) that makes it fit the screen
function Platform.fit(size: Vector2): number
	local d = Platform.designSize()
	return math.clamp(math.min((d.X - 24) / size.X, (d.Y - 24) / size.Y, 1), 0.5, 1)
end

function Platform.mode(): string
	return mode
end

-- "Press E" on PC, "Press X" on a controller, "Tap" on a phone
function Platform.press(): string
	return if mode == "touch" then "Tap" elseif mode == "pad" then "Press X" else "Press E"
end

---------------------------------------------------------------------------
-- The free cursor: View / touchpad toggles Roblox's own gamepad cursor, and a menu opening
-- on a controller turns it on by itself
---------------------------------------------------------------------------
local function setCursor(on: boolean)
	pcall(function()
		if on and not GamepadService.GamepadCursorEnabled then
			GamepadService:EnableGamepadCursor(nil)
		elseif not on and GamepadService.GamepadCursorEnabled then
			GamepadService:DisableGamepadCursor()
		end
	end)
end

local cursorHint: Frame? = nil
local guideCard: GuiObject? = nil

-- Menus.luau calls this when its pop-up opens / closes
function Platform.menuChanged(open: boolean)
	menuIsOpen = open
	if mode ~= "pad" then
		return
	end
	if open then
		setCursor(true)
	else
		task.defer(function()
			if not menuIsOpen and not guideCard then
				setCursor(false)
			end
		end)
	end
end

---------------------------------------------------------------------------
-- Stickers
---------------------------------------------------------------------------
local function refreshStickers()
	PadStickers.setOn(mode == "pad")
	if cursorHint then
		cursorHint.Visible = mode == "pad"
	end
end

local function setMode(new: string)
	if preview() then
		new = "touch"
	end
	if new == mode then
		return
	end
	mode = new
	rescale()
	if Platform.onMode then
		Platform.onMode(mode)
	end
	if mode ~= "pad" then
		GuiService.SelectedObject = nil
		setCursor(false)
	end
	refreshStickers()
	if mode == "pad" then
		Platform.showGuide()
	end
end

---------------------------------------------------------------------------
-- "Your Controller": the whole map, once per session, the first time a pad is used
---------------------------------------------------------------------------
local PAD_MAP = {
	{ Enum.KeyCode.ButtonX, "Interact / Fight" },
	{ Enum.KeyCode.ButtonY, "How to Fuse" },
	{ Enum.KeyCode.ButtonL1, "Robux Shop" },
	{ Enum.KeyCode.ButtonA, "Jump / Click" },
	{ Enum.KeyCode.ButtonB, "Close a menu" },
	{ Enum.KeyCode.ButtonSelect, "Cursor on / off" },
}
local guideShown = false

function Platform.showGuide()
	local sc = screen
	if guideShown or not sc or mode ~= "pad" then
		return
	end
	guideShown = true
	task.spawn(function()
		-- wait for the intro / reveals to finish (State.cinematic / revealing)
		local State = require(script.Parent.State) :: any
		local t0 = os.clock()
		while (State.cinematic or State.revealing or not State.snapshot) and os.clock() - t0 < 120 do
			task.wait(1)
		end
		if mode ~= "pad" then
			guideShown = false
			return
		end
		local card = UI.panel({ Name = "PadGuide", Size = UDim2.fromOffset(460, 470), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 50, Parent = sc })
		guideCard = card
		local fit = Platform.fit(Vector2.new(460, 470))
		UI.pop(card, 0.7 * fit, fit)
		UI.label({ Text = "Your Controller", MaxText = 38, Size = UDim2.new(1, -40, 0, 46), Position = UDim2.fromOffset(20, 14), TextColor3 = C.Gold, ZIndex = 51, Parent = card })
		UI.label({ Text = "Left stick moves, right stick looks", Stroke = 0, TextColor3 = C.Ink, MaxText = 22, Size = UDim2.new(1, -40, 0, 26), Position = UDim2.fromOffset(20, 60), ZIndex = 51, Parent = card })
		for i, row in PAD_MAP do
			local y = 96 + (i - 1) * 50
			local holder = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(24, y), ZIndex = 51, Parent = card })
			PadStickers.attach(holder, row[1], { always = true, size = 44, position = UDim2.fromOffset(23, 23) })
			UI.label({ Text = row[2], Stroke = 0, TextColor3 = C.Ink, MaxText = 26, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -100, 0, 40), Position = UDim2.fromOffset(84, y + 3), ZIndex = 51, Parent = card })
		end
		local btn = UI.button({ Text = "Got it!", Color = C.Kelp, Size = UDim2.new(1, -48, 0, 52), Position = UDim2.new(0, 24, 1, -66), ZIndex = 51, Parent = card }, function()
			guideCard = nil
			card:Destroy()
			if not menuIsOpen then
				setCursor(false)
			end
		end)
		local _ = btn
		setCursor(true) -- the card has a button: the free cursor clicks it
	end)
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------
-- init.client: called before the views are built so they draw at the right size from the start
function Platform.bindScale(root: ScreenGui, scale: UIScale)
	screen = root
	rootScale = scale
	mode = startMode()
	rescale()
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
end

-- init.client: after the HUD exists
function Platform.init()
	local sc = screen
	if not sc then
		return
	end
	-- the View / touchpad button is the cursor toggle, not Roblox's "select a button"
	GuiService.AutoSelectGuiEnabled = false
	ContextActionService:BindActionAtPriority("TideCursor", function(_, state)
		if state == Enum.UserInputState.Begin then
			setCursor(not GamepadService.GamepadCursorEnabled)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonSelect)

	-- a reminder at the left edge while a controller is in use
	local hudRoot = sc:FindFirstChild("Hud") :: GuiObject?
	local hint = UI.new("Frame", { Name = "CursorHint", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 18, 0.5, 0), Size = UDim2.fromOffset(130, 44), BackgroundTransparency = 1, Visible = mode == "pad", Parent = hudRoot or sc }) :: Frame
	PadStickers.attach(hint, Enum.KeyCode.ButtonSelect, { always = true, size = 40, position = UDim2.fromOffset(22, 22) })
	UI.label({ AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 48, 0.5, 0), Size = UDim2.fromOffset(80, 24), Text = "CURSOR", TextXAlignment = Enum.TextXAlignment.Left, Parent = hint })
	cursorHint = hint

	-- only a controller changes the layout (to "pad"); anything else goes back to the
	-- device's own layout
	UserInputService.LastInputTypeChanged:Connect(function(t)
		if string.find(t.Name, "Gamepad") then
			setMode("pad")
		elseif t == Enum.UserInputType.Touch or t == Enum.UserInputType.Keyboard or t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.MouseMovement then
			setMode(if isTouchOnly() then "touch" else "key")
		end
	end)
	Players.LocalPlayer:GetAttributeChangedSignal("PreviewDevice"):Connect(function()
		local m = mode
		mode = ""
		setMode(startMode())
		if mode == m and Platform.onMode then
			Platform.onMode(mode)
		end
		rescale()
	end)
	if Platform.onMode then
		Platform.onMode(mode)
	end
	refreshStickers()
	if mode == "pad" then
		Platform.showGuide()
	end
end

return Platform
