--!strict
-- Builds monsters, enemies, bosses (shared/MonsterShapes, generated from assets/monsters/spec.py)
-- and blocky eggs out of parts, and poses a creature's bones each frame with the same
-- motion as the Blender Idle / Swim actions. Client-side visuals: nothing here replicates.

local Config = require(script.Parent.Config)
local MonsterShapes = require(script.Parent.MonsterShapes)

local MonsterModels = {}

export type Rig = {
	model: Model,
	shape: MonsterShapes.Shape,
	scale: number,
	parts: { BasePart },
	bone: { number },
	localCf: { CFrame },
	cframes: { CFrame },
	worlds: { CFrame },
	baseColor: { Color3 },
	baseTransp: { number },
}

local MATERIALS: { [string]: Enum.Material } = {
	p = Enum.Material.SmoothPlastic,
	n = Enum.Material.Neon,
	g = Enum.Material.Glass,
	m = Enum.Material.Metal,
}

local function newPart(size: Vector3, color: Color3, mat: string, kind: string): BasePart
	local p = Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Material = MATERIALS[mat] or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if mat == "g" then
		p.Transparency = 0.3
	end
	if kind == "S" then
		p.Shape = Enum.PartType.Ball
		-- a Ball part is uniform; use a SpecialMesh for squashed spheres
		if size.X ~= size.Y or size.Y ~= size.Z then
			p.Shape = Enum.PartType.Block
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
		end
	end
	return p
end

function MonsterModels.has(id: string): boolean
	return MonsterShapes.all[id] ~= nil
end

function MonsterModels.displayName(id: string): string
	local s = MonsterShapes.all[id]
	return if s then s.name else id
end

-- A creature at rest, origin at the world origin. scale 1 = about 3 studs tall.
function MonsterModels.build(id: string, scale: number): Rig?
	local shape = MonsterShapes.all[id]
	if not shape then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = id
	local rig: Rig = {
		model = model,
		shape = shape,
		scale = scale,
		parts = {},
		bone = {},
		localCf = {},
		cframes = {},
		worlds = table.create(#shape.bones, CFrame.identity),
		baseColor = {},
		baseTransp = {},
	}
	for _, pc in shape.pieces do
		local cf = CFrame.new(pc.p * scale) * CFrame.Angles(math.rad(pc.r.X), math.rad(pc.r.Y), math.rad(pc.r.Z))
		local part = newPart(pc.s * scale, pc.c, pc.m, pc.k)
		part.CFrame = cf
		part.Parent = model
		table.insert(rig.parts, part)
		table.insert(rig.bone, pc.b)
		table.insert(rig.localCf, cf)
		table.insert(rig.cframes, cf)
		table.insert(rig.baseColor, pc.c)
		table.insert(rig.baseTransp, part.Transparency)
	end
	model.PrimaryPart = rig.parts[1]
	model.WorldPivot = CFrame.identity
	return rig
end

-- How far below its origin the lowest piece reaches (studs, at the rig's scale)
function MonsterModels.footDepth(rig: Rig): number
	local low = 0
	for k, cf in rig.localCf do
		low = math.min(low, cf.Position.Y - rig.parts[k].Size.Y / 2)
	end
	return -low
end

-- Top of the model above its origin (for name tags / HP bars)
function MonsterModels.height(rig: Rig): number
	local high = 0
	for k, cf in rig.localCf do
		high = math.max(high, cf.Position.Y + rig.parts[k].Size.Y / 2)
	end
	return high
end

-- Pose every bone at time t and place the creature with its origin at `origin`.
-- swim = true plays the faster battle cycle.
function MonsterModels.pose(rig: Rig, origin: CFrame, t: number, swim: boolean?, bulk: boolean?)
	local bones = rig.shape.bones
	local worlds = rig.worlds
	local s = rig.scale
	local loop = MonsterShapes.LOOP
	for i, bone in bones do
		local b: any = if swim then bone.swim else bone
		local motion = CFrame.identity
		if b.anim then
			local w = math.pi * 2 * b.speed * t / loop
			if b.anim == "rot" then
				motion = CFrame.fromAxisAngle(b.axis, math.rad(b.amp) * math.sin(w + b.phase))
			elseif b.anim == "spin" then
				motion = CFrame.fromAxisAngle(b.axis, w)
			elseif b.anim == "move" then
				motion = CFrame.new(b.axis * b.amp * s * math.sin(w + b.phase))
			end
		end
		local pivot = bone.pivot * s
		local local_ = CFrame.new(pivot) * motion * CFrame.new(-pivot)
		worlds[i] = if bone.parent > 0 then worlds[bone.parent] * local_ else local_
	end
	if (rig :: any).rainbow then
		-- hue sweeps across the body over time
		for k, part in rig.parts do
			local h, s2, v = rig.baseColor[k]:ToHSV()
			local _ = h
			part.Color = Color3.fromHSV((t * 0.25 + k * 0.03) % 1, math.max(0.55, s2), math.max(0.75, v))
		end
	end
	local cfs = rig.cframes
	for k, part in rig.parts do
		cfs[k] = origin * worlds[rig.bone[k]] * rig.localCf[k]
		if not bulk then
			part.CFrame = cfs[k]
		end
	end
	if bulk then
		workspace:BulkMoveTo(rig.parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- Flash the whole creature a colour (hit = white, 0 = back to normal)
function MonsterModels.tint(rig: Rig, color: Color3?, amount: number)
	for k, part in rig.parts do
		part.Color = if color then rig.baseColor[k]:Lerp(color, amount) else rig.baseColor[k]
	end
end

-- Fade the whole creature (0 = normal, 1 = invisible)
function MonsterModels.fade(rig: Rig, alpha: number)
	for k, part in rig.parts do
		part.Transparency = rig.baseTransp[k] + (1 - rig.baseTransp[k]) * alpha
	end
end

-- Mutation look: Golden = gold-plated with a metal sheen; Rainbow = colours cycle while it
-- moves (MonsterModels.pose does the cycling). Both also get a shimmer.
function MonsterModels.applyVariant(rig: Rig, variant: string?)
	if variant == "Golden" then
		local gold = Color3.fromRGB(255, 200, 50)
		for k, part in rig.parts do
			if part.Material ~= Enum.Material.Neon then
				rig.baseColor[k] = rig.baseColor[k]:Lerp(gold, 0.6)
				part.Color = rig.baseColor[k]
				part.Material = Enum.Material.Metal
				part.Reflectance = 0.15
			end
		end
	elseif variant == "Rainbow" then
		(rig :: any).rainbow = true
	end
	if variant == "Golden" or variant == "Rainbow" then
		local att = Instance.new("Attachment")
		att.Parent = rig.parts[1]
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Color = if variant == "Golden" then ColorSequence.new(Color3.fromRGB(255, 220, 90)) else ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 255, 140)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 120, 255)),
		})
		pe.LightEmission = 1
		pe.Size = NumberSequence.new(0.4 * rig.scale, 0)
		pe.Lifetime = NumberRange.new(0.6, 1)
		pe.Rate = 10
		pe.Speed = NumberRange.new(1, 2)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Parent = att
	end
end

-- Deep Rod perk look (Config.PERKS): a soft glow in the perk's colour plus its own particles,
-- so perk monsters stand out on deck and in battle. Client only, attachments on the body part.
local PERK_FX = {
	Frost = { texture = "rbxasset://textures/particles/sparkles_main.dds", rate = 9, speed = 0.6, accel = Vector3.new(0, -1.5, 0), size = 0.35, life = 1.6 },
	Venom = { texture = "rbxasset://textures/particles/smoke_main.dds", rate = 6, speed = 1, accel = Vector3.new(0, 2, 0), size = 0.5, life = 1.2 },
	Bubble = { texture = "rbxasset://textures/particles/sparkles_main.dds", rate = 8, speed = 1.2, accel = Vector3.new(0, 3, 0), size = 0.45, life = 1.4 },
	Leech = { texture = "rbxasset://textures/particles/fire_main.dds", rate = 6, speed = 0.8, accel = Vector3.new(0, 1.5, 0), size = 0.4, life = 1 },
	Lucky = { texture = "rbxasset://textures/particles/sparkles_main.dds", rate = 12, speed = 2, accel = Vector3.new(0, -2, 0), size = 0.4, life = 1 },
	Thorns = { texture = "rbxasset://textures/particles/fire_main.dds", rate = 7, speed = 1.6, accel = Vector3.new(0, 0, 0), size = 0.3, life = 0.8 },
	SecondWind = { texture = "rbxasset://textures/particles/sparkles_main.dds", rate = 10, speed = 1.4, accel = Vector3.new(0, 4, 0), size = 0.4, life = 1.2 },
	Barnacle = { texture = "rbxasset://textures/particles/smoke_main.dds", rate = 4, speed = 0.4, accel = Vector3.new(0, -0.5, 0), size = 0.55, life = 1.6 },
}
function MonsterModels.applyPerk(rig: Rig, perk: string?)
	local def = perk and Config.PERKS[perk]
	local fx = perk and PERK_FX[perk]
	if not def or not fx then
		return
	end
	local body = rig.parts[1]
	local light = Instance.new("PointLight")
	light.Name = "PerkGlow"
	light.Color = def.color
	light.Range = 7 * rig.scale
	light.Brightness = 1.6
	light.Parent = body
	local att = Instance.new("Attachment")
	att.Name = "PerkFx"
	att.Position = Vector3.new(0, 0.6 * rig.scale, 0)
	att.Parent = body
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = fx.texture
	pe.Color = ColorSequence.new(def.color, def.color:Lerp(Color3.new(1, 1, 1), 0.6))
	pe.LightEmission = 0.8
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, fx.size * rig.scale), NumberSequenceKeypoint.new(1, 0) })
	pe.Transparency = NumberSequence.new(0.15, 1)
	pe.Lifetime = NumberRange.new(fx.life * 0.7, fx.life)
	pe.Rate = fx.rate
	pe.Speed = NumberRange.new(fx.speed * 0.5, fx.speed)
	pe.Acceleration = fx.accel
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Parent = att
	-- a slow pulsing ring of light round the feet
	local ring = Instance.new("ParticleEmitter")
	ring.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	ring.Color = ColorSequence.new(def.color)
	ring.LightEmission = 1
	ring.Size = NumberSequence.new(0.25 * rig.scale, 0)
	ring.Lifetime = NumberRange.new(0.8)
	ring.Rate = 14
	ring.Speed = NumberRange.new(2.2 * rig.scale)
	ring.SpreadAngle = Vector2.new(0, 180)
	ring.EmissionDirection = Enum.NormalId.Right
	ring.Parent = att
end

-- Rarity aura: 3* sparkles, 4* sparkles + glow, 5* both, bigger and pink. Client only.
function MonsterModels.addAura(rig: Rig, stars: number)
	if stars < 3 then
		return
	end
	local rarity = Config.RARITY[math.clamp(stars, 1, 5)]
	local att = Instance.new("Attachment")
	att.Name = "Aura"
	att.Position = Vector3.new(0, 0.5 * rig.scale, 0)
	att.Parent = rig.parts[1]
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(rarity.color, Color3.new(1, 1, 1))
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5 * rig.scale), NumberSequenceKeypoint.new(1, 0) })
	pe.Transparency = NumberSequence.new(0.1, 1)
	pe.Lifetime = NumberRange.new(0.8, 1.4)
	pe.Rate = if stars >= 5 then 24 elseif stars >= 4 then 14 else 7
	pe.Speed = NumberRange.new(1.5, 3)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Shape = Enum.ParticleEmitterShape.Sphere
	pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	pe.Parent = att
	if stars >= 4 then
		local light = Instance.new("PointLight")
		light.Color = rarity.color
		light.Range = 8 * rig.scale
		light.Brightness = 1.6
		light.Parent = rig.parts[1]
	end
end

-- The main element colour of a species
function MonsterModels.elementColor(sp: string): Color3
	local def = Config.MONSTERS[sp]
	local el = def and Config.ELEMENTS[def.elements[1]]
	return if el then el.color else Color3.new(1, 1, 1)
end

-- A blocky egg: stacked blocks in the species' element colours with neon spots.
function MonsterModels.buildEgg(sp: string, scale: number, mystery: boolean?): Model
	local def = Config.MONSTERS[sp]
	local c1 = if mystery then Color3.fromRGB(70, 70, 90) else MonsterModels.elementColor(sp)
	local c2 = c1
	if def and #def.elements > 1 and not mystery then
		c2 = Config.ELEMENTS[def.elements[2]].color
	end
	local model = Instance.new("Model")
	model.Name = "Egg"
	local rows = {
		{ y = -0.75, w = 1.1, h = 0.35 },
		{ y = -0.4, w = 1.5, h = 0.45 },
		{ y = 0.05, w = 1.6, h = 0.5 },
		{ y = 0.5, w = 1.4, h = 0.45 },
		{ y = 0.88, w = 1.0, h = 0.35 },
		{ y = 1.12, w = 0.55, h = 0.18 },
	}
	for i, r in rows do
		local p = newPart(Vector3.new(r.w, r.h, r.w) * scale, if i % 2 == 0 then c1 else c1:Lerp(Color3.new(1, 1, 1), 0.15), "p", "B")
		p.CFrame = CFrame.new(0, r.y * scale, 0)
		p.Parent = model
		if i == 3 then
			model.PrimaryPart = p
		end
	end
	for _, s in { { 0.81, 0.1, 0.2 }, { -0.81, 0.45, -0.25 }, { 0.2, 0.5, 0.71 }, { -0.3, -0.35, -0.76 } } do
		local spot = newPart(Vector3.new(0.3, 0.3, 0.3) * scale, c2:Lerp(Color3.new(1, 1, 1), 0.3), "n", "B")
		spot.CFrame = CFrame.new(Vector3.new(s[1], s[2], s[3]) * scale)
		spot.Parent = model
	end
	model.WorldPivot = CFrame.identity
	return model
end

return MonsterModels
