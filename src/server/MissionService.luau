--!strict
-- Missions: three quick goals at a time (fish eggs, hatch, fuse, beat enemies, beat a boss,
-- sell a monster). Finish one and it pays coins + pearls by itself and a new one appears.
-- Sized so there is always something worth doing in the next couple of minutes early on, and
-- in 5-10 minutes late (targets grow with the stage you have reached).
-- Other services call MissionService.record(player, kind, n) when the player does the thing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Stats = require(Shared.Stats)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local Analytics = require(script.Parent.Analytics)

local MissionService = {}

local KINDS = { "fish", "hatch", "fuse", "kills", "boss", "sell" }
local rng = Random.new()
local nextId = 0

local function stageOf(data: any): number
	return math.max(1, data.bestDepth // Config.STAGE_LENGTH + 1)
end

-- how many of a thing a mission asks for (grows with your stage)
local function targetFor(kind: string, stage: number): number
	if kind == "fish" then
		return 2 + stage // 4
	elseif kind == "hatch" then
		return 1 + stage // 5
	elseif kind == "fuse" then
		return 1 + stage // 6
	elseif kind == "kills" then
		return 8 + 3 * stage
	elseif kind == "sell" then
		return 1 + stage // 8
	end
	return 1 -- boss
end

local function toast(player: Player, text: string, color: Color3?)
	Remotes.event("Toast"):FireClient(player, text, color)
end

local function newMission(data: any): any
	local stage = stageOf(data)
	local taken = {}
	for _, m in data.missions do
		taken[m.kind] = true
	end
	local pool = {}
	for _, k in KINDS do
		-- a boss mission needs a stage-1 boss behind you; one of each kind at a time
		if not taken[k] and not (k == "boss" and data.bestDepth < Config.STAGE_LENGTH) then
			table.insert(pool, k)
		end
	end
	if #pool == 0 then
		return nil
	end
	local kind = pool[rng:NextInteger(1, #pool)]
	local cpm = Stats.coinsPerMinute(data.bestDepth)
	nextId += 1
	return {
		id = os.time() * 100 + nextId % 100,
		kind = kind,
		target = targetFor(kind, stage),
		progress = 0,
		coins = math.max(100, math.floor(cpm * Config.MISSIONS.minutes[kind] / 50) * 50),
		pearls = Config.MISSIONS.pearls[kind] + stage // 4,
	}
end

-- Keep the player topped up to Config.MISSIONS.count missions (once the tutorial is done)
function MissionService.ensure(player: Player)
	local data = DataService.get(player)
	if not data or data.tutorial < Config.TUTORIAL_DONE then
		return
	end
	local added = false
	while #data.missions < Config.MISSIONS.count do
		local m = newMission(data)
		if not m then
			break
		end
		table.insert(data.missions, m)
		added = true
	end
	if added then
		DataService.changed(player)
	end
end

local LABEL = {
	fish = "Fish up %d eggs",
	hatch = "Hatch %d monsters",
	fuse = "Fuse %d times",
	kills = "Beat %d enemies",
	boss = "Beat a boss",
	sell = "Sell %d monsters",
}

function MissionService.label(m: any): string
	local f = LABEL[m.kind] or m.kind
	return if string.find(f, "%%d") then string.format(f, m.target) else f
end

---------------------------------------------------------------------------
-- Daily quests: three bigger goals a day (a new set every UTC day), claimed at the Quest Board in town
---------------------------------------------------------------------------
local function questTarget(kind: string, stage: number, bestDepth: number): number
	if kind == "kills" then
		return 40 + 10 * stage
	elseif kind == "hatch" then
		return 3 + stage // 3
	elseif kind == "fuse" then
		return 3 + stage // 4
	elseif kind == "fish" then
		return 5 + stage // 3
	elseif kind == "sell" then
		return 3 + stage // 4
	elseif kind == "boss" then
		return if bestDepth >= Config.STAGE_LENGTH * 3 then 2 else 1
	elseif kind == "cove" or kind == "dig" then
		return 2
	end
	return 1 -- lighthouse
end

-- make sure today's three quests exist (a new UTC day brings a new set)
function MissionService.ensureQuests(player: Player)
	local data = DataService.get(player)
	if not data or data.tutorial < Config.TUTORIAL_DONE then
		return
	end
	local today = os.time() // 86400
	if data.quests.day == today and #data.quests.list > 0 then
		return
	end
	local stage = stageOf(data)
	local pool = {}
	for _, k in Config.QUESTS.order do
		local ok = true
		if k == "boss" and data.bestDepth < Config.STAGE_LENGTH then
			ok = false
		elseif (k == "cove" or k == "dig" or k == "lighthouse") and not (data.drip and data.drip[k]) then
			ok = false
		end
		if ok then
			table.insert(pool, k)
		end
	end
	-- the same player gets the same set all day (a rejoin never re-rolls it)
	local r = Random.new(today * 131 + player.UserId % 100000)
	local list = {}
	local cpm = Stats.coinsPerMinute(data.bestDepth)
	for _ = 1, math.min(Config.QUESTS.count, #pool) do
		local kind = table.remove(pool, r:NextInteger(1, #pool)) :: string
		local def = Config.QUESTS.kinds[kind]
		table.insert(list, {
			kind = kind,
			target = questTarget(kind, stage, data.bestDepth),
			progress = 0,
			coins = math.max(200, math.floor(cpm * def.minutes / 50) * 50),
			pearls = def.pearls + stage // 3,
			claimed = false,
		})
	end
	data.quests = { day = today, list = list, bonus = false }
	DataService.changed(player)
end

local function questProgress(player: Player, data: any, kind: string, amount: number)
	MissionService.ensureQuests(player)
	for _, q in data.quests.list do
		if q.kind == kind and q.progress < q.target then
			q.progress = math.min(q.target, q.progress + amount)
			if q.progress >= q.target then
				toast(player, "Daily quest done! Claim it at the Quest Board in town", Color3.fromRGB(255, 205, 60))
			end
		end
	end
end

-- Claim a finished quest (index 1..3). Claiming the third gives the bonus chest too.
function MissionService.claimQuest(player: Player, index: any): (boolean, string?)
	local data = DataService.get(player)
	if not data or typeof(index) ~= "number" then
		return false, nil
	end
	MissionService.ensureQuests(player)
	local q = data.quests.list[math.floor(index)]
	if not q then
		return false, "No such quest"
	end
	if q.claimed then
		return false, "Already claimed"
	end
	if q.progress < q.target then
		return false, "Not finished yet"
	end
	q.claimed = true
	data.coins += q.coins
	data.pearls += q.pearls
	Analytics.event(player, "QuestClaim", 1, { kind = q.kind })
	local msg = "+" .. Format.abbrev(q.coins) .. " coins, +" .. q.pearls .. " pearls"
	local all = true
	for _, other in data.quests.list do
		if not other.claimed then
			all = false
		end
	end
	if all and not data.quests.bonus then
		data.quests.bonus = true
		data.pearls += Config.QUESTS.bonusPearls
		local ExtrasService = require(script.Parent.ExtrasService) :: any
		local sp = ExtrasService.giveSpell(player, "boss")
		msg ..= "  BONUS: +" .. Config.QUESTS.bonusPearls .. " pearls" .. (if sp then " and a " .. sp.name .. " spell card!" else "!")
	end
	DataService.changed(player)
	return true, msg
end

-- The player did something: count it towards every matching mission
function MissionService.record(player: Player, kind: string, n: number?)
	local data = DataService.get(player)
	if not data or data.tutorial < Config.TUTORIAL_DONE then
		return
	end
	local amount = n or 1
	questProgress(player, data, kind, amount)
	local finished = {}
	for i, m in data.missions do
		if m.kind == kind then
			m.progress = math.min(m.target, m.progress + amount)
			if m.progress >= m.target then
				table.insert(finished, i)
			end
		end
	end
	for k = #finished, 1, -1 do
		local m = table.remove(data.missions, finished[k])
		Analytics.tag(player, "Gameplay", "Mission")
		data.coins += m.coins
		data.pearls += m.pearls
		data.missionsDone += 1
		Analytics.event(player, "Mission", data.missionsDone, { kind = m.kind })
		toast(player, "Mission complete: " .. MissionService.label(m) .. "!  +" .. Format.abbrev(m.coins) .. " coins, +" .. m.pearls .. " pearls", Color3.fromRGB(120, 230, 140))
		-- a fresh one a moment later, so the board visibly ticks over
		task.delay(1.5, function()
			if player.Parent then
				MissionService.ensure(player)
			end
		end)
	end
	DataService.changed(player)
end

function MissionService.init()
	DataService.Loaded:Connect(function(player)
		MissionService.ensure(player)
		MissionService.ensureQuests(player)
	end)
	-- the tutorial finishing (or a player whose board emptied) fills the board
	task.spawn(function()
		while true do
			task.wait(5)
			for _, p in Players:GetPlayers() do
				if DataService.isLoaded(p) then
					MissionService.ensure(p)
					MissionService.ensureQuests(p)
				end
			end
		end
	end)
end

return MissionService
