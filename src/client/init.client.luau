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
local MiniGames = require(script.MiniGames)
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
require(script.PerfView).init() -- cull far lights, no shadows on phones
Cinema.init(screen)
Hud.init(screen)
Platform.onMode = Hud.setMode
Platform.init()
Menus.init(screen)
ShipView.init()
BattleView.init()
local TapFight = require(script.TapFight)
TapFight.init(screen) -- tap to help in fights: rage meter, SUPER SPLASH, combo, enrage drama
Guide.init(screen)
NpcView.init()
require(script.AdminPanel).init(screen)
require(script.MissionView).init(screen)
require(script.SwimTimer).init(screen)
require(script.CrateView).init(screen)
local CannonView = require(script.CannonView)

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
require(script.Travel).init(screen) -- fast travel: HUD button + the bow launch cannon
require(script.VendorMarks).init()
require(script.LighthouseView).init(screen) -- climb timer + chest countdowns
require(script.DigView).init() -- the treasure-dig cinematic
require(script.PetView).init() -- everyone's strongest monster follows them around (client/PetView)
Hud.on("Fuse", FuseView.hint)
Hud.on("Shop", Menus.shop)
Hud.on("Index", Menus.index)
Hud.on("Team", Menus.team)
Hud.on("Sell", Menus.sell)
Hud.on("Event", Menus.event)
Hud.on("Gifts", Menus.gifts)
Hud.on("Powers", Menus.powers)
Hud.on("Settings", Menus.settings)
Hud.on("InfoPearls", function()
	Menus.currencyInfo("Pearls")
end)
Hud.on("InfoCoins", function()
	Menus.currencyInfo("Coins")
end)
Hud.on("InfoShells", function()
	Menus.currencyInfo("Shells")
end)

-- world prompts that open menus or Robux prompts (the server never needs to see these)
local ProximityPromptService = game:GetService("ProximityPromptService")
local VENDOR_OF = { EventPrompt = "Event", SpellPrompt = "Spellbook", ShopPrompt = "Shop", MuseumPrompt = "Index", PowerPrompt = "Powers", GiftPrompt = "Gifts", TeamPrompt = "Team", EggShopPrompt = "EggShop", GuidePrompt = "Guide", DockyardPrompt = "Dockyard", CardsPrompt = "Cards", CannonGamePrompt = "Cannon", RebirthPrompt = "Rebirth", QuestPrompt = "Quests" }
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
	elseif pp.Name == "QuestPrompt" then
			Menus.quests()
		elseif pp.Name == "RebirthPrompt" then
			Menus.rebirth()
		elseif pp.Name == "GiftPrompt" then
		Menus.gifts()
	elseif pp.Name == "TeamPrompt" then
		Menus.team()
	elseif pp.Name == "EggShopPrompt" then
		Menus.eggShop()
	elseif pp.Name == "DockyardPrompt" then
		Menus.dockyard()
	elseif pp.Name == "GuidePrompt" then
		Menus.guide()
	elseif pp.Name == "CardsPrompt" and State.snapshot and not (State.snapshot.drip and State.snapshot.drip.cove) then
			-- not open yet (staggered unlocks): the server says when
			local ok, msg = State.action("DripCheck", "cove")
			if ok then
				MiniGames.cove()
			else
				Hud.toast(msg or "Not open yet", C.Gold)
			end
		elseif pp.Name == "CardsPrompt" then
		MiniGames.cove()
	elseif pp.Name == "CannonGamePrompt" then -- (not "CannonPrompt": that is the Workshop cannon's Load Cannonball prompt)
		CannonView.enter((pp.Parent :: Instance):GetAttribute("Side") :: string)
	elseif pp.Name == "BundlePrompt" then
		Menus.prompt("Product", "ElementBundle")
	elseif pp.Name == "RobuxPrompt" then
		Menus.prompt("Product", pp:GetAttribute("Product") :: string)
	elseif pp.Name == "FlagPrompt" then
		local ship = pp:FindFirstAncestorOfClass("Model")
		if ship and ship:GetAttribute("Owner") == player.UserId then Menus.shipFlag() end
	end
end)
-- controller shortcuts (with on-screen hints while a pad is used)
local Gamepad = require(script.Gamepad)
Gamepad.init()
-- the pad's button pictures sit on the two HUD buttons that have one (only while a pad is used)
PadStickers.attach(Hud.fightButton(), Enum.KeyCode.ButtonX, { keep = true, size = 36 })
PadStickers.attach(Hud.fuseButton(), Enum.KeyCode.ButtonY, { keep = true, size = 36 })
PadStickers.attach(Hud.sellButton(), Enum.KeyCode.ButtonR1, { keep = true, size = 36 })
PadStickers.attach(Hud.teamButton(), Enum.KeyCode.ButtonR2, { keep = true, size = 36 })
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
-- Y: SUPER SPLASH in a fight (when the rage meter is full), otherwise the fuse hint
Gamepad.bind(Enum.KeyCode.ButtonY, function()
	if Hud.inBattle then
		TapFight.super()
	else
		FuseView.hint()
	end
end)
-- RT opens Pick Team (same as the button beside FIGHT)
Gamepad.bind(Enum.KeyCode.ButtonR2, function()
	if Hud.teamButton().Visible and not Menus.isOpen() then
		Hud.press("Team")
	end
end)
-- RB opens Sell (same as the coin button, which only shows once the tutorial is done)
-- in a fight RB is the tap button instead (each press is one tap)
Gamepad.bind(Enum.KeyCode.ButtonR1, function()
	if Hud.inBattle then
		TapFight.tap()
	elseif Hud.sellButton().Visible and not Menus.isOpen() then
		Hud.press("Sell")
	end
end)
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
-- a new activity just opened (staggered unlocks, server/DripService)
Remotes.event("Drip").OnClientEvent:Connect(function(_id, name, blurb)
	Sound.play("Win", 0.6)
	Hud.splash("NEW: " .. string.upper(tostring(name)) .. "!", C.Gold)
	Hud.toast(tostring(blurb), C.Gold)
end)
-- server-wide brags (big hatches, fuses, first boss kills)
Remotes.event("Announce").OnClientEvent:Connect(function(text, color)
	Hud.announce(text, color)
end)

local snap = State.waitForData()
Hud.refresh()
-- the player's saved Settings volumes, before the music starts
if typeof(snap.volume) == "table" then
	Sound.setVolume("music", tonumber(snap.volume.music) or 1)
	Sound.setVolume("sfx", tonumber(snap.volume.sfx) or 1)
end
Sound.music("Music")

-- first visit: wait for the character on the ship, then roll the intro. Also plays again the
-- moment introSeen goes back to false (admin "Reset to new" / "Play intro"), without a rejoin.
local introQueued = false
local likesShown = false
local function showLikesMilestone()
	if not likesShown then
		likesShown = true
		Hud.toast("Admin Abuse at 100 Likes!", C.Gold)
	end
end

local function maybeIntro()
	local s = State.snapshot
	if introQueued or not s or s.introSeen then
		return
	end
	introQueued = true
	task.spawn(function()
		local char = player.Character or player.CharacterAdded:Wait()
		char:WaitForChild("HumanoidRootPart", 10)
		task.wait(1.2)
		Cinema.intro()
		showLikesMilestone()
		-- allow another replay once the server has marked this one seen
		task.wait(2)
		introQueued = false
	end)
end
maybeIntro()
State.Changed:Connect(maybeIntro)

-- Give returning players' join notifications time to clear before showing the milestone.
if snap.introSeen then
	task.defer(function()
		local quietSince = os.clock()
		while os.clock() - quietSince < 3 do
			task.wait(0.25)
			if introQueued or State.cinematic or State.revealing or Hud.inBattle or Menus.isOpen() or not player.Character or Hud.hasToasts() then
				quietSince = os.clock()
			end
		end
		showLikesMilestone()
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

-- Ask on a return visit, once the player has time to read the ship and join notifications.
task.spawn(function()
	if snap.tutorial < Config.TUTORIAL_DONE then
		return
	end
	local quietSince = os.clock()
	while true do
		task.wait(1)
		local s = State.snapshot
		if s and s.favAsked then
			break
		end
		if not s or s.tutorial < Config.TUTORIAL_DONE or Hud.inBattle or State.revealing or State.cinematic or Menus.isOpen() or Hud.hasToasts() then
			quietSince = os.clock()
		elseif os.clock() - quietSince >= 20 then
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
