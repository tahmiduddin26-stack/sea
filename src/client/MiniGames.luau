--!strict
-- The two harbour mini games, played in a window opened from their stands:
--   Coral Cards    match 6 pairs of sea cards; fewer moves = a bigger reward
--   Cannon Gallery 12 cannonballs and 30 seconds: tap the floating targets (barrel 1, chest 2, golden 5)
-- The server decides whether you may play (cooldown, tutorial, not in a fight) and pays the reward after
-- checking the result (server/MiniGameService); everything here is just the game and its picture.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)

local UI = require(script.Parent.UI)
local State = require(script.Parent.State)
local Hud = require(script.Parent.Hud)
local Sound = require(script.Parent.Sound)
local Menus = require(script.Parent.Menus)

local MiniGames = {}

local C = UI.Colors
local CORAL = Color3.fromRGB(255, 120, 140)
local ORANGE = Color3.fromRGB(255, 170, 80)

-- ask the server for a game: returns the shuffle seed, or nil (with a toast saying why)
local function begin(game: string): number?
	local ok, msg = State.action("MiniStart", game)
	if not ok then
		Hud.toast(msg or "Not now", C.Coral)
		return nil
	end
	return tonumber(msg) or 1
end

-- report the result: returns the reward text the server sent (or why it refused)
local function report(result: { [string]: any }): (boolean, string)
	local ok, msg = State.action("MiniFinish", result)
	return ok, msg or ""
end

-- the end screen inside the window: what you got, and a button to leave
local function showResult(body: Frame, ok: boolean, text: string)
	for _, d in body:GetChildren() do
		if d:IsA("GuiObject") then
			d.Visible = false
		end
	end
	local box = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = body })
	UI.label({ Text = if ok then "Great game!" else "Oh no!", TextColor3 = if ok then C.Gold else C.Coral, MaxText = 44, Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 24), Parent = box })
	UI.label({ Text = text, Stroke = 0, TextColor3 = C.Ink, MaxText = 26, TextWrapped = true, Size = UDim2.new(1, -40, 0, 90), Position = UDim2.fromOffset(20, 96), Parent = box })
	UI.button({ Text = "OK", Color = C.Kelp, Size = UDim2.fromOffset(220, 56), Position = UDim2.new(0.5, 0, 1, -24), AnchorPoint = Vector2.new(0.5, 1), Parent = box }, function()
		Menus.close()
	end)
	Sound.play(if ok then "Win" else "Lose", 0.7)
end

---------------------------------------------------------------------------
-- Coral Cards
---------------------------------------------------------------------------
local CARD_ICONS = { "Coin", "Pearl", "Shell", "Heart", "LuckEgg", "Crate" }

function MiniGames.cards()
	local seed = begin("cards")
	if not seed then
		return
	end
	local f, body = Menus.openWindow("Coral Cards", Vector2.new(520, 470), CORAL)
	local pairsN = Config.CARDS_PAIRS
	-- the deck: every picture twice, shuffled with the server's seed
	local deck: { number } = {}
	for i = 1, pairsN do
		table.insert(deck, i)
		table.insert(deck, i)
	end
	local rng = Random.new(seed)
	for i = #deck, 2, -1 do
		local j = rng:NextInteger(1, i)
		deck[i], deck[j] = deck[j], deck[i]
	end

	local moves, found = 0, 0
	local info = UI.label({ Text = "", MaxText = 26, TextColor3 = C.Gold, Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 2), Parent = body })
	local function refreshInfo()
		info.Text = "Moves: " .. moves .. "    Pairs: " .. found .. "/" .. pairsN
	end
	refreshInfo()
	local grid = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(398, 308), Position = UDim2.new(0.5, 0, 0, 44), AnchorPoint = Vector2.new(0.5, 0), Parent = body })
	UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(92, 96), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })

	local cards: { TextButton } = {}
	local faces: { ImageLabel } = {}
	local backs: { TextLabel } = {}
	local matched: { [number]: boolean } = {}
	local open: { number } = {}
	local locked = false

	-- a card's coral colour is a gradient (UI.button): switch it off to show the cream face-up colour
	local function paint(i: number, color: Color3?)
		local g = cards[i]:FindFirstChildOfClass("UIGradient")
		if g then
			g.Enabled = color == nil
		end
		cards[i].BackgroundColor3 = color or Color3.new(1, 1, 1)
	end
	local function show(i: number, up: boolean)
		faces[i].Visible = up
		backs[i].Visible = not up
		paint(i, if up then Color3.fromRGB(255, 248, 230) else nil)
	end

	local function click(i: number)
		if locked or matched[i] or table.find(open, i) or not f.Parent then
			return
		end
		show(i, true)
		Sound.play("Place", 0.5, 1.2)
		table.insert(open, i)
		if #open < 2 then
			return
		end
		moves += 1
		refreshInfo()
		local a, b = open[1], open[2]
		open = {}
		if deck[a] == deck[b] then
			matched[a], matched[b] = true, true
			found += 1
			refreshInfo()
			Sound.play("Coin", 0.6)
			for _, k in { a, b } do
				paint(k, Color3.fromRGB(165, 235, 170))
			end
			if found == pairsN then
				locked = true
				task.delay(0.6, function()
					if not f.Parent then
						return
					end
					local ok, text = report({ moves = moves })
					if f.Parent then
						showResult(body, ok, text)
					end
				end)
			end
			return
		end
		-- not a pair: look for a moment, then turn both back
		locked = true
		task.delay(0.7, function()
			if f.Parent then
				show(a, false)
				show(b, false)
			end
			locked = false
		end)
	end

	for i = 1, #deck do
		local card = UI.button({ Text = "", Color = CORAL, Size = UDim2.fromOffset(92, 96), LayoutOrder = i, Parent = grid }, function()
			click(i)
		end)
		local back = UI.label({ Text = "?", TextColor3 = Color3.new(1, 1, 1), MaxText = 52, Size = UDim2.fromScale(0.8, 0.7), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 3, Parent = card })
		local face = UI.new("ImageLabel", { BackgroundTransparency = 1, Image = Config.ICONS[CARD_ICONS[deck[i]]], Size = UDim2.fromScale(0.78, 0.78), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, ZIndex = 3, Parent = card })
		cards[i], faces[i], backs[i] = card, face, back
	end
	UI.label({ Text = "Flip two cards: find all " .. pairsN .. " pairs in as few moves as you can!", Stroke = 0, TextColor3 = C.Deep, MaxText = 20, Size = UDim2.new(1, -20, 0, 26), Position = UDim2.new(0, 10, 1, -30), Parent = body })
end


local _ = Format
return MiniGames
