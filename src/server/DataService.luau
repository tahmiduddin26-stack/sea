--!strict
-- Loads/saves player data, mirrors key stats to attributes + leaderstats, and pushes
-- snapshots to the owning client. If a load fails the session is playable but never
-- saved, so a failed load can't overwrite a real save with a fresh profile.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)

local Analytics = require(script.Parent.Analytics)

local DataService = {}

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DATASTORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[Data] DataStore unavailable, using session-only data:", result)
	end
end

local profiles: { [Player]: any } = {}
local session: { [Player]: any } = {}
local saveBlocked: { [Player]: string } = {}
local pendingSaves = 0
local dirtySnapshot: { [Player]: boolean } = {}
local loadedEvent = Instance.new("BindableEvent")
local leavingEvent = Instance.new("BindableEvent")

DataService.Loaded = loadedEvent.Event -- (player)
DataService.Leaving = leavingEvent.Event -- (player) before the final save

function DataService.defaultData()
	return {
		coins = Config.START_COINS,
		pearls = 0,
		bestDepth = 0,
		totalFuses = 0,
		totalHatches = 0,
		nextUid = 1,
		monsters = {}, -- uid(string) -> { sp, lvl, stars, v?, x6? } (x6 = very rare sixth-star fuse, +1% stats)
		-- nest index(string) -> { kind = "egg", egg = {sp,lvl,stars}, readyAt }
		--                     | { kind = "mon", uid }
		--                     | { kind = "fuse", child = {sp,lvl,stars}, readyAt }
		nests = {},
		nestCount = Config.START_NESTS,
		upgrades = { Luck = 0, Pedestals = 1 },
		floor = 1,
		shipTier = 0, -- Shipwright tiers bought (0..12)
		fittings = {}, -- Ship Workshop: fitting id -> level
		paint = { sail = "Cloud", stripe = "Gold" }, -- chosen colours
		paintOwned = { Cloud = true, Gold = true }, -- paint ids bought
		spellSets = {}, -- rarity (string) -> true once its Spellbook set reward was paid
		missions = {}, -- active missions: { id, kind, target, progress, coins, pearls }
		missionsDone = 0,
		index = {}, -- species -> true once owned
		tutorial = 1,
		introSeen = false,
		luckUntil = 0,
		luckMult = 1,
		luck30Until = 0, -- x2 Luck 30m product (egg + fuse luck)
		redeemedCodes = {},
		receipts = {},
		starterBought = false,
		groupEgg = false,
		favAsked = false,
		lastSeen = 0,
		battleSpeed = 1,
		team = {}, -- uids that fight (empty = best automatically)
		teamSlots = Config.TEAM_START,
		nestsOwned = {}, -- nest index(string) -> true for bought nests past the free ones
		spins = 0, -- free Power spins
		shells = 0, -- event currency
		eventId = "",
		dailyDay = 0,
		dailyStreak = 0,
		spells = {}, -- spell id -> how many cards you hold
		spellsFound = {}, -- spell id -> true once you have ever found it (unknown spells show as ???)
		indexV = {}, -- species -> { Golden = true, Rainbow = true } mutations found
		indexRewards = {}, -- milestone count (string) -> true once paid
		spellUntil = {}, -- spell id -> os.time it runs out
	}
end

local function reconcile(data: any)
	local def = DataService.defaultData()
	for k, v in def do
		if data[k] == nil then
			data[k] = v
		end
	end
	for k, v in def.upgrades do
		if data.upgrades[k] == nil then
			data.upgrades[k] = v
		end
	end
	return data
end

local function key(player: Player): string
	return "u_" .. player.UserId
end

function DataService.resetToNew(player: Player)
	if not profiles[player] then
		return
	end
	profiles[player] = DataService.defaultData()
	DataService.changed(player)
end

local function setupLeaderstats(player: Player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local best = Instance.new("IntValue")
	best.Name = "Depth"
	best.Parent = ls
	local coins = Instance.new("StringValue")
	coins.Name = "Coins"
	coins.Parent = ls
	ls.Parent = player
end

local function syncAttributes(player: Player)
	local data = profiles[player]
	if not data then
		return
	end
	player:SetAttribute("Coins", data.coins)
	player:SetAttribute("Pearls", data.pearls)
	player:SetAttribute("BestDepth", data.bestDepth)
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		(ls:FindFirstChild("Depth") :: IntValue).Value = data.bestDepth
		;(ls:FindFirstChild("Coins") :: StringValue).Value = Format.abbrev(data.coins)
	end
end

function DataService.get(player: Player): any
	return profiles[player]
end

function DataService.session(player: Player): any
	return session[player]
end

function DataService.isLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

function DataService.snapshot(player: Player): any
	local data = profiles[player]
	local s = session[player]
	if not data or not s then
		return nil
	end
	local snap = table.clone(data)
	snap.receipts = nil
	snap.passes = s.passes
	snap.pedestalEggs = s.pedestalEggs
	snap.carrying = s.carrying
	snap.shipIndex = s.shipIndex
	snap.inBattle = s.inBattle == true
	snap.giftsClaimed = s.giftsClaimed
	snap.sessionStart = s.joinTime
	snap.serverNow = os.time()
	-- when a monster in your nests is rested enough to fight (0 = now): the FIGHT button counts down
	local ready = nil
	for _, nest in data.nests do
		if nest.kind == "mon" then
			local m = data.monsters[nest.uid]
			if m then
				local at = m.restUntil or 0
				ready = if ready == nil then at else math.min(ready, at)
			end
		end
	end
	snap.fightReadyAt = ready or 0
	snap.isNew = s.isNew == true
	return snap
end

-- Mark data changed: attributes now, full snapshot batched.
function DataService.changed(player: Player)
	syncAttributes(player)
	Analytics.balance(player, profiles[player])
	dirtySnapshot[player] = true
end

function DataService.pushNow(player: Player)
	local snap = DataService.snapshot(player)
	if snap then
		Remotes.event("Snapshot"):FireClient(player, snap)
	end
	dirtySnapshot[player] = nil
end

function DataService.canSave(player: Player): boolean
	return store ~= nil and profiles[player] ~= nil and saveBlocked[player] == nil
end

function DataService.save(player: Player): boolean
	local data = profiles[player]
	if not data or not store or saveBlocked[player] then
		return false
	end
	data.lastSeen = os.time()
	local s = store :: DataStore
	pendingSaves += 1
	local ok, err = false, nil
	for attempt = 1, 3 do
		ok, err = pcall(function()
			s:UpdateAsync(key(player), function()
				return data
			end)
		end)
		if ok then
			break
		end
		warn("[Data] save attempt", attempt, "failed for", player.Name, err)
		if attempt < 3 then
			task.wait(1.5)
		end
	end
	pendingSaves -= 1
	return ok
end

local function isStudioApiBlock(err: any): boolean
	local msg = tostring(err)
	return string.find(msg, "StudioAccessToApisNotAllowed", 1, true) ~= nil or string.find(msg, "Studio access to APIs", 1, true) ~= nil
end

local function load(player: Player)
	local data = nil
	local loaded = false
	local blockReason: string? = nil
	if store then
		local s = store :: DataStore
		for attempt = 1, 4 do
			local ok, result = pcall(function()
				return s:GetAsync(key(player))
			end)
			if ok then
				data = result
				loaded = true
				break
			end
			warn("[Data] load attempt", attempt, "failed:", result)
			if isStudioApiBlock(result) then
				blockReason = "studio"
				break
			end
			task.wait(attempt)
		end
		if not loaded then
			blockReason = blockReason or "failed"
		end
	else
		blockReason = if RunService:IsStudio() then "studio" else "failed"
	end
	if blockReason then
		saveBlocked[player] = blockReason
	end
	if player.Parent == nil then
		return
	end
	profiles[player] = reconcile(data or DataService.defaultData())
	session[player] = {
		isNew = data == nil,
		joinTime = os.time(),
		passes = {},
		pedestalEggs = {}, -- index -> { sp, lvl, stars, price } rolled at the winch
		carrying = nil, -- { sp, lvl, stars } egg held overhead
		lastRoll = 0,
		shipIndex = 0,
		inBattle = false,
		giftsClaimed = {},
	}
	setupLeaderstats(player)
	syncAttributes(player)
	Analytics.balance(player, profiles[player]) -- starting balance (logs nothing)
	if data == nil then
		Analytics.onboarding(player, 1, "Joined")
	end
	Analytics.event(player, if data == nil then "NewPlayer" else "ReturningPlayer", 1)
	loadedEvent:Fire(player)
	DataService.pushNow(player)
	if blockReason then
		local msg = if blockReason == "studio"
			then "Saving is OFF in Studio. Turn on Game Settings > Security > Enable Studio Access to API Services."
			else "Couldn't load your save. This session won't be saved, so rejoin to get your progress back."
		warn("[Data] saving disabled for", player.Name, "(" .. blockReason .. ")")
		task.delay(6, function()
			if player.Parent then
				Remotes.event("Toast"):FireClient(player, msg, Color3.fromRGB(240, 60, 70))
			end
		end)
	end
end

function DataService.init()
	Players.PlayerAdded:Connect(load)
	for _, p in Players:GetPlayers() do
		task.spawn(load, p)
	end
	Players.PlayerRemoving:Connect(function(player)
		leavingEvent:Fire(player)
		DataService.save(player)
		profiles[player] = nil
		session[player] = nil
		dirtySnapshot[player] = nil
		saveBlocked[player] = nil
	end)
	game:BindToClose(function()
		for _, p in Players:GetPlayers() do
			task.spawn(DataService.save, p)
		end
		task.wait()
		local t0 = os.clock()
		while pendingSaves > 0 and os.clock() - t0 < 25 do
			task.wait(0.1)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.2)
			for player in dirtySnapshot do
				DataService.pushNow(player)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Config.AUTOSAVE_INTERVAL)
			for _, p in Players:GetPlayers() do
				task.spawn(DataService.save, p)
			end
		end
	end)
end

return DataService
