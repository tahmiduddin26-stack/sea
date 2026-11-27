--!strict
-- Fast travel between your ship and the harbour island (the walk was 150+ studs, which most players
-- never bothered with). One HUD button that says "To Harbour" on your ship and "To My Ship" on the
-- island, and a launch cannon on your ship's bow that does the same flight. The flight is a short arc
-- through the air: your character rides it (PlatformStand + CFrame each frame, so the server keeps
-- seeing where you are) and lands on its feet.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local UI = require(script.Parent.UI)
local State = require(script.Parent.State)
local Hud = require(script.Parent.Hud)
local Sound = require(script.Parent.Sound)

local Travel = {}

local player = Players.LocalPlayer
local C = UI.Colors
local HUB = Vector3.new(0, Config.SEA_LEVEL, 0) -- the harbour's centre (WorldBuilder.hubCenter)
local flying = false

local function myShip(): Model?
	local idx = player:GetAttribute("Ship")
	local world = workspace:FindFirstChild("World")
	return if idx and world then world:FindFirstChild("Ship" .. tostring(idx)) :: Model? else nil
end

-- true while standing on (or right next to) the harbour island
function Travel.onIsland(): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	local flat = Vector3.new(root.Position.X - HUB.X, 0, root.Position.Z - HUB.Z)
	return flat.Magnitude < Config.HUB_RADIUS * 1.3
end

-- where you land: on the island, on the path between the two rings of stands facing your ship; on
-- the ship, at its spawn spot on deck
local function islandSpot(): Vector3
	local ship = myShip()
	local shipCf = if ship then ship:GetAttribute("ShipCf") :: CFrame? else nil
	local dir = if shipCf then Vector3.new(shipCf.Position.X - HUB.X, 0, shipCf.Position.Z - HUB.Z) else Vector3.zAxis
	if dir.Magnitude < 1 then
		dir = Vector3.zAxis
	end
	return HUB + dir.Unit * 64 + Vector3.new(0, 9, 0)
end

local function shipSpot(): Vector3?
	local ship = myShip()
	local shipCf = if ship then ship:GetAttribute("ShipCf") :: CFrame? else nil
	if not shipCf then
		return nil
	end
	return (shipCf * CFrame.new(Config.SPAWN_POS.X, Config.DECK_Y + 4, Config.SPAWN_POS.Z)).Position
end

-- why you can't fly right now (nil = you can)
local function blocked(): string?
	if flying then
		return "busy"
	end
	if player:GetAttribute("Fishing") then
		return "Finish your cast first!"
	end
	if player:GetAttribute("InCannon") then
		return "Leave the cannon first!"
	end
	if player:GetAttribute("InCrabCove") then
		return "Finish your Crab Cove round first!"
	end
	return nil
end

-- Ragdoll: every joint of the character goes limp (a ball-socket in place of its Motor6D) so the
-- arms, legs and head flop about while the body flies. unRagdoll() puts it all back.
type Ragdoll = { motors: { Motor6D }, made: { Instance }, collide: { [BasePart]: boolean } }

local function ragdoll(char: Model): Ragdoll
	local rd: Ragdoll = { motors = {}, made = {}, collide = {} }
	for _, d in char:GetDescendants() do
		if d:IsA("Motor6D") and d.Name ~= "RootJoint" and d.Part0 and d.Part1 then
			local a0 = Instance.new("Attachment")
			a0.Name = "RagdollA0"
			a0.CFrame = d.C0
			a0.Parent = d.Part0
			local a1 = Instance.new("Attachment")
			a1.Name = "RagdollA1"
			a1.CFrame = d.C1
			a1.Parent = d.Part1
			local ball = Instance.new("BallSocketConstraint")
			ball.Name = "RagdollJoint"
			ball.Attachment0 = a0
			ball.Attachment1 = a1
			ball.LimitsEnabled = true
			ball.UpperAngle = if d.Name == "Neck" then 35 else 75
			ball.TwistLimitsEnabled = true
			ball.TwistLowerAngle = -35
			ball.TwistUpperAngle = 35
			ball.Parent = d.Part0
			d.Enabled = false
			table.insert(rd.motors, d)
			table.insert(rd.made, a0)
			table.insert(rd.made, a1)
			table.insert(rd.made, ball)
		end
	end
	-- limbs pass through each other while they flop (otherwise they jitter against the torso)
	for _, p in char:GetDescendants() do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			rd.collide[p] = p.CanCollide
			p.CanCollide = false
		end
	end
	return rd
end

local function unRagdoll(rd: Ragdoll)
	for _, m in rd.motors do
		if m.Parent then
			m.Enabled = true
		end
	end
	for _, i in rd.made do
		i:Destroy()
	end
	for p, c in rd.collide do
		if p.Parent then
			p.CanCollide = c
		end
	end
end

-- The flight. A real physics launch (so it is smooth and your own client simulates it): the speed is
-- worked out so gravity brings you down on `dest`. In the air the body is a ragdoll, tumbling and
-- flopping; a moment before landing it snaps upright, so you come down on your feet, never on your back.
function Travel.fly(dest: Vector3)
	local why = blocked()
	if why then
		if why ~= "busy" then
			Hud.toast(why, C.Coral)
		end
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not root or not hum then
		return
	end
	flying = true
	local from = root.Position + Vector3.new(0, 3, 0)
	local flat = Vector3.new(dest.X - from.X, 0, dest.Z - from.Z)
	local dist = flat.Magnitude
	local face = if dist > 0.1 then flat.Unit else Vector3.zAxis
	local T = math.clamp(dist / 110, 1.6, 2.8)
	local g = workspace.Gravity
	-- from + v*T - g*T^2/2 = dest
	local v0 = (dest - from) / T + Vector3.new(0, 0.5 * g * T, 0)
	local cam = workspace.CurrentCamera
	local baseFov = cam.FieldOfView

	hum.PlatformStand = true
	root.CFrame = CFrame.lookAt(from, from + face)
	local rd = ragdoll(char)
	root.AssemblyLinearVelocity = v0
	-- a forward somersault with a little sideways wobble
	root.AssemblyAngularVelocity = root.CFrame.RightVector * 7 + Vector3.new(0, 1.5, 0) + root.CFrame.LookVector * 1.5
	Sound.play("Cannon", 0.7)
	game:GetService("TweenService"):Create(cam, TweenInfo.new(0.3), { FieldOfView = baseFov + 14 }):Play()

	local t0 = os.clock()
	local recovered = false
	local conn: RBXScriptConnection
	local function finish()
		conn:Disconnect()
		flying = false
		game:GetService("TweenService"):Create(cam, TweenInfo.new(0.4), { FieldOfView = baseFov }):Play()
	end
	conn = RunService.Heartbeat:Connect(function()
		if not char.Parent or hum.Health <= 0 then
			-- reset or died mid-flight: the new character starts clean
			finish()
			return
		end
		local elapsed = os.clock() - t0
		if not recovered then
			-- time to get ready: the last 0.3 s of the arc (or anything that went wrong)
			if elapsed >= T - 0.3 or elapsed > T + 2 then
				recovered = true
				unRagdoll(rd)
				-- stand up in the air: upright, facing where you were going, still coming down
				local pos = root.Position
				local vel = root.AssemblyLinearVelocity
				root.CFrame = CFrame.lookAt(pos, pos + face)
				root.AssemblyAngularVelocity = Vector3.zero
				root.AssemblyLinearVelocity = Vector3.new(vel.X * 0.5, math.min(vel.Y, -12), vel.Z * 0.5)
				hum.PlatformStand = false
				hum:ChangeState(Enum.HumanoidStateType.Freefall)
			end
		else
			-- landed on something (or never will: a safety net)
			local grounded = hum.FloorMaterial ~= Enum.Material.Air
			if grounded or elapsed > T + 3 then
				if not grounded then
					root.CFrame = CFrame.lookAt(dest, dest + face)
					root.AssemblyLinearVelocity = Vector3.zero
				end
				Sound.play("Splash", 0.5, 1.4)
				finish()
			end
		end
	end)
end

function Travel.toIsland()
	Travel.fly(islandSpot())
end

function Travel.toShip()
	local spot = shipSpot()
	if spot then
		Travel.fly(spot)
	end
end

function Travel.init(screen: ScreenGui)
	local hud = screen:WaitForChild("Hud") :: GuiObject
	-- bottom centre, left of the Fuse heart (where it's easy to find with a thumb or the mouse)
	local btn = UI.button({ Text = "To Harbour", Color = C.Sea, Size = UDim2.fromOffset(150, 52), Position = UDim2.new(0.5, -84, 1, -40), AnchorPoint = Vector2.new(1, 0.5), Visible = false, Parent = hud }, function()
		if Travel.onIsland() then
			Travel.toShip()
		else
			Travel.toIsland()
		end
	end)
	-- the bow cannon on your ship: "Launch" flies you to the harbour
	ProximityPromptService.PromptTriggered:Connect(function(pp: ProximityPrompt, who: Player)
		if who == player and pp.Name == "LaunchPrompt" then
			Travel.toIsland()
		end
	end)
	task.spawn(function()
		local lastIsland: boolean? = nil
		while true do
			task.wait(0.4)
			local snap = State.snapshot
			-- after the tutorial (the island opens then), never during a fight or a cinematic
			local show = snap ~= nil and snap.tutorial >= Config.TUTORIAL_DONE and not Hud.inBattle and not State.cinematic and not Hud.fuseOpen
			btn.Visible = show and false -- the HUD travel button was removed; the bow launch cannon still flies you
			local island = Travel.onIsland()
			if island ~= lastIsland then
				lastIsland = island
				UI.setText(btn, if island then "To My Ship" else "To Harbour")
			end
		end
	end)
end

return Travel
