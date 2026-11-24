--!strict
-- Pop-up panels: Fuse (pick two same-level monsters, see the odds, FUSE!), Shop (Robux
-- passes + products + codes), Index (every species, found or a silhouette), the battle
-- end card with Revive, the big hatch / fuse reveal, and the offline earnings card.
-- One panel at a time; each closes with the red X.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Stats = require(Shared.Stats)
local MonsterModels = require(Shared.MonsterModels)
local Remotes = require(Shared.Remotes)

local UI = require(script.Parent.UI)
local State = require(script.Parent.State)
local Hud = require(script.Parent.Hud)
local Sound = require(script.Parent.Sound)
local Platform = require(script.Parent.Platform)

local Menus = {}

local player = Players.LocalPlayer
local C = UI.Colors

local screenRef: ScreenGui
local open: Frame? = nil

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
Menus.onOpen = nil :: ((GuiObject) -> ())?

function Menus.isOpen(): boolean
	return open ~= nil
end

Menus.onClose = nil :: (() -> ())?

function Menus.close()
	if open then
		open:Destroy()
		open = nil
		Platform.menuChanged(false)
		if Menus.onClose then
			Menus.onClose()
		end
	end
end

local function window(title: string, size: Vector2, color: Color3?): (Frame, Frame)
	Menus.close()
	local f, body = UI.window({ Title = title, Accent = color or C.Sea, Size = UDim2.fromOffset(size.X, size.Y), Position = UDim2.fromScale(0.5, 0.46), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 10, Parent = screenRef }, Menus.close)
	f.Parent = screenRef
	open = f
	-- phones are shorter than most menus: shrink to fit the screen
	local fit = Platform.fit(size)
	f.Position = Platform.menuPosition(size, fit)
	UI.pop(f, 0.7 * fit, fit)
	Platform.menuChanged(true)
	if Menus.onOpen then
		Menus.onOpen(f)
	end
	return f, body
end

-- A creature in a ViewportFrame, idling
local viewports: { { vp: ViewportFrame, rig: MonsterModels.Rig, cf: CFrame } } = {}
local function creatureView(parent: GuiObject, id: string, size: UDim2, pos: UDim2?, silhouette: boolean?): ViewportFrame
	local vp = UI.new("ViewportFrame", { BackgroundTransparency = 1, Size = size, Position = pos or UDim2.new(), Ambient = Color3.fromRGB(200, 200, 210), LightColor = Color3.new(1, 1, 1), LightDirection = Vector3.new(-1, -1, -1), Parent = parent })
	local rig = MonsterModels.build(id, 1)
	if not rig then
		return vp
	end
	rig.model.Parent = vp
	if silhouette then
		MonsterModels.tint(rig, Color3.fromRGB(20, 26, 50), 1)
	end
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	local h = MonsterModels.height(rig)
	local foot = MonsterModels.footDepth(rig)
	local mid = (h - foot) / 2
	cam.CFrame = CFrame.lookAt(Vector3.new(-5.5, mid + 2.2, -11), Vector3.new(0, mid, 0))
	cam.Parent = vp
	vp.CurrentCamera = cam
	table.insert(viewports, { vp = vp, rig = rig, cf = CFrame.Angles(0, math.rad(-10), 0) })
	return vp
end

-- The real purchase (Roblox's own confirm window). Players normally reach it from the detail window
-- below, which says what the item is first; only the Revive button (a 15 second window) buys directly.
local function buy(kind: string, name: string)
	local info = if kind == "Pass" then Config.GAMEPASSES[name] else Config.PRODUCTS[name]
	if not info then
		return
	end
	if info.id == 0 then
		if RunService:IsStudio() then
			local sim = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("SimulatePurchase") :: RemoteFunction?
			if sim then
				sim:InvokeServer(kind, name)
			end
		else
			Hud.toast("Coming soon!", C.Deep)
		end
		return
	end
	Remotes.event("Track"):FireServer("prompt", name)
	if kind == "Pass" then
		MarketplaceService:PromptGamePassPurchase(player, info.id)
	else
		MarketplaceService:PromptProductPurchase(player, info.id)
	end
end
Menus.buy = buy

-- What each pack / pass actually gives, one short line each (shown with a tick in the detail window).
-- Numbers come from Config / Stats so the text can never drift from what the purchase really grants.
local function detailLines(kind: string, name: string): ({ string }, string)
	local snap = State.snapshot
	local depth = (snap and snap.bestDepth) or 0
	local coins = Format.abbrev(5 * Config.COIN_SCALE * 1000)
	if name == "StarterPack" then
		return { "A Lv3 Kelpdrake (2-star) in a free nest", coins .. " coins", "50 pearls" }, "One-time offer"
	elseif name == "PearlDragonPack" then
		return { "The Legendary Pearl Dragon (4-star)", "Starts at Lv5", "Goes straight into a free nest" }, "One-time offer"
	elseif name == "ElementBundle" then
		return { "4 eggs, one of each element:", "Tide, Coral, Storm and Abyss", "Each is a 2-star Lv1 egg", "Needs 4 free nests: they go straight in" }, "4 eggs"
	elseif name == "LimitedRoll" then
		local lines = { "One roll of the Abyss Crate: a 2-star egg" }
		local odds = {}
		for _, o in Config.LIMITED.odds do
			table.insert(odds, Config.MONSTERS[o.sp].name .. " " .. math.floor(o.chance * 100 + 0.5) .. "%")
		end
		table.insert(lines, table.concat(odds, ", ", 1, math.min(3, #odds)))
		if #odds > 3 then
			table.insert(lines, table.concat(odds, ", ", 4))
		end
		table.insert(lines, "Needs a free nest. The odds are shown above")
		return lines, "A random egg"
	elseif name == "PowerSpins" then
		return { "5 spins of the Power wheel", "Each spin wins a random battle boost" }, "5 spins"
	elseif name == "Luck30" then
		return { "x2 egg luck from the rods", "x2 fuse luck (stars and secrets)", "Lasts 30 minutes" }, "Boost"
	elseif name == "FuseLuck" then
		return { "x2 chance of a star-up when fusing", "x2 chance of a secret monster", "Lasts 15 minutes" }, "Boost"
	elseif name == "InsaneLuck" then
		return { "x4 chance of a star-up when fusing", "x4 chance of a secret monster", "Lasts 15 minutes" }, "Boost"
	elseif name == "SkipTimer" then
		return { "Every egg hatches instantly", "Every fuse finishes instantly", "Lasts 5 minutes (buy again to add more)" }, "Boost"
	elseif name == "Revive" then
		return { "Your whole team comes back at full health", "Keep diving from the same depth", "Use it right after a defeat" }, "Use after a defeat"
	elseif Config.COIN_PACK_MINUTES[name] then
		return {
			"+" .. Format.abbrev(Stats.coinPack(name, depth)) .. " coins, paid right away",
			"About " .. Config.COIN_PACK_MINUTES[name] .. " minutes of fighting at your best depth",
			"Grows as you get deeper",
		}, "Coins"
	elseif name == "VIP" then
		return { "+25% coins from every battle", "Gold VIP Captain name tag", "Gold nests on your ship", "[VIP] tag in chat" }, "Game pass: yours forever"
	elseif name == "DoubleCoins" then
		return { "Double coins from every battle" }, "Game pass: yours forever"
	elseif name == "FastFuse" then
		return { "Eggs hatch twice as fast", "Monsters fuse twice as fast" }, "Game pass: yours forever"
	elseif name == "FastBattle" then
		return { "Unlocks the x2 battle speed button", "Fights finish twice as fast" }, "Game pass: yours forever"
	elseif name == "ExtraPedestal" then
		return { "The fishing rods reel in eggs 8% faster" }, "Game pass: yours forever"
	elseif name == "DoubleLuck" then
		return { "x2 egg luck", "x2 fuse luck (stars and secrets)" }, "Game pass: yours forever"
	end
	local info = if kind == "Pass" then Config.GAMEPASSES[name] else Config.PRODUCTS[name]
	return { if info then info.desc else "" }, ""
end

-- The window every pack / offer / sign opens: the picture, what it is, a ticked list of what you get,
-- the price and a Buy button, like a shop card but with the details.
local function detail(kind: string, name: string)
	local info = if kind == "Pass" then Config.GAMEPASSES[name] else Config.PRODUCTS[name]
	if not info then
		return
	end
	local owned = kind == "Pass" and State.hasPass(name)
	local lines, tag = detailLines(kind, name)
	local rowH = 36
	local h = 250 + #lines * rowH + 96
	local _, body = window(info.name, Vector2.new(520, h), C.Gold)
	local ICONKEY = { StarterPack = "Team", PearlDragonPack = "Pearl", FuseLuck = "LuckEgg", InsaneLuck = "Crate", SkipTimer = "Speed", CoinsSmall = "Coin", CoinsBig = "Shop", VIP = "Event", DoubleCoins = "Coin", FastFuse = "Heart", FastBattle = "Speed", ExtraPedestal = "Pedestal", Luck30 = "LuckEgg", DoubleLuck = "LuckEgg" }
	UI.new("ImageLabel", { BackgroundTransparency = 1, Image = Config.STORE_ICONS[name] or Config.ICONS[ICONKEY[name] or "Coin"], Size = UDim2.fromOffset(96, 96), Position = UDim2.new(0.5, 0, 0, 2), AnchorPoint = Vector2.new(0.5, 0), Parent = body })
	if tag ~= "" then
		UI.label({ Text = tag, Stroke = 0, TextColor3 = Color3.fromRGB(200, 120, 0), MaxText = 20, Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 102), Parent = body })
	end
	UI.label({ Text = "What you get", TextColor3 = C.Ink, Stroke = 0, MaxText = 24, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -30, 0, 30), Position = UDim2.fromOffset(18, 136), Parent = body })
	for i, text in lines do
		local y = 170 + (i - 1) * rowH
		-- a green tick box, then the line
		UI.new("Frame", { BackgroundColor3 = C.Kelp, Size = UDim2.fromOffset(26, 26), Position = UDim2.fromOffset(20, y + 3), Parent = body }, { UI.corner(7), UI.stroke(2.5) })
		UI.label({ Text = "✓", MaxText = 22, Size = UDim2.fromOffset(26, 26), Position = UDim2.fromOffset(20, y + 3), ZIndex = 3, Parent = body })
		UI.label({ Text = text, Stroke = 0, TextColor3 = C.Ink, MaxText = 20, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -86, 0, 32), Position = UDim2.fromOffset(60, y + 2), Parent = body })
	end
	UI.button({ Text = if owned then "Owned" else ("Buy   R$ " .. info.price), Color = if owned then C.Muted else C.Kelp, Size = UDim2.new(1, -40, 0, 56), Position = UDim2.new(0, 20, 1, -64), Parent = body }, function()
		if owned then
			return
		end
		Menus.close()
		buy(kind, name)
	end)
end
Menus.prompt = detail -- (signs, the Starter Pack and the offers open the detail window)

function Menus.promptOffer(name: string)
	if Config.GAMEPASSES[name] then
		if State.hasPass(name) then
			Hud.toast("You already own " .. Config.GAMEPASSES[name].name, C.Kelp)
			return
		end
		detail("Pass", name)
	else
		detail("Product", name)
	end
end

---------------------------------------------------------------------------
-- Fuse
---------------------------------------------------------------------------
function Menus.fuse()
	local snap = State.snapshot
	if not snap then
		return
	end
	if snap.inBattle then
		Hud.toast("Wait for the battle to end", C.Coral)
		return
	end
	local f, body = window("Fuse Monsters", Vector2.new(720, 470), Color3.fromRGB(255, 110, 170))
	local picked: { string } = {}

	-- slots row
	local top = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 150), Parent = body })
	local slotFrames: { Frame } = {}
	for i = 1, 2 do
		local s = UI.panel({ Size = UDim2.fromOffset(140, 140), Position = UDim2.fromOffset((i - 1) * 190, 0), Color = Color3.fromRGB(255, 220, 235), Parent = top })
		UI.label({ Text = "?", Size = UDim2.fromScale(0.5, 0.5), Position = UDim2.fromScale(0.25, 0.25), TextColor3 = Color3.fromRGB(255, 150, 190), Name = "Q", Parent = s })
		slotFrames[i] = s
	end
	UI.label({ Text = "+", Size = UDim2.fromOffset(40, 60), Position = UDim2.fromOffset(145, 40), Parent = top })
	UI.label({ Text = "=", Size = UDim2.fromOffset(40, 60), Position = UDim2.fromOffset(335, 40), Parent = top })
	local outcomes = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(300, 140), Position = UDim2.fromOffset(380, 0), Parent = top })
	UI.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), Parent = outcomes })
	local fuseBtn = UI.button({ Text = "FUSE!", Color = C.Kelp, Size = UDim2.fromOffset(180, 56), Position = UDim2.new(1, 0, 1, 0), AnchorPoint = Vector2.new(1, 1), Parent = f })
	fuseBtn.Position = UDim2.new(1, -16, 1, -14)
	local hint = UI.label({ Text = "Pick two monsters of the same level", TextColor3 = C.Deep, Stroke = 0, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -220, 0, 30), Position = UDim2.new(0, 16, 1, -50), Parent = f })

	-- monster grid
	local scroll = UI.new("ScrollingFrame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -210), Position = UDim2.fromOffset(0, 160), ScrollBarThickness = 8, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), BorderSizePixel = 0, Parent = body }, { UI.new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }) })
	UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(104, 120), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })

	local cards: { [string]: TextButton } = {}
	local function redraw()
		for i, s in slotFrames do
			for _, ch in s:GetChildren() do
				if ch:IsA("ViewportFrame") or ch.Name == "Info" then
					ch:Destroy()
				end
			end
			local uid = picked[i]
			local q = s:FindFirstChild("Q") :: TextLabel
			q.Visible = uid == nil
			if uid then
				local m = snap.monsters[uid]
				creatureView(s, m.sp, UDim2.fromScale(1, 0.8))
				UI.label({ Name = "Info", Text = "Lv." .. m.lvl .. " " .. UI.stars(Stats.shownStars(m.sp, m.x6), m.x6), Size = UDim2.new(1, 0, 0.2, 0), Position = UDim2.fromScale(0, 0.8), TextColor3 = C.Gold, Parent = s })
			end
		end
		for _, ch in outcomes:GetChildren() do
			if ch:IsA("GuiObject") then
				ch:Destroy()
			end
		end
		if #picked == 2 then
			local a, b = snap.monsters[picked[1]], snap.monsters[picked[2]]
			local luck = if (snap.luckUntil or 0) > State.now() then snap.luckMult else 1
			for _, o in Stats.fuseOdds({ a.sp, b.sp }, a.lvl, luck) do
				local card = UI.panel({ Size = UDim2.fromOffset(92, 130), Color = Color3.fromRGB(230, 240, 255), Parent = outcomes })
				local found = snap.index[o.sp] == true
				creatureView(card, o.sp, UDim2.new(1, 0, 0, 90), nil, not found)
				UI.label({ Text = math.floor(o.chance * 1000 + 0.5) / 10 .. "%", Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 94), TextColor3 = C.Gold, Parent = card })
			end
			hint.Text = "Lv." .. a.lvl .. " + Lv." .. b.lvl .. " = Lv." .. (a.lvl + 1) .. "   |   " .. "instant!"
		else
			hint.Text = "Pick two monsters of the same level"
		end
		for uid, card in cards do
			local m = snap.monsters[uid]
			local sel = table.find(picked, uid) ~= nil
			local ok = #picked == 0 or sel or (#picked == 1 and snap.monsters[picked[1]].lvl == m.lvl)
			card.BackgroundTransparency = if ok then 0 else 0.5
			local st = card:FindFirstChildOfClass("UIStroke")
			if st then
				st.Color = if sel then C.Gold else C.Ink
				st.Thickness = if sel then 5 else 3.5
			end
		end
	end

	-- list monsters, highest level first
	local list = {}
	for uid, m in snap.monsters do
		table.insert(list, { uid = uid, m = m })
	end
	table.sort(list, function(x, y)
		if x.m.lvl ~= y.m.lvl then
			return x.m.lvl > y.m.lvl
		end
		return x.uid < y.uid
	end)
	for i, e in list do
		local card = UI.button({ Text = "", Color = Color3.fromRGB(240, 246, 255), Size = UDim2.fromOffset(104, 120), LayoutOrder = i, Parent = scroll }, function()
			local idx = table.find(picked, e.uid)
			if idx then
				table.remove(picked, idx)
			elseif #picked < 2 then
				if #picked == 1 and snap.monsters[picked[1]].lvl ~= e.m.lvl then
					Hud.toast("Pick a monster of the same level", C.Coral)
					return
				end
				table.insert(picked, e.uid)
			end
			redraw()
		end)
		creatureView(card, e.m.sp, UDim2.new(1, 0, 0, 84))
		UI.label({ Text = "Lv." .. e.m.lvl, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 82), Parent = card })
		UI.label({ Text = UI.stars(Stats.shownStars(e.m.sp, e.m.x6), e.m.x6), TextColor3 = C.Gold, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 102), Parent = card })
		cards[e.uid] = card
	end
	if #list < 2 then
		UI.label({ Text = "You need two monsters of the same level. Hatch more eggs!", TextColor3 = C.Deep, Stroke = 0, Size = UDim2.new(1, 0, 0, 30), Parent = scroll })
	end
	-- tutorial: pre-pick the two Lv1 monsters
	if snap.tutorial == 10 and #list >= 2 then
		picked = { list[1].uid, list[2].uid }
	end

	fuseBtn.Activated:Connect(function()
		if #picked ~= 2 then
			Hud.toast("Pick two monsters first", C.Coral)
			return
		end
		local ok, msg = State.action("Fuse", picked)
		if ok then
			Menus.close()
		elseif msg then
			Hud.toast(msg, C.Coral)
		end
	end)
	redraw()
end

---------------------------------------------------------------------------
-- Shop (Robux) + codes
---------------------------------------------------------------------------
function Menus.shop()
	local _, body = window("Shop", Vector2.new(800, 540), C.Gold)
	-- short lines only: every card is icon, name, one line, price, so nothing gets cut
	local SHORT = {
		StarterPack = "Lv3 Kelpdrake + coins", PearlDragonPack = "Legendary dragon", FuseLuck = "x2 fuse luck 15m",
		InsaneLuck = "x4 fuse luck 15m", SkipTimer = "Instant hatch 5 min", CoinsSmall = "A chest of coins", CoinsBig = "A ship of coins",
		VIP = "+25% coins forever", DoubleCoins = "x2 coins forever", FastFuse = "x2 hatch speed", FastBattle = "x2 battle speed",
		ExtraPedestal = "rod reels 8% faster", Luck30 = "x2 luck for 30m", DoubleLuck = "x2 luck forever", PowerSpins = "5 Power wheel spins", ElementBundle = "1 egg of each element",
			LimitedRoll = "Roll the Abyss Crate", Revive = "Use after a defeat",
		}
	local ICON = { StarterPack = "Team", PearlDragonPack = "Pearl", FuseLuck = "LuckEgg", InsaneLuck = "Crate", SkipTimer = "Speed", CoinsSmall = "Coin", CoinsBig = "Shop", VIP = "Event", DoubleCoins = "Coin", FastFuse = "Heart", FastBattle = "Speed", ExtraPedestal = "Pedestal", Luck30 = "LuckEgg", DoubleLuck = "LuckEgg" }
	local scroll = UI.new("ScrollingFrame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -64), ScrollBarThickness = 8, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), BorderSizePixel = 0, Parent = body }, { UI.new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }) })
	UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(176, 196), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
	local order = 0
	local function card(kind: string, name: string, info: any, color: Color3)
		order += 1
		local owned = kind == "Pass" and State.hasPass(name)
		local c = UI.panel({ Size = UDim2.fromOffset(176, 196), Color = color, LayoutOrder = order, Parent = scroll })
		UI.new("ImageLabel", { BackgroundTransparency = 1, Image = Config.STORE_ICONS[name] or Config.ICONS[ICON[name] or "Coin"], Size = UDim2.fromOffset(72, 72), Position = UDim2.new(0.5, 0, 0, 6), AnchorPoint = Vector2.new(0.5, 0), Parent = c })
		UI.label({ Text = info.name, MaxText = 20, Size = UDim2.new(1, -12, 0, 24), Position = UDim2.fromOffset(6, 80), Parent = c })
		local line = SHORT[name] or ""
		if Config.COIN_PACK_MINUTES[name] then
			-- coin packs show exactly what they pay at your best depth
			line = "+" .. Format.abbrev(Stats.coinPack(name, State.snapshot.bestDepth or 0)) .. " Coins"
		end
		UI.label({ Text = line, Stroke = 0, TextColor3 = if Config.COIN_PACK_MINUTES[name] then Color3.fromRGB(200, 140, 0) else C.Ink, MaxText = 15, Size = UDim2.new(1, -12, 0, 20), Position = UDim2.fromOffset(6, 106), Parent = c })
		UI.button({ Text = if owned then "Owned" else ("R$ " .. info.price), Color = if owned then C.Muted else C.Kelp, Size = UDim2.new(1, -20, 0, 44), Position = UDim2.new(0, 10, 1, -54), Parent = c }, function()
			if not owned then
				detail(kind, name) -- what it is first, then Buy
			end
		end)
	end
	for _, name in { "StarterPack", "PearlDragonPack", "ElementBundle", "LimitedRoll", "PowerSpins", "Luck30", "FuseLuck", "InsaneLuck", "SkipTimer", "Revive", "CoinsSmall", "CoinsBig" } do
		local info = Config.PRODUCTS[name]
		-- products not created on Roblox yet (id 0) stay hidden outside Studio
		if not (name == "StarterPack" and State.snapshot.starterBought) and (info.id ~= 0 or RunService:IsStudio()) then
			card("Product", name, Config.PRODUCTS[name], Color3.fromRGB(255, 240, 200))
		end
	end
	for _, name in { "VIP", "DoubleCoins", "DoubleLuck", "FastFuse", "FastBattle", "ExtraPedestal" } do
		card("Pass", name, Config.GAMEPASSES[name], Color3.fromRGB(225, 235, 255))
	end
	-- codes
	local row = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 52), Position = UDim2.new(0, 0, 1, -52), Parent = body })
	local box = UI.new("TextBox", { PlaceholderText = "Enter code", Text = "", FontFace = UI.Font, TextScaled = true, TextColor3 = C.Ink, BackgroundColor3 = C.White, Size = UDim2.new(1, -170, 1, -6), ClearTextOnFocus = false, Parent = row }, { UI.corner(12), UI.stroke(3), UI.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }) })
	UI.button({ Text = "Redeem", Color = C.Sea, Size = UDim2.new(0, 156, 1, -6), Position = UDim2.new(1, -156, 0, 0), Parent = row }, function()
		local ok, msg = State.action("Code", box.Text)
		Hud.toast(msg or (if ok then "Redeemed!" else "Try again"), if ok then C.Kelp else C.Coral)
		if ok then
			box.Text = ""
		end
	end)
end

---------------------------------------------------------------------------
-- Index
---------------------------------------------------------------------------
function Menus.index(tab: number?)
	local snap = State.snapshot
	local _, body = window("Monster Index", Vector2.new(800, 540), C.Sea)
	local found = 0
	for _ in snap.index do
		found += 1
	end
	local total = #Config.MONSTER_ORDER
	-- progress bar + next milestone
	local nextR = nil
	for _, r in Config.INDEX_REWARDS do
		if found < r.count then
			nextR = r
			break
		end
	end
	local bar = UI.new("Frame", { BackgroundColor3 = Color3.fromRGB(40, 50, 80), Size = UDim2.new(1, -230, 0, 28), Position = UDim2.fromOffset(4, 2), Parent = body }, { UI.corner(14), UI.stroke(3) })
	UI.new("Frame", { BackgroundColor3 = C.Kelp, Size = UDim2.fromScale(math.clamp(found / total, 0.02, 1), 1), Parent = bar }, { UI.corner(14) })
	UI.label({ Text = "Found " .. found .. " / " .. total, MaxText = 20, Size = UDim2.fromScale(1, 0.85), Position = UDim2.fromScale(0, 0.08), ZIndex = 3, Parent = bar })
	UI.label({ Text = if nextR then ("Next: " .. nextR.count .. " = +" .. nextR.pearls .. " pearls") else "All found!", TextColor3 = C.Pearl, MaxText = 18, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.new(0, 220, 0, 28), Position = UDim2.new(1, -222, 0, 2), Parent = body })
	-- rarity tabs
	local tabs = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 38), Parent = body })
	UI.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), Parent = tabs })
	local cur = tab or 0
	local names = { "All", "Common", "Rare", "Epic", "Legendary", "Mythic", "Divine" }
	for i, n in names do
		local idx = i - 1
		local col = if idx == 0 then C.Sea else Config.RARITY[idx].color
		local b = UI.button({ Text = n, Color = col, Size = UDim2.fromOffset(104, 38), Parent = tabs }, function()
			Menus.index(idx)
		end)
		if idx ~= cur then
			b.BackgroundTransparency = 0.45
		end
	end
	local scroll = UI.new("ScrollingFrame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -86), Position = UDim2.fromOffset(0, 86), ScrollBarThickness = 8, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), BorderSizePixel = 0, Parent = body }, { UI.new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }) })
	UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(140, 168), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
	for i, id in Config.MONSTER_ORDER do
		local def = Config.MONSTERS[id]
		if cur == 0 or def.stars == cur then
			local has = snap.index[id] == true
			local r = Config.RARITY[def.stars]
			local c = UI.panel({ Size = UDim2.fromOffset(140, 168), Color = if has then Color3.fromRGB(235, 244, 255) else Color3.fromRGB(185, 195, 215), LayoutOrder = i, Parent = scroll })
			local st = c:FindFirstChildOfClass("UIStroke")
			if st then
				st.Color = r.color
			end
			creatureView(c, id, UDim2.new(1, 0, 0, 100), nil, not has)
			UI.label({ Text = UI.stars(def.stars), TextColor3 = C.Gold, MaxText = 14, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 100), Parent = c })
			UI.label({ Text = if has then def.name else "???", MaxText = 17, Size = UDim2.new(1, -10, 0, 22), Position = UDim2.fromOffset(5, 116), Parent = c })
			local row = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 142), Parent = c })
			UI.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 4), Parent = row })
			for _, el in def.elements do
				UI.new("Frame", { Size = UDim2.fromOffset(14, 14), BackgroundColor3 = Config.ELEMENTS[el].color, Parent = row }, { UI.corner(7), UI.stroke(2) })
			end
			-- mutation badges: gold / rainbow dots once found
			local muts = snap.indexV and snap.indexV[id]
			for _, v in { "Golden", "Rainbow" } do
				local got = muts and muts[v]
				UI.new("Frame", { Size = UDim2.fromOffset(14, 14), BackgroundColor3 = if v == "Golden" then C.Gold else C.Pearl, BackgroundTransparency = if got then 0 else 0.75, Parent = row }, { UI.corner(3), UI.stroke(2) })
			end
		end
	end
	Hud.indexSeen = found
	Hud.refresh()
end

---------------------------------------------------------------------------
-- Battle end
---------------------------------------------------------------------------
function Menus.battleEnd(p: any)
	local title = if p.retreat then "Retreated" elseif p.timeUp then "TIME'S UP!" else "Team Fainted!"
	-- tall enough for up to 5 text lines (36 each) and the Revive + No Thanks buttons below them
	local f, body = window(title, Vector2.new(440, 420), C.Coral)
	if p.timeUp then
		Hud.splash("TIME'S UP!", C.Coral)
	end
	local why = if p.retreat then "You swam back safely." elseif p.timeUp then "The boss swam away! Beat it in " .. Stats.bossTime(p.depth or 1) .. "s." else "Your team needs to get stronger!"
	local lines = {
		why,
		"Depth reached: " .. p.depth,
		"Coins earned: " .. Format.abbrev(p.coins),
		"Enemies beaten: " .. p.kills,
	}
	if p.rest then
		table.insert(lines, "Fainted monsters sleep up to " .. Format.time(p.rest))
	end
	for i, t in lines do
		UI.label({ Text = t, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, (i - 1) * 36), Parent = body })
	end
	-- "No Thanks" only when there is a Revive to turn down; otherwise (a retreat, or the offer has run
	-- out) it is just "OK"
	-- Revive is only ever for a team that was DEFEATED: a retreat never offers it
	local offerRevive = p.canRevive == true and not p.retreat
	local closeBtn = UI.button({ Text = if offerRevive then "No Thanks" else "OK", Color = if offerRevive then C.Muted else C.Kelp, Size = UDim2.new(1, -20, 0, 50), Position = UDim2.new(0, 10, 1, -58), Parent = body }, Menus.close)
	if offerRevive then
		local btn = UI.button({ Text = "Revive & Continue  R$" .. Config.PRODUCTS.Revive.price, Color = C.Kelp, Size = UDim2.new(1, -20, 0, 54), Position = UDim2.new(0, 10, 1, -120), Parent = body }, function()
			Menus.close()
			buy("Product", "Revive") -- straight to the purchase: the Revive offer only lasts 15 seconds
		end)
		local secs = Config.REVIVE_WINDOW
		task.spawn(function()
			while secs > 0 and btn.Parent do
				task.wait(1)
				secs -= 1
			end
			if btn.Parent then
				btn.Visible = false
				UI.setText(closeBtn, "OK") -- the offer is gone, so there is nothing left to refuse
				local g = closeBtn:FindFirstChildOfClass("UIGradient")
				if g then
					local fresh = UI.gradient(C.Kelp) -- same look as every green button
					g.Color = fresh.Color
					fresh:Destroy()
				end
			end
		end)
	end
	local _ = f
end

---------------------------------------------------------------------------
-- Reveal (hatch / fuse)
---------------------------------------------------------------------------
function Menus.reveal(kind: string, p: any)
	Menus.close()
	State.revealing = true
	Hud.refresh()
	local def = Config.MONSTERS[p.sp]
	-- full-screen holder; the dark backdrop is oversized so it also covers the top bar
	-- and the edges at any UI scale
	local f = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 30, Parent = screenRef })
	UI.new("Frame", { BackgroundColor3 = Color3.fromRGB(5, 10, 25), BackgroundTransparency = 0.25, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(3, 3), ZIndex = 29, Parent = f })
	open = f
	-- rotating rays behind the creature
	local rays = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(520, 520), Position = UDim2.fromScale(0.5, 0.45), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 30, Parent = f })
	local col = MonsterModels.elementColor(p.sp)
	for i = 0, 7 do
		UI.new("Frame", { BackgroundColor3 = col, BackgroundTransparency = 0.6, Size = UDim2.fromOffset(46, 520), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = i * 22.5, ZIndex = 30, Parent = rays }, { UI.corner(20) })
	end
	local vp = creatureView(f, p.sp, UDim2.fromOffset(340, 340), UDim2.fromScale(0.5, 0.45), true)
	vp.AnchorPoint = Vector2.new(0.5, 0.5)
	vp.ZIndex = 31
	local title = UI.label({ Text = if kind == "fuse" then "FUSED!" else "HATCHED!", TextColor3 = C.Gold, MaxText = 54, Size = UDim2.fromOffset(500, 56), Position = UDim2.new(0.5, 0, 0.12, 0), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 32, Parent = f })
	local name = UI.label({ Text = "", MaxText = 40, Size = UDim2.fromOffset(500, 50), Position = UDim2.new(0.5, 0, 0.76, 0), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 32, Parent = f })
	local stars = UI.label({ Text = "", TextColor3 = C.Gold, Size = UDim2.fromOffset(300, 40), Position = UDim2.new(0.5, 0, 0.84, 0), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 32, Parent = f })
	-- damage sticker: damage per second of the new monster
	local dmgSticker = UI.panel({ Color = Color3.fromRGB(255, 120, 100), Radius = 12, Size = UDim2.fromOffset(230, 34), Position = UDim2.new(0.5, 0, 0.9, 0), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 32, Visible = false, Parent = f })
	UI.label({ Text = "DAMAGE " .. Format.abbrev(math.floor(Stats.dps(p.sp, p.lvl, p.stars, p.v, p.x6) + 0.5)) .. " / sec", MaxText = 22, Size = UDim2.new(1, -16, 0.8, 0), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 33, Parent = dmgSticker })
	local isNew = true
	local _ = isNew
	UI.pop(title, 0.4)
	local conn = RunService.RenderStepped:Connect(function(dt)
		rays.Rotation += dt * 30
	end)
	Sound.play("Hatch", 0.8)
	-- silhouette, then colour pops in
	task.delay(0.9, function()
		for _, v in viewports do
			if v.vp == vp then
				MonsterModels.tint(v.rig, nil, 0)
			end
		end
		name.Text = (if def then def.name else p.sp) .. ' <font color="#FFCD32">Lv.' .. p.lvl .. "</font>"
		local st = Stats.shownStars(p.sp, p.x6)
		local rarity = Config.RARITY[math.clamp(st, 1, #Config.RARITY)]
		local rarityName = string.upper(rarity.name) .. (if p.x6 then " + SIXTH STAR" else "")
		stars.Text = UI.stars(st, p.x6) .. '  <font color="#' .. rarity.color:ToHex() .. '">' .. rarityName .. "</font>"
		if st >= 3 then
			Hud.splash(rarityName .. "!", rarity.color)
		end
		-- Deep Rod perk: say what it does under the title
		local perk = p.perk and Config.PERKS[p.perk]
		if perk then
			local pl = UI.label({ Text = string.upper(perk.name) .. ' PERK  <font color="#FFFFFF">' .. perk.desc .. "</font>", TextColor3 = perk.color, MaxText = 22, Size = UDim2.fromOffset(560, 30), Position = UDim2.new(0.5, 0, 0.19, 0), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 32, Parent = f })
			UI.pop(pl, 0.5)
			if st < 3 then
				Hud.splash(string.upper(perk.name) .. " PERK!", perk.color)
			end
		end
		UI.pop(name, 0.5)
		UI.pop(vp :: any, 0.6)
			dmgSticker.Visible = true
			UI.pop(dmgSticker, 0.4)
		Sound.play("Win", 0.6)
	end)
	-- The first hatch of the tutorial leads straight into its fight: closing this card sends the new
	-- monster out (the server moves the tutorial to step 5 right after the reveal fires, so the
	-- snapshot can still say 4 here). Without this, players went back to fishing and never found FIGHT.
	local tsnap = State.snapshot
	local tutorialFight = kind == "hatch" and tsnap ~= nil and (tsnap.tutorial == 4 or tsnap.tutorial == 5)
	local tapText = if Platform.mode() == "pad" then "Press the button to continue" elseif Platform.mode() == "key" then "Click to continue" else "Tap to continue"
	if tutorialFight then
		tapText = if Platform.mode() == "pad" then "Press the button to FIGHT" elseif Platform.mode() == "key" then "Click to FIGHT" else "Tap to FIGHT"
	end
	local tap = UI.label({ Text = tapText, Size = UDim2.fromOffset(300, 30), Position = UDim2.new(0.5, 0, 0.965, 0), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 32, TextTransparency = 1, Parent = f })
	task.delay(1.4, function()
		tap.TextTransparency = 0
	end)
	local btn = UI.new("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 40, Parent = f })
	local t0 = os.clock()
	local closed = false
	local function done()
		if closed or os.clock() - t0 < 1.2 then
			return
		end
		closed = true
		conn:Disconnect()
		State.revealing = false
		Hud.refresh()
		if open == f then
			open = nil
		end
		f:Destroy()
		if tutorialFight then
			Hud.press("Fight")
		end
	end
	if tutorialFight then
		-- a big FIGHT! button where the damage sticker's line ends, above everything (taps anywhere work too)
		local fightCta = UI.button({ Text = "FIGHT!", Color = C.Coral, Size = UDim2.fromOffset(240, 64), Position = UDim2.new(0.5, 0, 0.9, 0), AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, ZIndex = 41, Parent = f }, done)
		dmgSticker.Position = UDim2.new(0.5, 0, 0.115 + 0.06, 0) -- move the sticker under the title out of the button's way
		task.delay(1.2, function()
			if fightCta.Parent then
				fightCta.Visible = true
				UI.pop(fightCta, 0.5)
			end
		end)
	end
	btn.Activated:Connect(done)
	-- a controller needs no cursor here: A, B or X continues
	local pad
	pad = game:GetService("UserInputService").InputBegan:Connect(function(input)
		local k = input.KeyCode
		if k == Enum.KeyCode.ButtonA or k == Enum.KeyCode.ButtonB or k == Enum.KeyCode.ButtonX then
			pad:Disconnect()
			done()
		end
	end)
	task.delay(5, function()
		if tutorialFight then
			return -- the tutorial card waits for the player to choose FIGHT
		end
		pad:Disconnect()
		done()
	end)
end

---------------------------------------------------------------------------
-- Offline earnings
---------------------------------------------------------------------------
function Menus.offline(seconds: number, coins: number)
	local _, body = window("Welcome Back, Captain!", Vector2.new(440, 260), C.Kelp)
	UI.label({ Text = "Your team kept battling for " .. Format.time(seconds), Stroke = 0, TextColor3 = C.Ink, Size = UDim2.new(1, 0, 0, 30), Parent = body })
	UI.label({ Text = "+" .. Format.abbrev(coins) .. " Coins", TextColor3 = C.Gold, Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 44), Parent = body })
	UI.button({ Text = "Collect", Color = C.Kelp, Size = UDim2.new(1, -40, 0, 52), Position = UDim2.new(0, 20, 1, -56), Parent = body }, Menus.close)
	Sound.play("Coin", 0.8)
end

---------------------------------------------------------------------------
-- Team
---------------------------------------------------------------------------
local function sortedMonsters(snap: any)
	local list = {}
	for uid, m in snap.monsters do
		table.insert(list, { uid = uid, m = m, p = Stats.power(m.sp, m.lvl, m.stars, m.v, m.x6) })
	end
	table.sort(list, function(a, b)
		return a.p > b.p
	end)
	return list
end

local teamSellMode = false -- (Sell mode stays on while you sell several in a row)

-- The Sell button: the team screen with Sell mode already on
function Menus.sell()
	teamSellMode = true
	Menus.team(true)
end

-- keepSell: stay in Sell mode (the Sell button, or the redraw after a sale). Opening the team screen
-- any other way (the sign, the Team button) always starts with Sell mode OFF, so a monster can't be
-- sold by accident while you are just picking your team.
function Menus.team(keepSell: boolean?)
	if keepSell ~= true then
		teamSellMode = false
	end
	local snap = State.snapshot
	local list = sortedMonsters(snap)
	local chosen: { string } = table.clone(snap.team)
	if #chosen == 0 then
		for i = 1, math.min(#list, snap.teamSlots) do
			table.insert(chosen, list[i].uid)
		end
	end
	local f, body = window("Manage Team " .. #chosen .. "/" .. snap.teamSlots, Vector2.new(760, 480), C.Pearl)
	local scroll = UI.new("ScrollingFrame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -64), ScrollBarThickness = 8, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), BorderSizePixel = 0, Parent = body }, { UI.new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }) })
	-- three roomy columns so everything reads easily
	UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(226, 172), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
	local CARD_COLOR = Color3.fromRGB(255, 244, 216)
	local cards = {}
	-- Sell mode: tap a monster once to arm it (its card turns red and shows the price), tap again to sell
	local sellMode = teamSellMode
	local armed: string? = nil
	local sellBtn: GuiObject? = nil
	local function redraw()
		for uid, card in cards do
			local on = table.find(chosen, uid) ~= nil
			-- in Sell mode every card shows what it would sell for (in place of its Power line)
			local sellTag = card:FindFirstChild("SellTag") :: GuiObject
			local powerLbl = card:FindFirstChild("PowerLbl") :: GuiObject
			sellTag.Visible = sellMode
			powerLbl.Visible = not sellMode
			if sellMode then
				(card:FindFirstChild("Tick") :: GuiObject).Visible = false
				card.BackgroundColor3 = if uid == armed then Color3.fromRGB(255, 160, 150) else CARD_COLOR
				continue
			end
			-- no outlines: a chosen monster just gets a green card and an "IN" tag
			card.BackgroundColor3 = if on then Color3.fromRGB(165, 235, 170) else CARD_COLOR
			local tick = card:FindFirstChild("Tick") :: GuiObject
			tick.Visible = on
		end
	end
	for i, e in list do
		local card = UI.button({ Text = "", Color = Color3.fromRGB(255, 244, 216), Size = UDim2.fromOffset(226, 172), LayoutOrder = i, Parent = scroll }, function()
			if sellMode then
				local price = Stats.sellPrice(e.m.sp, e.m.lvl, e.m.v, snap.bestDepth)
				if armed ~= e.uid then
					armed = e.uid
					Hud.toast("Tap again to sell for " .. Format.abbrev(price) .. " coins", C.Coral)
					redraw()
					return
				end
				local ok, msg = State.action("Sell", e.uid)
				Hud.toast(msg or "", if ok then C.Gold else C.Coral)
				if ok then
					Sound.play("Coin", 0.7)
					task.wait(0.5) -- (the snapshot with the sale arrives a moment later)
					Menus.team(true) -- (redraws without the sold monster, still in Sell mode)
				end
				return
			end
			local idx = table.find(chosen, e.uid)
			local sleepLeft = (e.m.restUntil or 0) - State.now()
			if idx then
				table.remove(chosen, idx)
			elseif sleepLeft > 0 then
				Hud.toast("Sleeping! Ready in " .. Format.time(sleepLeft), C.Coral)
			elseif #chosen < snap.teamSlots then
				table.insert(chosen, e.uid)
			else
				Hud.toast("Team is full! Buy more slots", C.Coral)
			end
			redraw()
		end)
		local cst = card:FindFirstChildOfClass("UIStroke")
		if cst then
			cst.Thickness = 0
		end
		creatureView(card, e.m.sp, UDim2.new(1, 0, 0, 92))
		UI.label({ Text = "Lv." .. e.m.lvl .. (if e.m.power then " " .. e.m.power else ""), MaxText = 22, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 92), Parent = card })
		-- damage sticker: how hard this monster hits, per second
		local dmg = UI.panel({ Color = Color3.fromRGB(255, 120, 100), Radius = 10, Size = UDim2.new(1, -24, 0, 26), Position = UDim2.fromOffset(12, 118), Parent = card })
		UI.label({ Text = "DMG " .. Format.abbrev(math.floor(Stats.dps(e.m.sp, e.m.lvl, e.m.stars, e.m.v, e.m.x6) + 0.5)) .. "/s", MaxText = 19, Size = UDim2.new(1, -8, 0.85, 0), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = dmg })
		UI.label({ Name = "PowerLbl", Text = "Power " .. Format.abbrev(e.p), TextColor3 = C.Gold, MaxText = 19, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 146), Parent = card })
		-- what this monster sells for (the capped price the server pays), shown only in Sell mode
		UI.label({ Name = "SellTag", Text = "Sells for " .. Format.abbrev(Stats.sellPrice(e.m.sp, e.m.lvl, e.m.v, snap.bestDepth)), TextColor3 = C.Gold, MaxText = 22, Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 144), Visible = false, Parent = card })
		UI.label({ Name = "Tick", Text = "IN", MaxText = 22, TextColor3 = C.Kelp, Size = UDim2.fromOffset(44, 28), Position = UDim2.fromOffset(6, 4), Parent = card })
		-- a sleeping monster (fainted in a fight) shows how long until it can fight again
		local sleepFor = (e.m.restUntil or 0) - State.now()
		if sleepFor > 0 then
			UI.label({ Name = "Zzz", Text = "Zzz " .. Format.time(sleepFor), MaxText = 20, TextColor3 = C.Coral, Size = UDim2.fromOffset(100, 24), Position = UDim2.new(1, -104, 0, 4), Parent = card })
		end
		cards[e.uid] = card
	end
	redraw()
	local nextPrice = Config.TEAM_SLOT_PRICES[snap.teamSlots - Config.TEAM_START + 1]
	UI.button({ Text = "Save Team", Color = C.Kelp, Size = UDim2.fromOffset(180, 50), Position = UDim2.new(1, -16, 1, -12), AnchorPoint = Vector2.new(1, 1), Parent = f }, function()
		State.action("Team", chosen)
		Menus.close()
		Hud.toast("Team saved!", C.Kelp)
	end)
	UI.button({ Text = "Auto Best", Color = C.Sea, Size = UDim2.fromOffset(130, 50), Position = UDim2.new(1, -206, 1, -12), AnchorPoint = Vector2.new(1, 1), Parent = f }, function()
		State.action("Team", {})
		Menus.close()
		Hud.toast("Your strongest monsters will fight", C.Kelp)
	end)
	-- a bright orange button that says what it does; it turns red while Sell mode is on
	local SELL_OFF, SELL_ON = Color3.fromRGB(255, 150, 40), Color3.fromRGB(235, 60, 60)
	sellBtn = UI.button({ Text = if sellMode then "SELLING!" else "Sell Monsters", Color = SELL_OFF, Size = UDim2.fromOffset(184, 50), Position = UDim2.new(0, 204, 1, -12), AnchorPoint = Vector2.new(0, 1), Parent = f }, function()
		sellMode = not sellMode
		teamSellMode = sellMode
		armed = nil
		UI.setText(sellBtn :: GuiObject, if sellMode then "SELLING!" else "Sell Monsters")
		;(sellBtn :: GuiObject).BackgroundColor3 = if sellMode then SELL_ON else SELL_OFF
		if sellMode then
			Hud.toast("Tap a monster twice to sell it", C.Coral)
		end
		redraw()
	end)
	if sellMode then
		(sellBtn :: GuiObject).BackgroundColor3 = SELL_ON
	end
	redraw()
	if nextPrice then
		UI.button({ Text = "+1 Slot  " .. Format.abbrev(nextPrice), Color = C.Gold, Size = UDim2.fromOffset(176, 50), Position = UDim2.new(0, 16, 1, -12), AnchorPoint = Vector2.new(0, 1), Parent = f }, function()
			local ok, msg = State.action("TeamSlot")
			Hud.toast(msg or "", if ok then C.Kelp else C.Coral)
			if ok then
				Menus.close()
			end
		end)
	end
end

---------------------------------------------------------------------------
-- "What is this?" card for the currencies (tap the chip, or the ? next to it)
---------------------------------------------------------------------------
local CURRENCY_INFO = {
	Coins = {
		icon = "Coin",
		color = C.Gold,
		what = "Your everyday money.",
		get = "Win battles (every kill pays, even in a loss), Free Gifts, and the Daily Chest.",
		use = "Buy eggs from the fishing rod, extra nests, ship upgrades and Workshop fittings.",
	},
	Pearls = {
		icon = "Pearl",
		color = C.Pearl,
		what = "A rare treasure. You will not find them in battles.",
		get = "Free Gifts (every few minutes you play), the Daily Chest, Missions, and the first time you discover each monster in the Index.",
		use = "Egg Shop eggs (Rare, Epic, Golden) and Tide Power spins.",
	},
	Shells = {
		icon = "Shell",
		color = Color3.fromRGB(255, 140, 40),
		what = "Tide Festival money. Only around while the festival runs.",
		get = "Free Gifts (some of them carry shells) and the Daily Chest, during the festival.",
		use = "Festival prizes at the Tide Festival stand. Spend them before the festival ends!",
	},
}

function Menus.currencyInfo(kind: string)
	local info = CURRENCY_INFO[kind]
	if not info then
		return
	end
	local _, body = window(kind, Vector2.new(540, 380), info.color)
	UI.new("ImageLabel", { BackgroundTransparency = 1, Image = Config.ICONS[info.icon], Size = UDim2.fromOffset(84, 84), Position = UDim2.fromOffset(6, 0), Parent = body })
	UI.label({ Text = info.what, Stroke = 0, TextColor3 = C.Ink, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, TextScaled = false, TextSize = 24, Size = UDim2.new(1, -110, 0, 84), Position = UDim2.fromOffset(100, 0), Parent = body })
	local function block(title: string, text: string, y: number, color: Color3)
		local p = UI.panel({ Size = UDim2.new(1, -8, 0, 100), Position = UDim2.fromOffset(4, y), Color = Color3.fromRGB(255, 249, 232), Parent = body })
		UI.plank({ Text = title, Color = color, Size = UDim2.fromOffset(150, 30), Position = UDim2.fromOffset(10, -10), MaxText = 20, Parent = p })
		UI.label({ Text = text, Stroke = 0, TextColor3 = C.Ink, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, TextScaled = false, TextSize = 20, Size = UDim2.new(1, -24, 1, -34), Position = UDim2.fromOffset(12, 28), Parent = p })
	end
	block("Where to get it", info.get, 94, C.Kelp)
	block("What it buys", info.use, 204, C.Sea)
end

---------------------------------------------------------------------------
-- Settings: music and sound-effect volume (saved with the player's data)
---------------------------------------------------------------------------
local volumeSaveQueued = false
local function saveVolume()
	if volumeSaveQueued then
		return
	end
	volumeSaveQueued = true
	task.delay(0.5, function()
		volumeSaveQueued = false
		State.action("Volume", { music = Sound.getVolume("music"), sfx = Sound.getVolume("sfx") })
	end)
end

function Menus.settings()
	local UserInputService = game:GetService("UserInputService")
	local f, body = window("Settings", Vector2.new(620, 240), C.Plank)
	local conns: { RBXScriptConnection } = {}
	f.Destroying:Connect(function()
		for _, c in conns do
			c:Disconnect()
		end
	end)

	local function row(title: string, kind: string, y: number)
		UI.label({ Text = title, Stroke = 0, TextColor3 = C.Ink, MaxText = 26, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(150, 40), Position = UDim2.fromOffset(12, y), Parent = body })
		local track = UI.new("Frame", { BackgroundColor3 = Color3.fromRGB(205, 182, 138), BorderSizePixel = 0, Size = UDim2.new(1, -350, 0, 18), Position = UDim2.new(0, 218, 0, y + 11), Parent = body }, { UI.corner(9), UI.stroke(2.5) })
		local fill = UI.new("Frame", { BackgroundColor3 = C.Sea, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = track }, { UI.corner(9) })
		local knob = UI.new("Frame", { BackgroundColor3 = C.Brass, Size = UDim2.fromOffset(34, 34), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), ZIndex = 3, Parent = track }, { UI.corner(17), UI.stroke(3) })
		local pct = UI.label({ Text = "", Stroke = 0, TextColor3 = C.Deep, MaxText = 24, Size = UDim2.fromOffset(64, 40), Position = UDim2.new(1, -70, 0, y), Parent = body })

		local function show(v: number)
			fill.Size = UDim2.fromScale(v, 1)
			knob.Position = UDim2.fromScale(v, 0.5)
			pct.Text = math.floor(v * 100 + 0.5) .. "%"
		end
		local function set(v: number)
			v = math.clamp(v, 0, 1)
			Sound.setVolume(kind, v)
			show(v)
		end
		show(Sound.getVolume(kind))

		-- -/+ step by 10% (handy on a controller), and the track itself drags
		UI.button({ Text = "-", Color = C.Coral, Radius = 12, Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(166, y), Parent = body }, function()
			set(math.floor(Sound.getVolume(kind) * 10 + 0.5) / 10 - 0.1)
			saveVolume()
		end)
		UI.button({ Text = "+", Color = C.Kelp, Radius = 12, Size = UDim2.fromOffset(40, 40), Position = UDim2.new(1, -120, 0, y), Parent = body }, function()
			set(math.floor(Sound.getVolume(kind) * 10 + 0.5) / 10 + 0.1)
			saveVolume()
		end)

		local hit = UI.new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, 30, 0, 44), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 4, Parent = track })
		local dragging = false
		local function fromX(x: number)
			local w = track.AbsoluteSize.X
			if w > 0 then
				set((x - track.AbsolutePosition.X) / w)
			end
		end
		hit.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				fromX(input.Position.X)
			end
		end)
		table.insert(conns, UserInputService.InputChanged:Connect(function(input: InputObject)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				fromX(input.Position.X)
			end
		end))
		table.insert(conns, UserInputService.InputEnded:Connect(function(input: InputObject)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
				dragging = false
				Sound.play("Click")
				saveVolume()
			end
		end))
	end

	row("Music", "music", 24)
	row("Sound FX", "sfx", 104)
end

---------------------------------------------------------------------------
-- Event
---------------------------------------------------------------------------
function Menus.event()
	local snap = State.snapshot
	local ev = Config.EVENT
	local f, body = window(ev.name, Vector2.new(700, 430), Color3.fromRGB(255, 140, 40))
	local left = ev.endsAt - State.now()
	local timer = UI.label({ Text = "", TextColor3 = C.Coral, Size = UDim2.new(1, 0, 0, 30), Parent = body })
	task.spawn(function()
		while timer.Parent do
			local s = ev.endsAt - State.now()
			timer.Text = if s > 0 then ("Ends in " .. string.format("%dd %dh %dm", s // 86400, (s % 86400) // 3600, (s % 3600) // 60)) else "Event over"
			task.wait(1)
		end
	end)
	local row = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 34), Parent = body })
	UI.new("ImageLabel", { BackgroundTransparency = 1, Image = Config.ICONS.Shell, Size = UDim2.fromOffset(44, 44), Position = UDim2.new(0.5, -80, 0, 0), Parent = row })
	UI.label({ Text = Format.abbrev(snap.shells) .. " Shells", TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(0, 200, 0, 36), Position = UDim2.new(0.5, -30, 0, 4), Parent = row })
	UI.label({ Text = "Shells come from Free Gifts and the Daily Chest during the festival. Trade them here!", Stroke = 0, TextColor3 = C.Ink, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 82), Parent = body })
	for i, it in ev.shop do
		local card = UI.panel({ Size = UDim2.fromOffset(200, 200), Position = UDim2.fromOffset((i - 1) * 222 + 10, 116), Color = Color3.fromRGB(255, 236, 210), Parent = body })
		local icon = if it.id == "FestivalEgg" then Config.ICONS.LuckEgg elseif it.id == "PearlBag" then Config.ICONS.Pearl else Config.ICONS.Heart
		UI.new("ImageLabel", { BackgroundTransparency = 1, Image = icon, Size = UDim2.fromOffset(80, 80), Position = UDim2.new(0.5, 0, 0, 6), AnchorPoint = Vector2.new(0.5, 0), Parent = card })
		UI.label({ Text = it.name, Size = UDim2.new(1, -10, 0, 26), Position = UDim2.fromOffset(5, 86), Parent = card })
		UI.label({ Text = it.desc, Stroke = 0, TextColor3 = C.Ink, Size = UDim2.new(1, -10, 0, 20), Position = UDim2.fromOffset(5, 112), Parent = card })
		UI.button({ Text = it.cost .. " Shells", Color = Color3.fromRGB(255, 140, 40), Size = UDim2.new(1, -20, 0, 42), Position = UDim2.new(0, 10, 1, -50), Parent = card }, function()
			local ok, msg = State.action("EventBuy", it.id)
			Hud.toast(msg or (if ok then "Bought!" else "Can't buy"), if ok then C.Kelp else C.Coral)
			if ok then
				Menus.event()
			end
		end)
	end
	local _ = f
	local _l = left
end

---------------------------------------------------------------------------
-- Powers
---------------------------------------------------------------------------
function Menus.powers()
	local snap = State.snapshot
	local f, body = window("Tide Powers", Vector2.new(780, 480), C.Gold)
	if snap.bestDepth < Config.POWERS_UNLOCK_DEPTH then
		UI.new("ImageLabel", { BackgroundTransparency = 1, Image = Config.ICONS.Lock, Size = UDim2.fromOffset(120, 120), Position = UDim2.new(0.5, 0, 0.3, 0), AnchorPoint = Vector2.new(0.5, 0.5), Parent = body })
		UI.label({ Text = "Reach Depth " .. Config.POWERS_UNLOCK_DEPTH .. " to unlock Powers!", Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0.6, 0), Parent = body })
		UI.label({ Text = "Your best: Depth " .. snap.bestDepth, TextColor3 = C.Gold, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0.6, 46), Parent = body })
		return
	end
	-- wheel (list of powers lights up in turn while spinning)
	local wheel = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(250, 330), Parent = body })
	local rows: { [string]: Frame } = {}
	for i, p in Config.POWERS do
		local r = UI.panel({ Size = UDim2.fromOffset(250, 48), Position = UDim2.fromOffset(0, (i - 1) * 54), Color = p.color, Parent = wheel })
		UI.label({ Text = p.name .. "  " .. p.desc, Size = UDim2.new(1, -16, 0.6, 0), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = r })
		rows[p.id] = r
	end
	local picked: string? = nil
	local scroll = UI.new("ScrollingFrame", { BackgroundTransparency = 1, Size = UDim2.new(1, -270, 1, -70), Position = UDim2.fromOffset(270, 0), ScrollBarThickness = 8, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), BorderSizePixel = 0, Parent = body }, { UI.new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }) })
	UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(110, 130), CellPadding = UDim2.fromOffset(8, 8), Parent = scroll })
	local cards = {}
	for _, e in sortedMonsters(snap) do
		local card = UI.button({ Text = "", Color = Color3.fromRGB(240, 246, 255), Size = UDim2.fromOffset(110, 130), Parent = scroll }, function()
			picked = e.uid
			for uid, c in cards do
				local st = c:FindFirstChildOfClass("UIStroke")
				if st then
					st.Color = if uid == picked then C.Gold else C.Ink
				end
			end
		end)
		creatureView(card, e.m.sp, UDim2.new(1, 0, 0, 80))
		UI.label({ Text = "Lv." .. e.m.lvl, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 80), Parent = card })
		UI.label({ Text = e.m.power or "No power", TextColor3 = C.Gold, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 102), Parent = card })
		cards[e.uid] = card
	end
	local cost = if snap.spins > 0 then ("Free Spin (" .. snap.spins .. ")") else ("Spin  " .. Config.POWER_SPIN_PEARLS .. " Pearls")
	local spinning = false
	UI.button({ Text = cost, Color = C.Kelp, Size = UDim2.fromOffset(240, 54), Position = UDim2.new(1, -16, 1, -12), AnchorPoint = Vector2.new(1, 1), Parent = f }, function()
		if spinning then
			return
		end
		if not picked then
			Hud.toast("Pick a monster first", C.Coral)
			return
		end
		local ok, result = State.action("Spin", picked)
		if not ok then
			Hud.toast(result or "Can't spin", C.Coral)
			return
		end
		spinning = true
		-- light up rows faster then slower, landing on the result
		local order = {}
		for _, p in Config.POWERS do
			table.insert(order, p.id)
		end
		local steps = 18 + table.find(order, result) :: number
		for k = 1, steps do
			local id = order[(k - 1) % #order + 1]
			for pid, r in rows do
				r.BackgroundTransparency = if pid == id then 0 else 0.6
			end
			Sound.play("Click", 0.4, 1 + k * 0.02)
			task.wait(0.04 + (k / steps) ^ 2 * 0.25)
		end
		Sound.play("Win", 0.7)
		Hud.toast("Power: " .. tostring(result) .. "!", C.Gold)
		spinning = false
		task.wait(0.8)
		if open == f then
			Menus.powers()
		end
	end)
	UI.button({ Text = "5 Spins  R$" .. Config.PRODUCTS.PowerSpins.price, Color = C.Pearl, Size = UDim2.fromOffset(200, 54), Position = UDim2.new(1, -268, 1, -12), AnchorPoint = Vector2.new(1, 1), Parent = f }, function()
		detail("Product", "PowerSpins")
	end)
end

---------------------------------------------------------------------------
-- Gifts (playtime + daily)
---------------------------------------------------------------------------
function Menus.gifts()
	local snap = State.snapshot
	-- compact: 2 rows of cards, then the social buttons, then the Daily Chest: 530 units tall so
	-- the whole window fits a phone (the menu is scaled to fit on top of this)
	local _, body = window("Free Gifts", Vector2.new(760, 530), C.Kelp)
	local grid = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 300), Parent = body })
	UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(170, 140), CellPadding = UDim2.fromOffset(10, 10), Parent = grid })
	local labels = {}
	for i, g in Config.GIFTS do
		local c = UI.panel({ Size = UDim2.fromOffset(170, 140), Color = Color3.fromRGB(255, 244, 216), Parent = grid })
		local icon = if g.coins then Config.ICONS.Coin elseif g.pearls then Config.ICONS.Pearl elseif g.spins then Config.ICONS.Power else Config.ICONS.LuckEgg
		local what = if g.coins then Format.abbrev(g.coins) .. " Coins" elseif g.pearls then g.pearls .. " Pearls" elseif g.spins then "Power Spin" else "Mystery Egg"
		if g.spell then
			what ..= " + Spell"
		end
		UI.new("ImageLabel", { BackgroundTransparency = 1, Image = icon, Size = UDim2.fromOffset(44, 44), Position = UDim2.new(0.5, 0, 0, 4), AnchorPoint = Vector2.new(0.5, 0), Parent = c })
		UI.label({ Text = what, Size = UDim2.new(1, -10, 0, 22), Position = UDim2.fromOffset(5, 50), Parent = c })
		-- bonus line: festival shells ride along on some gifts
		if g.shells then
			UI.label({ Text = "+ " .. g.shells .. " Shells", TextColor3 = Color3.fromRGB(255, 160, 60), MaxText = 16, Size = UDim2.new(1, -10, 0, 18), Position = UDim2.fromOffset(5, 72), Parent = c })
		end
		local btn = UI.button({ Text = "", Color = C.Kelp, Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 1, -38), Parent = c }, function()
			local ok, msg = State.action("Gift", i)
			Hud.toast(msg or "", if ok then C.Kelp else C.Coral)
		end)
		labels[i] = btn
	end
	-- social row: joining the group is just a button (no reward for joining); friends who play in
	-- your server each add +10% battle coins, up to +30% (Config.FRIEND_BOOST / FRIEND_BOOST_MAX)
	UI.button({ Text = "Join the Crew", Color = C.Sea, Size = UDim2.new(0.5, -16, 0, 48), Position = UDim2.fromOffset(10, 308), Parent = body }, function()
		pcall(function()
			game:GetService("GroupService"):PromptJoinAsync(Config.GROUP_ID)
		end)
	end)
	UI.label({ Text = "Friends in your server give +10% coins each (up to +30%)", Stroke = 0, TextColor3 = C.Ink, MaxText = 20, Size = UDim2.new(1, -20, 0, 24), Position = UDim2.fromOffset(10, 360), Parent = body })
	UI.button({ Text = "Invite Friends", Color = Color3.fromRGB(255, 140, 60), Size = UDim2.new(0.5, -16, 0, 48), Position = UDim2.new(0.5, 6, 0, 308), Parent = body }, function()
		local SocialService = game:GetService("SocialService")
		local ok, can = pcall(function()
			return SocialService:CanSendGameInviteAsync(player)
		end)
		if ok and can then
			pcall(function()
				SocialService:PromptGameInvite(player)
			end)
		else
			Hud.toast("Invites aren't available right now", C.Coral)
		end
	end)
	local daily = UI.button({ Text = "Daily Chest", Color = C.Gold, Size = UDim2.new(1, -20, 0, 52), Position = UDim2.new(0, 10, 1, -56), Parent = body }, function()
		local ok, msg = State.action("Daily")
		Hud.toast(msg or "", if ok then C.Kelp else C.Coral)
	end)
	-- Ready and claimed must look nothing alike (same size either way): ready = a green face, a
	-- border pulsing gold/white and a red "!" badge; claimed = a muted grey face with a countdown.
	local dailyGrad = daily:FindFirstChildOfClass("UIGradient")
	local dailyStroke = daily:FindFirstChildOfClass("UIStroke")
	local dailyBadge = UI.new("Frame", { BackgroundColor3 = C.Coral, Size = UDim2.fromOffset(30, 30), Position = UDim2.new(1, -8, 0, 4), AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, ZIndex = 5, Parent = daily }, { UI.corner(15), UI.stroke(2.5) })
	UI.label({ Text = "!", Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.1), ZIndex = 6, Parent = dailyBadge })
	local dailyPulse: Tween? = nil
	local dailyReady: boolean? = nil
	daily.Destroying:Connect(function()
		if dailyPulse then
			dailyPulse:Cancel()
		end
	end)
	local function setDailyReady(ready: boolean)
		if dailyReady == ready then
			return
		end
		dailyReady = ready
		local face = if ready then C.Kelp else C.Muted
		if dailyGrad then
			dailyGrad.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, face:Lerp(Color3.new(1, 1, 1), 0.25)),
				ColorSequenceKeypoint.new(1, face:Lerp(Color3.new(0, 0, 0), 0.12)),
			})
		end
		dailyBadge.Visible = ready
		if dailyPulse then
			dailyPulse:Cancel()
			dailyPulse = nil
		end
		if dailyStroke then
			dailyStroke.Color = C.Ink
			if ready then
				dailyPulse = game:GetService("TweenService"):Create(dailyStroke, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Color = Color3.fromRGB(255, 245, 170) })
				;(dailyPulse :: Tween):Play()
			end
		end
	end
	task.spawn(function()
		while daily.Parent do
			local s = State.snapshot
			local played = State.now() - (s.sessionStart or State.now())
			for i, g in Config.GIFTS do
				local b = labels[i]
				if s.giftsClaimed and s.giftsClaimed[i] then
					UI.setText(b, "Claimed")
				elseif played >= g.min * 60 then
					UI.setText(b, "CLAIM!")
				else
					UI.setText(b, Format.time(g.min * 60 - played))
				end
			end
			local today = State.now() // 86400
			local claimed = s.dailyDay == today
			setDailyReady(not claimed)
			if claimed then
				-- the chest resets at the next UTC midnight (the server's day boundary)
				local left = (today + 1) * 86400 - State.now()
				UI.setText(daily, "Daily Chest: next in " .. string.format("%dh %02dm", left // 3600, (left % 3600) // 60))
			else
				-- same rule as ExtrasService.claimDaily: the streak only carries on from yesterday
				local day = if s.dailyDay == today - 1 then (s.dailyStreak or 0) + 1 else 1
				UI.setText(daily, "OPEN DAILY CHEST! (Day " .. day .. ")")
			end
			task.wait(1)
		end
	end)
	local _ = snap
end

---------------------------------------------------------------------------
-- Spellbook (harbour)
---------------------------------------------------------------------------
function Menus.spellbook()
	local snap = State.snapshot
	local PURPLE = Color3.fromRGB(150, 90, 235)
	local _, body = window("Spellbook", Vector2.new(920, 540), PURPLE)

	local function known(sp: any): boolean
		local s = State.snapshot
		return (tonumber(s.spells and s.spells[sp.id]) or 0) > 0 or (s.spellsFound and s.spellsFound[sp.id] == true) or (s.spellUntil and s.spellUntil[sp.id] ~= nil)
	end
	local function haveOf(sp: any): number
		return tonumber(State.snapshot.spells and State.snapshot.spells[sp.id]) or 0
	end

	-- sorted: rarest first among the spells you know, unknowns after, each by rarity
	local list = {}
	for _, sp in Config.SPELLS do
		table.insert(list, sp)
	end
	table.sort(list, function(a, b)
		if a.rarity ~= b.rarity then
			return a.rarity < b.rarity
		end
		return a.id < b.id
	end)

	-- left: found counter + grid of cards
	local found = 0
	for _, sp in list do
		if known(sp) then
			found += 1
		end
	end
	local counter = UI.label({ Text = "Found " .. found .. " / " .. #list, MaxText = 24, Size = UDim2.new(0.56, 0, 0, 30), Position = UDim2.fromOffset(0, 0), TextXAlignment = Enum.TextXAlignment.Left, Parent = body })
	local gridHolder = UI.panel({ Size = UDim2.new(0.56, 0, 1, -38), Position = UDim2.fromOffset(0, 36), Color = Color3.fromRGB(215, 205, 250), Parent = body })
	local grid = UI.new("ScrollingFrame", { BackgroundTransparency = 1, Size = UDim2.new(1, -12, 1, -12), Position = UDim2.fromOffset(6, 6), ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), BorderSizePixel = 0, Parent = gridHolder }, { UI.new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }) })
	UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(104, 124), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })

	-- right: the selected spell
	local detail = UI.panel({ Size = UDim2.new(0.42, 0, 1, 0), Position = UDim2.fromScale(0.58, 0), Color = Color3.fromRGB(245, 240, 255), Parent = body })
	local iconBack = UI.panel({ Size = UDim2.fromOffset(130, 130), Position = UDim2.new(0.5, 0, 0, 14), AnchorPoint = Vector2.new(0.5, 0), Color = C.Sea, Radius = 30, Parent = detail })
	local bigIcon = UI.new("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(0.78, 0.78), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = iconBack })
	local nameL = UI.label({ Text = "", MaxText = 30, Size = UDim2.new(1, -20, 0, 38), Position = UDim2.fromOffset(10, 154), Parent = detail })
	local rarL = UI.label({ Text = "", MaxText = 20, Size = UDim2.new(1, -20, 0, 24), Position = UDim2.fromOffset(10, 194), Parent = detail })
	local descL = UI.label({ Text = "", Stroke = 0, TextColor3 = C.Ink, MaxText = 22, TextWrapped = true, Size = UDim2.new(1, -30, 0, 60), Position = UDim2.fromOffset(15, 224), Parent = detail })
	local haveL = UI.label({ Text = "", Stroke = 0, TextColor3 = C.Deep, MaxText = 20, Size = UDim2.new(1, -30, 0, 24), Position = UDim2.fromOffset(15, 288), Parent = detail })
	local activeL = UI.label({ Text = "", Stroke = 0, TextColor3 = Color3.fromRGB(30, 150, 80), MaxText = 18, TextWrapped = true, Size = UDim2.new(1, -30, 0, 40), Position = UDim2.fromOffset(15, 314), Parent = detail })
	local selected = list[1]
	local castBtn = UI.button({ Text = "CAST!", Color = PURPLE, Size = UDim2.new(1, -40, 0, 56), Position = UDim2.new(0, 20, 1, -70), Parent = detail }, function()
		local ok, msg = State.action("SpellCast", selected.id)
		if ok then
			Sound.play("Win", 0.7)
			Hud.spellCast(selected.id)
		else
			Hud.toast(msg or "", C.Coral)
		end
	end)

	-- Combine: 3 cards of the selected spell's rarity -> 1 random card of the next rarity
	local function cardsOfRarity(r: number): number
		local n = 0
		for _, sp in Config.SPELLS do
			if sp.rarity == r then
				n += haveOf(sp)
			end
		end
		return n
	end
	local combineBtn: GuiObject
	local function updateCombine()
		local r = selected.rarity
		local have = cardsOfRarity(r)
		local can = r < #Config.RARITY and have >= Config.SPELL_COMBINE
		combineBtn.Visible = r < #Config.RARITY
		UI.setText(combineBtn, "Combine " .. have .. "/" .. Config.SPELL_COMBINE)
		combineBtn.BackgroundColor3 = if can then Color3.new(1, 1, 1) else C.Muted
	end
	combineBtn = UI.button({ Text = "Combine", Color = C.Kelp, Size = UDim2.fromOffset(190, 34), Position = UDim2.new(0.56, 0, 0, -2), AnchorPoint = Vector2.new(1, 0), Parent = body }, function()
		local ok, msg = State.action("SpellCombine", selected.rarity)
		Hud.toast(msg or "", if ok then C.Kelp else C.Coral)
		if ok then
			Sound.play("Win", 0.6)
			task.wait(0.7) -- (the new snapshot arrives a moment later), then redraw the book
			Menus.spellbook()
		end
	end)

	local cards: { [string]: { card: TextButton, stroke: UIStroke } } = {}
	local function show(sp: any)
		selected = sp
		local r = Config.RARITY[sp.rarity]
		local isKnown = known(sp)
		local have = haveOf(sp)
		bigIcon.Image = Config.ICONS[sp.icon]
		bigIcon.ImageColor3 = if isKnown then Color3.new(1, 1, 1) else Color3.fromRGB(20, 26, 50)
		iconBack:FindFirstChildOfClass("UIGradient").Color = ColorSequence.new(if isKnown then r.color else Color3.fromRGB(120, 125, 150))
		nameL.Text = if isKnown then sp.name else "???"
		-- Spellbook set: find every spell of this rarity for a pearl reward
		local setTotal, setHave = 0, 0
		for _, o in Config.SPELLS do
			if o.rarity == sp.rarity then
				setTotal += 1
				if known(o) then
					setHave += 1
				end
			end
		end
		local paid = State.snapshot.spellSets and State.snapshot.spellSets[tostring(sp.rarity)]
		rarL.Text = string.upper(r.name) .. " SPELL  ·  Set " .. setHave .. "/" .. setTotal .. (if paid then " done" else (" = " .. (Config.SPELL_SETS[sp.rarity] or 0) .. " pearls"))
		updateCombine()
		rarL.TextColor3 = r.color
		descL.Text = if isKnown then (sp.desc .. "  ·  " .. sp.minutes .. " min") else "Not found yet! Find it in the Gift Chest and daily chest."
		haveL.Text = if isKnown then ("You have " .. have) else ""
		castBtn.Visible = have > 0
		UI.pop(iconBack, 0.8)
		for id, c in cards do
			c.stroke.Thickness = if id == sp.id then 6 else 3.5
		end
	end
	for i, sp in list do
		local r = Config.RARITY[sp.rarity]
		local isKnown = known(sp)
		local have = haveOf(sp)
		local card = UI.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = if isKnown then Color3.new(1, 1, 1) else Color3.fromRGB(190, 195, 215), BorderSizePixel = 0, LayoutOrder = i, Parent = grid }, { UI.corner(16) })
		local st = UI.stroke(3.5, if isKnown then r.color else Color3.fromRGB(110, 115, 140))
		st.Parent = card
		-- rarity ribbon on top
		UI.new("Frame", { BackgroundColor3 = if isKnown then r.color else Color3.fromRGB(130, 135, 160), BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 8), Parent = card }, { UI.new("UICorner", { CornerRadius = UDim.new(0, 8) }) })
		UI.new("ImageLabel", { BackgroundTransparency = 1, Image = Config.ICONS[sp.icon], ImageColor3 = if isKnown then Color3.new(1, 1, 1) else Color3.fromRGB(20, 26, 50), Size = UDim2.fromOffset(60, 60), Position = UDim2.new(0.5, 0, 0, 14), AnchorPoint = Vector2.new(0.5, 0), Parent = card })
		UI.label({ Text = if isKnown then sp.name else "???", MaxText = 17, TextWrapped = true, Size = UDim2.new(1, -10, 0, 40), Position = UDim2.fromOffset(5, 78), Parent = card })
		if have > 0 then
			local badge = UI.panel({ Size = UDim2.fromOffset(34, 24), Position = UDim2.new(1, -4, 0, 12), AnchorPoint = Vector2.new(1, 0), Color = C.Gold, Radius = 10, Parent = card })
			UI.label({ Text = "x" .. have, MaxText = 16, Size = UDim2.fromScale(1, 0.85), Position = UDim2.fromScale(0, 0.08), Parent = badge })
		end
		card.Activated:Connect(function()
			Sound.play("Click")
			show(sp)
		end)
		cards[sp.id] = { card = card, stroke = st }
	end
	-- open on the first spell you hold
	for _, sp in list do
		if haveOf(sp) > 0 then
			selected = sp
			break
		end
	end
	show(selected)
	local me = open
	task.spawn(function()
		while me and me.Parent and open == me do
			local s2 = State.snapshot
			local lines = {}
			for _, sp in Config.SPELLS do
				local leftS = ((s2.spellUntil and s2.spellUntil[sp.id]) or 0) - State.now()
				if leftS > 0 then
					table.insert(lines, sp.name .. " " .. Format.time(leftS))
				end
			end
			activeL.Text = if #lines > 0 then ("Active: " .. table.concat(lines, ", ")) else ""
			haveL.Text = if known(selected) then ("You have " .. haveOf(selected)) else ""
			castBtn.Visible = haveOf(selected) > 0
			updateCombine()
			local n = 0
			for _, sp in list do
				if known(sp) then
					n += 1
				end
			end
			counter.Text = "Found " .. n .. " / " .. #list
			task.wait(0.5)
		end
	end)
	Sound.play("Hatch", 0.5, 1.3)
	local _ = snap
end

---------------------------------------------------------------------------
-- Ship Workshop (board on your deck): fittings that help a little in battle + paint
---------------------------------------------------------------------------
function Menus.workshop()
	local frame, body = window("Ship Workshop", Vector2.new(880, 580), Color3.fromRGB(70, 150, 235))
	-- a way back to the Dockyard (this window replaced it): a brass-edged button on the frame's top left
	UI.button({ Text = "◀ Back", Color = C.Sea, Size = UDim2.fromOffset(118, 44), Position = UDim2.fromOffset(22, 8), ZIndex = 8, Parent = frame }, function()
		Sound.play("Click")
		Menus.dockyard()
	end)
	local function redraw()
		-- clear only the content: the body's own parchment gradient, corners, outline and padding are
		-- children too, and wiping them turned the window plain white and pushed the content off the edge
		for _, ch in body:GetChildren() do
			if ch:IsA("GuiObject") then
				ch:Destroy()
			end
		end
		local snap = State.snapshot
		local fits = snap.fittings or {}
		-- left: the four fittings
		UI.label({ Text = "Fittings", MaxText = 26, Size = UDim2.new(0.52, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, Parent = body })
		for i, id in Config.FITTING_ORDER do
			local def = Config.FITTINGS[id]
			local lvl = fits[id] or 0
			local col, row = (i - 1) % 2, (i - 1) // 2
			local card = UI.panel({ Size = UDim2.new(0.25, -8, 0, 206), Position = UDim2.new(0.26 * col, 0, 0, 36 + row * 216), Color = Color3.fromRGB(230, 242, 255), Parent = body })
			UI.new("ImageLabel", { BackgroundTransparency = 1, Image = Config.ICONS[def.icon], Size = UDim2.fromOffset(54, 54), Position = UDim2.new(0.5, 0, 0, 6), AnchorPoint = Vector2.new(0.5, 0), Parent = card })
			UI.label({ Text = def.name, MaxText = 20, Size = UDim2.new(1, -10, 0, 26), Position = UDim2.fromOffset(5, 62), Parent = card })
			UI.label({ Text = def.desc, Stroke = 0, TextColor3 = C.Ink, MaxText = 15, TextWrapped = true, Size = UDim2.new(1, -12, 0, 34), Position = UDim2.fromOffset(6, 90), Parent = card })
			UI.label({ Text = "Level " .. lvl .. " / " .. def.max, Stroke = 0, TextColor3 = C.Deep, MaxText = 18, Size = UDim2.new(1, -10, 0, 22), Position = UDim2.fromOffset(5, 128), Parent = card })
			if lvl >= def.max then
				UI.label({ Text = "MAX", TextColor3 = C.Gold, MaxText = 24, Size = UDim2.new(1, -10, 0, 30), Position = UDim2.new(0, 5, 1, -36), Parent = card })
			else
				local price = Stats.fittingPrice(id, lvl)
				UI.button({ Text = Format.abbrev(price) .. " Coins", Color = if snap.coins >= price then C.Kelp else C.Muted, Size = UDim2.new(1, -16, 0, 38), Position = UDim2.new(0, 8, 1, -46), Parent = card }, function()
					local ok, msg = State.action("Workshop", { kind = "fit", id = id })
					Hud.toast(msg or "", if ok then C.Kelp else C.Coral)
					if ok then
						Sound.play("Upgrade", 0.8)
						task.defer(redraw)
					end
				end)
			end
		end
		-- right: paint
		local right = UI.panel({ Size = UDim2.new(0.46, 0, 1, -4), Position = UDim2.fromScale(0.54, 0), Color = Color3.fromRGB(245, 240, 255), Parent = body })
		UI.label({ Text = "Paint your ship", MaxText = 26, Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 6), TextXAlignment = Enum.TextXAlignment.Left, Parent = right })
		local function swatches(title: string, slot: string, list: { any }, y: number)
			UI.label({ Text = title, Stroke = 0, TextColor3 = C.Deep, MaxText = 20, Size = UDim2.new(1, -20, 0, 24), Position = UDim2.fromOffset(10, y), TextXAlignment = Enum.TextXAlignment.Left, Parent = right })
			local chosen = (snap.paint or {})[slot]
			local owned = snap.paintOwned or {}
			for k, p in list do
				local sx, sy = 14 + ((k - 1) % 3) * 108, y + 28 + ((k - 1) // 3) * 98
				local sw = UI.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = p.color, Size = UDim2.fromOffset(84, 64), Position = UDim2.fromOffset(sx, sy), Parent = right }, { UI.corner(14), UI.stroke(if chosen == p.id then 6 else 3.5, if chosen == p.id then C.Gold else C.Ink) })
				local note = if owned[p.id] then (if chosen == p.id then "Using" else "Owned") else Format.abbrev(p.price)
				UI.label({ Text = note, MaxText = 15, Size = UDim2.fromOffset(84, 20), Position = UDim2.fromOffset(sx, sy + 68), TextColor3 = if owned[p.id] then C.Kelp else C.Gold, Parent = right })
				sw.Activated:Connect(function()
					Sound.play("Click")
					local ok, msg = State.action("Workshop", { kind = "paint", slot = slot, id = p.id })
					Hud.toast(msg or "", if ok then C.Kelp else C.Coral)
					if ok then
						task.defer(redraw)
					end
				end)
			end
		end
		swatches("Sail", "sail", Config.PAINTS.Sail, 40)
		swatches("Hull stripe", "stripe", Config.PAINTS.Stripe, 40 + 28 + 196 + 12)
	end
	redraw()
end

---------------------------------------------------------------------------
-- Dockyard (harbour): the ship's store. Egg Luck, Fast Reel and the Shipwright are bought here
-- (the server's "Upgrade" action); the fourth card opens the Ship Workshop.
---------------------------------------------------------------------------
function Menus.dockyard()
	local frame, body = window("Dockyard", Vector2.new(880, 480), Color3.fromRGB(70, 150, 255))
	local function redraw()
		-- clear only the content (see Menus.workshop): keep the body's parchment, corners and padding
		for _, ch in body:GetChildren() do
			if ch:IsA("GuiObject") then
				ch:Destroy()
			end
		end
		local snap = State.snapshot
		if not snap then
			return
		end
		local function card(i: number, icon: string, name: string, desc: string, status: string, btn: string, canBuy: boolean, onClick: () -> ())
			local c = UI.panel({ Size = UDim2.new(0.25, -10, 0, 340), Position = UDim2.new(0.25 * (i - 1), 5, 0, 0), Color = Color3.fromRGB(230, 242, 255), Parent = body })
			UI.new("ImageLabel", { BackgroundTransparency = 1, Image = icon, Size = UDim2.fromOffset(72, 72), Position = UDim2.new(0.5, 0, 0, 8), AnchorPoint = Vector2.new(0.5, 0), Parent = c })
			UI.label({ Text = name, MaxText = 24, Size = UDim2.new(1, -10, 0, 30), Position = UDim2.fromOffset(5, 86), Parent = c })
			UI.label({ Text = desc, Stroke = 0, TextColor3 = C.Ink, MaxText = 16, TextWrapped = true, Size = UDim2.new(1, -16, 0, 52), Position = UDim2.fromOffset(8, 120), Parent = c })
			UI.label({ Text = status, Stroke = 0, TextColor3 = C.Deep, MaxText = 18, TextWrapped = true, Size = UDim2.new(1, -16, 0, 50), Position = UDim2.fromOffset(8, 180), Parent = c })
			UI.button({ Text = btn, Color = if canBuy then C.Kelp else C.Muted, Size = UDim2.new(1, -20, 0, 48), Position = UDim2.new(0, 10, 1, -58), Parent = c }, onClick)
		end
		local function buy(id: string)
			return function()
				local ok = State.action("Upgrade", id) -- the server toasts what happened
				if ok then
					Sound.play("Upgrade", 0.8)
				end
			end
		end
		local ups = snap.upgrades or {}
		-- Egg Luck
		local luck = ups.Luck or 0
		local luckPrice = Stats.upgradePrice("Luck", luck)
		card(1, Config.ICONS.LuckEgg, Config.UPGRADES.Luck.name, Config.UPGRADES.Luck.desc,
			"Level " .. luck .. " / " .. Config.UPGRADES.Luck.max .. "\n+" .. luck * 10 .. "% luck" .. (if luckPrice then "  >  +" .. (luck + 1) * 10 .. "%" else ""),
			if luckPrice then Format.abbrev(luckPrice) .. " Coins" else "MAX", luckPrice ~= nil and snap.coins >= luckPrice, buy("Luck"))
		-- Fast Reel
		local reel = ups.Pedestals or 1
		local reelPrice = Stats.upgradePrice("Pedestals", reel)
		card(2, Config.ICONS.Pedestal, Config.UPGRADES.Pedestals.name, Config.UPGRADES.Pedestals.desc,
			"Level " .. reel .. " / " .. Config.UPGRADES.Pedestals.max .. "\n-" .. (reel - 1) * 8 .. "% reel time" .. (if reelPrice then "  >  -" .. reel * 8 .. "%" else ""),
			if reelPrice then Format.abbrev(reelPrice) .. " Coins" else "MAX", reelPrice ~= nil and snap.coins >= reelPrice, buy("Pedestals"))
		-- Shipwright
		local tier = snap.shipTier or 0
		local nextTier = tier + 1
		local shipStatus, shipBtn, shipCan = "", "MAX", false
		if nextTier > #Config.SHIP_TIERS then
			shipStatus = "Royal Flagship!\nEvery upgrade built"
		else
			shipStatus = "Tier " .. nextTier .. " / " .. #Config.SHIP_TIERS .. "\nNext: " .. Config.SHIP_TIERS[nextTier]
			if snap.bestDepth < Stats.shipTierDepth(nextTier) then
				shipBtn = "Clear stage " .. (Stats.shipTierStage(nextTier) - 2)
			else
				local p = Stats.shipTierPrice(nextTier)
				shipBtn = Format.abbrev(p) .. " Coins"
				shipCan = snap.coins >= p
			end
		end
		card(3, Config.ICONS.Event, "Shipwright", "A better-looking ship, a little more coins and faster hatching with every tier.", shipStatus, shipBtn, shipCan, buy("Ship"))
		-- Ship Workshop
		card(4, Config.ICONS.Shop, "Ship Workshop", "Cannons, hull plating and paint. Small battle boosts and a ship that is yours.", "Fittings + paint", "Open", true, function()
			Sound.play("Click")
			Menus.workshop()
		end)
		UI.label({ Text = 'You have <font color="#FFCD32">' .. Format.abbrev(snap.coins) .. " coins</font>. Battle to earn more!", Stroke = 0, TextColor3 = C.Ink, MaxText = 18, Size = UDim2.new(1, -12, 0, 28), Position = UDim2.fromOffset(6, 352), Parent = body })
	end
	redraw()
	local conn: RBXScriptConnection
	conn = State.Changed:Connect(function()
		if open ~= frame then
			conn:Disconnect()
			return
		end
		redraw()
	end)
end

---------------------------------------------------------------------------
-- Egg Shop (harbour)
---------------------------------------------------------------------------
function Menus.eggShop()
	local _, body = window("Egg Shop", Vector2.new(700, 400), C.Sea)
	local have = UI.label({ Text = 'You have <font color="#C896FF">' .. Format.abbrev(State.snapshot.pearls) .. " pearls</font>. Earn more from Free Gifts, the Daily Chest, Missions and new Index monsters.", Stroke = 0, TextColor3 = C.Ink, MaxText = 18, Size = UDim2.new(1, -12, 0, 24), Position = UDim2.fromOffset(6, 296), Parent = body })
	local _h = have
	for i, it in Config.EGG_SHOP do
		local card = UI.panel({ Size = UDim2.fromOffset(204, 290), Position = UDim2.fromOffset((i - 1) * 222 + 6, 0), Color = Color3.fromRGB(230, 242, 255), Parent = body })
		local rarity = Config.RARITY[it.tier]
		local sample = Config.TIER_OF.Tide[it.tier]
		local vp = creatureView(card, sample, UDim2.new(1, 0, 0, 120), UDim2.fromOffset(0, 6), true)
		local _ = vp
		UI.label({ Text = it.name, TextColor3 = if it.variant then C.Gold else rarity.color, Size = UDim2.new(1, -10, 0, 30), Position = UDim2.fromOffset(5, 130), Parent = card })
		UI.label({ Text = it.desc, Stroke = 0, TextColor3 = C.Ink, MaxText = 20, Size = UDim2.new(1, -10, 0, 40), Position = UDim2.fromOffset(5, 164), Parent = card })
		UI.button({ Text = it.pearls .. " Pearls", Color = C.Pearl, Size = UDim2.new(1, -20, 0, 48), Position = UDim2.new(0, 10, 1, -58), Parent = card }, function()
			local ok, msg = State.action("EggShop", it.id)
			Hud.toast(msg or "", if ok then C.Kelp else C.Coral)
			if ok then
				Sound.play("Buy", 0.7)
			end
		end)
	end
end

---------------------------------------------------------------------------
-- Captain Coral, the Guide at the lighthouse: a short, paged "how the game works"
---------------------------------------------------------------------------
local GUIDE_PAGES = {
	{ icon = "Boss", title = "Ahoy, Tamer!", text = "Welcome to <font color=\"#FFCD32\">Merge Sea Monsters</font>! Fish up eggs, hatch sea monsters, <font color=\"#FFCD32\">FUSE</font> them into stronger ones and send your team diving. Reach <font color=\"#FFCD32\">Depth " .. Config.FINAL_DEPTH .. "</font> to save your friend from Maw, the Abyss King!" },
	{ icon = "LuckEgg", title = "1. Fish for Eggs", text = "Go to the <font color=\"#FFCD32\">fishing rod</font> on your ship. It dives through the sea zones, and the deeper it goes the rarer the egg. Buy the egg on a pedestal with <font color=\"#FFCD32\">coins</font> and carry it to a <font color=\"#FFCD32\">nest</font>." },
	{ icon = "Heart", title = "2. Hatch and Fuse", text = "When the timer ends, <font color=\"#FFCD32\">open</font> your egg. To <font color=\"#FFCD32\">FUSE</font>, pick one monster and then another of the <font color=\"#FFCD32\">same level</font>. Both are used up and one new, stronger monster comes out!" },
	{ icon = "Swords", title = "3. Dive and Fight", text = "Press <font color=\"#FFCD32\">FIGHT!</font> and your team battles by itself. Every 15 depths is a <font color=\"#FFCD32\">boss</font> with a timer. You earn coins and pearls even when you lose, and your team keeps fighting while you are away." },
	{ icon = "Pedestal", title = "4. Upgrade Your Ship", text = "The <font color=\"#FFCD32\">Dockyard</font> in the harbour sells <font color=\"#FFCD32\">Egg Luck</font>, a <font color=\"#FFCD32\">faster reel</font>, ship upgrades and paint. Fuse " .. Config.FLOOR2.fuses .. " times and save " .. Format.abbrev(Config.FLOOR2.coins) .. " coins to unlock the <font color=\"#FFCD32\">Quarterdeck</font> with extra nests." },
	{ icon = "Shop", title = "5. Explore the Harbour", text = "<font color=\"#FFCD32\">Treasure Shop</font>: boosts and codes. <font color=\"#FFCD32\">Egg Shop</font>: rare eggs for pearls. <font color=\"#FFCD32\">Museum</font>: your monster index. <font color=\"#FFCD32\">Power Shrine</font> and <font color=\"#FFCD32\">Spellbook</font>: buffs. A red <font color=\"#FF5A5A\">!</font> means something is waiting for you." },
	{ icon = "Gift", title = "Free Stuff!", text = "Your ship has a <font color=\"#FFCD32\">Gift Chest</font> with presents for playing and a daily chest. Only you can board your ship, so everything on it is yours. Good luck, Captain!" },
}

function Menus.guide()
	local page = 1
	local _, body = window("Captain Coral", Vector2.new(740, 430), C.Gold)
	local icon = UI.new("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(120, 120), Position = UDim2.fromOffset(6, 6), Parent = body })
	local title = UI.label({ Text = "", MaxText = 42, Size = UDim2.new(1, -150, 0, 56), Position = UDim2.fromOffset(140, 6), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Gold, Parent = body })
	local text = UI.label({ Text = "", Stroke = 0, TextColor3 = C.Ink, MaxText = 26, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, -150, 0, 210), Position = UDim2.fromOffset(140, 66), Parent = body })
	local counter = UI.label({ Text = "", Stroke = 0, TextColor3 = C.Muted, MaxText = 22, Size = UDim2.fromOffset(90, 28), Position = UDim2.new(0.5, -45, 1, -92), Parent = body })
	local back, nextBtn
	local function show()
		local p = GUIDE_PAGES[page]
		icon.Image = Config.ICONS[p.icon] or ""
		title.Text = p.title
		text.Text = p.text
		counter.Text = page .. " / " .. #GUIDE_PAGES
		back.Visible = page > 1
		UI.setText(nextBtn, if page == #GUIDE_PAGES then "Got it!" else "Next")
		Sound.play("Click", 0.4, 1.1)
	end
	back = UI.button({ Text = "Back", Color = C.Muted, Size = UDim2.fromOffset(150, 56), Position = UDim2.new(0, 6, 1, -66), Parent = body }, function()
		page = math.max(1, page - 1)
		show()
	end)
	nextBtn = UI.button({ Text = "Next", Color = C.Kelp, Size = UDim2.fromOffset(190, 56), Position = UDim2.new(1, -196, 1, -66), Parent = body }, function()
		if page >= #GUIDE_PAGES then
			Menus.close()
		else
			page += 1
			show()
		end
	end)
	show()
	Sound.play("Click", 0.5)
end

function Menus.init(screen: ScreenGui)
	screenRef = screen
	-- idle the viewport creatures
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for i = #viewports, 1, -1 do
			local v = viewports[i]
			if not v.vp.Parent then
				table.remove(viewports, i)
			else
				MonsterModels.pose(v.rig, v.cf * CFrame.Angles(0, math.sin(t * 0.6) * 0.4, 0), t, false, false)
			end
		end
	end)
	Remotes.event("Reveal").OnClientEvent:Connect(function(kind, p)
		if kind == "spell" then
			Hud.spellDrop(p.id)
		else
			Menus.reveal(kind, p)
		end
	end)
	Remotes.event("Offline").OnClientEvent:Connect(function(seconds, coins)
		Menus.offline(seconds, coins)
	end)
end

return Menus
