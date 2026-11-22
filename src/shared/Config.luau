--!strict
-- Merge Sea Monsters: every tunable in one place. Server and client both read this, so they can
-- never disagree. Retune numbers here, not in the services.

local Config = {}

Config.GAME_NAME = "Merge Sea Monsters"
Config.DATASTORE_NAME = "TideTamers_v1"
Config.AUTOSAVE_INTERVAL = 90
-- Studio-only admin controls (AdminService re-checks RunService:IsStudio()): TuckerFLNK
Config.ADMIN_IDS = { 11140921447 } :: { number }

---------------------------------------------------------------------------
-- World layout (studs). Ships sit in a ring round the harbour island.
---------------------------------------------------------------------------
Config.SEA_LEVEL = 0 -- water surface Y
Config.SHIP_COUNT = 6 -- one per player (6-player servers)
Config.SHIP_RING_RADIUS = 206 -- harbour centre -> ship centre
Config.HUB_RADIUS = 78 -- harbour island (town is roomy: vendors, plaza and palms all breathe)
Config.TOWN_SCALE = Config.HUB_RADIUS / 62 -- how much bigger the town is than v1 (layout numbers below are v1 x this)
Config.DECK_Y = 9 -- top of the main deck
Config.UPPER_DECK_Y = 19 -- top of the quarterdeck (Floor 2)
Config.SHIP_LENGTH = 168 -- big decks so nests, eggs and their name tags never crowd
Config.SHIP_WIDTH = 68
Config.ARENA_OFFSET = 80 -- ship centre -> arena centre, out to sea
Config.ARENA_RADIUS = 24
-- Invisible wall ring (radius from the harbour centre) that keeps swimmers in the play area. The
-- farthest thing in the world (a ship's stern plus its arena / trench off the side) is about 315 out.
Config.SWIM_RADIUS = 345

-- Nest slots on a ship (local to the ship: +X = starboard, -Z = bow towards the harbour).
-- The first START_NESTS are free; the rest are bought (and stay hidden until the tutorial
-- is done). Upper-deck nests need Floor 2.
Config.NEST_SLOTS = {
	{ pos = Vector3.new(-18, 0, 0), floor = 1 },
	{ pos = Vector3.new(0, 0, 0), floor = 1 },
	{ pos = Vector3.new(18, 0, 0), floor = 1 },
	{ pos = Vector3.new(-18, 0, 18), floor = 1 },
	{ pos = Vector3.new(0, 0, 18), floor = 1 },
	{ pos = Vector3.new(18, 0, 18), floor = 1 },
	{ pos = Vector3.new(-18, 0, 36), floor = 1 },
	{ pos = Vector3.new(18, 0, 36), floor = 1 },
	{ pos = Vector3.new(-18, 0, 64), floor = 2 },
	{ pos = Vector3.new(0, 0, 64), floor = 2 },
	{ pos = Vector3.new(18, 0, 64), floor = 2 },
	{ pos = Vector3.new(0, 0, 77), floor = 2 },
	-- Floor 3: the poop deck over the stern (reached by the starboard stairs)
	{ pos = Vector3.new(-20, 0, 78), floor = 3 },
	{ pos = Vector3.new(-7, 0, 78), floor = 3 },
	{ pos = Vector3.new(7, 0, 78), floor = 3 },
	{ pos = Vector3.new(20, 0, 78), floor = 3 },
}
Config.QUARTERDECK_Z = 54 -- the raised stern deck (Floor 2) starts here
Config.MAST_POS = Vector3.new(0, 0, 36)
Config.START_NESTS = 3
Config.NEST_BASE_PRICE = 1500 -- the cheapest a nest can ever be
Config.NEST_MINUTES = 5 -- a nest costs about this many minutes of battle coins at its stage (see Stats.nestPrice)

Config.WINCH_POS = Vector3.new(-24, 0, -40) -- the fishing rod, casting over the port rail
-- The rod dives through stacked zones in a trench off the port side; the server rolls where
-- it stops (Egg Luck makes deeper zones likelier). Each zone's eggs are its element; the
-- Abyss gives rare hybrids. A cast takes FISH_BASE + zone * FISH_PER_ZONE seconds (about 9.5-13.5 s).
Config.FISH_ZONES = {
	{ id = "Shallows", name = "Sunny Shallows", element = "Tide", weight = 40, color = Color3.fromRGB(80, 210, 255) },
	{ id = "Kelp", name = "Kelp Forest", element = "Coral", weight = 28, color = Color3.fromRGB(90, 220, 120) },
	{ id = "Reef", name = "Coral Reef", element = "Storm", weight = 18, color = Color3.fromRGB(255, 120, 170) },
	{ id = "Wreck", name = "Shipwreck Graveyard", element = "Abyss", weight = 10, color = Color3.fromRGB(200, 160, 90) },
	{ id = "Abyss", name = "The Abyss", element = nil, weight = 4, color = Color3.fromRGB(170, 90, 255) },
}
Config.FISH_ZONE_HEIGHT = 40 -- studs of water per zone
Config.ROD_SCALE = 1.7 -- the Blender rod is scaled up this much on deck so the station stands out
Config.FISH_BASE = 8.5
Config.FISH_PER_ZONE = 1.0
Config.FISH_TIME = Config.FISH_BASE + #Config.FISH_ZONES * Config.FISH_PER_ZONE -- longest cast
Config.PEDESTAL_POS = { Vector3.new(-8, 0, -36), Vector3.new(4, 0, -36), Vector3.new(16, 0, -36), Vector3.new(-2, 0, -24), Vector3.new(10, 0, -24) }
Config.SPAWN_POS = Vector3.new(0, 0, 27) -- where you stand when you join
-- Deck cannons (Ship Workshop > Cannons): level L puts cannon pairs at the first L entries of
-- CANNON_Z (one on each rail, CANNON_X from the centre line) on a raised mount of CANNON_BASE studs,
-- clear of the nests, boards, rod station, stairs and the boarding gaps in the rails.
Config.CANNON_Z = { 5, 36, -21, 51, -30 }
Config.CANNON_X = 30
Config.CANNON_BASE = 2.2

---------------------------------------------------------------------------
-- Currencies and economy
---------------------------------------------------------------------------
Config.START_COINS = 2500
Config.ROLL_COOLDOWN = 3 -- extra guard; a cast also blocks the next until it lands
-- Timers are a power curve of the level, then x rarity: seconds = max(HATCH_MIN, A * lvl^P) * star.
-- A smooth curve, so timers climb gradually and only the very top reaches the 6 hour ceiling
-- (TIMER_MAX_SECONDS): a Lv18 Mythic (5 star) is exactly 6 h, a Lv12 Mythic 2.7 h, a Lv12
-- Common 20 min, a Lv5 Common 3 min. A fuse of two Lv N monsters takes FUSE_FACTOR x a Lv N hatch.
Config.HATCH_CURVE = { a = 8.33, p = 2.0, min = 6 }
Config.FUSE_FACTOR = 0.9
-- Timers also grow with RARITY: x this for a 1..5 star egg / fuse (a Mythic takes 8x a Common of
-- the same level). Timers are wall-clock (os.time), so they keep running while you are offline.
Config.TIMER_STAR_MULT = { 1, 1.6, 2.6, 4.5, 8 }
Config.TIMER_MAX_SECONDS = 6 * 3600 -- no single timer is longer than 6 hours
-- Harder to build the higher you go: a monster can only be fused up to (stages cleared + this).
-- Clear the boss of a stage to raise the cap by one. Nothing you can buy skips it.
Config.LEVEL_CAP_BASE = 3
-- Lose a fight (a monster faints) and it has to rest this long before it can fight again.
-- Paying for a Revive right after the defeat skips the rest.
Config.REST_SECONDS = 30
-- Selling a hatched monster pays this fraction of what an egg like it costs (so buying an egg
-- and selling the baby always loses coins). Golden / Rainbow sell for more, like their eggs.
Config.SELL_RATIO = 0.5
Config.SKIP_PEARLS_PER_MINUTE = 5 -- pearls to finish a timer early (min 1)

-- Upgrade boards on the ship
Config.UPGRADES = {
	-- prices follow Stats.stagePrice: `minutes` of battle income at stage 1 + level * stageStep
	Luck = { name = "Egg Luck", max = 10, minutes = 10, stageStep = 2, desc = "Better eggs from the rod" },
	-- one egg per cast now, so this board speeds the rod up instead (each level 8% faster)
	Pedestals = { name = "Fast Reel", max = 3, minutes = 10, stageStep = 2, desc = "The rod reels in eggs faster" },
}
-- The Shipwright (board on your deck): 12 tiers, each one adds something to the ship's looks and
-- a small permanent bonus. Tier N unlocks once you have cleared stage 2N - 2 and costs about
-- SHIPWRIGHT.minutes of battling coins at the stage you can first buy it (a coin sink that scales).
Config.SHIPWRIGHT = { coinPerTier = 0.05, hatchPerTier = 0.03, minutes = 10 }
Config.SHIP_TIERS = {
	"Lantern Posts", "Brass Rails", "Pennant Flags", "Dragon Figurehead", "Golden Star Sail", "Cannon Deck",
	"Twin Mast", "Crow's Nest Lantern", "Coral Hull", "Glowing Wake", "Gold Sail Trim", "Royal Flagship",
}
-- Ship Workshop (a board on your deck): permanent fittings that help in battle a LITTLE (5% a
-- level, so they never replace spells or monsters), and paint to make the ship yours.
Config.FITTINGS = {
	-- priced by Stats.fittingPrice: `minutes` of income at stage 1 + level * stageStep
	Cannons = { name = "Cannons", desc = "+5% damage per level", max = 5, minutes = 8, stageStep = 3, icon = "Swords", dmg = 0.05 },
	Hull = { name = "Hull Plating", desc = "+5% health per level", max = 5, minutes = 8, stageStep = 3, icon = "Team", hp = 0.05 },
	CrowsNest = { name = "Crow's Nest", desc = "+2s boss timer per level", max = 5, minutes = 10, stageStep = 3, icon = "Boss", bossTime = 2 },
	Figurehead = { name = "Lucky Figurehead", desc = "+5% egg luck per level", max = 5, minutes = 10, stageStep = 3, icon = "LuckEgg", luck = 0.05 },
}
Config.FITTING_ORDER = { "Cannons", "Hull", "CrowsNest", "Figurehead" }
Config.PAINTS = {
	Sail = {
		{ id = "Cloud", name = "Cloud", color = Color3.fromRGB(250, 246, 232), price = 0 },
		{ id = "Sunset", name = "Sunset", color = Color3.fromRGB(255, 150, 80), price = 2500 },
		{ id = "Berry", name = "Berry", color = Color3.fromRGB(190, 90, 220), price = 2500 },
		{ id = "Lagoon", name = "Lagoon", color = Color3.fromRGB(70, 210, 200), price = 2500 },
		{ id = "Blossom", name = "Blossom", color = Color3.fromRGB(255, 140, 190), price = 2500 },
		{ id = "Midnight", name = "Midnight", color = Color3.fromRGB(60, 70, 130), price = 6000 },
	},
	Stripe = {
		{ id = "Gold", name = "Gold", color = Color3.fromRGB(245, 205, 70), price = 0 },
		{ id = "Coral", name = "Coral", color = Color3.fromRGB(255, 100, 110), price = 1500 },
		{ id = "Mint", name = "Mint", color = Color3.fromRGB(90, 220, 140), price = 1500 },
		{ id = "Sky", name = "Sky", color = Color3.fromRGB(90, 190, 255), price = 1500 },
		{ id = "Violet", name = "Violet", color = Color3.fromRGB(170, 110, 255), price = 1500 },
		{ id = "Ink", name = "Ink", color = Color3.fromRGB(40, 44, 70), price = 4000 },
	},
}
-- Some fished eggs cost coins: a "Treasure Egg" costs coins but is a level higher
Config.EGG_PRICE_CHANCE = 0.3
Config.FLOOR2 = { fuses = 20, coins = 130000 } -- the quarterdeck + Lighthouse boost: 12 minutes of income at stage 4
-- Floor 3 (the poop deck, 4 more nests): needs stage 10 cleared, 150 fuses and ~10 minutes of battle coins
Config.FLOOR3 = { fuses = 150, depth = 150, minutes = 10 }
Config.FLOOR3_Y = 29 -- top of the poop deck (the quarterdeck is UPPER_DECK_Y = 19)
Config.FLOOR3_COIN_BONUS = 0.2
Config.LIGHTHOUSE_COIN_BONUS = 0.15

-- Offline battling: your team keeps earning while you're away
Config.OFFLINE_MAX_HOURS = 8
Config.OFFLINE_RATE = 0.10 -- fraction of a live run's coin rate (8 h away = about 48 min of play); playing always beats waiting

---------------------------------------------------------------------------
-- Elements: Tide > Abyss > Coral > Storm > Tide (+50% damage, "SUPER!")
---------------------------------------------------------------------------
Config.ELEMENTS = {
	Tide = { name = "Tide", color = Color3.fromRGB(40, 160, 255), beats = "Abyss", order = 1 },
	Coral = { name = "Coral", color = Color3.fromRGB(255, 110, 150), beats = "Storm", order = 2 },
	Storm = { name = "Storm", color = Color3.fromRGB(255, 214, 40), beats = "Tide", order = 3 },
	Abyss = { name = "Abyss", color = Color3.fromRGB(150, 80, 230), beats = "Coral", order = 4 },
}
Config.SUPER_MULT = 1.5
Config.WEAK_MULT = 1 -- no "weak" hits: element advantage only ever helps (shown as SUPER!)

---------------------------------------------------------------------------
-- Monsters. Shapes are built from shared/MonsterShapes (generated by Blender spec).
-- elements: one = pure, two = hybrid. role tunes the stat spread.
---------------------------------------------------------------------------
Config.ROLES = {
	balanced = { hp = 1.0, atk = 1.0, rate = 1.0 },
	tank = { hp = 1.45, atk = 0.75, rate = 0.9 },
	fast = { hp = 0.85, atk = 0.7, rate = 1.6 },
	brute = { hp = 0.8, atk = 1.45, rate = 0.85 },
}

-- stars = rarity of the species (shown as the star row, like the reference game):
-- 1 Common, 2 Rare, 3 Epic, 4 Legendary, 5 Mythic. Stats scale with stars.
Config.MONSTERS = {
	-- 1 star: the winch's common eggs
	Splashfin = { name = "Splashfin", elements = { "Tide" }, role = "balanced", stars = 1 },
	Reefback = { name = "Reefling", elements = { "Coral" }, role = "tank", stars = 1 },
	Zapjelly = { name = "Zappy", elements = { "Storm" }, role = "fast", stars = 1 },
	Gloomeel = { name = "Gloomy", elements = { "Abyss" }, role = "brute", stars = 1 },
	-- 2 stars: rare evolutions and the six hybrids
	Wavecrest = { name = "Wavecrest", elements = { "Tide" }, role = "balanced", stars = 2 },
	Shellguard = { name = "Shellguard", elements = { "Coral" }, role = "tank", stars = 2 },
	Voltfin = { name = "Voltfin", elements = { "Storm" }, role = "fast", stars = 2 },
	Inkling = { name = "Inkling", elements = { "Abyss" }, role = "brute", stars = 2 },
	Kelpdrake = { name = "Kelpdrake", elements = { "Tide", "Coral" }, role = "tank", stars = 2 },
	Thunderwhale = { name = "Thunderwhale", elements = { "Tide", "Storm" }, role = "balanced", stars = 2 },
	Inkshark = { name = "Inkshark", elements = { "Tide", "Abyss" }, role = "brute", stars = 2 },
	Sparkcrab = { name = "Sparkcrab", elements = { "Coral", "Storm" }, role = "fast", stars = 2 },
	Bonereef = { name = "Bonereef", elements = { "Coral", "Abyss" }, role = "tank", stars = 2 },
	Voidray = { name = "Voidray", elements = { "Storm", "Abyss" }, role = "brute", stars = 2 },
	-- 3 stars: epics
	Tsunamaw = { name = "Tsunamaw", elements = { "Tide" }, role = "balanced", stars = 3 },
	Coralord = { name = "Coralord", elements = { "Coral" }, role = "tank", stars = 3 },
	Thunderjaw = { name = "Thunderjaw", elements = { "Storm" }, role = "fast", stars = 3 },
	Nightfang = { name = "Nightfang", elements = { "Abyss" }, role = "brute", stars = 3 },
	-- 3 stars: hybrid evolutions (fuse two of the same hybrid)
	Kelpking = { name = "Kelp King", elements = { "Tide", "Coral" }, role = "tank", stars = 3 },
	TempestWhale = { name = "Tempest Whale", elements = { "Tide", "Storm" }, role = "balanced", stars = 3 },
	AbyssShark = { name = "Abyss Shark", elements = { "Tide", "Abyss" }, role = "brute", stars = 3 },
	Voltclaw = { name = "Voltclaw", elements = { "Coral", "Storm" }, role = "fast", stars = 3 },
	Bonelord = { name = "Bonelord", elements = { "Coral", "Abyss" }, role = "tank", stars = 3 },
	Nightray = { name = "Nightray", elements = { "Storm", "Abyss" }, role = "brute", stars = 3 },
	-- 4 stars: legendary
	Tidalord = { name = "Tidalord", elements = { "Tide" }, role = "balanced", stars = 4 },
	ReefColossus = { name = "Reef Colossus", elements = { "Coral" }, role = "tank", stars = 4 },
	Stormwyrm = { name = "Stormwyrm", elements = { "Storm" }, role = "fast", stars = 4 },
	VoidSerpent = { name = "Void Serpent", elements = { "Abyss" }, role = "brute", stars = 4 },
	Leviathan = { name = "Leviathan", elements = { "Tide", "Abyss" }, role = "brute", stars = 4 },
	PearlDragon = { name = "Pearl Dragon", elements = { "Coral", "Tide" }, role = "balanced", stars = 4 },
	-- 5 stars: mythic (very rare fuses, crate, event, Robux)
	KrakenKing = { name = "Kraken King", elements = { "Abyss", "Coral" }, role = "brute", stars = 5, secret = true },
	StormEmperor = { name = "Storm Emperor", elements = { "Storm", "Tide" }, role = "fast", stars = 5, secret = true },
	CoralTitan = { name = "Coral Titan", elements = { "Coral", "Storm" }, role = "tank", stars = 5, secret = true },
	TideSeraph = { name = "Tide Seraph", elements = { "Tide", "Coral" }, role = "balanced", stars = 5, secret = true },
}
-- Index / display order
Config.MONSTER_ORDER = {
	"Splashfin", "Reefback", "Zapjelly", "Gloomeel",
	"Wavecrest", "Shellguard", "Voltfin", "Inkling",
	"Kelpdrake", "Thunderwhale", "Inkshark", "Sparkcrab", "Bonereef", "Voidray",
	"Tsunamaw", "Coralord", "Thunderjaw", "Nightfang",
	"Kelpking", "TempestWhale", "AbyssShark", "Voltclaw", "Bonelord", "Nightray",
	"Tidalord", "ReefColossus", "Stormwyrm", "VoidSerpent", "Leviathan", "PearlDragon",
	"KrakenKing", "StormEmperor", "CoralTitan", "TideSeraph",
}
-- Each element's line: 1* -> 2* -> 3* -> 4*
Config.TIER_OF = {
	Tide = { "Splashfin", "Wavecrest", "Tsunamaw", "Tidalord" },
	Coral = { "Reefback", "Shellguard", "Coralord", "ReefColossus" },
	Storm = { "Zapjelly", "Voltfin", "Thunderjaw", "Stormwyrm" },
	Abyss = { "Gloomeel", "Inkling", "Nightfang", "VoidSerpent" },
}
-- Two of the same 2* hybrid can fuse into its 3* evolution
Config.HYBRID_UP = {
	Kelpdrake = "Kelpking", Thunderwhale = "TempestWhale", Inkshark = "AbyssShark",
	Sparkcrab = "Voltclaw", Bonereef = "Bonelord", Voidray = "Nightray",
}
-- The 5* mythic each element can (very rarely) fuse into
Config.MYTHIC_OF = { Tide = "TideSeraph", Coral = "CoralTitan", Storm = "StormEmperor", Abyss = "KrakenKing" }

-- Index milestones: discovering this many species pays out automatically
Config.INDEX_REWARDS = {
	{ count = 5, pearls = 50 },
	{ count = 10, pearls = 120 },
	{ count = 15, pearls = 200 },
	{ count = 20, pearls = 350 },
	{ count = 25, pearls = 600 },
	{ count = 34, pearls = 2000 },
}

-- Mutations: every egg rolls one. They change the look and multiply stats (classic RNG).
Config.VARIANTS = {
	{ id = "Normal", name = "", weight = 94, mult = 1 },
	{ id = "Golden", name = "Golden", weight = 5, mult = 2, color = Color3.fromRGB(255, 205, 50) },
	{ id = "Rainbow", name = "Rainbow", weight = 1, mult = 5, color = Color3.fromRGB(255, 120, 220) },
}
-- Egg-only starters by element (what the winch hauls most)
Config.STARTER_OF = { Tide = "Splashfin", Coral = "Reefback", Storm = "Zapjelly", Abyss = "Gloomeel" }
Config.RARITY = {
	{ name = "Common", color = Color3.fromRGB(200, 210, 225) },
	{ name = "Rare", color = Color3.fromRGB(80, 190, 255) },
	{ name = "Epic", color = Color3.fromRGB(190, 110, 255) },
	{ name = "Legendary", color = Color3.fromRGB(255, 200, 40) },
	{ name = "Mythic", color = Color3.fromRGB(255, 80, 140) },
}
-- Each element's signature move (fires when the energy bar fills). Simple and readable.
Config.MOVES = {
	Tide = { name = "BOOM!", desc = "A super hit for 3.5x damage" },
	Coral = { name = "BOOM!", desc = "A super hit for 3.5x damage" },
	Storm = { name = "BOOM!", desc = "A super hit for 3.5x damage" },
	Abyss = { name = "BOOM!", desc = "A super hit for 3.5x damage" },
}
Config.CORAL_HEAL = 0.18 -- fraction of max HP healed on every teammate

-- Base stats of a Lv1, 1-star monster (role multiplies them)
Config.BASE_HP = 120
Config.BASE_ATK = 5
Config.BASE_ATTACK_INTERVAL = 1.1 -- seconds between attacks at rate 1
Config.LEVEL_STAT_GROWTH = 1.6 -- every stat x this per level
Config.STAR_MULT = { 1, 1.25, 1.6, 2.1, 3.0 }
Config.MAX_LEVEL = 32
Config.ABILITY_HITS = 4 -- normal hits to fill the energy bar
Config.ABILITY_MULT = 3.5 -- ability hit = this x attack

-- Winch roll odds. Star odds shift with Luck upgrade (+luck% moves weight up the tiers)
Config.ELEMENT_WEIGHTS = { Tide = 30, Coral = 25, Storm = 25, Abyss = 20 }
Config.STAR_WEIGHTS = { 86, 12, 2 } -- winch rarity: 1*, 2*, 3* (luck shifts it up)
Config.EGG_LEVEL_WEIGHTS = { 80, 17, 3 } -- Lv1/2/3 from the winch
Config.EGG_PRICE_BASE = 350
Config.EGG_PRICE_LEVEL_GROWTH = 2.0
Config.EGG_LEVEL_PER_STAGE = 1 -- winch eggs gain a level for every stage you've reached
Config.EGG_PRICE_STAR = { 1, 1.8, 3.5, 8, 20 }
Config.EGG_PRICE_ELEMENT = { Tide = 1, Coral = 1.25, Storm = 1.6, Abyss = 2.2 }
Config.EGG_PRICE_JITTER = 0.15

-- Fusing: same level only. Hybrid when elements differ, small chance of a parent's
-- species instead, tiny chance of a secret at Lv5+.
Config.FUSE_PARENT_CHANCE = 0.30 -- split between the two parents' species
Config.FUSE_SECRET_CHANCE = 0.02
-- Any fuse can very rarely come out with a 6th star (`x6` on the monster). It only adds a tiny
-- stat bonus: a showpiece, not a power jump.
Config.SIXTH_STAR_CHANCE = 0.005
Config.SIXTH_STAR_MULT = 1.01
Config.FUSE_SECRET_MIN_LEVEL = 5
Config.FUSE_STAR_UP_CHANCE = 0.18 -- the child gets +1 star over the better parent
Config.FUSE_LUCK_MULT = 2 -- Fuse Luck product doubles star-up and secret chances
Config.INSANE_LUCK_MULT = 4

---------------------------------------------------------------------------
-- Battle. A stage is 15 depths: 8 = mini-boss, 15 = boss.
---------------------------------------------------------------------------
Config.STAGE_LENGTH = 15
Config.MINIBOSS_AT = 8
Config.TICK = 0.1
-- Battles last longer: enemies have 4x the HP they had and hit about 40% softer, so a fight
-- is a few seconds of back and forth instead of a blink (a team near its limit takes roughly
-- 4-10 s per enemy, a team far above its depth 2-4 s). Boss timer doubled to match.
Config.ENEMY_BASE_HP = 56
Config.ENEMY_HP_PER_DEPTH = 0.12 -- within a stage
-- Progressive pacing: each new stage multiplies enemy HP by a step that grows from FIRST to LAST
-- across the 15 stage changes (tuned for ~2 h to reach stage 5, ~40-70 h to beat Maw).
-- 26 stages (390 depths). Each stage is 1.8x the one before; with the level cap (cleared + 3) a team needs
-- about one more level per stage, so there is always a next timer to wait on and a next upgrade to chase.
-- Simulated with the pacing sim: best-case team ~40 h, good team ~46 h, average ~29 h of hatching.
Config.STAGE_COUNT = 26
Config.ENEMY_HP_STEP_FIRST = 1.8
Config.ENEMY_HP_STEP_LAST = 1.8
Config.ENEMY_ATK_STEP_RATIO = 0.9 -- attack steps are this fraction of the HP step
Config.ENEMY_BASE_ATK = 3
Config.FINAL_ATK_EXTRA = 1.5 -- Maw hits harder than a normal boss (HP is a normal boss's)
Config.ENEMY_ATTACK_INTERVAL = 1.45
Config.MINIBOSS_HP_MULT = 4
Config.MINIBOSS_ATK_MULT = 1.6
Config.BOSS_HP_MULT = 10
Config.BOSS_ATK_MULT = 1.4
Config.BOSS_TIME = 60 -- seconds to beat a boss
Config.NEXT_WAVE_DELAY = 1.0
-- Coins per kill = (BASE + PER_DEPTH * depth) * STAGE_MULT^(stage - 1). Tuned so that a cap-level egg costs
-- about 5 minutes of battling at stage 1, falling to about 1-2 minutes late: coins always matter.
Config.COINS_BASE = 55
Config.COINS_PER_DEPTH = 1
Config.COINS_STAGE_MULT = 1.95
Config.BOSS_COIN_BONUS = 500
Config.PEARL_CHANCE = 0.3 -- per kill
Config.RUN_END_PEARLS_PER_STAGE = 25
Config.FINAL_DEPTH = Config.STAGE_COUNT * Config.STAGE_LENGTH -- the last boss (Maw) is the end of stage 26
Config.REVIVE_WINDOW = 15 -- seconds the Revive offer stays up

-- Stage themes (repeat after the list ends, stronger each loop)
Config.STAGES = {
	{ name = "Sunny Shallows", water = Color3.fromRGB(40, 190, 230), mobs = { "Crab", "Puffer", "Gull" }, miniboss = "Puffer", boss = "Clawbeard" },
	{ name = "Kelp Forest", water = Color3.fromRGB(30, 150, 140), mobs = { "Urchin", "Crab", "Squid" }, miniboss = "Urchin", boss = "Hammerjaw" },
	{ name = "Shipwreck Bay", water = Color3.fromRGB(30, 110, 150), mobs = { "Skelefish", "Squid", "Gull" }, miniboss = "Skelefish", boss = "GhostCaptain" },
	{ name = "Twilight Deep", water = Color3.fromRGB(30, 60, 120), mobs = { "Squid", "Skelefish", "Urchin" }, miniboss = "Squid", boss = "Hammerjaw" },
	{ name = "Coral Maze", water = Color3.fromRGB(200, 90, 130), mobs = { "Crab", "Urchin", "Puffer" }, miniboss = "Crab", boss = "Clawbeard" },
	{ name = "Sunken Temple", water = Color3.fromRGB(40, 140, 120), mobs = { "Skelefish", "Crab", "Squid" }, miniboss = "Skelefish", boss = "GhostCaptain" },
	{ name = "Frozen Trench", water = Color3.fromRGB(120, 190, 235), mobs = { "Puffer", "Gull", "Squid" }, miniboss = "Puffer", boss = "Hammerjaw" },
	{ name = "Volcanic Vents", water = Color3.fromRGB(190, 80, 40), mobs = { "Urchin", "Crab", "Skelefish" }, miniboss = "Urchin", boss = "Clawbeard" },
	{ name = "Storm Surface", water = Color3.fromRGB(70, 90, 130), mobs = { "Gull", "Squid", "Puffer" }, miniboss = "Gull", boss = "Hammerjaw" },
	{ name = "Pirate Graveyard", water = Color3.fromRGB(60, 80, 70), mobs = { "Skelefish", "Gull", "Crab" }, miniboss = "Skelefish", boss = "GhostCaptain" },
	{ name = "Crystal Caverns", water = Color3.fromRGB(110, 90, 200), mobs = { "Squid", "Urchin", "Puffer" }, miniboss = "Squid", boss = "Hammerjaw" },
	{ name = "The Black Current", water = Color3.fromRGB(20, 30, 70), mobs = { "Squid", "Skelefish", "Urchin" }, miniboss = "Skelefish", boss = "GhostCaptain" },
	{ name = "The Trench Gate", water = Color3.fromRGB(35, 15, 60), mobs = { "Skelefish", "Squid", "Urchin" }, miniboss = "Squid", boss = "GhostCaptain" },
}
Config.FINAL_BOSS = "Maw"
Config.ENEMIES = {
	Crab = { name = "Crab", element = "Coral", scale = 1.1 },
	Puffer = { name = "Puffer", element = "Tide", scale = 1.0 },
	Gull = { name = "Sea Gull", element = "Storm", scale = 1.0 },
	Urchin = { name = "Urchin", element = "Abyss", scale = 1.0 },
	Squid = { name = "Squid", element = "Abyss", scale = 1.1 },
	Skelefish = { name = "Skelefish", element = "Storm", scale = 1.1 },
	Clawbeard = { name = "Captain Clawbeard", element = "Coral", scale = 2.6, boss = true },
	Hammerjaw = { name = "Hammerjaw", element = "Tide", scale = 2.6, boss = true },
	GhostCaptain = { name = "Ghost Captain", element = "Abyss", scale = 2.6, boss = true },
	Maw = { name = "Maw, the Abyss King", element = "Abyss", scale = 1.3, boss = true },
}

---------------------------------------------------------------------------
-- Tutorial (server advances the step; client draws banner + arrow trail)
---------------------------------------------------------------------------
-- target: what the arrows point at. "winch" | "pedestal" | "nest" | "egg" | "fight" | "fuse" | nil
Config.TUTORIAL = {
	{ text = "Cast the rod to fish up an <EGG>!", target = "winch" },
	{ text = "Take your first <EGG>!", target = "pedestal" },
	{ text = "Put your egg in a <NEST>!", target = "nest" },
	{ text = "Open your egg when it's <READY>!", target = "egg" },
	{ text = "Try to beat the <MINI BOSS>!", target = "fight" },
	{ text = "You need <MORE MONSTERS>!", target = "winch" },
	{ text = "Take your new <EGG>!", target = "pedestal" },
	{ text = "Put your egg in a <NEST>!", target = "nest" },
	{ text = "Open your egg when it's <READY>!", target = "egg" },
	{ text = "Press E on a monster, then another, to <FUSE>!", target = "mon" },
	{ text = "Your monsters are <FUSING>...", target = nil },
	{ text = "Fish up one more <EGG>!", target = "winch" },
	{ text = "Take the <REEF EGG>!", target = "pedestal" },
	{ text = "Put your egg in a <NEST>!", target = "nest" },
	{ text = "Open your egg when it's <READY>!", target = "egg" },
	{ text = "Beat the <BOSS> at Depth 15!", target = "fight" },
}
Config.TUTORIAL_DONE = #Config.TUTORIAL + 1
-- Scripted winch hauls during the tutorial (step -> egg). Prices fit the starting coins.
Config.TUTORIAL_EGGS = {
	[1] = { sp = "Splashfin", lvl = 1, stars = 1, price = 800 },
	[6] = { sp = "Zapjelly", lvl = 1, stars = 1, price = 1500 },
	[12] = { sp = "Reefback", lvl = 1, stars = 1, price = 300 },
}
Config.HUD_UNLOCK_STEP = 12 -- the full HUD (menus, offers) appears from this step

---------------------------------------------------------------------------
-- Monetization. id = 0 means "not created yet" (Studio simulates the purchase).
---------------------------------------------------------------------------
Config.GAMEPASSES = {
	VIP = { id = 2093567317, price = 349, name = "VIP Captain", desc = "+25% coins, gold name tag and a gold nest." },
	DoubleCoins = { id = 2093447301, price = 219, name = "x2 Coins", desc = "Double coins from every battle." },
	FastFuse = { id = 2094359336, price = 299, name = "x2 Fuse Speed", desc = "Eggs hatch and monsters fuse twice as fast." },
	FastBattle = { id = 2096773204, price = 59, name = "x2 Battle Speed", desc = "Unlocks the x2 battle speed toggle." },
	ExtraPedestal = { id = 2092505182, price = 149, name = "Fast Reel", desc = "The fishing rod reels in eggs 8% faster." },
	DoubleLuck = { id = 2093183555, price = 100, name = "x2 Luck", desc = "Double egg luck and fuse luck forever." },
}
Config.PRODUCTS = {
	StarterPack = { id = 3734236479, price = 69, name = "Starter Pack", desc = "A Lv3 Kelpdrake, 5,000 coins and 50 pearls." },
	FuseLuck = { id = 3734236499, price = 20, name = "Fuse Luck", desc = "x2 star and secret chance for 15 minutes." },
	InsaneLuck = { id = 3734236523, price = 50, name = "Insane Fuse Luck", desc = "x4 star and secret chance for 15 minutes." },
	Luck30 = { id = 0, price = 10, name = "x2 Luck 30m", desc = "Double egg luck and fuse luck for 30 minutes." }, -- id 0 until created on Roblox
	Revive = { id = 3734236545, price = 39, name = "Revive", desc = "Bring your team back at full health and keep diving." },
	SkipTimer = { id = 3734236563, price = 25, name = "Hatch Now", desc = "Finish every egg and fuse timer right now." },
	CoinsSmall = { id = 3734236578, price = 49, name = "Coin Chest", desc = "A chest of coins (scales with your best depth)." },
	CoinsBig = { id = 3734236692, price = 199, name = "Coin Ship", desc = "A shipload of coins (scales with your best depth)." },
	PearlDragonPack = { id = 3734236716, price = 499, name = "Pearl Dragon", desc = "The Legendary Pearl Dragon (4 stars) at Lv5." },
	ElementBundle = { id = 3734236734, price = 199, name = "Elemental Bundle", desc = "One 2-star egg of every element." },
	LimitedRoll = { id = 3734236748, price = 99, name = "Abyss Crate", desc = "Roll the Abyss Crate (5% Leviathan)." },
	PowerSpins = { id = 3734236771, price = 79, name = "5 Power Spins", desc = "Five spins of the Power wheel." },
}
-- One icon per pass / product (rendered by assets/icons/build_icons.py, uploaded to the group).
-- The same PNGs (assets/icons/png/store/*.png) are what you set as the item icon in Creator Hub.
Config.STORE_ICONS = {
	VIP = "rbxassetid://138739310735703",
	DoubleCoins = "rbxassetid://138902125467176",
	FastFuse = "rbxassetid://94377732401142",
	FastBattle = "rbxassetid://84081021718145",
	ExtraPedestal = "rbxassetid://107902905956530",
	StarterPack = "rbxassetid://104199940950385",
	FuseLuck = "rbxassetid://83171630655834",
	InsaneLuck = "rbxassetid://97724225922785",
	Revive = "rbxassetid://114382509497655",
	SkipTimer = "rbxassetid://100768135562227",
	CoinsSmall = "rbxassetid://87718050215696",
	CoinsBig = "rbxassetid://126928939257506",
	PearlDragonPack = "rbxassetid://90967136736990",
	ElementBundle = "rbxassetid://137302013461895",
	LimitedRoll = "rbxassetid://112329307204969",
	PowerSpins = "rbxassetid://85540592026439",
}
Config.LUCK_SECONDS = 900
Config.LUCK30_SECONDS = 1800 -- the x2 Luck 30m product
Config.VIP_COIN_BONUS = 0.25
Config.COIN_PACK_MINUTES = { CoinsSmall = 6, CoinsBig = 30 } -- = this many minutes of battle coins

-- Rotating offer slot on the right of the HUD (cycles every OFFER_ROTATE seconds)
Config.OFFER_ROTATION = { "DoubleCoins", "Luck30", "FuseLuck", "FastFuse", "DoubleLuck", "FastBattle", "InsaneLuck" }
Config.OFFER_ROTATE = 25

Config.CODES = {
	SEAMONSTER = { pearls = 50 },
	AHOY = { coins = 2000 },
	FREESPIN = { spins = 1 },
}

---------------------------------------------------------------------------
-- Team: how many monsters go out to fight (the rest stay on deck)
---------------------------------------------------------------------------
Config.TEAM_START = 3
Config.TEAM_MAX = 8
-- 4th..8th slot: 12 minutes of income at stages 2, 6, 10, 14, 18 (Stats.stagePrice)
Config.TEAM_SLOT_PRICES = { 26000, 650000, 14000000, 260000000, 4600000000 }

---------------------------------------------------------------------------
-- Powers: spin a random passive onto one monster (unlocks at a depth)
---------------------------------------------------------------------------
Config.POWERS_UNLOCK_DEPTH = 30
Config.POWER_SPIN_PEARLS = 25
Config.POWERS = {
	{ id = "Fierce", name = "Fierce", desc = "+30% attack", weight = 30, color = Color3.fromRGB(255, 90, 70) },
	{ id = "Tough", name = "Tough", desc = "+40% health", weight = 30, color = Color3.fromRGB(90, 200, 110) },
	{ id = "Swift", name = "Swift", desc = "+30% attack speed", weight = 22, color = Color3.fromRGB(80, 190, 255) },
	{ id = "Greedy", name = "Greedy", desc = "+25% coins from battles", weight = 12, color = Color3.fromRGB(255, 205, 50) },
	{ id = "Titan", name = "Titan", desc = "+60% attack and health", weight = 5, color = Color3.fromRGB(190, 110, 255) },
	{ id = "Kraken", name = "Kraken", desc = "Ability every 2 hits", weight = 1, color = Color3.fromRGB(255, 80, 200) },
}

---------------------------------------------------------------------------
-- Event: limited-time Tide Festival. Shells come from the Gift Chest and daily chest; spend them in the event shop.
---------------------------------------------------------------------------
Config.EVENT = {
	name = "Tide Festival",
	endsAt = 1798761600, -- 2027-01-01 00:00 UTC
	shellChance = 0.35, -- per kill
	shop = {
		{ id = "FestivalEgg", name = "Festival Egg", desc = "A 3-star hybrid egg", cost = 120 },
		{ id = "PearlBag", name = "Pearl Bag", desc = "+60 pearls", cost = 50 },
		{ id = "LuckBoost", name = "Fuse Luck", desc = "x2 fuse luck, 10 min", cost = 70 },
	},
}

---------------------------------------------------------------------------
-- Limited crate stand on the harbour: roll for the Leviathan
---------------------------------------------------------------------------
Config.LIMITED = {
	name = "Abyss Crate",
	pearls = 150,
	odds = { { sp = "Inkling", chance = 0.40 }, { sp = "Voidray", chance = 0.34 }, { sp = "Nightfang", chance = 0.19 }, { sp = "Leviathan", chance = 0.05 }, { sp = "KrakenKing", chance = 0.02 } },
	stars = 2,
}

---------------------------------------------------------------------------
-- Spells: cards from the Gift Chest and daily chest (SPELL_DROP tables pick the rarity;
-- always). Collect them in the Spellbook (the harbour vendor opens a big book), then cast
-- one to get its boost for `minutes`. Casting the same spell again adds time.
-- effects (all multiply / add together while active):
--   eggLuck  winch rarity luck      mutation  Golden/Rainbow chance   pedestals  extra eggs per haul
--   coins    battle coins            pearls    pearl drop chance        dmg / hp   team attack / health
--   fuseLuck fuse upgrade chance     hatch     timer speed (2 = twice as fast)
---------------------------------------------------------------------------
Config.SPELLS = {
	-- Common
	{ id = "LuckyTide", name = "Lucky Tide", desc = "x1.5 egg luck", rarity = 1, minutes = 5, icon = "LuckEgg", effects = { eggLuck = 1.5 } },
	{ id = "CoinSplash", name = "Coin Splash", desc = "x1.5 battle coins", rarity = 1, minutes = 5, icon = "Coin", effects = { coins = 1.5 } },
	{ id = "QuickHatch", name = "Quick Hatch", desc = "Hatch 2x faster", rarity = 1, minutes = 5, icon = "Speed", effects = { hatch = 2 } },
	{ id = "SharpFins", name = "Sharp Fins", desc = "+25% damage", rarity = 1, minutes = 5, icon = "Swords", effects = { dmg = 1.25 } },
	-- Rare
	{ id = "DoubleHaul", name = "Double Haul", desc = "Rod reels 8% faster", rarity = 2, minutes = 8, icon = "Pedestal", effects = { pedestals = 1 } },
	{ id = "ToughScales", name = "Tough Scales", desc = "+40% health", rarity = 2, minutes = 6, icon = "Team", effects = { hp = 1.4 } },
	{ id = "FuseCharm", name = "Fuse Charm", desc = "x2 fuse luck", rarity = 2, minutes = 6, icon = "Heart", effects = { fuseLuck = 2 } },
	{ id = "PearlRain", name = "Pearl Rain", desc = "x3 pearl drops", rarity = 2, minutes = 6, icon = "Pearl", effects = { pearls = 3 } },
	-- Epic
	{ id = "GoldenTouch", name = "Golden Touch", desc = "x5 Golden & Rainbow eggs", rarity = 3, minutes = 6, icon = "Shop", effects = { mutation = 5 } },
	{ id = "TidalFury", name = "Tidal Fury", desc = "+60% damage", rarity = 3, minutes = 6, icon = "Power", effects = { dmg = 1.6 } },
	{ id = "TreasureTide", name = "Treasure Tide", desc = "x3 battle coins", rarity = 3, minutes = 6, icon = "Coin", effects = { coins = 3 } },
	-- Legendary
	{ id = "KrakenBlessing", name = "Kraken Blessing", desc = "x3 egg luck, rod 8% faster", rarity = 4, minutes = 10, icon = "Crate", effects = { eggLuck = 3, pedestals = 1 } },
	{ id = "MoonFuse", name = "Moon Fuse", desc = "x3 fuse luck", rarity = 4, minutes = 10, icon = "Event", effects = { fuseLuck = 3 } },
	-- Mythic
	{ id = "AbyssAwakening", name = "Abyss Awakening", desc = "x2 damage and health", rarity = 5, minutes = 8, icon = "Boss", effects = { dmg = 2, hp = 2 } },
	-- more Common
	{ id = "ShellShine", name = "Shell Shine", desc = "x1.3 egg luck", rarity = 1, minutes = 6, icon = "LuckEgg", effects = { eggLuck = 1.3 } },
	{ id = "PennyPouch", name = "Penny Pouch", desc = "x1.3 battle coins", rarity = 1, minutes = 6, icon = "Coin", effects = { coins = 1.3 } },
	{ id = "ZippyShells", name = "Zippy Shells", desc = "Hatch 1.5x faster", rarity = 1, minutes = 6, icon = "Speed", effects = { hatch = 1.5 } },
	{ id = "BarnacleBite", name = "Barnacle Bite", desc = "+15% damage", rarity = 1, minutes = 6, icon = "Swords", effects = { dmg = 1.15 } },
	{ id = "BubbleShield", name = "Bubble Shield", desc = "+20% health", rarity = 1, minutes = 6, icon = "Team", effects = { hp = 1.2 } },
	-- more Rare
	{ id = "SeaBreeze", name = "Sea Breeze", desc = "Hatch 3x faster", rarity = 2, minutes = 5, icon = "Speed", effects = { hatch = 3 } },
	{ id = "TrawlNet", name = "Trawl Net", desc = "x2 egg luck", rarity = 2, minutes = 6, icon = "LuckEgg", effects = { eggLuck = 2 } },
	{ id = "SunkenGold", name = "Sunken Gold", desc = "x2 battle coins", rarity = 2, minutes = 6, icon = "Coin", effects = { coins = 2 } },
	{ id = "ReefRoar", name = "Reef Roar", desc = "+40% damage", rarity = 2, minutes = 6, icon = "Swords", effects = { dmg = 1.4 } },
	{ id = "PearlDiver", name = "Pearl Diver", desc = "x2 pearl drops", rarity = 2, minutes = 8, icon = "Pearl", effects = { pearls = 2 } },
	-- more Epic
	{ id = "RainbowRipple", name = "Rainbow Ripple", desc = "x8 Golden & Rainbow eggs", rarity = 3, minutes = 5, icon = "Shop", effects = { mutation = 8 } },
	{ id = "WhirlpoolHaul", name = "Whirlpool Haul", desc = "Rod reels 16% faster", rarity = 3, minutes = 6, icon = "Pedestal", effects = { pedestals = 2 } },
	{ id = "CoralArmor", name = "Coral Armor", desc = "x2 health", rarity = 3, minutes = 6, icon = "Team", effects = { hp = 2 } },
	{ id = "StormSurge", name = "Storm Surge", desc = "x1.8 damage, x1.5 coins", rarity = 3, minutes = 6, icon = "Power", effects = { dmg = 1.8, coins = 1.5 } },
	{ id = "PearlStorm", name = "Pearl Storm", desc = "x5 pearl drops", rarity = 3, minutes = 6, icon = "Pearl", effects = { pearls = 5 } },
	-- more Legendary
	{ id = "TidalCrown", name = "Tidal Crown", desc = "x2 coins and x2 egg luck", rarity = 4, minutes = 8, icon = "Crate", effects = { coins = 2, eggLuck = 2 } },
	{ id = "DeepCurrent", name = "Deep Current", desc = "Hatch 4x faster, x2 fuse luck", rarity = 4, minutes = 8, icon = "Event", effects = { hatch = 4, fuseLuck = 2 } },
	{ id = "LeviathanRage", name = "Leviathan Rage", desc = "x2.5 damage", rarity = 4, minutes = 8, icon = "Boss", effects = { dmg = 2.5 } },
	-- more Mythic
	{ id = "AbyssCrown", name = "Abyss Crown", desc = "x4 egg luck, rod 16% faster, x4 fuse luck", rarity = 5, minutes = 6, icon = "Crate", effects = { eggLuck = 4, pedestals = 2, fuseLuck = 4 } },
	{ id = "KingTide", name = "King Tide", desc = "x3 damage, health and coins", rarity = 5, minutes = 6, icon = "Boss", effects = { dmg = 3, hp = 3, coins = 3 } },
}
-- Spell art (rendered in Blender: assets/icons/build_spell_icons.py). One picture per effect;
-- the `icon` above is only the fallback if a spell is not listed here.
Config.SPELL_ICON = {
	LuckyTide = "Spell_EggLuck", ShellShine = "Spell_EggLuck", TrawlNet = "Spell_EggLuck",
	CoinSplash = "Spell_Coins", PennyPouch = "Spell_Coins", SunkenGold = "Spell_Coins", TreasureTide = "Spell_Treasure",
	QuickHatch = "Spell_HatchSpeed", ZippyShells = "Spell_HatchSpeed", SeaBreeze = "Spell_HatchSpeed", DeepCurrent = "Spell_Whirlpool",
	SharpFins = "Spell_Damage", BarnacleBite = "Spell_Damage", ReefRoar = "Spell_Damage", TidalFury = "Spell_Fang", LeviathanRage = "Spell_Fang",
	DoubleHaul = "Spell_Haul", WhirlpoolHaul = "Spell_Haul",
	ToughScales = "Spell_Health", BubbleShield = "Spell_Health", CoralArmor = "Spell_Health",
	FuseCharm = "Spell_FuseLuck", MoonFuse = "Spell_Moon",
	PearlRain = "Spell_Pearls", PearlDiver = "Spell_Pearls", PearlStorm = "Spell_Pearls",
	GoldenTouch = "Spell_GoldenEgg", RainbowRipple = "Spell_Mutation", StormSurge = "Spell_Storm",
	KrakenBlessing = "Spell_Kraken", AbyssAwakening = "Spell_Abyss", AbyssCrown = "Spell_Abyss",
	TidalCrown = "Spell_Crown", KingTide = "Spell_King",
}
for _, sp in Config.SPELLS do
	local art = Config.SPELL_ICON[sp.id]
	if art then
		sp.icon = art
	end
end
-- Spellbook set rewards: find every spell of a rarity and the book pays out once (pearls)
Config.SPELL_SETS = { 20, 40, 80, 150, 300 } -- by rarity (Common..Mythic)
-- Combine: this many cards of one rarity make one random card of the next rarity
Config.SPELL_COMBINE = 3

-- Missions (the board on the left of the HUD): three at a time, each paying coins + pearls.
-- A mission is sized to take about 2 minutes early and 5-10 minutes late (targets grow with your stage).
Config.MISSIONS = {
	count = 3,
	-- coins = this many minutes of battle income at your best depth (Stats.coinsPerMinute)
	minutes = { fish = 1.5, hatch = 2, fuse = 2.5, kills = 2, boss = 4, sell = 1 },
	pearls = { fish = 1, hatch = 2, fuse = 3, kills = 2, boss = 6, sell = 1 },
}
-- drop chance per kill, and the rarity weights (Common..Mythic) of what drops
Config.SPELL_DROP = {
	mob = { chance = 0.03, weights = { 80, 18, 2, 0, 0 } },
	miniboss = { chance = 0.3, weights = { 55, 33, 10, 2, 0 } },
	boss = { chance = 1, weights = { 25, 40, 25, 9, 1 } },
	final = { chance = 1, weights = { 0, 0, 40, 45, 15 } },
}

-- Egg Shop (harbour stand): premium eggs for pearls
Config.EGG_SHOP = {
	{ id = "RareEgg", name = "Rare Egg", desc = "A random 2-star egg", pearls = 60, tier = 2 },
	{ id = "EpicEgg", name = "Epic Egg", desc = "A random 3-star egg", pearls = 260, tier = 3 },
	-- Golden is x2 stats, better than an Epic (x1.6), so it costs more than the Epic egg
	{ id = "GoldenEgg", name = "Golden Egg", desc = "A Golden egg (x2 stats)", pearls = 400, tier = 1, variant = "Golden" },
}

---------------------------------------------------------------------------
-- Playtime gifts (minutes this session) and the daily chest
---------------------------------------------------------------------------
Config.GIFTS = {
	{ min = 1, coins = 500 },
	{ min = 3, pearls = 10, spell = "miniboss" },
	{ min = 6, coins = 2500, shells = 15 },
	{ min = 10, spins = 1 },
	{ min = 15, pearls = 30, spell = "boss", shells = 20 },
	{ min = 20, egg = 2 }, -- egg = levels above your stage
	{ min = 30, pearls = 75, spell = "final" },
}
Config.DAILY_PEARLS = { 10, 15, 20, 30, 40, 60, 100 } -- by streak day
Config.GROUP_ID = 865496476 -- the owning group (the Gift Chest has a plain "Join the Crew" button, no reward)
Config.FRIEND_BOOST = 0.1 -- +10% battle coins for each friend in your server
Config.FRIEND_BOOST_MAX = 3
-- Badges (0 = not created yet). Create them in Creator Hub > Badges and paste the ids here.
Config.BADGES = {
	Welcome = 2077297959419624, -- Welcome Aboard!
	FirstHatch = 1001596991742430, -- First Hatch
	FirstFuse = 88552570788093, -- First Fuse
	FirstBoss = 1544952781343054, -- Boss Beater
	Legendary = 4222686682678814, -- Legendary Tamer
	Depth50 = 0, -- not created yet (free badge quota ran out): "Deep Diver"
	Depth100 = 0, -- not created yet: "Abyss Explorer"
	Maw = 0, -- not created yet: "Abyss King Slayer"
}

---------------------------------------------------------------------------
-- HUD icons (rendered in Blender by assets/icons/build_icons.py, uploaded to the group)
---------------------------------------------------------------------------
Config.ICONS = {
	Shop = "rbxassetid://112052750486791",
	Coin = "rbxassetid://88151067857512",
	Pearl = "rbxassetid://95287559745105",
	Shell = "rbxassetid://105161002839030",
	Event = "rbxassetid://74782198899378",
	Index = "rbxassetid://124221333836874",
	Team = "rbxassetid://112599311025999",
	Swords = "rbxassetid://90255808279037",
	Heart = "rbxassetid://92452957321523",
	Gift = "rbxassetid://89171850469218",
	Power = "rbxassetid://125579851480532",
	Lock = "rbxassetid://88609573588067",
	Speed = "rbxassetid://110584379544391",
	Skull = "rbxassetid://119099352078905",
	Boss = "rbxassetid://110084203144578",
	LuckEgg = "rbxassetid://122257711543315",
	Pedestal = "rbxassetid://77478671681095",
	Crate = "rbxassetid://76833700471518",
	Robux = "rbxassetid://135289974942755",
	-- Spellbook art (Spell_Pearls was still in moderation review when uploaded: if it shows blank, re-check it)
	Spell_Damage = "rbxassetid://136837578930236",
	Spell_Health = "rbxassetid://133955691763392",
	Spell_HatchSpeed = "rbxassetid://93228581052167",
	Spell_EggLuck = "rbxassetid://111707652046529",
	Spell_Coins = "rbxassetid://101471837008221",
	Spell_Pearls = "rbxassetid://93406703041821",
	Spell_Haul = "rbxassetid://103164129422564",
	Spell_FuseLuck = "rbxassetid://114072730509845",
	Spell_Mutation = "rbxassetid://107961163577574",
	Spell_Crown = "rbxassetid://99939891250189",
	Spell_Storm = "rbxassetid://84669327536090",
	Spell_Kraken = "rbxassetid://137149048412626",
	Spell_Abyss = "rbxassetid://114274047630197",
	Spell_King = "rbxassetid://134351496168768",
	Spell_Treasure = "rbxassetid://124611534225999",
	Spell_Fang = "rbxassetid://98917534640218",
	Spell_Whirlpool = "rbxassetid://104702546889244",
	Spell_Moon = "rbxassetid://135343355984332",
	Spell_GoldenEgg = "rbxassetid://128241398180029",
}

---------------------------------------------------------------------------
-- Sounds (rbxassetid, 0 = silent until uploaded)
---------------------------------------------------------------------------
-- Generated with ElevenLabs (assets/audio), uploaded to the group.
Config.SOUNDS = {
	Click = 100143720596892,
	Winch = 93276104774318,
	-- fishing and Ship Workshop (assets/audio, ElevenLabs): the cannon boom, the chime as the hook
	-- passes a zone, the egg popping out of its nest, the rod cast, the workshop upgrade
	Cannon = 71295962741418,
	ZoneChime = 110832657525357,
	EggPop = 87204529640023,
	Cast = 105307309435251,
	Upgrade = 92072519260327,
	Buy = 118571612779669,
	Place = 96720949066015,
	Hatch = 92445619035350,
	Fuse = 122810923967846,
	Hit = 100209636062398,
	Super = 135850945524549,
	EnemyDie = 76082120523415,
	Coin = 123521275321259,
	BossIntro = 90594118927098,
	Win = 72735947852511,
	Lose = 137821541809081,
	Splash = 104709010652844,
	Music = 134974519506522,
	BattleMusic = 93283679745792,
}

return Config
