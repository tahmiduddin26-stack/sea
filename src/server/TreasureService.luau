--!strict
-- Treasure dig (retention plan Phase 3, item 18): every Config.TREASURE.every seconds, a few red
-- "X marks the spot" appear on the harbour island's sand. Walk up and hold the prompt to dig: coins,
-- pearls, a spell card or (rarely) an egg. First come, first served, so kids race round the island.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Stats = require(Shared.Stats)

local DataService = require(script.Parent.DataService)
local ExtrasService = require(script.Parent.ExtrasService)
local Analytics = require(script.Parent.Analytics)

local TreasureService = {}

local rng = Random.new()
local folder: Folder
local T = Config.TREASURE

local SAND = { [Enum.Material.Sand] = true, [Enum.Material.Grass] = true, [Enum.Material.Ground] = true, [Enum.Material.LeafyGrass] = true, [Enum.Material.Slate] = true }

-- A random open spot on the island. Its ground is plain grass/sand parts straight inside World.Harbour;
-- the first thing a ray from the sky hits must be one of those (so never a roof, a stall, a palm or a dock).
local function findSpot(taken: { Vector3 }): Vector3?
	local harbour = workspace:FindFirstChild("World") and workspace.World:FindFirstChild("Harbour")
	if not harbour then
		return nil
	end
	local blockers = RaycastParams.new()
	blockers.FilterType = Enum.RaycastFilterType.Exclude
	local skip: { Instance } = { folder }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(skip, p.Character)
		end
	end
	blockers.FilterDescendantsInstances = skip
	for _ = 1, 80 do
		local a = rng:NextNumber() * math.pi * 2
		local r = rng:NextNumber(0.25, 0.85) * Config.HUB_RADIUS
		local x, z = math.cos(a) * r, math.sin(a) * r
		local origin = Vector3.new(x, Config.SEA_LEVEL + 120, z)
		local hit = workspace:Raycast(origin, Vector3.new(0, -200, 0), blockers)
		if hit and hit.Instance.Parent == harbour and SAND[hit.Material] and hit.Position.Y > Config.SEA_LEVEL + 0.5 then
			local far = true
			for _, p in taken do
				if (p - hit.Position).Magnitude < 30 then
					far = false
				end
			end
			if far then
				return hit.Position
			end
		end
	end
	return nil
end

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

local function pickPrize(player: Player): string
	local data = DataService.get(player)
	if not data then
		return ""
	end
	local roll = rng:NextNumber()
	if roll < T.eggChance then
		if ExtrasService.giveRandomEgg(player, nil, 0, 1) then
			Remotes.event("Announce"):FireAllClients(player.DisplayName .. " dug up a MONSTER EGG!", Color3.fromRGB(255, 205, 60))
			return "a MONSTER EGG!"
		end
	end
	if roll < T.eggChance + T.spellChance then
		local sp = ExtrasService.giveSpell(player, "miniboss")
		if sp then
			DataService.changed(player)
			return "a " .. sp.name .. " spell card!"
		end
	end
	if roll < T.eggChance + T.spellChance + T.pearlChance then
		local n = rng:NextInteger(T.pearls[1], T.pearls[2])
		data.pearls += n
		DataService.changed(player)
		return n .. " pearls!"
	end
	local coins = math.max(1, math.floor(Stats.coinsPerMinute(data.bestDepth) * T.coinMinutes * rng:NextNumber(0.7, 1.3)))
	data.coins += coins
	DataService.changed(player)
	return Format.abbrev(coins) .. " coins!"
end

local function dig(player: Player, mark: Model)
	if mark:GetAttribute("Dug") then
		return
	end
	local Drip = require(script.Parent.DripService)
	if not Drip.open(player, "dig") then
		Remotes.event("Toast"):FireClient(player, Drip.waitText(player, "dig"), Color3.fromRGB(255, 205, 60))
		return
	end
	mark:SetAttribute("Dug", true)
	local prize = pickPrize(player)
	Analytics.event(player, "TreasureDig", 1, { prize = prize })
	require(script.Parent.MissionService).record(player, "dig", 1)
	Remotes.event("Toast"):FireClient(player, "You dug up " .. prize, Color3.fromRGB(255, 205, 60))
	-- the X pops: a chest jumps out of the sand, then everything sinks away
	local anchor = mark.PrimaryPart :: BasePart
	local chest = part({ Name = "Chest", Size = Vector3.new(3, 2.2, 2.2), Color = Color3.fromRGB(150, 95, 45), Material = Enum.Material.Wood, CFrame = anchor.CFrame * CFrame.new(0, -1, 0), Parent = mark })
	part({ Name = "Lid", Size = Vector3.new(3.1, 0.5, 2.3), Color = Color3.fromRGB(255, 205, 60), Material = Enum.Material.Metal, CFrame = chest.CFrame * CFrame.new(0, 1.3, 0), Parent = chest })
	TweenService:Create(chest, TweenInfo.new(0.4, Enum.EasingStyle.Back), { CFrame = anchor.CFrame * CFrame.new(0, 2, 0) * CFrame.Angles(0, math.rad(25), 0) }):Play()
	local prompt = anchor:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt:Destroy()
	end
	local tag = anchor:FindFirstChildOfClass("BillboardGui")
	if tag then
		tag:Destroy()
	end
	task.delay(2.5, function()
		mark:Destroy()
	end)
end

local function spawnMarks()
	folder:ClearAllChildren()
	local taken = {}
	for i = 1, T.count do
		local pos = findSpot(taken)
		if pos then
			table.insert(taken, pos)
			local mark = Instance.new("Model")
			mark.Name = "TreasureX" .. i
			local yaw = rng:NextNumber() * math.pi
			local base = CFrame.new(pos + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, yaw, 0)
			local anchor = part({ Name = "Anchor", Size = Vector3.new(1, 1, 1), Transparency = 1, CFrame = base * CFrame.new(0, 1.5, 0), Parent = mark })
			mark.PrimaryPart = anchor
			local red = Color3.fromRGB(215, 45, 40)
			part({ Name = "Bar1", Size = Vector3.new(7, 0.25, 1.3), Color = red, CFrame = base * CFrame.Angles(0, math.rad(45), 0), Parent = mark })
			part({ Name = "Bar2", Size = Vector3.new(7, 0.25, 1.3), Color = red, CFrame = base * CFrame.Angles(0, math.rad(-45), 0), Parent = mark })
			-- a little sand mound
			part({ Name = "Mound", Shape = Enum.PartType.Ball, Size = Vector3.new(5, 1.4, 5), Color = Color3.fromRGB(225, 200, 140), Material = Enum.Material.Sand, CFrame = base * CFrame.new(0, -0.35, 0), Parent = mark })
			local pp = Instance.new("ProximityPrompt")
			pp.Name = "DigPrompt"
			pp.ActionText = "Dig"
			pp.ObjectText = "Treasure"
			pp.HoldDuration = T.hold
			pp.MaxActivationDistance = 10
			pp.RequiresLineOfSight = false
			pp.Parent = anchor
			pp.Triggered:Connect(function(who)
				dig(who, mark)
			end)
			-- a floating "X" you can spot from across the island
			local gui = Instance.new("BillboardGui")
			gui.Size = UDim2.fromOffset(60, 60)
			gui.StudsOffset = Vector3.new(0, 5, 0)
			gui.MaxDistance = 140
			gui.LightInfluence = 0
			gui.AlwaysOnTop = false
			local l = Instance.new("TextLabel")
			l.BackgroundTransparency = 1
			l.Size = UDim2.fromScale(1, 1)
			l.Text = "X"
			l.TextScaled = true
			l.Font = Enum.Font.FredokaOne
			l.TextColor3 = red
			local st = Instance.new("UIStroke")
			st.Thickness = 3
			st.Color = Color3.new(1, 1, 1)
			st.Parent = l
			l.Parent = gui
			gui.Parent = anchor
			mark.Parent = folder
		end
	end
	if #folder:GetChildren() > 0 then
		Remotes.event("Announce"):FireAllClients("Treasure appeared on the island! Find the X!", Color3.fromRGB(255, 205, 60))
	end
	workspace:SetAttribute("TreasureNextAt", workspace:GetServerTimeNow() + T.every)
end

function TreasureService.respawn()
	spawnMarks()
end

function TreasureService.init()
	folder = Instance.new("Folder")
	folder.Name = "Treasure"
	folder.Parent = workspace
	task.spawn(function()
		task.wait(T.firstAt)
		while true do
			if #Players:GetPlayers() > 0 then
				spawnMarks()
			end
			task.wait(T.every)
		end
	end)
end

return TreasureService
