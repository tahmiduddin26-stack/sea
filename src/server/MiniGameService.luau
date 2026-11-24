--!strict
-- The harbour mini games (Coral Cards and Cannon Gallery). The games themselves are played on the client
-- (client/MiniGames.luau); the server only decides whether you may play (after the tutorial, not in a fight,
-- once per cooldown), hands out a shuffle seed, and pays the reward after checking that the result is possible
-- (not faster than a real run, not more points than the shots allow). The reward is capped, so a cheater
-- gains at most one perfect run per cooldown.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Stats = require(Shared.Stats)

local Analytics = require(script.Parent.Analytics)
local DataService = require(script.Parent.DataService)
local FarmService = require(script.Parent.FarmService)

local MiniGameService = {}

local rng = Random.new()

-- the player asks to start a game: returns ok, and (as text) the seed the client shuffles with
function MiniGameService.start(player: Player, game: any): (boolean, string?)
	local cfg = if typeof(game) == "string" then Config.MINIGAMES[game] else nil
	local data = DataService.get(player)
	local s = DataService.session(player)
	if not cfg or not data or not s then
		return false, nil
	end
	if FarmService.inTutorial(player) then
		return false, "Finish the tutorial first!"
	end
	if s.inBattle then
		return false, "Wait for the battle to end"
	end
	data.miniAt = data.miniAt or {}
	local left = (data.miniAt[game] or 0) + cfg.cooldown - os.time()
	if left > 0 then
		return false, cfg.name .. " is ready in " .. Format.time(left)
	end
	local seed = rng:NextInteger(1, 2000000000)
	;(s :: any).mini = { game = game, t0 = os.clock(), seed = seed }
	Analytics.vendor(player, if game == "cards" then "Cards" else "Cannon", 1)
	return true, tostring(seed)
end

-- the client says how the run went: { moves } for Coral Cards, { points, shots } for Cannon Gallery
function MiniGameService.finish(player: Player, arg: any): (boolean, string?)
	local data = DataService.get(player)
	local s = DataService.session(player)
	local run = if s then (s :: any).mini else nil
	if not data or not s or not run or typeof(arg) ~= "table" then
		return false, "No game in progress"
	end
	;(s :: any).mini = nil -- a run can only be paid once
	local game = run.game :: string
	local cfg = Config.MINIGAMES[game]
	local elapsed = os.clock() - (run.t0 :: number)
	if elapsed < cfg.minSeconds or elapsed > 900 then
		return false, "That was too fast to count!"
	end
	local quality: number
	if game == "cards" then
		local moves = arg.moves
		if typeof(moves) ~= "number" or moves ~= math.floor(moves) or moves < Config.CARDS_PAIRS or moves > 60 then
			return false, "That game didn't count"
		end
		-- 6 moves is perfect; every extra move costs a little, down to a quarter of the reward
		quality = math.clamp(1 - (moves - Config.CARDS_PAIRS) / 16, 0.25, 1)
	else
		-- (the Cannon Gallery is live crates now: server/CrateService)
		return false, "That game didn't count"
	end
	local coins = Stats.miniGameCoins(game, data.bestDepth or 0, quality)
	local pearls = math.floor(cfg.pearls * quality + 0.5)
	Analytics.tag(player, "Gameplay", "MiniGame_" .. game)
	data.coins += coins
	data.pearls += pearls
	data.miniAt = data.miniAt or {}
	data.miniAt[game] = os.time()
	Analytics.event(player, "MiniGame", math.floor(quality * 100), { game = game })
	Analytics.vendor(player, if game == "cards" then "Cards" else "Cannon", 2)
	DataService.changed(player)
	return true, cfg.name .. ": +" .. Format.abbrev(coins) .. " coins and +" .. pearls .. " pearls!"
end

return MiniGameService
