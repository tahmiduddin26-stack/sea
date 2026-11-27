--!strict
-- The Lighthouse Climb on screen (server/LighthouseService builds and runs it): a climb timer with
-- your best time while you climb, and a "Ready!" / refill countdown over each loot chest at the top.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)

local UI = require(script.Parent.UI)
local State = require(script.Parent.State)

local LighthouseView = {}

local player = Players.LocalPlayer
local C = UI.Colors

-- My own character's root + humanoid, if `hit` belongs to it
local function myHit(hit: BasePart): (BasePart?, Humanoid?)
	local char = player.Character
	if not char or not hit:IsDescendantOf(char) then
		return nil, nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or hum.Health <= 0 or not root then
		return nil, nil
	end
	return root, hum
end

-- The moving parts of the climb (anchors, barrels, lamp). These run here because a character's physics belongs to its own
-- client: a push the server sets is thrown away.
function LighthouseView.wire(inside: Instance)
	local swings: { { model: Model, pivot: CFrame, phase: number, amp: number, parts: { [BasePart]: CFrame } } } = {}
	local beams: { BasePart } = {}
	local lastKnock = 0
	local lastBounce = 0
	local hitters: { { part: BasePart, swing: any } } = {}
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	for _, d in inside:GetDescendants() do
		if d:IsA("Model") and d.Name == "SwingAnchor" then
			local s = { model = d, pivot = d:GetAttribute("Pivot") :: CFrame, phase = d:GetAttribute("Phase") :: number, amp = math.rad((d:GetAttribute("Swing") :: number?) or 65), parts = {} }
			for _, p in d:GetChildren() do
				if p:IsA("BasePart") then
					s.parts[p] = p:GetAttribute("Offset") :: CFrame
					if p:GetAttribute("Hits") ~= false then
						table.insert(hitters, { part = p, swing = s })
					end
				end
			end
			table.insert(swings, s)
		elseif d:IsA("BasePart") and d:GetAttribute("LampBeam") ~= nil then
			table.insert(beams, d)
		elseif d:IsA("BasePart") and d.Name == "BounceTop" then
			local target = d:GetAttribute("Bounce") :: Vector3
			d.Touched:Connect(function(hit)
				local root, hum = myHit(hit)
				if not root or not hum or os.clock() - lastBounce < 0.6 then
					return
				end
				lastBounce = os.clock()
				-- up and over towards the next stair
				local flat = (target - root.Position) * Vector3.new(1, 0, 1)
				local fwd = if flat.Magnitude > 0.1 then flat.Unit * math.min(20, flat.Magnitude * 1.1) else Vector3.zero
				hum:ChangeState(Enum.HumanoidStateType.Jumping)
				root.AssemblyLinearVelocity = fwd + Vector3.new(0, 82, 0)
				local Sound = require(script.Parent.Sound) :: any
				Sound.play("Splash", 0.6, 1.6)
				-- the canvas squashes
				local size = d.Size
				d.Size = Vector3.new(size.X, size.Y * 0.8, size.Z * 0.8)
				task.delay(0.15, function()
					d.Size = size
				end)
			end)
		end
	end
	RunService.Heartbeat:Connect(function()
		if not player:GetAttribute("InLighthouse") then
			return
		end
		local t = workspace:GetServerTimeNow()
		for _, s in swings do
			local c = s.pivot * CFrame.Angles(math.sin(t * 1.8 + s.phase) * s.amp, 0, 0)
			for p, off in s.parts do
				p.CFrame = c * off
			end
		end
		-- did an anchor hit me? (checked every frame: Touched is unreliable on parts moved by CFrame)
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if char and root and hum and hum.Health > 0 and os.clock() - lastKnock > 1 then
			overlap.FilterDescendantsInstances = { char }
			for _, h in hitters do
				if (h.part.Position - root.Position).Magnitude < 12 and #workspace:GetPartsInPart(h.part, overlap) > 0 then
					lastKnock = os.clock()
					-- knocked the way the anchor is swinging (its bottom moves along -Z of the pivot
					-- while the swing angle grows)
					local s = h.swing
					local growing = math.cos(t * 1.8 + s.phase) > 0
					local push = s.pivot.LookVector * (if growing then 1 else -1)
					hum:ChangeState(Enum.HumanoidStateType.FallingDown)
					root.AssemblyLinearVelocity = push * 55 + Vector3.new(0, 28, 0)
					local Sound = require(script.Parent.Sound) :: any
					Sound.play("Hit", 0.9, 0.7)
					break
				end
			end
		end
		for _, b in beams do
			local center = b:GetAttribute("Center") :: CFrame
			local k = b:GetAttribute("LampBeam") :: number
			local len = b.Size.Z
			b.CFrame = center * CFrame.Angles(0, t * 0.6 + k * math.pi, 0) * CFrame.new(0, 0, len / 2)
		end
	end)
end

function LighthouseView.init(screen: ScreenGui)
	local timer = UI.plank({ Color = C.Plank, Size = UDim2.fromOffset(300, 64), Position = UDim2.new(1, -20, 0.42, 0), AnchorPoint = Vector2.new(1, 0.5), Parent = screen })
	timer.Visible = false
	local timeLbl = UI.label({ Text = "0.0s", TextColor3 = C.Gold, Stroke = 3, MaxText = 30, Size = UDim2.new(1, -16, 0.6, 0), Position = UDim2.new(0.5, 0, 0, 4), AnchorPoint = Vector2.new(0.5, 0), Parent = timer })
	local bestLbl = UI.label({ Text = "", Stroke = 2, MaxText = 16, Size = UDim2.new(1, -16, 0.32, 0), Position = UDim2.new(0.5, 0, 1, -4), AnchorPoint = Vector2.new(0.5, 1), Parent = timer })

	-- a big Leave button, shown the whole time you are inside: the way out from any stair (falling only
	-- puts you back on a checkpoint, so without this you could never leave from halfway up)
	local leaveBtn = UI.button({ Text = "Leave", Color = C.Coral, Size = UDim2.fromOffset(190, 62), Position = UDim2.new(1, -20, 0.6, 0), AnchorPoint = Vector2.new(1, 0.5), Parent = screen }, function()
		State.action("LeaveLighthouse")
	end)
	leaveBtn.Visible = false
	player:GetAttributeChangedSignal("InLighthouse"):Connect(function()
		leaveBtn.Visible = player:GetAttribute("InLighthouse") == true
	end)
	leaveBtn.Visible = player:GetAttribute("InLighthouse") == true

	-- chest labels + the moving bits: built once the inside exists
	local labels: { [string]: TextLabel } = {}
	task.spawn(function()
		local inside = workspace:WaitForChild("LighthouseInside", 30)
		if not inside then
			return
		end
		task.wait(1) -- let every part arrive
		LighthouseView.wire(inside)
		for _, d in inside:GetDescendants() do
			local id = d:GetAttribute("ChestId")
			if typeof(id) == "string" and d:IsA("BasePart") then
				local gui = UI.new("BillboardGui", { Size = UDim2.fromOffset(150, 40), StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0), LightInfluence = 0, MaxDistance = 60, Adornee = d, Parent = player:WaitForChild("PlayerGui") })
				labels[id] = UI.label({ Text = "", Stroke = 3, MaxText = 24, Size = UDim2.fromScale(1, 1), Parent = gui })
			end
		end
	end)

	task.spawn(function()
		while true do
			local s = State.snapshot
			local start = player:GetAttribute("ObbyStart") :: number?
			timer.Visible = start ~= nil
			if start then
				timeLbl.Text = string.format("%.1fs", workspace:GetServerTimeNow() - start)
				local best = s and s.obbyBest
				bestLbl.Text = if best then string.format("Best: %.1fs", best) else "Climb to the top!"
			end
			if s and player:GetAttribute("InLighthouse") then
				for id, l in labels do
					local left = ((s.obbyAt and s.obbyAt[id]) or 0) + Config.LIGHTHOUSE.chestCooldown - State.now()
					l.Text = if left > 0 then Format.time(left) else "READY!"
					l.TextColor3 = if left > 0 then C.White else C.Kelp
				end
			end
			task.wait(if start then 0.1 else 0.5)
		end
	end)
end

return LighthouseView
