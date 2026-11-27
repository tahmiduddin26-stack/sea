"""Tide Tamers: the treasure-dig cinematic, authored in Blender and baked for Roblox.

Run inside Blender (exec the file). It builds a scene "Dig" with a shovel, nine flying dirt chunks, a
glow that swells out of the hole and a TrackTo camera, keys everything at 30 fps over the 2.4 s the
player holds the Dig prompt (Config.TREASURE.hold), saves assets/dig/dig.blend and bakes every animated
object to src/shared/DigAnim.luau (generated, do not edit by hand).

Coordinates: 1 Blender unit = 1 stud. The origin is the X mark on the ground. The digger stands at
(0, -3.2, 0) facing +Y (towards the hole); +X is the digger's right, +Z up. Roblox gets (x, z, -y), so
the frame's -Z is the digger's forward. Object rotations keep their local axes one to one (the shovel
points along its local -Z with the blade at the -Z end).
"""
import bpy, math, os
from mathutils import Vector, Matrix, Quaternion

ROOT = r"G:\Projects\CODES\sea"
FPS = 30
DUR = 2.4
N = int(round(DUR * FPS)) + 1
STABS = 3
STAB_AT = [0.1, 0.85, 1.6]       # when each stab starts (s)
STAB_LEN = 0.72
GRAV = 38.0
DIRT_PER = 3

def clamp(x, a=0.0, b=1.0): return max(a, min(b, x))
def lerp(a, b, t): return a + (b - a) * t
def ease(t): t = clamp(t); return t * t * (3 - 2 * t)
def easeout(t): t = clamp(t); return 1 - (1 - t) ** 3
def easein(t): t = clamp(t); return t ** 3
def seg(t, a, b): return clamp((t - a) / (b - a))
def V(x, y, z): return Vector((x, y, z))

# ---------------------------------------------------------------------------
# the digger's shovel: grip (hands) and tip (blade point) for each pose
# ---------------------------------------------------------------------------
RAISE = (V(0.2, -2.7, 3.7), V(0.1, -0.9, 1.7))     # blade lifted, shovel leaning back over the hole
PLUNGE = (V(0.2, -2.1, 2.9), V(0.0, 0.1, -0.4))    # blade driven into the ground at the mark
LEVER = (V(0.2, -3.0, 3.3), V(0.0, 0.5, -0.2))     # handle pulled back to pry the dirt loose
FLICK = (V(0.3, -2.4, 4.0), V(-0.4, -1.7, 2.6))    # swung up and back, throwing the dirt over the shoulder

def stab_state(t):
    """(grip, tip, plunge amount 0..1) at time t: idle on RAISE before the first stab"""
    if t < STAB_AT[0]:
        u = ease(seg(t, 0, STAB_AT[0]))
        rest = (V(0.3, -2.4, 2.8), V(0.3, -0.9, 0.5))
        return (rest[0].lerp(RAISE[0], u), rest[1].lerp(RAISE[1], u), 0.0)
    k = 0
    for i, s in enumerate(STAB_AT):
        if t >= s:
            k = i
    u = (t - STAB_AT[k]) / STAB_LEN
    if u >= 1.0:   # after the last stab: settle back to raised
        return (RAISE[0], RAISE[1], 0.0)
    keys = [(0.0, RAISE), (0.28, PLUNGE), (0.5, LEVER), (0.78, FLICK), (1.0, RAISE)]
    for i in range(len(keys) - 1):
        a, pa = keys[i]; b, pb = keys[i + 1]
        if u <= b:
            q = ease((u - a) / (b - a))
            g = pa[0].lerp(pb[0], q); tp = pa[1].lerp(pb[1], q)
            plunge = {0: q, 1: 1.0, 2: 1.0 - q * 0.8, 3: 0.2 * (1 - q)}.get(i, 0.0)
            return (g, tp, plunge)
    return (RAISE[0], RAISE[1], 0.0)

def tip_at_flick(k):
    return lerp_state(STAB_AT[k] + STAB_LEN * 0.62)[1]

def lerp_state(t): return stab_state(t)

# ---------------------------------------------------------------------------
# dirt chunks: thrown at the flick of each stab, ballistic, shrinking away
# ---------------------------------------------------------------------------
THROWS = [(-3.0, -5.0, 8.0), (1.5, -6.5, 10.5), (4.0, -4.0, 9.0)]   # vx, vy (back), vz per chunk
def dirt_state(k, i, t):
    t0 = STAB_AT[k] + STAB_LEN * 0.6 + i * 0.015
    life = 0.85
    if t < t0 or t > t0 + life:
        return (V(0, 0, -50), 0.0)
    s = t - t0
    p0 = tip_at_flick(k)
    vx, vy, vz = THROWS[i]
    vx += (k - 1) * 0.8
    pos = p0 + V(vx * s, vy * s, vz * s - 0.5 * GRAV * s * s)
    if pos.z < 0.1:
        pos.z = 0.1
    scale = (0.5 + 0.12 * i) * (1.0 - easein(seg(s, 0.5, life)))
    return (pos, scale)

# the glow in the hole: swells during the last stab
def glow_state(t):
    u = ease(seg(t, 1.55, 2.4))
    return (V(0, 0.05, 0.2 + u * 0.5), u * 1.0)

# ---------------------------------------------------------------------------
# the digger's body: lean (rad), arm raise (rad) and a dip of the whole body (studs)
# ---------------------------------------------------------------------------
def body_state(t):
    g, tp, plunge = stab_state(t)
    high = clamp((g.z - 2.8) / 1.2)
    lean = 0.38 * plunge - 0.08 * (1 - plunge)
    arm = lerp(1.2, 2.05, high)
    dip = -0.35 * plunge
    return (lean, arm, dip)

# ---------------------------------------------------------------------------
# the camera: over the digger's shoulder, round to the side, then low and close at the hole as the
# last stab breaks the treasure free
# ---------------------------------------------------------------------------
def cam_state(t):
    # Starts on the digger's right, a little behind, so the shovel and both arms are in profile (the
    # body never hides them); sweeps round to the hole's far side, low, as the treasure breaks free.
    if t <= 1.6:
        u = ease(seg(t, 0, 1.6))
        ang = math.radians(lerp(-38, 8, u))           # measured from +X (the digger's right) round the hole
        r = lerp(10.5, 8.8, u)
        look = V(0, lerp(-1.5, -0.6, u), 2.0)
        pos = V(math.cos(ang) * r, -1.6 + math.sin(ang) * r, lerp(3.4, 2.6, u))
        fov = lerp(60, 52, u)
    else:
        u = ease(seg(t, 1.6, 2.4))
        ang = math.radians(lerp(8, 70, u))
        r = lerp(8.8, 5.6, u)
        look = V(0, 0, lerp(1.9, 1.0, u))
        pos = V(math.cos(ang) * r, math.sin(ang) * r - lerp(1.6, 0, u), lerp(2.6, 1.0, u))
        fov = lerp(52, 38, u)
    return (pos, look, fov)

# ---------------------------------------------------------------------------
# build the scene and key it
# ---------------------------------------------------------------------------
def build():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    sc = bpy.context.scene
    sc.name = "Dig"
    sc.render.fps = FPS
    sc.frame_start, sc.frame_end = 0, N - 1

    def mat(name, color):
        m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        m.diffuse_color = color
        return m

    def cube(name, size, color, loc=(0, 0, 0)):
        bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
        o = bpy.context.active_object
        o.name = name
        o.scale = size
        bpy.ops.object.transform_apply(scale=True)
        o.data.materials.append(mat(name + "_m", color))
        return o

    # shovel: origin at the middle of the handle, blade at the -Z end
    handle = cube("ShovelHandle", (0.32, 0.32, 5.0), (0.55, 0.36, 0.2, 1))
    blade = cube("ShovelBlade", (1.5, 0.18, 1.9), (0.62, 0.64, 0.68, 1), (0, 0, -2.9))
    grip = cube("ShovelGrip", (0.9, 0.3, 0.3), (0.55, 0.36, 0.2, 1), (0, 0, 2.5))
    bpy.ops.object.select_all(action='DESELECT')
    for o in (handle, blade, grip):
        o.select_set(True)
    bpy.context.view_layer.objects.active = handle
    bpy.ops.object.join()
    shovel = bpy.context.active_object
    shovel.name = "Shovel"
    shovel.rotation_mode = 'QUATERNION'

    dirt = []
    for k in range(STABS):
        for i in range(DIRT_PER):
            d = cube("Dirt%d" % (k * DIRT_PER + i + 1), (1, 1, 1), (0.45, 0.3, 0.16, 1))
            dirt.append((k, i, d))
    glow = cube("Glow", (1, 1, 1), (1.0, 0.85, 0.3, 1))

    cam_data = bpy.data.cameras.new("DigCam")
    cam = bpy.data.objects.new("Cam", cam_data)
    sc.collection.objects.link(cam)
    tgt = bpy.data.objects.new("CamTarget", None)
    sc.collection.objects.link(tgt)
    tc = cam.constraints.new('TRACK_TO')
    tc.target = tgt
    tc.track_axis = 'TRACK_NEGATIVE_Z'
    tc.up_axis = 'UP_Y'
    sc.camera = cam
    cam_data.sensor_fit = 'VERTICAL'

    # the digger as a stand-in (so the animation reads in Blender): a simple capsule-ish body
    body = cube("Digger", (1.6, 1.0, 4.6), (0.3, 0.55, 0.9, 1), (0, -3.2, 2.3))

    # key every frame
    for f in range(N):
        t = f / FPS
        sc.frame_set(f)
        g, tp, _ = stab_state(t)
        d = (tp - g).normalized()
        centre = tp - d * 2.9             # blade tip is 2.9 from the object's origin along -Z
        shovel.location = centre
        shovel.rotation_quaternion = d.to_track_quat('-Z', 'Y')
        shovel.keyframe_insert("location", frame=f)
        shovel.keyframe_insert("rotation_quaternion", frame=f)
        for k, i, o in dirt:
            pos, s = dirt_state(k, i, t)
            o.location = pos
            o.scale = (s, s, s)
            o.keyframe_insert("location", frame=f)
            o.keyframe_insert("scale", frame=f)
        gp, gs = glow_state(t)
        glow.location = gp
        glow.scale = (gs, gs, gs)
        glow.keyframe_insert("location", frame=f)
        glow.keyframe_insert("scale", frame=f)
        cp, cl, fov = cam_state(t)
        cam.location = cp
        tgt.location = cl
        cam_data.angle = math.radians(fov)
        cam.keyframe_insert("location", frame=f)
        tgt.keyframe_insert("location", frame=f)
        cam_data.keyframe_insert("lens", frame=f)
    return sc, shovel, dirt, glow, cam, body

# ---------------------------------------------------------------------------
# bake to Luau
# ---------------------------------------------------------------------------
P = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0)))     # Blender (x, y, z) -> Roblox (x, z, -y)

def to_rbx_pos(v): return (v.x, v.z, -v.y)

def to_rbx_quat(m3):
    cols = [P @ m3.col[i] for i in range(3)]
    r = Matrix((cols[0], cols[1], cols[2])).transposed()   # columns = mapped local axes
    q = r.to_quaternion()
    return (q.x, q.y, q.z, q.w)

def r(x):
    s = ("%.3f" % x).rstrip("0").rstrip(".")
    return "0" if s in ("", "-0") else s

def bake(sc, shovel, dirt, glow, cam, body):
    tracks = {}
    def add(name, vals): tracks.setdefault(name, []).extend(vals)
    for f in range(N):
        sc.frame_set(f)
        t = f / FPS
        bpy.context.view_layer.update()
        m = shovel.matrix_world
        add("Shovel", list(to_rbx_pos(m.translation)) + list(to_rbx_quat(m.to_3x3().normalized())))
        for k, i, o in dirt:
            m = o.matrix_world
            add(o.name, list(to_rbx_pos(m.translation)) + [o.scale.x])
        m = glow.matrix_world
        add("Glow", list(to_rbx_pos(m.translation)) + [glow.scale.x])
        m = cam.matrix_world
        add("Cam", list(to_rbx_pos(m.translation)) + list(to_rbx_quat(m.to_3x3().normalized())) + [math.degrees(cam.data.angle)])
        lean, arm, dip = body_state(t)
        add("Body", [lean, arm, dip])
    strides = {"Shovel": 7, "Glow": 4, "Cam": 8, "Body": 3}
    for k, i, o in dirt:
        strides[o.name] = 4
    out = []
    out.append("--!strict")
    out.append("-- GENERATED by assets/dig/build_dig_anim.py (Blender). Do not edit by hand.")
    out.append("-- The treasure-dig cinematic: %d frames at %d fps. Every track is flat per frame in the DIG FRAME" % (N, FPS))
    out.append("-- (origin = the X mark, the digger stands at +Z and faces -Z). Shovel: x y z qx qy qz qw. Dirt/Glow: x y z scale.")
    out.append("-- Cam: x y z qx qy qz qw fov. Body: lean arm dip (radians, radians, studs).")
    out.append("local Anim = {")
    out.append("\tFPS = %d," % FPS)
    out.append("\tFRAMES = %d," % N)
    out.append("\tDURATION = %s," % r(DUR))
    out.append("\tDIRT = %d," % len(dirt))
    out.append("\tSTRIDE = { Shovel = 7, Glow = 4, Cam = 8, Body = 3, Dirt = 4 },")
    out.append("\tTracks = {")
    for name in ["Shovel"] + [o.name for k, i, o in dirt] + ["Glow", "Cam", "Body"]:
        out.append("\t\t%s = { %s }," % (name, ", ".join(r(v) for v in tracks[name])))
    out.append("\t},")
    out.append("}")
    out.append("return Anim")
    path = os.path.join(ROOT, "src", "shared", "DigAnim.luau")
    with open(path, "w", newline="\n") as fh:
        fh.write("\n".join(out) + "\n")
    return path

sc, shovel, dirt, glow, cam, body = build()
path = bake(sc, shovel, dirt, glow, cam, body)
os.makedirs(os.path.join(ROOT, "assets", "dig"), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, "assets", "dig", "dig.blend"))
result = {"baked": path, "frames": N}
