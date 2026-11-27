--!strict
-- The treasure-dig cinematic. While you hold the Dig prompt on an X mark, the game plays the clip
-- authored in Blender (assets/dig/build_dig_anim.py, baked to shared/DigAnim): you stand at the mark
-- with a shovel, lean in and stab the ground three times, dirt flies over your shoulder, a glow swells
-- out of the hole, and the camera swings round the hole. Let go early and it stops; hold to the end
-- and the server hands over the treasure (server/TreasureService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Anim = require(Shared.DigAnim)

local Sound = require(script.Parent.Sound)
local State = require(script.Parent.State)

local DigView = {}

local player = Players.LocalPlayer
local SHOVEL_PARTS = { { off = CFrame.identity, size = Vector3.new(0.32, 0.32, 5), color = Color3.fromRGB(140, 92, 52), mat = Enum.Material.Wood },
	{ off = CFrame.new(0, 0, -2.9), size = Vector3.new(1.5, 0.18, 1.9), color = Color3.fromRGB(160, 166, 175), mat = Enum.Material.Metal },
	{ off = CFrame.new(0, 0, 2.5), size = Vector3.new(0.9, 0.3, 0.3), color = Color3.fromRGB(140, 92, 52), mat = Enum.Material.Wood } }

local active: { stop: (success: boolean) -> (), began: number }? = nil

local function sample(track: { number }, stride: number, t: number): (number, { number })
	local f = math.clamp(t * Anim.FPS, 0, Anim.FRAMES - 1)
	local f0 = math.floor(f)
	local f1 = math.min(f0 + 1, Anim.FRAMES - 1)
	local a = f - f0
	local out = table.create(stride, 0)
	for k = 1, stride do
		local v0 = track[f0 * stride + k]
		local v1 = track[f1 * stride + k]
		out[k] = v0 + (v1 - v0) * a
	end
	return a, out
end

local function cframeOf(v: { number }): CFrame
	return CFrame.new(v[1], v[2], v[3], v[4], v[5], v[6], v[7]) -- (CFrame.new(x,y,z,qx,qy,qz,qw))
end

local function part(size: Vector3, color: Color3, mat: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = mat
	p.Shape = shape or Enum.PartType.Block
	return p
end

local function start(prompt: ProximityPrompt)
	if active then
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local anchor = prompt.Parent
	if not char or not root or not hum or not anchor or not anchor:IsA("BasePart") then
		return
	end
	-- the mark on the ground (the prompt's anchor floats 1.5 above it) and the frame of the clip: -Z
	-- points from the digger towards the hole
	local mark = anchor.Position - Vector3.new(0, 1.5, 0)
	local toPlayer = Vector3.new(root.Position.X - mark.X, 0, root.Position.Z - mark.Z)
	toPlayer = if toPlayer.Magnitude > 0.1 then toPlayer.Unit else Vector3.zAxis
	local frame = CFrame.lookAt(mark, mark - toPlayer)

	-- stand where the clip wants you (3.2 studs back from the mark) and face the hole
	local standAt = mark + toPlayer * 3.2 + Vector3.new(0, root.Position.Y - mark.Y, 0)
	local savedSpeed, savedRotate = hum.WalkSpeed, hum.AutoRotate
	hum.WalkSpeed = 0
	hum.AutoRotate = false
	root.CFrame = CFrame.lookAt(standAt, Vector3.new(mark.X, standAt.Y, mark.Z))
	root.AssemblyLinearVelocity = Vector3.zero

	-- the props
	local folder = Instance.new("Folder")
	folder.Name = "DigFx"
	folder.Parent = workspace
	local shovel = {}
	for _, s in SHOVEL_PARTS do
		local p = part(s.size, s.color, s.mat)
		p.Parent = folder
		table.insert(shovel, { part = p, off = s.off })
	end
	local dirt: { Part } = {}
	for i = 1, Anim.DIRT do
		local d = part(Vector3.one, Color3.fromRGB(112, 76, 42), Enum.Material.Ground)
		d.Parent = folder
		dirt[i] = d
	end
	local glow = part(Vector3.one, Color3.fromRGB(255, 220, 90), Enum.Material.Neon, Enum.PartType.Ball)
	glow.Transparency = 0.15
	glow.Parent = folder
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 220, 120)
	light.Range = 18
	light.Brightness = 0
	light.Parent = glow

	-- the body: lean at the waist, both arms round the shovel
	-- Modern characters pose their joints with AnimationConstraints (the animator drives their Transform
	-- and the rest pose comes from the Attachment on the parent part); older ones use a Motor6D (rest
	-- pose = C0). Either way we turn the rest pose, which stays put while the idle animation plays.
	type Joint = { get: () -> CFrame, set: (CFrame) -> () }
	local function joint(name: string): Joint?
		for _, d in char:GetDescendants() do
			if d.Name == name then
				if d:IsA("AnimationConstraint") and d.Attachment0 then
					local a = d.Attachment0 :: Attachment
					return { get = function() return a.CFrame end, set = function(cf: CFrame) a.CFrame = cf end }
				elseif d:IsA("Motor6D") then
					return { get = function() return d.C0 end, set = function(cf: CFrame) d.C0 = cf end }
				end
			end
		end
		return nil
	end
	local waist, rs, ls = joint("Waist"), joint("RightShoulder"), joint("LeftShoulder")
	local c0: { [Joint]: CFrame } = {}
	for _, j in { waist, rs, ls } do
		if j then
			c0[j] = j.get()
		end
	end
	player:SetAttribute("Digging", true) -- (PetView hides your pet so it can't block the camera)

	local cam = workspace.CurrentCamera
	local savedType, savedCf, savedFov = cam.CameraType, cam.CFrame, cam.FieldOfView
	cam.CameraType = Enum.CameraType.Scriptable

	local t0 = os.clock()
	local conn: RBXScriptConnection
	local stabsHeard = 0
	local STAB_SOUND_AT = { 0.3, 1.05, 1.8 } -- when the blade hits the ground
	local stopped = false

	local function cleanup()
		if stopped then
			return
		end
		stopped = true
		conn:Disconnect()
		folder:Destroy()
		for j, c in c0 do
			j.set(c)
		end
		player:SetAttribute("Digging", nil)
		cam.CameraType = savedType
		cam.CFrame = savedCf
		cam.FieldOfView = savedFov
		hum.WalkSpeed = savedSpeed
		hum.AutoRotate = savedRotate
		active = nil
	end

	local function pose(t: number)
		local _, s = sample(Anim.Tracks.Shovel, 7, t)
		local scf = frame * cframeOf(s)
		for _, sp in shovel do
			sp.part.CFrame = scf * sp.off
		end
		for i, d in dirt do
			local _, v = sample(Anim.Tracks["Dirt" .. i], 4, t)
			local size = math.max(v[4], 0.001)
			d.Size = Vector3.one * size
			d.CFrame = frame * CFrame.new(v[1], v[2], v[3]) * CFrame.Angles(t * 7 + i, t * 5, 0)
		end
		local _, g = sample(Anim.Tracks.Glow, 4, t)
		glow.Size = Vector3.one * math.max(g[4], 0.001) * 2.4
		glow.CFrame = frame * CFrame.new(g[1], g[2], g[3])
		light.Brightness = g[4] * 4
		local _, c = sample(Anim.Tracks.Cam, 8, t)
		cam.CFrame = frame * cframeOf(c)
		cam.FieldOfView = c[8]
		local _, b = sample(Anim.Tracks.Body, 3, t)
		if waist then
			waist.set(c0[waist] * CFrame.Angles(-b[1], 0, 0))
		end
		if rs then
			rs.set(c0[rs] * CFrame.Angles(b[2], 0, 0))
		end
		if ls then
			ls.set(c0[ls] * CFrame.Angles(b[2], 0, 0))
		end
	end

	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		-- (testing only) workspace attribute DigFreeze = N holds the clip still at N seconds
		local freeze = workspace:GetAttribute("DigFreeze") :: number?
		if freeze then
			t = freeze
			t0 = os.clock() - freeze
		end
		if not char.Parent or hum.Health <= 0 then
			cleanup()
			return
		end
		-- keep the digger planted (no sliding off the spot if something nudges you)
		root.CFrame = CFrame.lookAt(standAt, Vector3.new(mark.X, standAt.Y, mark.Z))
		root.AssemblyLinearVelocity = Vector3.zero
		pose(math.min(t, Anim.DURATION))
		local nextSound = STAB_SOUND_AT[stabsHeard + 1]
		if nextSound and t >= nextSound then
			stabsHeard += 1
			Sound.play("Hit", 0.7, 0.55 + stabsHeard * 0.08)
		end
		if t > Anim.DURATION + 3 then
			cleanup()
		end
	end)

	active = {
		began = t0,
		stop = function(success: boolean)
			if success then
				-- the treasure is out: let the glow and the chest have a moment on screen
				Sound.play("Coin", 0.8)
				task.delay(0.9, cleanup)
			else
				cleanup()
			end
		end,
	}
end

function DigView.init()
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt: ProximityPrompt, who: Player)
		if who == player and prompt.Name == "DigPrompt" then
			-- Treasure Digs open a few minutes after the tutorial (staggered unlocks): no dig scene until then
			local sn = State.snapshot
			if sn and not (sn.drip and sn.drip.dig) then
				return
			end
			start(prompt)
		end
	end)
	-- the server removes the mark when the dig completes, so the end of the hold can't be relied on
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, who: Player)
		if who == player and prompt.Name == "DigPrompt" and active and not workspace:GetAttribute("DigFreeze") then
			active.stop(true)
		end
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt: ProximityPrompt, who: Player)
		if who == player and prompt.Name == "DigPrompt" and active and not workspace:GetAttribute("DigFreeze") then
			active.stop(os.clock() - active.began >= Anim.DURATION * 0.9)
		end
	end)
end

return DigView
