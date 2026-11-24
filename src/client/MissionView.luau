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
local Platform = require(script.Parent.Platform)

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
	local holder = UI.new("Frame", { Name = "Missions", BackgroundTransparency = 1, Visible = false, Parent = hud })
	-- The header is a button: the board is a drop-down (closed on phones and consoles, open on
	-- PC). While it is closed the little arrow bobs to say "tap me".
	local header = UI.plank({ Text = "MISSIONS", Color = C.Plank, MaxText = 18, TextColor = C.Brass, Size = UDim2.fromOffset(160, 28), Position = UDim2.fromOffset(0, 0), Parent = holder })
	local arrow = UI.label({ Text = "▼", MaxText = 16, Stroke = 0, TextColor3 = C.Gold, Size = UDim2.fromOffset(22, 22), Position = UDim2.new(1, -26, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 5, Parent = header })
	local toggleBtn = UI.new("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = header })

	local rows: { [number]: { frame: Frame, fill: Frame, count: TextLabel, title: TextLabel, reward: TextLabel, id: number, shown: number } } = {}
	local expanded = Platform.mode() == "key"

	-- Phones (touch mode): a compact board at the bottom, just left of the Fuse heart (the money
	-- has the left edge to itself, Hud.setMode). Its header sits at the bottom and the rows open
	-- UPWARD, over the deck: clear of the Sell button, the thumbstick and the battle bar.
	-- PC / console: the roomy board on the left edge with the reward line.
	local compact = false
	local lastOff = 0
	local rowH, gap = ROW_H, GAP
	local function layout()
		compact = Platform.mode() == "touch"
		-- opened on a phone there is room for bigger rows (the closed board is just the header)
		rowH, gap = if compact then 46 else ROW_H, if compact then 5 else GAP
		local H = if expanded then Config.MISSIONS.count * (rowH + gap) + 34 else 30
		-- narrow so it doesn't run across the screen, with real gaps between the rows
		holder.Size = UDim2.fromOffset(if compact then 230 else 268, H)
		if compact then
			-- opens upward: the arrow points the way the board will open
			arrow.Text = if expanded then "▼" else "▲"
			lastOff = Platform.topInset()
			holder.AnchorPoint = Vector2.new(1, 1)
			holder.Position = UDim2.new(0.5, -80, 1, -10) -- bottom, left of the Fuse heart
			header.Position = UDim2.new(0, 0, 1, -28)
		else
			arrow.Text = if expanded then "▲" else "▼"
			holder.AnchorPoint = Vector2.new(0, 1)
			holder.Position = UDim2.new(0, 14, 0.5, -34)
			header.Position = UDim2.fromOffset(0, 0)
		end
	end
	layout()

	local function build(i: number, m: any)
		-- phones: rows stack from the top of the board down to the header at the bottom
		local f = UI.panel({ Size = UDim2.new(1, 0, 0, rowH), Position = UDim2.fromOffset(0, (if compact then 0 else 34) + (i - 1) * (rowH + gap)), Radius = 14, Parent = holder })
		local title = UI.label({ Text = label(m), Stroke = 0, TextColor3 = C.Ink, MaxText = if compact then 22 else 17, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -60, 0, if compact then 26 else 22), Position = UDim2.fromOffset(10, if compact then 3 else 3), Parent = f })
		local count = UI.label({ Text = "", Stroke = 0, TextColor3 = C.Deep, MaxText = if compact then 22 else 17, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.fromOffset(52, if compact then 26 else 22), Position = UDim2.new(1, -58, 0, 3), Parent = f })
		-- the bar sits well below the words so the two never touch
		local bar = UI.new("Frame", { BackgroundColor3 = Color3.fromRGB(205, 182, 138), BorderSizePixel = 0, Size = UDim2.new(1, -20, 0, if compact then 10 else 12), Position = UDim2.fromOffset(10, if compact then 33 else 34), Parent = f }, { UI.corner(6), UI.stroke(2) })
		local fill = UI.new("Frame", { BackgroundColor3 = C.Kelp, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = bar }, { UI.corner(6) })
		local reward = UI.label({ Text = "", Stroke = 1.5, TextColor3 = C.Gold, MaxText = 15, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.new(1, -20, 0, 18), Position = UDim2.fromOffset(10, 50), Visible = not compact, Parent = f })
		UI.pop(f, 0.85)
		rows[i] = { frame = f, fill = fill, count = count, title = title, reward = reward, id = m.id, shown = -1 }
	end

	local function refresh()
		local snap = State.snapshot
		if not snap then
			return
		end
		-- the device layout changed (phone <-> PC / console): rebuild the rows at the new size
		-- and reset the drop-down to that device's default (open on PC, closed elsewhere)
		if compact ~= (Platform.mode() == "touch") then
			for i, r in rows do
				r.frame:Destroy()
				rows[i] = nil
			end
			expanded = Platform.mode() == "key"
			layout()
		end
		local list = snap.missions or {}
		-- on phones the board shares the bottom with the fuse tray: step aside while it is open
		local Hud = require(script.Parent.Hud) :: any
		holder.Visible = snap.tutorial >= Config.TUTORIAL_DONE and #list > 0 and not (compact and Hud.fuseOpen)
		-- closed: just the header (rows are only built while open)
		if not expanded then
			for i, r in rows do
				r.frame:Destroy()
				rows[i] = nil
			end
			return
		end
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
	toggleBtn.Activated:Connect(function()
		expanded = not expanded
		for i, r in rows do
			r.frame:Destroy()
			rows[i] = nil
		end
		layout()
		refresh()
	end)
	-- while the board is closed the arrow bobs: "tap me"
	task.spawn(function()
		local up = true
		while holder.Parent do
			if not expanded and holder.Visible then
				UI.tween(arrow, 0.5, { Position = UDim2.new(1, -26, 0.5, if up then 4 else -3) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
				up = not up
			else
				arrow.Position = UDim2.new(1, -26, 0.5, 0)
			end
			task.wait(0.55)
		end
	end)
	layout()
	refresh()
	-- also notice a layout change when no data changed (a controller or phone preview kicks in)
	task.spawn(function()
		while holder.Parent do
			task.wait(0.5)
			if compact ~= (Platform.mode() == "touch") or (compact and math.abs(Platform.topInset() - lastOff) > 1) then
				if compact == (Platform.mode() == "touch") then
					layout() -- only the strip under Roblox's buttons changed: move the board
				else
					refresh()
				end
			elseif compact then
				refresh() -- (cheap) picks up the fuse tray opening / closing, which sends no data
			end
		end
	end)
end

return MissionView
