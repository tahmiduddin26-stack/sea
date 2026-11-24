--!strict
-- The ship farm: gives each player a ship, rolls eggs at the winch, sells them from the
-- pedestals, lets players carry an egg to a nest, hatches it, and fuses two monsters
-- into one stronger one. Mirrors every nest/pedestal state onto the parts as attributes
-- so every client can draw the monsters, and drives the tutorial steps.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Stats = require(Shared.Stats)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local Analytics = require(script.Parent.Analytics)
local MissionService = require(script.Parent.MissionService)
local WorldBuilder = require(script.Parent.WorldBuilder)

local FarmService = {}

local owners: { [number]: Player } = {} -- ship index -> player
local rng = Random.new()

local function toast(player: Player, text: string, color: Color3?)
	Remotes.event("Toast"):FireClient(player, text, color)
end

---------------------------------------------------------------------------
-- Tutorial
---------------------------------------------------------------------------
-- Move the tutorial on, but only if the player is exactly on `from`.
function FarmService.tutorial(player: Player, from: number)
	local data = DataService.get(player)
	-- steps past the end (old hooks for the removed post-fuse steps) never advance anything
	if not data or data.tutorial ~= from or from >= Config.TUTORIAL_DONE then
		return
	end
	data.tutorial = from + 1
	Analytics.tutorialStep(player, data.tutorial)
	DataService.changed(player)
	Remotes.event("Tutorial"):FireClient(player, data.tutorial)
	-- tutorial finished: the rest of the ship's nests appear
	if data.tutorial == Config.TUTORIAL_DONE then
		FarmService.syncAll(player)
	end
end

function FarmService.inTutorial(player: Player): boolean
	local data = DataService.get(player)
	return data ~= nil and data.tutorial < Config.TUTORIAL_DONE
end

---------------------------------------------------------------------------
-- Ships
---------------------------------------------------------------------------
function FarmService.shipOf(player: Player): WorldBuilder.Ship?
	local s = DataService.session(player)
	if not s or s.shipIndex == 0 then
		return nil
	end
	return WorldBuilder.ships[s.shipIndex]
end

function FarmService.ownerOf(index: number): Player?
	return owners[index]
end

local function passes(player: Player)
	local s = DataService.session(player)
	return if s then s.passes else {}
end

-- Active spells: multiply every active spell's value for `key` (eggLuck, coins, dmg ...)
function FarmService.spellMult(player: Player, key: string): number
	local data = DataService.get(player)
	local m = 1
	if not data or not data.spellUntil then
		return m
	end
	local now = os.time()
	for _, sp in Config.SPELLS do
		local v = sp.effects[key]
		if v and (data.spellUntil[sp.id] or 0) > now then
			m *= v
		end
	end
	return m
end

-- ...or add them (pedestals)
function FarmService.spellAdd(player: Player, key: string): number
	local data = DataService.get(player)
	local n = 0
	if not data or not data.spellUntil then
		return n
	end
	local now = os.time()
	for _, sp in Config.SPELLS do
		local v = sp.effects[key]
		if v and (data.spellUntil[sp.id] or 0) > now then
			n += v
		end
	end
	return n
end

function FarmService.hatchMult(player: Player): number
	local m = if passes(player).FastFuse then 0.5 else 1
	local data = DataService.get(player)
	-- every Shipwright tier hatches a little faster (never more than 40% off)
	m *= 1 - math.min(0.4, ((data and data.shipTier) or 0) * Config.SHIPWRIGHT.hatchPerTier)
	return m / FarmService.spellMult(player, "hatch")
end

-- Fuse luck: Fuse Luck products and the Fuse Fortune spell multiply together
function FarmService.luckMult(player: Player): number
	local data = DataService.get(player)
	local m = 1
	if data and data.luckUntil > os.time() then
		m = data.luckMult
	end
	local s = DataService.session(player)
	if s and s.passes.DoubleLuck then
		m *= 2
	end
	if data and (data.luck30Until or 0) > os.time() then
		m *= 2
	end
	return m * FarmService.spellMult(player, "fuseLuck")
end

function FarmService.ownsNest(data: any, i: number): boolean
	return i <= Config.START_NESTS or data.nestsOwned[tostring(i)] == true
end

-- Mirror one nest's state onto its pad (everyone's client reads these)
function FarmService.syncNest(player: Player, i: number)
	local ship = FarmService.shipOf(player)
	local data = DataService.get(player)
	if not ship or not data then
		return
	end
	local pad = ship.nests[i]
	local prompt = pad:FindFirstChild("NestPrompt") :: ProximityPrompt
	local slot = Config.NEST_SLOTS[i]
	local nest = data.nests[tostring(i)]
	local s = DataService.session(player)
	pad:SetAttribute("Owner", player.UserId)
	-- VIP Captain pass: your nests turn gold
	if pad:GetAttribute("BaseColor") == nil then
		pad:SetAttribute("BaseColor", pad.Color)
	end
	local gold = s ~= nil and s.passes ~= nil and s.passes.VIP == true
	pad.Color = if gold then Color3.fromRGB(255, 200, 60) else pad:GetAttribute("BaseColor") :: Color3
	pad.Material = if gold then Enum.Material.Foil else Enum.Material.SmoothPlastic
	pad:SetAttribute("Uid", nil)
	pad:SetAttribute("Sp", nil)
	pad:SetAttribute("Lvl", nil)
	pad:SetAttribute("Stars", nil)
	pad:SetAttribute("ReadyAt", nil)
	pad:SetAttribute("InBattle", nil)
	pad:SetAttribute("Variant", nil)
	pad:SetAttribute("Perk", nil)
	pad:SetAttribute("RestUntil", nil)
	prompt:SetAttribute("Live", true)
	prompt.HoldDuration = 0
	pad:SetAttribute("Price", nil)
	-- the buyable nests stay hidden until you own NEST_REVEAL_MONSTERS monsters (your free nests are full)
	local owned = 0
	for _ in data.monsters do
		owned += 1
	end
	-- Once revealed they STAY revealed: fusing or selling down to 2 monsters must not hide the nests you
	-- can buy again. Revealed when you have owned enough monsters, finished the tutorial, or bought one.
	if not data.nestsRevealed and (owned >= Config.NEST_REVEAL_MONSTERS or data.tutorial >= Config.TUTORIAL_DONE or (data.nestCount or 0) > 0) then
		data.nestsRevealed = true
	end
	local hidden = i > Config.START_NESTS and not FarmService.ownsNest(data, i) and not data.nestsRevealed
	for _, p in { pad, table.unpack(pad:GetChildren()) } do
		if p:IsA("BasePart") then
			p.Transparency = if hidden then 1 else 0
			p.CanCollide = not hidden
		end
	end
	if hidden then
		pad:SetAttribute("State", "hidden")
		prompt:SetAttribute("Live", false)
		return
	end
	if not FarmService.ownsNest(data, i) then
		if slot.floor >= 2 and data.floor < slot.floor then
			pad:SetAttribute("State", "locked2")
			prompt:SetAttribute("Live", false)
		else
			-- every buyable nest shows the price of your next nest
			local price = Stats.nestPrice(data.nestCount)
			pad:SetAttribute("State", "locked")
			pad:SetAttribute("Price", price)
			prompt.ActionText = "Buy Nest"
			prompt.ObjectText = Format.abbrev(price) .. " Coins"
			prompt.HoldDuration = 0.3
			prompt:SetAttribute("Live", true)
		end
		return
	end
	if not nest then
		pad:SetAttribute("State", "empty")
		prompt.ActionText = "Place Egg"
		prompt.ObjectText = "Nest"
		return
	end
	if nest.kind == "mon" then
		local m = data.monsters[nest.uid]
		pad:SetAttribute("State", "mon")
		pad:SetAttribute("Uid", nest.uid)
		if m then
			pad:SetAttribute("Sp", m.sp)
			pad:SetAttribute("Variant", m.v)
			pad:SetAttribute("Lvl", m.lvl)
			pad:SetAttribute("Stars", Stats.shownStars(m.sp, m.x6))
			pad:SetAttribute("Perk", m.perk) -- Deep Rod perk (shown on the name tag)
			-- fainted in a fight: it rests until this os.time (the name tag counts it down)
			pad:SetAttribute("RestUntil", if (m.restUntil or 0) > os.time() then m.restUntil else nil)
		end
		pad:SetAttribute("InBattle", if s and s.fighting and s.fighting[nest.uid] then true else nil)
		-- fusing happens in the world: E on a monster picks it (handled on the client)
		prompt.ActionText = "Fuse"
		prompt.ObjectText = (if m then Config.MONSTERS[m.sp].name .. " Lv." .. m.lvl else "")
		prompt:SetAttribute("Live", not (s and s.inBattle))
		return
	end
	local item = if nest.kind == "egg" then nest.egg else nest.child
	pad:SetAttribute("State", nest.kind)
	pad:SetAttribute("Sp", item.sp)
	pad:SetAttribute("Variant", item.v)
	pad:SetAttribute("Lvl", item.lvl)
	pad:SetAttribute("Stars", Stats.shownStars(item.sp, item.x6))
	pad:SetAttribute("ReadyAt", nest.readyAt)
	local left = nest.readyAt - os.time()
	if left <= 0 then
		prompt.ActionText = "Open"
		prompt.ObjectText = if nest.kind == "egg" then "Egg" else "Fused Monster"
		prompt:SetAttribute("Live", true) -- fused eggs open by themselves, and a tap opens them too
	else
		prompt.ActionText = "Hatch Now"
		prompt.ObjectText = "R$" .. Config.PRODUCTS.SkipTimer.price .. " · 5 min"
		prompt.HoldDuration = 0.4
		-- a fuse only lasts a couple of seconds: no Hatch Now offer, just let it finish
		prompt:SetAttribute("Live", nest.kind ~= "fuse")
	end
end

function FarmService.syncAll(player: Player)
	local ship = FarmService.shipOf(player)
	if not ship then
		return
	end
	for i in Config.NEST_SLOTS do
		FarmService.syncNest(player, i)
	end
	FarmService.syncPedestals(player)
	WorldBuilder.applyShipTier(ship, DataService.get(player).shipTier or 0)
	WorldBuilder.applyPaint(ship, DataService.get(player).paint)
	WorldBuilder.applyFittings(ship, DataService.get(player).fittings)
	ship.quarterBarrier.CanCollide = (DataService.get(player).floor or 1) < 2
	ship.quarterBarrier.Transparency = if ship.quarterBarrier.CanCollide then 0.5 else 1
	local bb = ship.quarterBarrier:FindFirstChildOfClass("BillboardGui")
	if bb then
		bb.Enabled = ship.quarterBarrier.CanCollide
	end
	-- the stairs up to the poop deck (Floor 3) stay shut until it is bought
	local b3 = ship.floor3Barrier
	b3.CanCollide = (DataService.get(player).floor or 1) < 3
	b3.Transparency = if b3.CanCollide then 0.5 else 1
	local bb3 = b3:FindFirstChildOfClass("BillboardGui")
	if bb3 then
		bb3.Enabled = b3.CanCollide
	end
end

function FarmService.syncPedestals(player: Player)
	local ship = FarmService.shipOf(player)
	local data = DataService.get(player)
	local s = DataService.session(player)
	if not ship or not data or not s then
		return
	end
	local count = FarmService.pedestalCount(player)
	for i, ped in ship.pedestals do
		local egg = s.pedestalEggs[i]
		local prompt = ped:FindFirstChild("BuyPrompt") :: ProximityPrompt
		ped:SetAttribute("Owner", player.UserId)
		-- the last pedestal is the Deep Rod's: shown whenever a deep egg sits on it
		ped:SetAttribute("Active", i <= count or egg ~= nil)
		if egg then
			ped:SetAttribute("Sp", egg.sp)
			ped:SetAttribute("Lvl", egg.lvl)
			ped:SetAttribute("Stars", egg.stars)
			ped:SetAttribute("Variant", egg.v)
			ped:SetAttribute("Price", egg.price)
			prompt:SetAttribute("Live", true)
			prompt.ActionText = "Take"
			prompt.ObjectText = if (egg.price or 0) <= 0 then "Egg" else Format.abbrev(egg.price) .. " Coins"
		else
			ped:SetAttribute("Sp", nil)
			ped:SetAttribute("Price", nil)
			-- holding an egg with no free nest? An empty pedestal takes it back (refunding what you paid)
			if s.carrying and i <= count and data.tutorial >= Config.TUTORIAL_DONE then
				prompt:SetAttribute("Live", true)
				prompt.ActionText = "Put Back"
				prompt.ObjectText = "Egg"
			else
				prompt:SetAttribute("Live", false)
			end
		end
	end
end

function FarmService.pedestalCount(player: Player): number
	local data = DataService.get(player)
	local n = data and data.upgrades.Pedestals or 1
	if passes(player).ExtraPedestal then
		n += 1
	end
	n += FarmService.spellAdd(player, "pedestals")
	if FarmService.inTutorial(player) then
		n = 1
	end
	return math.clamp(n, 1, #Config.PEDESTAL_POS)
end

local function updateSign(player: Player?, ship: WorldBuilder.Ship)
	local text = ship.sign:FindFirstChild("Text") :: TextLabel
	local best = ship.sign:FindFirstChild("Best") :: TextLabel
	ship.sign.Enabled = player ~= nil
	if player then
		local data = DataService.get(player)
		text.Text = player.DisplayName .. "'s Ship"
		best.Text = "Best Depth: " .. (if data then data.bestDepth else 0)
	else
		text.Text = ""
		best.Text = ""
	end
end

function FarmService.updateSign(player: Player)
	local ship = FarmService.shipOf(player)
	if ship then
		updateSign(player, ship)
	end
end

local function clearShip(ship: WorldBuilder.Ship)
	for _, pad in ship.nests do
		for _, a in { "Owner", "State", "Uid", "Sp", "Lvl", "Stars", "ReadyAt", "InBattle", "Price", "Variant", "RestUntil" } do
			pad:SetAttribute(a, nil)
		end
		(pad:FindFirstChild("NestPrompt") :: ProximityPrompt):SetAttribute("Live", false)
		for _, p in { pad, table.unpack(pad:GetChildren()) } do
			if p:IsA("BasePart") then
				p.Transparency = 0
				p.CanCollide = true
			end
		end
	end
	for _, ped in ship.pedestals do
		ped:SetAttribute("Owner", nil)
		ped:SetAttribute("Sp", nil)
		ped:SetAttribute("Active", nil)
		;(ped:FindFirstChild("BuyPrompt") :: ProximityPrompt):SetAttribute("Live", false)
	end
	ship.model:SetAttribute("Owner", nil)
	WorldBuilder.applyShipTier(ship, 0)
	WorldBuilder.applyPaint(ship, nil)
	WorldBuilder.applyFittings(ship, nil)
	updateSign(nil, ship)
end

function FarmService.spawnAtShip(player: Player)
	local ship = FarmService.shipOf(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if ship and root then
		root.CFrame = ship.spawnCf
	end
end

local function assignShip(player: Player)
	for i = 1, Config.SHIP_COUNT do
		if not owners[i] then
			owners[i] = player
			local s = DataService.session(player)
			s.shipIndex = i
			local ship = WorldBuilder.ships[i]
			ship.model:SetAttribute("Owner", player.UserId)
			player:SetAttribute("Ship", i)
			WorldBuilder.setCrew(player, i) -- only this crew can pass the ship's boarding gate
			updateSign(player, ship)
			FarmService.syncDeepRod(player)
			FarmService.syncAbyssRod(player)
			FarmService.syncAll(player)
			return
		end
	end
	warn("[Farm] no free ship for", player.Name)
end

---------------------------------------------------------------------------
-- Eggs
---------------------------------------------------------------------------
local function pickWeighted<T>(items: { T }, weights: { number }): T
	local total = 0
	for _, w in weights do
		total += w
	end
	local r = rng:NextNumber() * total
	for i, w in weights do
		r -= w
		if r <= 0 then
			return items[i]
		end
	end
	return items[#items]
end

-- Everything that raises winch luck, as one multiplier shown on the HUD ("Luck x1.6"):
-- the Egg Luck upgrade, an active Lucky Tide spell, the VIP pass.
function FarmService.eggLuck(player: Player): number
	local data = DataService.get(player)
	local s = DataService.session(player)
	local m = 1 + (data.upgrades.Luck or 0) * 0.1
	m *= FarmService.spellMult(player, "eggLuck")
	if s and s.passes.VIP then
		m *= 1.2
	end
	if s and s.passes.DoubleLuck then
		m *= 2
	end
	if (data.luck30Until or 0) > os.time() then
		m *= 2
	end
	m *= 1 + ((data.fittings or {}).Figurehead or 0) * Config.FITTINGS.Figurehead.luck
	return m
end

-- Secret new-player luck (Config.EARLY_LUCK): fades to 1 over the first minutes of play. Applied
-- on top of eggLuck inside the rolls only, so it never shows on screen.
function FarmService.rollLuck(player: Player): number
	local over = DataService.playSeconds(player) - Config.EARLY_LUCK_MINUTES * 60 -- seconds past the full-luck start
	local fade = math.clamp(1 - over / (Config.EARLY_LUCK_FADE_MINUTES * 60), 0, 1)
	return FarmService.eggLuck(player) * (1 + (Config.EARLY_LUCK - 1) * fade)
end

-- The shortest an egg / fuse timer can be for this player right now (short for brand-new players)
function FarmService.timerFloor(player: Player): number
	-- the tutorial is always fast: a slow first session must never meet a minutes-long first fuse
	if FarmService.inTutorial(player) then
		return Config.HATCH_CURVE.min
	end
	return Stats.timerFloor(DataService.playSeconds(player))
end

function FarmService.rollVariant(player: Player): string
	local luck = FarmService.rollLuck(player)
	local weights = {}
	local ids = {}
	for i, v in Config.VARIANTS do
		table.insert(ids, v.id)
		table.insert(weights, if i == 1 then v.weight else v.weight * luck * FarmService.spellMult(player, "mutation"))
	end
	return pickWeighted(ids, weights)
end

-- forceEl: the zone's element; hybrid: the Abyss zone (a random 2-star hybrid or better)
function FarmService.rollEgg(player: Player, forceEl: string?, hybrid: boolean?, luckMult: number?)
	local data = DataService.get(player)
	local els, ews = {}, {}
	for el, w in Config.ELEMENT_WEIGHTS do
		table.insert(els, el)
		table.insert(ews, w)
	end
	local el = forceEl or pickWeighted(els, ews)
	if hybrid then
		local hs = {}
		for h, up in Config.HYBRID_UP do
			table.insert(hs, h)
			table.insert(hs, h)
			table.insert(hs, up) -- a 1-in-3 shot at the 3-star evolution
		end
		local sp = hs[rng:NextInteger(1, #hs)]
		local stars = Stats.stars(sp)
		local lvl = math.min(Stats.levelCap(data.bestDepth), pickWeighted({ 1, 2, 3 }, Config.EGG_LEVEL_WEIGHTS) + math.max(0, Stats.stageOf(math.max(1, data.bestDepth)) - 1) * Config.EGG_LEVEL_PER_STAGE)
		local v = FarmService.rollVariant(player)
		local price = Stats.eggPrice(sp, lvl, stars, rng:NextNumber()) * (if v == "Rainbow" then 6 elseif v == "Golden" then 2.5 else 1)
		return { sp = sp, lvl = lvl, stars = stars, v = v, price = math.floor(price) }
	end
	-- rarity: luck moves weight from Common up to Rare / Epic of that element's line
	local luck = FarmService.rollLuck(player) * (luckMult or 1)
	local sw = table.clone(Config.STAR_WEIGHTS)
	for k = 2, #sw do
		sw[k] *= luck ^ (k - 1)
	end
	local tier = pickWeighted({ 1, 2, 3 }, sw)
	local sp = Config.TIER_OF[el][tier]
	local stars = Stats.stars(sp)
	local lvl = pickWeighted({ 1, 2, 3 }, Config.EGG_LEVEL_WEIGHTS)
	lvl += math.max(0, Stats.stageOf(math.max(1, data.bestDepth)) - 1) * Config.EGG_LEVEL_PER_STAGE
	lvl = math.min(lvl, Stats.levelCap(data.bestDepth))
	local v = FarmService.rollVariant(player)
	local price = Stats.eggPrice(sp, lvl, stars, rng:NextNumber()) * (if v == "Rainbow" then 6 elseif v == "Golden" then 2.5 else 1)
	return { sp = sp, lvl = lvl, stars = stars, v = v, price = math.floor(price) }
end

-- Seconds until this player's Deep Rod can cast (0 = ready) and whether it is still locked
-- behind Config.DEEP_ROD.unlockMinutes of play.
function FarmService.deepRodWait(player: Player): (number, boolean)
	local data = DataService.get(player)
	if not data then
		return 0, true
	end
	local lockLeft = Config.DEEP_ROD.unlockMinutes * 60 - DataService.playSeconds(player)
	if lockLeft > 0 then
		return math.ceil(lockLeft), true
	end
	return math.max(0, (data.deepRodAt or 0) + Config.DEEP_ROD.cooldown - os.time()), false
end

-- Tell the owner's client when the Deep Rod unlocks and when its next cast is ready (os.time;
-- play time only grows while you are on, so one stamp per join / cast stays right)
function FarmService.syncDeepRod(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local now = os.time()
	local unlockAt = now + math.max(0, math.ceil(Config.DEEP_ROD.unlockMinutes * 60 - DataService.playSeconds(player)))
	player:SetAttribute("DeepUnlockAt", unlockAt)
	player:SetAttribute("DeepReadyAt", math.max(unlockAt, (data.deepRodAt or 0) + Config.DEEP_ROD.cooldown))
end

-- The Abyss Rod (Floor 3 balcony): seconds until it can cast and why it can't yet
-- ("floor" = Floor 3 not bought, "time" = still locked behind play time, nil = just cooling down)
function FarmService.abyssRodWait(player: Player): (number, string?)
	local data = DataService.get(player)
	if not data then
		return 0, "time"
	end
	if (data.floor or 1) < 3 then
		return 0, "floor"
	end
	local lockLeft = Config.ABYSS_ROD.unlockMinutes * 60 - DataService.playSeconds(player)
	if lockLeft > 0 then
		return math.ceil(lockLeft), "time"
	end
	return math.max(0, (data.abyssRodAt or 0) + Config.ABYSS_ROD.cooldown - os.time()), nil
end

function FarmService.syncAbyssRod(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local now = os.time()
	local unlockAt = now + math.max(0, math.ceil(Config.ABYSS_ROD.unlockMinutes * 60 - DataService.playSeconds(player)))
	player:SetAttribute("AbyssUnlockAt", unlockAt)
	player:SetAttribute("AbyssReadyAt", math.max(unlockAt, (data.abyssRodAt or 0) + Config.ABYSS_ROD.cooldown))
	player:SetAttribute("AbyssFloor", (data.floor or 1) >= 3)
end

-- A Legendary or Mythic egg from the Abyss Rod's bottom zones (element = the zone's, or any)
local function rareAbyssEgg(player: Player, el: string?, mythic: boolean): any
	local data = DataService.get(player)
	local pool = {}
	for id, def in Config.MONSTERS do
		local want = if mythic then 5 else 4
		if def.stars == want and (el == nil or table.find(def.elements, el)) then
			table.insert(pool, id)
		end
	end
	if #pool == 0 then
		return nil
	end
	local sp = pool[rng:NextInteger(1, #pool)]
	local lvl = pickWeighted({ 1, 2, 3 }, Config.EGG_LEVEL_WEIGHTS) + math.max(0, Stats.stageOf(math.max(1, data.bestDepth)) - 1) * Config.EGG_LEVEL_PER_STAGE
	lvl = math.min(lvl, Stats.levelCap(data.bestDepth))
	return { sp = sp, lvl = lvl, stars = Stats.stars(sp), v = FarmService.rollVariant(player), price = 0 }
end

-- kind: nil = Egg Rod, true / "deep" = Deep Rod, "abyss" = Abyss Rod
local function haul(player: Player, kind: any)
	local s = DataService.session(player)
	local data = DataService.get(player)
	if not s or not data then
		return
	end
	local info = Config.rodInfo(kind)
	local abyss = info.kind == "abyss"
	local deep = info.kind ~= nil -- the Deep and Abyss Rods share the special-rod rules
	if os.clock() - s.lastRoll < Config.ROLL_COOLDOWN then
		return
	end
	if s.fishing then
		return
	end
	if deep then
		-- (no tutorial check: the rods only wait for their own unlock time, see below)
		local PINK = Color3.fromRGB(255, 90, 170)
		if abyss then
			local wait, why = FarmService.abyssRodWait(player)
			if why == "floor" then
				toast(player, "Unlock Floor 3 to use the Abyss Rod", PINK)
				return
			elseif why == "time" then
				toast(player, "The Abyss Rod unlocks after " .. math.floor(Config.ABYSS_ROD.unlockMinutes / 60) .. " hours of play (" .. Format.time(wait) .. " left)", PINK)
				return
			elseif wait > 0 then
				toast(player, "The Abyss Rod is ready in " .. Format.time(wait), PINK)
				return
			end
		else
			local wait, locked = FarmService.deepRodWait(player)
			if locked then
				toast(player, "The Deep Rod unlocks after " .. Config.DEEP_ROD.unlockMinutes .. " minutes of play (" .. Format.time(wait) .. " left)", Color3.fromRGB(170, 130, 255))
				return
			elseif wait > 0 then
				toast(player, "The Deep Rod is ready in " .. Format.time(wait), Color3.fromRGB(170, 130, 255))
				return
			end
		end
	end
	-- every catch STACKS on the next free pedestal: an egg you haven't taken is never replaced.
	-- The Deep Rod prefers its own pedestal (the last deck one), the Egg Rod fills from the first.
	-- The Abyss Rod only ever uses its own pedestal on the balcony (so the egg never flies across
	-- the whole ship); if that one is still full it waits.
	local DEEP_SLOT = #Config.PEDESTAL_POS
	local ABYSS_SLOT = #Config.PEDESTAL_POS + 1
	local slot: number? = nil
	if abyss then
		if s.pedestalEggs[ABYSS_SLOT] then
			toast(player, "Take the egg on the Abyss Rod's pedestal first!", Color3.fromRGB(255, 200, 60))
			return
		end
		slot = ABYSS_SLOT
	elseif deep and not s.pedestalEggs[DEEP_SLOT] then
		slot = DEEP_SLOT
	else
		for i = 1, #Config.PEDESTAL_POS do
			if not s.pedestalEggs[i] then
				slot = i
				break
			end
		end
	end
	if not slot then
		toast(player, "Pedestals full! Take an egg before you fish again", Color3.fromRGB(255, 200, 60))
		return
	end
	local mySlot = slot :: number
	if abyss then
		data.abyssRodAt = os.time()
	elseif deep then
		data.deepRodAt = os.time()
	end
	s.lastRoll = os.clock()
	local ZONES = info.zones
	local rodLuck = if abyss then Config.ABYSS_ROD.luck else Config.DEEP_ROD.luck
	-- roll the zone the hook stops in (Egg Luck makes the deep zones likelier)
	local scripted = if deep then nil else Config.TUTORIAL_EGGS[data.tutorial]
	local zone = 1
	if deep then
		local luck = FarmService.rollLuck(player) * rodLuck
		local ids, ws = {}, {}
		for k, z in ZONES do
			table.insert(ids, k)
			table.insert(ws, z.weight * luck ^ ((k - 1) / 3))
		end
		zone = pickWeighted(ids, ws)
	elseif scripted then
		local el = Config.MONSTERS[scripted.sp].elements[1]
		for k, z in Config.FISH_ZONES do
			if z.element == el then
				zone = k
			end
		end
	else
		local luck = FarmService.rollLuck(player)
		local ids, ws = {}, {}
		for k, z in Config.FISH_ZONES do
			table.insert(ids, k)
			table.insert(ws, z.weight * luck ^ ((k - 1) / 2))
		end
		zone = pickWeighted(ids, ws)
	end
	-- Fast Reel: every pedestal level (upgrade, pass or spell) makes the whole cast 8% quicker
	local reel = 1 - 0.08 * (FarmService.pedestalCount(player) - 1)
	local time = (Config.FISH_BASE + zone * info.perZone) * math.max(0.6, reel)
	-- the rod casts and dives: the pedestals empty now and the catch lands on them when the
	-- line comes up (every client plays the same dive from "haul")
	s.fishing = true
	MissionService.record(player, "fish", 1)
	Analytics.event(player, "RodCast", 1, { rod = info.kind or "egg", zone = zone }) -- also the Loop funnel's "fished an egg"
	-- the Deep Rod has its own pedestal (the last one), so the two rods never clear each other's eggs
	-- one egg per cast: the hook pulls a single egg out of a rock nest on the sea floor
	local count = 1
	Remotes.event("Battle"):FireAllClients(player.UserId, "haul", { count = count, zone = zone, time = time, deep = deep, rod = info.kind, slot = mySlot })
	if abyss then
		DataService.changed(player) -- the cooldown starts now (abyssRodAt)
		FarmService.syncAbyssRod(player)
	elseif deep then
		DataService.changed(player) -- the cooldown starts now (deepRodAt)
		FarmService.syncDeepRod(player)
	end
	-- the captain steps up to the rod and holds it for the whole cast (clients pose the arms)
	do
		local ship = FarmService.shipOf(player)
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local rod = ship and ship.model:FindFirstChild(info.model)
		local rodCf = rod and rod:GetAttribute("RodCf") :: CFrame?
		if root and hum and rodCf then
			local S = Config.ROD_SCALE
			-- behind and a little right of the handle, facing out to sea (-Z of the rod frame)
			root.CFrame = rodCf * CFrame.new(1.4, -4.2 * S + 1.4 + hum.HipHeight + root.Size.Y / 2, 4.6 * S / 1.7 + 1.2)
			local speed, jump = hum.WalkSpeed, hum.JumpPower
			hum.WalkSpeed = 0
			hum.JumpPower = 0
			hum.AutoRotate = false
			player:SetAttribute("Fishing", true)
			task.delay(time, function()
				if hum.Parent then
					hum.WalkSpeed = speed
					hum.JumpPower = jump
					hum.AutoRotate = true
				end
				player:SetAttribute("Fishing", nil)
			end)
		end
	end
	task.delay(time, function()
		s.fishing = false
		if not DataService.get(player) or DataService.session(player) ~= s then
			return
		end
		scripted = if deep then nil else Config.TUTORIAL_EGGS[data.tutorial]
		local new: any
		if scripted then
			new = table.clone(scripted)
		elseif deep then
			-- the Deep Rod: 50% luckier, always free, and the deeper the zone the likelier a perk.
			-- The Abyss Rod: luckier still, its own perks, and Legendary / Mythic eggs at the bottom.
			local z = ZONES[zone]
			local e: any = nil
			if abyss and z.mythic and rng:NextNumber() < z.mythic then
				e = rareAbyssEgg(player, nil, true)
			end
			if not e and abyss and z.legend and rng:NextNumber() < z.legend then
				e = rareAbyssEgg(player, z.element, false)
			end
			e = e or FarmService.rollEgg(player, z.element, z.element == nil, rodLuck)
			local order = if abyss then Config.ABYSS_PERK_ORDER else Config.PERK_ORDER
			if rng:NextNumber() < z.perk then
				e.perk = order[rng:NextInteger(1, #order)]
			end
			e.price = 0
			new = e
		else
			-- one egg per cast, and a single catch is always free (same as before: the "never every
			-- egg on one cast" rule meant a lone egg never became a Treasure Egg)
			local el = Config.FISH_ZONES[zone].element
			new = FarmService.rollEgg(player, el, el == nil)
			new.price = 0
		end
		-- lands on the pedestal picked at cast time; earlier untaken eggs stay where they are
		new.price = new.price or 0 -- tutorial eggs come without a price
		-- every egg caught before the tutorial ends is Lv1, so your first and second monsters can
		-- always be fused (fusing needs the same level)
		if data.tutorial < Config.TUTORIAL_DONE then
			new.lvl = 1
		end
		s.pedestalEggs[mySlot] = new
		FarmService.syncPedestals(player)
		DataService.changed(player)
		FarmService.tutorial(player, 1)
		FarmService.tutorial(player, 6)
		FarmService.tutorial(player, 12)
	end)
end

local function setCarrying(player: Player, egg: any)
	local s = DataService.session(player)
	s.carrying = egg
	if egg then
		player:SetAttribute("Carrying", egg.sp .. ":" .. egg.lvl .. ":" .. egg.stars .. ":" .. (egg.v or "Normal"))
	else
		player:SetAttribute("Carrying", nil)
	end
	FarmService.syncPedestals(player) -- empty pedestals offer "Put Back" while you hold an egg
	DataService.changed(player)
end

local function buyEgg(player: Player, i: number)
	local s = DataService.session(player)
	local data = DataService.get(player)
	local egg = s and s.pedestalEggs[i]
	if not egg then
		-- an empty pedestal while holding an egg: put it back (e.g. you picked it up and have no free nest)
		local c = s and s.carrying
		if c and i <= FarmService.pedestalCount(player) and data.tutorial >= Config.TUTORIAL_DONE then
			local paid = c.paid or 0
			data.coins += paid -- what you paid comes back, and the egg costs the same again if you retake it
			s.pedestalEggs[i] = { sp = c.sp, lvl = c.lvl, stars = c.stars, v = c.v, perk = c.perk, price = paid }
			setCarrying(player, nil)
			FarmService.syncPedestals(player)
			toast(player, "Egg put back", Color3.fromRGB(120, 230, 170))
		end
		return
	end
	if s.carrying then
		toast(player, "Put your egg in a nest first!", Color3.fromRGB(255, 200, 60))
		return
	end
	if data.coins < egg.price then
		toast(player, "Not enough coins! Battle to earn more", Color3.fromRGB(255, 90, 90))
		return
	end
	Analytics.tag(player, "Shop", "WinchEgg")
	data.coins -= egg.price
	s.pedestalEggs[i] = nil
	Analytics.event(player, "BuyEgg", egg.price, { stars = egg.stars, variant = egg.v or "Normal" })
	setCarrying(player, { sp = egg.sp, lvl = egg.lvl, stars = egg.stars, v = egg.v, perk = egg.perk, paid = egg.price })
	FarmService.syncPedestals(player)
	FarmService.tutorial(player, 2)
	FarmService.tutorial(player, 7)
	FarmService.tutorial(player, 13)
end

-- Put a ready egg/child straight into a free nest (boss drops, products). false if full.
function FarmService.giveEgg(player: Player, egg: any, hatchSeconds: number?): boolean
	local data = DataService.get(player)
	for i = 1, #Config.NEST_SLOTS do
		if FarmService.ownsNest(data, i) and not data.nests[tostring(i)] then
			data.nests[tostring(i)] = { kind = "egg", egg = egg, readyAt = os.time() + (hatchSeconds or 0) }
			FarmService.syncNest(player, i)
			DataService.changed(player)
			return true
		end
	end
	return false
end

-- Add a monster directly (Robux packs). Uses a free nest; false if the ship is full.
function FarmService.giveMonster(player: Player, sp: string, lvl: number, stars: number): boolean
	return FarmService.giveEgg(player, { sp = sp, lvl = lvl, stars = stars }, 0)
end

local function placeEgg(player: Player, i: number)
	local s = DataService.session(player)
	local data = DataService.get(player)
	if not s.carrying then
		toast(player, "Fish up an egg with the rod first!", Color3.fromRGB(255, 200, 60))
		return
	end
	if not FarmService.ownsNest(data, i) or data.nests[tostring(i)] then
		return
	end
	local c = s.carrying
	local egg = { sp = c.sp, lvl = c.lvl, stars = c.stars, v = c.v, perk = c.perk } -- (no "paid": that is only for Put Back)
	local secs = math.max(2, math.floor(Stats.hatchSeconds(egg.lvl, Stats.stars(egg.sp), FarmService.timerFloor(player)) * FarmService.hatchMult(player)))
	data.nests[tostring(i)] = { kind = "egg", egg = egg, readyAt = os.time() + secs }
	setCarrying(player, nil)
	FarmService.syncNest(player, i)
	FarmService.tutorial(player, 3)
	FarmService.tutorial(player, 8)
	FarmService.tutorial(player, 14)
end

local function newMonster(player: Player, item: any): string
	local data = DataService.get(player)
	local uid = tostring(data.nextUid)
	data.nextUid += 1
	data.monsters[uid] = { sp = item.sp, lvl = item.lvl, stars = item.stars, v = item.v, x6 = item.x6, perk = item.perk }
	-- the buyable nests appear the moment you own NEST_REVEAL_MONSTERS monsters
	task.defer(function()
		for n = Config.START_NESTS + 1, #Config.NEST_SLOTS do
			FarmService.syncNest(player, n)
		end
	end)
	local isNew = not data.index[item.sp]
	data.index[item.sp] = true
	if item.v and item.v ~= "Normal" then
		data.indexV[item.sp] = data.indexV[item.sp] or {}
		data.indexV[item.sp][item.v] = true
	end
	if isNew and data.tutorial >= Config.TUTORIAL_DONE then
		data.pearls += 10
	end
	-- Index milestones pay out once
	local found = 0
	for _ in data.index do
		found += 1
	end
	for _, r in Config.INDEX_REWARDS do
		local key = tostring(r.count)
		if found >= r.count and not data.indexRewards[key] then
			data.indexRewards[key] = true
			data.pearls += r.pearls
			toast(player, "Index " .. r.count .. " found! +" .. r.pearls .. " pearls", Color3.fromRGB(80, 190, 255))
		end
	end
	return uid
end

local function openEgg(player: Player, i: number)
	local data = DataService.get(player)
	local nest = data.nests[tostring(i)]
	if not nest or nest.kind ~= "egg" or nest.readyAt > os.time() then
		return
	end
	local uid = newMonster(player, nest.egg)
	data.totalHatches += 1
	Analytics.event(player, "Hatch", nest.egg.lvl, { species = nest.egg.sp, stars = nest.egg.stars })
	MissionService.record(player, "hatch", 1)
	data.nests[tostring(i)] = { kind = "mon", uid = uid }
	FarmService.syncNest(player, i)
	DataService.changed(player)
	Remotes.event("Reveal"):FireClient(player, "hatch", { sp = nest.egg.sp, lvl = nest.egg.lvl, stars = nest.egg.stars, v = nest.egg.v, perk = nest.egg.perk, nest = i })
	Remotes.event("Battle"):FireAllClients(player.UserId, "hatch", { nest = i, sp = nest.egg.sp })
	FarmService.tutorial(player, 4)
	FarmService.tutorial(player, 9)
	FarmService.tutorial(player, 15)
end

-- Studio testing: put a monster straight into a free nest
function FarmService.devMonster(player: Player, sp: string, lvl: number, stars: number)
	local data = DataService.get(player)
	for i = 1, #Config.NEST_SLOTS do
		if FarmService.ownsNest(data, i) and not data.nests[tostring(i)] then
			local uid = newMonster(player, { sp = sp, lvl = lvl, stars = stars })
			data.nests[tostring(i)] = { kind = "mon", uid = uid }
			FarmService.syncNest(player, i)
			return
		end
	end
end

-- Hatch Now (Robux, timed): while it runs every egg and fuse finishes instantly
function FarmService.hatchNowActive(player: Player): boolean
	local data = DataService.get(player)
	return data ~= nil and (data.hatchNowUntil or 0) > os.time()
end

-- "Hatch Now" on a nest: finish it if Hatch Now is running, otherwise offer the product
local function skipNest(player: Player, i: number)
	local data = DataService.get(player)
	local nest = data.nests[tostring(i)]
	if not nest or nest.kind == "mon" then
		return
	end
	if nest.readyAt - os.time() <= 0 then
		return
	end
	if FarmService.hatchNowActive(player) then
		nest.readyAt = os.time()
		FarmService.syncNest(player, i)
		DataService.changed(player)
		return
	end
	Analytics.store(player, "SkipTimer", 1) -- prompted
	game:GetService("MarketplaceService"):PromptProductPurchase(player, Config.PRODUCTS.SkipTimer.id)
end

-- Finish every timer (the Hatch Now product)
function FarmService.finishAllTimers(player: Player): boolean
	local data = DataService.get(player)
	local any = false
	for _, nest in data.nests do
		if nest.kind ~= "mon" and nest.readyAt > os.time() then
			nest.readyAt = os.time()
			any = true
		end
	end
	FarmService.syncAll(player)
	return any
end

local function buyNest(player: Player, i: number)
	local data = DataService.get(player)
	if FarmService.ownsNest(data, i) then
		return
	end
	local slot = Config.NEST_SLOTS[i]
	if not slot or (slot.floor >= 2 and data.floor < slot.floor) then
		return
	end
	local price = Stats.nestPrice(data.nestCount)
	if data.coins < price then
		toast(player, "Need " .. Format.abbrev(price) .. " coins for a new nest", Color3.fromRGB(255, 90, 90))
		return
	end
	Analytics.tag(player, "Shop", "Nest")
	data.coins -= price
	data.nestsOwned[tostring(i)] = true
	Analytics.event(player, "BuyNest", data.nestCount + 1)
	data.nestCount += 1
	FarmService.syncAll(player)
	DataService.changed(player)
	toast(player, "New nest unlocked!", Color3.fromRGB(90, 220, 120))
end

---------------------------------------------------------------------------
-- Fusing
---------------------------------------------------------------------------
local function nestOfUid(data: any, uid: string): number?
	for k, nest in data.nests do
		if nest.kind == "mon" and nest.uid == uid then
			return tonumber(k)
		end
	end
	return nil
end

-- Sell a hatched monster that is standing in one of your nests
function FarmService.sellMonster(player: Player, uid: any): (boolean, string?)
	local data = DataService.get(player)
	local s = DataService.session(player)
	if typeof(uid) ~= "string" then
		return false, "Pick a monster"
	end
	if s.inBattle then
		return false, "Wait for the battle to end"
	end
	if data.tutorial < Config.TUTORIAL_DONE then
		return false, "Finish the tutorial first"
	end
	local m = data.monsters[uid]
	local nest = if m then nestOfUid(data, uid) else nil
	if not m or not nest then
		return false, "That monster isn't in a nest"
	end
	local price = Stats.sellPrice(m.sp, m.lvl, m.v, data.bestDepth)
	data.monsters[uid] = nil
	data.nests[tostring(nest)] = nil
	for i = #data.team, 1, -1 do
		if data.team[i] == uid then
			table.remove(data.team, i)
		end
	end
	Analytics.tag(player, "Gameplay", "SellMonster")
	data.coins += price
	MissionService.record(player, "sell", 1)
	FarmService.syncNest(player, nest)
	DataService.changed(player)
	return true, "Sold " .. Config.MONSTERS[m.sp].name .. " Lv." .. m.lvl .. " for " .. Format.abbrev(price) .. " coins"
end

-- uidA + uidB decide the outcome (their species); `extra` are the additional same-level
-- monsters a Lv3+ fuse eats (Stats.fuseNeeded: Lv3 needs 3 in all, Lv4 needs 4, ...)
function FarmService.fuse(player: Player, uidA: any, uidB: any, extra: { any }?): (boolean, string?)
	local data = DataService.get(player)
	local s = DataService.session(player)
	if typeof(uidA) ~= "string" or typeof(uidB) ~= "string" or uidA == uidB then
		return false, "Pick two monsters"
	end
	if s.inBattle then
		return false, "Wait for the battle to end"
	end
	local a, b = data.monsters[uidA], data.monsters[uidB]
	if not a or not b then
		return false, "Pick two monsters"
	end
	if a.lvl ~= b.lvl then
		return false, "Both monsters must be the same level"
	end
	if a.lvl >= Config.MAX_LEVEL then
		return false, "Already max level"
	end
	if a.lvl + 1 > Stats.levelCap(data.bestDepth) then
		return false, "Beat the next boss to fuse higher! (max Lv." .. Stats.levelCap(data.bestDepth) .. ")"
	end
	local na, nb = nestOfUid(data, uidA), nestOfUid(data, uidB)
	if not na or not nb then
		return false, "Pick two monsters"
	end
	-- Lv3+ needs more of the same level: check the extras before anything is used up
	local need = Stats.fuseNeeded(a.lvl)
	local extras: { { uid: string, m: any, nest: number } } = {}
	local seen = { [uidA] = true, [uidB] = true }
	for _, u in extra or {} do
		if #extras >= need - 2 then
			break
		end
		local m = typeof(u) == "string" and data.monsters[u]
		local n = m and nestOfUid(data, u)
		if not m or not n or seen[u] or m.lvl ~= a.lvl then
			return false, "All the monsters must be Lv." .. a.lvl
		end
		seen[u] = true
		table.insert(extras, { uid = u, m = m, nest = n })
	end
	if #extras < need - 2 then
		return false, "Lv." .. a.lvl .. " needs " .. need .. " monsters to fuse (you picked " .. (2 + #extras) .. ")"
	end
	local luck = FarmService.luckMult(player)
	-- every monster going in counts (Stats.fuseOdds): the result never hits softer than any of them
	local fed = { a, b }
	for _, x in extras do
		table.insert(fed, x.m)
	end
	local species = {}
	for _, m in fed do
		table.insert(species, m.sp)
	end
	local outcomes = Stats.fuseOdds(species, a.lvl, luck)
	local r = rng:NextNumber()
	local sp = outcomes[#outcomes].sp
	for _, o in outcomes do
		r -= o.chance
		if r <= 0 then
			sp = o.sp
			break
		end
	end
	-- the best finish (Golden / Rainbow) and a sixth star carry over from ANY monster fed in
	local rank = { Normal = 1, Golden = 2, Rainbow = 3 }
	local v = a.v
	local x6 = false
	for _, m in fed do
		if (rank[m.v or "Normal"] or 1) > (rank[v or "Normal"] or 1) then
			v = m.v
		end
		x6 = x6 or m.x6 == true
	end
	-- a perk (Deep Rod) is kept: one of the parents' perks, picked at random if both have one
	local perk = if a.perk and b.perk then (if rng:NextNumber() < 0.5 then a.perk else b.perk) else a.perk or b.perk
	local child = { sp = sp, lvl = a.lvl + 1, stars = Stats.stars(sp), v = v, x6 = x6 or rng:NextNumber() < Config.SIXTH_STAR_CHANCE, perk = perk }
	data.monsters[uidA] = nil
	data.monsters[uidB] = nil
	-- the extra monsters are eaten too (their nests free up); a perk on one can carry over
	for _, x in extras do
		data.monsters[x.uid] = nil
		data.nests[tostring(x.nest)] = nil
		if not child.perk and x.m.perk then
			child.perk = x.m.perk
		end
	end
	-- nobody fused away stays on the battle team
	for i = #data.team, 1, -1 do
		if seen[data.team[i]] then
			table.remove(data.team, i)
		end
	end
	local secs = Config.FUSE_SECONDS -- instant: only the swoop animation, no speed boost needed
	data.nests[tostring(na)] = { kind = "fuse", child = child, readyAt = os.time() + secs, from = { a.sp, b.sp } }
	data.nests[tostring(nb)] = nil
	data.totalFuses += 1
	Analytics.event(player, "Fuse", child.lvl, { species = child.sp, stars = Stats.shownStars(child.sp, child.x6) })
	MissionService.record(player, "fuse", 1)
	FarmService.syncNest(player, na)
	FarmService.syncNest(player, nb)
	for _, x in extras do
		FarmService.syncNest(player, x.nest)
	end
	DataService.changed(player)
	Remotes.event("Battle"):FireAllClients(player.UserId, "fuse", { into = na, from = nb, a = a.sp, b = b.sp })
	FarmService.tutorial(player, 10)
	return true, nil
end

local function finishFuse(player: Player, i: number)
	local data = DataService.get(player)
	local nest = data.nests[tostring(i)]
	local uid = newMonster(player, nest.child)
	data.nests[tostring(i)] = { kind = "mon", uid = uid }
	FarmService.syncNest(player, i)
	DataService.changed(player)
	Remotes.event("Reveal"):FireClient(player, "fuse", { sp = nest.child.sp, lvl = nest.child.lvl, stars = nest.child.stars, x6 = nest.child.x6, perk = nest.child.perk, nest = i })
	FarmService.tutorial(player, 11)
end

-- The team that fights: every monster sitting in a nest
-- Seconds until at least one monster in your nests is rested (0 = someone can fight now)
function FarmService.restLeft(player: Player): number
	local data = DataService.get(player)
	local now = os.time()
	local best: number? = nil
	for _, nest in data.nests do
		if nest.kind == "mon" then
			local m = data.monsters[nest.uid]
			if m then
				local left = math.max(0, (m.restUntil or 0) - now)
				best = if best == nil then left else math.min(best, left)
			end
		end
	end
	return best or 0
end

-- forBattle: leave out monsters that are resting after a defeat
function FarmService.team(player: Player, forBattle: boolean?): { { uid: string, sp: string, lvl: number, stars: number, nest: number } }
	local data = DataService.get(player)
	local out = {}
	local now = os.time()
	for k, nest in data.nests do
		if nest.kind == "mon" then
			local m = data.monsters[nest.uid]
			if m and not (forBattle and (m.restUntil or 0) > now) then
				table.insert(out, { uid = nest.uid, sp = m.sp, lvl = m.lvl, stars = m.stars, v = m.v, x6 = m.x6, perk = m.perk, nest = tonumber(k) :: number })
			end
		end
	end
	-- chosen fighters first (if still around), then fill the free slots with the strongest
	local byUid = {}
	for _, m in out do
		byUid[m.uid] = m
	end
	local team = {}
	local used = {}
	for _, uid in data.team do
		if byUid[uid] and not used[uid] and #team < data.teamSlots then
			table.insert(team, byUid[uid])
			used[uid] = true
		end
	end
	-- no chosen fighter is awake (none picked, or they are all sleeping): send the strongest awake monsters
	if #team == 0 then
		table.sort(out, function(x, y)
			return Stats.power(x.sp, x.lvl, x.stars, x.v, x.x6) > Stats.power(y.sp, y.lvl, y.stars, y.v, y.x6)
		end)
		for _, m in out do
			if #team >= data.teamSlots then
				break
			end
			if not used[m.uid] then
				table.insert(team, m)
				used[m.uid] = true
			end
		end
	end
	table.sort(team, function(x, y)
		return x.nest < y.nest
	end)
	return team
end

-- Choose who fights: a list of uids (empty = auto best)
function FarmService.setTeam(player: Player, uids: any): (boolean, string?)
	local data = DataService.get(player)
	if typeof(uids) ~= "table" then
		return false, nil
	end
	local list = {}
	for _, uid in uids do
		if typeof(uid) == "string" and data.monsters[uid] and not table.find(list, uid) and #list < data.teamSlots then
			table.insert(list, uid)
		end
	end
	data.team = list
	DataService.changed(player)
	return true, nil
end

function FarmService.teamPower(player: Player): number
	local p = 0
	for _, m in FarmService.team(player) do
		p += Stats.power(m.sp, m.lvl, m.stars, m.v, m.x6)
	end
	return p
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
local function ownsShipOf(player: Player, inst: Instance): (WorldBuilder.Ship?, boolean)
	local model = inst:FindFirstAncestorWhichIsA("Model")
	while model and not model:GetAttribute("ShipIndex") do
		model = model.Parent and model.Parent:FindFirstAncestorWhichIsA("Model")
	end
	if not model then
		return nil, false
	end
	local ship = WorldBuilder.ships[model:GetAttribute("ShipIndex") :: number]
	return ship, owners[ship.index] == player
end

function FarmService.init()
	for _, ship in WorldBuilder.ships do
		clearShip(ship);
		(ship.winch:FindFirstChild("WinchPrompt") :: ProximityPrompt).Triggered:Connect(function(player)
			local _, mine = ownsShipOf(player, ship.winch)
			if mine then
				haul(player)
			end
		end)
		local deepPrompt = ship.deepWinch:FindFirstChild("DeepRodPrompt") :: ProximityPrompt
		deepPrompt.Triggered:Connect(function(player)
			local _, mine = ownsShipOf(player, ship.deepWinch)
			if mine then
				haul(player, "deep")
			end
		end)
		local abyssPrompt = ship.abyssWinch:FindFirstChild("AbyssRodPrompt") :: ProximityPrompt
		abyssPrompt.Triggered:Connect(function(player)
			local _, mine = ownsShipOf(player, ship.abyssWinch)
			if mine then
				haul(player, "abyss")
			end
		end)
		for i, ped in ship.pedestals do
			(ped:FindFirstChild("BuyPrompt") :: ProximityPrompt).Triggered:Connect(function(player)
				local _, mine = ownsShipOf(player, ped)
				if mine then
					buyEgg(player, i)
				end
			end)
		end
		for i, pad in ship.nests do
			(pad:FindFirstChild("NestPrompt") :: ProximityPrompt).Triggered:Connect(function(player)
				local _, mine = ownsShipOf(player, pad)
				if not mine then
					return
				end
				local state = pad:GetAttribute("State")
				if state == "empty" then
					placeEgg(player, i)
				elseif state == "locked" then
					buyNest(player, i)
				elseif state == "egg" or state == "fuse" then
					local ready = (pad:GetAttribute("ReadyAt") or 0) <= os.time()
					if ready and state == "fuse" then
						-- a ready fused egg opens by itself, but a tap opens it too (never stuck on "Ready!")
						local data = DataService.get(player)
						local nest = data and data.nests[tostring(i)]
						if nest and nest.kind == "fuse" then
							finishFuse(player, i)
						end
					elseif ready then
						openEgg(player, i)
					elseif state ~= "fuse" then
						skipNest(player, i) -- (never offered for a fuse: it finishes by itself in a moment)
					end
				end
			end)
		end
	end

	DataService.Loaded:Connect(function(player)
		assignShip(player)
		DataService.changed(player)
	end)
	DataService.Leaving:Connect(function(player)
		local s = DataService.session(player)
		-- a carried egg goes back into a free nest so it's never lost
		if s and s.carrying then
			FarmService.giveEgg(player, s.carrying, 0)
			s.carrying = nil
		end
		for i, p in owners do
			if p == player then
				owners[i] = nil
				clearShip(WorldBuilder.ships[i])
			end
		end
	end)

	-- timers: fused eggs open by themselves, ready eggs flip their prompt to "Open"
	task.spawn(function()
		while true do
			task.wait(0.5)
			local now = os.time()
			for _, player in Players:GetPlayers() do
				local data = DataService.get(player)
				if data and FarmService.shipOf(player) then
					for k, nest in data.nests do
						-- one bad nest must never stop this loop: it runs every timer for every player
						local ok, err = pcall(function()
							if nest.kind ~= "mon" and nest.readyAt <= now and not nest.flagged then
								if nest.kind == "fuse" then
									finishFuse(player, tonumber(k) :: number)
								else
									nest.flagged = true
									FarmService.syncNest(player, tonumber(k) :: number)
								end
							elseif nest.kind ~= "mon" and nest.readyAt > now and FarmService.hatchNowActive(player) then
								-- Hatch Now is running: every timer (old or new) finishes right away
								nest.readyAt = now
								FarmService.syncNest(player, tonumber(k) :: number)
								DataService.changed(player)
							end
						end)
						if not ok then
							warn("[Farm] nest timer failed", player.Name, k, err)
						end
					end
				end
			end
		end
	end)
end

return FarmService
