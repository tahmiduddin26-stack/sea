--!strict
-- The Floor board on each ship, the Dockyard's upgrades (Egg Luck, Fast Reel, Shipwright), codes,
-- and the one Action remote the client calls for everything that isn't a prompt.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Stats = require(Shared.Stats)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local FarmService = require(script.Parent.FarmService)
local BattleService = require(script.Parent.BattleService)
local WorldBuilder = require(script.Parent.WorldBuilder)
local ExtrasService = require(script.Parent.ExtrasService)
local AdminService = require(script.Parent.AdminService)
local Analytics = require(script.Parent.Analytics)
local MiniGameService = require(script.Parent.MiniGameService)
local LighthouseService = require(script.Parent.LighthouseService)
local CrateService = require(script.Parent.CrateService)

local ShopService = {}

local function toast(player: Player, text: string, color: Color3?)
	Remotes.event("Toast"):FireClient(player, text, color)
end

-- Board face: title, a "from > to" line and a price chip
local function ensureBoardGui(board: BasePart): (TextLabel, TextLabel, TextLabel)
	local gui = board:FindFirstChild("Gui") :: SurfaceGui?
	if not gui then
		local g = Instance.new("SurfaceGui")
		g.Name = "Gui"
		g.Face = Enum.NormalId.Front
		-- canvas matches the board shape (8.6 x 4.6 studs) so text is never stretched or clipped
		g.CanvasSize = Vector2.new(math.floor(210 * board.Size.X / board.Size.Y), 210)
		g.LightInfluence = 0
		g.Parent = board
		local function line(name: string, y: number, h: number, color: Color3)
			local t = Instance.new("TextLabel")
			t.Name = name
			t.BackgroundTransparency = 1
			t.Position = UDim2.fromOffset(22, y)
			t.Size = UDim2.new(1, -44, 0, h)
			t.Font = Enum.Font.FredokaOne
			t.TextScaled = true
			t.TextColor3 = color
			t.Parent = g
			local st = Instance.new("UIStroke")
			st.Thickness = 3
			st.Color = Color3.fromRGB(40, 24, 12)
			st.Parent = t
		end
		line("Title", 10, 52, Color3.fromRGB(255, 255, 255))
		line("Value", 70, 60, Color3.fromRGB(120, 230, 255))
		line("Price", 140, 54, Color3.fromRGB(255, 215, 60))
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.Size = UDim2.fromOffset(96, 96)
		icon.Position = UDim2.fromOffset(22, 64)
		icon.Parent = g
		for _, n in { "Value", "Price" } do
			local t = g:FindFirstChild(n) :: TextLabel
			t.Position = UDim2.fromOffset(124, t.Position.Y.Offset)
			t.Size = UDim2.new(1, -146, 0, t.Size.Y.Offset)
		end
		gui = g
	end
	local g = gui :: SurfaceGui
	return g:FindFirstChild("Title") :: TextLabel, g:FindFirstChild("Value") :: TextLabel, g:FindFirstChild("Price") :: TextLabel
end

function ShopService.syncBoards(player: Player)
	local ship = FarmService.shipOf(player)
	local data = DataService.get(player)
	if not ship or not data then
		return
	end
	-- (Egg Luck, Fast Reel and the Shipwright are bought at the Dockyard in town, not from boards)
	-- Floor 2
	do
		local title, value, price = ensureBoardGui(ship.boards.Floor)
		title.Text = if data.floor >= 2 then "Unlock Floor 3" else "Unlock Floor 2"
		if data.floor >= 3 then
			title.Text = "Floors"
			value.Text = "All unlocked! +35% coins"
			price.Text = ""
		elseif data.floor >= 2 then
			-- Floor 3 (the poop deck): needs fuses, a cleared stage and a pile of coins
			if data.bestDepth < Config.FLOOR3.depth then
				value.Text = "Clear stage " .. (Config.FLOOR3.depth // Config.STAGE_LENGTH)
				price.Text = Format.abbrev(Stats.floor3Price()) .. " Coins"
			else
				value.Text = "Fuses " .. math.min(data.totalFuses, Config.FLOOR3.fuses) .. "/" .. Config.FLOOR3.fuses
				price.Text = Format.abbrev(Stats.floor3Price()) .. " Coins"
			end
		else
			value.Text = "Fuses " .. math.min(data.totalFuses, Config.FLOOR2.fuses) .. "/" .. Config.FLOOR2.fuses
			price.Text = Format.abbrev(Config.FLOOR2.coins) .. " Coins"
		end
	end
	local icons = { Floor = if data.floor >= 3 then Config.ICONS.Gift else Config.ICONS.Lock }
	for id, b in ship.boards do
		local gui = b:FindFirstChild("Gui")
		local icon = gui and gui:FindFirstChild("Icon") :: ImageLabel?
		if icon then
			icon.Image = icons[id] or ""
		end
	end
	for _, b in ship.boards do
		local pp = b:FindFirstChild("UpgradePrompt") :: ProximityPrompt
		pp.ObjectText = (b:FindFirstChild("Gui") :: any).Title.Text
	end
end

local function upgrade(player: Player, id: string)
	local data = DataService.get(player)
	if FarmService.inTutorial(player) and data.tutorial < Config.SIGNS_UNLOCK_STEP then
		toast(player, "Finish the tutorial first!", Color3.fromRGB(255, 200, 60))
		return
	end
	if id == "Ship" then
		local tier = (data.shipTier or 0) + 1
		if tier > #Config.SHIP_TIERS then
			toast(player, "Your ship is a Royal Flagship!", Color3.fromRGB(255, 200, 60))
			return
		end
		if data.bestDepth < Stats.shipTierDepth(tier) then
			toast(player, "Clear stage " .. (Stats.shipTierStage(tier) - 2) .. " to unlock " .. Config.SHIP_TIERS[tier], Color3.fromRGB(255, 200, 60))
			return
		end
		local price = Stats.shipTierPrice(tier)
		if data.coins < price then
			toast(player, "Need " .. Format.abbrev(price) .. " coins", Color3.fromRGB(255, 90, 90))
			return
		end
		Analytics.tag(player, "Shop", "Shipwright")
		data.coins -= price
		data.shipTier = tier
		Analytics.event(player, "ShipTier", tier)
		toast(player, Config.SHIP_TIERS[tier] .. "! +" .. math.floor(Config.SHIPWRIGHT.coinPerTier * 100) .. "% coins, " .. math.floor(Config.SHIPWRIGHT.hatchPerTier * 100) .. "% faster hatching", Color3.fromRGB(90, 220, 120))
	elseif id == "Floor" and data.floor >= 2 then
		if data.floor >= 3 then
			return
		end
		if data.bestDepth < Config.FLOOR3.depth then
			toast(player, "Clear stage " .. (Config.FLOOR3.depth // Config.STAGE_LENGTH) .. " to unlock Floor 3", Color3.fromRGB(255, 200, 60))
			return
		end
		if data.totalFuses < Config.FLOOR3.fuses then
			toast(player, "Fuse " .. (Config.FLOOR3.fuses - data.totalFuses) .. " more times to unlock", Color3.fromRGB(255, 200, 60))
			return
		end
		local price = Stats.floor3Price()
		if data.coins < price then
			toast(player, "Need " .. Format.abbrev(price) .. " coins", Color3.fromRGB(255, 90, 90))
			return
		end
		Analytics.tag(player, "Shop", "Floor3")
		data.coins -= price
		Analytics.event(player, "UnlockFloor3", 1)
		data.floor = 3
		player:SetAttribute("AbyssFloor", true) -- the Abyss Rod's balcony is up here (FarmService.syncAbyssRod)
		toast(player, "Poop Deck unlocked! 4 more nests, +20% coins and the Abyss Rod", Color3.fromRGB(90, 220, 120))
	elseif id == "Floor" then
		if data.totalFuses < Config.FLOOR2.fuses then
			toast(player, "Fuse " .. (Config.FLOOR2.fuses - data.totalFuses) .. " more times to unlock", Color3.fromRGB(255, 200, 60))
			return
		end
		if data.coins < Config.FLOOR2.coins then
			toast(player, "Need " .. Format.abbrev(Config.FLOOR2.coins) .. " coins", Color3.fromRGB(255, 90, 90))
			return
		end
		Analytics.tag(player, "Shop", "Floor2")
		data.coins -= Config.FLOOR2.coins
		Analytics.event(player, "UnlockFloor2", 1)
		data.floor = 2
		toast(player, "Quarterdeck unlocked! More nests and +15% coins", Color3.fromRGB(90, 220, 120))
	else
		local lvl = data.upgrades[id]
		local p = Stats.upgradePrice(id, lvl)
		if not p then
			toast(player, "Already maxed!", Color3.fromRGB(255, 200, 60))
			return
		end
		if data.coins < p then
			toast(player, "Need " .. Format.abbrev(p) .. " coins", Color3.fromRGB(255, 90, 90))
			return
		end
		Analytics.tag(player, "Shop", id)
		data.coins -= p
		data.upgrades[id] = lvl + 1
		Analytics.event(player, "Upgrade", lvl + 1, { upgrade = id })
		toast(player, Config.UPGRADES[id].name .. " upgraded!", Color3.fromRGB(90, 220, 120))
	end
	FarmService.syncAll(player)
	ShopService.syncBoards(player)
	DataService.changed(player)
end

local function redeem(player: Player, code: any): (boolean, string?)
	if typeof(code) ~= "string" then
		return false, "Type a code"
	end
	local key = string.upper((string.gsub(code, "%s", "")))
	local reward = Config.CODES[key]
	local data = DataService.get(player)
	if not reward then
		return false, "That code doesn't exist"
	end
	if data.redeemedCodes[key] then
		return false, "Already redeemed"
	end
	data.redeemedCodes[key] = true
	Analytics.tag(player, "Onboarding", "Code_" .. key)
	Analytics.event(player, "Code", 1, { code = key })
	if reward.coins then
		data.coins += reward.coins
	end
	if reward.pearls then
		data.pearls += reward.pearls
	end
	if reward.spins then
		data.spins += reward.spins
	end
	DataService.changed(player)
	return true, "Code redeemed!"
end

local handlers: { [string]: (Player, any) -> (boolean, string?) } = {
	Sell = function(player, arg)
		return FarmService.sellMonster(player, arg)
	end,
	SellEgg = function(player, arg)
		return FarmService.sellEgg(player, arg)
	end,
	ShipFlag = function(player, arg)
		local ship = FarmService.shipOf(player)
		local station = ship and ship.model:FindFirstChild("FlagStation") :: BasePart?
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if FarmService.inTutorial(player) or not ship or not station or not root or (root.Position - station.Position).Magnitude > 14 then
			return false, "Visit the flag station on your ship"
		end
		if typeof(arg) ~= "table" or not table.find(Config.FLAG_EMBLEMS, arg.emblem) then return false, "Pick an emblem" end
		for _, entry in Config.FLAG_COLORS do
			if entry.id == arg.color then
				local design = { color = entry.id, emblem = arg.emblem }
				DataService.get(player).shipFlag = design
				WorldBuilder.applyFlag(ship, design)
				DataService.changed(player)
				return true, "Ship flag saved!"
			end
		end
		return false, "Pick a flag colour"
	end,
	Admin = function(player, arg)
		return AdminService.run(player, arg)
	end,
	-- the Leave button inside the Lighthouse Climb
	LeaveLighthouse = function(player)
		LighthouseService.leaveClimb(player)
		return true, nil
	end,
	-- Crab Cove starts a server-owned round. MiniFinish leaves early.
	MiniStart = function(player, arg)
		return MiniGameService.start(player, arg)
	end,
	MiniFinish = function(player, arg)
		return MiniGameService.finish(player, arg)
	end,
	-- Cannon Gallery: get in / out of a ship's gallery cannon, and fire at the live crates
	CannonEnter = function(player, arg)
		return CrateService.enter(player, arg)
	end,
	CannonLeave = function(player)
		return CrateService.leave(player)
	end,
	CannonFire = function(player, arg)
		return CrateService.fire(player, arg)
	end,
	Fight = function(player)
		return BattleService.fight(player)
	end,
	Retreat = function(player)
		BattleService.retreat(player)
		return true, nil
	end,
	Speed = function(player, arg)
		return BattleService.setSpeed(player, arg), nil
	end,
	-- Settings: music / sound-effect volume. Cosmetic only, so it just saves (no snapshot push).
	Volume = function(player, arg)
		if typeof(arg) ~= "table" then
			return false, nil
		end
		local m, s = arg.music, arg.sfx
		if typeof(m) ~= "number" or typeof(s) ~= "number" or m ~= m or s ~= s then
			return false, nil
		end
		local data = DataService.get(player)
		if not data then
			return false, nil
		end
		data.volume = { music = math.clamp(m, 0, 1), sfx = math.clamp(s, 0, 1) }
		return true, nil
	end,
	Fuse = function(player, arg)
		if typeof(arg) ~= "table" then
			return false, "Pick two monsters"
		end
		-- { uidA, uidB, extra... }: Lv3+ fuses need more than two (Stats.fuseNeeded)
		local extra = {}
		for k = 3, math.min(#arg, 20) do
			table.insert(extra, arg[k])
		end
		return FarmService.fuse(player, arg[1], arg[2], extra)
	end,
	Code = function(player, arg)
		return redeem(player, arg)
	end,
	Respawn = function(player)
		FarmService.spawnAtShip(player)
		return true, nil
	end,
	Team = function(player, arg)
		return FarmService.setTeam(player, arg)
	end,
	TeamSlot = function(player)
		return ExtrasService.buyTeamSlot(player)
	end,
	-- asks whether a staggered unlock is open yet: ok, or false + "Crab Cove opens in 1:12 - keep playing!"
	DripCheck = function(player, arg)
		if typeof(arg) ~= "string" then
			return false, nil
		end
		local DripService = require(script.Parent.DripService)
		if DripService.open(player, arg) then
			return true, nil
		end
		return false, DripService.waitText(player, arg)
	end,
	QuestClaim = function(player, arg)
		return require(script.Parent.MissionService).claimQuest(player, arg)
	end,
	Rebirth = function(player)
		return ExtrasService.rebirth(player)
	end,
	Spin = function(player, arg)
		return ExtrasService.spin(player, arg)
	end,
	EventBuy = function(player, arg)
		return ExtrasService.eventBuy(player, arg)
	end,
	Crate = function(player)
		return ExtrasService.limitedRoll(player, false)
	end,
	Gift = function(player, arg)
		return ExtrasService.claimGift(player, arg)
	end,
	Group = function(player)
		return ExtrasService.claimGroup(player)
	end,
	-- Ship Workshop: arg = { kind = "fit" | "paint", id = fitting id | paint id, slot = "sail" | "stripe" }
	Workshop = function(player, arg)
		local data = DataService.get(player)
		if typeof(arg) ~= "table" or not data then
			return false, nil
		end
		if arg.kind == "fit" then
			local def = Config.FITTINGS[arg.id]
			if not def then
				return false, nil
			end
			data.fittings = data.fittings or {}
			local lvl = data.fittings[arg.id] or 0
			if lvl >= def.max then
				return false, "Already maxed!"
			end
			local price = Stats.fittingPrice(arg.id, lvl)
			if data.coins < price then
				return false, "Not enough coins! Battle to earn more"
			end
			Analytics.tag(player, "Shop", "Fitting" .. arg.id)
			data.coins -= price
			data.fittings[arg.id] = lvl + 1
			Analytics.vendor(player, "Workshop", 2)
			FarmService.syncAll(player)
			DataService.changed(player)
			return true, def.name .. " level " .. (lvl + 1) .. "!"
		elseif arg.kind == "paint" and (arg.slot == "sail" or arg.slot == "stripe") then
			local list = if arg.slot == "sail" then Config.PAINTS.Sail else Config.PAINTS.Stripe
			local def
			for _, p in list do
				if p.id == arg.id then
					def = p
				end
			end
			if not def then
				return false, nil
			end
			data.paintOwned = data.paintOwned or {}
			if not data.paintOwned[def.id] then
				if data.coins < def.price then
					return false, "Not enough coins! Battle to earn more"
				end
				Analytics.tag(player, "Shop", "Paint" .. def.id)
				data.coins -= def.price
				data.paintOwned[def.id] = true
			end
			data.paint = data.paint or {}
			data.paint[arg.slot] = def.id
			FarmService.syncAll(player)
			DataService.changed(player)
			return true, def.name .. " paint!"
		end
		return false, nil
	end,
	-- Dockyard (town): arg = "Luck" | "Pedestals" | "Ship". `upgrade` does the checks and toasts;
	-- we only report whether a level was actually bought so the menu can refresh and chime.
	Upgrade = function(player, arg)
		if arg ~= "Luck" and arg ~= "Pedestals" and arg ~= "Ship" then
			return false, nil
		end
		local data = DataService.get(player)
		if not data then
			return false, nil
		end
		local function level(): number
			return if arg == "Ship" then (data.shipTier or 0) else data.upgrades[arg]
		end
		local before = level()
		upgrade(player, arg)
		return level() > before, nil
	end,
	Favorite = function(player, arg)
		return ExtrasService.favorite(player, arg)
	end,
	Daily = function(player)
		return ExtrasService.claimDaily(player)
	end,
	SpellCombine = function(player, arg)
		return ExtrasService.combineSpells(player, arg)
	end,
	SpellCast = function(player, arg)
		return ExtrasService.castSpell(player, arg)
	end,
	EggShop = function(player, arg)
		return ExtrasService.eggShopBuy(player, arg)
	end,
	-- Studio only: jump past the tutorial with a test bank (for checking the full HUD)
	DevSkip = function(player)
		if not game:GetService("RunService"):IsStudio() then
			return false, nil
		end
		local data = DataService.get(player)
		data.tutorial = Config.TUTORIAL_DONE
		data.coins += 100000 * Config.COIN_SCALE
		data.pearls += 500
		data.bestDepth = math.max(data.bestDepth, 31)
		for _, sp in Config.SPELLS do
			data.spells[sp.id] = 2
			data.spellsFound[sp.id] = true
		end
		FarmService.devMonster(player, "Tsunamaw", 5, 3)
		FarmService.devMonster(player, "Coralord", 5, 3)
		FarmService.devMonster(player, "Nightfang", 5, 3)
		FarmService.syncAll(player)
		DataService.changed(player)
		return true, "Dev skip"
	end,
}

function ShopService.init()
	for _, ship in WorldBuilder.ships do
		for id, b in ship.boards do
			(b:FindFirstChild("UpgradePrompt") :: ProximityPrompt).Triggered:Connect(function(player)
				if FarmService.ownerOf(ship.index) == player then
					upgrade(player, id)
				end
			end)
		end
	end
	DataService.Loaded:Connect(function(player)
		task.defer(ShopService.syncBoards, player)
	end)
	Remotes.event("IntroSeen").OnServerEvent:Connect(function(player)
		local data = DataService.get(player)
		if data and not data.introSeen then
			data.introSeen = true
			DataService.changed(player)
		end
	end)
	local last: { [Player]: number } = {}
	Remotes.func("Action").OnServerInvoke = function(player, name, arg)
		if typeof(name) ~= "string" or not DataService.isLoaded(player) then
			return false, nil
		end
		-- light rate limit
		local now = os.clock()
		if last[player] and now - last[player] < 0.15 then
			return false, nil
		end
		last[player] = now
		local h = handlers[name]
		if not h then
			return false, nil
		end
		local ok, a, b = pcall(h, player, arg)
		if not ok then
			warn("[Action]", name, a)
			return false, nil
		end
		ShopService.syncBoards(player)
		return a, b
	end
	-- keep board numbers fresh as coins change
	task.spawn(function()
		while true do
			task.wait(2)
			for _, p in game:GetService("Players"):GetPlayers() do
				if DataService.isLoaded(p) then
					ShopService.syncBoards(p)
				end
			end
		end
	end)
end

return ShopService
