--!strict
-- Derived numbers used by both sides: monster stats, enemy stats per depth, prices,
-- timers and fuse odds. Pure functions of Config + the values passed in.

local Config = require(script.Parent.Config)

local Stats = {}

export type MonsterStats = { hp: number, atk: number, interval: number }

-- Rarity of a species (its star count). The per-monster `stars` value is legacy and
-- ignored: stars always come from the species, like the reference game.
function Stats.stars(sp: string): number
	local def = Config.MONSTERS[sp]
	return if def then def.stars else 1
end

function Stats.variant(id: string?): any
	for _, v in Config.VARIANTS do
		if v.id == id then
			return v
		end
	end
	return Config.VARIANTS[1]
end

-- Stars to show on a monster: its species rarity, or 6 for the very rare sixth-star fuse
function Stats.shownStars(sp: string, sixth: boolean?): number
	return if sixth then 6 else Stats.stars(sp)
end

function Stats.monster(sp: string, lvl: number, _stars: number?, variant: string?, sixth: boolean?): MonsterStats
	local def = Config.MONSTERS[sp]
	local role = Config.ROLES[def and def.role or "balanced"]
	local grow = Config.LEVEL_STAT_GROWTH ^ (lvl - 1)
	local star = Config.STAR_MULT[math.clamp(Stats.stars(sp), 1, 5)] * Stats.variant(variant).mult * (if sixth then Config.SIXTH_STAR_MULT else 1)
	return {
		hp = math.floor(Config.BASE_HP * role.hp * grow * star),
		atk = math.max(1, math.floor(Config.BASE_ATK * role.atk * grow * star)),
		interval = Config.BASE_ATTACK_INTERVAL / role.rate,
	}
end

-- One number for "how strong is this team" (shown as Team Power)
function Stats.power(sp: string, lvl: number, stars: number?, variant: string?, sixth: boolean?): number
	local s = Stats.monster(sp, lvl, stars, variant, sixth)
	return math.floor(s.hp * 0.2 + (s.atk / s.interval) * 8)
end

-- Damage per second of a monster on its own (what the damage sticker and the hatch card show)
function Stats.dps(sp: string, lvl: number, stars: number?, variant: string?, sixth: boolean?): number
	local s = Stats.monster(sp, lvl, stars, variant, sixth)
	return s.atk / s.interval
end

function Stats.stageOf(depth: number): number
	return (depth - 1) // Config.STAGE_LENGTH + 1
end

function Stats.stageInfo(depth: number)
	local stage = Stats.stageOf(depth)
	return Config.STAGES[(stage - 1) % #Config.STAGES + 1]
end

function Stats.waveKind(depth: number): string
	local inStage = (depth - 1) % Config.STAGE_LENGTH + 1
	if depth == Config.FINAL_DEPTH then
		return "final"
	elseif inStage == Config.STAGE_LENGTH then
		return "boss"
	elseif inStage == Config.MINIBOSS_AT then
		return "miniboss"
	end
	return "mob"
end

-- Cumulative enemy growth up to `stage`. Each stage change multiplies by a step that rises
-- from ENEMY_HP_STEP_FIRST to ENEMY_HP_STEP_LAST (x ratio), so early stages stay easy and the
-- climb gets steadily longer. Stage 1 = 1.
function Stats.stageScale(stage: number, ratio: number): number
	local scale = 1
	local changes = 15 -- stage changes from stage 2 to the last stage (16)
	for k = 1, stage - 1 do
		local t = math.clamp((k - 1) / (changes - 1), 0, 1)
		local step = Config.ENEMY_HP_STEP_FIRST + (Config.ENEMY_HP_STEP_LAST - Config.ENEMY_HP_STEP_FIRST) * t
		scale *= step * ratio
	end
	return scale
end

export type EnemyStats ={ id: string, hp: number, atk: number, interval: number, kind: string, scale: number }

-- Which enemy appears at a depth, and its stats. `pick` (0..1) chooses the mob.
function Stats.enemy(depth: number, pick: number): EnemyStats
	local stage = Stats.stageOf(depth)
	local info = Stats.stageInfo(depth)
	local kind = Stats.waveKind(depth)
	local inStage = (depth - 1) % Config.STAGE_LENGTH
	local hp = Config.ENEMY_BASE_HP * Stats.stageScale(stage, 1) * (1 + Config.ENEMY_HP_PER_DEPTH * inStage)
	local atk = Config.ENEMY_BASE_ATK * Stats.stageScale(stage, Config.ENEMY_ATK_STEP_RATIO) * (1 + 0.05 * inStage)
	local id: string
	local scale = 1
	if kind == "final" then
		id = Config.FINAL_BOSS
		hp *= Config.BOSS_HP_MULT
		atk *= Config.BOSS_ATK_MULT * Config.FINAL_ATK_EXTRA
	elseif kind == "boss" then
		id = info.boss
		hp *= Config.BOSS_HP_MULT
		atk *= Config.BOSS_ATK_MULT
	elseif kind == "miniboss" then
		id = info.miniboss
		hp *= Config.MINIBOSS_HP_MULT
		atk *= Config.MINIBOSS_ATK_MULT
		scale = 1.7
	else
		id = info.mobs[math.clamp(math.floor(pick * #info.mobs) + 1, 1, #info.mobs)]
	end
	local def = Config.ENEMIES[id]
	return {
		id = id,
		hp = math.max(1, math.floor(hp)),
		atk = math.max(1, math.floor(atk)),
		interval = Config.ENEMY_ATTACK_INTERVAL,
		kind = kind,
		scale = (def and def.scale or 1) * scale,
	}
end

function Stats.killCoins(depth: number, kind: string): number
	local stage = Stats.stageOf(depth)
	local c = (Config.COINS_BASE + Config.COINS_PER_DEPTH * depth) * (Config.COINS_STAGE_MULT ^ (stage - 1))
	if kind == "boss" or kind == "final" then
		c += Config.BOSS_COIN_BONUS * (Config.COINS_STAGE_MULT ^ (stage - 1)) * stage
	elseif kind == "miniboss" then
		c *= 3
	end
	return math.floor(c)
end

-- Element multiplier of attacker element(s) vs defender element
function Stats.elementMult(attacker: { string }, defender: string): number
	local best = 1
	for _, e in attacker do
		local info = Config.ELEMENTS[e]
		if info and info.beats == defender then
			best = math.max(best, Config.SUPER_MULT)
		end
	end
	if best == 1 then
		local d = Config.ELEMENTS[defender]
		for _, e in attacker do
			if d and d.beats == e and #attacker == 1 then
				return Config.WEAK_MULT
			end
		end
	end
	return best
end

function Stats.eggPrice(sp: string, lvl: number, _stars: number?, jitter: number): number
	local def = Config.MONSTERS[sp]
	local el = def and def.elements[1] or "Tide"
	local p = Config.EGG_PRICE_BASE * (Config.EGG_PRICE_LEVEL_GROWTH ^ (lvl - 1)) * Config.EGG_PRICE_STAR[Stats.stars(sp)] * (Config.EGG_PRICE_ELEMENT[el] or 1)
	p *= 1 + (jitter * 2 - 1) * Config.EGG_PRICE_JITTER
	if p > 1000 then
		return math.floor(p / 50) * 50
	end
	return math.floor(p / 10) * 10
end

-- Timers grow with level AND rarity (stars): higher levels and rarer eggs take far longer
local function starMult(stars: number?): number
	return Config.TIMER_STAR_MULT[math.clamp(stars or 1, 1, #Config.TIMER_STAR_MULT)]
end

-- Shipwright tiers (Config.SHIP_TIERS). Tier N unlocks after clearing stage 2N - 2 and costs about
-- Config.SHIPWRIGHT.minutes of battling at the stage 2N, so the price tracks your income all game.
function Stats.shipTierStage(tier: number): number
	return 2 * tier
end

-- the best depth that unlocks a tier (its stage's predecessor cleared)
function Stats.shipTierDepth(tier: number): number
	return (Stats.shipTierStage(tier) - 2) * Config.STAGE_LENGTH
end

function Stats.shipTierPrice(tier: number): number
	local stage = Stats.shipTierStage(tier)
	local depth = (stage - 1) * Config.STAGE_LENGTH + Config.MINIBOSS_AT
	local perKill = (Config.COINS_BASE + Config.COINS_PER_DEPTH * depth) * Config.COINS_STAGE_MULT ^ (stage - 1)
	return math.floor(perKill * 10 * Config.SHIPWRIGHT.minutes / 50) * 50
end

-- Floor 3 costs Config.FLOOR3.minutes of battle income at the stage it unlocks
function Stats.floor3Price(): number
	return math.floor(Stats.coinsPerMinute(Config.FLOOR3.depth) * Config.FLOOR3.minutes / 50) * 50
end

-- What a hatched monster sells for
function Stats.sellPrice(sp: string, lvl: number, variant: string?): number
	local v = if variant == "Rainbow" then 6 elseif variant == "Golden" then 2.5 else 1
	return math.max(1, math.floor(Stats.eggPrice(sp, lvl, Stats.stars(sp), 0.5) * v * Config.SELL_RATIO))
end

function Stats.hatchSeconds(lvl: number, stars: number?): number
	local c = Config.HATCH_CURVE
	return math.min(Config.TIMER_MAX_SECONDS, math.floor(math.max(c.min, c.a * lvl ^ c.p) * starMult(stars)))
end

-- A fuse's rarity is the rarer parent's stars (so the client can show the time up front)
-- (lvl = the parents' level; the fuse makes lvl + 1)
function Stats.fuseSeconds(lvl: number, stars: number?): number
	return math.max(4, math.floor(Stats.hatchSeconds(lvl, stars) * Config.FUSE_FACTOR))
end

-- Highest level a monster can be fused up to: 3 + the stages you have cleared (bosses beaten)
function Stats.levelCap(bestDepth: number): number
	return math.min(Config.MAX_LEVEL, Config.LEVEL_CAP_BASE + bestDepth // Config.STAGE_LENGTH)
end

function Stats.skipPearls(secondsLeft: number): number
	return math.max(1, math.ceil(secondsLeft / 60 * Config.SKIP_PEARLS_PER_MINUTE))
end

-- Price of the n-th extra nest (owned = how many nests you have now)
function Stats.nestPrice(owned: number): number
	local extra = owned - Config.START_NESTS
	return math.floor(Config.NEST_BASE_PRICE * Config.NEST_PRICE_GROWTH ^ extra / 50) * 50
end

function Stats.upgradePrice(id: string, level: number): number?
	local u = Config.UPGRADES[id]
	if not u then
		return nil
	end
	if u.prices then
		return u.prices[level + 1]
	end
	if level >= u.max then
		return nil
	end
	return math.floor(u.base * u.growth ^ level / 100) * 100
end

-- Hybrid species for a pair of elements (nil if the pair is the same element)
function Stats.hybridOf(a: string, b: string): string?
	if a == b then
		return nil
	end
	for _, id in Config.MONSTER_ORDER do
		local def = Config.MONSTERS[id]
		if not def.secret and #def.elements == 2 then
			local e1, e2 = def.elements[1], def.elements[2]
			if (e1 == a and e2 == b) or (e1 == b and e2 == a) then
				return id
			end
		end
	end
	return nil
end

export type Outcome = { sp: string, chance: number }

-- The next species up an element's line (nil past 3 stars)
function Stats.tierUp(element: string, stars: number): string?
	local line = Config.TIER_OF[element]
	return line and line[stars + 1] or nil
end

-- Possible fuse results of two species at a level, with chances that add up to 1.
-- Simple rules a kid can learn from the odds row:
--   same element      -> chance to climb that element's line (1* -> 2* -> 3*)
--   different elements -> mostly their 2* hybrid, small chance to climb either line
--   Lv5+ with an Epic  -> tiny chance of a Legendary
-- luckMult (Fuse Luck) boosts every "better" outcome.
function Stats.fuseOutcomes(spA: string, spB: string, lvl: number, luckMult: number): { Outcome }
	local out: { Outcome } = {}
	local function add(sp: string?, chance: number)
		if not sp or chance <= 0 then
			return
		end
		for _, o in out do
			if o.sp == sp then
				o.chance += chance
				return
			end
		end
		table.insert(out, { sp = sp, chance = chance })
	end
	local a, b = Config.MONSTERS[spA], Config.MONSTERS[spB]
	local ea, eb = a.elements[1], b.elements[1]
	local top = math.max(a.stars, b.stars)
	local good = 0 -- total weight given to upgrades
	local function try(sp: string?, c: number)
		if sp then
			add(sp, c)
			good += c
		end
	end
	-- two Legendaries+ at a high level: a whisper of a Mythic
	if top >= 4 and lvl + 1 >= 8 then
		try(Config.MYTHIC_OF[ea], math.min(0.1, 0.015 * luckMult))
	end
	-- mixed Epics at Lv5+: the hybrid Legendaries
	if top >= 3 and ea ~= eb and lvl + 1 >= Config.FUSE_SECRET_MIN_LEVEL then
		local legend = if ea == "Abyss" or eb == "Abyss" or ea == "Storm" or eb == "Storm" then "Leviathan" else "PearlDragon"
		try(legend, math.min(0.25, 0.04 * luckMult))
	end
	-- the same 2* hybrid twice: its 3* evolution
	if spA == spB and Config.HYBRID_UP[spA] then
		try(Config.HYBRID_UP[spA], math.min(0.7, 0.35 * luckMult))
	end
	if ea == eb then
		local up = Stats.tierUp(ea, top)
		local base = if top <= 2 then 0.3 elseif top == 3 then 0.12 else 0
		try(up, math.min(0.7, base * luckMult))
	else
		local hybrid = Stats.hybridOf(ea, eb)
		if hybrid and top <= 2 then
			local c = math.min(0.75, 0.55 * math.sqrt(luckMult))
			add(hybrid, c)
			good += c
		end
		for _, e in { ea, eb } do
			local up = Stats.tierUp(e, top)
			local c = if up then math.min(0.2, 0.06 * luckMult) else 0
			add(up, c)
			good += c
		end
	end
	local rest = math.max(0, 1 - good)
	add(spA, rest / 2)
	add(spB, rest / 2)
	table.sort(out, function(x, y)
		return x.chance > y.chance
	end)
	return out
end


-- Coins per minute a run around this depth earns (coin packs + offline use it)
function Stats.coinsPerMinute(bestDepth: number): number
	local d = math.max(5, bestDepth)
	return Stats.killCoins(d, "mob") * 14
end

return Stats
