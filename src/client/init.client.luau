--!strict
-- Merge Sea Monsters client bootstrap: builds the UI root, starts every view, wires the HUD
-- buttons to actions, and plays the intro cinematic on a player's first visit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local UI = require(script.UI)
local State = require(script.State)
local Sound = require(script.Sound)
local Hud = require(script.Hud)
local Menus = require(script.Menus)
local Cinema = require(script.Cinema)
local ShipView = require(script.ShipView)
local BattleView = require(script.BattleView)
local Guide = require(script.Guide)
local NpcView = require(script.NpcView)
local Platform = require(script.Platform)
local PadStickers = require(script.PadStickers)

local player = Players.LocalPlayer
local C = UI.Colors

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)
player:WaitForChild("PlayerGui").ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor

local screen = UI.new("ScreenGui", {
	Name = "TideUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

-- scale the whole UI from a 1280x720 design so it fits phones, tablets, PC and TV
-- (Platform owns the rule: PC / console fit 1280x720, phones fit 1180x540, safe-area aware)
local uiScale = UI.new("UIScale", { Parent = screen })
Platform.bindScale(screen, uiScale)

State.init()
Cinema.init(screen)
Hud.init(screen)
Platform.onMode = Hud.setMode
Platform.init()
Menus.init(screen)
ShipView.init()
BattleView.init()
Guide.init(screen)
NpcView.init()
require(script.AdminPanel).init(screen)
require(script.MissionView).init(screen)

-- HUD buttons
local busy = false
Hud.on("Fight", function()
	if busy then
		return
	end
	busy = true
	local ok, msg = State.action("Fight")
	if not ok and msg then
		Hud.toast(msg, C.Coral)
	end
	busy = false
end)
Hud.on("Retreat", function()
	State.action("Retreat")
end)
Hud.on("Speed", function()
	local snap = State.snapshot
	local next = if (snap.battleSpeed or 1) == 1 then 2 else 1
	State.action("Speed", next)
end)
-- fusing is in the world now; the heart button just shows how
local FuseView = require(script.FuseView)
FuseView.init()
require(script.FittingView).init()
require(script.VendorMarks).init()
Hud.on("Fuse", FuseView.hint)
Hud.on("Shop", Menus.shop)
Hud.on("Index", Menus.index)
Hud.on("Team", Menus.team)
Hud.on("Event", Menus.event)
Hud.on("Gifts", Menus.gifts)
Hud.on("Powers", Menus.powers)
Hud.on("InfoPearls", function()
	Menus.currencyInfo("Pearls")
end)
Hud.on("InfoCoins", function()
	Menus.currencyInfo("Coins")
end)

-- world prompts that open menus or Robux prompts (the server never needs to see these)
local ProximityPromptService = game:GetService("ProximityPromptService")
local VENDOR_OF = { EventPrompt = "Event", SpellPrompt = "Spellbook", ShopPrompt = "Shop", MuseumPrompt = "Index", PowerPrompt = "Powers", GiftPrompt = "Gifts", TeamPrompt = "Team", EggShopPrompt = "EggShop", GuidePrompt = "Guide", WorkshopPrompt = "Workshop" }
-- a prompt on screen owns the X button (its default gamepad key), so X-to-fight waits
local shownPrompts = 0
ProximityPromptService.PromptShown:Connect(function()
	shownPrompts += 1
end)
ProximityPromptService.PromptHidden:Connect(function()
	shownPrompts = math.max(0, shownPrompts - 1)
end)
ProximityPromptService.PromptTriggered:Connect(function(pp: ProximityPrompt, who: Player)
	if who ~= player then
		return
	end
	local vendor = VENDOR_OF[pp.Name]
	if vendor then
		Remotes.event("Track"):FireServer("vendor", vendor)
	end
	if pp.Name == "EventPrompt" then
		Menus.event()
	elseif pp.Name == "SpellPrompt" then
		Menus.spellbook()
	elseif pp.Name == "ShopPrompt" then
		Menus.shop()
	elseif pp.Name == "MuseumPrompt" then
		Menus.index()
	elseif pp.Name == "PowerPrompt" then
		Menus.powers()
	elseif pp.Name == "GiftPrompt" then
		Menus.gifts()
	elseif pp.Name == "TeamPrompt" then
		Menus.team()
	elseif pp.Name == "EggShopPrompt" then
		Menus.eggShop()
	elseif pp.Name == "WorkshopPrompt" then
		Menus.workshop()
	elseif pp.Name == "GuidePrompt" then
		Menus.guide()
	elseif pp.Name == "BundlePrompt" then
		Menus.prompt("Product", "ElementBundle")
	elseif pp.Name == "RobuxPrompt" then
		Menus.prompt("Product", pp:GetAttribute("Product") :: string)
	end
end)
Hud.on("Starter", function()
	Menus.prompt("Product", "StarterPack")
end)
Hud.on("Offer", function()
	Menus.promptOffer(Hud.offerName())
end)
-- controller shortcuts (with on-screen hints while a pad is used)
local Gamepad = require(script.Gamepad)
Gamepad.init()
-- the pad's button pictures sit on the two HUD buttons that have one (only while a pad is used)
PadStickers.attach(Hud.fightButton(), Enum.KeyCode.ButtonX, { keep = true, size = 36 })
PadStickers.attach(Hud.fuseButton(), Enum.KeyCode.ButtonY, { keep = true, size = 36 })
Gamepad.bind(Enum.KeyCode.ButtonX, function()
	if shownPrompts > 0 or Menus.isOpen() then
		return
	end
	if Hud.inBattle then
		State.action("Retreat")
	else
		Hud.press("Fight")
	end
end)
Gamepad.bind(Enum.KeyCode.ButtonY, FuseView.hint)
Gamepad.bind(Enum.KeyCode.ButtonL1, function()
	Remotes.event("Track"):FireServer("vendor", "Shop")
	Menus.shop()
end)
Gamepad.bind(Enum.KeyCode.ButtonB, Menus.close)
-- View / touchpad is the free-cursor toggle (Platform); opening a menu turns the cursor on

BattleView.onMyEnd = function(p)
	task.delay(1.2, function()
		Menus.battleEnd(p)
	end)
end

Remotes.event("Toast").OnClientEvent:Connect(function(text, color)
	Hud.toast(text, color)
end)

local snap = State.waitForData()
Hud.refresh()
Sound.music("Music")

-- first visit: wait for the character on the ship, then roll the intro
if not snap.introSeen then
	task.spawn(function()
		local char = player.Character or player.CharacterAdded:Wait()
		char:WaitForChild("HumanoidRootPart", 10)
		task.wait(1.2)
		Cinema.intro()
	end)
end

-- VIP Captains get a gold [VIP] tag in chat
pcall(function()
	local TextChatService = game:GetService("TextChatService")
	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local props = Instance.new("TextChatMessageProperties")
		local src = message.TextSource
		local who = src and Players:GetPlayerByUserId(src.UserId)
		if who and who:GetAttribute("VIP") then
			props.PrefixText = '<font color="#FFCD3C">[VIP]</font> ' .. message.PrefixText
		end
		return props
	end
end)

-- ask once to favourite, a little after the tutorial ends (the first boss is beaten)
task.spawn(function()
	while true do
		task.wait(5)
		local s = State.snapshot
		if s and s.favAsked then
			break
		end
		if s and s.tutorial >= Config.TUTORIAL_DONE and not Hud.inBattle and not State.revealing and not State.cinematic then
			task.wait(20)
			local AvatarEditorService = game:GetService("AvatarEditorService")
			local done = false
			local conn = AvatarEditorService.PromptSetFavoriteCompleted:Connect(function(result)
				done = true
				State.action("Favorite", result == Enum.AvatarPromptResult.Success)
			end)
			local ok = pcall(function()
				AvatarEditorService:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
			end)
			if not ok then
				State.action("Favorite", false)
				done = true
			end
			task.delay(60, function()
				conn:Disconnect()
				if not done then
					State.action("Favorite", false)
				end
			end)
			break
		end
	end
end)

local _ = Config
print("[TideTamers] client ready")
