"""Tide Tamers: the egg-fishing cast, authored in Blender and baked for Roblox.

Run inside Blender (exec the file). It builds a scene "EggRod" with the rod, line, lure hook,
mystery egg, splash rings, seafloor decoy eggs and a TrackTo camera, keys everything on the
timeline (30 fps), saves assets/fishing/egg_rod.blend, then bakes every animated object to
src/shared/RodAnim.luau (generated, do not edit by hand).

Coordinates: 1 Blender unit = 1 stud. The origin is the rod pivot. +X right, +Y OUT over the
rail (towards the sea), +Z up. Roblox gets (x, z, -y): the rod frame's -Z is "out to sea".
Sea surface is at z = WATER, the sea floor at z = FLOOR (rod pivot sits 13.6 studs above sea).
"""
import bpy, math, os, json
from mathutils import Vector, Matrix, Euler

ROOT = r"G:\Projects\CODES\sea"
FPS = 30
DUR = 4.8                      # must match Config.FISH_TIME
N = int(round(DUR * FPS)) + 1
WATER = -13.6
FLOOR = -41.6
TGT = Vector((0.0, 33.0, WATER))          # where the hook lands
E1, E2, E3 = Vector((-7, 29, FLOOR + 2.3)), Vector((8, 37, FLOOR + 2.3)), Vector((-1, 41, FLOOR + 2.3))  # decoy, decoy, THE egg

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
def clamp(x, a=0.0, b=1.0): return max(a, min(b, x))
def lerp(a, b, t): return a + (b - a) * t
def ease(t):  t = clamp(t); return t * t * (3 - 2 * t)
def easeout(t): t = clamp(t); return 1 - (1 - t) ** 3
def easein(t): t = clamp(t); return t ** 3
def vlerp(a, b, t): return a.lerp(b, t)
def seg(t, a, b): return clamp((t - a) / (b - a))

def pieces(t, keys):
    """piecewise smooth interpolation through (time, value) keys"""
    if t <= keys[0][0]: return keys[0][1]
    for i in range(len(keys) - 1):
        t0, v0 = keys[i]; t1, v1 = keys[i + 1]
        if t <= t1:
            u = ease((t - t0) / (t1 - t0))
            return lerp(v0, v1, u) if not isinstance(v0, Vector) else v0.lerp(v1, u)
    return keys[-1][1]

# rod pitch (degrees) and bend (degrees, tip curling down)
THETA = [(0, 50), (0.55, 108), (0.9, 28), (1.25, 40), (3.05, 38), (3.2, 66), (3.4, 50), (4.1, 96), (4.8, 50)]
BEND = [(0, 0), (0.45, -16), (0.7, -6), (0.9, 18), (1.3, 2), (3.0, 4), (3.2, 34), (3.45, 14), (3.9, 36), (4.2, 8), (4.8, 0)]
SEGS = [(1.3, 8.9, 0.55), (8.9, 16.4, 0.5), (16.4, 24.0, 0.35)]   # rod segment start/end along the rod, thickness
HANDLE = (-3.7, 1.3, 0.9)

def rod_state(t):
    th = math.radians(pieces(t, THETA))
    bd = math.radians(pieces(t, BEND))
    out = {"theta": th, "segs": []}
    d0 = Vector((0, math.cos(th), math.sin(th)))
    out["handle"] = (d0 * ((HANDLE[0] + HANDLE[1]) / 2), th)
    start = d0 * SEGS[0][0]
    ph = [th - bd * 0.2, th - bd * 0.6, th - bd * 1.2]
    cur = start
    for i, (a, b, _) in enumerate(SEGS):
        d = Vector((0, math.cos(ph[i]), math.sin(ph[i])))
        L = b - a
        out["segs"].append((cur + d * (L / 2), ph[i]))
        cur = cur + d * L
    out["tip"] = cur
    out["reel"] = d0 * 0.6 + Vector((0.9, 0, 0)) + Vector((0, 0, -0.8))
    return out

T_RELEASE, T_SPLASH = 0.78, 1.3
def hook_pos(t):
    rs = rod_state(t)
    tip = rs["tip"]
    if t < T_RELEASE:
        dang = Vector((math.sin(t * 9) * 0.25, -0.6 * (1 if t < 0.55 else -0.4), -2.6))
        return tip + dang
    p0 = rod_state(T_RELEASE)["tip"] + Vector((0, 0, -2.6))
    if t < T_SPLASH:                       # ballistic arc out to the sea
        u = (t - T_RELEASE) / (T_SPLASH - T_RELEASE)
        p = p0.lerp(TGT, u)
        p.z += math.sin(u * math.pi) * 15 * (1 - 0.0)
        return p
    if t < 2.3:                            # sink, swaying
        u = easeout((t - T_SPLASH) / 1.0)
        z = lerp(WATER, FLOOR + 6.5, u)
        return Vector((TGT.x + math.sin(t * 5) * 0.5 * (1 - u), TGT.y + math.cos(t * 4) * 0.4 * (1 - u), z))
    # search the floor: tour E1, E2, then E3
    base_z = FLOOR + 6.3
    W = [(2.3, Vector((TGT.x, TGT.y, base_z))),
         (2.62, Vector((E1.x, E1.y, base_z + 0.2))),
         (2.78, Vector((E1.x, E1.y, base_z - 1.2))),     # peek at decoy 1
         (2.92, Vector((E1.x, E1.y, base_z + 0.4))),
         (3.14, Vector((E2.x, E2.y, base_z + 0.2))),
         (3.28, Vector((E2.x, E2.y, base_z - 1.0))),     # peek at decoy 2
         (3.42, Vector((E2.x, E2.y, base_z + 0.4))),
         (3.62, Vector((E3.x, E3.y, base_z + 0.6))),
         (3.74, Vector((E3.x, E3.y, FLOOR + 5.0)))]      # lands on THE egg
    if t < 3.74:
        p = pieces(t, W)
        return p + Vector((math.sin(t * 7) * 0.25, 0, math.sin(t * 9) * 0.2))
    # haul it up; ends near the rod tip
    end = rod_state(4.25)["tip"] + Vector((0, 0, -2.6))
    start = Vector((E3.x, E3.y, FLOOR + 5.0))
    u = ease((t - 3.74) / (4.25 - 3.74)) if t < 4.25 else 1.0
    p = start.lerp(end, u)
    if t >= 4.25:
        return rod_state(t)["tip"] + Vector((0, 0, -2.6))
    return p

T_GRAB, T_HAULEND = 3.74, 4.25
def egg_state(t):
    """returns (pos, scale, spin) of THE egg. On the floor until the hook lands, then hangs below the hook."""
    floor_p = Vector((E3.x, E3.y, FLOOR + 1.4))
    if t < T_GRAB:
        return floor_p, 1.0, 0.0
    hp = hook_pos(t)
    hang = hp + Vector((0, 0, -2.4))
    u = ease((t - T_GRAB) / 0.18)
    p = floor_p.lerp(hang, u)
    spin = (t - T_GRAB) * 9
    return p, 1.0 + 0.1 * math.sin((t - T_GRAB) * 20) * (1 - u), spin

def ripple(t, t0, x, y, life=0.9):
    u = (t - t0) / life
    if u < 0 or u > 1: return Vector((x, y, WATER + 0.15)), 0.0
    return Vector((x, y, WATER + 0.15)), easeout(u) * 0.999 + 0.001

def breach_t():
    # the first time the egg rises above the water line
    t = T_GRAB
    while t < T_HAULEND + 0.3:
        if egg_state(t)[0].z > WATER: return t
        t += 1 / FPS
    return T_HAULEND

def line_points(t):
    rs = rod_state(t); a = rs["tip"]; b = hook_pos(t) + Vector((0, 0, 0.6))
    if t < T_RELEASE: slack = 0.8
    elif t < T_SPLASH: slack = 3.5 * (1 - seg(t, T_RELEASE, T_SPLASH)) + 0.4
    elif t < T_GRAB: slack = 0.5 + 0.3 * math.sin(t * 3)
    else: slack = 0.15
    pts = []
    for i in range(8):
        s = i / 7
        p = a.lerp(b, s)
        p.z -= slack * 4 * s * (1 - s)
        pts.append(p)
    return pts

# camera: position and look-at target are keyed in time
CAM_POS = [
    (0.0, Vector((7, -13, 7))), (0.7, Vector((7, -13, 7))), (1.1, Vector((8, -4, 10))),
    (1.5, Vector((11, 17, -5))), (2.2, Vector((9, 24, -26))), (2.9, Vector((7, 26, -30))),
    (3.4, Vector((5, 34, -33))), (3.74, Vector((4, 37, -34))), (4.0, Vector((9, 26, -12))),
    (4.3, Vector((5, 3, 14))), (4.8, Vector((5, -6, 12))),
]
CAM_FOV = [(0, 62), (1.1, 58), (2.2, 66), (3.4, 44), (3.74, 40), (4.3, 60), (4.8, 62)]
def cam_target(t):
    if t < 0.7: return Vector((0, 14, 10))
    if t < 3.74 and t < T_RELEASE + 0.0: return hook_pos(t)
    if t < 3.0: return hook_pos(t)
    if t < 3.74: return hook_pos(t).lerp(egg_state(t)[0], seg(t, 3.0, 3.74))
    return egg_state(t)[0]

# ---------------------------------------------------------------------------
# scene
# ---------------------------------------------------------------------------
for s in list(bpy.data.scenes):
    if s.name == "EggRod": bpy.data.scenes.remove(s)
scene = bpy.data.scenes.new("EggRod")
bpy.context.window.scene = scene
scene.render.fps = FPS
scene.frame_start, scene.frame_end = 0, N - 1
scene.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE_NEXT"
scene.render.resolution_x, scene.render.resolution_y = 640, 360
col = bpy.data.collections.new("EggRodCol"); scene.collection.children.link(col)

def mat(name, rgb, emit=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1)
    if emit:
        b.inputs["Emission Color"].default_value = (*rgb, 1); b.inputs["Emission Strength"].default_value = emit
    return m

def box(name, size, rgb, emit=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1)
    o = bpy.context.active_object; o.name = name; o.dimensions = size
    o.data.materials.append(mat(name + "M", rgb, emit))
    for c in o.users_collection: c.objects.unlink(o)
    col.objects.link(o)
    return o

def sphere(name, size, rgb, emit=0.0, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=size / 2, segments=24, ring_count=16)
    o = bpy.context.active_object; o.name = name
    o.scale = scale
    bpy.ops.object.shade_smooth()
    o.data.materials.append(mat(name + "M", rgb, emit))
    for c in o.users_collection: c.objects.unlink(o)
    col.objects.link(o)
    return o

# stage dressing (not baked): sea, floor, the ship's rail
sea = box("Sea", (400, 400, 0.2), (0.1, 0.5, 0.85)); sea.location = (0, 0, WATER)
sea.data.materials[0].diffuse_color = (0.1, 0.5, 0.85, 0.5)
sea.hide_render = False
floor = box("SeaFloor", (400, 400, 1), (0.9, 0.8, 0.55)); floor.location = (0, 0, FLOOR - 0.5)
hull = box("Hull", (6, 70, 14), (0.6, 0.38, 0.22)); hull.location = (-3.0 - 0.5, 0, WATER - 7 + 0.1 + 0)  # rod stands 9.5 from the rail: rail at y~-? placeholder
hull.location = (0, -35, WATER - 1)
hull.dimensions = (30, 60, 22)
stand = box("Stand", (1.4, 1.4, 4.2), (0.6, 0.4, 0.2)); stand.location = (0, 0, -2.1)

# animated objects
handle = box("RodHandle", (HANDLE[2], HANDLE[1] - HANDLE[0], HANDLE[2]), (0.94, 0.24, 0.24))
rod_s = [box("RodS%d" % (i + 1), (s[2], s[1] - s[0], s[2]), (0.98, 0.92, 0.75)) for i, s in enumerate(SEGS)]
reel = sphere("RodReel", 1.6, (1.0, 0.8, 0.2))
hook = sphere("Hook", 1.4, (0.3, 0.9, 1.0), emit=4.0)
hook_curve = box("HookBarb", (0.2, 0.2, 1.4), (0.8, 0.8, 0.85)); hook_curve.parent = hook; hook_curve.location = (0, 0, -1.0)
egg = sphere("Egg", 2.4, (0.04, 0.04, 0.07), scale=(1, 1, 1.28))
decoys = []
for i, p in enumerate((E1, E2)):
    d = sphere("Decoy%d" % (i + 1), 2.4, (0.1, 0.6, 0.7), emit=1.2, scale=(1, 1, 1.28)); d.location = p; decoys.append(d)
egg.location = E3
rings = []
for i in range(3):
    r = bpy.data.objects.new("Ripple%d" % (i + 1), bpy.data.meshes.new("Ripple%d" % (i + 1)))
    bpy.ops.mesh.primitive_torus_add(major_radius=1, minor_radius=0.04, major_segments=48, minor_segments=6)
    t_ = bpy.context.active_object; t_.name = "Ripple%d" % (i + 1)
    t_.data.materials.append(mat("RippleM%d" % i, (0.8, 0.95, 1.0), 2.0))
    for c in t_.users_collection: c.objects.unlink(t_)
    col.objects.link(t_); rings.append(t_)
    bpy.data.objects.remove(r)
cam_data = bpy.data.cameras.new("Cam"); cam = bpy.data.objects.new("Cam", cam_data); col.objects.link(cam)
look = bpy.data.objects.new("CamTarget", None); col.objects.link(look)
tc = cam.constraints.new("TRACK_TO"); tc.target = look; tc.track_axis = "TRACK_NEGATIVE_Z"; tc.up_axis = "UP_Y"
scene.camera = cam
sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN")); sun.data.energy = 4; sun.rotation_euler = (math.radians(50), 0, math.radians(30)); col.objects.link(sun)
scene.world = bpy.data.worlds.new("W"); scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.78, 0.95, 1)

def key(o, frame, **kw):
    for k, v in kw.items():
        setattr(o, k, v); o.keyframe_insert(k, frame=frame)

b_pre = breach_t()
for f in range(N):
    t = f / FPS
    rs = rod_state(t)
    # rod
    c, th = rs["handle"]; key(handle, f, location=c, rotation_euler=(th, 0, 0))
    for o, (c, ph) in zip(rod_s, rs["segs"]): key(o, f, location=c, rotation_euler=(ph, 0, 0))
    key(reel, f, location=rs["reel"])
    hp = hook_pos(t)
    # the hook points its barb down; sways a little
    key(hook, f, location=hp, rotation_euler=(math.sin(t * 6) * 0.15, math.cos(t * 5) * 0.12, 0))
    ep, es, spin = egg_state(t)
    key(egg, f, location=ep, rotation_euler=(0, 0, spin), scale=(es, es, es * 1.28))
    # ripples: plunge x2 and the breach
    p, s = ripple(t, T_SPLASH, TGT.x, TGT.y); key(rings[0], f, location=p, scale=(s * 7, s * 7, s * 7) if s else (0.001, 0.001, 0.001))
    p, s = ripple(t, T_SPLASH + 0.18, TGT.x, TGT.y); key(rings[1], f, location=p, scale=(s * 7, s * 7, s * 7) if s else (0.001, 0.001, 0.001))
    bp = egg_state(b_pre)[0]
    p, s = ripple(t, b_pre, bp.x, bp.y, 0.7); key(rings[2], f, location=p, scale=(s * 6, s * 6, s * 6) if s else (0.001, 0.001, 0.001))
    # camera
    key(cam, f, location=pieces(t, CAM_POS))
    key(look, f, location=cam_target(t))
    cam_data.sensor_fit = "VERTICAL"; cam_data.sensor_height = 24
    cam_data.lens = 12 / math.tan(math.radians(pieces(t, CAM_FOV)) / 2); cam_data.keyframe_insert("lens", frame=f)

# ---------------------------------------------------------------------------
# bake to Luau
# ---------------------------------------------------------------------------
M = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0)))     # Blender (x,y,z) -> Roblox (x, z, -y)
Minv = M.inverted()
def fmt(x): return ("%.3f" % x).rstrip("0").rstrip(".") if abs(x) > 1e-4 else "0"
def pack_obj(o, conj=True, scale=False):
    """8 numbers: position (3), quaternion (4: x y z w in Roblox), uniform scale"""
    mw = o.matrix_world
    pr = M @ mw.to_translation()
    R = mw.to_3x3().normalized()
    Rr = (M @ R @ Minv) if conj else (M @ R)
    q = Rr.to_quaternion()
    s = mw.to_scale().x
    return [pr.x, pr.y, pr.z, q.x, q.y, q.z, q.w, s]

names = [("RodHandle", handle), ("RodS1", rod_s[0]), ("RodS2", rod_s[1]), ("RodS3", rod_s[2]), ("RodReel", reel),
         ("Hook", hook), ("Egg", egg), ("Ripple1", rings[0]), ("Ripple2", rings[1]), ("Ripple3", rings[2])]
tracks = {n: [] for n, _ in names}; tracks["Cam"] = []; tracks["Line"] = []
for f in range(N):
    scene.frame_set(f)
    bpy.context.view_layer.update()
    for n, o in names:
        tracks[n] += pack_obj(o)
    tracks["Cam"] += pack_obj(cam, conj=False) + [math.degrees(2 * math.atan(12 / cam_data.lens))]
    for p in line_points(f / FPS):
        pr = M @ p
        tracks["Line"] += [pr.x, pr.y, pr.z]

lines = ["--!strict", "-- GENERATED by assets/fishing/build_rod_anim.py (Blender). Do not edit by hand.",
         "-- The egg-fishing cast: %d frames at %d fps. Each track is flat per frame in the ROD FRAME" % (N, FPS),
         "-- (rod pivot origin, -Z out to sea). Object tracks: x y z qx qy qz qw scale. Cam adds fov. Line = 8 points x 3.",
         "local Anim = {", "\tFPS = %d," % FPS, "\tFRAMES = %d," % N, "\tDURATION = %s," % fmt(DUR),
         "\tTHROW = %s, -- the hook leaves the rod" % fmt(T_RELEASE), "\tSPLASH = %s," % fmt(T_SPLASH),
         "\tGRAB = %s, -- the hook lands on the egg" % fmt(T_GRAB), "\tHAULEND = %s, -- the egg leaves the line and flies to the pedestal" % fmt(T_HAULEND),
         "\tDECOYS = { Vector3.new(%s, %s, %s), Vector3.new(%s, %s, %s) }," % tuple(fmt(v) for v in (E1.x, E1.z, -E1.y, E2.x, E2.z, -E2.y)),
         "\tEGGSPOT = Vector3.new(%s, %s, %s)," % (fmt(E3.x), fmt(E3.z), fmt(-E3.y)),
         "\tTracks = {"]
for n, arr in tracks.items():
    lines.append("\t\t%s = { %s }," % (n, ", ".join(fmt(v) for v in arr)))
lines += ["\t} :: { [string]: { number } },", "}", "", "return Anim", ""]
out = os.path.join(ROOT, "src", "shared", "RodAnim.luau")
open(out, "w", newline="\n").write("\n".join(lines))

os.makedirs(os.path.join(ROOT, "assets", "fishing"), exist_ok=True)
blend = os.path.join(ROOT, "assets", "fishing", "egg_rod.blend")
bpy.data.libraries.write(blend, {scene}, fake_user=True)
result = {"frames": N, "luau": out, "bytes": os.path.getsize(out), "breach": b_pre, "tracks": list(tracks)}
