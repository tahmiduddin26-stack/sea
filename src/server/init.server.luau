--!strict
-- Merge Sea Monsters server bootstrap: build the world, start services, spawn players on their ship.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)
Remotes.init()

local WorldBuilder = require(script.WorldBuilder)
WorldBuilder.build()

require(script.Analytics).init()
local DataService = require(script.DataService)
local FarmService = require(script.FarmService)
local BattleService = require(script.BattleService)
local ShopService = require(script.ShopService)
local MonetizationService = require(script.MonetizationService)
local ExtrasService = require(script.ExtrasService)

Players.CharacterAutoLoads = false

FarmService.init()
BattleService.init()
ExtrasService.init()
require(script.LeaderboardService).init()
ShopService.init()
MonetizationService.init()
require(script.AdminService).init()
require(script.MissionService).init()

local function spawnPlayer(player: Player)
	if not player.Parent then
		return
	end
	player:LoadCharacter()
end

local function setupPlayer(player: Player)
	player.CharacterAdded:Connect(function(char)
		-- land on your own ship (twice: the engine places new characters at a spawn
		-- a moment after CharacterAdded, which would undo the first move)
		task.spawn(function()
			local root = char:WaitForChild("HumanoidRootPart", 5)
			if root then
				task.wait(0.1)
				FarmService.spawnAtShip(player)
				task.wait(0.4)
				FarmService.spawnAtShip(player)
			end
		end)
		local hum = char:WaitForChild("Humanoid") :: Humanoid
		hum.Died:Connect(function()
			task.wait(2)
			spawnPlayer(player)
		end)
	end)
end

-- the world build yields, so some players may already be here
for _, p in Players:GetPlayers() do
	setupPlayer(p)
end
Players.PlayerAdded:Connect(setupPlayer)

-- characters load once data (and so the ship) is ready
DataService.Loaded:Connect(function(player)
	task.defer(spawnPlayer, player)
end)

DataService.init()

-- fell in the sea? back to the deck
task.spawn(function()
	while true do
		task.wait(1)
		for _, p in Players:GetPlayers() do
			local char = p.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and root.Position.Y < -6 then
				FarmService.spawnAtShip(p)
			end
		end
	end
end)

print("[TideTamers] server ready")
