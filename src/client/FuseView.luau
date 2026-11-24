--!strict
-- Fusing in the world with a bottom tray. Press the pink Fuse button (or E on any monster in
-- its nest) and a ship-plank tray slides up with two slots. Press E on a monster and it flies
-- into the first slot; every other monster of the same level glows green, the rest fade.
-- Pick a second one of the same level and it flies into the second slot. When both slots are
-- full the FUSE! button lights up; press it and both swoop into the first nest with a spin
-- and a burst of hearts, then the fused egg appears there. E on a picked monster takes it back
-- out; X on the tray (or B / Escape) closes it.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MonsterModels = require(Shared.MonsterModels)
local Stats = require(Shared.Stats)

local UI = require(script.Parent.UI)
local State = require(script.Parent.State)
local Hud = require(script.Parent.Hud)
local Sound = require(script.Parent.Sound)
local Platform = require(script.Parent.Platform)

-- the verb for picking a monster on this device: Tap (phone), Click (PC), Pick (controller)
local function pickWord(): string
	local m = Platform.mode()
	return if m == "touch" then "Tap" elseif m == "key" then "Click" else "Pick"
end
local ShipView = require(script.Parent.ShipView)

local FuseView = {}

local player = Players.LocalPlayer
local C = UI.Colors
local PINK = Color3.fromRGB(255, 110, 170)

local chosen: { BasePart } = {}
local tag: BillboardGui? = nil
local busy = false

local screenGui: ScreenGui? = nil
local tray: Frame? = nil
local slotBoxes: { Frame } = {}
local hintLbl: TextLabel? = nil
local resultLbl: TextLabel? = nil
local goBtn: TextButton? = nil
local oddsPanel: Frame? = nil -- "Fuse chances" plank above the tray, shown while a pair is picked
local oddsRow: Frame? = nil
local oddsHeadRight: TextLabel? = nil
local fuseNow: () -> () = function() end -- set below, once the fuse itself is defined
local fuseVfx: (Vector3, Color3, Color3, number) -> () -- defined with the fuse itself
local flash: (Vector3, number) -> ()

local function myNests(): { BasePart }
	local out = {}
	local ship = ShipView.myShip()
	if not ship then
		return out
	end
	for _, d in ship:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("NestIndex") then
			table.insert(out, d)
		end
	end
	return out
end

-- bouncing "TAP!" signs over every monster that can still go in the tray
local tapTags: { BillboardGui } = {}

local function clearMarks()
	for k in ShipView.marks do
		ShipView.marks[k] = nil
	end
	if tag then
		tag:Destroy()
		tag = nil
	end
	for _, g in tapTags do
		g:Destroy()
	end
	tapTags = {}
end

---------------------------------------------------------------------------
-- Tray helpers
---------------------------------------------------------------------------
local function guiScale(): number
	local sg = screenGui
	local sc = if sg then sg:FindFirstChildOfClass("UIScale") else nil
	return if sc then sc.Scale else 1
end

-- design-unit position of a point in the world (for the flying ghost)
local function worldToGui(world: Vector3): Vector2?
	local sg = screenGui
	local cam = workspace.CurrentCamera
	if not sg or not cam then
		return nil
	end
	local p, onScreen = cam:WorldToViewportPoint(world)
	if not onScreen then
		return nil
	end
	local inset = sg.AbsolutePosition
	local s = guiScale()
	return Vector2.new((p.X - inset.X) / s, (p.Y - inset.Y) / s)
end

local function centerOf(gui: GuiObject): Vector2
	local sg = screenGui :: ScreenGui
	local inset = sg.AbsolutePosition
	local s = guiScale()
	local c = gui.AbsolutePosition + gui.AbsoluteSize / 2
	return Vector2.new((c.X - inset.X) / s, (c.Y - inset.Y) / s)
end

local function creatureView(parent: GuiObject, sp: string, size: UDim2, silhouette: boolean?): ViewportFrame
	local vp = UI.new("ViewportFrame", { BackgroundTransparency = 1, Size = size, Ambient = Color3.fromRGB(200, 200, 210), LightColor = Color3.new(1, 1, 1), LightDirection = Vector3.new(-1, -1, -1), Parent = parent })
	local rig = MonsterModels.build(sp, 1)
	if not rig then
		return vp
	end
	rig.model.Parent = vp
	if silhouette then
		MonsterModels.tint(rig, Color3.fromRGB(20, 26, 50), 1) -- not found yet: a dark shape, like the Index
	end
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	local h = MonsterModels.height(rig)
	local foot = MonsterModels.footDepth(rig)
	local mid = (h - foot) / 2
	cam.CFrame = CFrame.lookAt(Vector3.new(-5.5, mid + 2.2, -11), Vector3.new(0, mid, 0))
	cam.Parent = vp
	vp.CurrentCamera = cam
	return vp
end

-- how many monsters this fuse takes (Stats.fuseNeeded of the first pick's level; 2 before a pick)
local function needed(): number
	if #chosen == 0 then
		return 2
	end
	return Stats.fuseNeeded(chosen[1]:GetAttribute("Lvl") :: number)
end

---------------------------------------------------------------------------
-- The helper: while the tray is open the guide (red trail, bobbing arrow, banner) shows the next
-- step, exactly like the new-player tutorial: walk to a monster, pick the others, then FUSE!
---------------------------------------------------------------------------
local function myMonsterPads(): { BasePart }
	local out = {}
	for _, n in myNests() do
		if n:GetAttribute("State") == "mon" and not table.find(chosen, n) then
			table.insert(out, n)
		end
	end
	return out
end

-- the nearest of these pads to the player
local function nearestPad(pads: { BasePart }): BasePart?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local best: BasePart? = nil
	local bestD = math.huge
	for _, p in pads do
		local d = if root then (p.Position - root.Position).Magnitude else 0
		if d < bestD then
			best, bestD = p, d
		end
	end
	return best
end

-- the next monster to pick: a partner of the same level once one is chosen, otherwise a monster
-- whose level has enough friends to fuse (nil if no level does)
local function helperPad(): BasePart?
	local pads = myMonsterPads()
	if #chosen > 0 then
		if #chosen >= needed() then
			return nil
		end
		local lvl = chosen[1]:GetAttribute("Lvl")
		local same = {}
		for _, p in pads do
			if p:GetAttribute("Lvl") == lvl then
				table.insert(same, p)
			end
		end
		return nearestPad(same)
	end
	local byLvl: { [number]: { BasePart } } = {}
	for _, p in pads do
		local l = (p:GetAttribute("Lvl") or 1) :: number
		byLvl[l] = byLvl[l] or {}
		table.insert(byLvl[l], p)
	end
	local ok = {}
	for l, list in byLvl do
		if #list >= Stats.fuseNeeded(l) then
			for _, p in list do
				table.insert(ok, p)
			end
		end
	end
	return nearestPad(ok)
end

local function helperText(): string
	local need = needed()
	if #chosen == 0 then
		if helperPad() == nil then
			return "You need <MORE MONSTERS> of the same level!"
		end
		return pickWord() .. " a monster to <FUSE>!"
	elseif #chosen < need then
		return pickWord() .. " " .. (need - #chosen) .. " more <Lv." .. tostring(chosen[1]:GetAttribute("Lvl")) .. ">!"
	end
	return "Press <FUSE!>"
end

local function startHelper()
	local Guide = require(script.Parent.Guide) :: any
	Guide.helper = {
		text = helperText,
		world = function()
			return if tray and tray.Visible then helperPad() else nil
		end,
		gui = function()
			if tray and tray.Visible and #chosen >= needed() and #chosen > 0 then
				return goBtn
			end
			return nil
		end,
	}
end

local function stopHelper()
	local Guide = require(script.Parent.Guide) :: any
	Guide.helper = nil
end

-- the slot boxes, rebuilt whenever the count changes; they shrink to fit the slot area
local slotArea: Frame? = nil
local SLOT_AREA_W = 380
local function layoutSlots(n: number)
	local area = slotArea :: Frame
	for _, b in slotBoxes do
		b:Destroy()
	end
	slotBoxes = {}
	local gap = 8
	local size = math.min(92, math.floor((SLOT_AREA_W - (n - 1) * gap) / n))
	for i = 1, n do
		local box = UI.panel({ Color = Color3.fromRGB(255, 236, 214), Radius = 14, Size = UDim2.fromOffset(size, size), Position = UDim2.new(0, (i - 1) * (size + gap), 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Parent = area })
		UI.label({ Name = "Q", Text = "?", TextColor3 = Color3.fromRGB(190, 120, 80), Size = UDim2.fromScale(0.5, 0.5), Position = UDim2.fromScale(0.25, 0.25), Parent = box })
		slotBoxes[i] = box
	end
end

-- Fuse luck as the server counts it (FarmService.luckMult): Fuse Luck boost, x2 Luck pass,
-- x2 Luck 30m, and any running spell with a fuseLuck effect
local function fuseLuck(snap: any): number
	local now = State.now()
	local m = 1
	if (snap.luckUntil or 0) > now then
		m = snap.luckMult or 1
	end
	if snap.passes and snap.passes.DoubleLuck then
		m *= 2
	end
	if (snap.luck30Until or 0) > now then
		m *= 2
	end
	for _, sp in Config.SPELLS do
		local v = sp.effects.fuseLuck
		if v and ((snap.spellUntil or {})[sp.id] or 0) > now then
			m *= v
		end
	end
	return m
end

-- The chances plank above the tray: once two monsters are picked it lists every monster this
-- fuse can make with its chance, and it stays up until you press FUSE! (or take one back out)
local function updateOdds()
	local panel, row = oddsPanel, oddsRow
	local snap = State.snapshot
	if not panel or not row or not snap then
		return
	end
	for _, ch in row:GetChildren() do
		if ch:IsA("GuiObject") then
			ch:Destroy()
		end
	end
	if #chosen < 2 then
		panel.Visible = false
		return
	end
	panel.Visible = true
	local luck = fuseLuck(snap)
	local right = oddsHeadRight :: TextLabel
	right.Text = if luck > 1 then "Fuse luck x" .. math.floor(luck * 10 + 0.5) / 10 else ""
	local lvl = chosen[1]:GetAttribute("Lvl") :: number
	-- every monster in the tray counts, same as the server's roll (Stats.fuseOdds)
	local species = {}
	for _, p in chosen do
		table.insert(species, p:GetAttribute("Sp") :: string)
	end
	local outs = Stats.fuseOdds(species, lvl, luck)
	for i, o in outs do
		if i > 5 then
			break
		end
		local def = Config.MONSTERS[o.sp]
		local known = snap.index ~= nil and snap.index[o.sp] ~= nil
		local card = UI.panel({ Color = Color3.fromRGB(255, 236, 214), Radius = 12, Size = UDim2.fromOffset(112, 92), Parent = row })
		card.LayoutOrder = i
		local vp = creatureView(card, o.sp, UDim2.new(1, 0, 0, 42), not known)
		vp.Position = UDim2.fromOffset(0, 3)
		UI.label({ Text = if known then def.name else "???", TextColor3 = Config.RARITY[def.stars].color, MaxText = 15, Size = UDim2.new(1, -6, 0, 17), Position = UDim2.fromOffset(3, 47), Parent = card })
		UI.label({ Text = (math.floor(o.chance * 1000 + 0.5) / 10) .. "%", TextColor3 = C.Gold, MaxText = 24, Size = UDim2.new(1, -6, 0, 26), Position = UDim2.fromOffset(3, 64), Parent = card })
	end
end

local function renderTray(newIndex: number?)
	if not tray then
		return
	end
	updateOdds()
	local need = needed()
	if #slotBoxes ~= need then
		layoutSlots(need)
	end
	for i = 1, need do
		local box = slotBoxes[i]
		local old = box:FindFirstChild("Mon")
		if old then
			old:Destroy()
		end
		local q = box:FindFirstChild("Q") :: GuiObject
		local pad = chosen[i]
		q.Visible = pad == nil
		if pad then
			local holder = UI.new("Frame", { Name = "Mon", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = newIndex ~= i, Parent = box })
			creatureView(holder, pad:GetAttribute("Sp") :: string, UDim2.new(1, 0, 0.76, 0))
			UI.label({ Text = "Lv." .. tostring(pad:GetAttribute("Lvl")), MaxText = 18, Size = UDim2.new(1, 0, 0.22, 0), Position = UDim2.fromScale(0, 0.77), Parent = holder })
			if newIndex == i then
				task.delay(0.45, function()
					if holder.Parent then
						holder.Visible = true
						UI.pop(holder, 0.7)
					end
				end)
			end
		end
	end
	local ready = #chosen >= need
	local hint = hintLbl :: TextLabel
	if #chosen == 0 then
		hint.Text = pickWord() .. " a monster to fuse"
	elseif not ready then
		local left = need - #chosen
		hint.Text = pickWord() .. " " .. left .. " more <font color=\"#6BF08F\">glowing</font> <font color=\"#FFCD32\">Lv." .. tostring(chosen[1]:GetAttribute("Lvl")) .. "</font> on your ship (" .. #chosen .. "/" .. need .. ")"
	else
		hint.Text = "Ready! Press <font color=\"#6BF08F\">FUSE!</font>"
	end
	local res = resultLbl :: TextLabel
	res.Text = if #chosen > 0 then "Lv." .. tostring((chosen[1]:GetAttribute("Lvl") :: number) + 1) .. "\n???" else "?"
	local go = goBtn :: TextButton
	go.BackgroundColor3 = if ready then Color3.new(1, 1, 1) else Color3.fromRGB(150, 150, 150)
	local g = go:FindFirstChildOfClass("UIGradient")
	if g then
		local face = if ready then C.Kelp else C.Muted
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, face:Lerp(Color3.new(1, 1, 1), 0.25)),
			ColorSequenceKeypoint.new(1, face:Lerp(Color3.new(0, 0, 0), 0.12)),
		})
	end
	if ready then
		local sc = go:FindFirstChildOfClass("UIScale")
		if sc then
			sc.Scale = 1.12
			UI.tween(sc, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end
end

-- a small copy of the monster flies from the world into its slot
local function flyGhost(pad: BasePart, index: number)
	local sg = screenGui
	local box = slotBoxes[index]
	if not sg or not box then
		return
	end
	local from = worldToGui(pad.Position + Vector3.new(0, 4, 0)) or Vector2.new(640, 300)
	local to = centerOf(box)
	local ghost = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(110, 110), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(from.X, from.Y), ZIndex = 60, Parent = sg })
	creatureView(ghost, pad:GetAttribute("Sp") :: string, UDim2.fromScale(1, 1))
	UI.tween(ghost, 0.45, { Position = UDim2.fromOffset(to.X, to.Y), Size = UDim2.fromOffset(70, 70) }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	task.delay(0.47, function()
		ghost:Destroy()
		Sound.play("Click", 0.6, 1.3)
	end)
end

---------------------------------------------------------------------------
-- Marks in the world (green = can pair, dim = can't)
---------------------------------------------------------------------------
local function floatTag(pad: BasePart, text: string, color: Color3): BillboardGui
	local gui = UI.new("BillboardGui", { Size = UDim2.fromScale(8, 1.6), StudsOffsetWorldSpace = Vector3.new(0, 9, 0), LightInfluence = 0, AlwaysOnTop = true, MaxDistance = 120, Parent = pad })
	UI.label({ Text = text, TextColor3 = color, MaxText = 26, Size = UDim2.fromScale(1, 1), Parent = gui })
	return gui
end

local function refreshMarks()
	clearMarks()
	if #chosen == 0 then
		-- nothing picked yet: the monsters that CAN be fused stay in full colour, the rest turn
		-- see-through. Fusable = enough monsters of its level (Stats.fuseNeeded), below max level
		-- and not past the level cap that the next boss unlocks (the same checks as the server)
		if not (tray and tray.Visible) then
			return
		end
		local snap = State.snapshot
		local cap = Stats.levelCap(if snap then snap.bestDepth else 0)
		local counts: { [number]: number } = {}
		local mons: { BasePart } = {}
		for _, n in myNests() do
			if n:GetAttribute("State") == "mon" then
				local l = (n:GetAttribute("Lvl") or 1) :: number
				counts[l] = (counts[l] or 0) + 1
				table.insert(mons, n)
			end
		end
		for _, n in mons do
			local l = (n:GetAttribute("Lvl") or 1) :: number
			local can = l < Config.MAX_LEVEL and l + 1 <= cap and (counts[l] or 0) >= Stats.fuseNeeded(l)
			ShipView.marks[n] = if can then "ready" else "dim"
		end
		return
	end
	local lvl = chosen[1]:GetAttribute("Lvl")
	local need = needed()
	for _, c in chosen do
		ShipView.marks[c] = "picked"
	end
	local partners = 0
	for _, n in myNests() do
		if not table.find(chosen, n) and n:GetAttribute("State") == "mon" then
			if #chosen < need and n:GetAttribute("Lvl") == lvl then
				ShipView.marks[n] = "ok"
				partners += 1
				-- a bouncing green "TAP!" so it's obvious which monsters you can pick next
				local g = UI.new("BillboardGui", { Size = UDim2.fromScale(4, 2), StudsOffsetWorldSpace = Vector3.new(0, 8, 0), LightInfluence = 0, AlwaysOnTop = true, MaxDistance = 160, Parent = n })
				local lbl = UI.label({ Text = string.upper(pickWord()) .. "!", TextColor3 = C.Kelp, MaxText = 30, Size = UDim2.fromScale(1, 1), Parent = g })
				task.spawn(function()
					local up = true
					while g.Parent do
						UI.tween(lbl, 0.4, { Position = UDim2.fromScale(0, if up then -0.25 else 0) }, Enum.EasingStyle.Sine)
						up = not up
						task.wait(0.42)
					end
				end)
				table.insert(tapTags, g)
			else
				ShipView.marks[n] = "dim"
			end
		end
	end
	local left = need - #chosen
	if left > 0 then
		if partners < left then
			tag = floatTag(chosen[1], "Need " .. need .. " Lv." .. tostring(lvl) .. " monsters!", C.Coral)
			Hud.toast("Lv." .. tostring(lvl) .. " needs " .. need .. " monsters to fuse. Hatch " .. (left - partners) .. " more", C.Coral)
		else
			tag = floatTag(chosen[1], "Pick " .. left .. " more Lv." .. tostring(lvl) .. "!", C.Gold)
		end
	end
end

function FuseView.closeTray()
	chosen = {}
	clearMarks()
	stopHelper()
	if tray then
		tray.Visible = false
	end
	Hud.fuseOpen = false
	Hud.refresh()
end

-- (kept for the other views: cancelling the pick closes the tray)
function FuseView.cancel()
	FuseView.closeTray()
end

local function buildTray()
	local sg = screenGui :: ScreenGui
	local t = UI.panel({ Color = C.Plank, Radius = 20, Size = UDim2.fromOffset(700, 150), Position = UDim2.new(0.5, 0, 1, -10), AnchorPoint = Vector2.new(0.5, 1), ZIndex = 12, Visible = false, Parent = sg })
	UI.rivet(t, UDim2.new(0, 12, 0, 12))
	UI.rivet(t, UDim2.new(1, -12, 0, 12))
	UI.rivet(t, UDim2.new(0, 12, 1, -12))
	UI.rivet(t, UDim2.new(1, -12, 1, -12))
	hintLbl = UI.label({ Text = "", MaxText = 22, Size = UDim2.fromOffset(380, 26), Position = UDim2.fromOffset(20, 8), TextXAlignment = Enum.TextXAlignment.Left, Parent = t })
	-- the slots (2 for Lv1-2, then as many as the level: see Stats.fuseNeeded), built by layoutSlots
	slotArea = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(SLOT_AREA_W, 92), Position = UDim2.fromOffset(22, 42), Parent = t })
	layoutSlots(2)
	UI.label({ Text = "=", Size = UDim2.fromOffset(30, 50), Position = UDim2.fromOffset(406, 62), Parent = t })
	local res = UI.panel({ Color = Color3.fromRGB(255, 214, 232), Radius = 14, Size = UDim2.fromOffset(92, 92), Position = UDim2.fromOffset(440, 42), Parent = t })
	resultLbl = UI.label({ Text = "?", TextColor3 = PINK, Size = UDim2.new(1, -10, 0.8, 0), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = res })
	local go = UI.button({ Text = "FUSE!", Color = C.Muted, Size = UDim2.fromOffset(130, 76), Position = UDim2.fromOffset(548, 50), Parent = t }, function()
		if busy or #chosen < needed() then
			if #chosen < needed() then
				Hud.toast(if #chosen == 0 then "Pick monsters of the same level" else "Lv." .. tostring(chosen[1]:GetAttribute("Lvl")) .. " needs " .. needed() .. " monsters", C.Coral)
			end
			return
		end
		task.spawn(function()
			fuseNow()
		end)
	end)
	goBtn = go
	-- the chances plank sits on top of the tray (a child of it, so it opens / closes with it)
	local odds = UI.panel({ Color = C.Plank, Radius = 18, Size = UDim2.fromOffset(620, 134), Position = UDim2.new(0.5, 0, 0, -8), AnchorPoint = Vector2.new(0.5, 1), Visible = false, Parent = t })
	UI.rivet(odds, UDim2.new(0, 12, 0, 12))
	UI.rivet(odds, UDim2.new(1, -12, 0, 12))
	UI.label({ Text = "Fuse chances", MaxText = 20, Size = UDim2.fromOffset(240, 24), Position = UDim2.fromOffset(28, 6), TextXAlignment = Enum.TextXAlignment.Left, Parent = odds })
	oddsHeadRight = UI.label({ Text = "", TextColor3 = C.Gold, MaxText = 18, Size = UDim2.fromOffset(200, 22), Position = UDim2.new(1, -228, 0, 7), TextXAlignment = Enum.TextXAlignment.Right, Parent = odds })
	local orow = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -24, 0, 92), Position = UDim2.fromOffset(12, 34), Parent = odds })
	UI.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8), Parent = orow })
	oddsPanel = odds
	oddsRow = orow
	-- close (porthole style, like the menus)
	local ring = UI.new("Frame", { BackgroundColor3 = C.Brass, Size = UDim2.fromOffset(40, 40), Position = UDim2.new(1, 8, 0, -12), AnchorPoint = Vector2.new(1, 0), ZIndex = 14, Parent = t }, { UI.corner(40), UI.stroke(3) })
	UI.button({ Text = "X", Color = C.Coral, Radius = 30, Size = UDim2.fromOffset(30, 30), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 15, Parent = ring }, function()
		FuseView.closeTray()
	end)
	tray = t
end

function FuseView.openTray()
	if State.snapshot and State.snapshot.inBattle then
		Hud.toast("Wait for the battle to end", C.Coral)
		return
	end
	if not tray then
		buildTray()
	end
	local t = tray :: Frame
	chosen = {}
	clearMarks()
	t.Visible = true
	refreshMarks() -- fusable monsters in full colour, the others see-through
	-- the tray takes the heart button's place at the bottom of the screen
	Hud.fuseOpen = true
	Hud.refresh()
	UI.pop(t, 0.8)
	renderTray(nil)
	startHelper() -- show the way: the arrow trail to a monster, then to the FUSE! button
	Sound.play("Click", 0.6, 1.1)
end

---------------------------------------------------------------------------
-- The fuse itself
---------------------------------------------------------------------------
local function hearts(pos: Vector3)
	for _ = 1, 22 do
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.Material = Enum.Material.Neon
		p.Color = if math.random() < 0.5 then Color3.fromRGB(255, 110, 170) else Color3.fromRGB(255, 220, 90)
		p.Size = Vector3.new(0.6, 0.6, 0.6)
		p.CFrame = CFrame.new(pos)
		p.Parent = workspace
		local dir = Vector3.new(math.random() - 0.5, math.random() * 0.9 + 0.3, math.random() - 0.5).Unit
		TweenService:Create(p, TweenInfo.new(0.9), { CFrame = CFrame.new(pos + dir * 8) * CFrame.Angles(math.random() * 6, 0, 0), Size = Vector3.new(0.05, 0.05, 0.05) }):Play()
		task.delay(0.95, function()
			p:Destroy()
		end)
	end
end

-- A little glowing part used by the fuse effects
local function glowPart(shape: Enum.PartType, size: Vector3, color: Color3, cf: CFrame): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Shape = shape
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = size
	p.CFrame = cf
	p.Parent = workspace
	return p
end

-- The build-up: two energy rings turn round the meeting point and tighten, motes spiral in
-- from both monsters, and a bright core swells. Everything is gone after `dur` seconds.
fuseVfx = function(center: Vector3, colA: Color3, colB: Color3, dur: number)
	local t0 = os.clock()
	local parts: { Part } = {}
	local core = glowPart(Enum.PartType.Ball, Vector3.one * 0.5, Color3.new(1, 1, 1), CFrame.new(center))
	table.insert(parts, core)
	local rings: { Part } = {}
	for i = 1, 2 do
		local r = glowPart(Enum.PartType.Cylinder, Vector3.new(0.25, 4, 4), if i == 1 then colA else colB, CFrame.new(center))
		r.Transparency = 0.25
		table.insert(parts, r)
		table.insert(rings, r)
	end
	local motes: { { part: Part, phase: number, col: number } } = {}
	for i = 1, 24 do
		local m = glowPart(Enum.PartType.Ball, Vector3.one * 0.55, if i % 2 == 0 then colA else colB, CFrame.new(center))
		table.insert(parts, m)
		table.insert(motes, { part = m, phase = i / 24 * math.pi * 2, col = i % 2 })
	end
	local light = Instance.new("PointLight")
	light.Range = 30
	light.Brightness = 3
	light.Color = colA:Lerp(colB, 0.5)
	light.Parent = core
	task.spawn(function()
		while true do
			local k = (os.clock() - t0) / dur
			if k >= 1 then
				break
			end
			local tt = os.clock() - t0
			local e = k * k
			core.Size = Vector3.one * (0.5 + e * 6 + math.sin(tt * 30) * 0.2 * e)
			core.CFrame = CFrame.new(center)
			light.Brightness = 3 + e * 8
			for i, r in rings do
				local rad = 9 - 6 * e
				r.Size = Vector3.new(0.25, rad * 2, rad * 2)
				r.CFrame = CFrame.new(center) * CFrame.Angles(tt * (3 + i * 2) * e + i, tt * 2.2 * (if i == 1 then 1 else -1), math.rad(90))
			end
			for _, m in motes do
				-- spiral inwards: radius shrinks, speed grows
				local rad = (1 - e) * 8 + 0.6
				local a = m.phase + tt * (4 + e * 12) * (if m.col == 0 then 1 else -1)
				m.part.CFrame = CFrame.new(center + Vector3.new(math.cos(a) * rad, math.sin(a * 1.3 + m.phase) * rad * 0.6, math.sin(a) * rad))
				m.part.Size = Vector3.one * (0.55 * (1 - e * 0.6))
			end
			task.wait()
		end
		for _, p in parts do
			p:Destroy()
		end
	end)
end

-- The merge: a white flash, two shockwave rings, and a little screen punch
flash = function(center: Vector3, _dur: number)
	local f = glowPart(Enum.PartType.Ball, Vector3.one * 3, Color3.new(1, 1, 1), CFrame.new(center))
	TweenService:Create(f, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * 26, Transparency = 1 }):Play()
	task.delay(0.55, function()
		f:Destroy()
	end)
	for i = 1, 2 do
		local ring = glowPart(Enum.PartType.Cylinder, Vector3.new(0.3, 2, 2), if i == 1 then Color3.fromRGB(255, 130, 190) else Color3.fromRGB(255, 225, 120), CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)))
		TweenService:Create(ring, TweenInfo.new(0.7 + i * 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.3, 30 + i * 8, 30 + i * 8), Transparency = 1 }):Play()
		task.delay(1, function()
			ring:Destroy()
		end)
	end
	local cam = workspace.CurrentCamera
	local fov = cam.FieldOfView
	cam.FieldOfView = fov + 10
	TweenService:Create(cam, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = fov }):Play()
	Sound.play("Win", 0.6, 1.4)
end

local function fuse(list: { BasePart })
	busy = true
	local a, b = list[1], list[2]
	local uids = {}
	for i, p in list do
		uids[i] = p:GetAttribute("Uid") :: string
	end
	local spA, spB = a:GetAttribute("Sp") :: string, b:GetAttribute("Sp") :: string
	if tag then
		tag:Destroy()
		tag = nil
	end
	if tray then
		tray.Visible = false
	end
	stopHelper()
	Hud.fuseOpen = false
	Hud.refresh()
	-- both monsters lift off, spiral round each other above the first nest in a ring of
	-- energy, beams linking them, then merge in a flash
	local target = a.Position + Vector3.new(0, 3, 0)
	local center = a.Position + Vector3.new(0, 9, 0)
	local DUR = 1.7
	-- every picked monster flies up into a ring above the first nest
	for i, p in list do
		ShipView.marks[p] = "picked"
		local ang = (i - 1) / #list * math.pi * 2
		local r = if #list <= 2 then 2.5 else 3.5
		ShipView.flights[p] = { t0 = os.clock(), dur = DUR, to = center + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r) }
	end
	Sound.play("Fuse", 0.9)
	fuseVfx(center, MonsterModels.elementColor(spA), MonsterModels.elementColor(spB), DUR)
	task.wait(DUR)
	ShipView.flights[a] = nil
	flash(center, DUR)
	hearts(target)
	local ok, msg = State.action("Fuse", uids)
	for _, p in list do
		ShipView.flights[p] = nil
	end
	FuseView.closeTray()
	if not ok then
		Hud.toast(msg or "Couldn't fuse", C.Coral)
	else
		Hud.splash("FUSING!", Color3.fromRGB(255, 120, 180))
	end
	busy = false
end

fuseNow = function()
	if busy or #chosen < needed() then
		return
	end
	fuse(table.clone(chosen))
end

---------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------
local function toggle(pad: BasePart)
	local idx = table.find(chosen, pad)
	if idx then
		table.remove(chosen, idx)
		Sound.play("Click", 0.5, 0.8)
		refreshMarks()
		renderTray(nil)
		return
	end
	if #chosen > 0 and #chosen >= needed() then
		Hud.toast("All the slots are full. Press FUSE!", C.Gold)
		return
	end
	if #chosen >= 1 and pad:GetAttribute("Lvl") ~= chosen[1]:GetAttribute("Lvl") then
		Hud.toast("Pick a monster of the same level", C.Coral)
		return
	end
	table.insert(chosen, pad)
	refreshMarks()
	renderTray(#chosen) -- may add slots (Lv3+ needs more), so lay them out before the ghost flies
	flyGhost(pad, #chosen)
end

function FuseView.init()
	screenGui = player:WaitForChild("PlayerGui"):WaitForChild("TideUI") :: ScreenGui
	ProximityPromptService.PromptTriggered:Connect(function(pp: ProximityPrompt, who: Player)
		if who ~= player or pp.Name ~= "NestPrompt" or busy then
			return
		end
		local pad = pp.Parent :: BasePart
		if pad:GetAttribute("State") ~= "mon" or pad:GetAttribute("Owner") ~= player.UserId then
			return
		end
		if State.snapshot and State.snapshot.inBattle then
			Hud.toast("Wait for the battle to end", C.Coral)
			return
		end
		if not tray or not tray.Visible then
			FuseView.openTray()
		end
		toggle(pad)
	end)
	-- a picked monster changing (hatched over, fused, battle) drops it from the tray
	State.Changed:Connect(function()
		if busy then
			return
		end
		if State.snapshot and State.snapshot.inBattle and tray and tray.Visible then
			FuseView.closeTray()
			return
		end
		local changed = false
		for i = #chosen, 1, -1 do
			local c = chosen[i]
			if not c.Parent or c:GetAttribute("State") ~= "mon" then
				table.remove(chosen, i)
				changed = true
			end
		end
		if changed then
			refreshMarks()
			renderTray(nil)
		elseif #chosen == 0 and tray and tray.Visible then
			refreshMarks() -- a monster hatched / fused / levelled: who can fuse may have changed
		end
	end)
	-- with the tray open, tap / click a monster ANYWHERE on screen to pick it (no need to walk up)
	local tapStart: { [InputObject]: { pos: Vector2, t: number } } = {}
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not tray or not tray.Visible or busy then
			return
		end
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			tapStart[input] = { pos = Vector2.new(input.Position.X, input.Position.Y), t = os.clock() }
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local s = tapStart[input]
		tapStart[input] = nil
		if not s or not tray or not tray.Visible or busy then
			return
		end
		local now = Vector2.new(input.Position.X, input.Position.Y)
		-- a tap: quick and barely moved (a drag is the camera or the thumbstick)
		if os.clock() - s.t > 0.4 or (now - s.pos).Magnitude > 24 then
			return
		end
		local pad = ShipView.monsterNear(now, 110)
		if pad then
			toggle(pad)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			if tray and tray.Visible then
				FuseView.closeTray()
			end
		end
	end)
end

-- the pink Fuse button toggles the tray
function FuseView.hint()
	if tray and tray.Visible then
		FuseView.closeTray()
	else
		FuseView.openTray()
	end
end

return FuseView
