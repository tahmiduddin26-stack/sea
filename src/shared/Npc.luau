--!strict
-- Blocky townsfolk. The server builds each one as an anchored Model (Npc.build) and the
-- client animates them every frame (Npc.register / Npc.step), so nobody pays network cost
-- for the motion. Same chunky block style as the rest of the harbour, no animation assets.
--
-- A rig stands on the origin of its CFrame and looks down -Z. Every part carries a "Group"
-- attribute (Body / Head / LArm / RArm) so the animator knows what swings from where.

local Npc = {}

export type Spec = {
	name: string,
	anim: string, -- wave | idle | read | hover | present
	skin: Color3?,
	shirt: Color3,
	pants: Color3?,
	hat: string?, -- tricorn | straw | party | hood | wizard | cap | captain | none
	hatColor: Color3?,
	beard: Color3?,
	glasses: boolean?,
	scale: number?,
	prop: string?, -- book | scroll | lantern | gift
}

local SKINS = { Color3.fromRGB(255, 214, 170), Color3.fromRGB(224, 172, 120), Color3.fromRGB(176, 120, 80), Color3.fromRGB(245, 195, 150) }
local NAVY = Color3.fromRGB(16, 22, 44)

local function part(model: Model, name: string, size: Vector3, rel: CFrame, color: Color3, group: string, extra: { [string]: any }?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.Size = size
	p.Color = color
	p.CFrame = rel -- placed in model space first, moved to the world by Npc.build
	p:SetAttribute("Group", group)
	if extra then
		for k, v in extra do
			(p :: any)[k] = v
		end
	end
	p.Parent = model
	return p
end

-- Build a townsperson standing at `cf` (feet on the ground, facing -Z)
function Npc.build(parent: Instance, cf: CFrame, spec: Spec, seed: number?): Model
	local m = Instance.new("Model")
	m.Name = spec.name
	local s = spec.scale or 1.15
	local skin = spec.skin or SKINS[((seed or 1) % #SKINS) + 1]
	local pants = spec.pants or Color3.fromRGB(60, 70, 110)
	local hatColor = spec.hatColor or Color3.fromRGB(150, 60, 50)
	local function v(x: number, y: number, z: number): Vector3
		return Vector3.new(x, y, z) * s
	end
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(x * s, y * s, z * s)
	end

	-- legs, torso, arms, head
	part(m, "LLeg", v(0.95, 2.2, 1), at(-0.55, 1.1, 0), pants, "Body")
	part(m, "RLeg", v(0.95, 2.2, 1), at(0.55, 1.1, 0), pants, "Body")
	part(m, "Shoes", v(2.3, 0.5, 1.5), at(0, 0.25, -0.15), NAVY, "Body")
	local torso = part(m, "Torso", v(2.2, 2.4, 1.2), at(0, 3.4, 0), spec.shirt, "Body", { CanCollide = true, CanQuery = true })
	part(m, "Belt", v(2.3, 0.35, 1.3), at(0, 2.35, 0), NAVY, "Body")
	part(m, "LArm", v(0.9, 2.3, 0.9), at(-1.6, 3.5, 0), spec.shirt, "LArm")
	part(m, "RArm", v(0.9, 2.3, 0.9), at(1.6, 3.5, 0), spec.shirt, "RArm")
	part(m, "LHand", v(0.9, 0.7, 0.9), at(-1.6, 2.15, 0), skin, "LArm")
	part(m, "RHand", v(0.9, 0.7, 0.9), at(1.6, 2.15, 0), skin, "RArm")
	local head = part(m, "Head", v(1.9, 1.9, 1.9), at(0, 5.5, 0), skin, "Head")
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head
	if spec.glasses then
		part(m, "GlassL", v(0.62, 0.5, 0.15), at(-0.45, 5.62, -0.98), Color3.fromRGB(240, 240, 250), "Head", { Transparency = 0.35 })
		part(m, "GlassR", v(0.62, 0.5, 0.15), at(0.45, 5.62, -0.98), Color3.fromRGB(240, 240, 250), "Head", { Transparency = 0.35 })
		part(m, "GlassBar", v(0.3, 0.12, 0.15), at(0, 5.66, -0.98), NAVY, "Head")
	end
	if spec.beard then
		part(m, "Beard", v(1.7, 0.9, 0.6), at(0, 4.85, -0.75), spec.beard, "Head")
		part(m, "Beard2", v(1.1, 0.7, 0.5), at(0, 4.35, -0.8), spec.beard, "Head")
	end

	-- hats
	local hat = spec.hat or "none"
	if hat == "tricorn" or hat == "captain" then
		part(m, "HatBrim", v(2.9, 0.3, 2.9), at(0, 6.5, 0), hatColor, "Head")
		part(m, "HatTop", v(2.1, 0.9, 2.1), at(0, 7.05, 0), hatColor, "Head")
		part(m, "HatBand", v(2.2, 0.25, 2.2), at(0, 6.8, 0), Color3.fromRGB(255, 205, 60), "Head")
		if hat == "captain" then
			part(m, "HatBadge", v(0.9, 0.7, 0.2), at(0, 7.05, -1.1), Color3.fromRGB(255, 205, 60), "Head")
		end
	elseif hat == "straw" then
		part(m, "HatBrim", v(3.4, 0.25, 3.4), at(0, 6.5, 0), Color3.fromRGB(240, 205, 120), "Head", { Material = Enum.Material.Wood })
		part(m, "HatTop", v(2.0, 0.9, 2.0), at(0, 7.0, 0), Color3.fromRGB(230, 190, 100), "Head", { Material = Enum.Material.Wood })
		part(m, "HatBand", v(2.1, 0.25, 2.1), at(0, 6.75, 0), Color3.fromRGB(230, 70, 70), "Head")
	elseif hat == "party" then
		for k = 0, 3 do
			part(m, "Cone" .. k, v(1.8 - k * 0.42, 0.7, 1.8 - k * 0.42), at(0, 6.65 + k * 0.7, 0), if k % 2 == 0 then hatColor else Color3.fromRGB(255, 255, 255), "Head")
		end
		part(m, "Pom", v(0.5, 0.5, 0.5), at(0, 9.5, 0), Color3.fromRGB(255, 230, 90), "Head", { Shape = Enum.PartType.Ball })
	elseif hat == "hood" then
		part(m, "HoodTop", v(2.3, 0.7, 2.3), at(0, 6.55, 0.05), hatColor, "Head")
		part(m, "HoodBack", v(2.3, 2.3, 0.6), at(0, 5.6, 0.95), hatColor, "Head")
		part(m, "HoodL", v(0.45, 1.9, 1.9), at(-1.1, 5.5, 0), hatColor, "Head")
		part(m, "HoodR", v(0.45, 1.9, 1.9), at(1.1, 5.5, 0), hatColor, "Head")
		part(m, "Cape", v(2.4, 2.6, 0.3), at(0, 3.5, 0.75), hatColor, "Body")
	elseif hat == "wizard" then
		part(m, "HatBrim", v(3.2, 0.25, 3.2), at(0, 6.5, 0), hatColor, "Head")
		for k = 0, 3 do
			part(m, "Cone" .. k, v(2.2 - k * 0.5, 0.9, 2.2 - k * 0.5), at(k * 0.08, 7.0 + k * 0.9, 0), hatColor, "Head")
		end
		part(m, "HatStar", v(0.6, 0.6, 0.25), at(0, 6.95, -1.15), Color3.fromRGB(255, 230, 90), "Head", { Material = Enum.Material.Neon })
	elseif hat == "cap" then
		part(m, "CapTop", v(2.05, 0.8, 2.05), at(0, 6.55, 0), hatColor, "Head")
		part(m, "CapBill", v(1.6, 0.2, 0.9), at(0, 6.25, -1.3), hatColor, "Head")
	end

	-- props held in front
	local prop = spec.prop
	if prop == "book" then
		part(m, "Book", v(1.8, 0.25, 1.4), at(0, 3.5, -1.35), Color3.fromRGB(120, 60, 170), "Body")
		part(m, "BookPages", v(1.6, 0.3, 1.2), at(0, 3.62, -1.35), Color3.fromRGB(250, 244, 225), "Body")
	elseif prop == "scroll" then
		part(m, "Scroll", v(1.5, 0.5, 1.0), at(0, 3.5, -1.3), Color3.fromRGB(245, 232, 190), "Body")
	elseif prop == "lantern" then
		part(m, "Lantern", v(0.7, 0.9, 0.7), at(2.2, 2.0, -0.3), Color3.fromRGB(255, 220, 120), "RArm", { Material = Enum.Material.Neon, Transparency = 0.15 })
	elseif prop == "gift" then
		part(m, "Gift", v(1.3, 1.1, 1.3), at(0, 3.6, -1.35), Color3.fromRGB(255, 90, 120), "Body")
		part(m, "GiftRibbon", v(0.3, 1.15, 1.35), at(0, 3.6, -1.35), Color3.fromRGB(255, 255, 255), "Body")
	end

	m.PrimaryPart = torso
	m:SetAttribute("Anim", spec.anim)
	m:SetAttribute("Scale", s)
	m:SetAttribute("Phase", ((seed or 1) * 1.7) % 6.28)
	-- everything above was laid out around the origin; move the whole rig to the world cf
	for _, d in m:GetChildren() do
		if d:IsA("BasePart") then
			d.CFrame = cf * d.CFrame
		end
	end
	m.Parent = parent
	game:GetService("CollectionService"):AddTag(m, "Npc")
	return m
end

---------------------------------------------------------------------------
-- Animation (runs on the client)
---------------------------------------------------------------------------
export type Rig = {
	model: Model,
	root: BasePart,
	restRoot: CFrame, -- root's rest CFrame in world space
	parts: { { part: BasePart, group: string, rel: CFrame } },
	scale: number,
	phase: number,
	anim: string,
}

function Npc.register(model: Model): Rig?
	local root = model.PrimaryPart or model:FindFirstChild("Torso") :: BasePart?
	if not root then
		return nil
	end
	local rig: Rig = {
		model = model,
		root = root,
		restRoot = root.CFrame,
		parts = {},
		scale = (model:GetAttribute("Scale") or 1) :: number,
		phase = (model:GetAttribute("Phase") or 0) :: number,
		anim = (model:GetAttribute("Anim") or "idle") :: string,
	}
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			table.insert(rig.parts, { part = d, group = (d:GetAttribute("Group") or "Body") :: string, rel = rig.restRoot:ToObjectSpace(d.CFrame) })
		end
	end
	return rig
end

-- pivot points in root space (the rig's torso centre is 3.4 up from the feet)
local function pivots(s: number): { [string]: CFrame }
	local ty = 3.4 * s
	return {
		Head = CFrame.new(0, (4.6 * s) - ty, 0),
		LArm = CFrame.new(-1.6 * s, (4.6 * s) - ty, 0),
		RArm = CFrame.new(1.6 * s, (4.6 * s) - ty, 0),
		Body = CFrame.new(0, -ty, 0),
	}
end

local rad = math.rad
local bulkParts: { BasePart } = {} -- reused every step (no garbage)
local bulkCfs: { CFrame } = {}

function Npc.step(rig: Rig, t: number)
	local s = rig.scale
	local ph = rig.phase
	local a = rig.anim
	local piv = pivots(s)
	local bob = 0
	local sway = 0
	local head = CFrame.identity
	local larm = CFrame.identity
	local rarm = CFrame.identity
	if a == "wave" then
		bob = math.sin(t * 2 + ph) * 0.06 * s
		rarm = CFrame.Angles(0, 0, rad(150 + math.sin(t * 7 + ph) * 16))
		larm = CFrame.Angles(0, 0, rad(math.sin(t * 2 + ph) * 3))
		head = CFrame.Angles(0, rad(math.sin(t * 1.1 + ph) * 14), rad(math.sin(t * 2 + ph) * 3))
	elseif a == "read" then
		bob = math.sin(t * 1.6 + ph) * 0.05 * s
		larm = CFrame.Angles(rad(62 + math.sin(t * 1.6 + ph) * 3), 0, rad(-8))
		rarm = CFrame.Angles(rad(62 + math.sin(t * 1.6 + ph + 1) * 3), 0, rad(8))
		head = CFrame.Angles(rad(22 + math.sin(t * 0.8 + ph) * 4), rad(math.sin(t * 0.5 + ph) * 18), 0)
	elseif a == "hover" then
		bob = (0.6 + math.sin(t * 1.5 + ph) * 0.45) * s
		sway = math.sin(t * 0.7 + ph) * 0.06
		larm = CFrame.Angles(rad(20), 0, rad(-50 + math.sin(t * 1.5 + ph) * 8))
		rarm = CFrame.Angles(rad(20), 0, rad(50 - math.sin(t * 1.5 + ph) * 8))
		head = CFrame.Angles(rad(-8), rad(math.sin(t * 0.6 + ph) * 10), 0)
	elseif a == "present" then
		bob = math.sin(t * 2.2 + ph) * 0.07 * s
		rarm = CFrame.Angles(rad(70 + math.sin(t * 2.4 + ph) * 14), 0, rad(18))
		larm = CFrame.Angles(rad(math.sin(t * 2.4 + ph + 3) * 10), 0, rad(-14))
		head = CFrame.Angles(rad(math.sin(t * 2.4 + ph) * 5), rad(math.sin(t * 0.9 + ph) * 22), 0)
	else -- idle
		bob = math.sin(t * 2 + ph) * 0.07 * s
		larm = CFrame.Angles(rad(math.sin(t * 2 + ph) * 4), 0, rad(-3 + math.sin(t * 2 + ph) * 2))
		rarm = CFrame.Angles(rad(-math.sin(t * 2 + ph) * 4), 0, rad(3 - math.sin(t * 2 + ph) * 2))
		head = CFrame.Angles(0, rad(math.sin(t * 0.6 + ph) * 24), 0)
	end
	local body = CFrame.new(0, bob, 0) * CFrame.Angles(0, sway, 0)
	local offsets: { [string]: CFrame } = {
		Body = body,
		Head = body * piv.Head * head * piv.Head:Inverse(),
		LArm = body * piv.LArm * larm * piv.LArm:Inverse(),
		RArm = body * piv.RArm * rarm * piv.RArm:Inverse(),
	}
	local rootCf = rig.restRoot
	-- move every part in ONE call: setting .CFrame on dozens of parts one by one every frame
	-- is what made the busy stands (Abyss Crate) stutter
	table.clear(bulkParts)
	table.clear(bulkCfs)
	for _, e in rig.parts do
		local o = offsets[e.group] or body
		-- legs and shoes stay planted unless the whole body floats
		table.insert(bulkParts, e.part)
		if (e.part.Name == "LLeg" or e.part.Name == "RLeg" or e.part.Name == "Shoes") and a ~= "hover" then
			table.insert(bulkCfs, rootCf * e.rel)
		else
			table.insert(bulkCfs, rootCf * o * e.rel)
		end
	end
	workspace:BulkMoveTo(bulkParts, bulkCfs, Enum.BulkMoveMode.FireCFrameChanged)
end

return Npc
