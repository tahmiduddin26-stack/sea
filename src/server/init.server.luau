--!strict
-- Merge Sea Monsters server bootstrap: build the world, start services, spawn players on their ship.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)
local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
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
require(script.CrateService).init()

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
		hum.WalkSpeed = Config.WALK_SPEED -- 1.5x the Roblox default (16), so the walk to the island is quicker
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

-- Swimming: you can swim for Config.SWIM_SECONDS. The moment you are in the water the player's
-- "SwimEndsAt" attribute (server time) says when time is up, the client counts it down on screen, and at
-- zero you are taken back to your ship. Getting out of the water (a ladder, the dock) cancels it.
task.spawn(function()
	while true do
		task.wait(0.2)
		local now = workspace:GetServerTimeNow()
		for _, p in Players:GetPlayers() do
			local char = p.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			-- a floating swimmer's root sits just under the waves (about -0.5), so go by the Swimming state;
			-- being well below the surface counts too (a dive)
			local inWater = root ~= nil and hum ~= nil and hum.Health > 0 and (hum:GetState() == Enum.HumanoidStateType.Swimming or root.Position.Y < Config.SWIM_Y)
			local endsAt = p:GetAttribute("SwimEndsAt") :: number?
			if inWater then
				if not endsAt then
					p:SetAttribute("SwimEndsAt", now + Config.SWIM_SECONDS)
				elseif now >= endsAt then
					p:SetAttribute("SwimEndsAt", nil)
					FarmService.spawnAtShip(p)
				end
			elseif endsAt then
				p:SetAttribute("SwimEndsAt", nil)
			end
		end
	end
end)

print("[TideTamers] server ready")
