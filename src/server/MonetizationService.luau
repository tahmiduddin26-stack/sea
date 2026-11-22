--!strict
-- Gamepasses + developer products. An id of 0 means "not created yet": in Studio the client
-- asks the server to simulate the purchase so every flow can be tested before the ids exist.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Stats = require(Shared.Stats)
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local FarmService = require(script.Parent.FarmService)
local BattleService = require(script.Parent.BattleService)
local ExtrasService = require(script.Parent.ExtrasService)
local Analytics = require(script.Parent.Analytics)

local MonetizationService = {}

local GOLD = Color3.fromRGB(255, 205, 60)

local function toast(player: Player, text: string, color: Color3?)
	Remotes.event("Toast"):FireClient(player, text, color)
end

-- a gold "VIP" tag over the head (re-added on every respawn)
local function addTag(char: Model)
	local head = char:WaitForChild("Head", 5)
	if not head or head:FindFirstChild("VipTag") then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "VipTag"
	bb.Size = UDim2.fromScale(3, 0.9)
	bb.StudsOffset = Vector3.new(0, 2.4, 0)
	bb.MaxDistance = 80
	bb.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.Text = "VIP CAPTAIN"
	t.TextColor3 = Color3.fromRGB(255, 205, 60)
	local st = Instance.new("UIStroke")
	st.Thickness = 2
	st.Color = Color3.fromRGB(60, 35, 5)
	st.Parent = t
	t.Parent = bb
	bb.Parent = head
end

local tagged: { [Player]: boolean } = {}
local function vipTag(player: Player)
	if tagged[player] then
		return
	end
	tagged[player] = true
	if player.Character then
		task.spawn(addTag, player.Character)
	end
	player.CharacterAdded:Connect(addTag)
end

local function grantPass(player: Player, name: string)
	local s = DataService.session(player)
	if not s or s.passes[name] then
		return
	end
	s.passes[name] = true
	Analytics.store(player, name, 3)
	if name == "VIP" then
		player:SetAttribute("VIP", true)
		vipTag(player)
	end
	FarmService.syncAll(player)
	DataService.changed(player)
end

local function grantProduct(player: Player, name: string): boolean
	local data = DataService.get(player)
	if not data then
		return false
	end
	Analytics.tag(player, "IAP", name)
	if name == "StarterPack" then
		data.starterBought = true
		data.coins += 5000
		data.pearls += 50
		if not FarmService.giveMonster(player, "Kelpdrake", 3, 2) then
			data.coins += 8000
			toast(player, "Nests full, so you got extra coins instead of the egg", GOLD)
		end
		toast(player, "Starter Pack! A Lv3 Kelpdrake egg is in your nest", GOLD)
	elseif name == "FuseLuck" or name == "InsaneLuck" then
		local mult = if name == "FuseLuck" then Config.FUSE_LUCK_MULT else Config.INSANE_LUCK_MULT
		data.luckMult = math.max(if data.luckUntil > os.time() then data.luckMult else 1, mult)
		data.luckUntil = math.max(data.luckUntil, os.time()) + Config.LUCK_SECONDS
		toast(player, "x" .. mult .. " Fuse Luck for 15 minutes!", GOLD)
	elseif name == "Luck30" then
		data.luck30Until = math.max(data.luck30Until or 0, os.time()) + Config.LUCK30_SECONDS
		toast(player, "x2 Luck for 30 minutes!", GOLD)
	elseif name == "Revive" then
		if not BattleService.revive(player) then
			-- nothing to revive: keep the value as pearls
			data.pearls += 20
			toast(player, "No battle to revive, so here are 20 pearls", GOLD)
		end
	elseif name == "SkipTimer" then
		if not FarmService.finishAllTimers(player) then
			data.pearls += 10
			toast(player, "No timers running, so here are 10 pearls", GOLD)
		end
	elseif Config.COIN_PACK_MINUTES[name] then
		local coins = math.floor(Stats.coinsPerMinute(data.bestDepth) * Config.COIN_PACK_MINUTES[name])
		coins = math.max(coins, if name == "CoinsSmall" then 5000 else 25000)
		data.coins += coins
		toast(player, "+" .. Format.abbrev(coins) .. " Coins!", GOLD)
	elseif name == "ElementBundle" then
		if not ExtrasService.elementBundle(player) then
			toast(player, "Free 4 nests to get your Elemental Bundle!", GOLD)
			return false -- Roblox retries it later
		end
	elseif name == "LimitedRoll" then
		local ok = ExtrasService.limitedRoll(player, true)
		if not ok then
			toast(player, "Free a nest to open your Abyss Crate!", GOLD)
			return false
		end
	elseif name == "PowerSpins" then
		data.spins += 5
		toast(player, "+5 Power spins!", GOLD)
	elseif name == "PearlDragonPack" then
		if not FarmService.giveMonster(player, "PearlDragon", 5, 3) then
			return false -- retried until they have a free nest
		end
		toast(player, "The Pearl Dragon egg is in your nest!", GOLD)
	else
		return false
	end
	DataService.changed(player)
	Analytics.store(player, name, 3)
	return true
end

local function passNameById(id: number): string?
	for name, info in Config.GAMEPASSES do
		if info.id == id and id ~= 0 then
			return name
		end
	end
	return nil
end

local function productNameById(id: number): string?
	for name, info in Config.PRODUCTS do
		if info.id == id and id ~= 0 then
			return name
		end
	end
	return nil
end

local function checkOwnedPasses(player: Player)
	for name, info in Config.GAMEPASSES do
		if info.id ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, info.id)
			end)
			if ok and owns then
				grantPass(player, name)
			end
		end
	end
end

function MonetizationService.init()
	DataService.Loaded:Connect(function(player)
		task.spawn(checkOwnedPasses, player)
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased then
			local name = passNameById(passId)
			if name then
				grantPass(player, name)
				toast(player, "Thanks for buying " .. Config.GAMEPASSES[name].name .. "!", GOLD)
			end
		end
	end)

	-- Never grant the same PurchaseId twice; only answer Granted once it's saved.
	MarketplaceService.ProcessReceipt = function(receipt)
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		if not player or not DataService.isLoaded(player) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local data = DataService.get(player)
		local purchaseId = tostring(receipt.PurchaseId)
		data.receipts = data.receipts or {}
		if data.receipts[purchaseId] then
			if DataService.canSave(player) and not DataService.save(player) then
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		local name = productNameById(receipt.ProductId)
		if not name then
			warn("[Shop] receipt for unknown product", receipt.ProductId)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local canSave = DataService.canSave(player)
		if not canSave and not RunService:IsStudio() then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		if not grantProduct(player, name) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		data.receipts[purchaseId] = true
		if canSave and not DataService.save(player) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- Studio-only simulated purchases for ids that aren't set yet
	local simulate = Instance.new("RemoteFunction")
	simulate.Name = "SimulatePurchase"
	simulate.Parent = ReplicatedStorage:WaitForChild("Remotes")
	simulate.OnServerInvoke = function(player, kind, name)
		if not RunService:IsStudio() or typeof(name) ~= "string" then
			return false
		end
		if kind == "Pass" and Config.GAMEPASSES[name] and Config.GAMEPASSES[name].id == 0 then
			grantPass(player, name)
			toast(player, "[Studio] Granted " .. Config.GAMEPASSES[name].name, GOLD)
			return true
		elseif kind == "Product" and Config.PRODUCTS[name] and Config.PRODUCTS[name].id == 0 then
			return grantProduct(player, name)
		end
		return false
	end
end

return MonetizationService
