--!strict
-- Staggered unlocks. Instead of every activity being open the moment the tutorial ends, the island's
-- activities (Crab Cove, the Lighthouse Climb, Treasure Digs) open one at a time (Config.DRIP), each a couple
-- of minutes after the last, with a "NEW!" splash and a few pearls. It keeps a new player's next reward only
-- minutes away right when most of them used to leave.
-- Players who finished the tutorial before this existed get everything open, silently.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local Analytics = require(script.Parent.Analytics)

local DripService = {}

local function defOf(id: string): any?
	for _, d in Config.DRIP do
		if d.id == id then
			return d
		end
	end
	return nil
end

function DripService.open(player: Player, id: string): boolean
	local data = DataService.get(player)
	return data ~= nil and data.drip ~= nil and data.drip[id] == true
end

-- "Crab Cove opens in 1:12 - keep playing!"
function DripService.waitText(player: Player, id: string): string
	local data = DataService.get(player)
	local def = defOf(id)
	if not data or not def then
		return "Not open yet"
	end
	if data.tutorial < Config.TUTORIAL_DONE or data.dripBase < 0 then
		return def.name .. " opens once you finish the tutorial!"
	end
	local left = math.max(1, math.ceil(def.afterMin * 60 - (DataService.playSeconds(player) - data.dripBase)))
	return def.name .. " opens in " .. Format.time(left) .. " - keep playing!"
end

local function check(player: Player)
	local data = DataService.get(player)
	if not data or not DataService.session(player) or data.tutorial < Config.TUTORIAL_DONE then
		return
	end
	local played = DataService.playSeconds(player)
	if data.dripBase < 0 then
		data.dripBase = played
	end
	for _, def in Config.DRIP do
		if not data.drip[def.id] and played - data.dripBase >= def.afterMin * 60 then
			data.drip[def.id] = true
			data.pearls += def.pearls
			Analytics.event(player, "DripUnlock", 1, { id = def.id })
			Remotes.event("Drip"):FireClient(player, def.id, def.name, def.blurb)
			-- a bouncing "!" marks the new place for a couple of minutes (client/VendorMarks)
			player:SetAttribute("DripNew", def.id)
			task.delay(120, function()
				if player.Parent and player:GetAttribute("DripNew") == def.id then
					player:SetAttribute("DripNew", nil)
				end
			end)
			DataService.changed(player)
			return -- one at a time
		end
	end
end

function DripService.init()
	DataService.Loaded:Connect(function(player)
		local data = DataService.get(player)
		if data and data.tutorial >= Config.TUTORIAL_DONE and data.dripBase < 0 then
			-- an existing player: everything is open, nothing is announced
			for _, def in Config.DRIP do
				data.drip[def.id] = true
			end
			data.dripBase = 0
		end
	end)
	task.spawn(function()
		while true do
			task.wait(3)
			for _, p in Players:GetPlayers() do
				if DataService.isLoaded(p) then
					check(p)
				end
			end
		end
	end)
end

return DripService
