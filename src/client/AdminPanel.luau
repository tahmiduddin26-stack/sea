--!strict
-- Admin panel for the accounts in Config.ADMIN_IDS ONLY (Studio and live). The tab is only built when
-- the server has set the "Admin" attribute AND this account is on the list; the server re-checks
-- every command (AdminService), so nobody else can use it even with a tampered client.
-- A small ADMIN tab at the left edge opens a list of buttons; each one sends a command to
-- AdminService. In a live server the panel title says so, since the commands change real saves.

local Players = game:GetService("Players")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Config)
local UI = require(script.Parent.UI)
local State = require(script.Parent.State)
local Hud = require(script.Parent.Hud)

local AdminPanel = {}

local player = Players.LocalPlayer
local C = UI.Colors

local ROWS: { { label: string, cmd: string, n: number?, color: Color3? } } = {
	{ label = "RESET: new player", cmd = "ResetNew", color = C.Coral },
	{ label = "Give 3 Lv1 monsters", cmd = "Lv1Team", color = C.Kelp },
	{ label = "Skip tutorial", cmd = "SkipTutorial" },
	{ label = "+10K coins", cmd = "Coins", n = 10000 },
	{ label = "+1M coins", cmd = "Coins", n = 1000000 },
	{ label = "Set coins to the start amount", cmd = "SetCoins", n = 2500 * 100 }, -- = Config.START_COINS
	{ label = "+500 pearls", cmd = "Pearls", n = 500 },
	{ label = "Best depth 0", cmd = "BestDepth", n = 0 },
	{ label = "Best depth 30", cmd = "BestDepth", n = 30 },
	{ label = "Best depth 100", cmd = "BestDepth", n = 100 },
	{ label = "Add Lv3 monster", cmd = "Monster", n = 3 },
	{ label = "Add Lv6 monster", cmd = "Monster", n = 6 },
	{ label = "Add Lv10 monster", cmd = "Monster", n = 10 },
	{ label = "Add 2 Tide Sovereigns (Lv1)", cmd = "Sovereigns", n = 1, color = Color3.fromRGB(110, 230, 255) },
	{ label = "Divine egg in a nest", cmd = "DivineEgg", color = Color3.fromRGB(110, 230, 255) },
	{ label = "Finish all timers", cmd = "FinishTimers" },
	{ label = "Unlock Floor 2", cmd = "Floor2" },
	{ label = "Unlock Floor 3", cmd = "Floor3" },
	{ label = "Fight from depth 10", cmd = "GoToDepth", n = 10 },
	{ label = "Deep Rod ready now", cmd = "DeepRod" },
	{ label = "Abyss Rod ready now", cmd = "AbyssRod" },
	{ label = "Play new-player intro", cmd = "Intro" },
	{ label = "+9 Common spell cards", cmd = "Spells", n = 9 },
	{ label = "Ship tier 0", cmd = "ShipTier", n = 0 },
	{ label = "Ship tier 6", cmd = "ShipTier", n = 6 },
	{ label = "Ship tier 12", cmd = "ShipTier", n = 12 },
}

function AdminPanel.init(screen: ScreenGui)
	local function build()
		local tab = UI.button({ Text = "ADMIN", Color = C.Deep, Size = UDim2.fromOffset(110, 40), Position = UDim2.new(0, 170, 0, 8), Parent = screen }, nil)
		tab.ZIndex = 40
		local panel = UI.panel({ Name = "AdminPanel", Size = UDim2.fromOffset(330, 560), Position = UDim2.new(0, 170, 0, 54), Visible = false, ZIndex = 40, Parent = screen })
		UI.label({ Text = if game:GetService("RunService"):IsStudio() then "Admin (Studio)" else "ADMIN: LIVE SERVER", MaxText = 26, Size = UDim2.new(1, -20, 0, 34), Position = UDim2.fromOffset(10, 6), TextColor3 = C.Gold, ZIndex = 41, Parent = panel })
		local scroll = UI.new("ScrollingFrame", { BackgroundTransparency = 1, Size = UDim2.new(1, -20, 1, -50), Position = UDim2.fromOffset(10, 44), ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), BorderSizePixel = 0, ZIndex = 41, Parent = panel })
		UI.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
		for i, row in ROWS do
			local b = UI.button({ Text = row.label, Color = row.color or C.Sea, Size = UDim2.new(1, -8, 0, 40), LayoutOrder = i, ZIndex = 42, Parent = scroll }, function()
				local ok, msg = State.action("Admin", { cmd = row.cmd, n = row.n })
				Hud.toast(msg or (if ok then "Done" else "Failed"), if ok then C.Kelp else C.Coral)
			end)
			b.ZIndex = 42
		end
		tab.Activated:Connect(function()
			panel.Visible = not panel.Visible
		end)
		-- on phones the HUD reaches the top edge, where Roblox's own buttons sit at the left: keep the
		-- tab (and its panel) just to the right of them
		local Platform = require(script.Parent.Platform) :: any
		task.spawn(function()
			while tab.Parent do
				local x = math.max(170, Platform.topbarLeft() + 6)
				tab.Position = UDim2.new(0, x, 0, 8)
				panel.Position = UDim2.new(0, x, 0, 54)
				task.wait(1)
			end
		end)
	end
	-- nobody but the listed admins ever gets the ADMIN tab
	if table.find(Config.ADMIN_IDS, player.UserId) == nil then
		return
	end
	if player:GetAttribute("Admin") then
		build()
	else
		local conn
		conn = player:GetAttributeChangedSignal("Admin"):Connect(function()
			if player:GetAttribute("Admin") then
				conn:Disconnect()
				build()
			end
		end)
	end
end

return AdminPanel
