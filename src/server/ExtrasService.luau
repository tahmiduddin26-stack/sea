--!strict
-- Side systems around the core loop:
--   Powers     spin a random passive onto one monster (unlocks at a depth)
--   Team       buy more team slots
--   Event      Tide Festival shells -> event shop
--   Limited    the Abyss Crate stand on the harbour (pearls or Robux)
--   Gifts      playtime gifts this session + the daily chest streak
-- Each is reached through the Action remote; MonetizationService calls the grant helpers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Stats = require(Shared.Stats)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local FarmService = require(script.Parent.FarmService)
local Analytics = require(script.Parent.Analytics)

local ExtrasService = {}

local rng = Random.new()

local function toast(player: Player, text: string, color: Color3?)
	Remotes.event("Toast"):FireClient(player, text, color)
end

local function eggLevelBonus(data: any): number
	return math.max(0, Stats.stageOf(math.max(1, data.bestDepth)) - 1)
end

---------------------------------------------------------------------------
-- Powers
---------------------------------------------------------------------------
local function rollPower(): any
	local total = 0
	for _, p in Config.POWERS do
		total += p.weight
	end
	local r = rng:NextNumber() * total
	for _, p in Config.POWERS do
		r -= p.weight
		if r <= 0 then
			return p
		end
	end
	return Config.POWERS[1]
end

function ExtrasService.spin(player: Player, uid: any): (boolean, any)
	local data = DataService.get(player)
	if data.bestDepth < Config.POWERS_UNLOCK_DEPTH then
		return false, "Reach Depth " .. Config.POWERS_UNLOCK_DEPTH .. " to unlock Powers"
	end
	local m = typeof(uid) == "string" and data.monsters[uid]
	if not m then
		return false, "Pick a monster"
	end
	Analytics.tag(player, "Shop", "PowerSpin")
	if data.spins > 0 then
		data.spins -= 1
	elseif data.pearls >= Config.POWER_SPIN_PEARLS then
		data.pearls -= Config.POWER_SPIN_PEARLS
	else
		return false, "Not enough pearls"
	end
	local p = rollPower()
	m.power = p.id
	Analytics.event(player, "PowerSpin", 1, { power = p.id })
	Analytics.vendor(player, "Powers", 2)
	DataService.changed(player)
	return true, p.id
end

---------------------------------------------------------------------------
-- Team slots
---------------------------------------------------------------------------
function ExtrasService.buyTeamSlot(player: Player): (boolean, string?)
	local data = DataService.get(player)
	if data.teamSlots >= Config.TEAM_MAX then
		return false, "Team is maxed"
	end
	local price = Config.TEAM_SLOT_PRICES[data.teamSlots - Config.TEAM_START + 1]
	if not price then
		return false, "Team is maxed"
	end
	if data.coins < price then
		return false, "Need " .. Format.abbrev(price) .. " coins"
	end
	Analytics.tag(player, "Shop", "TeamSlot")
	data.coins -= price
	data.teamSlots += 1
	Analytics.vendor(player, "Team", 2)
	DataService.changed(player)
	return true, "Team size " .. data.teamSlots .. "!"
end

---------------------------------------------------------------------------
-- Eggs given by side systems
---------------------------------------------------------------------------
function ExtrasService.giveRandomEgg(player: Player, sp: string?, lvlExtra: number, stars: number): boolean
	local data = DataService.get(player)
	local species = sp
	if not species then
		local hybrids = {}
		for _, id in Config.MONSTER_ORDER do
			local def = Config.MONSTERS[id]
			if #def.elements == 2 and not def.secret then
				table.insert(hybrids, id)
			end
		end
		species = hybrids[rng:NextInteger(1, #hybrids)]
	end
	local egg = { sp = species :: string, lvl = 1 + eggLevelBonus(data) + lvlExtra, stars = stars }
	local secs = math.floor(Stats.hatchSeconds(egg.lvl, Stats.stars(egg.sp)) * FarmService.hatchMult(player))
	return FarmService.giveEgg(player, egg, secs)
end

function ExtrasService.elementBundle(player: Player): boolean
	local data = DataService.get(player)
	local free = 0
	for i = 1, #Config.NEST_SLOTS do
		if FarmService.ownsNest(data, i) and not data.nests[tostring(i)] then
			free += 1
		end
	end
	if free < 4 then
		return false
	end
	for _, el in { "Tide", "Coral", "Storm", "Abyss" } do
		ExtrasService.giveRandomEgg(player, Config.STARTER_OF[el], 1, 2)
	end
	toast(player, "Elemental Bundle! Four eggs are in your nests", Color3.fromRGB(255, 205, 60))
	return true
end

function ExtrasService.limitedRoll(player: Player, paid: boolean): (boolean, string?)
	local data = DataService.get(player)
	if not paid then
		if data.pearls < Config.LIMITED.pearls then
			return false, "Need " .. Config.LIMITED.pearls .. " pearls"
		end
	end
	local r = rng:NextNumber()
	local pick = Config.LIMITED.odds[1].sp
	for _, o in Config.LIMITED.odds do
		r -= o.chance
		if r <= 0 then
			pick = o.sp
			break
		end
	end
	if not ExtrasService.giveRandomEgg(player, pick, 1, Config.LIMITED.stars) then
		return false, "Free a nest first!"
	end
	if not paid then
		Analytics.tag(player, "Shop", "AbyssCrate")
		data.pearls -= Config.LIMITED.pearls
	end
	Analytics.event(player, "CrateRoll", if paid then 1 else 0, { species = pick })
	Analytics.vendor(player, "Crate", 2)
	DataService.changed(player)
	toast(player, "Abyss Crate: a " .. Config.MONSTERS[pick].name .. " egg!", Color3.fromRGB(190, 110, 255))
	return true, pick
end

---------------------------------------------------------------------------
-- Event shop
---------------------------------------------------------------------------
function ExtrasService.eventBuy(player: Player, id: any): (boolean, string?)
	local data = DataService.get(player)
	if os.time() >= Config.EVENT.endsAt then
		return false, "The event has ended"
	end
	local item
	for _, it in Config.EVENT.shop do
		if it.id == id then
			item = it
		end
	end
	if not item then
		return false, nil
	end
	if data.shells < item.cost then
		return false, "Need " .. item.cost .. " shells"
	end
	if item.id == "FestivalEgg" then
		if not ExtrasService.giveRandomEgg(player, nil, 1, 3) then
			return false, "Free a nest first!"
		end
	elseif item.id == "PearlBag" then
		data.pearls += 60
	elseif item.id == "LuckBoost" then
		data.luckMult = math.max(if data.luckUntil > os.time() then data.luckMult else 1, 2)
		data.luckUntil = math.max(data.luckUntil, os.time()) + 600
	end
	data.shells -= item.cost
	Analytics.event(player, "EventBuy", item.cost, { item = item.id })
	Analytics.vendor(player, "Event", 2)
	DataService.changed(player)
	return true, item.name .. "!"
end

---------------------------------------------------------------------------
-- Spellbook
---------------------------------------------------------------------------
local function spellDef(id: any)
	for _, s in Config.SPELLS do
		if s.id == id then
			return s
		end
	end
	return nil
end

function ExtrasService.spellActive(player: Player, id: string): boolean
	local data = DataService.get(player)
	return data ~= nil and (data.spellUntil[id] or 0) > os.time()
end

-- Cast one of your spell cards: spends the card, adds its minutes to the timer
function ExtrasService.castSpell(player: Player, id: any): (boolean, string?)
	local data = DataService.get(player)
	local sp = spellDef(id)
	local have = sp and tonumber(data.spells[sp.id]) or 0
	if not sp or have <= 0 then
		return false, "Find this spell in the Gift Chest!"
	end
	data.spells[sp.id] = have - 1
	Analytics.event(player, "SpellCast", sp.rarity, { spell = sp.id })
	Analytics.vendor(player, "Spellbook", 2)
	data.spellUntil[sp.id] = math.max(data.spellUntil[sp.id] or 0, os.time()) + sp.minutes * 60
	DataService.changed(player)
	FarmService.syncAll(player)
	return true, sp.name .. "! " .. sp.desc .. " for " .. sp.minutes .. " min"
end

---------------------------------------------------------------------------
-- Egg Shop
---------------------------------------------------------------------------
function ExtrasService.eggShopBuy(player: Player, id: any): (boolean, string?)
	local data = DataService.get(player)
	local item
	for _, it in Config.EGG_SHOP do
		if it.id == id then
			item = it
		end
	end
	if not item then
		return false, nil
	end
	if data.pearls < item.pearls then
		return false, "Need " .. item.pearls .. " pearls"
	end
	local els = { "Tide", "Coral", "Storm", "Abyss" }
	local el = els[rng:NextInteger(1, #els)]
	local sp = Config.TIER_OF[el][item.tier]
	local egg = { sp = sp, lvl = 1 + eggLevelBonus(data), stars = Stats.stars(sp), v = item.variant }
	local secs = math.floor(Stats.hatchSeconds(egg.lvl, Stats.stars(egg.sp)) * FarmService.hatchMult(player))
	if not FarmService.giveEgg(player, egg, secs) then
		return false, "Free a nest first!"
	end
	Analytics.tag(player, "Shop", item.id)
	data.pearls -= item.pearls
	Analytics.vendor(player, "EggShop", 2)
	DataService.changed(player)
	return true, "A " .. (item.variant and (item.variant .. " ") or "") .. Config.MONSTERS[sp].name .. " egg is in your nest!"
end

---------------------------------------------------------------------------
-- Gifts + daily
---------------------------------------------------------------------------
function ExtrasService.claimGift(player: Player, i: any): (boolean, string?)
	local data = DataService.get(player)
	local s = DataService.session(player)
	local g = typeof(i) == "number" and Config.GIFTS[i]
	if not g or s.giftsClaimed[i] then
		return false, nil
	end
	if os.time() - s.joinTime < g.min * 60 then
		return false, "Not ready yet"
	end
	if g.egg and not ExtrasService.giveRandomEgg(player, nil, g.egg, 1) then
		return false, "Free a nest first!"
	end
	s.giftsClaimed[i] = true
	Analytics.tag(player, "TimedReward", "Gift" .. i)
	Analytics.event(player, "GiftClaim", i)
	Analytics.vendor(player, "Gifts", 2)
	data.coins += g.coins or 0
	data.pearls += g.pearls or 0
	data.spins += g.spins or 0
	if g.shells and os.time() < Config.EVENT.endsAt then
		data.shells += g.shells
	end
	local msg = "Gift claimed!"
	if g.spell then
		local sp = ExtrasService.giveSpell(player, g.spell)
		if sp then
			msg = "Spell card: " .. sp.name .. "!"
		end
	end
	DataService.changed(player)
	return true, msg
end

-- A random spell card from a drop table's rarity weights (Config.SPELL_DROP[kind])
function ExtrasService.giveSpell(player: Player, kind: string): any
	local data = DataService.get(player)
	local drop = Config.SPELL_DROP[kind]
	if not data or not drop then
		return nil
	end
	local total = 0
	for _, w in drop.weights do
		total += w
	end
	local r = math.random() * total
	local rarity = 1
	for i, w in drop.weights do
		r -= w
		if r <= 0 then
			rarity = i
			break
		end
	end
	local pool = {}
	for _, sp in Config.SPELLS do
		if sp.rarity == rarity then
			table.insert(pool, sp)
		end
	end
	if #pool == 0 then
		return nil
	end
	local sp = pool[math.random(1, #pool)]
	data.spells[sp.id] = (tonumber(data.spells[sp.id]) or 0) + 1
	data.spellsFound[sp.id] = true
	Analytics.event(player, "SpellDrop", sp.rarity, { spell = sp.id })
	Remotes.event("Reveal"):FireClient(player, "spell", { id = sp.id })
	ExtrasService.checkSpellSets(player)
	return sp
end

-- Find every spell of a rarity and the Spellbook pays that rarity's set reward, once
function ExtrasService.checkSpellSets(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	for rarity, pearls in Config.SPELL_SETS do
		local key = tostring(rarity)
		if not data.spellSets[key] then
			local total, have = 0, 0
			for _, sp in Config.SPELLS do
				if sp.rarity == rarity then
					total += 1
					if data.spellsFound[sp.id] then
						have += 1
					end
				end
			end
			if total > 0 and have >= total then
				data.spellSets[key] = true
				data.pearls += pearls
				Analytics.event(player, "SpellSet", rarity)
				toast(player, "Spellbook set complete: every " .. Config.RARITY[rarity].name .. " spell! +" .. pearls .. " pearls", Config.RARITY[rarity].color)
				DataService.changed(player)
			end
		end
	end
end

-- Combine: spend SPELL_COMBINE cards of one rarity (the ones you hold most of first, so you keep
-- your variety) for one random card of the next rarity
function ExtrasService.combineSpells(player: Player, rarity: any): (boolean, string?)
	local data = DataService.get(player)
	if not data or typeof(rarity) ~= "number" or rarity < 1 or rarity >= #Config.RARITY then
		return false, nil
	end
	local owned = {}
	local total = 0
	for _, sp in Config.SPELLS do
		if sp.rarity == rarity then
			local n = tonumber(data.spells[sp.id]) or 0
			if n > 0 then
				table.insert(owned, { sp = sp, n = n })
				total += n
			end
		end
	end
	if total < Config.SPELL_COMBINE then
		return false, "Need " .. Config.SPELL_COMBINE .. " " .. Config.RARITY[rarity].name .. " cards (you have " .. total .. ")"
	end
	local pool = {}
	for _, sp in Config.SPELLS do
		if sp.rarity == rarity + 1 then
			table.insert(pool, sp)
		end
	end
	if #pool == 0 then
		return false, nil
	end
	for _ = 1, Config.SPELL_COMBINE do
		table.sort(owned, function(a, b)
			return a.n > b.n
		end)
		owned[1].n -= 1
		data.spells[owned[1].sp.id] = owned[1].n
	end
	local sp = pool[math.random(1, #pool)]
	data.spells[sp.id] = (tonumber(data.spells[sp.id]) or 0) + 1
	data.spellsFound[sp.id] = true
	Analytics.event(player, "SpellCombine", rarity, { spell = sp.id })
	Remotes.event("Reveal"):FireClient(player, "spell", { id = sp.id })
	ExtrasService.checkSpellSets(player)
	DataService.changed(player)
	return true, "Combined into " .. sp.name .. " (" .. Config.RARITY[sp.rarity].name .. ")!"
end

function ExtrasService.claimDaily(player: Player): (boolean, string?)
	local data = DataService.get(player)
	local today = os.time() // 86400
	if data.dailyDay == today then
		return false, "Come back tomorrow!"
	end
	data.dailyStreak = if data.dailyDay == today - 1 then data.dailyStreak + 1 else 1
	data.dailyDay = today
	Analytics.tag(player, "TimedReward", "Daily")
	Analytics.event(player, "DailyClaim", data.dailyStreak)
	local day = (data.dailyStreak - 1) % #Config.DAILY_PEARLS + 1
	local pearls = Config.DAILY_PEARLS[day]
	data.pearls += pearls
	if os.time() < Config.EVENT.endsAt then
		data.shells += 25
	end
	-- every daily chest holds a spell card too (boss-quality odds)
	ExtrasService.giveSpell(player, "boss")
	DataService.changed(player)
	return true, "Day " .. data.dailyStreak .. ": +" .. pearls .. " pearls and a spell card!"
end

---------------------------------------------------------------------------
-- Retention: group reward, favourite prompt, friends coin boost
---------------------------------------------------------------------------
-- Joined the group? A free egg + spins, once. Checked on join and from the Gift Chest.
function ExtrasService.claimGroup(player: Player): (boolean, string?)
	local data = DataService.get(player)
	if Config.GROUP_ID == 0 or not data then
		return false, nil
	end
	if data.groupEgg then
		return false, "You already got the crew reward!"
	end
	local ok, inGroup = pcall(function()
		return player:IsInGroup(Config.GROUP_ID)
	end)
	if not ok or not inGroup then
		return false, "Join the group to get a free egg!"
	end
	local r = Config.GROUP_REWARD
	if not ExtrasService.giveRandomEgg(player, nil, r.levels, r.stars) then
		return false, "Free a nest first!"
	end
	data.groupEgg = true
	data.spins += r.spins
	DataService.changed(player)
	Analytics.event(player, "GroupReward", 1)
	return true, "Welcome to the crew! A free egg and " .. r.spins .. " Power spins"
end

-- The client asked to favourite (once); remember so we never ask again
function ExtrasService.favorite(player: Player, result: any): (boolean, string?)
	local data = DataService.get(player)
	if data.favAsked then
		return false, nil
	end
	data.favAsked = true
	DataService.changed(player)
	Analytics.event(player, "FavoritePrompt", if result == true then 1 else 0)
	return true, nil
end

-- Friends in the same server: each one adds Config.FRIEND_BOOST battle coins (attribute "Friends")
local Players = game:GetService("Players")
local friendCache: { [string]: boolean } = {}
local function areFriends(a: Player, b: Player): boolean
	local k = math.min(a.UserId, b.UserId) .. ":" .. math.max(a.UserId, b.UserId)
	if friendCache[k] == nil then
		local ok, yes = pcall(function()
			return a:IsFriendsWith(b.UserId)
		end)
		friendCache[k] = ok and yes == true
	end
	return friendCache[k]
end

local function refreshFriends()
	local list = Players:GetPlayers()
	for _, p in list do
		local n = 0
		for _, q in list do
			if q ~= p and areFriends(p, q) then
				n += 1
			end
		end
		p:SetAttribute("Friends", math.min(n, Config.FRIEND_BOOST_MAX))
	end
end

function ExtrasService.init()
	Players.PlayerAdded:Connect(function()
		task.wait(3)
		refreshFriends()
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(refreshFriends)
	end)
	task.spawn(refreshFriends)
	DataService.Loaded:Connect(function(player)
		task.delay(8, function()
			local data = DataService.get(player)
			if player.Parent and data and not data.groupEgg then
				local ok, msg = ExtrasService.claimGroup(player)
				if ok and msg then
					toast(player, msg, Color3.fromRGB(255, 205, 60))
				end
			end
		end)
	end)
	-- hub stands (built by WorldBuilder) open menus on the client; the Abyss Crate rolls here
	local hub = workspace:WaitForChild("World"):WaitForChild("Harbour")
	for _, d in hub:GetDescendants() do
		if d:IsA("ProximityPrompt") and d.Name == "LimitedPrompt" then
			d.Triggered:Connect(function(player)
				Analytics.vendor(player, "Crate", 1)
				local ok, msg = ExtrasService.limitedRoll(player, false)
				if not ok and msg then
					toast(player, msg, Color3.fromRGB(255, 90, 90))
				end
			end)
		end
	end
end

return ExtrasService
