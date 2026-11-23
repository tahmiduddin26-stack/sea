--!strict
-- Admin controls. Members of the FLNK LTD group (Config.ADMIN_GROUP_ID) and the accounts in
-- Config.ADMIN_IDS, and ONLY in Roblox Studio: in a published server isAdmin is always false,
-- so none of this can ever run for a real player.
-- The client's Admin panel (client/AdminPanel) sends { cmd = "...", n = number? } through the
-- Action remote ("Admin" handler in ShopService).

local RunService = game:GetService("RunService")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Config)

local DataService = require(script.Parent.DataService)
local FarmService = require(script.Parent.FarmService)
local BattleService = require(script.Parent.BattleService)

local AdminService = {}

-- group membership is a web call, so it is looked up once per player and remembered
local inGroup: { [Player]: boolean } = {}

local function isGroupMember(player: Player): boolean
	local known = inGroup[player]
	if known ~= nil then
		return known
	end
	local ok, member = pcall(function()
		return player:IsInGroup(Config.ADMIN_GROUP_ID)
	end)
	if not ok then
		return false -- don't remember a failed lookup: the next check tries again
	end
	inGroup[player] = member == true
	return member == true
end

function AdminService.isAdmin(player: Player): boolean
	if not RunService:IsStudio() then
		return false
	end
	return table.find(Config.ADMIN_IDS, player.UserId) ~= nil or isGroupMember(player)
end

local function refresh(player: Player)
	FarmService.syncAll(player)
	FarmService.updateSign(player)
	DataService.changed(player)
end

-- A brand-new account: no monsters, 2,500 coins, tutorial at step 1
local function resetToNew(player: Player)
	BattleService.retreat(player)
	local s = DataService.session(player)
	if s then
		s.carrying = nil
		s.pedestalEggs = {}
		s.fighting = {}
		s.giftsClaimed = {}
	end
	player:SetAttribute("Carrying", nil)
	DataService.resetToNew(player)
	local data = DataService.get(player)
	refresh(player)
	require(game:GetService("ReplicatedStorage").Shared.Remotes).event("Tutorial"):FireClient(player, data.tutorial)
	if DataService.canSave(player) then
		DataService.save(player)
	end
end

local STARTERS = { "Splashfin", "Reefback", "Zapjelly", "Gloomeel" }

-- Runs one command. Returns (ok, message) for a toast.
function AdminService.run(player: Player, arg: any): (boolean, string?)
	if not AdminService.isAdmin(player) then
		return false, nil
	end
	if typeof(arg) ~= "table" or typeof(arg.cmd) ~= "string" then
		return false, nil
	end
	local data = DataService.get(player)
	if not data then
		return false, nil
	end
	local cmd = arg.cmd
	local n = if typeof(arg.n) == "number" then math.clamp(math.floor(arg.n), 0, 1e12) else 0
	if cmd == "ResetNew" then
		resetToNew(player)
		return true, "Fresh account: new-player tutorial from step 1"
	elseif cmd == "Coins" then
		data.coins += n
	elseif cmd == "SetCoins" then
		data.coins = n
	elseif cmd == "Pearls" then
		data.pearls += n
	elseif cmd == "BestDepth" then
		data.bestDepth = n
		BattleService.retreat(player)
	elseif cmd == "GoToDepth" then
		-- testing: the next FIGHT starts at depth n (best depth is raised to match, so it is allowed)
		local depth = math.clamp(n, 1, Config.FINAL_DEPTH)
		BattleService.retreat(player)
		data.bestDepth = math.max(data.bestDepth, depth - 1)
		data.resumeDepth = depth
		refresh(player)
		return true, "Press FIGHT: you start at depth " .. depth
	elseif cmd == "Lv1Team" then
		-- three Lv1 1-star monsters in your nests, tutorial done (so FIGHT and the HUD are on)
		data.tutorial = Config.TUTORIAL_DONE
		for i = 1, 3 do
			FarmService.devMonster(player, STARTERS[i], 1, 1)
		end
		refresh(player)
		return true, "Three Lv1 monsters added"
	elseif cmd == "Monster" then
		local lvl = math.clamp(n, 1, Config.MAX_LEVEL)
		FarmService.devMonster(player, STARTERS[math.random(#STARTERS)], lvl, 1)
		refresh(player)
		return true, "Lv" .. lvl .. " monster added"
	elseif cmd == "SkipTutorial" then
		data.tutorial = Config.TUTORIAL_DONE
	elseif cmd == "FinishTimers" then
		FarmService.finishAllTimers(player)
	elseif cmd == "Spells" then
		-- n random Common cards (to try Combine and the sets)
		for _ = 1, math.clamp(n, 1, 50) do
			local pool = {}
			for _, sp in Config.SPELLS do
				if sp.rarity == 1 then
					table.insert(pool, sp)
				end
			end
			local sp = pool[math.random(#pool)]
			data.spells[sp.id] = (tonumber(data.spells[sp.id]) or 0) + 1
			data.spellsFound[sp.id] = true
		end
	elseif cmd == "ShipTier" then
		data.shipTier = math.clamp(n, 0, #Config.SHIP_TIERS)
	elseif cmd == "Floor2" then
		data.floor = 2
	elseif cmd == "Floor3" then
		data.floor = 3
		FarmService.syncAbyssRod(player)
	elseif cmd == "Intro" then
		-- the client plays the intro as soon as it sees introSeen go false
		data.introSeen = false
		refresh(player)
		return true, "Playing the intro"
	elseif cmd == "DeepRod" then
		-- Deep Rod ready now: count the 20 minutes as played and clear the 10 minute cooldown
		data.playSeconds = math.max(data.playSeconds or 0, Config.DEEP_ROD.unlockMinutes * 60)
		data.deepRodAt = 0
		FarmService.syncDeepRod(player)
		refresh(player)
		return true, "Deep Rod unlocked and ready"
	elseif cmd == "AbyssRod" then
		-- Abyss Rod ready now: Floor 3, the 2 hours counted as played, no cooldown
		data.floor = math.max(data.floor or 1, 3)
		data.playSeconds = math.max(data.playSeconds or 0, Config.ABYSS_ROD.unlockMinutes * 60)
		data.abyssRodAt = 0
		FarmService.syncAbyssRod(player)
		FarmService.syncDeepRod(player)
		refresh(player)
		return true, "Abyss Rod unlocked and ready"
	else
		return false, "Unknown admin command"
	end
	refresh(player)
	return true, "Done: " .. cmd
end

-- Decide whether this player gets the admin panel (the "Admin" attribute). The group check is a
-- web call that can fail or time out; a failed lookup used to leave a group member without the
-- panel for the whole session, so it now retries in the background until Roblox answers.
local GROUP_RETRIES = { 2, 4, 8, 15, 30 } -- seconds between attempts after a failed lookup
local function grantIfAdmin(player: Player)
	if not RunService:IsStudio() then
		return
	end
	if table.find(Config.ADMIN_IDS, player.UserId) ~= nil then
		player:SetAttribute("Admin", true)
		return
	end
	if player.UserId <= 0 then
		-- Studio's "Start Server + Players" test gives players made-up negative ids: not in the
		-- group, and not in ADMIN_IDS
		print("[Admin] no admin panel for", player.Name, "(Studio test player, id " .. player.UserId .. ")")
		return
	end
	for attempt = 0, #GROUP_RETRIES do
		if attempt > 0 then
			task.wait(GROUP_RETRIES[attempt])
		end
		if not player.Parent then
			return
		end
		local ok, member = pcall(function()
			return player:IsInGroup(Config.ADMIN_GROUP_ID)
		end)
		if ok then
			inGroup[player] = member == true
			if member then
				player:SetAttribute("Admin", true)
			else
				print("[Admin] no admin panel for", player.Name, "(not in the FLNK LTD group or Config.ADMIN_IDS)")
			end
			return
		end
		warn("[Admin] group check failed for", player.Name, "(try " .. (attempt + 1) .. "):", member)
	end
	warn("[Admin] gave up checking the group for", player.Name, "- rejoin to try again")
end

function AdminService.init()
	DataService.Loaded:Connect(function(player)
		task.spawn(grantIfAdmin, player)
	end)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		inGroup[player] = nil
	end)
end

return AdminService
