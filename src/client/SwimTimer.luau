--!strict
-- The swim counter: while you are in the water the server sets the "SwimEndsAt" attribute (server time,
-- Config.SWIM_SECONDS from when you jumped in). A big number counts 5 .. 1 at the top of the screen, and at
-- zero the server takes you back to your ship. Nothing here decides anything: it only shows the count.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local UI = require(script.Parent.UI)

local SwimTimer = {}

local player = Players.LocalPlayer
local C = UI.Colors

function SwimTimer.init(screen: ScreenGui)
	local holder = UI.new("Frame", {
		Name = "SwimTimer",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(460, 120),
		Position = UDim2.new(0.5, 0, 0.22, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 20,
		Parent = screen,
	})
	local title = UI.label({ Text = "Swimming! Back to your ship in", MaxText = 26, Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 0), ZIndex = 21, Parent = holder })
	local number = UI.label({ Text = "5", MaxText = 72, TextColor3 = C.Gold, Size = UDim2.new(1, 0, 0, 80), Position = UDim2.fromOffset(0, 36), ZIndex = 21, Parent = holder })
	local lastShown = -1
	RunService.RenderStepped:Connect(function()
		local endsAt = player:GetAttribute("SwimEndsAt") :: number?
		if not endsAt then
			holder.Visible = false
			lastShown = -1
			return
		end
		local left = math.max(0, math.ceil(endsAt - workspace:GetServerTimeNow()))
		holder.Visible = true
		if left ~= lastShown then
			lastShown = left
			number.Text = tostring(left)
			number.TextColor3 = if left <= 2 then C.Coral else C.Gold
			-- a little pop each second
			local scale = holder:FindFirstChildOfClass("UIScale") or UI.new("UIScale", { Parent = holder })
			scale.Scale = 1.25
			UI.tween(scale, 0.25, { Scale = 1 })
		end
	end)
end

return SwimTimer
