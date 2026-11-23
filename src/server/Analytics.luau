--!strict
-- Creator Dashboard analytics (Roblox AnalyticsService). Everything here is fire-and-forget
-- and wrapped in pcall, so analytics can never break gameplay.
--   Onboarding funnel   (built in) 1 Joined ... 12 Tutorial complete (ONBOARDING_STEPS, fixed names)
--   Growth funnel       "Growth" (custom, ONCE per player ever): what a player reaches AFTER the tutorial:
--                       first fight, first boss, first nest, Deep Rod, Floor 2, stage 5, Floor 3, Abyss Rod, stage 10
--   Loop funnel         "Loop" (custom, once per play SESSION): fish -> hatch -> fuse -> dive -> progress -> boss
--                       (shows what returning players actually do each time they play)
--   Store funnel        1 Offer seen -> 2 Purchase prompted -> 3 Purchased   (per item; Revive also gets
--                       "Seen" when the defeat window offers it)
--   Vendor funnel       1 Vendor opened -> 2 Used the vendor                  (per vendor)
--   Economy             coins and pearls in and out, from the balance difference
--                       on every data change, tagged with why (Shop, IAP, TimedReward...)
--   Progression         every dive: start at a depth, complete each stage, fail at the end
--   Custom events       SessionStart / SessionEnd, Hatch, Fuse, RodCast, SpellCast, DailyClaim, GiftClaim, Code ...

local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local Badges = require(script.Parent.Badges)

local Analytics = {}

type Tag = { tx: string, sku: string? }

local balances: { [Player]: { coins: number, pearls: number } } = {}
local tags: { [Player]: Tag } = {}
local storeSessions: { [Player]: { [string]: string } } = {} -- item -> funnel session id
local vendorSessions: { [Player]: { [string]: string } } = {}
local onboardingLogged: { [Player]: { [number]: boolean } } = {}

local function safe(fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn("[Analytics]", err)
	end
end

local function clean(text: string): string
	-- AnalyticsService rejects step names with , " ' (and we drop markup and !)
	return (string.gsub(string.gsub(string.gsub(text, "[<>]", ""), "!", ""), "[,\"']", ""))
end

---------------------------------------------------------------------------
-- Onboarding
---------------------------------------------------------------------------
function Analytics.onboarding(player: Player, step: number, name: string)
	onboardingLogged[player] = onboardingLogged[player] or {}
	if onboardingLogged[player][step] then
		return
	end
	onboardingLogged[player][step] = true
	safe(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, string.format("%02d %s", step, name))
	end)
end

-- Fixed names, so editing the tutorial's wording never splits the dashboard's data. Step N = the
-- player just reached tutorial step N (step 1 = joined, the last = tutorial complete). If you add or
-- remove tutorial steps, keep this list the same length as #Config.TUTORIAL + 1 (= TUTORIAL_DONE).
local ONBOARDING_STEPS = {
	"Joined",
	"Cast the rod",
	"Took first egg",
	"Placed first egg",
	"Hatched first egg",
	"Tried the mini boss",
	"Cast for a second egg",
	"Took second egg",
	"Placed second egg",
	"Hatched second egg",
	"Started a fuse",
	"Tutorial complete",
}

-- the server moved the tutorial to `step` (2 .. TUTORIAL_DONE)
function Analytics.tutorialStep(player: Player, step: number)
	Analytics.onboarding(player, step, ONBOARDING_STEPS[step] or ("Step " .. step))
	if step == Config.TUTORIAL_DONE then
		Analytics.growth(player, "TutorialDone")
	end
end

---------------------------------------------------------------------------
-- Funnels with a session id per item / vendor
---------------------------------------------------------------------------
local function funnelStep(player: Player, funnel: string, map: { [Player]: { [string]: string } }, item: string, step: number, stepName: string)
	map[player] = map[player] or {}
	local id = map[player][item]
	if step == 1 or not id then
		id = HttpService:GenerateGUID(false)
		map[player][item] = id
	end
	safe(function()
		AnalyticsService:LogFunnelStepEvent(player, funnel, id, step, stepName)
	end)
end

---------------------------------------------------------------------------
-- Growth funnel: what a player reaches after the tutorial. A custom funnel with ONE run per player
-- (the session id is their UserId), each step logged only the first time EVER (remembered in their
-- save, data.funnel), so it measures how far players get over days, not per session.
---------------------------------------------------------------------------
-- Steps only ever go forward (a funnel needs that): the tutorial, the first dive, then the stages
-- cleared. Unlocks that can happen in any order (nests, rods, floors) are custom events instead.
local GROWTH_NAMES = {
	"Tutorial complete", "First dive", "Cleared stage 1", "Cleared stage 2", "Cleared stage 3",
	"Cleared stage 5", "Cleared stage 8", "Cleared stage 10", "Cleared stage 15", "Beat Maw (stage 20)",
}
local GROWTH_STEPS: { [string]: number } = {
	TutorialDone = 1,
	FirstDive = 2,
	Stage1 = 3,
	Stage2 = 4,
	Stage3 = 5,
	Stage5 = 6,
	Stage8 = 7,
	Stage10 = 8,
	Stage15 = 9,
	Stage20 = 10,
}

-- Reaching a step also logs every earlier step that was missed (an admin jump or a fast player), in order,
-- so the funnel never has holes. Remembered in the save (data.funnel = the highest step logged).
function Analytics.growth(player: Player, key: string)
	local step = GROWTH_STEPS[key]
	if not step then
		return
	end
	safe(function()
		local data = require(script.Parent.DataService).get(player) -- (lazy: DataService requires this module)
		if not data then
			return
		end
		data.funnel = data.funnel or {}
		local done = tonumber(data.funnel.growth) or 0
		for s = done + 1, step do
			AnalyticsService:LogFunnelStepEvent(player, "Growth", tostring(player.UserId), s, GROWTH_NAMES[s])
		end
		if step > done then
			data.funnel.growth = step
		end
	end)
end

-- a stage was cleared: advance the Growth funnel on the stages it tracks
function Analytics.growthStage(player: Player, stage: number)
	for _, s in { 20, 15, 10, 8, 5, 3, 2, 1 } do
		if stage >= s then
			Analytics.growth(player, "Stage" .. s)
			return
		end
	end
end

---------------------------------------------------------------------------
-- Loop funnel: the core loop once per play session (a new session id every join)
---------------------------------------------------------------------------
local LOOP_NAMES = { "Session start", "Fished an egg", "Hatched an egg", "Fused monsters", "Went on a dive", "Pushed a new depth", "Beat a boss" }
local loopSessions: { [Player]: string } = {}
local loopLogged: { [Player]: { [number]: boolean } } = {}

function Analytics.loop(player: Player, step: number)
	loopLogged[player] = loopLogged[player] or {}
	if loopLogged[player][step] then
		return
	end
	loopLogged[player][step] = true
	local id = loopSessions[player]
	if not id then
		id = HttpService:GenerateGUID(false)
		loopSessions[player] = id
	end
	safe(function()
		AnalyticsService:LogFunnelStepEvent(player, "Loop", id, step, LOOP_NAMES[step] or ("Step " .. step))
	end)
end

-- 1 Seen (offer shown / shop opened), 2 Prompted, 3 Purchased
function Analytics.store(player: Player, item: string, step: number)
	local names = { "Seen " .. item, "Prompted " .. item, "Purchased " .. item }
	funnelStep(player, "Store_" .. item, storeSessions, item, step, names[step] or item)
end

-- 1 Opened, 2 Used
function Analytics.vendor(player: Player, vendor: string, step: number)
	funnelStep(player, "Vendor_" .. vendor, vendorSessions, vendor, step, if step == 1 then "Opened" else "Used")
end

---------------------------------------------------------------------------
-- Economy: tag the reason before a change; DataService.changed logs the difference
---------------------------------------------------------------------------
-- tx: "Gameplay" | "Shop" | "IAP" | "TimedReward" | "Onboarding" | "ContextualPurchase"
function Analytics.tag(player: Player, tx: string, sku: string?)
	tags[player] = { tx = tx, sku = sku }
end

local function economy(player: Player, currency: string, delta: number, balance: number, tag: Tag)
	if delta == 0 then
		return
	end
	safe(function()
		local flow = if delta > 0 then Enum.AnalyticsEconomyFlowType.Source else Enum.AnalyticsEconomyFlowType.Sink
		local tx = (Enum.AnalyticsEconomyTransactionType :: any)[tag.tx] or Enum.AnalyticsEconomyTransactionType.Gameplay
		AnalyticsService:LogEconomyEvent(player, flow, currency, math.abs(delta), balance, tx.Name, tag.sku)
	end)
end

function Analytics.balance(player: Player, data: any)
	if not data then
		return
	end
	local last = balances[player]
	local tag = tags[player] or { tx = "Gameplay" }
	tags[player] = nil
	if last then
		economy(player, "Coins", data.coins - last.coins, data.coins, tag)
		economy(player, "Pearls", data.pearls - last.pearls, data.pearls, tag)
	end
	balances[player] = { coins = data.coins, pearls = data.pearls }
end

---------------------------------------------------------------------------
-- Progression (dives)
---------------------------------------------------------------------------
function Analytics.diveStart(player: Player, depth: number)
	Analytics.loop(player, 5) -- went on a dive
	safe(function()
		local data = require(script.Parent.DataService).get(player) -- (lazy: DataService requires this module)
		if data and data.tutorial >= Config.TUTORIAL_DONE then
			Analytics.growth(player, "FirstDive") -- the tutorial's own fights don't count
		end
	end)
	safe(function()
		AnalyticsService:LogProgressionStartEvent(player, "Dive", depth, "Depth " .. depth)
	end)
end

function Analytics.stageCleared(player: Player, stage: number)
	Badges.onEvent(player, "StageCleared", stage)
	Analytics.growthStage(player, stage)
	Analytics.loop(player, 7) -- beat a boss
	safe(function()
		AnalyticsService:LogProgressionCompleteEvent(player, "Stage", stage, "Stage " .. stage)
	end)
end

function Analytics.diveEnd(player: Player, depth: number, retreat: boolean)
	safe(function()
		if retreat then
			AnalyticsService:LogProgressionCompleteEvent(player, "Dive", depth, "Retreat at " .. depth)
		else
			AnalyticsService:LogProgressionFailEvent(player, "Dive", depth, "Lost at " .. depth)
		end
	end)
end

---------------------------------------------------------------------------
-- Custom events
---------------------------------------------------------------------------
-- custom events that also move a session's Loop funnel
local LOOP_BY_EVENT: { [string]: number } = { RodCast = 2, Hatch = 3, Fuse = 4 }

function Analytics.event(player: Player, name: string, value: number?, fields: { [string]: any }?)
	Badges.onEvent(player, name, value or 1, fields)
	local loopStep = LOOP_BY_EVENT[name]
	if loopStep then
		Analytics.loop(player, loopStep)
	end
	safe(function()
		AnalyticsService:LogCustomEvent(player, name, value or 1, fields)
	end)
end

---------------------------------------------------------------------------
-- Client reports (only what the server can't see: menus opened, prompts shown)
---------------------------------------------------------------------------
local VENDORS = { Shop = true, Event = true, Spellbook = true, Index = true, Powers = true, Gifts = true, Team = true, EggShop = true, Crate = true, Guide = true, Workshop = true, Dockyard = true }
local lastTrack: { [Player]: number } = {}

local function onTrack(player: Player, kind: any, name: any)
	if typeof(kind) ~= "string" or typeof(name) ~= "string" or #name > 40 then
		return
	end
	local now = os.clock()
	if now - (lastTrack[player] or 0) < 0.2 then
		return
	end
	lastTrack[player] = now
	if kind == "vendor" and VENDORS[name] then
		Analytics.vendor(player, name, 1)
	elseif (kind == "seen" or kind == "prompt") and (Config.PRODUCTS[name] or Config.GAMEPASSES[name]) then
		Analytics.store(player, name, if kind == "seen" then 1 else 2)
	end
end

local sessionStart: { [Player]: number } = {}

-- who the player is when a session starts / ends, as 3 custom fields (the dashboard's limit):
-- stage = their best stage, floor = 1..3, tut = 1 once the tutorial is done
local function snapshotFields(player: Player): { [string]: any }?
	local ok, data = pcall(function()
		return require(script.Parent.DataService).get(player)
	end)
	if not ok or not data then
		return nil
	end
	return {
		stage = (data.bestDepth or 0) // Config.STAGE_LENGTH + 1,
		floor = data.floor or 1,
		tut = if data.tutorial >= Config.TUTORIAL_DONE then 1 else 0,
	}
end

function Analytics.init()
	local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes) :: any
	Remotes.event("Track").OnServerEvent:Connect(onTrack)
	-- SessionStart once the save is loaded (and the Loop funnel's first step); SessionEnd with its length
	task.defer(function()
		local DataService = require(script.Parent.DataService) :: any
		DataService.Loaded:Connect(function(player: Player)
			sessionStart[player] = os.clock()
			Analytics.loop(player, 1)
			safe(function()
				AnalyticsService:LogCustomEvent(player, "SessionStart", 1, snapshotFields(player))
			end)
		end)
		-- "Leaving" fires before the save is cleared, so the player's data is still there to read
		DataService.Leaving:Connect(function(player: Player)
			local started = sessionStart[player]
			if started then
				local minutes = math.floor((os.clock() - started) / 60)
				safe(function()
					AnalyticsService:LogCustomEvent(player, "SessionEnd", minutes, snapshotFields(player))
				end)
			end
			sessionStart[player] = nil -- (here, not in PlayerRemoving: that handler can run first)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		loopSessions[player] = nil
		loopLogged[player] = nil
		balances[player] = nil
		tags[player] = nil
		storeSessions[player] = nil
		vendorSessions[player] = nil
		onboardingLogged[player] = nil
		lastTrack[player] = nil
	end)
end

return Analytics
