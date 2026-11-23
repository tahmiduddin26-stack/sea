--!strict
-- The blue hole arena off each ship's starboard side: a deep sinkhole of open water ringed by a
-- thin, light coral reef, with the fight floating over the dark water in the middle.
--
-- It is built from ArenaLayout, which the Blender mock-up writes (sea-art/arena/bluehole.py), so
-- the game matches the mock-up: the reef floor's heights and colour patches, the hole's wall,
-- the rock ledges deep in the hole (all terrain), and where every islet, rock and patch of surf
-- goes (models in ServerStorage.ArenaProps, imported from sea-art/arena/arena_props.fbx and
-- sorted by sea-art/arena/organize_arena_props.luau).
--
-- Layout coordinates are the mock-up's arena frame: bx = right, by = away from the ship, bz = up.
-- In the arena CFrame's own space that is (x, y, z) = (bx, bz, -by).

local ServerStorage = game:GetService("ServerStorage")

local Layout = require(script.Parent.ArenaLayout) :: any

local ArenaBuilder = {}

local RES = 4 -- terrain voxel size
local WORK_R = 74 -- terrain is written out to this radius (the grid covers 72)
local OCEAN_SAND_BOTTOM = -36 -- the rest of the ocean: water down to seaFloor, sand under it to here
local ISLET_LIFT = 0.45 -- studs the islets are raised above their mock-up height (see props)

local PATCH_MATERIALS = { Enum.Material.Salt, Enum.Material.Limestone, Enum.Material.Ground, Enum.Material.Mud }
local WALL = Enum.Material.Basalt
local FLOOR = Enum.Material.Asphalt -- the hole's floor, near-black so it reads bottomless
local DEEP = Enum.Material.Rock
local WATER = Enum.Material.Water
local AIR = Enum.Material.Air

-- the reef floor's height at (bx, by): bilinear over the grid, the ocean floor outside it
local function floorAt(bx: number, by: number): number
	local g = Layout.grid
	local fx = (bx + g.half) / g.step
	local fy = (by + g.half) / g.step
	local n = g.n
	if fx < 0 or fy < 0 or fx > n - 1 or fy > n - 1 then
		return Layout.seaFloor
	end
	local ix, iy = math.min(math.floor(fx), n - 2), math.min(math.floor(fy), n - 2)
	local tx, ty = fx - ix, fy - iy
	local h = g.h
	local a = h[iy * n + ix + 1]
	local b = h[iy * n + ix + 2]
	local c = h[(iy + 1) * n + ix + 1]
	local d = h[(iy + 1) * n + ix + 2]
	return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty
end

local function patchAt(bx: number, by: number): Enum.Material
	local g = Layout.grid
	local ix = math.clamp(math.floor((bx + g.half) / g.step + 0.5), 0, g.n - 1)
	local iy = math.clamp(math.floor((by + g.half) / g.step + 0.5), 0, g.n - 1)
	local k = string.byte(g.patch, iy * g.n + ix + 1) - 48
	return PATCH_MATERIALS[k + 1] or Enum.Material.Sand
end

-- the hole's wall radius at angle a (atan2(by, bx)) and height bz
local function wallAt(a: number, bz: number): number
	local w = Layout.wall
	local t = (a % (2 * math.pi)) / (2 * math.pi) * w.na
	local k0 = math.floor(t) % w.na
	local k1 = (k0 + 1) % w.na
	local ka = t - math.floor(t)
	local d = math.clamp(-bz / w.dz, 0, w.nz - 1)
	local j0 = math.min(math.floor(d), w.nz - 2)
	local ja = d - j0
	local r0, r1 = w.r[k0 + 1], w.r[k1 + 1]
	local top = r0[j0 + 1] * (1 - ka) + r1[j0 + 1] * ka
	local bottom = r0[j0 + 2] * (1 - ka) + r1[j0 + 2] * ka
	return top * (1 - ja) + bottom * ja
end

-- how much of a voxel centred at (bx, by, bz) a deep rock fills (0 = none)
local function deepRockAt(bx: number, by: number, bz: number): number
	local best = 0
	for _, e in Layout.deep do
		local dz = bz - e[3]
		if math.abs(dz) < e[6] + RES then
			local dx, dy = bx - e[1], by - e[2]
			local c, s = math.cos(e[7]), math.sin(e[7])
			local u = dx * c + dy * s
			local v = -dx * s + dy * c
			local q = (u / e[4]) ^ 2 + (v / e[5]) ^ 2 + (dz / e[6]) ^ 2
			if q < 1.6 then
				local o = math.clamp((1 - math.sqrt(q)) * math.min(e[4], e[5], e[6]) / RES + 0.5, 0, 1)
				best = math.max(best, o)
			end
		end
	end
	return best
end

-- Terrain colours: the reef's patches (Salt, Limestone, Ground, Mud), the hole's walls (Basalt)
-- and floor (Asphalt),
-- the deep rocks (Rock), and Sand, the whole ocean's floor (also the trenches' floors).
function ArenaBuilder.paintTerrain()
	for name, c in Layout.terrain do
		workspace.Terrain:SetMaterialColor((Enum.Material :: any)[name], Color3.fromRGB(c[1], c[2], c[3]))
	end
end

-- Writes the arena's terrain round arenaCf (its centre at the water surface, -Z away from the
-- ship): the reef shelf, the hole and its wall down to holeFloor, the deep rocks. Run it after
-- the ocean and BEFORE the trenches (they carve their own shafts after it).
function ArenaBuilder.terrain(arenaCf: CFrame)
	local c = arenaCf.Position
	local minY = Layout.holeFloor - 8
	local region = Region3.new(Vector3.new(c.X - WORK_R, minY, c.Z - WORK_R), Vector3.new(c.X + WORK_R, RES, c.Z + WORK_R)):ExpandToGrid(RES)
	local corner = region.CFrame.Position - region.Size / 2
	local nx, ny, nz = math.round(region.Size.X / RES), math.round(region.Size.Y / RES), math.round(region.Size.Z / RES)
	local mats: { { { Enum.Material } } } = table.create(nx)
	local occs: { { { number } } } = table.create(nx)
	local holeMax = 0
	for _, row in Layout.wall.r do
		for _, r in row do
			holeMax = math.max(holeMax, r)
		end
	end
	for ix = 1, nx do
		local mx: { { Enum.Material } } = table.create(ny)
		local ox: { { number } } = table.create(ny)
		for iy = 1, ny do
			mx[iy] = table.create(nz)
			ox[iy] = table.create(nz)
		end
		mats[ix] = mx
		occs[ix] = ox
		for iz = 1, nz do
			local wx = corner.X + (ix - 0.5) * RES
			local wz = corner.Z + (iz - 0.5) * RES
			local lp = arenaCf:PointToObjectSpace(Vector3.new(wx, c.Y, wz))
			local bx, by = lp.X, -lp.Z
			local r = math.sqrt(bx * bx + by * by)
			local a = math.atan2(by, bx)
			local h = floorAt(bx, by)
			local skin = patchAt(bx, by)
			-- the hole's wall rock goes all the way down near the hole; further out, only the
			-- ocean's usual sand layer sits under the floor
			local solidBottom = if r < holeMax + 22 then minY else OCEAN_SAND_BOTTOM
			for iy = 1, ny do
				local yb = corner.Y + (iy - 1) * RES -- voxel bottom (world y, sea level 0)
				local bz = yb + RES / 2 - c.Y
				local mat, occ = AIR, 0
				if yb - c.Y >= 0 then
					mat, occ = AIR, 0
				elseif r > WORK_R - 2 then
					-- the plain ocean
					if bz > Layout.seaFloor then
						mat, occ = WATER, 1
					elseif bz > OCEAN_SAND_BOTTOM then
						mat, occ = Enum.Material.Sand, 1
					end
				else
					local rw = wallAt(a, bz)
					if r < rw - RES / 2 then
						-- in the hole: open water, its floor, and the ledges on its walls
						if bz < Layout.holeFloor then
							mat, occ = FLOOR, 1
						else
							local o = deepRockAt(bx, by, bz)
							if o > 0.05 then
								mat, occ = DEEP, o
							else
								mat, occ = WATER, 1
							end
						end
					elseif bz < solidBottom then
						mat, occ = AIR, 0
					else
						-- reef floor: the surface lands at yb + 2 + 4 * occupancy
						local oy = math.clamp((h - (yb - c.Y) - RES / 2) / RES, 0, 1)
						local orad = math.clamp((r - rw) / RES + 0.5, 0, 1)
						local o = math.min(oy, orad)
						if o > 0.02 then
							occ = o
							local y0 = yb - c.Y
							if r < rw + RES and y0 < h - RES then
								mat = WALL -- the hole's wall face (under the reef's top skin)
							elseif y0 >= h - 10 then
								mat = skin -- the reef floor and the slopes, in their colour patches
							elseif r < rw + 10 then
								mat = WALL
							else
								mat = Enum.Material.Sand -- buried
							end
						else
							mat, occ = WATER, 1
						end
					end
				end
				mx[iy][iz] = mat
				ox[iy][iz] = occ
			end
		end
		if ix % 6 == 0 then
			task.wait()
		end
	end
	workspace.Terrain:WriteVoxels(region, RES, mats, occs)
end

-- The hole's shade: see-through navy discs lying on the water, darker towards the middle.
-- At low graphics quality Roblox draws water flat and nearly opaque, hiding the dark hole under
-- it, so these keep it reading as a deep-blue pool. At high quality the clear water's surface
-- is drawn over them and they barely show. (Checked in Studio at quality levels 3 and 21.)
-- { radius / rim, transparency }: many faint layers, so the fade has no visible bands
local SHADE = {}
for i = 0, 9 do
	table.insert(SHADE, { 0.98 - i * 0.055, 0.915 })
end

local function holeShade(parent: Instance, arenaCf: CFrame)
	local rim = math.huge
	for _, row in Layout.wall.r do
		rim = math.min(rim, row[1])
	end
	for i, s in SHADE do
		local d = Instance.new("Part")
		d.Name = "HoleShade"
		d.Shape = Enum.PartType.Cylinder
		d.Anchored = true
		d.CanCollide = false
		d.CanQuery = false
		d.CanTouch = false
		d.CastShadow = false
		d.Material = Enum.Material.SmoothPlastic
		d.Color = Color3.fromRGB(8, 34, 92)
		d.Transparency = s[2]
		d.Size = Vector3.new(0.05, rim * s[1] * 2, rim * s[1] * 2)
		d.CFrame = CFrame.new(arenaCf.Position + Vector3.new(0, 0.04 + i * 0.015, 0)) * CFrame.Angles(0, 0, math.rad(90))
		d.Parent = parent
	end
end

-- The islets, rocks and surf, cloned from ServerStorage.ArenaProps into `parent`, and the hole's shade.
function ArenaBuilder.props(parent: Instance, arenaCf: CFrame)
	holeShade(parent, arenaCf)
	local kit = ServerStorage:FindFirstChild("ArenaProps")
	if not kit then
		warn("[ArenaBuilder] ServerStorage.ArenaProps is missing: import sea-art/arena/arena_props.fbx and run organize_arena_props.luau")
		return
	end
	local missing = {}
	for _, p in Layout.props do
		local kind, bx, by, yaw, scale = p[1], p[2], p[3], p[4], p[5]
		local src = kit:FindFirstChild(kind)
		if not src then
			missing[kind] = true
			continue
		end
		local m = (src :: Model):Clone()
		if scale ~= 1 then
			m:ScaleTo(m:GetScale() * scale)
		end
		-- islets ride a little higher than in the mock-up: Roblox's waves otherwise cover their humps
		local lift = if string.sub(kind, 1, 5) == "Islet" then ISLET_LIFT else 0
		m:PivotTo(arenaCf * CFrame.new(bx, lift, -by) * CFrame.Angles(0, yaw, 0))
		m.Parent = parent
	end
	for kind in missing do
		warn("[ArenaBuilder] no ArenaProps." .. kind)
	end
end

return ArenaBuilder
