--!strict
-- Badges for the big moments (the reference game awards one for the first boss).
-- Ids live in Config.BADGES; an id of 0 means "not created yet" and is skipped.
-- Analytics forwards its events here, so the hooks live in one place.

local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local Badges = {}

local given: { [Player]: { [string]: boolean } } = {}

function Badges.award(player: Player, key: string)
	local id = Config.BADGES[key]
	if not id or id == 0 then
		return
	end
	given[player] = given[player] or {}
	if given[player][key] then
		return
	end
	given[player][key] = true
	task.spawn(function()
		local ok, has = pcall(function()
			return BadgeService:UserHasBadgeAsync(player.UserId, id)
		end)
		if ok and not has then
			pcall(function()
				BadgeService:AwardBadge(player.UserId, id)
			end)
		end
	end)
end

-- Analytics event name (+ value) -> badge
function Badges.onEvent(player: Player, name: string, value: number, fields: { [string]: any }?)
	if name == "NewPlayer" or name == "ReturningPlayer" then
		Badges.award(player, "Welcome")
	elseif name == "Hatch" then
		Badges.award(player, "FirstHatch")
		if fields and (tonumber(fields.stars) or 0) >= 4 then
			Badges.award(player, "Legendary")
		end
	elseif name == "Fuse" then
		Badges.award(player, "FirstFuse")
		if fields and (tonumber(fields.stars) or 0) >= 4 then
			Badges.award(player, "Legendary")
		end
	elseif name == "StageCleared" then
		Badges.award(player, "FirstBoss")
	elseif name == "BestDepth" then
		if value >= 50 then
			Badges.award(player, "Depth50")
		end
		if value >= 100 then
			Badges.award(player, "Depth100")
		end
		if value >= Config.FINAL_DEPTH then
			Badges.award(player, "Maw")
		end
	end
end

Players.PlayerRemoving:Connect(function(player)
	given[player] = nil
end)

return Badges
