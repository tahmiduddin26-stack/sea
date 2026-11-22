--!strict
-- The missions board: three quick goals on the left edge of the HUD with a progress bar and
-- the reward (the server pays it the moment a mission is done and a new one slides in).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)

local UI = require(script.Parent.UI)
local State = require(script.Parent.State)

local MissionView = {}

local C = UI.Colors

local LABEL = {
	fish = "Fish up %d eggs",
	hatch = "Hatch %d monsters",
	fuse = "Fuse %d times",
	kills = "Beat %d enemies",
	boss = "Beat a boss",
	sell = "Sell %d monsters",
}
local ROW_H, GAP = 70, 8

local function label(m: any): string
	local f = LABEL[m.kind] or m.kind
	return if string.find(f, "%%d") then string.format(f, m.target) else f
end

function MissionView.init(screen: ScreenGui)
	local hud = screen:WaitForChild("Hud") :: GuiObject
	local H = Config.MISSIONS.count * (ROW_H + GAP) + 30
	local holder = UI.new("Frame", { Name = "Missions", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 0.5, -34), Size = UDim2.fromOffset(268, H), Visible = false, Parent = hud })
	UI.plank({ Text = "MISSIONS", Color = C.Plank, MaxText = 18, TextColor = C.Brass, Size = UDim2.fromOffset(150, 24), Position = UDim2.fromOffset(0, 0), Parent = holder })

	local rows: { [number]: { frame: Frame, fill: Frame, count: TextLabel, title: TextLabel, reward: TextLabel, id: number, shown: number } } = {}

	local function build(i: number, m: any)
		local f = UI.panel({ Size = UDim2.new(1, 0, 0, ROW_H), Position = UDim2.fromOffset(0, 30 + (i - 1) * (ROW_H + GAP)), Radius = 14, Parent = holder })
		local title = UI.label({ Text = label(m), Stroke = 0, TextColor3 = C.Ink, MaxText = 18, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -62, 0, 22), Position = UDim2.fromOffset(10, 4), Parent = f })
		local count = UI.label({ Text = "", Stroke = 0, TextColor3 = C.Deep, MaxText = 18, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.fromOffset(52, 22), Position = UDim2.new(1, -58, 0, 4), Parent = f })
		local bar = UI.new("Frame", { BackgroundColor3 = Color3.fromRGB(205, 182, 138), BorderSizePixel = 0, Size = UDim2.new(1, -20, 0, 12), Position = UDim2.fromOffset(10, 32), Parent = f }, { UI.corner(6), UI.stroke(2) })
		local fill = UI.new("Frame", { BackgroundColor3 = C.Kelp, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = bar }, { UI.corner(6) })
		local reward = UI.label({ Text = "", Stroke = 1.5, TextColor3 = C.Gold, MaxText = 15, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.new(1, -20, 0, 18), Position = UDim2.fromOffset(10, 48), Parent = f })
		UI.pop(f, 0.85)
		rows[i] = { frame = f, fill = fill, count = count, title = title, reward = reward, id = m.id, shown = -1 }
	end

	local function refresh()
		local snap = State.snapshot
		if not snap then
			return
		end
		local list = snap.missions or {}
		holder.Visible = snap.tutorial >= Config.TUTORIAL_DONE and #list > 0
		for i = 1, Config.MISSIONS.count do
			local m = list[i]
			local row = rows[i]
			if not m then
				if row then
					row.frame:Destroy()
					rows[i] = nil
				end
			else
				if row and row.id ~= m.id then
					row.frame:Destroy()
					rows[i] = nil
					row = nil
				end
				if not row then
					build(i, m)
					row = rows[i]
				end
				local r = rows[i]
				if r.shown ~= m.progress then
					r.shown = m.progress
					r.count.Text = m.progress .. "/" .. m.target
					UI.tween(r.fill, 0.3, { Size = UDim2.fromScale(math.clamp(m.progress / m.target, 0, 1), 1) })
				end
				r.reward.Text = Format.abbrev(m.coins) .. " coins + " .. m.pearls .. " pearls"
			end
		end
	end
	State.Changed:Connect(refresh)
	refresh()
end

return MissionView
