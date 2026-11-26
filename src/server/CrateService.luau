--!strict
-- Live crates + the Cannon Gallery. Every Config.LIVE_CRATES.every seconds the server drops
-- LIVE_CRATES.count crates in the sea off random ships' sides (workspace.LiveCrates, the same crates
-- for everyone). Players get into a gallery cannon on THEIR OWN ship (one gun on each rail) and shoot
-- them; barrels and golden chests take several hits, and whoever lands the last hit gets the reward
-- (LIVE_CRATES.minutes of battle coins at their best depth x the kind's pay, plus pearls).
--
-- Anti-cheat: the client only sends its aim (yaw, pitch) and which crate it thinks it hit. The server
-- re-flies the same arc (shared/Ballistics) from the cannon it knows the player sits in, enforces the
-- reload, and only counts a hit if that arc really passes the crate.
--
-- Remote "Crates" (S -> all): ("shot", userId, p0, v0, ship, side, yaw, pitch) | ("hit", id, hp)
--   | ("break", id, playerName, kind) | ("drop", count) | ("sink")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Stats = require(Shared.Stats)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Ballistics = require(Shared.Ballistics)

local DataService = require(script.Parent.DataService)
local FarmService = require(script.Parent.FarmService)
local Analytics = require(script.Parent.Analytics)
local WorldBuilder = require(script.Parent.WorldBuilder)

local CrateService = {}

local L = Config.LIVE_CRATES
local rng = Random.new()

type Seat = { ship: number, side: string, base: CFrame, lastShot: number }
local seats: { [Player]: Seat } = {}
local occupied: { [string]: Player } = {} -- "ship:side" -> player in it

local folder = Instance.new("Folder")
folder.Name = "LiveCrates"
folder.Parent = workspace

local nextId = 0

local function kindOf(id: string): any
	for _, k in L.kinds do
		if k.id == id then
			return k
		end
	end
	return L.kinds[1]
end

local function rollKind(): any
	local total = 0
	for _, k in L.kinds do
		total += k.weight
	end
	local r = rng:NextNumber() * total
	for _, k in L.kinds do
		r -= k.weight
		if r <= 0 then
			return k
		end
	end
	return L.kinds[1]
end

-- a spot in open water off a random ship's side (never in a battle arena or on a hull)
local function spot(): Vector3?
	local ships = WorldBuilder.ships
	if #ships == 0 then
		return nil
	end
	for _ = 1, 40 do
		local ship = ships[rng:NextInteger(1, #ships)]
		local sx = if rng:NextNumber() < 0.5 then -1 else 1
		local out = Config.SHIP_WIDTH / 2 + rng:NextNumber(L.outMin, L.outMax)
		local p = (ship.cf * CFrame.new(sx * out, 0, rng:NextNumber(-L.alongMax, L.alongMax))).Position
		local ok = true
		for _, s in ships do
			local a = s.arenaCf.Position
			if Vector2.new(p.X - a.X, p.Z - a.Z).Magnitude < Config.ARENA_RADIUS + 12 then
				ok = false
			end
			local lp = s.cf:PointToObjectSpace(p)
			if math.abs(lp.X) < Config.SHIP_WIDTH / 2 + 20 and math.abs(lp.Z) < Config.SHIP_LENGTH / 2 + 20 then
				ok = false
			end
		end
		for _, c in folder:GetChildren() do
			if ((c :: BasePart).Position - p).Magnitude < 25 then
				ok = false
			end
		end
		if ok then
			return Vector3.new(p.X, Config.SEA_LEVEL + 1, p.Z)
		end
	end
	return nil
end

local function drop()
	folder:ClearAllChildren()
	Remotes.event("Crates"):FireAllClients("sink")
	local made = 0
	for _ = 1, L.count do
		local pos = spot()
		if pos then
			local k = rollKind()
			nextId += 1
			local p = Instance.new("Part")
			p.Name = "Crate" .. nextId
			p.Anchored = true
			p.CanCollide = false
			p.CanTouch = false
			p.Size = k.size
			p.Color = k.color
			p.Material = if k.id == "Gold" then Enum.Material.Neon elseif k.id == "Barrel" then Enum.Material.Wood else Enum.Material.WoodPlanks
			p.CFrame = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0)
			p:SetAttribute("Id", nextId)
			p:SetAttribute("Kind", k.id)
			p:SetAttribute("Hp", k.hp)
			p:SetAttribute("MaxHp", k.hp)
			p.Parent = folder
			made += 1
		end
	end
	Remotes.event("Crates"):FireAllClients("drop", made)
end

local function crateById(id: any): BasePart?
	if typeof(id) ~= "number" then
		return nil
	end
	for _, c in folder:GetChildren() do
		if c:GetAttribute("Id") == id then
			return c :: BasePart
		end
	end
	return nil
end

local function reward(player: Player, k: any)
	local data = DataService.get(player)
	if not data then
		return
	end
	local coins = math.floor(Stats.coinsPerMinute(data.bestDepth or 0) * L.minutes * k.pay)
	data.coins += coins
	data.pearls += k.pearls
	DataService.changed(player)
	Analytics.tag(player, "Gameplay", "LiveCrate_" .. k.id)
	local text = k.name .. "! +" .. Format.abbrev(coins) .. " coins" .. (if k.pearls > 0 then " and +" .. k.pearls .. " pearls" else "")
	Remotes.event("Toast"):FireClient(player, text, Color3.fromRGB(255, 205, 60))
end

-- Cannonballs: LIVE_CRATES.ammo per player, refilled to full LIVE_CRATES.ammoEvery seconds after the
-- first shot from a full stack (saved in the profile). Shown through player attributes.
local function ammo(player: Player): number
	local data = DataService.get(player)
	if not data then
		return 0
	end
	if data.cannonAmmo == nil or (data.cannonRefillAt and os.time() >= data.cannonRefillAt) then
		data.cannonAmmo = L.ammo
		data.cannonRefillAt = nil
	end
	player:SetAttribute("CannonAmmo", data.cannonAmmo)
	player:SetAttribute("CannonRefillAt", data.cannonRefillAt)
	return data.cannonAmmo
end

local function useAmmo(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	data.cannonAmmo = math.max(0, (data.cannonAmmo or L.ammo) - 1)
	if not data.cannonRefillAt then
		data.cannonRefillAt = os.time() + L.ammoEvery
	end
	player:SetAttribute("CannonAmmo", data.cannonAmmo)
	player:SetAttribute("CannonRefillAt", data.cannonRefillAt)
end

---------------------------------------------------------------------------
-- Actions (ShopService routes them)
---------------------------------------------------------------------------
local function leave(player: Player)
	local s = seats[player]
	if not s then
		return
	end
	occupied[s.ship .. ":" .. s.side] = nil
	seats[player] = nil
	player:SetAttribute("InCannon", nil)
end

function CrateService.enter(player: Player, side: any): (boolean, string?)
	if player:GetAttribute("InCrabCove") then return false, "Leave Crab Cove first!" end
	local sess = DataService.session(player)
	if typeof(side) ~= "string" or not Config.CANNON_GAME_POS[side] or not sess then
		return false, nil
	end
	if FarmService.inTutorial(player) then
		return false, "Finish the tutorial first!"
	end
	if sess.inBattle then
		return false, "Wait for the battle to end"
	end
	local idx = sess.shipIndex
	local ship = if idx then WorldBuilder.ships[idx] else nil
	if not ship then
		return false, "You need a ship first"
	end
	local base = Ballistics.base(ship.cf, side)
	local root = if player.Character then player.Character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if not root or (root.Position - base.Position).Magnitude > 20 then
		return false, "Walk up to your cannon"
	end
	local key = idx .. ":" .. side
	if occupied[key] and occupied[key] ~= player then
		return false, "Someone is using this cannon"
	end
	leave(player)
	occupied[key] = player
	seats[player] = { ship = idx, side = side, base = base, lastShot = 0 }
	ammo(player) -- refresh the counter (and refill if the 10 minutes are up)
	player:SetAttribute("InCannon", side)
	return true, nil
end

function CrateService.leave(player: Player): (boolean, string?)
	leave(player)
	return true, nil
end

-- arg = { yaw, pitch, crate? }: the shot always flies (everyone sees it); it scores only if the
-- server's own arc really passes the crate
function CrateService.fire(player: Player, arg: any): (boolean, string?)
	local s = seats[player]
	if not s or typeof(arg) ~= "table" or typeof(arg.yaw) ~= "number" or typeof(arg.pitch) ~= "number" then
		return false, nil
	end
	local now = os.clock()
	if now - s.lastShot < L.reload * 0.8 then
		return false, nil
	end
	if ammo(player) <= 0 then
		local data = DataService.get(player)
		local left = if data and data.cannonRefillAt then data.cannonRefillAt - os.time() else 0
		return false, "Out of cannonballs! More in " .. Format.time(left)
	end
	s.lastShot = now
	useAmmo(player)
	local yaw, pitch = Ballistics.clamp(arg.yaw, arg.pitch)
	local p0, v0 = Ballistics.launch(s.base, yaw, pitch)
	Remotes.event("Crates"):FireAllClients("shot", player.UserId, p0, v0, s.ship, s.side, yaw, pitch)
	local crate = crateById(arg.crate)
	if not crate then
		return true, nil
	end
	local hp = (crate:GetAttribute("Hp") :: number?) or 0
	if hp <= 0 then
		return true, nil
	end
	local k = kindOf(crate:GetAttribute("Kind") :: string)
	local radius = math.max(k.size.X, k.size.Y, k.size.Z) / 2 + L.hitPad
	local miss, flight = Ballistics.closest(p0, v0, crate.Position)
	if miss > radius then
		return true, nil
	end
	-- the hit lands when the ball gets there (not the moment it is fired: crates used to burst
	-- while the ball was still in the air, as if they broke on their own)
	local id = crate:GetAttribute("Id")
	local name = player.DisplayName
	task.delay(flight, function()
		local hp2 = (crate:GetAttribute("Hp") :: number?) or 0
		if not crate.Parent or hp2 <= 0 then
			return -- someone else finished it first, or a new drop replaced it
		end
		hp2 -= 1
		crate:SetAttribute("Hp", hp2)
		if hp2 > 0 then
			Remotes.event("Crates"):FireAllClients("hit", id, hp2)
			return
		end
		Remotes.event("Crates"):FireAllClients("break", id, name, k.id)
		if player.Parent then
			reward(player, k)
		end
		task.delay(1, function()
			crate:Destroy()
		end)
	end)
	return true, "hit"
end

-- admin / Studio: drop a fresh set now
function CrateService.dropNow()
	drop()
end

function CrateService.init()
	local function watch(p: Player)
		p.CharacterRemoving:Connect(function()
			leave(p)
		end)
	end
	Players.PlayerRemoving:Connect(leave)
	Players.PlayerAdded:Connect(watch)
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	task.spawn(function()
		local nextAt = os.time() + L.firstDrop
		while true do
			workspace:SetAttribute("CrateDropAt", nextAt)
			while os.time() < nextAt do
				task.wait(1)
			end
			drop()
			nextAt = os.time() + L.every
		end
	end)
end

return CrateService
