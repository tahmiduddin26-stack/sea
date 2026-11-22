--!strict
-- Creator Dashboard analytics (Roblox AnalyticsService). Everything here is fire-and-forget
-- and wrapped in pcall, so analytics can never break gameplay.
--   Onboarding funnel   step 1 = joined, then one step per tutorial step (Config.TUTORIAL)
--   Store funnel        1 Offer seen -> 2 Purchase prompted -> 3 Purchased   (per item)
--   Vendor funnel       1 Vendor opened -> 2 Used the vendor                  (per vendor)
--   Economy             coins and pearls in and out, from the balance difference
--                       on every data change, tagged with why (Shop, IAP, TimedReward...)
--   Progression         every dive: start at a depth, complete each stage, fail at the end
--   Custom events       Hatch, Fuse, SpellCast, SpellDrop, DailyClaim, GiftClaim, Code ...

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
	return (string.gsub(string.gsub(text, "[<>]", ""), "!", ""))
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

-- the server moved the tutorial to `step` (2 .. TUTORIAL_DONE)
function Analytics.tutorialStep(player: Player, step: number)
	local def = Config.TUTORIAL[step]
	Analytics.onboarding(player, step, if def then clean(def.text) else "Tutorial complete")
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
	safe(function()
		AnalyticsService:LogProgressionStartEvent(player, "Dive", depth, "Depth " .. depth)
	end)
end

function Analytics.stageCleared(player: Player, stage: number)
	Badges.onEvent(player, "StageCleared", stage)
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
function Analytics.event(player: Player, name: string, value: number?, fields: { [string]: any }?)
	Badges.onEvent(player, name, value or 1, fields)
	safe(function()
		AnalyticsService:LogCustomEvent(player, name, value or 1, fields)
	end)
end

---------------------------------------------------------------------------
-- Client reports (only what the server can't see: menus opened, prompts shown)
---------------------------------------------------------------------------
local VENDORS = { Shop = true, Event = true, Spellbook = true, Index = true, Powers = true, Gifts = true, Team = true, EggShop = true, Crate = true, Guide = true, Workshop = true }
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

function Analytics.init()
	local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes) :: any
	Remotes.event("Track").OnServerEvent:Connect(onTrack)
	Players.PlayerRemoving:Connect(function(player)
		balances[player] = nil
		tags[player] = nil
		storeSessions[player] = nil
		vendorSessions[player] = nil
		onboardingLogged[player] = nil
		lastTrack[player] = nil
	end)
end

return Analytics
