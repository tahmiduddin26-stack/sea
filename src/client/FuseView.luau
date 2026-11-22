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
local fuseNow: () -> () = function() end -- set below, once the fuse itself is defined

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

local function clearMarks()
	for k in ShipView.marks do
		ShipView.marks[k] = nil
	end
	if tag then
		tag:Destroy()
		tag = nil
	end
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

local function creatureView(parent: GuiObject, sp: string, size: UDim2): ViewportFrame
	local vp = UI.new("ViewportFrame", { BackgroundTransparency = 1, Size = size, Ambient = Color3.fromRGB(200, 200, 210), LightColor = Color3.new(1, 1, 1), LightDirection = Vector3.new(-1, -1, -1), Parent = parent })
	local rig = MonsterModels.build(sp, 1)
	if not rig then
		return vp
	end
	rig.model.Parent = vp
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

local function renderTray(newIndex: number?)
	if not tray then
		return
	end
	for i = 1, 2 do
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
	local ready = #chosen == 2
	local hint = hintLbl :: TextLabel
	if #chosen == 0 then
		hint.Text = "Tap a monster to fuse"
	elseif #chosen == 1 then
		hint.Text = "Now pick another <font color=\"#FFCD32\">Lv." .. tostring(chosen[1]:GetAttribute("Lvl")) .. "</font>"
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
		return
	end
	local lvl = chosen[1]:GetAttribute("Lvl")
	for _, c in chosen do
		ShipView.marks[c] = "picked"
	end
	local partners = 0
	for _, n in myNests() do
		if not table.find(chosen, n) and n:GetAttribute("State") == "mon" then
			if #chosen < 2 and n:GetAttribute("Lvl") == lvl then
				ShipView.marks[n] = "ok"
				partners += 1
			else
				ShipView.marks[n] = "dim"
			end
		end
	end
	if #chosen == 1 then
		if partners == 0 then
			tag = floatTag(chosen[1], "Need another Lv." .. tostring(lvl) .. "!", C.Coral)
			Hud.toast("Hatch another Lv." .. tostring(lvl) .. " monster to fuse with it", C.Coral)
		else
			tag = floatTag(chosen[1], "Pick another Lv." .. tostring(lvl) .. "!", C.Gold)
		end
	end
end

function FuseView.closeTray()
	chosen = {}
	clearMarks()
	if tray then
		tray.Visible = false
	end
end

-- (kept for the other views: cancelling the pick closes the tray)
function FuseView.cancel()
	FuseView.closeTray()
end

local function buildTray()
	local sg = screenGui :: ScreenGui
	local t = UI.panel({ Color = C.Plank, Radius = 20, Size = UDim2.fromOffset(580, 150), Position = UDim2.new(0.5, 0, 1, -146), AnchorPoint = Vector2.new(0.5, 1), ZIndex = 12, Visible = false, Parent = sg })
	UI.rivet(t, UDim2.new(0, 12, 0, 12))
	UI.rivet(t, UDim2.new(1, -12, 0, 12))
	UI.rivet(t, UDim2.new(0, 12, 1, -12))
	UI.rivet(t, UDim2.new(1, -12, 1, -12))
	hintLbl = UI.label({ Text = "", MaxText = 22, Size = UDim2.fromOffset(380, 26), Position = UDim2.fromOffset(20, 8), TextXAlignment = Enum.TextXAlignment.Left, Parent = t })
	for i = 1, 2 do
		local box = UI.panel({ Color = Color3.fromRGB(255, 236, 214), Radius = 14, Size = UDim2.fromOffset(92, 92), Position = UDim2.fromOffset(22 + (i - 1) * 140, 42), Parent = t })
		UI.label({ Name = "Q", Text = "?", TextColor3 = Color3.fromRGB(190, 120, 80), Size = UDim2.fromScale(0.5, 0.5), Position = UDim2.fromScale(0.25, 0.25), Parent = box })
		slotBoxes[i] = box
	end
	UI.label({ Text = "+", Size = UDim2.fromOffset(36, 50), Position = UDim2.fromOffset(116, 62), Parent = t })
	UI.label({ Text = "=", Size = UDim2.fromOffset(36, 50), Position = UDim2.fromOffset(256, 62), Parent = t })
	local res = UI.panel({ Color = Color3.fromRGB(255, 214, 232), Radius = 14, Size = UDim2.fromOffset(92, 92), Position = UDim2.fromOffset(302, 42), Parent = t })
	resultLbl = UI.label({ Text = "?", TextColor3 = PINK, Size = UDim2.new(1, -10, 0.8, 0), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = res })
	local go = UI.button({ Text = "FUSE!", Color = C.Muted, Size = UDim2.fromOffset(140, 76), Position = UDim2.fromOffset(418, 50), Parent = t }, function()
		if busy or #chosen < 2 then
			if #chosen < 2 then
				Hud.toast("Pick two monsters of the same level", C.Coral)
			end
			return
		end
		task.spawn(function()
			fuseNow()
		end)
	end)
	goBtn = go
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
	UI.pop(t, 0.8)
	renderTray(nil)
	Sound.play("Click", 0.6, 1.1)
end

---------------------------------------------------------------------------
-- The fuse itself
---------------------------------------------------------------------------
-- The odds pop up over the pair for a moment while they fly together
local function showOdds(at: BasePart, spA: string, spB: string, lvl: number)
	local snap = State.snapshot
	local luck = if (snap.luckUntil or 0) > State.now() then snap.luckMult else 1
	local outs = Stats.fuseOutcomes(spA, spB, lvl, luck)
	local gui = UI.new("BillboardGui", { Size = UDim2.fromScale(12, 2.6), StudsOffsetWorldSpace = Vector3.new(0, 12, 0), LightInfluence = 0, AlwaysOnTop = true, MaxDistance = 140, Parent = at })
	local row = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
	UI.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0.02, 0), Parent = row })
	for i, o in outs do
		if i > 4 then
			break
		end
		local def = Config.MONSTERS[o.sp]
		local r = Config.RARITY[def.stars]
		local cell = UI.new("Frame", { BackgroundColor3 = Color3.fromRGB(20, 30, 60), BackgroundTransparency = 0.15, Size = UDim2.fromScale(0.23, 1) }, { UI.corner(10), UI.stroke(3, r.color) })
		UI.label({ Text = if snap.index[o.sp] then def.name else "???", TextColor3 = r.color, MaxText = 18, Size = UDim2.fromScale(0.94, 0.5), Position = UDim2.fromScale(0.03, 0.05), Parent = cell })
		UI.label({ Text = math.floor(o.chance * 1000 + 0.5) / 10 .. "%", TextColor3 = C.Gold, MaxText = 20, Size = UDim2.fromScale(1, 0.42), Position = UDim2.fromScale(0, 0.55), Parent = cell })
		cell.Parent = row
	end
	task.delay(2.2, function()
		gui:Destroy()
	end)
end

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

local function fuse(a: BasePart, b: BasePart)
	busy = true
	local uidA, uidB = a:GetAttribute("Uid") :: string, b:GetAttribute("Uid") :: string
	local spA, spB = a:GetAttribute("Sp") :: string, b:GetAttribute("Sp") :: string
	local lvl = a:GetAttribute("Lvl") :: number
	if tag then
		tag:Destroy()
		tag = nil
	end
	if tray then
		tray.Visible = false
	end
	showOdds(a, spA, spB, lvl)
	-- both swoop into the first nest
	local target = a.Position + Vector3.new(0, 3, 0)
	ShipView.marks[a] = "picked"
	ShipView.marks[b] = "picked"
	ShipView.flights[b] = { t0 = os.clock(), dur = 0.9, to = target }
	Sound.play("Fuse", 0.9)
	task.wait(0.9)
	hearts(target)
	local ok, msg = State.action("Fuse", { uidA, uidB })
	ShipView.flights[b] = nil
	FuseView.closeTray()
	if not ok then
		Hud.toast(msg or "Couldn't fuse", C.Coral)
	else
		Hud.splash("FUSING!", Color3.fromRGB(255, 120, 180))
	end
	busy = false
end

fuseNow = function()
	if busy or #chosen < 2 then
		return
	end
	fuse(chosen[1], chosen[2])
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
	if #chosen >= 2 then
		Hud.toast("Both slots are full. Press FUSE!", C.Gold)
		return
	end
	if #chosen == 1 and pad:GetAttribute("Lvl") ~= chosen[1]:GetAttribute("Lvl") then
		Hud.toast("Pick a monster of the same level", C.Coral)
		return
	end
	table.insert(chosen, pad)
	refreshMarks()
	flyGhost(pad, #chosen)
	renderTray(#chosen)
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
