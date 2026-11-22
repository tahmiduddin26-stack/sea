--!strict
-- Controller button stickers (same idea as Survive the Snow). With a controller in hand,
-- the few HUD buttons that have a pad button wear a little round sticker on their corner
-- showing THAT button, drawn with Roblox's own controller pictures
-- (UserInputService:GetImageForKeyCode), so an Xbox pad shows Xbox buttons and a PlayStation
-- pad shows PlayStation ones. PC and phones never see them. Platform.luau switches them on
-- and off with the input in use.
--   keep    one of the few kept while a controller is in use (FIGHT, Fuse)
--   always  shown whatever the input (the controls card's own stickers, the CURSOR hint)

local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent.UI)

local PadStickers = {}

local STICKER = Color3.fromRGB(32, 34, 46) -- the sticker's face (near-black, a little blue)

-- when there's no picture for a button (or no pad plugged in yet), its name in text
local FALLBACK: { [string]: string } = {
	ButtonA = "A", ButtonB = "B", ButtonX = "X", ButtonY = "Y",
	ButtonL1 = "LB", ButtonR1 = "RB", ButtonL2 = "LT", ButtonR2 = "RT",
	ButtonL3 = "L3", ButtonR3 = "R3",
	DPadUp = "Up", DPadDown = "Down", DPadLeft = "Left", DPadRight = "Right",
	ButtonSelect = "View",
}

type Sticker = { frame: Frame, key: Enum.KeyCode, img: ImageLabel, txt: TextLabel }
local stickers: { [Frame]: Sticker } = {}
local on = false

local function paint(s: Sticker)
	local ok, img = pcall(function()
		return UserInputService:GetImageForKeyCode(s.key)
	end)
	if ok and typeof(img) == "string" and img ~= "" then
		s.img.Image = img
		s.img.Visible = true
		s.txt.Visible = false
	else
		s.img.Visible = false
		s.txt.Visible = true
		s.txt.Text = FALLBACK[s.key.Name] or s.key.Name
	end
end

export type Opts = {
	size: number?, -- sticker size in design units (default 34)
	position: UDim2?, -- where its centre sits on the button (default the top-left corner)
	always: boolean?,
	keep: boolean?,
}

local function shown(f: Frame): boolean
	return (on and f:GetAttribute("Keep") == true) or f:GetAttribute("Always") == true
end

-- Put the sticker for `key` on `gui` (replaces one already there). Returns it.
function PadStickers.attach(gui: GuiObject, key: Enum.KeyCode, opts: Opts?): Frame
	local o: Opts = opts or {}
	local old = gui:FindFirstChild("PadSticker")
	if old then
		stickers[old :: Frame] = nil
		old:Destroy()
	end
	local size = o.size or 34
	local frame = UI.new("Frame", {
		Name = "PadSticker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		-- on the button's top-left corner, mostly off it: a sticker slapped on the edge
		Position = o.position or UDim2.fromOffset(2, 2),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = STICKER,
		Rotation = -12,
		ZIndex = gui.ZIndex + 10,
		Visible = false,
		Parent = gui,
	}, { UI.corner(size), UI.stroke(2.5, Color3.new(1, 1, 1)) }) :: Frame
	local img = UI.new("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.9),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = frame.ZIndex + 1,
		Parent = frame,
	}) :: ImageLabel
	local txt = UI.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.72, 0.72),
		Text = "",
		Stroke = 0,
		ZIndex = frame.ZIndex + 1,
		Parent = frame,
	})
	if o.always then
		frame:SetAttribute("Always", true)
	end
	if o.keep then
		frame:SetAttribute("Keep", true)
	end
	frame.Visible = shown(frame)
	local s: Sticker = { frame = frame, key = key, img = img, txt = txt }
	stickers[frame] = s
	frame.Destroying:Connect(function()
		stickers[frame] = nil
	end)
	paint(s)
	return frame
end

-- The picture for a button (the controls card uses this for its rows)
function PadStickers.image(key: Enum.KeyCode): string
	local ok, img = pcall(function()
		return UserInputService:GetImageForKeyCode(key)
	end)
	return if ok and typeof(img) == "string" then img else ""
end

function PadStickers.fallback(key: Enum.KeyCode): string
	return FALLBACK[key.Name] or key.Name
end

-- Platform: a controller is (or isn't) the input in use now
function PadStickers.setOn(isPad: boolean)
	on = isPad
	for f, s in stickers do
		f.Visible = shown(f)
		if on then
			paint(s) -- the pad may have changed (Xbox <-> PlayStation)
		end
	end
end

function PadStickers.isOn(): boolean
	return on
end

UserInputService.GamepadConnected:Connect(function()
	for _, s in stickers do
		paint(s)
	end
end)

return PadStickers
