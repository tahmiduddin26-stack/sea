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

-- Hologram look (a nest whose monster is away fighting): every part turns cyan tinted glass
-- (the caller flickers it with MonsterModels.fade), and its sparkles / lights / rainbow cycling
-- are paused. Turning it off puts back exactly what was there (materials, colours, effects).
-- Glass, not Neon: neon washes out to white in daylight and the monster's shape gets lost.
local HOLO = Color3.fromRGB(70, 200, 255)
function MonsterModels.hologram(rig: Rig, on: boolean)
	local r = rig :: any
	if on == (r.holo == true) then
		return
	end
	if on then
		local saved = { mats = {}, refl = {}, fx = {}, rainbow = r.rainbow }
		r.rainbow = nil
		for k, part in rig.parts do
			saved.mats[k] = part.Material
			saved.refl[k] = part.Reflectance
			part.Material = Enum.Material.Glass
			part.Reflectance = 0
			part.Color = rig.baseColor[k]:Lerp(HOLO, 0.85)
		end
		for _, d in rig.model:GetDescendants() do
			if d:IsA("ParticleEmitter") or d:IsA("Light") then
				saved.fx[d] = (d :: any).Enabled
				;(d :: any).Enabled = false
			end
		end
		r.holoSaved = saved
		r.holo = true
	else
		local saved = r.holoSaved
		for k, part in rig.parts do
			part.Material = saved.mats[k]
			part.Reflectance = saved.refl[k]
			part.Color = rig.baseColor[k]
			part.Transparency = rig.baseTransp[k]
		end
		for d, enabled in saved.fx do
			if d.Parent then
				d.Enabled = enabled
			end
		end
		r.rainbow = saved.rainbow
		r.holoSaved = nil
		r.holo = nil
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

---------------------------------------------------------------------------
-- Eggs. A glossy egg-shaped shell (one tall ellipsoid) decorated
-- by element, so you can tell what's inside at a glance:
--   Tide  = rolling wave band with foam caps, a scallop-shell crest, bubbles
--   Coral = polka spots and coral branches sprouting out of the shell, glowing tips
--   Storm = a glowing zig-zag lightning crack round the middle and a bolt on top
--   Abyss = a slit-pupilled glowing eye, rune dots, crystals bursting out of the top
-- Hybrids: a band of shell tiles and a glow ring in the second element round the bottom.
-- Mystery (fusing / fished-up): a dark shell with a faint glowing crack. Golden / Rainbow variants
-- restyle the shell. Every egg also gets a soft glowing aura, a tilted ring of gems orbiting its
-- waist (it turns as the egg spins), a light, and particles in its element's style.
-- Origin at the egg's centre: the shell spans about -0.93 to +1.17 (x scale), the ring 1.15 wide.
---------------------------------------------------------------------------
local EGG_TRIM: { [string]: { trim: Color3, glow: Color3 } } = {
	Tide = { trim = Color3.fromRGB(200, 240, 255), glow = Color3.fromRGB(130, 230, 255) },
	Coral = { trim = Color3.fromRGB(255, 225, 205), glow = Color3.fromRGB(255, 170, 215) },
	Storm = { trim = Color3.fromRGB(70, 80, 140), glow = Color3.fromRGB(255, 250, 150) },
	Abyss = { trim = Color3.fromRGB(35, 20, 60), glow = Color3.fromRGB(200, 120, 255) },
}

-- Radius of the egg at height y (unit egg)
local EGG_R, EGG_H, EGG_Y = 0.8, 1.05, 0.12 -- shell radius, half height, centre height
local function eggRadius(y: number): number
	local a = (y - EGG_Y) / EGG_H
	return if math.abs(a) < 1 then EGG_R * math.sqrt(1 - a * a) else 0
end

-- A frame on the egg's surface at angle a (radians round Y, 0 = the front, -Z) and height y, with
-- local -Z pointing straight out of the shell. Keep y within about -0.8 .. 1.05 (the poles are flat).
local function eggSurface(a: number, y: number): CFrame
	local dir = Vector3.new(math.sin(a), 0, -math.cos(a))
	local dr = (eggRadius(y + 0.02) - eggRadius(y - 0.02)) / 0.04
	local p = dir * eggRadius(y) + Vector3.new(0, y, 0)
	return CFrame.lookAt(p, p + (dir - Vector3.yAxis * dr).Unit)
end

local function hue(i: number, n: number): Color3
	return Color3.fromHSV((i / n) % 1, 0.65, 1)
end

-- Particles per egg style. Emitted from the shell's surface; ignored inside ViewportFrames.
local EGG_FX = {
	Tide = { tex = "rbxasset://textures/particles/sparkles_main.dds", rate = 6, life = 1.6, speed = 0.6, accel = Vector3.new(0, 2.5, 0), size = 0.22, light = 0.6 },
	Coral = { tex = "rbxasset://textures/particles/sparkles_main.dds", rate = 5, life = 2.2, speed = 0.4, accel = Vector3.new(0, 0.6, 0), size = 0.26, light = 0.8 },
	Storm = { tex = "rbxasset://textures/particles/sparkles_main.dds", rate = 12, life = 0.3, speed = 3.5, accel = Vector3.zero, size = 0.24, light = 1 },
	Abyss = { tex = "rbxasset://textures/particles/smoke_main.dds", rate = 4, life = 1.8, speed = 0.3, accel = Vector3.new(0, 0.8, 0), size = 0.5, light = 0.4 },
	Mystery = { tex = "rbxasset://textures/particles/sparkles_main.dds", rate = 3, life = 1.4, speed = 0.5, accel = Vector3.new(0, 1, 0), size = 0.2, light = 1 },
}
local RAINBOW_SEQ = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
	ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 230, 80)),
	ColorSequenceKeypoint.new(0.66, Color3.fromRGB(80, 255, 160)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 130, 255)),
})

local function eggFx(shell: BasePart, style: string, glow: Color3, scale: number, variant: string?)
	local fx = EGG_FX[style] or EGG_FX.Mystery
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "EggFx"
	pe.Texture = fx.tex
	pe.Color = if variant == "Rainbow" then RAINBOW_SEQ else ColorSequence.new(glow, glow:Lerp(Color3.new(1, 1, 1), 0.5))
	pe.LightEmission = fx.light
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, fx.size * scale), NumberSequenceKeypoint.new(1, 0) })
	pe.Transparency = NumberSequence.new(if style == "Abyss" then 0.55 else 0.1, 1)
	pe.Lifetime = NumberRange.new(fx.life * 0.6, fx.life)
	pe.Rate = fx.rate
	pe.Speed = NumberRange.new(fx.speed * 0.5 * scale, fx.speed * scale)
	pe.Acceleration = fx.accel * scale
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	pe.Parent = shell
	if variant == "Golden" or variant == "Rainbow" then
		local sp = Instance.new("ParticleEmitter")
		sp.Name = "EggShine"
		sp.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sp.Color = if variant == "Rainbow" then RAINBOW_SEQ else ColorSequence.new(Color3.fromRGB(255, 225, 110))
		sp.LightEmission = 1
		sp.Size = NumberSequence.new(0.3 * scale, 0)
		sp.Lifetime = NumberRange.new(0.6, 1)
		sp.Rate = 10
		sp.Speed = NumberRange.new(1 * scale, 2 * scale)
		sp.SpreadAngle = Vector2.new(180, 180)
		sp.Parent = shell
	end
	local light = Instance.new("PointLight")
	light.Name = "EggGlow"
	light.Color = glow
	light.Range = 7 * scale
	light.Brightness = 1.3
	light.Shadows = false
	light.Parent = shell
end

function MonsterModels.buildEgg(sp: string, scale: number, mystery: boolean?, variant: string?): Model
	local def = Config.MONSTERS[sp]
	local el1 = def and def.elements[1] or "Tide"
	local el2 = def and def.elements[2] or nil
	local model = Instance.new("Model")
	model.Name = "Egg"
	local count = 0
	local rainbow = variant == "Rainbow" and not mystery
	-- one decoration piece; cf is in unit-egg space
	local function add(size: Vector3, cf: CFrame, color: Color3, mat: string?, kind: string?): BasePart
		count += 1
		if rainbow and (mat == "n" or kind == "deco") then
			color = hue(count, 9)
		end
		local p = newPart(size * scale, color, mat or "p", if kind == "S" then "S" else "B")
		p.CFrame = cf.Rotation + cf.Position * scale
		p.Parent = model
		return p
	end
	local function onShell(a: number, y: number, size: Vector3, color: Color3, mat: string?, lift: number?, twist: number?)
		local cf = eggSurface(a, y) * CFrame.Angles(0, 0, math.rad(twist or 0)) * CFrame.new(0, 0, -(lift or 0))
		return add(size, cf, color, mat, "deco")
	end
	-- the soft glowing aura and the tilted ring of gems orbiting the egg's waist
	local function aura(glow: Color3)
		local a = add(Vector3.new(EGG_R * 2.24, EGG_H * 2.16, EGG_R * 2.24), CFrame.new(0, EGG_Y, 0), glow, "n", "S")
		a.Transparency = 0.93
		-- a thin glowing hoop (tangent segments) with three gems set in it
		local tilt = CFrame.new(0, -0.05, 0) * CFrame.Angles(math.rad(16), 0, math.rad(-8))
		for i = 0, 23 do
			local ring = tilt * CFrame.Angles(0, i / 24 * math.pi * 2, 0) * CFrame.new(0, 0, -1.12)
			add(Vector3.new(0.31, 0.06, 0.06), ring, glow, "n")
			if i % 8 == 0 then
				add(Vector3.new(0.2, 0.2, 0.2), ring * CFrame.Angles(math.rad(45), 0, math.rad(45)), Color3.new(1, 1, 1):Lerp(glow, 0.4), "n")
			end
		end
	end

	-- the shell
	local top = if mystery then Color3.fromRGB(48, 48, 66) else Config.ELEMENTS[el1].color
	if variant == "Golden" and not mystery then
		top = Color3.fromRGB(255, 205, 60)
	elseif rainbow then
		top = Color3.fromRGB(255, 140, 210)
	end
	local shell = add(Vector3.new(EGG_R * 2, EGG_H * 2, EGG_R * 2), CFrame.new(0, EGG_Y, 0), top, "p", "S")
	shell.Reflectance = 0.08
	if variant == "Golden" and not mystery then
		shell.Material = Enum.Material.Metal
		shell.Reflectance = 0.2
	end
	model.PrimaryPart = shell
	-- a glossy highlight up on the left
	local glint = onShell(-0.7, 0.7, Vector3.new(0.16, 0.38, 0.04), Color3.new(1, 1, 1), "p", 0, -20)
	glint.Color = Color3.new(1, 1, 1)
	glint.Transparency = 0.35
	onShell(-0.55, 0.42, Vector3.new(0.1, 0.12, 0.04), Color3.new(1, 1, 1), "p").Transparency = 0.35

	if mystery then
		-- a faint glowing crack round the middle and a few speckles
		local crack = Color3.fromRGB(150, 140, 255)
		for i = 0, 13 do
			local a = i / 14 * math.pi * 2
			onShell(a, if i % 2 == 0 then 0.18 else 0.0, Vector3.new(0.36, 0.07, 0.05), crack, "n", 0, if i % 2 == 0 then -30 else 30)
		end
		for i = 0, 6 do
			onShell(i * 1.9, -0.5 + (i % 3) * 0.55, Vector3.new(0.1, 0.1, 0.05), Color3.fromRGB(200, 200, 230), "n")
		end
		add(Vector3.new(0.22, 0.22, 0.22), CFrame.new(0, 1.24, 0) * CFrame.Angles(0, math.rad(45), math.rad(45)), crack, "n")
		aura(crack)
		eggFx(shell, "Mystery", crack, scale, nil)
		model.WorldPivot = CFrame.identity
		return model
	end

	local t1 = EGG_TRIM[el1] or EGG_TRIM.Tide
	local glow = t1.glow
	local trim = t1.trim
	if el1 == "Tide" then
		-- a rolling wave band with foam caps
		for i = 0, 11 do
			local a = i / 12 * math.pi * 2
			onShell(a, -0.28 + (i % 2) * 0.1, Vector3.new(0.42, 0.24, 0.07), trim, "p")
			if i % 2 == 1 then
				onShell(a, -0.12, Vector3.new(0.2, 0.1, 0.08), Color3.new(1, 1, 1), "p", 0.01)
			end
		end
		-- a scallop-shell crest on the front with a pearl
		for d = -2, 2 do
			onShell(0, 0.42, Vector3.new(0.11, 0.42, 0.06), trim, "p", 0.01, d * 22) -- fanned ribs
		end
		add(Vector3.new(0.18, 0.18, 0.18), eggSurface(0, 0.3) * CFrame.new(0, 0, -0.06), glow, "n", "S")
		-- little fins on the sides and back, as if something is swimming inside
		for _, a in { math.pi / 2, -math.pi / 2 } do
			onShell(a, 0.15, Vector3.new(0.06, 0.42, 0.36), trim, "p", 0.14, 0)
			onShell(a, 0.32, Vector3.new(0.07, 0.14, 0.2), glow, "n", 0.22)
		end
		onShell(math.pi, 0.55, Vector3.new(0.06, 0.5, 0.3), trim, "p", 0.12)
		-- bubbles
		for _, b in { { 1.6, 0.6, 0.12 }, { 2.3, 0.85, 0.09 }, { 3.6, 0.5, 0.14 }, { 4.6, 0.95, 0.08 } } do
			add(Vector3.one * b[3] * 2, eggSurface(b[1], b[2]) * CFrame.new(0, 0, -b[3] * 0.6), glow, "g", "S")
		end
	elseif el1 == "Coral" then
		-- polka spots
		for i = 0, 9 do
			onShell(i * 2.4, -0.55 + (i % 4) * 0.42, Vector3.new(0.2, 0.2, 0.05), trim, "p")
		end
		-- coral branches growing out of the shell, glowing at the tips
		local coral = Config.ELEMENTS.Coral.color:Lerp(Color3.new(1, 1, 1), 0.25)
		for _, b in { { 1.9, 0.75 }, { 4.2, 0.55 }, { 0.5, 0.95 } } do
			local base = eggSurface(b[1], b[2])
			add(Vector3.new(0.14, 0.14, 0.5), base * CFrame.new(0, 0, -0.18), coral, "p", "deco")
			for _, side in { -1, 1 } do
				local arm = base * CFrame.new(0, 0, -0.3) * CFrame.Angles(0, math.rad(40 * side), 0) * CFrame.new(0, 0, -0.16)
				add(Vector3.new(0.11, 0.11, 0.32), arm, coral, "p", "deco")
				add(Vector3.new(0.13, 0.13, 0.13), arm * CFrame.new(0, 0, -0.17), glow, "n")
			end
			add(Vector3.new(0.15, 0.15, 0.15), base * CFrame.new(0, 0, -0.45), glow, "n")
		end
	elseif el1 == "Storm" then
		-- a glowing zig-zag lightning crack all the way round
		for i = 0, 15 do
			local a = i / 16 * math.pi * 2
			onShell(a, if i % 2 == 0 then 0.22 else 0.02, Vector3.new(0.34, 0.09, 0.06), glow, "n", 0, if i % 2 == 0 then -32 else 32)
		end
		-- dark storm bands above and below it
		for i = 0, 9 do
			local a = i / 10 * math.pi * 2
			onShell(a, -0.45, Vector3.new(0.5, 0.12, 0.05), trim, "p")
			onShell(a + 0.3, 0.7, Vector3.new(0.4, 0.1, 0.05), trim, "p")
		end
		-- a lightning bolt standing on top
		add(Vector3.new(0.14, 0.34, 0.12), CFrame.new(0.04, 1.3, 0) * CFrame.Angles(0, 0, math.rad(-25)), glow, "n")
		add(Vector3.new(0.14, 0.3, 0.12), CFrame.new(-0.02, 1.55, 0) * CFrame.Angles(0, 0, math.rad(25)), glow, "n")
	else -- Abyss
		-- a big glowing diamond eye on the front: dark socket, glowing iris, slit pupil, a heavy brow
		onShell(0, 0.3, Vector3.new(0.52, 0.52, 0.04), trim, "p", 0, 45)
		onShell(0, 0.3, Vector3.new(0.38, 0.38, 0.05), glow, "n", 0.01, 45)
		onShell(0, 0.3, Vector3.new(0.07, 0.36, 0.05), Color3.fromRGB(15, 8, 25), "p", 0.025)
		onShell(0, 0.6, Vector3.new(0.5, 0.1, 0.08), trim, "p", 0.01)
		-- rune dots round the base
		for i = 0, 9 do
			onShell(i / 10 * math.pi * 2 + 0.3, -0.48, Vector3.new(0.12, 0.12, 0.05), glow, "n")
		end
		-- crystals bursting out of the top
		local crystal = Config.ELEMENTS.Abyss.color:Lerp(Color3.new(1, 1, 1), 0.3)
		for i = 0, 3 do
			local base = eggSurface(i / 4 * math.pi * 2 + 0.4, 0.88)
			add(Vector3.new(0.2, 0.2, 0.55), base * CFrame.new(0, 0, -0.15) * CFrame.Angles(0, 0, math.rad(45)), crystal, "g", "deco")
		end
		add(Vector3.new(0.24, 0.62, 0.24), CFrame.new(0, 1.35, 0) * CFrame.Angles(0, math.rad(45), 0), glow, "n")
	end
	if el2 then
		-- a hybrid wears its second element as a band of shell tiles and a glow ring round the bottom
		local c2 = if rainbow then Color3.fromRGB(120, 170, 255) else Config.ELEMENTS[el2].color
		local g2 = (EGG_TRIM[el2] or EGG_TRIM.Tide).glow
		for i = 0, 11 do
			onShell(i / 12 * math.pi * 2, -0.6 + (i % 2) * 0.08, Vector3.new(0.46, 0.34, 0.05), c2, "p")
		end
		for i = 0, 7 do
			onShell(i / 8 * math.pi * 2 + 0.2, -0.8, Vector3.new(0.12, 0.12, 0.05), g2, "n", 0.01)
		end
	end
	local fxGlow = if variant == "Golden" then Color3.fromRGB(255, 215, 90) else glow
	aura(fxGlow)
	eggFx(shell, el1, fxGlow, scale, variant)
	model.WorldPivot = CFrame.identity
	return model
end

return MonsterModels
