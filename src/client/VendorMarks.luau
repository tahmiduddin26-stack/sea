--!strict
-- Since menus live at vendors in the world, a big bouncing "!" floats over any vendor that
-- has something waiting for you, so kids know where to walk:
--   Gift Chest     a playtime gift or the daily chest is ready
--   Event stand    you have enough shells to buy something
--   Spellbook      you hold spell cards
--   Monster Museum you found a new species since you last looked
--   Power Shrine   you have free spins (after Powers unlock)
--   Dockyard       you can afford a ship upgrade

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local Stats = require(ReplicatedStorage:WaitForChild("Shared").Stats)

local UI = require(script.Parent.UI)
local State = require(script.Parent.State)
local Hud = require(script.Parent.Hud)

local VendorMarks = {}

local player = Players.LocalPlayer
local C = UI.Colors

local marks: { [BasePart]: BillboardGui } = {}

local function mark(anchor: BasePart, on: boolean)
	local g = marks[anchor]
	if on and not g then
		local gui = UI.new("BillboardGui", { Size = UDim2.fromScale(3, 3), StudsOffsetWorldSpace = Vector3.new(0, 9, 0), LightInfluence = 0, AlwaysOnTop = true, MaxDistance = 400, Parent = anchor })
		local chip = UI.new("Frame", { BackgroundColor3 = C.Coral, Size = UDim2.fromScale(1, 1), Parent = gui }, { UI.corner(100), UI.stroke(4) })
		UI.label({ Text = "!", MaxText = 60, Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.08), Parent = chip })
		marks[anchor] = gui
	elseif not on and g then
		g:Destroy()
		marks[anchor] = nil
	end
end

local function anchorOf(root: Instance?, promptName: string): BasePart?
	if not root then
		return nil
	end
	local pp = root:FindFirstChild(promptName, true)
	return if pp then pp.Parent :: BasePart else nil
end

local function refresh()
	local snap = State.snapshot
	local world = workspace:FindFirstChild("World")
	if not snap or not world or snap.tutorial < Config.HUD_UNLOCK_STEP then
		return
	end
	local hub = world:FindFirstChild("Harbour")
	local ship = world:FindFirstChild("Ship" .. tostring(player:GetAttribute("Ship")))
	-- gifts
	local played = State.now() - (snap.sessionStart or State.now())
	local giftReady = snap.dailyDay ~= State.now() // 86400
	for i, g in Config.GIFTS do
		if not (snap.giftsClaimed and snap.giftsClaimed[i]) and played >= g.min * 60 then
			giftReady = true
		end
	end
	local a = anchorOf(ship, "GiftPrompt")
	if a then
		mark(a, giftReady)
	end
	-- event shells
	local cheapest = math.huge
	for _, it in Config.EVENT.shop do
		cheapest = math.min(cheapest, it.cost)
	end
	a = anchorOf(hub, "EventPrompt")
	if a then
		mark(a, os.time() < Config.EVENT.endsAt and (snap.shells or 0) >= cheapest)
	end
	-- spells held
	local held = 0
	for _, n in snap.spells or {} do
		held += tonumber(n) or 0
	end
	a = anchorOf(hub, "SpellPrompt")
	if a then
		mark(a, held > 0)
	end
	-- new species
	local found = 0
	for _ in snap.index do
		found += 1
	end
	a = anchorOf(hub, "MuseumPrompt")
	if a then
		mark(a, found > (Hud.indexSeen or 0))
	end
	-- free power spins
	a = anchorOf(hub, "PowerPrompt")
	if a then
		mark(a, snap.bestDepth >= Config.POWERS_UNLOCK_DEPTH and (snap.spins or 0) > 0)
	end
	-- Dockyard: you can afford an Egg Luck / Fast Reel level or the next Shipwright tier
	local ups = snap.upgrades or {}
	local lowest = math.huge
	for _, id in { "Luck", "Pedestals" } do
		local p = Stats.upgradePrice(id, ups[id] or 0)
		if p then
			lowest = math.min(lowest, p)
		end
	end
	local nextTier = (snap.shipTier or 0) + 1
	if nextTier <= #Config.SHIP_TIERS and snap.bestDepth >= Stats.shipTierDepth(nextTier) then
		lowest = math.min(lowest, Stats.shipTierPrice(nextTier))
	end
	a = anchorOf(hub, "DockyardPrompt")
	if a then
		mark(a, snap.coins >= lowest)
	end
end

function VendorMarks.init()
	local last = 0
	-- Town text (vendor names, the leaderboard...) stays hidden until you are inside the town;
	-- nothing floats about while you're out at sea. (The bouncing "!" marks stay: they guide you.)
	local townGuis: { BillboardGui } = {}
	task.spawn(function()
		local world = workspace:WaitForChild("World")
		local hub = world:WaitForChild("Harbour")
		task.wait(1)
		for _, d in hub:GetDescendants() do
			if d:IsA("BillboardGui") and not (d.Parent and marks[d.Parent :: BasePart] == d) then
				table.insert(townGuis, d)
			end
		end
		local TOWN_RADIUS = Config.HUB_RADIUS + 30
		local centre = Vector3.new(0, Config.SEA_LEVEL, 0)
		while true do
			local char = Players.LocalPlayer.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local flat = (root.Position - centre) * Vector3.new(1, 0, 1)
				local inTown = flat.Magnitude < TOWN_RADIUS
				for _, g in townGuis do
					if g.Enabled ~= inTown then
						g.Enabled = inTown
					end
				end
			end
			task.wait(0.4)
		end
	end)
	RunService.Heartbeat:Connect(function()
		local t = os.clock()
		-- bob every mark
		for anchor, g in marks do
			if anchor.Parent then
				g.StudsOffsetWorldSpace = Vector3.new(0, 9 + math.abs(math.sin(t * 3)) * 1.2, 0)
			end
		end
		if t - last > 1 then
			last = t
			refresh()
		end
	end)
end

return VendorMarks
