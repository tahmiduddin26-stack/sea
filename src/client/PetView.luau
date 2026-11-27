--!strict
-- Your strongest monster follows you around (retention plan Phase 3, item 19). The server sets
-- PetSp / PetLvl / PetV / PetPerk attributes on each player (DataService.syncAttributes); every
-- client builds a small copy of that monster and walks it along behind its owner, so the island
-- fills with everyone's pets. Purely cosmetic: no collisions, no server work per frame.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonsterModels = require(Shared.MonsterModels)
local Stats = require(Shared.Stats)
local PerfView = require(script.Parent.PerfView)

local PetView = {}

local PET_SCALE = 0.75 -- a level-1 pet is about knee to hip height on a Roblox character
local SIDE = 3.5 -- studs to the owner's right
local BEHIND = 4.5 -- studs behind the owner
local DRAW_DIST = 220

type Pet = { rig: MonsterModels.Rig, key: string, pos: Vector3, look: Vector3, foot: number, phase: number, gy: number, gt: number }
local lastExclude = 0

local pets: { [Player]: Pet } = {}

local folder = Instance.new("Folder")
folder.Name = "Pets"
folder.Parent = workspace

local ground = RaycastParams.new()
ground.FilterType = Enum.RaycastFilterType.Exclude
ground.IgnoreWater = false

local function keyOf(p: Player): string?
	local sp = p:GetAttribute("PetSp")
	if typeof(sp) ~= "string" then
		return nil
	end
	return sp .. "|" .. tostring(p:GetAttribute("PetLvl")) .. "|" .. tostring(p:GetAttribute("PetV")) .. "|" .. tostring(p:GetAttribute("PetPerk"))
end

local function remove(p: Player)
	local pet = pets[p]
	if pet then
		pet.rig.model:Destroy()
		pets[p] = nil
	end
end

local function build(p: Player, key: string, root: BasePart): Pet?
	local sp = p:GetAttribute("PetSp") :: string
	local lvl = tonumber(p:GetAttribute("PetLvl")) or 1
	-- grows a little with level (like in battle), but never bigger than the player
	local scale = PET_SCALE * math.min(1.6, Stats.sizeMult(lvl))
	local rig = MonsterModels.build(sp, scale)
	if not rig then
		return nil
	end
	MonsterModels.applyVariant(rig, p:GetAttribute("PetV") :: string?)
	MonsterModels.applyPerk(rig, p:GetAttribute("PetPerk") :: string?)
	for _, d in rig.model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
	rig.model.Name = p.Name .. "_Pet"
	rig.model.Parent = folder
	local start = root.Position - root.CFrame.LookVector * BEHIND
	return { rig = rig, key = key, pos = start, look = root.CFrame.LookVector, foot = MonsterModels.footDepth(rig), phase = math.random() * 5, gy = root.Position.Y - 3, gt = 0 }
end

function PetView.init()
	Players.PlayerRemoving:Connect(remove)
	RunService.RenderStepped:Connect(function(dt)
		local cam = workspace.CurrentCamera.CFrame.Position
		local t = os.clock()
		-- the ground ray ignores the characters: refreshed once a second, not every frame
		if t - lastExclude > 1 then
			lastExclude = t
			local exclude: { Instance } = { folder }
			for _, p in Players:GetPlayers() do
				if p.Character then
					table.insert(exclude, p.Character)
				end
			end
			ground.FilterDescendantsInstances = exclude
		end
		for _, p in Players:GetPlayers() do
			local char = p.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local key = keyOf(p)
			-- other players' pets only close up (every pet is dozens of parts posed each frame); yours always
			local range = if p == Players.LocalPlayer then DRAW_DIST elseif PerfView.mobile then 70 else 160
			if not root or not hum or hum.Health <= 0 or not key or (root.Position - cam).Magnitude > range or (p == Players.LocalPlayer and p:GetAttribute("Digging")) then
				remove(p)
				continue
			end
			local pet = pets[p]
			if pet and pet.key ~= key then
				remove(p)
				pet = nil
			end
			if not pet then
				pet = build(p, key, root)
				if not pet then
					continue
				end
				pets[p] = pet
			end
			local pt = pet :: Pet
			-- aim for a spot behind and to the right of the owner; teleports (fast travel) snap it over
			local cf = root.CFrame
			local target = cf.Position + cf.RightVector * SIDE - cf.LookVector * BEHIND
			local flat = (target - pt.pos) * Vector3.new(1, 0, 1)
			if flat.Magnitude > 60 then
				pt.pos = target
			else
				pt.pos = pt.pos:Lerp(target, math.clamp(dt * 5, 0, 1))
			end
			-- stand on whatever is below (deck, sand, a dock); over water it bobs on the surface
			-- (looked up a few times a second, not every frame)
			if t - pt.gt > 0.15 then
				pt.gt = t
				local hit = workspace:Raycast(Vector3.new(pt.pos.X, root.Position.Y + 4, pt.pos.Z), Vector3.new(0, -30, 0), ground)
				pt.gy = if hit then hit.Position.Y else root.Position.Y - 3
			end
			local y = pt.gy
			local moving = flat.Magnitude > 0.6
			if moving then
				pt.look = flat.Unit
			end
			local hop = if moving then math.abs(math.sin(t * 9 + pt.phase)) * 0.5 else 0
			local origin = CFrame.lookAt(Vector3.new(pt.pos.X, y + pt.foot + hop, pt.pos.Z), Vector3.new(pt.pos.X, y + pt.foot + hop, pt.pos.Z) + pt.look)
			MonsterModels.pose(pt.rig, origin, t + pt.phase, moving, false)
		end
	end)
end

return PetView
