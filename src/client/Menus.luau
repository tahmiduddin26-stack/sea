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
	local f, body = UI.window({ Title = title, Accent = color or C.Sea, Size = UDim2.fromOffset(size.X, size.Y), Position = UDim2.fromScale(0.5, 0.52), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 10, Parent = screenRef }, Menus.close)
	f.Parent = screenRef
	open = f
	-- phones are shorter than most menus: shrink to fit the screen
	local fit = Platform.fit(size)
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

local function prompt(kind: string, name: string)
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
Menus.prompt = prompt

function Menus.promptOffer(name: string)
	if Config.GAMEPASSES[name] then
		if State.hasPass(name) then
			Hud.toast("You already own " .. Config.GAMEPASSES[name].name, C.Kelp)
			return
		end
		prompt("Pass", name)
	else
		prompt("Product", name)
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
				UI.label({ Name = "Info", Text = "Lv." .. m.lvl .. " " .. UI.stars(Stats.shownStars(m.sp, m.x6)), Size = UDim2.new(1, 0, 0.2, 0), Position = UDim2.fromScale(0, 0.8), TextColor3 = C.Gold, Parent = s })
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
			for _, o in Stats.fuseOutcomes(a.sp, b.sp, a.lvl, luck) do
				local card = UI.panel({ Size = UDim2.fromOffset(92, 130), Color = Color3.fromRGB(230, 240, 255), Parent = outcomes })
				local found = snap.index[o.sp] == true
				creatureView(card, o.sp, UDim2.new(1, 0, 0, 90), nil, not found)
				UI.label({ Text = math.floor(o.chance * 1000 + 0.5) / 10 .. "%", Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 94), TextColor3 = C.Gold, Parent = card })
			end
			hint.Text = "Lv." .. a.lvl .. " + Lv." .. b.lvl .. " = Lv." .. (a.lvl + 1) .. "   |   " .. Format.time(Stats.fuseSeconds(a.lvl, math.max(Stats.stars(a.sp), Stats.stars(b.sp))) * (if State.hasPass("FastFuse") then 0.5 else 1))
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
		UI.label({ Text = UI.stars(Stats.shownStars(e.m.sp, e.m.x6)), TextColor3 = C.Gold, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 102), Parent = card })
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
		InsaneLuck = "x4 fuse luck 15m", SkipTimer = "Finish all timers", CoinsSmall = "A chest of coins", CoinsBig = "A ship of coins",
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
		UI.label({ Text = SHORT[name] or "", Stroke = 0, TextColor3 = C.Ink, MaxText = 15, Size = UDim2.new(1, -12, 0, 20), Position = UDim2.fromOffset(6, 106), Parent = c })
		UI.button({ Text = if owned then "Owned" else ("R$ " .. info.price), Color = if owned then C.Muted else C.Kelp, Size = UDim2.new(1, -20, 0, 44), Position = UDim2.new(0, 10, 1, -54), Parent = c }, function()
			if not owned then
				prompt(kind, name)
			end
		end)
	end
	for _, name in { "StarterPack", "PearlDragonPack", "ElementBundle", "LimitedRoll", "PowerSpins", "Luck30", "FuseLuck", "InsaneLuck", "SkipTimer", "Revive", "CoinsSmall", "CoinsBig" } do
		if not (name == "StarterPack" and State.snapshot.starterBought) then
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
	local names = { "All", "Common", "Rare", "Epic", "Legendary", "Mythic" }
	for i, n in names do
		local idx = i - 1
		local col = if idx == 0 then C.Sea else Config.RARITY[idx].color
		local b = UI.button({ Text = n, Color = col, Size = UDim2.fromOffset(118, 38), Parent = tabs }, function()
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
	local f, body = window(title, Vector2.new(420, 340), C.Coral)
	if p.timeUp then
		Hud.splash("TIME'S UP!", C.Coral)
	end
	local why = if p.retreat then "You swam back safely." elseif p.timeUp then "The boss swam away! Beat it in " .. Config.BOSS_TIME .. "s." else "Your team needs to get stronger!"
	local lines = {
		why,
		"Depth reached: " .. p.depth,
		"Coins earned: " .. Format.abbrev(p.coins),
		"Enemies beaten: " .. p.kills,
	}
	if p.rest then
		table.insert(lines, "Your monsters must rest for " .. p.rest .. "s")
	end
	for i, t in lines do
		UI.label({ Text = t, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, (i - 1) * 36), Parent = body })
	end
	if p.canRevive then
		local btn = UI.button({ Text = "Revive & Continue  R$" .. Config.PRODUCTS.Revive.price, Color = C.Kelp, Size = UDim2.new(1, -20, 0, 54), Position = UDim2.new(0, 10, 1, -120), Parent = body }, function()
			Menus.close()
			prompt("Product", "Revive")
		end)
		local secs = Config.REVIVE_WINDOW
		task.spawn(function()
			while secs > 0 and btn.Parent do
				task.wait(1)
				secs -= 1
			end
			if btn.Parent then
				btn.Visible = false
			end
		end)
	end
	UI.button({ Text = "No Thanks", Color = C.Muted, Size = UDim2.new(1, -20, 0, 50), Position = UDim2.new(0, 10, 1, -58), Parent = body }, Menus.close)
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
		local rarity = Config.RARITY[math.min(st, #Config.RARITY)]
		local rarityName = if st > #Config.RARITY then "SIX STAR" else string.upper(rarity.name)
		stars.Text = UI.stars(st) .. '  <font color="#' .. rarity.color:ToHex() .. '">' .. rarityName .. "</font>"
		if st >= 3 then
			Hud.splash(rarityName .. "!", rarity.color)
		end
		UI.pop(name, 0.5)
		UI.pop(vp :: any, 0.6)
			dmgSticker.Visible = true
			UI.pop(dmgSticker, 0.4)
		Sound.play("Win", 0.6)
	end)
	local tap = UI.label({ Text = "Tap to continue", Size = UDim2.fromOffset(300, 30), Position = UDim2.new(0.5, 0, 0.965, 0), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 32, TextTransparency = 1, Parent = f })
	task.delay(1.4, function()
		tap.TextTransparency = 0
	end)
	local btn = UI.new("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 40, Parent = f })
	local t0 = os.clock()
	local function done()
		if os.clock() - t0 < 1.2 then
			return
		end
		conn:Disconnect()
		State.revealing = false
		Hud.refresh()
		if open == f then
			open = nil
		end
		f:Destroy()
	end
	btn.Activated:Connect(done)
	task.delay(5, done)
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

function Menus.team()
	local snap = State.snapshot
	local list = sortedMonsters(snap)
	local chosen: { string } = table.clone(snap.team)
	if #chosen == 0 then
		for i = 1, math.min(#list, snap.teamSlots) do
			table.insert(chosen, list[i].uid)
		end
	end
	local f, body = window("Team " .. #chosen .. "/" .. snap.teamSlots, Vector2.new(760, 480), C.Pearl)
	local scroll = UI.new("ScrollingFrame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -64), ScrollBarThickness = 8, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), BorderSizePixel = 0, Parent = body }, { UI.new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }) })
	UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(112, 140), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
	local cards = {}
	-- Sell mode: tap a monster once to arm it (its card turns red and shows the price), tap again to sell
	local sellMode = teamSellMode
	local armed: string? = nil
	local sellBtn: GuiObject? = nil
	local function redraw()
		for uid, card in cards do
			local on = table.find(chosen, uid) ~= nil
			if sellMode then
				(card:FindFirstChild("Tick") :: GuiObject).Visible = false
				local st = card:FindFirstChildOfClass("UIStroke")
				if st then
					st.Color = if uid == armed then C.Coral else C.Ink
					st.Thickness = if uid == armed then 5 else 3.5
				end
				continue
			end
			local st = card:FindFirstChildOfClass("UIStroke")
			if st then
				st.Color = if on then C.Kelp else C.Ink
				st.Thickness = if on then 5 else 3.5
			end
			(card:FindFirstChild("Tick") :: GuiObject).Visible = on
		end
	end
	for i, e in list do
		local card = UI.button({ Text = "", Color = Color3.fromRGB(255, 244, 216), Size = UDim2.fromOffset(112, 140), LayoutOrder = i, Parent = scroll }, function()
			if sellMode then
				local price = Stats.sellPrice(e.m.sp, e.m.lvl, e.m.v)
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
					Menus.team() -- (redraws without the sold monster)
				end
				return
			end
			local idx = table.find(chosen, e.uid)
			if idx then
				table.remove(chosen, idx)
			elseif #chosen < snap.teamSlots then
				table.insert(chosen, e.uid)
			else
				Hud.toast("Team is full! Buy more slots", C.Coral)
			end
			redraw()
		end)
		creatureView(card, e.m.sp, UDim2.new(1, 0, 0, 80))
		UI.label({ Text = "Lv." .. e.m.lvl .. (if e.m.power then " " .. e.m.power else ""), Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 78), Parent = card })
		-- damage sticker: how hard this monster hits, per second
		local dmg = UI.panel({ Color = Color3.fromRGB(255, 120, 100), Radius = 9, Size = UDim2.new(1, -16, 0, 20), Position = UDim2.fromOffset(8, 98), Parent = card })
		UI.label({ Text = "DMG " .. Format.abbrev(math.floor(Stats.dps(e.m.sp, e.m.lvl, e.m.stars, e.m.v, e.m.x6) + 0.5)) .. "/s", MaxText = 14, Size = UDim2.new(1, -8, 0.8, 0), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = dmg })
		UI.label({ Text = "Power " .. Format.abbrev(e.p), TextColor3 = C.Gold, MaxText = 15, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 120), Parent = card })
		UI.label({ Name = "Tick", Text = "IN", TextColor3 = C.Kelp, Size = UDim2.fromOffset(34, 22), Position = UDim2.fromOffset(4, 4), Parent = card })
		cards[e.uid] = card
	end
	redraw()
	local nextPrice = Config.TEAM_SLOT_PRICES[snap.teamSlots - Config.TEAM_START + 1]
	UI.button({ Text = "Save Team", Color = C.Kelp, Size = UDim2.fromOffset(180, 50), Position = UDim2.new(1, -16, 1, -12), AnchorPoint = Vector2.new(1, 1), Parent = f }, function()
		State.action("Team", chosen)
		Menus.close()
		Hud.toast("Team saved!", C.Kelp)
	end)
	UI.button({ Text = "Auto Best", Color = C.Sea, Size = UDim2.fromOffset(150, 50), Position = UDim2.new(1, -206, 1, -12), AnchorPoint = Vector2.new(1, 1), Parent = f }, function()
		State.action("Team", {})
		Menus.close()
		Hud.toast("Your strongest monsters will fight", C.Kelp)
	end)
	sellBtn = UI.button({ Text = if sellMode then "Sell: ON" else "Sell: off", Color = C.Muted, Size = UDim2.fromOffset(130, 50), Position = UDim2.new(0, 226, 1, -12), AnchorPoint = Vector2.new(0, 1), Parent = f }, function()
		sellMode = not sellMode
		teamSellMode = sellMode
		armed = nil
		UI.setText(sellBtn :: GuiObject, if sellMode then "Sell: ON" else "Sell: off")
		;(sellBtn :: GuiObject).BackgroundColor3 = if sellMode then C.Coral else Color3.new(1, 1, 1)
		if sellMode then
			Hud.toast("Tap a monster twice to sell it", C.Coral)
		end
		redraw()
	end)
	if sellMode then
		(sellBtn :: GuiObject).BackgroundColor3 = C.Coral
	end
	redraw()
	if nextPrice then
		UI.button({ Text = "+1 Slot  " .. Format.abbrev(nextPrice), Color = C.Gold, Size = UDim2.fromOffset(200, 50), Position = UDim2.new(0, 16, 1, -12), AnchorPoint = Vector2.new(0, 1), Parent = f }, function()
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
		prompt("Product", "PowerSpins")
	end)
end

---------------------------------------------------------------------------
-- Gifts (playtime + daily)
---------------------------------------------------------------------------
function Menus.gifts()
	local snap = State.snapshot
	local _, body = window("Free Gifts", Vector2.new(760, 590), C.Kelp)
	local grid = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 340), Parent = body })
	UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(170, 160), CellPadding = UDim2.fromOffset(10, 10), Parent = grid })
	local labels = {}
	for i, g in Config.GIFTS do
		local c = UI.panel({ Size = UDim2.fromOffset(170, 160), Color = Color3.fromRGB(255, 244, 216), Parent = grid })
		local icon = if g.coins then Config.ICONS.Coin elseif g.pearls then Config.ICONS.Pearl elseif g.spins then Config.ICONS.Power else Config.ICONS.LuckEgg
		local what = if g.coins then Format.abbrev(g.coins) .. " Coins" elseif g.pearls then g.pearls .. " Pearls" elseif g.spins then "Power Spin" else "Mystery Egg"
		if g.spell then
			what ..= " + Spell"
		end
		UI.new("ImageLabel", { BackgroundTransparency = 1, Image = icon, Size = UDim2.fromOffset(52, 52), Position = UDim2.new(0.5, 0, 0, 4), AnchorPoint = Vector2.new(0.5, 0), Parent = c })
		UI.label({ Text = what, Size = UDim2.new(1, -10, 0, 22), Position = UDim2.fromOffset(5, 56), Parent = c })
		-- bonus line: festival shells ride along on some gifts
		if g.shells then
			UI.label({ Text = "+ " .. g.shells .. " Shells", TextColor3 = Color3.fromRGB(255, 160, 60), MaxText = 16, Size = UDim2.new(1, -10, 0, 18), Position = UDim2.fromOffset(5, 82), Parent = c })
		end
		local btn = UI.button({ Text = "", Color = C.Kelp, Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 1, -36), Parent = c }, function()
			local ok, msg = State.action("Gift", i)
			Hud.toast(msg or "", if ok then C.Kelp else C.Coral)
		end)
		labels[i] = btn
	end
	-- social row: joining the group is just a button (no reward for joining); friends who play in
	-- your server each add +10% battle coins, up to +30% (Config.FRIEND_BOOST / FRIEND_BOOST_MAX)
	UI.button({ Text = "Join the Crew", Color = C.Sea, Size = UDim2.new(0.5, -16, 0, 50), Position = UDim2.fromOffset(10, 352), Parent = body }, function()
		pcall(function()
			game:GetService("GroupService"):PromptJoinAsync(Config.GROUP_ID)
		end)
	end)
	UI.button({ Text = "Invite Friends: +10% coins each (max 30%)", Color = Color3.fromRGB(255, 140, 60), Size = UDim2.new(0.5, -16, 0, 50), Position = UDim2.new(0.5, 6, 0, 352), Parent = body }, function()
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
			UI.setText(daily, if s.dailyDay == State.now() // 86400 then "Daily Chest: come back tomorrow" else ("Daily Chest: Day " .. ((s.dailyStreak or 0) + 1)))
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
	local _, body = window("Ship Workshop", Vector2.new(880, 580), Color3.fromRGB(70, 150, 235))
	local function redraw()
		for _, ch in body:GetChildren() do
			ch:Destroy()
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
	{ icon = "Pedestal", title = "4. Upgrade Your Ship", text = "The wooden boards on your deck buy <font color=\"#FFCD32\">Egg Luck</font>, more <font color=\"#FFCD32\">pedestals</font> and nests. Fuse 20 times and save 30K coins to unlock the <font color=\"#FFCD32\">Quarterdeck</font> with extra nests." },
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
