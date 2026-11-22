--!strict
-- Server-authoritative auto battles. FIGHT sends the player's whole team out to the buoy
-- arena; enemies rise one depth at a time (mini-boss at 8, boss at 15 with a timer).
-- Every beat is broadcast with the Battle remote (ownerUserId, kind, payload) so all
-- clients can draw the fight. Coins are paid per kill, so a loss still pays.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Stats = require(Shared.Stats)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local FarmService = require(script.Parent.FarmService)
local WorldBuilder = require(script.Parent.WorldBuilder)
local Analytics = require(script.Parent.Analytics)
local MissionService = require(script.Parent.MissionService)

local BattleService = {}

type Fighter = { power: string?, v: string?, uid: string, sp: string, lvl: number, stars: number, elements: { string }, hp: number, maxHp: number, atk: number, interval: number, cd: number, energy: number, nest: number }
type Run = {
	player: Player,
	team: { Fighter },
	depth: number,
	startDepth: number,
	enemy: any?,
	enemyCd: number,
	waveTimer: number,
	bossLeft: number?,
	coins: number,
	pearls: number,
	kills: number,
	alive: boolean,
	retreat: boolean,
	speed: number,
}

local runs: { [Player]: Run } = {}
local ended: { [Player]: { depth: number, until_: number } } = {} -- revive window
local rng = Random.new()

local function broadcast(player: Player, kind: string, payload: any)
	Remotes.event("Battle"):FireAllClients(player.UserId, kind, payload)
end

local function toast(player: Player, text: string, color: Color3?)
	Remotes.event("Toast"):FireClient(player, text, color)
end

local function coinMult(player: Player): number
	local s = DataService.session(player)
	local data = DataService.get(player)
	local m = 1
	if s.passes.DoubleCoins then
		m *= 2
	end
	if s.passes.VIP then
		m += Config.VIP_COIN_BONUS
	end
	if data.floor >= 2 then
		m += Config.LIGHTHOUSE_COIN_BONUS
	end
	if data.floor >= 3 then
		m += Config.FLOOR3_COIN_BONUS
	end
	m += (data.shipTier or 0) * Config.SHIPWRIGHT.coinPerTier
	m += (tonumber(player:GetAttribute("Friends")) or 0) * Config.FRIEND_BOOST
	m *= FarmService.spellMult(player, "coins")
	return m
end

local function setInBattle(player: Player, on: boolean, fighters: { any }?)
	local s = DataService.session(player)
	if s then
		s.inBattle = on
		s.fighting = {}
		if on and fighters then
			for _, f in fighters do
				s.fighting[f.uid] = true
			end
		end
	end
	player:SetAttribute("InBattle", on or nil)
	FarmService.syncAll(player)
	DataService.changed(player)
end

local function teamPayload(run: Run)
	local list = {}
	for i, f in run.team do
		list[i] = { sp = f.sp, lvl = f.lvl, stars = f.stars, v = f.v, hp = f.hp, maxHp = f.maxHp, nest = f.nest }
	end
	return list
end

local function spawnEnemy(run: Run)
	local e = Stats.enemy(run.depth, rng:NextNumber())
	local def = Config.ENEMIES[e.id]
	run.enemy = { id = e.id, hp = e.hp, maxHp = e.hp, atk = e.atk, interval = e.interval, kind = e.kind, element = def.element, scale = e.scale }
	run.enemyCd = e.interval * 0.8
	local nest = ((DataService.get(run.player).fittings or {}).CrowsNest or 0) * Config.FITTINGS.CrowsNest.bossTime
	run.bossLeft = if e.kind == "boss" or e.kind == "final" then Config.BOSS_TIME + nest else nil
	broadcast(run.player, "wave", {
		depth = run.depth,
		id = e.id,
		hp = e.hp,
		maxHp = e.hp,
		kind = e.kind,
		scale = e.scale,
		stage = Stats.stageInfo(run.depth).name,
		bossTime = run.bossLeft,
	})
end

local function aliveFighters(run: Run): { number }
	local out = {}
	for i, f in run.team do
		if f.hp > 0 then
			table.insert(out, i)
		end
	end
	return out
end

local function giveBossEgg(player: Player, depth: number)
	local data = DataService.get(player)
	local stage = Stats.stageOf(depth)
	local els = { "Tide", "Coral", "Storm", "Abyss" }
	local el = els[rng:NextInteger(1, #els)]
	local egg = { sp = Config.STARTER_OF[el], lvl = stage + 2, stars = if rng:NextNumber() < 0.25 then 2 else 1 }
	local secs = math.floor(Stats.hatchSeconds(egg.lvl, Stats.stars(egg.sp)) * FarmService.hatchMult(player))
	if FarmService.giveEgg(player, egg, secs) then
		toast(player, "The boss dropped a Lv" .. egg.lvl .. " " .. el .. " Egg! It's in a nest", Config.ELEMENTS[el].color)
	else
		local coins = Stats.eggPrice(egg.sp, egg.lvl, egg.stars, 0.5)
		data.coins += coins
		toast(player, "Nests full! The boss egg was sold for " .. Format.abbrev(coins) .. " coins", Color3.fromRGB(255, 200, 60))
	end
end

-- Spell cards drop from kills: pick a rarity from the drop table, then a spell of it
function BattleService.maybeDropSpell(player: Player, kind: string)
	local drop = Config.SPELL_DROP[kind]
	if not drop or rng:NextNumber() > drop.chance then
		return
	end
	local total = 0
	for _, w in drop.weights do
		total += w
	end
	local r = rng:NextNumber() * total
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
		return
	end
	local sp = pool[rng:NextInteger(1, #pool)]
	local data = DataService.get(player)
	data.spells[sp.id] = (tonumber(data.spells[sp.id]) or 0) + 1
	data.spellsFound[sp.id] = true
	Analytics.event(player, "SpellDrop", sp.rarity, { spell = sp.id })
	Remotes.event("Reveal"):FireClient(player, "spell", { id = sp.id })
	require(script.Parent.ExtrasService).checkSpellSets(player) -- (lazy: ExtrasService needs this module)
end

local function killEnemy(run: Run)
	local player = run.player
	local data = DataService.get(player)
	local e = run.enemy :: any
	local greedy = 0
	for _, f in run.team do
		if f.power == "Greedy" and f.hp > 0 then
			greedy += 0.25
		end
	end
	local coins = math.floor(Stats.killCoins(run.depth, e.kind) * (coinMult(player) + greedy))
	-- battles pay coins (and the boss egg) only; pearls, spells and shells come from the
	-- Gift Chest, daily chest, Index and shops so a fight stays easy to read
	local pearls = 0
	data.coins += coins
	data.pearls += pearls
	run.coins += coins
	run.pearls += pearls
	run.kills += 1
	MissionService.record(player, "kills", 1)
	if e.kind == "boss" or e.kind == "final" then
		MissionService.record(player, "boss", 1)
	end
	if run.depth > data.bestDepth then
		data.bestDepth = run.depth
		if run.depth % 5 == 0 then
			Analytics.event(player, "BestDepth", run.depth)
		end
		FarmService.updateSign(player)
	end
	broadcast(player, "kill", { coins = coins, pearls = pearls, depth = run.depth })
	if e.kind == "boss" or e.kind == "final" then
		Analytics.stageCleared(player, Stats.stageOf(run.depth))
	end
	if e.kind == "boss" then
		giveBossEgg(player, run.depth)
	end
	if run.depth >= Config.STAGE_LENGTH then
		FarmService.tutorial(player, 16)
	end
	DataService.changed(player)
	run.enemy = nil
	if run.depth >= Config.FINAL_DEPTH then
		toast(player, "You beat Maw and rescued your monster! Keep diving for glory", Color3.fromRGB(255, 220, 80))
	end
	run.depth += 1
	run.waveTimer = Config.NEXT_WAVE_DELAY
end

-- one simulation step of dt seconds
local function step(run: Run, dt: number)
	if run.enemy == nil then
		run.waveTimer -= dt
		if run.waveTimer <= 0 then
			spawnEnemy(run)
		end
		return
	end
	local e = run.enemy :: any
	-- monsters attack
	for i, f in run.team do
		if f.hp > 0 and e.hp > 0 then
			f.cd -= dt
			if f.cd <= 0 then
				f.cd += f.interval
				local mult = Stats.elementMult(f.elements, e.element)
				local ability = false
				f.energy += 1
				if f.energy >= (if f.power == "Kraken" then 2 else Config.ABILITY_HITS) then
					f.energy = 0
					ability = true
				end
				local move = if ability then f.elements[1] else nil
				-- one simple energy hit for everyone; the element only picks its colour on screen
				local abilityMult = Config.ABILITY_MULT
				local dmg = f.atk * mult * (if ability then abilityMult else 1) * rng:NextNumber(0.9, 1.1)
				dmg = math.max(1, math.floor(dmg))
				e.hp = math.max(0, e.hp - dmg)
				local heals = nil
				broadcast(run.player, "hit", { from = i, dmg = dmg, super = mult > 1, weak = mult < 1, ability = ability, move = move, heals = heals, hp = e.hp })
			end
		end
	end
	if e.hp <= 0 then
		killEnemy(run)
		return
	end
	-- the enemy attacks a random living monster
	run.enemyCd -= dt
	if run.enemyCd <= 0 then
		run.enemyCd += e.interval
		local alive = aliveFighters(run)
		if #alive > 0 then
			local i = alive[rng:NextInteger(1, #alive)]
			local f = run.team[i]
			local mult = Stats.elementMult({ e.element }, f.elements[1])
			local dmg = math.max(1, math.floor(e.atk * mult * rng:NextNumber(0.9, 1.1)))
			f.hp = math.max(0, f.hp - dmg)
			broadcast(run.player, "enemyHit", { to = i, dmg = dmg, hp = f.hp, super = mult > 1 })
			if f.hp <= 0 then
				broadcast(run.player, "faint", { who = i })
			end
		end
	end
	if run.bossLeft then
		run.bossLeft -= dt
		if run.bossLeft <= 0 then
			(run :: any).timeUp = true
			toast(run.player, "Time's up! The boss swam away", Color3.fromRGB(255, 90, 90))
			for _, f in run.team do
				f.hp = 0
			end
		end
	end
end

local function finish(run: Run)
	local player = run.player
	runs[player] = nil
	local data = DataService.get(player)
	if not data then
		return
	end
	setInBattle(player, false)
	-- every monster that fainted has to rest before it can fight again
	local rested = false
	for _, f in run.team do
		if f.hp <= 0 then
			local m = data.monsters[f.uid]
			if m then
				m.restUntil = os.time() + Config.REST_SECONDS
				rested = true
			end
		end
	end
	Analytics.diveEnd(player, run.depth, run.retreat)
	if not run.retreat then
		ended[player] = { depth = run.depth, until_ = os.clock() + Config.REVIVE_WINDOW }
	end
	broadcast(player, "end", {
		depth = run.depth,
		coins = run.coins,
		pearls = run.pearls,
		kills = run.kills,
		canRevive = not run.retreat and not FarmService.inTutorial(player),
		retreat = run.retreat,
		timeUp = (run :: any).timeUp == true,
		rest = if rested then Config.REST_SECONDS else nil,
	})
	FarmService.tutorial(player, 5)
	DataService.changed(player)
end

local function startRun(player: Player, depth: number, keep: Run?): (boolean, string?)
	if runs[player] then
		return false, "Already battling"
	end
	local team = FarmService.team(player, true)
	if #team == 0 then
		local rest = FarmService.restLeft(player)
		if rest > 0 then
			return false, "Your monsters are resting! Ready in " .. rest .. "s"
		end
		return false, "Hatch a monster first!"
	end
	local fighters: { Fighter } = {}
	local data0 = DataService.get(player)
	for _, m in team do
		local st = Stats.monster(m.sp, m.lvl, m.stars, m.v, m.x6)
		local power = data0.monsters[m.uid] and data0.monsters[m.uid].power
		if power == "Fierce" then
			st.atk = math.floor(st.atk * 1.3)
		elseif power == "Tough" then
			st.hp = math.floor(st.hp * 1.4)
		elseif power == "Swift" then
			st.interval /= 1.3
		elseif power == "Titan" then
			st.atk = math.floor(st.atk * 1.6)
			st.hp = math.floor(st.hp * 1.6)
		end
		local fit = DataService.get(player).fittings or {}
		st.atk = math.max(1, math.floor(st.atk * FarmService.spellMult(player, "dmg") * (1 + (fit.Cannons or 0) * Config.FITTINGS.Cannons.dmg)))
		st.hp = math.max(1, math.floor(st.hp * FarmService.spellMult(player, "hp") * (1 + (fit.Hull or 0) * Config.FITTINGS.Hull.hp)))
		table.insert(fighters, {
			power = power,
			v = m.v,
			uid = m.uid,
			sp = m.sp,
			lvl = m.lvl,
			stars = m.stars,
			elements = Config.MONSTERS[m.sp].elements,
			hp = st.hp,
			maxHp = st.hp,
			atk = st.atk,
			interval = st.interval,
			cd = st.interval * rng:NextNumber(0.3, 1),
			energy = 0,
			nest = m.nest,
		})
	end
	local data = DataService.get(player)
	local run: Run = {
		player = player,
		team = fighters,
		depth = depth,
		startDepth = depth,
		enemy = nil,
		enemyCd = 0,
		waveTimer = 1.6,
		bossLeft = nil,
		coins = if keep then keep.coins else 0,
		pearls = if keep then keep.pearls else 0,
		kills = if keep then keep.kills else 0,
		alive = true,
		retreat = false,
		speed = if DataService.session(player).passes.FastBattle then (data.battleSpeed or 1) else 1,
	}
	runs[player] = run
	ended[player] = nil
	setInBattle(player, true, fighters)
	Analytics.diveStart(player, depth)
	broadcast(player, "start", { team = teamPayload(run), depth = depth, power = FarmService.teamPower(player) })
	-- loaded deck cannons fire as the battle starts and are empty again (cosmetic, see WorldBuilder.fireCannons)
	local ownShip = FarmService.shipOf(player)
	if ownShip then
		WorldBuilder.fireCannons(ownShip)
	end
	task.spawn(function()
		local last = os.clock()
		while runs[player] == run and player.Parent do
			task.wait(Config.TICK)
			local now = os.clock()
			local dt = math.min(0.5, now - last) * run.speed
			last = now
			if run.retreat then
				break
			end
			step(run, dt)
			if #aliveFighters(run) == 0 then
				break
			end
		end
		if runs[player] == run then
			finish(run)
		end
	end)
	return true, nil
end

function BattleService.startDepthFor(player: Player): number
	local data = DataService.get(player)
	if FarmService.inTutorial(player) then
		return 1
	end
	-- restart from the last stage checkpoint you've cleared
	return (data.bestDepth // Config.STAGE_LENGTH) * Config.STAGE_LENGTH + 1
end

function BattleService.fight(player: Player): (boolean, string?)
	local data = DataService.get(player)
	if data.tutorial < 5 then
		return false, "Hatch your first monster first!"
	end
	local s = DataService.session(player)
	if s.carrying then
		return false, "Put your egg in a nest first!"
	end
	return startRun(player, BattleService.startDepthFor(player))
end

function BattleService.retreat(player: Player)
	local run = runs[player]
	if run then
		run.retreat = true
	end
end

function BattleService.revive(player: Player): boolean
	local e = ended[player]
	if not e or runs[player] then
		return false
	end
	ended[player] = nil
	-- a Revive brings everyone back: no resting
	local data = DataService.get(player)
	for _, m in data.monsters do
		m.restUntil = nil
	end
	local ok = startRun(player, e.depth)
	if ok then
		toast(player, "Revived! Keep diving!", Color3.fromRGB(90, 220, 120))
	end
	return ok
end

function BattleService.canRevive(player: Player): boolean
	local e = ended[player]
	return e ~= nil and os.clock() < e.until_ and runs[player] == nil
end

function BattleService.setSpeed(player: Player, speed: any): boolean
	local s = DataService.session(player)
	local data = DataService.get(player)
	if speed ~= 1 and speed ~= 2 then
		return false
	end
	if speed == 2 and not s.passes.FastBattle then
		return false
	end
	data.battleSpeed = speed
	local run = runs[player]
	if run then
		run.speed = speed
	end
	DataService.changed(player)
	return true
end

function BattleService.isFighting(player: Player): boolean
	return runs[player] ~= nil
end

-- coins earned while away: your team kept battling at your best depth
local function offlineEarnings(player: Player)
	local data = DataService.get(player)
	if not data or data.lastSeen == 0 or data.tutorial < Config.TUTORIAL_DONE then
		return
	end
	local away = math.min(os.time() - data.lastSeen, Config.OFFLINE_MAX_HOURS * 3600)
	if away < 120 or #FarmService.team(player) == 0 then
		return
	end
	local coins = math.floor(Stats.coinsPerMinute(data.bestDepth) * (away / 60) * Config.OFFLINE_RATE * coinMult(player))
	if coins <= 0 then
		return
	end
	data.coins += coins
	DataService.changed(player)
	task.delay(4, function()
		if player.Parent then
			Remotes.event("Offline"):FireClient(player, away, coins)
		end
	end)
end

function BattleService.init()
	DataService.Loaded:Connect(offlineEarnings)
	Players.PlayerRemoving:Connect(function(player)
		runs[player] = nil
		ended[player] = nil
	end)
end

return BattleService
