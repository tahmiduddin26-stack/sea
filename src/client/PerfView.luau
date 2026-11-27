--!strict
-- Keeps the game cool and smooth on phones (a hot phone throttles and the frame rate drops).
-- The world is big: ~22,000 parts, ~1,100 lights (most of them down the fishing trenches) and nearly every
-- part casts a shadow. A phone cannot afford that, so:
--   * lights far from the camera are switched off (the trench lights only matter during a dive)
--   * the underwater shafts of the ships and the lighthouse interior are lifted out of the world until you are near
--   * on phones the depth-of-field and sun-rays screen effects are off
--   * on a touch device real-time shadows are off and lights cast none
--   * PerfView.mobile tells the other views to use shorter draw distances

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local PerfView = {}

-- a phone / tablet without a keyboard (consoles and PCs have the headroom)
PerfView.mobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local LIGHT_RADIUS = if PerfView.mobile then 120 else 260 -- lights farther than this (from the camera) are off

type Tracked = { light: Light, want: boolean, on: boolean }
local tracked: { Tracked } = {}
local seen: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function track(d: Instance)
	if (d:IsA("PointLight") or d:IsA("SpotLight")) and not seen[d] then
		seen[d] = true
		if PerfView.mobile then
			d.Shadows = false
		end
		table.insert(tracked, { light = d, want = d.Enabled, on = d.Enabled })
	end
end

-- Big pieces of scenery that you only see up close (about 11,000 of the world's 18,500 parts are the
-- underwater shafts below the six ships; the lighthouse interior is another 1,700). While the camera is
-- far from one, it is lifted out of the world (parent = nil, local to this client only) and put back when
-- you come near, so the renderer and physics never touch it.
type Cull = { model: Model, home: Instance, cf: CFrame, half: Vector3, radius: number, shown: boolean, keep: (() -> boolean)? }
local culls: { Cull } = {}
local culled: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local SHAFT_RADIUS = if PerfView.mobile then 100 else 200 -- studs from the camera to the shaft's box

local function addCull(model: Model, radius: number, keep: (() -> boolean)?)
	if culled[model] or not model.Parent then
		return
	end
	culled[model] = true
	local cf, size = model:GetBoundingBox()
	table.insert(culls, { model = model, home = model.Parent, cf = cf, half = size / 2, radius = radius, shown = true, keep = keep })
end

local function considerShaft(d: Instance)
	if d:IsA("Model") and (d.Name == "Trench" or d.Name == "DeepTrench" or d.Name == "AbyssTrench") and d.Parent and string.match(d.Parent.Name, "^Ship%d+$") then
		addCull(d, SHAFT_RADIUS, nil)
	end
end

local function boxDistance(c: Cull, p: Vector3): number
	local l = c.cf:PointToObjectSpace(p)
	return Vector3.new(math.max(math.abs(l.X) - c.half.X, 0), math.max(math.abs(l.Y) - c.half.Y, 0), math.max(math.abs(l.Z) - c.half.Z, 0)).Magnitude
end

-- one change per call (re-parenting hundreds of parts is a small hitch; never do several in a frame)
local function updateCulls(camPos: Vector3)
	local i = 1
	while i <= #culls do
		local c = culls[i]
		local gone = if c.shown then not c.model.Parent else not c.home.Parent
		if gone then
			culls[i] = culls[#culls]
			culls[#culls] = nil
			continue
		end
		local near = boxDistance(c, camPos) < (if c.shown then c.radius * 1.2 else c.radius)
		if not near and c.keep and c.keep() then
			near = true
		end
		if near ~= c.shown then
			c.shown = near
			c.model.Parent = if near then c.home else nil
			return
		end
		i += 1
	end
end

local function lightPos(l: Light): Vector3?
	local p = l.Parent
	if p and p:IsA("BasePart") then
		return p.Position
	elseif p and p:IsA("Attachment") then
		return p.WorldPosition
	end
	return nil
end

function PerfView.init()
	if PerfView.mobile then
		Lighting.GlobalShadows = false
		-- the two costliest screen effects; bloom, colour grading and the atmosphere stay, so it still looks like the game
		for _, e in Lighting:GetChildren() do
			if e:IsA("DepthOfFieldEffect") or e:IsA("SunRaysEffect") then
				local fx: any = e
				fx.Enabled = false
			end
		end
	end
	task.spawn(function()
		local world = workspace:WaitForChild("World")
		task.wait(2) -- the world finishes building a moment after the server starts
		for _, d in workspace:GetDescendants() do
			track(d)
			considerShaft(d)
		end
		world.DescendantAdded:Connect(function(d)
			track(d)
			if d:IsA("Model") then
				task.delay(2, considerShaft, d) -- its parts arrive with it; measure once they have
			end
		end)
		-- the lighthouse interior sits 5,000 studs out: only there once you walk up to the door (or are inside)
		task.spawn(function()
			local player = Players.LocalPlayer
			local inside = workspace:WaitForChild("LighthouseInside", 60)
			local door = world:FindFirstChild("LighthouseEnter", true) :: BasePart?
			if not inside or not inside:IsA("Model") then
				return
			end
			task.wait(4) -- LighthouseView wires its moving parts first
			addCull(inside, 400, function()
				if player:GetAttribute("InLighthouse") then
					return true
				end
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				return door ~= nil and root ~= nil and (root.Position - door.Position).Magnitude < 170
			end)
		end)
		while true do
			local cam = workspace.CurrentCamera
			if cam then
				local camPos = cam.CFrame.Position
				updateCulls(camPos)
				local i = 1
				while i <= #tracked do
					local t = tracked[i]
					if not t.light.Parent then
						tracked[i] = tracked[#tracked]
						tracked[#tracked] = nil
					else
						local pos = lightPos(t.light)
						if pos then
							local d = (pos - camPos).Magnitude - t.light.Range
							-- a little hysteresis so a light at the edge doesn't flicker
							local on = if t.on then d < LIGHT_RADIUS * 1.15 else d < LIGHT_RADIUS
							if on ~= t.on then
								t.on = on
								t.light.Enabled = on and t.want
							end
						end
						i += 1
					end
				end
			end
			task.wait(0.5)
		end
	end)
end

return PerfView
