--!strict
-- Tide Tamers UI kit: "Ship's Deck". Everything looks built from a pirate ship: dark timber
-- outlines, plank frames with brass rivets, parchment bodies, a hanging title sign, round
-- porthole close buttons. White text with a timber stroke, one bright colour per job, springy
-- buttons. Few elements, big targets, one word per button.
--   Sea   = primary actions (Fight, Buy)       Coral = danger / close / boss
--   Gold  = coins, rewards, the tutorial key word   Pearl = pearls / premium
--   Kelp  = success / fuse / go
--   Plank / Parchment / Brass = the ship itself (frames, bodies, rivets)

local TweenService = game:GetService("TweenService")

local UI = {}

UI.Colors = {
	Ink = Color3.fromRGB(46, 28, 18), -- dark timber: every outline and text stroke
	White = Color3.fromRGB(255, 255, 255),
	Panel = Color3.fromRGB(247, 236, 208), -- parchment
	Plank = Color3.fromRGB(150, 98, 56),
	PlankDark = Color3.fromRGB(104, 66, 38),
	Brass = Color3.fromRGB(232, 184, 70),
	Rope = Color3.fromRGB(214, 184, 120),
	Sea = Color3.fromRGB(30, 150, 255),
	Deep = Color3.fromRGB(20, 60, 130),
	Coral = Color3.fromRGB(255, 80, 90),
	Gold = Color3.fromRGB(255, 205, 50),
	Pearl = Color3.fromRGB(200, 150, 255),
	Kelp = Color3.fromRGB(70, 210, 110),
	Muted = Color3.fromRGB(150, 165, 190),
}
local C = UI.Colors

UI.Font = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Regular)
UI.FontBold = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)

function UI.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	if props then
		for k, v in props do
			if k ~= "Parent" then
				(inst :: any)[k] = v
			end
		end
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

function UI.corner(r: number?): UICorner
	return UI.new("UICorner", { CornerRadius = UDim.new(0, r or 14) })
end

function UI.stroke(t: number?, color: Color3?): UIStroke
	return UI.new("UIStroke", { Thickness = t or 3.5, Color = color or C.Ink, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, LineJoinMode = Enum.LineJoinMode.Round })
end

function UI.gradient(face: Color3): UIGradient
	return UI.new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, face:Lerp(Color3.new(1, 1, 1), 0.25)),
			ColorSequenceKeypoint.new(1, face:Lerp(Color3.new(0, 0, 0), 0.12)),
		}),
	})
end

-- Text never grows past MaxText px (default 30), so labels stay tidy on big screens and
-- world tags don't balloon when you stand next to them.
function UI.label(props: { [string]: any }): TextLabel
	local stroke = props.Stroke
	local maxText = props.MaxText or 30
	props.Stroke = nil
	props.MaxText = nil
	local l = UI.new("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = UI.Font,
		TextColor3 = C.White,
		TextScaled = true,
		RichText = true,
		Text = "",
	})
	for k, v in props do
		if k ~= "Parent" then
			(l :: any)[k] = v
		end
	end
	if stroke ~= 0 then
		UI.new("UIStroke", { Thickness = stroke or 2.5, Color = C.Ink, LineJoinMode = Enum.LineJoinMode.Round, Parent = l })
	end
	UI.new("UITextSizeConstraint", { MaxTextSize = maxText, MinTextSize = 8, Parent = l })
	l.Parent = props.Parent
	return l
end

function UI.panel(props: { [string]: any }): Frame
	local color = props.Color or C.Panel
	props.Color = nil
	local f = UI.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, { UI.corner(props.Radius or 20), UI.stroke(4), UI.gradient(color) })
	props.Radius = nil
	for k, v in props do
		if k ~= "Parent" then
			(f :: any)[k] = v
		end
	end
	f.Parent = props.Parent
	return f
end

-- A brass rivet (round, with a dark rim)
function UI.rivet(parent: GuiObject, pos: UDim2, size: number?)
	local s = size or 11
	return UI.new("Frame", {
		BackgroundColor3 = C.Brass,
		Size = UDim2.fromOffset(s, s),
		Position = pos,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = parent,
	}, { UI.corner(s), UI.stroke(2) })
end

-- A strip of timber (section bar, tab, ribbon). Text is optional.
function UI.plank(props: { [string]: any }): Frame
	local text = props.Text
	local f = UI.panel({ Color = props.Color or C.Plank, Radius = props.Radius or 10, Size = props.Size, Position = props.Position, AnchorPoint = props.AnchorPoint, ZIndex = props.ZIndex or 1, Parent = props.Parent })
	if text then
		UI.label({ Text = text, Size = UDim2.new(1, -16, 0.72, 0), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), TextColor3 = props.TextColor or C.Panel, MaxText = props.MaxText or 24, Parent = f })
	end
	return f
end

-- The ship-themed pop-up window every menu uses: a plank frame with brass rivets, a hanging
-- title sign (tinted with `Accent`), a parchment body, and a round porthole close button.
-- Returns (frame, body). The body is the parchment area: put the content in it.
function UI.window(props: { [string]: any }, onClose: (() -> ())?): (Frame, Frame)
	local accent = props.Accent or C.Sea
	local f = UI.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		ZIndex = props.ZIndex or 1,
	}, { UI.corner(22), UI.stroke(5), UI.gradient(C.Plank) })
	-- plank seams across the frame
	for _, y in { 0.34, 0.68 } do
		UI.new("Frame", { BackgroundColor3 = C.Ink, BackgroundTransparency = 0.82, BorderSizePixel = 0, Size = UDim2.new(1, -24, 0, 2), Position = UDim2.new(0, 12, y, 0), Parent = f })
	end
	UI.rivet(f, UDim2.new(0, 14, 0, 14))
	UI.rivet(f, UDim2.new(1, -14, 0, 14))
	UI.rivet(f, UDim2.new(0, 14, 1, -14))
	UI.rivet(f, UDim2.new(1, -14, 1, -14))
	-- hanging title sign
	local sign = UI.panel({ Color = accent, Radius = 14, Size = UDim2.new(0.6, 0, 0, 46), Position = UDim2.new(0.5, 0, 0, 6), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 4, Parent = f })
	UI.label({ Name = "Title", Text = props.Title or "", Size = UDim2.new(1, -20, 0.74, 0), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 5, Parent = sign })
	UI.rivet(sign, UDim2.new(0, 10, 0.5, 0), 9)
	UI.rivet(sign, UDim2.new(1, -10, 0.5, 0), 9)
	-- parchment body
	local body = UI.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.new(1, -28, 1, -74),
		Position = UDim2.fromOffset(14, 60),
		Parent = f,
	}, { UI.corner(14), UI.stroke(3), UI.gradient(C.Panel) })
	UI.new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), Parent = body })
	-- porthole close button: brass ring, red glass
	local ring = UI.new("Frame", { BackgroundColor3 = C.Brass, Size = UDim2.fromOffset(54, 54), Position = UDim2.new(1, 12, 0, -12), AnchorPoint = Vector2.new(1, 0), ZIndex = 6, Parent = f }, { UI.corner(54), UI.stroke(3.5) })
	UI.button({ Text = "X", Color = C.Coral, Radius = 40, Size = UDim2.fromOffset(40, 40), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 7, Parent = ring }, onClose)
	return f, body
end

function UI.tween(inst: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local t = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

-- Pop: scale up from small with a spring (needs a UIScale child; one is added if missing)
function UI.pop(gui: GuiObject, from: number?, to: number?)
	local sc = gui:FindFirstChildOfClass("UIScale") or UI.new("UIScale", { Parent = gui })
	sc.Scale = from or 0.6
	UI.tween(sc, 0.35, { Scale = to or 1 }, Enum.EasingStyle.Back)
end

-- A chunky button: coloured face, navy outline, white label, squash on press.
function UI.button(props: { [string]: any }, onClick: (() -> ())?): TextButton
	local color = props.Color or C.Sea
	local text = props.Text or ""
	props.Color = nil
	props.Text = nil
	local b = UI.new("TextButton", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = false,
		Text = "",
		BorderSizePixel = 0,
	}, { UI.corner(props.Radius or 16), UI.stroke(3.5), UI.gradient(color) })
	props.Radius = nil
	local textSize = props.TextSize
	props.TextSize = nil
	for k, v in props do
		if k ~= "Parent" then
			(b :: any)[k] = v
		end
	end
	local sc = UI.new("UIScale", { Parent = b })
	local lbl = UI.label({ Name = "Label", Text = text, Size = UDim2.new(1, -12, textSize or 0.72, 0), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = b })
	b.MouseEnter:Connect(function()
		UI.tween(sc, 0.12, { Scale = 1.06 })
	end)
	b.MouseLeave:Connect(function()
		UI.tween(sc, 0.12, { Scale = 1 })
	end)
	b.MouseButton1Down:Connect(function()
		UI.tween(sc, 0.08, { Scale = 0.9 })
	end)
	b.MouseButton1Up:Connect(function()
		UI.tween(sc, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	if onClick then
		b.Activated:Connect(function()
			local Sound = require(script.Parent.Sound) :: any
			Sound.play("Click")
			onClick()
		end)
	end
	local _ = lbl
	b.Parent = props.Parent
	return b
end

function UI.setText(b: GuiObject, text: string)
	local l = b:FindFirstChild("Label") :: TextLabel?
	if l then
		l.Text = text
	end
end

-- "<WORD>" in tutorial lines becomes gold
function UI.keyword(text: string): string
	return (string.gsub(text, "<(.-)>", '<font color="#FFCD32">%1</font>'))
end

-- Star row as text (6 = Divine: six full stars). sixth = the rare sixth-star fuse bonus, shown as a
-- sparkle after the row so it never looks like the Divine rarity.
function UI.stars(n: number, sixth: boolean?): string
	return string.rep("★", n) .. string.rep("☆", math.max(0, 5 - n)) .. (if sixth then " ✦" else "")
end

return UI
