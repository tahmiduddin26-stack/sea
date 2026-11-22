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
	if not data or data.tutorial ~= from then
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
	prompt:SetAttribute("Live", true)
	prompt.HoldDuration = 0
	pad:SetAttribute("Price", nil)
	-- new players see only their free nests until the tutorial is done
	local hidden = i > Config.START_NESTS and data.tutorial < Config.TUTORIAL_DONE
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
		prompt.ObjectText = if nest.kind == "egg" then "Egg" else "Fused Egg"
		prompt:SetAttribute("Live", nest.kind == "egg") -- fused eggs open by themselves
	else
		prompt.ActionText = "Hatch Now"
		prompt.ObjectText = Stats.skipPearls(left) .. " Pearls"
		prompt.HoldDuration = 0.4
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
		ped:SetAttribute("Active", i <= count)
		if egg then
			ped:SetAttribute("Sp", egg.sp)
			ped:SetAttribute("Lvl", egg.lvl)
			ped:SetAttribute("Stars", egg.stars)
			ped:SetAttribute("Variant", egg.v)
			ped:SetAttribute("Price", egg.price)
			prompt:SetAttribute("Live", true)
			prompt.ActionText = "Take"
			prompt.ObjectText = if egg.price <= 0 then "Egg" else Format.abbrev(egg.price) .. " Coins"
		else
			ped:SetAttribute("Sp", nil)
			ped:SetAttribute("Price", nil)
			prompt:SetAttribute("Live", false)
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
		for _, a in { "Owner", "State", "Uid", "Sp", "Lvl", "Stars", "ReadyAt", "InBattle", "Price", "Variant" } do
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

function FarmService.rollVariant(player: Player): string
	local luck = FarmService.eggLuck(player)
	local weights = {}
	local ids = {}
	for i, v in Config.VARIANTS do
		table.insert(ids, v.id)
		table.insert(weights, if i == 1 then v.weight else v.weight * luck * FarmService.spellMult(player, "mutation"))
	end
	return pickWeighted(ids, weights)
end

-- forceEl: the zone's element; hybrid: the Abyss zone (a random 2-star hybrid or better)
function FarmService.rollEgg(player: Player, forceEl: string?, hybrid: boolean?)
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
	local luck = FarmService.eggLuck(player)
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

local function haul(player: Player)
	local s = DataService.session(player)
	local data = DataService.get(player)
	if not s or not data then
		return
	end
	if os.clock() - s.lastRoll < Config.ROLL_COOLDOWN then
		return
	end
	if s.fishing then
		return
	end
	s.lastRoll = os.clock()
	-- roll the zone the hook stops in (Egg Luck makes the deep zones likelier)
	local scripted = Config.TUTORIAL_EGGS[data.tutorial]
	local zone = 1
	if scripted then
		local el = Config.MONSTERS[scripted.sp].elements[1]
		for k, z in Config.FISH_ZONES do
			if z.element == el then
				zone = k
			end
		end
	else
		local luck = FarmService.eggLuck(player)
		local ids, ws = {}, {}
		for k, z in Config.FISH_ZONES do
			table.insert(ids, k)
			table.insert(ws, z.weight * luck ^ ((k - 1) / 2))
		end
		zone = pickWeighted(ids, ws)
	end
	-- Fast Reel: every pedestal level (upgrade, pass or spell) makes the whole cast 8% quicker
	local reel = 1 - 0.08 * (FarmService.pedestalCount(player) - 1)
	local time = (Config.FISH_BASE + zone * Config.FISH_PER_ZONE) * math.max(0.6, reel)
	-- the rod casts and dives: the pedestals empty now and the catch lands on them when the
	-- line comes up (every client plays the same dive from "haul")
	s.fishing = true
	MissionService.record(player, "fish", 1)
	s.pedestalEggs = {}
	FarmService.syncPedestals(player)
	-- one egg per cast: the hook pulls a single egg out of a rock nest on the sea floor
	local count = 1
	Remotes.event("Battle"):FireAllClients(player.UserId, "haul", { count = count, zone = zone, time = time })
	-- the captain steps up to the rod and holds it for the whole cast (clients pose the arms)
	do
		local ship = FarmService.shipOf(player)
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local rod = ship and ship.model:FindFirstChild("Rod")
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
		scripted = Config.TUTORIAL_EGGS[data.tutorial]
		s.pedestalEggs = {}
		if scripted then
			s.pedestalEggs[1] = table.clone(scripted)
		else
			local el = Config.FISH_ZONES[zone].element
			for i = 1, count do
				s.pedestalEggs[i] = FarmService.rollEgg(player, el, el == nil)
			end
		end
		-- most fished eggs are FREE (nests, hatch timers and fusing are the limit, so a broke
		-- player can always keep playing); some are Treasure Eggs: a level higher, for coins.
		-- Never every egg on one cast, so there is always a free one to take.
		local freeLeft = false
		for i, e in s.pedestalEggs do
			if not scripted and rng:NextNumber() < Config.EGG_PRICE_CHANCE and (i < #s.pedestalEggs or freeLeft) then
				e.lvl += 1
				e.price = math.floor(Stats.eggPrice(e.sp, e.lvl, e.stars, rng:NextNumber()) * (if e.v == "Rainbow" then 6 elseif e.v == "Golden" then 2.5 else 1))
			else
				e.price = 0
				freeLeft = true
			end
		end
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
	DataService.changed(player)
end

local function buyEgg(player: Player, i: number)
	local s = DataService.session(player)
	local data = DataService.get(player)
	local egg = s and s.pedestalEggs[i]
	if not egg then
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
	setCarrying(player, { sp = egg.sp, lvl = egg.lvl, stars = egg.stars, v = egg.v })
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
	local egg = s.carrying
	local secs = math.max(2, math.floor(Stats.hatchSeconds(egg.lvl, Stats.stars(egg.sp)) * FarmService.hatchMult(player)))
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
	data.monsters[uid] = { sp = item.sp, lvl = item.lvl, stars = item.stars, v = item.v, x6 = item.x6 }
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
	Remotes.event("Reveal"):FireClient(player, "hatch", { sp = nest.egg.sp, lvl = nest.egg.lvl, stars = nest.egg.stars, nest = i })
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

-- Pay pearls to finish a timer now
local function skipNest(player: Player, i: number)
	local data = DataService.get(player)
	local nest = data.nests[tostring(i)]
	if not nest or nest.kind == "mon" then
		return
	end
	local left = nest.readyAt - os.time()
	if left <= 0 then
		return
	end
	local cost = Stats.skipPearls(left)
	if data.pearls < cost then
		toast(player, "Not enough pearls!", Color3.fromRGB(255, 90, 90))
		return
	end
	Analytics.tag(player, "Shop", "SkipTimer")
	data.pearls -= cost
	nest.readyAt = os.time()
	FarmService.syncNest(player, i)
	DataService.changed(player)
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
	local price = Stats.sellPrice(m.sp, m.lvl, m.v)
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

function FarmService.fuse(player: Player, uidA: any, uidB: any): (boolean, string?)
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
	local luck = FarmService.luckMult(player)
	local outcomes = Stats.fuseOutcomes(a.sp, b.sp, a.lvl, luck)
	local r = rng:NextNumber()
	local sp = outcomes[#outcomes].sp
	for _, o in outcomes do
		r -= o.chance
		if r <= 0 then
			sp = o.sp
			break
		end
	end
	local rank = { Normal = 1, Golden = 2, Rainbow = 3 }
	local v = if (rank[a.v or "Normal"] or 1) >= (rank[b.v or "Normal"] or 1) then a.v else b.v
	local child = { sp = sp, lvl = a.lvl + 1, stars = Stats.stars(sp), v = v, x6 = rng:NextNumber() < Config.SIXTH_STAR_CHANCE }
	data.monsters[uidA] = nil
	data.monsters[uidB] = nil
	local secs = math.max(2, math.floor(Stats.fuseSeconds(a.lvl, math.max(Stats.stars(a.sp), Stats.stars(b.sp))) * FarmService.hatchMult(player)))
	data.nests[tostring(na)] = { kind = "fuse", child = child, readyAt = os.time() + secs, from = { a.sp, b.sp } }
	data.nests[tostring(nb)] = nil
	data.totalFuses += 1
	Analytics.event(player, "Fuse", child.lvl, { species = child.sp, stars = Stats.shownStars(child.sp, child.x6) })
	MissionService.record(player, "fuse", 1)
	FarmService.syncNest(player, na)
	FarmService.syncNest(player, nb)
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
	Remotes.event("Reveal"):FireClient(player, "fuse", { sp = nest.child.sp, lvl = nest.child.lvl, stars = nest.child.stars, x6 = nest.child.x6, nest = i })
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
				table.insert(out, { uid = nest.uid, sp = m.sp, lvl = m.lvl, stars = m.stars, v = m.v, x6 = m.x6, nest = tonumber(k) :: number })
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
	if #data.team == 0 then
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
					if ready then
						openEgg(player, i)
					else
						skipNest(player, i)
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
						if nest.kind ~= "mon" and nest.readyAt <= now and not nest.flagged then
							if nest.kind == "fuse" then
								finishFuse(player, tonumber(k) :: number)
							else
								nest.flagged = true
								FarmService.syncNest(player, tonumber(k) :: number)
							end
						elseif nest.kind ~= "mon" and nest.readyAt > now then
							-- keep the pearl price on "Hatch Now" fresh
							local pad = FarmService.shipOf(player).nests[tonumber(k) :: number]
							local prompt = pad and pad:FindFirstChild("NestPrompt") :: ProximityPrompt?
							if prompt then
								prompt.ObjectText = Stats.skipPearls(nest.readyAt - now) .. " Pearls"
							end
						end
					end
				end
			end
		end
	end)
end

return FarmService
