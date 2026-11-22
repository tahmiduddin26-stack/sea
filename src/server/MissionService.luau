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

-- The player did something: count it towards every matching mission
function MissionService.record(player: Player, kind: string, n: number?)
	local data = DataService.get(player)
	if not data or data.tutorial < Config.TUTORIAL_DONE then
		return
	end
	local amount = n or 1
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
	end)
	-- the tutorial finishing (or a player whose board emptied) fills the board
	task.spawn(function()
		while true do
			task.wait(5)
			for _, p in Players:GetPlayers() do
				if DataService.isLoaded(p) then
					MissionService.ensure(p)
				end
			end
		end
	end)
end

return MissionService
