# Renders the Spellbook icons (one per spell EFFECT) as glossy chunky 3D-cartoon icons with the same
# navy inverted-hull outline + transparent background as build_icons.py.
# -> assets/icons/png/spells/Spell_<Name>.png (512x512)
#
# Headless:  "G:\Program Files (x86)\blender.exe" -b --factory-startup --python build_spell_icons.py
# Subset:    set env SPELL_ONLY=Damage,Health
import bpy, bmesh, math, os, sys
from mathutils import Matrix, Vector, Euler

OUT = r"G:\Projects\CODES\sea\assets\icons\png\spells"
os.makedirs(OUT, exist_ok=True)

NAVY = (16, 22, 44)
WHITE = (255, 255, 255)
GOLD = (255, 205, 50)
GOLD_D = (225, 150, 25)
WOOD = (150, 96, 56)
CREAM = (255, 240, 205)


def srgb(c):
    def g(v):
        v = v / 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return (g(c[0]), g(c[1]), g(c[2]), 1)


MATS = {}


def setin(b, names, val):
    for n in names:
        if n in b.inputs:
            b.inputs[n].default_value = val
            return


def mat(color, neon=0.0, metal=0.0, rough=0.28):
    key = (tuple(color), neon, metal, rough)
    if key in MATS:
        return MATS[key]
    m = bpy.data.materials.new("S_%02x%02x%02x" % tuple(color))
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = srgb(color)
    b.inputs["Roughness"].default_value = rough
    setin(b, ["Coat Weight", "Clearcoat"], 0.5)
    setin(b, ["Coat Roughness", "Clearcoat Roughness"], 0.12)
    if neon:
        setin(b, ["Emission Color"], srgb(color))
        setin(b, ["Emission Strength"], neon)
    if metal:
        b.inputs["Metallic"].default_value = metal
    MATS[key] = m
    return m


def rainbow_mat():
    m = bpy.data.materials.new("S_Rainbow")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.25
    setin(b, ["Coat Weight", "Clearcoat"], 0.5)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = -1.35
    mr.inputs["From Max"].default_value = 1.35
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    cols = [(255, 70, 80), (255, 150, 50), (255, 225, 60), (90, 215, 110), (70, 170, 255), (170, 100, 255)]
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = srgb(cols[0])
    for i in range(1, len(cols)):
        e = ramp.color_ramp.elements.new(i / len(cols))
        e.color = srgb(cols[i])
    nt.links.new(tc.outputs["Object"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], mr.inputs["Value"])
    nt.links.new(mr.outputs[0], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    return m


def outline_mat():
    if "SpellOutline" in bpy.data.materials:
        return bpy.data.materials["SpellOutline"]
    m = bpy.data.materials.new("SpellOutline")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = srgb(NAVY)
    em.inputs["Strength"].default_value = 1.0
    nt.links.new(em.outputs[0], out.inputs[0])
    m.use_backface_culling = True
    return m


COLL = None
XF = Matrix.Identity(4)


class xf:
    """group transform: with xf(pos, rot_deg, s): ... everything inside is placed relative to it"""
    def __init__(self, pos=(0, 0, 0), rot=(0, 0, 0), s=1.0):
        self.m = Matrix.Translation(pos) @ Euler([math.radians(a) for a in rot]).to_matrix().to_4x4() @ Matrix.Diagonal((s, s, s, 1))

    def __enter__(self):
        global XF
        self.old = XF
        XF = XF @ self.m

    def __exit__(self, *a):
        global XF
        XF = self.old


def finish(bm, color, pos, rot, outline=True, neon=0.0, metal=0.0, ol=0.07, rough=0.28, material=None, flat_front=False):
    me = bpy.data.meshes.new("m")
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = not (flat_front and abs(p.normal.y) > 0.985)
    me.materials.append(material or mat(color, neon, metal, rough))
    if outline:
        me.materials.append(outline_mat())
    ob = bpy.data.objects.new("o", me)
    COLL.objects.link(ob)
    ob.matrix_world = XF @ Matrix.Translation(pos) @ Euler([math.radians(a) for a in rot]).to_matrix().to_4x4()
    if outline:
        sol = ob.modifiers.new("Outline", "SOLIDIFY")
        sol.thickness = ol
        sol.offset = 1
        sol.use_flip_normals = True
        sol.material_offset = 1
    return ob


def sph(r, pos=(0, 0, 0), color=WHITE, rot=(0, 0, 0), seg=28, **kw):
    if not isinstance(r, (tuple, list)):
        r = (r, r, r)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=max(8, seg // 2), radius=1.0)
    bmesh.ops.transform(bm, matrix=Matrix.Diagonal((r[0], r[1], r[2], 1)), verts=bm.verts)
    return finish(bm, color, pos, rot, **kw)


def egg(r=(1.0, 1.0, 1.35), pos=(0, 0, 0), color=CREAM, rot=(0, 0, 0), taper=0.22, **kw):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=36, v_segments=20, radius=1.0)
    for v in bm.verts:
        k = 1 - taper * max(0.0, v.co.z)
        v.co.x *= r[0] * k
        v.co.y *= r[1] * k
        v.co.z *= r[2]
    return finish(bm, color, pos, rot, **kw)


def egg_y(r, x, z, taper=0.22):
    """front-surface y of an egg centered at the origin"""
    zn = max(-1, min(1, z / r[2]))
    k = 1 - taper * max(0.0, zn)
    a = r[0] * k
    t = 1 - (x / a) ** 2 - zn ** 2
    return -r[1] * k * math.sqrt(max(t, 0.0))


def cyl(r, depth, pos=(0, 0, 0), color=WHITE, rot=(0, 0, 0), r2=None, bev=0.0, seg=32, **kw):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r if r2 is None else r2, depth=depth)
    if bev > 0:
        caps = [f for f in bm.faces if len(f.verts) == seg]
        edges = list({e for f in caps for e in f.edges})
        try:
            bmesh.ops.bevel(bm, geom=edges, offset=bev, segments=3, affect="EDGES")
        except Exception:
            pass
    return finish(bm, color, pos, rot, **kw)


def cone(r, depth, pos=(0, 0, 0), color=WHITE, rot=(0, 0, 0), **kw):
    return cyl(r, depth, pos, color, rot, r2=0.0, **kw)


def offset_pts(pts, d):
    n = len(pts)
    area = sum(pts[i][0] * pts[(i + 1) % n][1] - pts[(i + 1) % n][0] * pts[i][1] for i in range(n))
    sg = 1 if area > 0 else -1
    out = []
    for i in range(n):
        p0, p1, p2 = pts[i - 1], pts[i], pts[(i + 1) % n]
        def nrm(a, b):
            ex, ez = b[0] - a[0], b[1] - a[1]
            L = math.hypot(ex, ez) or 1
            return (sg * ez / L, -sg * ex / L)
        n1, n2 = nrm(p0, p1), nrm(p1, p2)
        k = 1 + n1[0] * n2[0] + n1[1] * n2[1]
        mx, mz = (n1[0] + n2[0]) / max(k, 0.35), (n1[1] + n2[1]) / max(k, 0.35)
        out.append((p1[0] + mx * d, p1[1] + mz * d))
    return out


def poly(pts, depth=0.3, color=WHITE, pos=(0, 0, 0), rot=(0, 0, 0), bev=0.07, **kw):
    """extruded polygon in the XZ plane (front faces the camera at -Y); outline = offset navy extrusion behind"""
    outline = kw.pop("outline", True)
    ol = kw.pop("ol", 0.07)
    if outline:
        poly(offset_pts(pts, ol * 0.62), depth * 0.8, NAVY, pos, rot, bev=0.0, outline=False, material=outline_mat_flat())
    return _poly(pts, depth, color, pos, rot, bev, **kw)


def outline_mat_flat():
    if "SpellOutlineFlat" in bpy.data.materials:
        return bpy.data.materials["SpellOutlineFlat"]
    m = bpy.data.materials.new("SpellOutlineFlat")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = srgb(NAVY)
    nt.links.new(em.outputs[0], out.inputs[0])
    return m


def _poly(pts, depth, color, pos, rot, bev, **kw):
    kw["outline"] = False
    kw["flat_front"] = True
    bm = bmesh.new()
    vs = [bm.verts.new((x, -depth / 2, z)) for x, z in pts]
    f = bm.faces.new(vs)
    res = bmesh.ops.extrude_face_region(bm, geom=[f])
    nv = [e for e in res["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(0, depth, 0), verts=nv)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    xs = [p[0] for p in pts]
    zs = [p[1] for p in pts]
    bev = min(bev, depth * 0.4, 0.22 * min(max(xs) - min(xs), max(zs) - min(zs)))
    if bev > 0:
        try:
            bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bev, segments=3, affect="EDGES")
        except Exception:
            pass
    return finish(bm, color, pos, rot, **kw)


def scale_pts(pts, sx, sz=None):
    sz = sx if sz is None else sz
    return [(x * sx, z * sz) for x, z in pts]


def hl(x, z, y, rx=0.12, rz=0.2, rot=(0, 0, 0), color=WHITE):
    """soft white highlight blob (no outline)"""
    return sph((rx, 0.05, rz), (x, y, z), color, rot, seg=16, outline=False, neon=0.5, rough=0.6)


def catmull(ctrl, n=14):
    out = []
    P = [ctrl[0]] + list(ctrl) + [ctrl[-1]]
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for k in range(n):
            t = k / n
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2 +
                                    (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3) for j in range(2)))
    out.append(tuple(ctrl[-1]))
    return out


def resample(pts, step):
    out = [pts[0]]
    acc = 0.0
    for i in range(1, len(pts)):
        a, b = pts[i - 1], pts[i]
        d = math.hypot(b[0] - a[0], b[1] - a[1])
        if d == 0:
            continue
        pos = step - acc
        while pos <= d:
            t = pos / d
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
            pos += step
        acc = d - (pos - step)
    return out


def chain(pts, r0, r1, color, y=0.0, color2=None, step=0.3, **kw):
    """tube made of overlapping spheres along a 2D path (x,z), radius r0 -> r1"""
    pts = resample(pts, 0.01)  # dense
    # arc-length param
    L = [0.0]
    for i in range(1, len(pts)):
        L.append(L[-1] + math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]))
    total = L[-1]
    s = 0.0
    idx = 0
    placed = []
    while s <= total + 1e-6:
        while idx < len(L) - 1 and L[idx] < s:
            idx += 1
        t = s / total if total else 0
        r = r0 + (r1 - r0) * t
        c = color(t) if callable(color) else color
        placed.append((pts[idx], r, c, t))
        s += max(0.03, r * step * 2)
    # draw far end first so the thick end overlaps the thin one
    for (p, r, c, t) in reversed(placed):
        sph(r, (p[0], y, p[1]), c, seg=20, **kw)
    return placed


def sparkle(x, z, y=-0.5, s=0.5, color=WHITE, **kw):
    pts = [(0, 1), (0.2, 0.2), (1, 0), (0.2, -0.2), (0, -1), (-0.2, -0.2), (-1, 0), (-0.2, 0.2)]
    return poly(scale_pts(pts, s), 0.14, color, (x, y, z), bev=0.03, ol=0.05, neon=0.6, **kw)


def star5(x, z, y=-0.5, s=0.5, color=GOLD, depth=0.2):
    pts = []
    for i in range(10):
        a = math.radians(90 + i * 36)
        r = 1.0 if i % 2 == 0 else 0.45
        pts.append((math.cos(a) * r, math.sin(a) * r))
    return poly(scale_pts(pts, s), depth, color, (x, y, z), bev=0.04, ol=0.06)


def heart_pts(s=1.0):
    raw = []
    N = 96
    for i in range(N):
        t = i / N * 2 * math.pi
        x = 16 * math.sin(t) ** 3
        z = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        raw.append((x, z))
    for _ in range(4):  # round off the sharp cusp / tip so the bevel behaves
        raw = [((raw[i - 1][0] + 2 * raw[i][0] + raw[(i + 1) % N][0]) / 4, (raw[i - 1][1] + 2 * raw[i][1] + raw[(i + 1) % N][1]) / 4) for i in range(N)]
    zmin = min(z for _, z in raw)
    pts = [(x * 0.0345 * s, (z - zmin) * 0.0345 * s) for x, z in raw]  # tip at the origin, ~1.0*s tall
    return pts


def bolt_pts(s=1.0):
    return scale_pts([(0.35, 1.3), (-0.55, -0.1), (0.0, -0.1), (-0.35, -1.3), (0.6, 0.25), (0.05, 0.25)], s)


def drop(x, z, y=-0.3, s=0.3, color=(90, 190, 255)):
    sph(s, (x, y, z - s * 0.2), color, seg=16, ol=0.05)
    cone(s * 0.85, s * 1.4, (x, y, z + s * 0.75), color, ol=0.05)


# ---------------------------------------------------------------------------
# The icons
# ---------------------------------------------------------------------------
def icon_Damage():
    RED, RED_L = (255, 80, 45), (255, 175, 90)
    star5(0, 0.15, 0.45, 1.75, (255, 215, 60), 0.18)
    for sgn in (-1, 1):
        with xf((0, sgn * -0.05, 0.1), (0, sgn * 42, 0)):
            blade = [(-0.2, -0.7), (0.2, -0.7), (0.2, 1.0), (0.0, 1.55), (-0.2, 1.0)]
            poly(blade, 0.2, RED, bev=0.07)
            poly([(-0.05, -0.55), (0.05, -0.55), (0.05, 1.0), (0.0, 1.25), (-0.05, 1.0)], 0.27, RED_L, bev=0.03, outline=False, neon=0.4)
            poly([(-0.7, -1.0), (0.7, -1.0), (0.7, -0.62), (-0.7, -0.62)], 0.36, GOLD, bev=0.1)
            cyl(0.13, 0.7, (0, 0, -1.25), WOOD, rot=(0, 0, 0), bev=0.03)
            sph(0.21, (0, 0, -1.7), GOLD)


def icon_Health():
    T, TL = (30, 195, 200), (130, 245, 235)
    shield = [(-1.0, 1.0), (0, 0.78), (1.0, 1.0), (1.0, 0.1), (0.72, -0.55), (0, -1.15), (-0.72, -0.55), (-1.0, 0.1)]
    poly(shield, 0.4, T, bev=0.14)
    poly(scale_pts(shield, 0.74), 0.45, TL, pos=(0, -0.02, -0.03), bev=0.1, neon=0.25)
    # white plus
    poly([(-0.14, 0.52), (0.14, 0.52), (0.14, 0.14), (0.5, 0.14), (0.5, -0.14), (0.14, -0.14), (0.14, -0.5), (-0.14, -0.5),
          (-0.14, -0.14), (-0.5, -0.14), (-0.5, 0.14), (-0.14, 0.14)], 0.2, WHITE, pos=(0, -0.3, 0.02), bev=0.05, ol=0.05)
    # bubbles
    for (x, z, r) in ((-0.95, 1.05, 0.26), (1.0, -0.2, 0.2), (-1.05, 0.2, 0.15)):
        sph(r, (x, -0.35, z), (190, 240, 255), ol=0.05, neon=0.3)
        hl(x - r * 0.3, z + r * 0.35, -0.35 - r * 0.9, r * 0.25, r * 0.28)


def icon_HatchSpeed():
    R = (1.0, 0.95, 1.35)
    with xf((-0.35, 0, -0.05)):
        egg(R, (0, 0, 0), CREAM)
        for (x, z, r) in ((-0.35, 0.3, 0.17), (0.35, -0.3, 0.2), (-0.2, -0.75, 0.14), (0.3, 0.55, 0.13)):
            sph((r, 0.05, r), (x, egg_y(R, x, z) + 0.03, z), (255, 210, 70), seg=16, outline=False)
        hl(-0.45, 0.85, -0.9, 0.1, 0.22, rot=(0, -20, 0))
    poly(bolt_pts(1.05), 0.34, (255, 225, 40), pos=(0.7, -0.55, -0.05), bev=0.08, neon=0.7)
    sparkle(1.75, 1.15, -0.6, 0.3, WHITE)
    sparkle(-1.65, 1.2, -0.6, 0.22, (255, 235, 90))


def icon_EggLuck():
    R = (1.3, 1.1, 1.75)
    egg(R, (0, 0, 0), CREAM)
    hl(-0.7, 1.0, -1.0, 0.12, 0.28, rot=(0, -20, 0))
    G, GL = (50, 195, 85), (130, 235, 120)
    with xf((0, -1.3, 0.1), (0, 0, 0), 1.0):
        chain([(0.1, -0.1), (0.2, -0.7), (0.5, -1.15), (0.95, -1.25)], 0.11, 0.08, (40, 150, 70), y=0.15, ol=0.05)
        for k in range(4):
            with xf((0, 0, 0), (0, 45 + k * 90, 0)):
                poly(heart_pts(1.05), 0.3, G if k % 2 == 0 else (60, 210, 100), pos=(0, -0.02 * k, 0.03), bev=0.035)
        sph(0.15, (0, -0.3, 0), GL, ol=0.05)


def icon_Coins():
    def coin(x, z, y, r, rot=(0, 0, 0)):
        cyl(r, 0.3 * r + 0.05, (x, y, z), GOLD, rot=(90 + rot[0], rot[1], rot[2]), bev=0.05)
        cyl(r * 0.78, 0.36 * r + 0.05, (x, y - 0.02, z), (255, 232, 110), rot=(90 + rot[0], rot[1], rot[2]), bev=0.03, outline=False)
        cyl(r * 0.62, 0.38 * r + 0.05, (x, y - 0.04, z), GOLD_D, rot=(90 + rot[0], rot[1], rot[2]), bev=0.03, outline=False)
    coin(1.25, 1.05, 0.5, 0.42, (0, 25, 0))
    coin(-1.45, -0.55, 0.45, 0.36, (0, -25, 0))
    coin(-0.05, 0.05, -0.2, 1.1)
    star5(-0.05, 0.05, -0.8, 0.52, (255, 245, 150), 0.12)
    for (x, z, s) in ((0.75, -1.3, 0.28), (1.6, -0.45, 0.33), (-1.05, 1.35, 0.2)):
        drop(x, z, -0.6, s)
    sparkle(-1.45, 1.55, -0.7, 0.3)
    sparkle(0.3, 1.7, -0.7, 0.26, (255, 250, 200))


def icon_Pearls():
    L, LL = (190, 150, 255), (235, 215, 255)
    sph(0.95, (0, 0.05, -0.1), L)
    sph(0.8, (0.03, -0.12, -0.04), LL, outline=False, neon=0.35)  # soft inner sheen
    sph(0.75, (0.0, -0.25, -0.1), L, outline=False, rough=0.15)
    hl(-0.35, 0.45, -0.95, 0.24, 0.16, rot=(0, -35, 0))
    sph(0.07, (0.3, -0.98, -0.45), WHITE, outline=False, neon=0.5)
    for (x, z, r) in ((-1.35, 0.95, 0.34), (1.2, 1.15, 0.28), (1.45, -0.6, 0.3), (-1.2, -1.0, 0.25)):
        sph(r, (x, -0.1, z), L)
        hl(x - r * 0.3, z + r * 0.35, -0.1 - r * 0.9, r * 0.28, r * 0.2, rot=(0, -35, 0))
    for (x, z) in ((-1.4, 1.55), (1.15, 1.8), (1.5, 0.3), (-1.0, -0.2)):
        poly([(-0.045, -0.3), (0.045, -0.3), (0.045, 0.3), (-0.045, 0.3)], 0.08, (160, 215, 255), pos=(x, -0.4, z), bev=0.02, ol=0.04, neon=0.5)
    sparkle(0.9, 0.7, -0.6, 0.28)
    sparkle(-0.85, 1.55, -0.6, 0.24, (255, 240, 255))


def icon_Haul():
    B = (60, 160, 255)
    # eggs sit in the hook's curve
    R = (0.8, 0.75, 1.05)
    egg(R, (0.95, 0.5, -0.45), CREAM, rot=(0, 10, 0))
    for (x, z) in ((0.8, 0.0), (1.2, -0.6), (0.65, -0.65)):
        sph((0.13, 0.05, 0.13), (x + 0.0, 0.5 + egg_y(R, x - 0.95, z + 0.45) + 0.03, z), (255, 190, 80), seg=12, outline=False)
    egg((0.55, 0.5, 0.75), (-1.0, 0.5, -1.35), (255, 220, 110), rot=(0, -15, 0))
    egg((0.5, 0.45, 0.7), (2.2, 0.5, -1.4), (180, 235, 255), rot=(0, 15, 0))
    # hook (J shape, arc centre (0.95,-0.2) radius 0.95)
    path = [(0.0, 2.1), (0.0, -0.2)]
    for i in range(1, 21):
        t = math.pi + i / 20 * math.pi
        path.append((0.95 + 0.95 * math.cos(t), -0.2 + 0.95 * math.sin(t)))
    path += [(1.9, 0.5)]
    chain(path, 0.19, 0.19, B, y=-0.1, ol=0.07)
    cone(0.3, 0.6, (1.9, -0.1, 0.75), (200, 225, 255), ol=0.06)
    ring = [(0.0 + 0.33 * math.cos(a), 2.4 + 0.33 * math.sin(a)) for a in [i * math.pi / 10 for i in range(21)]]
    chain(ring, 0.1, 0.1, (200, 225, 255), y=-0.1, ol=0.05)
    hl(-0.1, 1.1, -0.38, 0.05, 0.6)
    sparkle(2.0, 1.7, -0.5, 0.3)


def icon_FuseLuck():
    P = (255, 95, 170)
    poly(heart_pts(3.4), 0.75, P, pos=(0, 0, -1.55), bev=0.09, ol=0.09)
    hl(-0.85, 0.7, -0.5, 0.16, 0.36, rot=(0, 20, 0))
    hl(-0.4, 1.12, -0.5, 0.08, 0.08)
    sparkle(1.25, 1.15, -0.5, 0.45, (255, 235, 90))
    sparkle(-1.35, 1.35, -0.5, 0.32, WHITE)
    sparkle(1.5, -0.1, -0.5, 0.26, (140, 230, 255))
    sparkle(0.3, 1.55, -0.5, 0.2, WHITE)


def icon_Mutation():
    R = (1.15, 1.0, 1.5)
    egg(R, (0, 0, 0), WHITE, material=rainbow_mat())
    hl(-0.55, 0.95, -0.98, 0.13, 0.3, rot=(0, -20, 0))
    hl(-0.2, 1.3, -0.9, 0.07, 0.07)
    sparkle(1.5, 1.2, -0.5, 0.45, (255, 235, 90))
    sparkle(-1.45, -0.3, -0.5, 0.35, WHITE)
    sparkle(1.35, -1.0, -0.5, 0.28, (140, 230, 255))
    sparkle(-1.2, 1.5, -0.5, 0.24, (255, 190, 240))


def crown(blue=True, gem_mid=(80, 200, 255), tip=(255, 255, 255), band_gems=((80, 200, 255),) * 3):
    pts = [(-1.1, -0.7), (1.1, -0.7), (1.3, 0.8), (0.55, 0.2), (0, 1.1), (-0.55, 0.2), (-1.3, 0.8)]
    poly(pts, 0.5, GOLD, bev=0.15)
    poly([(-1.1, -0.7), (1.1, -0.7), (1.14, -0.3), (-1.14, -0.3)], 0.6, GOLD_D, pos=(0, -0.02, 0), bev=0.1)
    for x, z in ((-1.3, 0.95), (0, 1.3), (1.3, 0.95)):
        sph(0.23, (x, -0.05, z), tip)
    sph((0.3, 0.2, 0.36), (0, -0.33, 0.2), gem_mid, neon=0.5)
    for x, c in zip((-0.72, 0, 0.72), band_gems):
        sph((0.17, 0.12, 0.13), (x, -0.36, -0.5), c, neon=0.5, ol=0.05)
    hl(-0.7, 0.3, -0.3, 0.08, 0.25, rot=(0, 0, 25))


def icon_Crown():
    with xf((0, 0, -0.1)):
        crown(gem_mid=(70, 190, 255), tip=(120, 215, 255))
    # tide waves under
    for sgn in (-1, 1):
        sparkle(sgn * 1.55, 0.75 if sgn > 0 else -0.1, -0.4, 0.28, (140, 230, 255))


def icon_Storm():
    CL = (120, 135, 215)
    # cloud
    sph(0.75, (-0.95, 0.15, 0.4), CL)
    sph(0.95, (0.0, 0.18, 0.85), CL)
    sph(0.75, (0.95, 0.15, 0.4), CL)
    cyl(0.5, 2.0, (0, 0.1, 0.0), CL, rot=(0, 90, 0))
    sph(0.5, (-1.0, 0.1, 0.0), CL)
    sph(0.5, (1.0, 0.1, 0.0), CL)
    hl(-0.35, 1.25, -0.8, 0.28, 0.14, rot=(0, -30, 0))
    hl(-1.2, 0.7, -0.7, 0.14, 0.09)
    poly(bolt_pts(1.2), 0.4, (255, 225, 40), pos=(0.1, -0.7, -0.75), bev=0.09, neon=0.8)
    for (x, z) in ((-1.35, -0.8), (-0.85, -1.35), (1.4, -1.0)):
        drop(x, z, -0.2, 0.2)


def tentacle(ctrl, r0, r1, c, c2, y=0.0, suckers=True, ol=0.07):
    path = catmull(ctrl, 16)
    placed = chain(path, r0, r1, c, y=y, ol=ol)
    if suckers:
        k = 0
        for (p, r, col, t) in reversed(placed):
            k += 1
            if k % 2 == 0 and r > 0.1:
                sph((r * 0.42, r * 0.2, r * 0.42), (p[0] - r * 0.1, y - r * 0.9, p[1]), c2, seg=12, outline=False)


def icon_Kraken():
    P, P2 = (150, 85, 235), (255, 170, 230)
    tentacle([(0.9, -1.7), (0.7, -0.9), (1.1, -0.1), (0.7, 0.6), (-0.1, 0.9), (-0.55, 0.45), (-0.2, 0.15)], 0.42, 0.08, (110, 60, 190), (230, 140, 210), y=0.45)
    tentacle([(-0.8, -1.7), (-0.6, -0.9), (-0.9, 0.0), (-0.4, 0.8), (0.4, 1.3), (1.0, 1.7), (1.35, 1.4), (1.15, 1.15)], 0.5, 0.09, P, P2, y=0.0)
    for (x, z) in ((-1.35, -1.0),):
        pass


def icon_Abyss():
    D = (80, 40, 150)
    # tentacle tips
    tentacle([(-1.8, -1.2), (-1.5, -0.4), (-1.9, 0.3), (-1.6, 1.0)], 0.28, 0.07, (120, 60, 200), (230, 140, 210), y=0.3, suckers=False)
    tentacle([(1.8, -1.2), (1.5, -0.4), (1.9, 0.3), (1.6, 1.0)], 0.28, 0.07, (120, 60, 200), (230, 140, 210), y=0.3, suckers=False)
    # eye
    sph((1.45, 0.65, 1.0), (0, 0, 0), (245, 235, 255))
    sph((0.82, 0.3, 0.82), (0, -0.55, 0), (190, 60, 255), neon=0.8, outline=True, ol=0.06)
    sph((0.5, 0.2, 0.5), (0, -0.78, 0), (255, 120, 235), neon=0.8, outline=False)
    sph((0.13, 0.1, 0.55), (0, -0.88, 0), (15, 5, 40), outline=False, rough=0.2)
    hl(-0.35, 0.4, -0.95, 0.16, 0.12, rot=(0, -20, 0))
    sph(0.05, (0.3, -0.95, -0.25), WHITE, outline=False, neon=0.6)
    # brow ridge
    poly([(-1.6, 0.9), (-0.7, 1.35), (0.7, 1.35), (1.6, 0.9), (0.8, 1.05), (-0.8, 1.05)], 0.35, D, pos=(0, 0.25, 0.3), bev=0.07)
    for x in (-1.0, 0, 1.0):
        sparkle(x * 0.8, 1.9, -0.3, 0.2, (210, 120, 255))



def icon_Treasure():
    def stack(x, y, z0, n, r, rot=0):
        for i in range(n):
            c = GOLD if i % 2 == 0 else (255, 225, 90)
            cyl(r, 0.22, (x + 0.03 * (i % 2), y, z0 + i * 0.22), c, bev=0.05, ol=0.06)
    stack(-0.6, 0.3, -1.1, 6, 0.8)
    stack(0.7, 0.0, -1.1, 4, 0.75)
    stack(0.0, -0.9, -1.1, 3, 0.7)
    # leaning coin
    cyl(0.7, 0.2, (0.05, -0.1, 0.65), GOLD, rot=(78, 0, 0), bev=0.05)
    cyl(0.5, 0.24, (0.05, -0.2, 0.67), GOLD_D, rot=(78, 0, 0), bev=0.03, outline=False)
    sparkle(1.35, 0.8, -0.8, 0.35, WHITE)
    sparkle(-1.5, 0.3, -0.9, 0.28, (255, 250, 200))
    sph((0.3, 0.2, 0.3), (1.2, -1.0, -0.9), (255, 70, 110), neon=0.5)



def icon_Whirlpool():
    pts = []
    n = 60
    for i in range(n + 1):
        t = i / n
        a = t * 2.4 * 2 * math.pi
        r = 1.45 * (1 - t) + 0.12
        pts.append((r * math.cos(a), r * math.sin(a)))
    def col(t):
        a = (40, 120, 235)
        b = (170, 235, 255)
        return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))
    chain(pts, 0.3, 0.14, col, y=0.0, step=0.4, ol=0.06)
    sph(0.16, (0, -0.2, 0), WHITE, neon=0.5, ol=0.05)
    hl(-0.6, 0.9, -0.3, 0.14, 0.1)
    sparkle(1.45, 1.15, -0.4, 0.3, WHITE)
    sparkle(-1.45, -1.1, -0.4, 0.25, (255, 250, 200))



def icon_GoldenEgg():
    R = (1.15, 1.0, 1.5)
    egg(R, (0, 0, 0), (255, 195, 35), metal=0.55, rough=0.2)
    # band highlights
    hl(-0.55, 0.95, -0.98, 0.13, 0.32, rot=(0, -20, 0))
    hl(-0.25, 1.3, -0.9, 0.07, 0.07)
    sparkle(1.5, 1.2, -0.5, 0.5, WHITE)
    sparkle(-1.5, 0.4, -0.5, 0.36, (255, 250, 200))
    sparkle(1.4, -0.9, -0.5, 0.3, (255, 235, 120))
    sparkle(-1.1, -1.3, -0.5, 0.22, WHITE)


def icon_King():
    G = (255, 200, 40)
    with xf((0, 0.5, 0.7)):
        chain([(0, -2.0), (0, 1.9)], 0.17, 0.17, GOLD_D, y=0, ol=0.07)
        arc = [(-1.0 * math.cos(math.pi * i / 16), 2.7 - 1.1 * math.sin(math.pi * i / 16)) for i in range(17)]
        chain(arc, 0.14, 0.14, G, y=0, ol=0.06)
        chain([(-1.0, 2.7), (-1.0, 3.0)], 0.14, 0.14, G, y=0, ol=0.06)
        chain([(1.0, 2.7), (1.0, 3.0)], 0.14, 0.14, G, y=0, ol=0.06)
        chain([(0, 1.6), (0, 3.2)], 0.14, 0.14, G, y=0, ol=0.06)
        cone(0.3, 0.8, (-1.0, 0, 3.35), (255, 225, 90), ol=0.06)
        cone(0.3, 0.8, (1.0, 0, 3.35), (255, 225, 90), ol=0.06)
        cone(0.34, 0.95, (0, 0, 3.65), (255, 225, 90), ol=0.06)
    with xf((0, -0.4, -0.55), (0, 0, 0), 1.5):
        crown(gem_mid=(255, 70, 90), tip=(250, 240, 255), band_gems=((255, 70, 90), (80, 200, 255), (255, 70, 90)))
    sparkle(-2.0, 2.3, -1.2, 0.4)
    sparkle(2.1, 0.9, -1.2, 0.32, (255, 235, 90))


def icon_Fang():
    def burst(rO, rI, n, off=0.0):
        pts = []
        for i in range(n * 2):
            a = math.radians(90 + off + i * 180 / n)
            r = rO if i % 2 == 0 else rI
            pts.append((math.cos(a) * r, math.sin(a) * r))
        return pts
    poly(burst(1.95, 1.45, 10), 0.4, (240, 60, 45), pos=(0, 0.4, 0.0), bev=0.1, ol=0.08)
    poly(burst(1.45, 1.1, 10, 18), 0.4, (255, 160, 50), pos=(0, 0.1, 0.0), bev=0.08, outline=False, neon=0.35)
    tooth = [(-0.8, 1.0), (0.8, 1.0), (0.62, 0.35), (0.35, -0.5), (0.18, -1.3), (-0.18, -1.3), (-0.35, -0.5), (-0.62, 0.35)]
    poly(tooth, 0.5, (250, 250, 255), pos=(0, -0.4, 0.05), bev=0.07, ol=0.08)
    hl(-0.45, 0.55, -0.7, 0.07, 0.3, rot=(0, 0, 8), color=(210, 225, 250))


def icon_Moon():
    ro, ri, off = 1.45, 1.2, (0.6, 0.3)
    ox, oz = off
    D = math.hypot(ox, oz)
    # circle-circle intersection (outer centred at 0, inner centred at off)
    a = (ro * ro - ri * ri + D * D) / (2 * D)
    h = math.sqrt(ro * ro - a * a)
    mx, mz = ox / D * a, oz / D * a
    P1 = (mx + h * oz / D, mz - h * ox / D)
    P2 = (mx - h * oz / D, mz + h * ox / D)

    def ang(p, c=(0, 0)):
        return math.atan2(p[1] - c[1], p[0] - c[0])

    def sweep(c, r, a0, a1, mid):
        # points from angle a0 to a1 around c, going the way that passes through angle `mid`
        d = (a1 - a0) % (2 * math.pi)
        dm = (mid - a0) % (2 * math.pi)
        sgn = 1 if dm <= d else -1
        if sgn < 0:
            d = 2 * math.pi - d
        return [(c[0] + r * math.cos(a0 + sgn * d * i / 40), c[1] + r * math.sin(a0 + sgn * d * i / 40)) for i in range(41)]

    away = math.atan2(-oz, -ox)
    outer = sweep((0, 0), ro, ang(P1), ang(P2), away)
    inner = sweep(off, ri, ang(P2, off), ang(P1, off), away)
    pts = outer + inner[1:-1]
    poly(pts, 0.55, (255, 220, 90), pos=(-0.2, 0, 0), bev=0.07, ol=0.08)
    hl(-1.0, 0.45, -0.55, 0.1, 0.4, rot=(0, 25, 0))
    poly(heart_pts(1.0), 0.3, (255, 95, 170), pos=(0.55, -0.4, -0.35), bev=0.08)
    sparkle(0.6, 1.3, -0.4, 0.35, WHITE)
    sparkle(1.5, 0.35, -0.4, 0.26, (140, 230, 255))
    sparkle(-0.5, -1.4, -0.4, 0.2, (255, 250, 200))


ICONS = ["Damage", "Health", "HatchSpeed", "EggLuck", "Coins", "Pearls", "Haul", "FuseLuck", "Mutation", "Crown", "Storm",
         "Kraken", "Abyss", "King", "Treasure", "Fang", "Whirlpool", "Moon", "GoldenEgg"]
CAM_Z = {"Treasure": 3.6}


def setup_scene():
    scn = bpy.context.scene
    scn.render.engine = "BLENDER_EEVEE"
    scn.render.film_transparent = True
    scn.render.resolution_x = scn.render.resolution_y = 512
    scn.render.image_settings.file_format = "PNG"
    scn.render.image_settings.color_mode = "RGBA"
    scn.view_settings.view_transform = "Standard"
    try:
        scn.eevee.taa_render_samples = 48
    except Exception:
        pass
    scn.render.filter_size = 1.2
    if scn.world is None:
        scn.world = bpy.data.worlds.new("IconWorld")
    scn.world.use_nodes = True
    bg = scn.world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (1, 1, 1, 1)
    bg.inputs["Strength"].default_value = 0.85
    for ob in list(scn.collection.all_objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    cam_data = bpy.data.cameras.new("IconCam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("IconCam", cam_data)
    scn.collection.objects.link(cam)
    scn.camera = cam
    sun = bpy.data.objects.new("IconSun", bpy.data.lights.new("IconSun", "SUN"))
    sun.data.energy = 3.2
    sun.rotation_euler = (math.radians(42), math.radians(-18), math.radians(-28))
    scn.collection.objects.link(sun)
    fill = bpy.data.objects.new("IconFill", bpy.data.lights.new("IconFill", "SUN"))
    fill.data.energy = 1.0
    fill.rotation_euler = (math.radians(70), math.radians(25), math.radians(40))
    scn.collection.objects.link(fill)
    return scn


def fit_camera(scn, name):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for ob in COLL.objects:
        for c in ob.bound_box:
            w = ob.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    center = (lo + hi) / 2
    size = max(hi.x - lo.x, hi.z - lo.z, 1.0)
    cam = scn.camera
    cam.data.ortho_scale = size * 1.22 + 0.25
    cam.location = center + Vector((1.0, -9, CAM_Z.get(name, 1.5)))
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()


def render_all():
    global COLL, XF
    scn = setup_scene()
    only = os.environ.get("SPELL_ONLY")
    only = [s for s in only.split(",") if s] if only else None
    done = []
    for name in ICONS:
        if only and name not in only:
            continue
        COLL = bpy.data.collections.new("Icon_" + name)
        scn.collection.children.link(COLL)
        XF = Matrix.Identity(4)
        globals()["icon_" + name]()
        bpy.context.view_layer.update()
        fit_camera(scn, name)
        scn.render.filepath = os.path.join(OUT, "Spell_" + name + ".png")
        bpy.ops.render.render(write_still=True, scene=scn.name)
        for ob in list(COLL.objects):
            bpy.data.objects.remove(ob, do_unlink=True)
        bpy.data.collections.remove(COLL)
        done.append(name)
        print("RENDERED", name, flush=True)
    return done


render_all()
