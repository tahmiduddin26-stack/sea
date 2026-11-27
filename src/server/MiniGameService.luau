--!strict
-- The server owns private rounds and validates every pickup against the player's character.
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Cove = require(Shared.CrabCove)
local Remotes = require(Shared.Remotes)
local Stats = require(Shared.Stats)
local Format = require(Shared.Format)
local DataService = require(script.Parent.DataService)
local FarmService = require(script.Parent.FarmService)
local Analytics = require(script.Parent.Analytics)
local MiniGameService = {}
local rounds: { [Player]: any } = {}
local rng = Random.new()
local eggSites: { Vector3 } = {}
local scenery = RaycastParams.new()
scenery.FilterType = Enum.RaycastFilterType.Include
scenery.RespectCanCollide = true
scenery.IgnoreWater = true

local function groundAt(pos: Vector3): RaycastResult?
	return workspace:Raycast(Vector3.new(pos.X, 18, pos.Z), Vector3.new(0, -18, 0), scenery)
end

local function placeEgg(run: any, index: number): Vector3?
	local previous = run.eggs[index]
	local start = run.random:NextInteger(1, #eggSites)
	local fallback: Vector3? = nil
	for offset = 0, #eggSites - 1 do
		local site = eggSites[(start + offset - 1) % #eggSites + 1]
		local available = (site - run.keeper).Magnitude >= Cove.eggMinDistance
			and (not previous or (previous.pos - site).Magnitude >= Cove.eggSpread)
			and (not previous or (previous.spawn - site).Magnitude >= Cove.eggSpread)
		for other, egg in run.eggs do
			if other ~= index and not egg.delivered and not egg.held and (egg.pos - site).Magnitude < 7 then
				available = false
				break
			end
		end
		if available then
			if not run.usedSites[site] then
				run.usedSites[site] = true
				return site
			end
			fallback = fallback or site
		end
	end
	return fallback
end

local function send(player: Player, run: any)
	Remotes.event("MiniGame"):FireClient(player, "state", {
		eggs = run.eggs,
		crabs = run.crabs,
		carried = run.carried,
		score = run.score,
		delivered = run.delivered,
		boostEarned = run.boostEarned,
		boostUntil = run.boostUntil,
		message = run.message,
		lives = run.lives,
		guide = run.guide,
	})
end

local function finish(player: Player, completed: boolean, gameOver: boolean?)
	local run = rounds[player]
	if not run then
		return
	end
	rounds[player] = nil
	player:SetAttribute("InCrabCove", nil)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = run.speed
	end
	for part, group in run.groups do
		if part.Parent then
			part.CollisionGroup = group
		end
	end
	if char and hum and hum.Health > 0 then
		char:PivotTo(run.returnCf)
	end
	local data = DataService.get(player)
	if data and run.guide then
		data.coveSeen = true -- they have played once: the big guide stays off from now on
	end
	local reward = ""
	if (completed or gameOver) and data and run.score > 0 then
		local cfg = Config.MINIGAMES.cove
		data.miniAt = data.miniAt or {}
		if os.time() >= (data.miniAt.cove or 0) + cfg.cooldown then
			-- full pay for the first fullPlays plays each hour, then a reduced share (still worth replaying)
			local hour = os.time() // 3600
			if data.miniAt.coveHour ~= hour then
				data.miniAt.coveHour = hour
				data.miniAt.coveN = 0
			end
			data.miniAt.coveN = (data.miniAt.coveN or 0) + 1
			local tired = data.miniAt.coveN > (cfg.fullPlays or 3)
			local quality = math.clamp(run.score / 24, 0.25, 1) * (if tired then cfg.tiredShare or 0.4 else 1)
			local coins = Stats.miniGameCoins("cove", data.bestDepth, quality)
			local pearls = math.floor(cfg.pearls * quality + 0.5)
			data.coins += coins
			data.pearls += pearls
			data.miniAt.cove = os.time()
			Analytics.tag(player, "Gameplay", "MiniGame_cove")
			reward = "+" .. Format.abbrev(coins) .. " coins · +" .. pearls .. " pearls" .. (if tired then " (reduced: 3 full plays an hour)" else "")
		else
			reward = "Coin rewards recharge in " .. Format.time(data.miniAt.cove + cfg.cooldown - os.time())
		end
		data.coveBest = math.max(data.coveBest or 0, run.score)
		DataService.changed(player)
		Analytics.event(player, "MiniGame", run.score, { game = "cove" })
		require(script.Parent.MissionService).record(player, "cove", 1)
	end
	Remotes.event("MiniGame"):FireClient(player, "ended", {
		score = run.score,
		delivered = run.delivered,
		boostEarned = run.boostEarned,
		boostUntil = run.boostUntil,
		reward = reward,
		best = if data then data.coveBest or 0 else 0,
		completed = completed,
		gameOver = gameOver == true,
	})
end

function MiniGameService.start(player: Player, gameId: any): (boolean, string?)
	local data, session = DataService.get(player), DataService.session(player)
	if gameId ~= "cove" or not data or not session or #eggSites < Cove.eggCount then
		return false, "Game unavailable"
	end
	if rounds[player] then
		return false, "You are already playing!"
	end
	if FarmService.inTutorial(player) then
		return false, "Finish the tutorial first!"
	end
	local Drip = require(script.Parent.DripService)
	if not Drip.open(player, "cove") then
		return false, Drip.waitText(player, "cove")
	end
	if session.inBattle then
		return false, "Wait for the battle to end"
	end
	if session.carrying then
		return false, "Put your egg in a nest first!"
	end
	if player:GetAttribute("InCannon") then
		return false, "Leave your cannon first!"
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local world = workspace:FindFirstChild("World")
	local prompt = world and world:FindFirstChild("CardsPrompt", true)
	local host = prompt and prompt.Parent
	if not root or not hum or hum.Health <= 0 or not host or not host:IsA("BasePart") then
		return false, "Walk up to the Crab Cove host"
	end
	if (root.Position - host.Position).Magnitude > 24 then
		return false, "Walk up to the Crab Cove host"
	end
	local now = workspace:GetServerTimeNow()
	local returnCf = Cove.keeperCFrame(host)
	local run = {
		random = Random.new(rng:NextInteger(1, 1000000)),
		started = now,
		last = now,
		lastPos = root.Position,
		keeper = returnCf.Position,
		returnCf = returnCf,
		speed = hum.WalkSpeed,
		eggs = {},
		crabs = {},
		usedSites = {},
		carried = {},
		score = 0,
		delivered = 0,
		boostEarned = false,
		boostUntil = data.coveHatchUntil or 0,
		hitUntil = 0,
		lives = Cove.lives,
		-- the big guide (banner, line, pillar) shows only on your very first round, then it hides
		guide = not data.coveSeen,
		groups = {},
		message = "Eggs are scattered around the island. Follow the egg marker!",
	}
	for i = 1, Cove.eggCount do
		local site = placeEgg(run, i)
		if not site then
			return false, "Could not place the rescue eggs"
		end
		run.eggs[i] = { pos = site, spawn = site, generation = 0, held = false, golden = i % 6 == 0 }
	end
	-- a crab guards some of the eggs (every Cove.eggCount / Cove.crabCount-th one, spread over the island)
	for k = 1, Cove.crabCount do
		local egg = run.eggs[math.clamp(math.floor((k - 0.5) * Cove.eggCount / Cove.crabCount) + 1, 1, Cove.eggCount)]
		local home = egg.pos - Vector3.new(0, 1.2, 0)
		table.insert(run.crabs, { pos = home, home = home, direction = Vector3.zAxis, chasing = false })
	end
	for _, part in char:GetDescendants() do
		if part:IsA("BasePart") then
			run.groups[part] = part.CollisionGroup
			part.CollisionGroup = "CrabCovePlayers"
		end
	end
	rounds[player] = run
	player:SetAttribute("InCrabCove", true)
	return true, tostring(now)
end

function MiniGameService.finish(player: Player, _arg: any): (boolean, string?)
	finish(player, false)
	return true, nil
end

local function drop(run: any, now: number, position: Vector3?)
	for slot, index in run.carried do
		local egg = run.eggs[index]
		egg.held = false
		local ground = if position then groundAt(position + Vector3.new((slot - 2) * 3, 0, 0)) else nil
		egg.pos = if ground
				and math.abs(ground.Position.Y - position.Y) < 6
				and Cove.inPlayArea(ground.Position)
				and not Cove.atKeeper(ground.Position, run.keeper)
			then ground.Position + Vector3.new(0, 1.7, 0)
			else egg.spawn
	end
	run.carried = {}
	run.hitUntil = now + 2
end

-- returns: did the snap hit you, did the crab snap at all this step (so the client can play the snap
-- even when it misses)
local function crabStep(
	crab: any,
	index: number,
	playerPos: Vector3,
	keeper: Vector3,
	elapsed: number,
	dt: number
): (boolean, boolean)
	local delta = playerPos - crab.pos
	local towardPlayer = Vector3.new(delta.X, 0, delta.Z)
	local safe = Cove.atKeeper(playerPos, keeper)
	if crab.strikeAt then
		if elapsed < crab.strikeAt then
			return false, false
		end
		crab.strikeAt = nil
		crab.recoverUntil = elapsed + 1.1
		local forward = towardPlayer:Dot(crab.direction)
		local sideways = towardPlayer - crab.direction * forward
		local hit = not safe
			and forward >= -0.3
			and forward <= 3.6
			and sideways.Magnitude <= 1.6
			and math.abs(delta.Y - 2.4) <= 1.9
			and not workspace:Raycast(crab.pos + Vector3.yAxis, delta - Vector3.yAxis, scenery)
		return hit, true
	end
	if elapsed < (crab.recoverUntil or 0) then
		return false, false
	end
	crab.chasing = not safe
		and towardPlayer.Magnitude < 23
		and math.abs(delta.Y) < 6
		and (playerPos - crab.home).Magnitude < 32
	if
		crab.chasing
		and towardPlayer.Magnitude <= 4.4
		and math.abs(delta.Y - 2.4) <= 1.9
		and not workspace:Raycast(crab.pos + Vector3.yAxis, delta - Vector3.yAxis, scenery)
	then
		if towardPlayer.Magnitude > 0.05 then
			crab.direction = towardPlayer.Unit
		end
		crab.strikeAt = elapsed + Cove.crabWarning
		return false, false
	end
	local patrol = crab.home + Vector3.new(math.sin(elapsed * 0.7 + index) * 7, 0, math.cos(elapsed * 0.7 + index) * 7)
	local goal = if crab.chasing then playerPos else patrol
	local travel = Vector3.new(goal.X - crab.pos.X, 0, goal.Z - crab.pos.Z)
	if travel.Magnitude > 0.1 then
		local distance = math.min(travel.Magnitude, dt * (if crab.chasing then 12 else 6))
		for _, angle in { 0, 55, -55, 100, -100 } do
			local direction = CFrame.Angles(0, math.rad(angle), 0):VectorToWorldSpace(travel.Unit)
			local advance = direction * distance
			local spot = crab.pos + advance
			local ground = groundAt(spot)
			if
				ground
				and Cove.inPlayArea(ground.Position)
				and not Cove.atKeeper(ground.Position, keeper)
				and math.abs(ground.Position.Y + 0.5 - crab.pos.Y) < 1.8
				and not workspace:Raycast(crab.pos + Vector3.yAxis, advance, scenery)
			then
				crab.pos = ground.Position + Vector3.yAxis * 0.5
				crab.direction = direction
				break
			end
		end
	end
	return false, false
end

local function step(player: Player, run: any, now: number)
	local dt = math.clamp(now - run.last, 0, 0.5)
	run.last = now
	local elapsed = now - run.started
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local data = DataService.get(player)
	if not root or not hum or hum.Health <= 0 or not data then
		finish(player, false)
		return
	end
	if elapsed >= Cove.duration then
		finish(player, true)
		return
	end
	-- just got snapped: you are held still while the hit plays (client), then sent back next to the
	-- Cove Keeper, or the round ends if that was your last heart
	if run.stunUntil then
		if now < run.stunUntil then
			hum.WalkSpeed = 0
			root.AssemblyLinearVelocity = Vector3.zero
			send(player, run)
			return
		end
		run.stunUntil = nil
		if run.lives <= 0 then
			finish(player, false, true)
			return
		end
		run.lastPos = run.keeper
		char:PivotTo(run.returnCf)
		root.AssemblyLinearVelocity = Vector3.zero
	end
	local pos = root.Position

	if not Cove.inPlayArea(pos) or hum:GetState() == Enum.HumanoidStateType.Swimming then
		drop(run, now)
		char:PivotTo(run.returnCf)
		run.lastPos = run.keeper
		send(player, run)
		return
	end
	local distance = (pos - run.lastPos).Magnitude
	local valid = distance <= 36 * math.max(dt, 0.1) + 3
	if not valid then
		char:PivotTo(CFrame.new(run.lastPos))
		send(player, run)
		return
	end
	run.lastPos = pos
	local crabHit = false
	local snaps = {}
	local vulnerable = now >= run.hitUntil
	for index, crab in run.crabs do
		local hit, struck = crabStep(crab, index, pos, run.keeper, elapsed, dt)
		if struck then
			table.insert(snaps, { crab = index, hit = hit and vulnerable })
		end
		if hit then
			crabHit = true
		end
	end
	-- every snap is told to the client at once (hit or miss) so it can play the snap straight away
	for _, s in snaps do
		Remotes.event("MiniGame"):FireClient(player, "snap", s)
	end
	if crabHit and vulnerable then
		drop(run, now, pos)
		run.lives -= 1
		-- held still while the hit plays; the teleport to the keeper (or the game over) comes after
		run.stunUntil = now + Cove.stun
		run.hitUntil = now + Cove.stun + Cove.safeTime
		run.message = if run.lives > 0 then "A crab got you! You lost a heart." else "A crab got you! Out of hearts!"
		hum.WalkSpeed = 0
		root.AssemblyLinearVelocity = Vector3.zero
	else
		if Cove.atKeeper(pos, run.keeper) and #run.carried > 0 then
			for _, index in run.carried do
				local egg = run.eggs[index]
				run.score += if egg.golden then 3 else 1
				run.delivered += 1
				egg.generation += 1
				egg.golden = (index + egg.generation) % 6 == 0
				local site = placeEgg(run, index)
				egg.pos = site or egg.pos
				egg.spawn = egg.pos
				egg.delivered = site == nil
				egg.held = false
			end
			run.carried = {}
			if not run.boostEarned and run.delivered >= Cove.hatchRewardEggs then
				run.boostUntil = FarmService.grantCoveHatchBoost(player)
				run.boostEarned = true
				run.message = "Reward earned! " .. Cove.hatchRewardText .. "."
			else
				run.message = "Eggs delivered! Follow the marker to find more around the island."
			end
		end
		for index, egg in run.eggs do
			if
				not egg.held
				and not egg.delivered
				and #run.carried < 3
				and Vector2.new(pos.X - egg.pos.X, pos.Z - egg.pos.Z).Magnitude <= Cove.pickupRadius
				and math.abs(pos.Y - egg.pos.Y) < 5
			then
				egg.held = true
				table.insert(run.carried, index)
				run.message = "Egg collected! Bring it back to the Cove Keeper."
			end
		end
	end
	hum.WalkSpeed = 24 - #run.carried * 2
	send(player, run)
end

function MiniGameService.init()
	local world = workspace:WaitForChild("World")
	scenery.FilterDescendantsInstances = { world:WaitForChild("Harbour"), workspace.Terrain }
	-- Choose open grass near the waterfront and along the paths, clear of buildings.
	local siteStep = 12
	local siteEdge = math.floor((Config.HUB_RADIUS * 0.85 - 4) / siteStep) * siteStep
	for x = -siteEdge, siteEdge, siteStep do
		for z = -siteEdge, siteEdge, siteStep do
			if math.max(math.abs(x), math.abs(z)) >= 36 then
				local spot = Vector3.new(x, 0, z)
				local ground = groundAt(spot)
				if
					ground
					and ground.Instance.Material == Enum.Material.Grass
					and ground.Position.Y > 4.9
					and ground.Position.Y < 5.2
				then
					table.insert(eggSites, ground.Position + Vector3.yAxis * 1.7)
				end
			end
		end
	end
	local physics = game:GetService("PhysicsService")
	if not physics:IsCollisionGroupRegistered("CrabCovePlayers") then
		physics:RegisterCollisionGroup("CrabCovePlayers")
	end
	physics:CollisionGroupSetCollidable("CrabCovePlayers", "CrabCovePlayers", false)
	Players.PlayerRemoving:Connect(function(player)
		rounds[player] = nil
	end)
	task.spawn(function()
		while script.Parent do
			task.wait(Cove.tick)
			local now = workspace:GetServerTimeNow()
			for player, run in rounds do
				local ok, err = pcall(step, player, run, now)
				if not ok then
					warn("[Crab Cove]", err)
					finish(player, false)
				end
			end
		end
	end)
end
return MiniGameService
