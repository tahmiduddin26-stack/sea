--!strict
-- Merge Sea Monsters: every tunable in one place. Server and client both read this, so they can
-- never disagree. Retune numbers here, not in the services.

local Config = {}

Config.GAME_NAME = "Merge Sea Monsters"
Config.DATASTORE_NAME = "TideTamers_v1"
Config.AUTOSAVE_INTERVAL = 90
-- Studio-only admin controls (AdminService re-checks RunService:IsStudio()): every member of
-- ADMIN_GROUP_ID (FLNK LTD, the group that owns the place), plus anyone listed in ADMIN_IDS
Config.ADMIN_GROUP_ID = 865496476 -- FLNK LTD
Config.ADMIN_IDS = { 11140921447, 11110589684 } :: { number } -- TuckerFLNK, 11110589684 = Sylar9719

---------------------------------------------------------------------------
-- World layout (studs). Ships sit in a ring round the harbour island.
---------------------------------------------------------------------------
Config.SEA_LEVEL = 0 -- water surface Y
Config.SHIP_COUNT = 6 -- one per player (6-player servers)
Config.SHIP_RING_RADIUS = 236 -- harbour centre -> ship centre (pushed out so the bigger island never touches a hull)
Config.HUB_RADIUS = 96 -- harbour island (was 78: the town felt cramped once the Dockyard joined the vendors)
Config.TOWN_SCALE = Config.HUB_RADIUS / 62 -- how much bigger the town is than v1 (layout numbers below are v1 x this)
Config.DECK_Y = 9 -- top of the main deck
Config.UPPER_DECK_Y = 19 -- top of the quarterdeck (Floor 2)
Config.SHIP_LENGTH = 168 -- big decks so nests, eggs and their name tags never crowd
Config.SHIP_WIDTH = 68
Config.ARENA_OFFSET = 110 -- ship centre -> arena centre, out to sea (starboard, ship-space X)
Config.ARENA_OFFSET_Z = 40 -- ... and this far toward the stern, clear of the Deep Rod trench
Config.ARENA_RADIUS = 60 -- 60 is the most that fits here (Deep Rod trench walls ~62 away)
-- Where things float in a fight, in studs from the arena's centre towards the ship (+) or away
-- (-). Your team lines up near the ship side of the hole (rows of 4, each row further back),
-- in front of the lookout pier; enemies and bosses rise in the middle of the hole.
Config.ARENA_TEAM_Z = 34
Config.ARENA_TEAM_ROW = 4
Config.ARENA_ENEMY_Z = 0
-- The sea's look. Roblox only shows what is under its water when the water is nearly clear, so it
-- is (the blue hole arena needs it: dark deep water, turquoise shallows). Was 0.45 / (30, 170, 220)
-- / 0.6 with the old buoy ring: opaque cyan, nothing under it showed.
Config.WATER = { transparency = 0.9, color = Color3.fromRGB(16, 120, 196), reflectance = 0.25 }
-- Invisible wall ring (radius from the harbour centre) that keeps swimmers in the play area. The
-- farthest thing in the world (a ship's stern plus its arena / trench off the side) is about 345 out.
Config.SWIM_RADIUS = 410 -- wide enough for the Abyss Rod's cast and shaft astern of each ship

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
Config.WALK_SPEED = 24 -- how fast a player runs: 1.5x Roblox's default of 16
Config.START_NESTS = 3
Config.NEST_REVEAL_MONSTERS = 3 -- the buyable nests appear once you own this many monsters
-- Coin inflation, for looks only: EVERY coin amount (what you earn AND what things cost) is this
-- many times bigger, so the economy plays exactly as before but shows thousands and millions
-- (you start with 250K, a first egg is tens of thousands). Prices that follow income (nests,
-- upgrades, fittings, floors) scale on their own through COINS_BASE / COINS_PER_DEPTH below; the
-- fixed amounts (start coins, paints, Floor 2, eggs, gifts, Robux packs) are multiplied by it.
Config.COIN_SCALE = 100
Config.NEST_BASE_PRICE = 1500 * Config.COIN_SCALE -- the cheapest a nest can ever be
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

-- The Deep Rod: a second rod on the STARBOARD rail. It unlocks after DEEP_ROD.unlockMinutes of
-- play, casts once every DEEP_ROD.cooldown seconds, and dives a deeper trench of its own
-- (Config.DEEP_ZONES). Its eggs are always free, rarity luck is x DEEP_ROD.luck (50% better than
-- the first rod), and each egg may carry a PERK (Config.PERKS): a small battle trick, never
-- extra damage. `look` picks how a zone is dressed (the first rod's looks plus Ice and Vents).
-- `trench` = the shaft centre from the rod (ship space): out past the starboard rail and a bit
-- toward the bow, so the shaft stays clear of the arena (x 80, z -24..24) and the harbour.
Config.DEEP_ROD = { unlockMinutes = 20, cooldown = 600, luck = 1.5, pos = Vector3.new(24, 0, -40), trench = Vector3.new(44, 0, -24), half = 22 }
Config.DEEP_ZONE_HEIGHT = 32
Config.DEEP_ZONES = {
	{ id = "Glimmer", name = "Glimmer Lagoon", element = "Tide", look = "Shallows", weight = 20, perk = 0.25, color = Color3.fromRGB(120, 235, 255) },
	{ id = "Frostkelp", name = "Frost Kelp", element = "Coral", look = "Ice", weight = 17, perk = 0.3, color = Color3.fromRGB(170, 230, 255) },
	{ id = "Thunder", name = "Thunder Reef", element = "Storm", look = "Reef", weight = 14, perk = 0.35, color = Color3.fromRGB(255, 230, 80) },
	{ id = "Ghostwreck", name = "Ghost Fleet", element = "Abyss", look = "Wreck", weight = 12, perk = 0.4, color = Color3.fromRGB(150, 255, 200) },
	{ id = "Vents", name = "Lava Vents", element = "Coral", look = "Vents", weight = 10, perk = 0.45, color = Color3.fromRGB(255, 120, 40) },
	{ id = "Crystal", name = "Crystal Caves", element = "Tide", look = "Ice", weight = 8, perk = 0.5, color = Color3.fromRGB(140, 200, 255) },
	{ id = "Stormdeep", name = "Storm Deep", element = "Storm", look = "Kelp", weight = 7, perk = 0.55, color = Color3.fromRGB(200, 255, 90) },
	{ id = "Ember", name = "Ember Trench", element = "Abyss", look = "Vents", weight = 5, perk = 0.6, color = Color3.fromRGB(255, 70, 90) },
	{ id = "Midnight", name = "Midnight Zone", element = nil, look = "Abyss", weight = 4, perk = 0.7, color = Color3.fromRGB(120, 110, 255) },
	{ id = "Maw", name = "Maw's Doorstep", element = nil, look = "Abyss", weight = 3, perk = 0.85, color = Color3.fromRGB(255, 60, 200) },
}
Config.DEEP_FISH_TIME = Config.FISH_BASE + #Config.DEEP_ZONES * 0.7 -- longest deep cast (0.7 s per zone)

-- The Abyss Rod: a third rod on a balcony off the STERN of the poop deck (Floor 3). It unlocks
-- after ABYSS_ROD.unlockMinutes of play AND Floor 3, casts once every ABYSS_ROD.cooldown seconds and
-- dives the deepest shaft: the Deep Rod's ten zones plus five new ones at the bottom. Eggs are
-- always free, luck is x ABYSS_ROD.luck, perks are likelier (and three perks only it gives), and
-- the five new zones can hold Legendary (4-star) eggs, the very last one even a Mythic.
-- `pos` = the rod on the balcony; `trench` = shaft centre from the rod (straight out astern, so
-- the shaft never meets the arena, the other trenches or a neighbour ship); `pedestal` = its own
-- egg pedestal on the balcony, so the catch never flies back across the ship.
Config.ABYSS_ROD = {
	unlockMinutes = 120,
	cooldown = 1200, -- one cast every 20 minutes
	luck = 2,
	pos = Vector3.new(-5, 0, 92),
	trench = Vector3.new(5, 0, 28),
	half = 18,
	perZone = 0.55,
	pedestal = Vector3.new(8, 0, 92),
}
Config.ABYSS_ZONE_HEIGHT = 30
Config.ABYSS_ZONES = {}
for _, z in Config.DEEP_ZONES do
	local c = table.clone(z)
	c.perk = math.min(1, z.perk + 0.15)
	table.insert(Config.ABYSS_ZONES, c)
end
for _, z in {
	{ id = "BoneGarden", name = "Bone Gardens", element = "Abyss", look = "Wreck", weight = 3, perk = 1, legend = 0.12, color = Color3.fromRGB(235, 225, 200) },
	{ id = "Palace", name = "Sunken Palace", element = nil, look = "Reef", weight = 2.5, perk = 1, legend = 0.18, color = Color3.fromRGB(255, 200, 90) },
	{ id = "Glowfall", name = "Glowfall Chasm", element = "Storm", look = "Ice", weight = 2, perk = 1, legend = 0.25, color = Color3.fromRGB(90, 255, 230) },
	{ id = "LeviathanRest", name = "Leviathan's Rest", element = "Tide", look = "Abyss", weight = 1.5, perk = 1, legend = 0.35, color = Color3.fromRGB(80, 140, 255) },
	{ id = "Heart", name = "Heart of the Trench", element = nil, look = "Vents", weight = 1, perk = 1, legend = 0.45, mythic = 0.04, color = Color3.fromRGB(255, 40, 120) },
} do
	table.insert(Config.ABYSS_ZONES, z)
end
Config.ABYSS_FISH_TIME = Config.FISH_BASE + #Config.ABYSS_ZONES * Config.ABYSS_ROD.perZone

-- Everything that differs between the three rods, in one place (server, world and client all use
-- it). kind: nil = the Egg Rod, "deep" (or true) = the Deep Rod, "abyss" = the Abyss Rod.
function Config.rodInfo(kind: any)
	if kind == "abyss" then
		local r = Config.ABYSS_ROD
		return { kind = "abyss", zones = Config.ABYSS_ZONES, H = Config.ABYSS_ZONE_HEIGHT, half = r.half, center = r.pos + r.trench, perZone = r.perZone, model = "AbyssRod", y = Config.FLOOR3_Y, out = Vector3.zAxis }
	elseif kind == "deep" or kind == true then
		local r = Config.DEEP_ROD
		return { kind = "deep", zones = Config.DEEP_ZONES, H = Config.DEEP_ZONE_HEIGHT, half = r.half, center = r.pos + r.trench, perZone = 0.7, model = "DeepRod", y = Config.DECK_Y, out = Vector3.xAxis }
	end
	return { kind = nil, zones = Config.FISH_ZONES, H = Config.FISH_ZONE_HEIGHT, half = 26, center = Config.WINCH_POS + Vector3.new(-44, 0, 0), perZone = Config.FISH_PER_ZONE, model = "Rod", y = Config.DECK_Y, out = -Vector3.xAxis }
end
-- Perks from the Deep Rod (`perk` on the monster). Same damage as a plain monster, just a little
-- trick in battle. A fused child keeps one of its parents' perks.
Config.PERKS = {
	Frost = { name = "Frost", desc = "Every 4th hit freezes the enemy for 1.5s", color = Color3.fromRGB(150, 230, 255), every = 4, freeze = 1.5 },
	Venom = { name = "Venom", desc = "Hits poison the enemy a little", color = Color3.fromRGB(140, 255, 90), share = 0.15, seconds = 3 },
	Bubble = { name = "Bubble", desc = "A bubble blocks the first hit from each enemy", color = Color3.fromRGB(120, 200, 255) },
	Leech = { name = "Leech", desc = "Heals 10% of the damage it deals", color = Color3.fromRGB(255, 90, 130), heal = 0.1 },
	Lucky = { name = "Lucky", desc = "+10% coins from kills while it's alive", color = Color3.fromRGB(255, 210, 60), coins = 0.1 },
	-- Abyss Rod only
	Thorns = { name = "Thorns", desc = "Enemies take 20% of the damage they deal it", color = Color3.fromRGB(255, 140, 60), share = 0.2 },
	SecondWind = { name = "Second Wind", desc = "Once per dive, gets back up with 35% HP", color = Color3.fromRGB(120, 255, 170), hp = 0.35 },
	Barnacle = { name = "Barnacle", desc = "Takes 20% less damage", color = Color3.fromRGB(200, 180, 150), cut = 0.2 },
}
Config.PERK_ORDER = { "Frost", "Venom", "Bubble", "Leech", "Lucky" }
Config.ABYSS_PERK_ORDER = { "Frost", "Venom", "Bubble", "Leech", "Lucky", "Thorns", "SecondWind", "Barnacle", "Thorns", "SecondWind", "Barnacle" } -- new perks twice as likely
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
Config.START_COINS = 2500 * Config.COIN_SCALE
Config.ROLL_COOLDOWN = 3 -- extra guard; a cast also blocks the next until it lands
-- Timers are a power curve of the level, then x rarity: seconds = max(HATCH_MIN, A * lvl^P) * star.
-- A smooth curve, so timers climb gradually and only the very top reaches the 6 hour ceiling
-- (TIMER_MAX_SECONDS): a Lv18 Mythic (5 star) is exactly 6 h, a Lv12 Mythic 2.7 h, a Lv12
-- Common 20 min, a Lv5 Common 3 min. A fuse of two Lv N monsters takes FUSE_FACTOR x a Lv N hatch.
Config.HATCH_CURVE = { a = 8.33, p = 2.0, min = 6 }
Config.FUSE_FACTOR = 0.9 -- (unused: fusing is instant now)
Config.FUSE_SECONDS = 2 -- how long a fuse takes: only the swoop and heart burst, no waiting
-- Timers also grow with RARITY: x this for a 1..5 star egg / fuse (a Mythic takes 8x a Common of
-- the same level). Timers are wall-clock (os.time), so they keep running while you are offline.
Config.TIMER_STAR_MULT = { 1, 1.6, 2.6, 4.5, 8 }
Config.TIMER_MAX_SECONDS = 6 * 3600 -- no single timer is longer than 6 hours
-- A new player's first TIMER_FAST_MINUTES of play are all fast: egg / fuse timers keep their short curve
-- (HATCH_CURVE.min). After that the shortest timer rises smoothly over TIMER_RAMP_MINUTES up to
-- TIMER_FLOOR_SECONDS and stays there. (This stretches the first 100 depths to about 6-7 hours while the
-- first stages still fly by.)
Config.TIMER_FLOOR_SECONDS = 1800
Config.TIMER_FAST_MINUTES = 15
Config.TIMER_RAMP_MINUTES = 60
-- Secret luck for new players: eggs from the rod are EARLY_LUCK times luckier for the first
-- EARLY_LUCK_MINUTES of play, then it fades to nothing over EARLY_LUCK_FADE_MINUTES. Never shown on
-- screen, so the first finds just feel generous.
Config.EARLY_LUCK = 2.5
Config.EARLY_LUCK_MINUTES = 30
Config.EARLY_LUCK_FADE_MINUTES = 30
-- Harder to build the higher you go: a monster can only be fused up to (stages cleared + this).
-- Clear the boss of a stage to raise the cap by one. Nothing you can buy skips it.
Config.LEVEL_CAP_BASE = 3
-- A fuse of Lv N monsters takes N of them (at least 2), but never more than this. Without the cap a
-- stage-20 monster took 420 eggs (20 x 21); capped it is at most 4 x 4 = 16 at any stage.
Config.FUSE_NEEDED_MAX = 4
-- Lose a fight (a monster faints) and it has to rest this long before it can fight again.
-- Paying for a Revive right after the defeat skips the rest.
Config.REST_SECONDS = 30 -- (old flat rest, unused: see Stats.restSeconds)
-- A fainted monster sleeps for REST_MIN_SECONDS (Lv1) up to REST_MAX_SECONDS (Lv MAX_LEVEL): the higher its
-- level, the longer it sleeps. The rest of your team keeps fighting while it sleeps.
Config.REST_MIN_SECONDS = 20
Config.REST_MAX_SECONDS = 180
-- Selling a hatched monster pays this fraction of what an egg like it costs (so buying an egg
-- and selling the baby always loses coins). Golden / Rainbow sell for more, like their eggs.
Config.SELL_RATIO = 0.5
-- ...and a sale never pays more than this many kills' worth of coins at your best depth
-- (Stats.killCoins of a normal enemy). 70 kills is about 5 minutes of nonstop fighting.
Config.SELL_CAP_KILLS = 70
Config.SKIP_PEARLS_PER_MINUTE = 5 -- pearls to finish a timer early (min 1)
Config.HATCH_NOW_SECONDS = 300 -- the Hatch Now product: instant eggs and fuses for 5 minutes

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
for _, list in Config.PAINTS do
	for _, p in list do
		p.price *= Config.COIN_SCALE -- coin inflation
	end
end
-- Some fished eggs cost coins: a "Treasure Egg" costs coins but is a level higher
Config.EGG_PRICE_CHANCE = 0.3
-- Floor 2 (the quarterdeck + Lighthouse boost): 10 fuses and 2M coins (about 9 minutes of income at
-- stage 2). Meant to land around the 30 minute mark.
Config.FLOOR2 = { fuses = 10, coins = 20000 * Config.COIN_SCALE }
-- Floor 3 (the poop deck, 4 more nests): needs stage 3 cleared (depth 45), 40 fuses and 8 minutes of
-- battle coins at that depth (about 4M). Meant to be reachable in about 1h 50m of play, just before
-- the Abyss Rod (which needs Floor 3 AND ABYSS_ROD.unlockMinutes = 2 hours of play) opens up.
Config.FLOOR3 = { fuses = 40, depth = 45, minutes = 8 }
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
-- Number inflation, for looks only: EVERY health and damage number (monsters AND enemies, so
-- every fight plays out exactly as before) is multiplied by this. At 550 a Lv1 Splashfin does
-- 2,500 damage per second (instead of 4.5) and a strong late-game monster shows around a million.
-- Balance, coins, timers and prices do not change: only Stats.monster and Stats.enemy use it.
Config.NUMBER_SCALE = 550
Config.BASE_HP = 120
Config.BASE_ATK = 5
Config.BASE_ATTACK_INTERVAL = 1.1 -- seconds between attacks at rate 1
Config.LEVEL_STAT_GROWTH = 1.6 -- every stat x this per level
Config.STAR_MULT = { 1, 1.25, 1.6, 2.1, 3.0 }
Config.MAX_LEVEL = 32
Config.SIZE_MAX_BONUS = 0.25 -- a monster at MAX_LEVEL looks this much bigger than at Lv1 (grows evenly with each level)
Config.ABILITY_HITS = 4 -- normal hits to fill the energy bar
Config.ABILITY_MULT = 3.5 -- ability hit = this x attack

-- Winch roll odds. Star odds shift with Luck upgrade (+luck% moves weight up the tiers)
Config.ELEMENT_WEIGHTS = { Tide = 30, Coral = 25, Storm = 25, Abyss = 20 }
Config.STAR_WEIGHTS = { 86, 12, 2 } -- winch rarity: 1*, 2*, 3* (luck shifts it up)
Config.EGG_LEVEL_WEIGHTS = { 80, 17, 3 } -- Lv1/2/3 from the winch
Config.EGG_PRICE_BASE = 350 * Config.COIN_SCALE
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
Config.ENEMY_BASE_HP = 240
Config.ENEMY_HP_PER_DEPTH = 0 -- no creep inside a stage: enemies only get tougher when a new stage starts
Config.ENEMY_ATK_PER_DEPTH = 0
-- Every normal depth is a wave of this many enemies (one after another); mini-boss and boss depths are single.
-- The depth number only goes up when the whole wave is down.
Config.WAVE_SIZE = 3
-- Pacing: 20 stages x 15 depths = 300 depths (Maw at the end). The enemy HP step per stage eases
-- from FIRST to LAST over the stage changes. Simulated new player (3 Lv1 monsters, nonstop play): depth 100 in
-- about 8 h, depth 300 in about 45-55 h (stage clears come quickly at first and slow down later).
Config.STAGE_COUNT = 20
Config.ENEMY_HP_STEP_FIRST = 1.81
Config.ENEMY_HP_STEP_LAST = 1.68
Config.ENEMY_ATK_STEP_RATIO = 0.9 -- attack steps are this fraction of the HP step
Config.ENEMY_BASE_ATK = 3
Config.FINAL_ATK_EXTRA = 1.5 -- Maw hits harder than a normal boss (HP is a normal boss's)
Config.ENEMY_ATTACK_INTERVAL = 1.45
Config.MINIBOSS_HP_MULT = 4
Config.MINIBOSS_ATK_MULT = 1.6
Config.BOSS_HP_MULT = 10
Config.BOSS_ATK_MULT = 1.4
-- Outclassed: past this many seconds for your team to kill an ordinary enemy, that enemy's damage grows in
-- proportion (up to HOPELESS_MAX_MULT x), so a hopeless dive ends fast. A fair fight (3-10 s) is unaffected.
Config.HOPELESS_TTK = 12
Config.HOPELESS_MAX_MULT = 10
Config.BOSS_TIME = 60 -- seconds to beat a boss (stages 1-10)
Config.BOSS_TIME_PER_STAGE = 2 -- + this many seconds per stage past 10 (stage 20: 80 s), so the late climb stays fair
Config.NEXT_WAVE_DELAY = 1.0
-- Coins per kill = (BASE + PER_DEPTH * depth) * STAGE_MULT^(stage - 1). Tuned so that a cap-level egg costs
-- about 5 minutes of battling at stage 1, falling to about 1-2 minutes late: coins always matter.
Config.COINS_BASE = 55 * Config.COIN_SCALE
Config.COINS_PER_DEPTH = 1 * Config.COIN_SCALE
Config.COINS_STAGE_MULT = 1.95
Config.BOSS_COIN_BONUS = 500 * Config.COIN_SCALE
Config.PEARL_CHANCE = 0.3 -- per kill
Config.RUN_END_PEARLS_PER_STAGE = 25
Config.FINAL_DEPTH = Config.STAGE_COUNT * Config.STAGE_LENGTH -- the last boss (Maw) is the end of the last stage (depth 300)
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
	-- the arrow points at the pink Fuse heart; pressing it opens the tray and only THEN does the
	-- guide draw the trail to the monsters (FuseView sets Guide.helper)
	{ text = "Press the pink <FUSE> heart to fuse your monsters!", target = "fuse" },
	{ text = "Your monsters are <FUSING>...", target = nil },
	-- the tutorial ends when the first fuse opens (FarmService.tutorial(player, 11))
}
Config.TUTORIAL_DONE = #Config.TUTORIAL + 1
-- Scripted winch hauls during the tutorial (step -> egg). Prices fit the starting coins.
Config.TUTORIAL_EGGS = {
	[1] = { sp = "Splashfin", lvl = 1, stars = 1, price = 800 },
	[6] = { sp = "Zapjelly", lvl = 1, stars = 1, price = 1500 },
}
for _, e in Config.TUTORIAL_EGGS do
	e.price *= Config.COIN_SCALE -- coin inflation
end
-- The tutorial fight (step 5): if the mini boss hasn't shown up after this many seconds, a card
-- tells the player to go fish for more monsters and offers to end the fight.
Config.TUTORIAL_FIGHT_PROMPT = 25
Config.HUD_UNLOCK_STEP = 12 -- the full HUD (menus, offers) appears from this step
Config.SIGNS_UNLOCK_STEP = 10 -- the ship's upgrade signs can be bought from this step (the Fuse step)

---------------------------------------------------------------------------
-- Monetization. id = 0 means "not created yet" (Studio simulates the purchase).
---------------------------------------------------------------------------
Config.GAMEPASSES = {
	VIP = { id = 2093567317, price = 175, name = "VIP Captain", desc = "+25% coins, gold name tag and a gold nest." },
	DoubleCoins = { id = 2093447301, price = 110, name = "x2 Coins", desc = "Double coins from every battle." },
	FastFuse = { id = 2094359336, price = 150, name = "x2 Hatch Speed", desc = "Eggs hatch twice as fast." },
	FastBattle = { id = 2096773204, price = 30, name = "x2 Battle Speed", desc = "Unlocks the x2 battle speed toggle." },
	ExtraPedestal = { id = 2092505182, price = 75, name = "Fast Reel", desc = "The fishing rod reels in eggs 8% faster." },
	DoubleLuck = { id = 2093183555, price = 50, name = "x2 Luck", desc = "Double egg luck and fuse luck forever." },
}
Config.PRODUCTS = {
	StarterPack = { id = 3734236479, price = 35, name = "Starter Pack", desc = "A Lv3 Kelpdrake, " .. (5 * Config.COIN_SCALE) .. "K coins and 50 pearls." },
	FuseLuck = { id = 3734236499, price = 10, name = "Fuse Luck", desc = "x2 star and secret chance for 15 minutes." },
	InsaneLuck = { id = 3734236523, price = 25, name = "Insane Fuse Luck", desc = "x4 star and secret chance for 15 minutes." },
	Luck30 = { id = 3734813463, price = 5, name = "x2 Luck 30m", desc = "Double egg luck and fuse luck for 30 minutes." },
	Revive = { id = 3734236545, price = 20, name = "Revive", desc = "Bring your team back at full health and keep diving." },
	-- timed: for HATCH_NOW_SECONDS every egg and fuse finishes instantly (also the "Hatch Now" nest prompt)
	SkipTimer = { id = 3734236563, price = 5, name = "Hatch Now", desc = "Every egg and fuse hatches instantly for 5 minutes." },
	CoinsSmall = { id = 3734236578, price = 25, name = "Coin Chest", desc = "A chest of coins (scales with your best depth)." },
	CoinsBig = { id = 3734236692, price = 100, name = "Coin Ship", desc = "A shipload of coins (scales with your best depth)." },
	PearlDragonPack = { id = 3734236716, price = 250, name = "Pearl Dragon", desc = "The Legendary Pearl Dragon (4 stars) at Lv5." },
	ElementBundle = { id = 3734236734, price = 100, name = "Elemental Bundle", desc = "One 2-star egg of every element." },
	LimitedRoll = { id = 3734236748, price = 50, name = "Abyss Crate", desc = "Roll the Abyss Crate (5% Leviathan)." },
	PowerSpins = { id = 3734236771, price = 40, name = "5 Power Spins", desc = "Five spins of the Power wheel." },
}
-- One icon per pass / product (rendered by assets/icons/build_icons.py, uploaded to the group).
-- The same PNGs (assets/icons/png/store/*.png) are what you set as the item icon in Creator Hub.
Config.STORE_ICONS = {
	VIP = "rbxassetid://138739310735703",
	DoubleCoins = "rbxassetid://138902125467176",
	FastFuse = "rbxassetid://94377732401142",
	FastBattle = "rbxassetid://84081021718145",
	ExtraPedestal = "rbxassetid://107902905956530",
	DoubleLuck = "rbxassetid://74834594009844",
	Luck30 = "rbxassetid://78112106934758",
	StarterPack = "rbxassetid://104199940950385",
	FuseLuck = "rbxassetid://83171630655834",
	InsaneLuck = "rbxassetid://97724225922785",
	Revive = "rbxassetid://114382509497655",
	SkipTimer = "rbxassetid://100768135562227",
	CoinsSmall = "rbxassetid://87718050215696",
	CoinsBig = "rbxassetid://91988282025667",
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
	AHOY = { coins = 2000 * Config.COIN_SCALE },
	FREESPIN = { spins = 1 },
}

---------------------------------------------------------------------------
-- Team: how many monsters go out to fight (the rest stay on deck)
---------------------------------------------------------------------------
Config.TEAM_START = 3
Config.TEAM_MAX = 6 -- a team never has more than this many (3 to start, 3 slots to buy)
-- 4th..6th slot: 12 minutes of income at stages 2, 6, 10 (Stats.stagePrice). One price per slot to
-- buy, so there is nothing left to sell once the team is at TEAM_MAX.
Config.TEAM_SLOT_PRICES = { 26000, 650000, 14000000 }
for i, p in Config.TEAM_SLOT_PRICES do
	Config.TEAM_SLOT_PRICES[i] = p * Config.COIN_SCALE -- coin inflation (was missing: slots cost 0.12 min of income, not 12)
end

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
for _, g in Config.GIFTS do
	if g.coins then
		g.coins *= Config.COIN_SCALE -- coin inflation
	end
end
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
