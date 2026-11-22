--!strict
-- Draws every ship's living parts from the attributes the server puts on nest pads and
-- pedestals: monsters idling on their nests, eggs with countdowns, eggs for sale with
-- prices, the egg each player carries overhead. Also filters ProximityPrompts so you only
-- see the ones that make sense on your own ship right now.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local MonsterModels = require(Shared.MonsterModels)
local Stats = require(Shared.Stats)

local UI = require(script.Parent.UI)
local State = require(script.Parent.State)

local ShipView = {}

local player = Players.LocalPlayer
local C = UI.Colors

local NEST_SCALE = 1.25
local EGG_SCALE = 1.5
local DRAW_DIST = 320

type Slot = {
	anchor: BasePart,
	sig: string,
	rig: MonsterModels.Rig?,
	egg: Model?,
	gui: BillboardGui?,
	timer: TextLabel?,
	base: CFrame,
	phase: number,
	kind: string,
}

local slots: { [BasePart]: Slot } = {}
local carried: { [Player]: { sig: string, model: Model? } } = {}
local folder = Instance.new("Folder")
folder.Name = "ShipVisuals"
folder.Parent = workspace

ShipView.hidden = {} :: { [BasePart]: boolean } -- nests whose monster is away fighting / fusing
ShipView.prompts = {} :: { [number]: { ProximityPrompt } } -- ship index -> its prompts
ShipView.marks = {} :: { [BasePart]: string } -- in-world fusing: "picked" | "ok" | "dim"
ShipView.flights = {} :: { [BasePart]: { t0: number, dur: number, to: Vector3 } } -- fuse swoops

local function tag(parent: Instance, size: UDim2, offset: Vector3): BillboardGui
	return UI.new("BillboardGui", { Size = size, StudsOffsetWorldSpace = offset, LightInfluence = 0, MaxDistance = 90, AlwaysOnTop = false, Parent = parent })
end

local function variantPrefix(v: string?): string
	if v == "Golden" then
		return '<font color="#FFCD32">Golden</font> '
	elseif v == "Rainbow" then
		return '<font color="#FF78DC">Rainbow</font> '
	end
	return ""
end

-- Eggs only show their TYPE (element, from the zone they were fished in). The species and
-- rarity stay secret until the egg hatches.
local function eggType(sp: string): string
	local def = Config.MONSTERS[sp]
	if not def then
		return "Mystery"
	end
	local names = {}
	for _, el in def.elements do
		table.insert(names, Config.ELEMENTS[el].name)
	end
	return table.concat(names, "-")
end

local function nameTag(slot: Slot, sp: string, lvl: number, stars: number, height: number, v: string?)
	local def = Config.MONSTERS[sp]
	local gui = tag(slot.anchor, UDim2.fromOffset(170, 92), Vector3.new(0, height + 1.6, 0))
	local col = MonsterModels.elementColor(sp)
	UI.label({ Text = UI.stars(stars), Size = UDim2.new(1, 0, 0.22, 0), TextColor3 = C.Gold, Parent = gui })
	UI.label({ Text = variantPrefix(v) .. (if def then def.name else sp) .. ' <font color="#FFCD32">Lv.' .. lvl .. "</font>", Size = UDim2.new(1, 0, 0.34, 0), Position = UDim2.fromScale(0, 0.22), Parent = gui })
	-- damage sticker: how hard it hits per second
	local sticker = UI.panel({ Color = Color3.fromRGB(255, 120, 100), Radius = 8, Size = UDim2.new(0.62, 0, 0.24, 0), Position = UDim2.fromScale(0.5, 0.57), AnchorPoint = Vector2.new(0.5, 0), Parent = gui })
	UI.label({ Text = "DMG " .. Format.abbrev(math.floor(Stats.dps(sp, lvl, nil, v) + 0.5)) .. "/s", Size = UDim2.new(1, -6, 0.82, 0), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Parent = sticker })
	local row = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0.17, 0), Position = UDim2.fromScale(0, 0.83), Parent = gui })
	UI.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 4), Parent = row })
	if def then
		for _, el in def.elements do
			UI.new("Frame", { Size = UDim2.fromOffset(14, 14), BackgroundColor3 = Config.ELEMENTS[el].color, Parent = row }, { UI.corner(7), UI.stroke(2) })
		end
	end
	local _ = col
	slot.gui = gui
end

local function clearSlot(slot: Slot)
	if slot.rig then
		slot.rig.model:Destroy()
		slot.rig = nil
	end
	if slot.egg then
		slot.egg:Destroy()
		slot.egg = nil
	end
	if slot.gui then
		slot.gui:Destroy()
		slot.gui = nil
	end
	slot.timer = nil
end

local function nestSig(pad: BasePart): string
	return table.concat({
		tostring(pad:GetAttribute("State")),
		tostring(pad:GetAttribute("Sp")),
		tostring(pad:GetAttribute("Lvl")),
		tostring(pad:GetAttribute("Stars")),
		tostring(pad:GetAttribute("Price")),
		tostring(pad:GetAttribute("Variant")),
	}, "|")
end

local function buildNest(slot: Slot)
	local pad = slot.anchor
	clearSlot(slot)
	local state = pad:GetAttribute("State")
	local sp = pad:GetAttribute("Sp") :: string?
	local lvl = (pad:GetAttribute("Lvl") or 1) :: number
	local stars = (pad:GetAttribute("Stars") or 1) :: number
	slot.kind = tostring(state)
	if state == "mon" and sp then
		local rig = MonsterModels.build(sp, NEST_SCALE)
		if rig then
			rig.model.Parent = folder
			slot.rig = rig
			MonsterModels.addAura(rig, stars)
			MonsterModels.applyVariant(rig, pad:GetAttribute("Variant") :: string?)
			local foot = MonsterModels.footDepth(rig)
			slot.base = pad.CFrame * CFrame.new(0, pad.Size.Y / 2 + foot, 0) * CFrame.Angles(0, math.rad(180), 0)
			nameTag(slot, sp, lvl, stars, MonsterModels.height(rig) + foot, pad:GetAttribute("Variant") :: string?)
		end
	elseif (state == "egg" or state == "fuse") and sp then
		local egg = MonsterModels.buildEgg(sp, EGG_SCALE, state == "fuse")
		egg.Parent = folder
		slot.egg = egg
		slot.base = pad.CFrame * CFrame.new(0, pad.Size.Y / 2 + 0.85 * EGG_SCALE, 0)
		local gui = tag(pad, UDim2.fromOffset(150, 70), Vector3.new(0, 4.2, 0))
		local def = Config.MONSTERS[sp]
		local title = if state == "fuse" then "Fusing..." else (eggType(sp) .. " Egg")
		local _ = def
		UI.label({ Text = title .. ' <font color="#FFCD32">Lv.' .. lvl .. "</font>", Size = UDim2.new(1, 0, 0.42, 0), Parent = gui })
		slot.timer = UI.label({ Text = "", Size = UDim2.new(1, 0, 0.55, 0), Position = UDim2.fromScale(0, 0.45), TextColor3 = C.Gold, Parent = gui })
		slot.gui = gui
	elseif state == "locked" then
		-- a small coin + price chip floating over the empty nest, sized in studs
		local gui = UI.new("BillboardGui", { Size = UDim2.fromScale(4.2, 1.4), StudsOffsetWorldSpace = Vector3.new(0, 1.6, 0), LightInfluence = 0, MaxDistance = 120, Parent = pad })
		UI.new("ImageLabel", { BackgroundTransparency = 1, Image = Config.ICONS.Coin, Size = UDim2.fromScale(0.34, 1), SizeConstraint = Enum.SizeConstraint.RelativeYY, Parent = gui })
		UI.label({ Text = Format.abbrev((pad:GetAttribute("Price") or 0) :: number), TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromScale(0.64, 0.9), Position = UDim2.fromScale(0.36, 0.05), TextColor3 = C.Gold, Parent = gui })
		slot.gui = gui
	end
end

local function pedSig(ped: BasePart): string
	return table.concat({ tostring(ped:GetAttribute("Sp")), tostring(ped:GetAttribute("Lvl")), tostring(ped:GetAttribute("Stars")), tostring(ped:GetAttribute("Price")), tostring(ped:GetAttribute("Active")), tostring(ped:GetAttribute("Variant")) }, "|")
end

local function buildPedestal(slot: Slot)
	local ped = slot.anchor
	clearSlot(slot)
	local sp = ped:GetAttribute("Sp") :: string?
	if not sp then
		return
	end
	local lvl = (ped:GetAttribute("Lvl") or 1) :: number
	local stars = (ped:GetAttribute("Stars") or 1) :: number
	local egg = MonsterModels.buildEgg(sp, EGG_SCALE)
	egg.Parent = folder
	slot.egg = egg
	slot.base = ped.CFrame * CFrame.new(0, ped.Size.Y / 2 + 1.6 * EGG_SCALE, 0)
	local def = Config.MONSTERS[sp]
	local gui = tag(ped, UDim2.fromOffset(170, 86), Vector3.new(0, 6.2, 0))
	local _ = stars
	UI.label({ Text = variantPrefix(ped:GetAttribute("Variant") :: string?) .. eggType(sp) .. ' Egg <font color="#FFCD32">Lv.' .. lvl .. "</font>", Size = UDim2.new(1, 0, 0.36, 0), Position = UDim2.fromScale(0, 0.24), Parent = gui })
	UI.label({ Text = "Rarity: ???", TextColor3 = C.Muted, Size = UDim2.new(1, 0, 0.22, 0), Position = UDim2.fromScale(0, 0.02), Parent = gui })
	local priceNum = (ped:GetAttribute("Price") or 0) :: number
	if priceNum > 0 then
		UI.label({ Text = Format.abbrev(priceNum) .. " Coins", Size = UDim2.new(1, 0, 0.36, 0), Position = UDim2.fromScale(0, 0.62), TextColor3 = C.Gold, Parent = gui })
	else
		UI.label({ Text = "Take it!", Size = UDim2.new(1, 0, 0.36, 0), Position = UDim2.fromScale(0, 0.62), TextColor3 = C.Kelp, Parent = gui })
	end
	slot.gui = gui
	UI.pop(gui :: any)
	-- my own hauls roll like a slot reel before landing
	if ped:GetAttribute("Owner") == player.UserId then
		local finalColors = {}
		for _, d in egg:GetChildren() do
			if d:IsA("BasePart") then
				finalColors[d] = d.Color
			end
		end
		local labels = {}
		for _, l in gui:GetChildren() do
			if l:IsA("TextLabel") then
				l.Visible = false
				table.insert(labels, l)
			end
		end
		-- it lands black (the egg you fished up), shakes, then light cracks out in its type colour
		local reel = UI.label({ Text = "???", TextColor3 = C.White, MaxText = 40, Size = UDim2.new(1, 0, 0.5, 0), Position = UDim2.fromScale(0, 0.25), Parent = gui })
		task.spawn(function()
			local Sound = require(script.Parent.Sound) :: any
			for part in finalColors do
				part.Color = Color3.fromRGB(25, 25, 35)
			end
			local t0 = os.clock()
			local k = 0
			while os.clock() - t0 < 0.9 and egg.Parent do
				k += 1
				reel.Text = string.rep(".", k % 4) .. "?"
				Sound.play("Click", 0.25, 0.8 + k * 0.05)
				task.wait(0.12)
			end
			local first = next(finalColors)
			local col = if first then finalColors[first] else C.White
			for part in finalColors do
				part.Color = Color3.new(1, 1, 1)
				part.Material = Enum.Material.Neon
			end
			reel.Text = string.upper(eggType(sp)) .. " EGG!"
			reel.TextColor3 = col
			Sound.play("Super", 0.6, 1.2)
			task.wait(0.25)
			for part in finalColors do
				part.Material = Enum.Material.SmoothPlastic
			end
			task.wait(0.5)
			for part, c in finalColors do
				part.Color = c
			end
			reel:Destroy()
			for _, l in labels do
				l.Visible = true
			end
			UI.pop(gui :: any, 0.5)
			local v = ped:GetAttribute("Variant")
			local Hud = require(script.Parent.Hud) :: any
			if v == "Rainbow" or v == "Golden" then
				Hud.splash(string.upper(v) .. " EGG!", if v == "Golden" then C.Gold else C.Pearl)
				Sound.play("Win", 0.8)
			end
		end)
	end
end

local function watch(anchor: BasePart, kind: string)
	local slot: Slot = { anchor = anchor, sig = "", rig = nil, egg = nil, gui = nil, timer = nil, base = anchor.CFrame, phase = math.random() * 10, kind = "" }
	slots[anchor] = slot
	local function refresh()
		local sig = if kind == "nest" then nestSig(anchor) else pedSig(anchor)
		if sig ~= slot.sig then
			slot.sig = sig
			if kind == "nest" then
				buildNest(slot)
			else
				buildPedestal(slot)
			end
		end
	end
	anchor.AttributeChanged:Connect(refresh)
	refresh()
end

-- Every ship's boarding gate is solid for everyone but its crew (collision groups, server side);
-- on your own ship the gate is hidden so it never looks like a wall to you
local gates: { [number]: BasePart } = {}
local function filterGates()
	local myShip = player:GetAttribute("Ship")
	for idx, gate in gates do
		local mine = idx == myShip
		gate.LocalTransparencyModifier = if mine then 1 else 0
		local gl = gate:FindFirstChild("GateLabel") :: BillboardGui?
		if gl then
			gl.Enabled = not mine
		end
	end
end

-- Prompts: only on your ship, and only the ones that fit what you're doing
local nestsFullWarned = false
local function filterPrompts()
	local snap = State.snapshot
	local myShip = player:GetAttribute("Ship")
	local carrying = player:GetAttribute("Carrying") ~= nil
	-- holding an egg with every nest taken: say what to do (once per egg)
	if carrying and myShip then
		local world = workspace:FindFirstChild("World")
		local ship = world and world:FindFirstChild("Ship" .. tostring(myShip))
		local free = false
		if ship then
			for _, d in ship:GetDescendants() do
				if d:IsA("BasePart") and d:GetAttribute("NestIndex") and d:GetAttribute("State") == "empty" then
					free = true
					break
				end
			end
		end
		if not free and not nestsFullWarned then
			nestsFullWarned = true
			local Hud = require(script.Parent.Hud) :: any
			Hud.toast("Nests full! Buy a new nest or FUSE two monsters to free one", C.Coral)
		end
	else
		nestsFullWarned = false
	end
	for shipIdx, list in ShipView.prompts do
		do
			local mine = shipIdx == myShip
			for _, pp in list do
				do
					local show = mine
					local parent = pp.Parent :: Instance
					if mine and pp.Name == "NestPrompt" then
						local state = parent:GetAttribute("State")
						if state == "empty" then
							show = carrying
						elseif state == "locked" then
							-- you can buy a nest even while holding an egg (that's when you need one)
							show = snap ~= nil and snap.tutorial >= Config.HUD_UNLOCK_STEP
						end
					elseif mine and pp.Name == "BuyPrompt" then
						show = not carrying
					elseif mine and pp.Name == "WinchPrompt" then
						show = true -- you can always fish, even holding an egg
					elseif mine and pp.Name == "UpgradePrompt" then
						show = snap ~= nil and snap.tutorial >= Config.HUD_UNLOCK_STEP
					end
					-- the server says whether a prompt is live; the client owns Enabled
					pp.Enabled = show and pp:GetAttribute("Live") ~= false
				end
			end
		end
	end
end

local function carriedSig(p: Player): string
	return tostring(p:GetAttribute("Carrying"))
end

local function updateCarried(p: Player)
	local c = carried[p] or { sig = "", model = nil }
	carried[p] = c
	local sig = carriedSig(p)
	if sig == c.sig then
		return
	end
	c.sig = sig
	if c.model then
		c.model:Destroy()
		c.model = nil
	end
	local val = p:GetAttribute("Carrying") :: string?
	if p == player then
		local Sound = require(script.Parent.Sound) :: any
		Sound.play(if val then "Buy" else "Place", 0.7)
	end
	if val then
		local sp = string.split(val, ":")[1]
		local egg = MonsterModels.buildEgg(sp, 1.2)
		egg.Parent = folder
		c.model = egg
	end
end

function ShipView.init()
	local world = workspace:WaitForChild("World")
	local function scan(ship: Instance)
		for _, d in ship:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("NestIndex") then
				watch(d, "nest")
			elseif d:IsA("BasePart") and d:GetAttribute("PedestalIndex") then
				watch(d, "ped")
			elseif d:IsA("BasePart") and d.Name == "ShipGate" then
				gates[ship:GetAttribute("ShipIndex") :: number] = d
			elseif d:IsA("ProximityPrompt") then
				local idx = ship:GetAttribute("ShipIndex") :: number
				ShipView.prompts[idx] = ShipView.prompts[idx] or {}
				table.insert(ShipView.prompts[idx], d)
			end
		end
	end
	local function onChild(ship: Instance)
		if ship:GetAttribute("ShipIndex") then
			task.defer(scan, ship)
		end
	end
	for _, ship in world:GetChildren() do
		onChild(ship)
	end
	world.ChildAdded:Connect(onChild)

	for _, p in Players:GetPlayers() do
		p:GetAttributeChangedSignal("Carrying"):Connect(function()
			updateCarried(p)
		end)
		updateCarried(p)
	end
	Players.PlayerAdded:Connect(function(p)
		p:GetAttributeChangedSignal("Carrying"):Connect(function()
			updateCarried(p)
		end)
	end)
	Players.PlayerRemoving:Connect(function(p)
		local c = carried[p]
		if c and c.model then
			c.model:Destroy()
		end
		carried[p] = nil
	end)

	local lastFilter = 0
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		local cam = workspace.CurrentCamera.CFrame.Position
		local now = State.now()
		for anchor, slot in slots do
			local near = (anchor.Position - cam).Magnitude < DRAW_DIST
			local hide = ShipView.hidden[anchor] == true or anchor:GetAttribute("InBattle") == true
			if slot.rig then
				slot.rig.model.Parent = if near and not hide then folder else nil
				if near and not hide then
					local mark = ShipView.marks[anchor]
					local cf = slot.base
					local fly = ShipView.flights[anchor]
					if fly then
						-- swoop through the air to the target nest, spinning
						local k = math.clamp((t - fly.t0) / fly.dur, 0, 1)
						local e = k * k * (3 - 2 * k)
						local pos = slot.base.Position:Lerp(fly.to, e) + Vector3.new(0, math.sin(k * math.pi) * 9, 0)
						cf = CFrame.new(pos) * slot.base.Rotation * CFrame.Angles(0, k * math.pi * 4, 0)
					elseif mark == "picked" then
						cf = slot.base * CFrame.new(0, 2.2 + math.sin(t * 4) * 0.4, 0) * CFrame.Angles(0, math.sin(t * 2) * 0.3, 0)
					elseif mark == "ok" then
						cf = slot.base * CFrame.new(0, math.abs(math.sin(t * 5)) * 0.6, 0)
					end
					MonsterModels.pose(slot.rig, cf, t + slot.phase, mark == "picked" or fly ~= nil, true)
				end
				-- highlight: gold = picked, green = a valid partner, faded = can't fuse with it
				local mark = ShipView.marks[anchor]
				local hl = slot.rig.model:FindFirstChild("FuseMark") :: Highlight?
				if mark and mark ~= "dim" then
					if not hl then
						hl = Instance.new("Highlight")
						hl.Name = "FuseMark"
						hl.DepthMode = Enum.HighlightDepthMode.Occluded
						hl.Parent = slot.rig.model
					end
					local h = hl :: Highlight
					h.FillColor = if mark == "picked" then C.Gold else C.Kelp
					h.OutlineColor = h.FillColor
					h.FillTransparency = 0.78 + math.sin(t * 6) * 0.1
					h.OutlineTransparency = 0
				elseif hl then
					hl:Destroy()
				end
				local dimNow = mark == "dim"
				if (slot :: any).dimmed ~= dimNow then
					(slot :: any).dimmed = dimNow
					MonsterModels.fade(slot.rig, if dimNow then 0.6 else 0)
				end
			end
			if slot.gui then
				slot.gui.Enabled = not hide
			end
			if slot.egg then
				slot.egg.Parent = if near and not hide then folder else nil
				local wob = 0
				local ready = false
				if slot.timer then
					local left = ((anchor:GetAttribute("ReadyAt") or 0) :: number) - now
					ready = left <= 0
					slot.timer.Text = if ready then "Ready!" else Format.time(left)
					slot.timer.TextColor3 = if ready then C.Kelp else C.Gold
					wob = if ready then math.sin(t * 9) * 0.12 else math.sin(t * 2) * 0.03
				end
				local spin = if slot.kind == "" then t * 0.8 else 0 -- pedestal eggs turn slowly
				local bob = if slot.timer then 0 else math.sin(t * 2 + slot.phase) * 0.3
				slot.egg:PivotTo(slot.base * CFrame.new(0, bob, 0) * CFrame.Angles(0, spin, wob))
			end
		end
		for p, c in carried do
			local char = p.Character
			local head = char and char:FindFirstChild("Head") :: BasePart?
			if c.model and head then
				c.model:PivotTo(CFrame.new(head.Position + Vector3.new(0, 2.8 + math.sin(t * 4) * 0.15, 0)) * CFrame.Angles(0, t * 1.5, 0))
			end
		end
		if t - lastFilter > 0.2 then
			lastFilter = t
			filterPrompts()
			filterGates()
		end
	end)
end

-- World position of one of my nests / pedestals / the winch (tutorial arrows, camera)
function ShipView.myShip(): Model?
	local idx = player:GetAttribute("Ship")
	local world = workspace:FindFirstChild("World")
	if not idx or not world then
		return nil
	end
	return world:FindFirstChild("Ship" .. idx) :: Model?
end

return ShipView
