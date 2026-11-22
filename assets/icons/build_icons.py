# Renders every HUD icon for Tide Tamers as a chunky voxel 3D icon with a thick navy
# outline (inverted-hull), transparent background, 512x512 PNG -> assets/icons/png/<Name>.png
# Same block style as the monsters (assets/monsters/spec.py), so the UI matches the world.
#
# Run inside Blender:
#   exec(open(r"G:\Projects\CODES\sea\assets\icons\build_icons.py").read())
import bpy, bmesh, math, os
from mathutils import Matrix, Vector, Euler

OUT = r"G:\Projects\CODES\sea\assets\icons\png"
os.makedirs(OUT, exist_ok=True)

NAVY = (16, 22, 44)
WHITE = (255, 255, 255)
GOLD = (255, 205, 50)
GOLD_D = (220, 150, 20)
WOOD = (150, 96, 56)
WOOD_D = (105, 64, 38)
BLUE = (40, 150, 255)
RED = (240, 60, 70)
PINK = (255, 110, 170)
PURPLE = (160, 100, 255)
GREEN = (70, 210, 110)
TEAL = (40, 200, 200)


def srgb(c):
    def g(v):
        v = v / 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return (g(c[0]), g(c[1]), g(c[2]), 1)


MATS = {}


def mat(color, neon=False, metal=False):
    key = (tuple(color), neon, metal)
    if key in MATS:
        return MATS[key]
    m = bpy.data.materials.new("Icon_%02x%02x%02x" % tuple(color))
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = srgb(color)
    b.inputs["Roughness"].default_value = 0.35
    if neon:
        b.inputs["Emission Color"].default_value = srgb(color)
        b.inputs["Emission Strength"].default_value = 1.5
    if metal:
        b.inputs["Metallic"].default_value = 0.6
    MATS[key] = m
    return m


def outline_mat():
    if "IconOutline" in bpy.data.materials:
        return bpy.data.materials["IconOutline"]
    m = bpy.data.materials.new("IconOutline")
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


def block(size, pos=(0, 0, 0), color=WHITE, rot=(0, 0, 0), neon=False, metal=False, sphere=False, cyl=False):
    """size/pos in Blender units, Z up. rot in degrees."""
    bm = bmesh.new()
    if sphere:
        bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=0.5)
    elif cyl:
        bmesh.ops.create_cone(bm, cap_ends=True, segments=24, radius1=0.5, radius2=0.5, depth=1.0)
    else:
        bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.transform(bm, matrix=Matrix.Diagonal((size[0], size[1], size[2], 1)), verts=bm.verts)
    if not sphere and not cyl:
        bev = min(0.06, min(size) * 0.15)
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bev, segments=2, affect="EDGES")
    me = bpy.data.meshes.new("b")
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = sphere or cyl
    me.materials.append(mat(color, neon, metal))
    me.materials.append(outline_mat())
    ob = bpy.data.objects.new("b", me)
    ob.location = pos
    ob.rotation_euler = Euler([math.radians(a) for a in rot])
    COLL.objects.link(ob)
    sol = ob.modifiers.new("Outline", "SOLIDIFY")
    sol.thickness = 0.09
    sol.offset = 1
    sol.use_flip_normals = True
    sol.material_offset = 1
    return ob


# ---------------------------------------------------------------------------
# Icons (each builds into COLL; the camera frames everything)
# ---------------------------------------------------------------------------
def coin(x=0, y=0, z=0, s=1.0):
    block((1.8 * s, 1.8 * s, 0.35 * s), (x, y, z), GOLD, rot=(90, 0, 0), cyl=True)
    block((1.3 * s, 1.3 * s, 0.38 * s), (x, y - 0.02, z), GOLD_D, rot=(90, 0, 0), cyl=True)
    # anchor
    block((0.18 * s, 0.2 * s, 0.75 * s), (x, y - 0.25, z), GOLD)
    block((0.6 * s, 0.2 * s, 0.16 * s), (x, y - 0.25, z + 0.2 * s), GOLD)
    block((0.6 * s, 0.2 * s, 0.16 * s), (x, y - 0.25, z - 0.3 * s), GOLD)


def icon_Coin():
    coin()


def icon_Pearl():
    block((1.8, 1.0, 0.4), (0, 0.2, -0.7), PINK, rot=(10, 0, 0))
    block((1.6, 0.9, 0.35), (0, 0.5, 0.3), PINK, rot=(-55, 0, 0))
    block((0.95, 0.95, 0.95), (0, -0.1, -0.25), (245, 235, 255), sphere=True)


def icon_Shell():
    for i in range(5):
        a = -50 + i * 25
        block((0.35, 0.3, 1.5), (math.sin(math.radians(a)) * 0.6, 0, math.cos(math.radians(a)) * 0.6 - 0.3),
              (255, 170, 120) if i % 2 == 0 else (255, 210, 170), rot=(0, a, 0))
    block((0.8, 0.35, 0.4), (0, 0, -0.85), (240, 140, 100))


def icon_Shop():
    block((2.0, 1.4, 1.1), (0, 0, -0.4), WOOD)
    block((2.1, 1.5, 0.25), (0, 0, -0.95), WOOD_D)
    block((2.0, 1.4, 0.5), (0, 0.55, 0.55), WOOD, rot=(-40, 0, 0))
    for x in (-0.75, 0.75):
        block((0.2, 1.45, 1.15), (x, 0, -0.4), GOLD_D)
    for (x, z) in ((-0.5, 0.3), (0.1, 0.4), (0.55, 0.25), (-0.1, 0.15)):
        block((0.55, 0.15, 0.55), (x, -0.3, z), GOLD, rot=(70, 0, x * 40))
    block((0.4, 0.2, 0.4), (0, -0.75, -0.3), GOLD)


def icon_Event():
    # ship's wheel with a star in the middle
    block((1.9, 1.9, 0.3), (0, 0, 0), WOOD, cyl=True, rot=(90, 0, 0))
    block((1.3, 1.3, 0.35), (0, -0.02, 0), (255, 170, 60), cyl=True, rot=(90, 0, 0))
    for i in range(8):
        a = i * 45
        block((0.22, 0.25, 0.6), (math.sin(math.radians(a)) * 1.2, 0, math.cos(math.radians(a)) * 1.2), WOOD_D,
              rot=(0, a, 0))
    for i in range(5):
        a = i * 72
        block((0.32, 0.3, 0.62), (math.sin(math.radians(a)) * 0.28, -0.12, math.cos(math.radians(a)) * 0.28), GOLD,
              rot=(0, a, 0))
    block((0.4, 0.3, 0.4), (0, -0.14, 0), GOLD)


def icon_Index():
    block((1.7, 0.6, 2.0), (0, 0, 0), BLUE, rot=(0, 0, -8))
    block((1.5, 0.62, 1.85), (0.12, 0.02, 0), (250, 245, 230), rot=(0, 0, -8))
    block((1.55, 0.2, 2.02), (-0.05, -0.32, 0), BLUE, rot=(0, 0, -8))
    block((0.6, 0.25, 0.8), (0.05, -0.45, 0.1), TEAL, rot=(0, 0, 20))
    block((0.15, 0.24, 2.0), (-0.78, -0.3, 0), (30, 100, 200), rot=(0, 0, -8))


def icon_Team():
    # Splashfin head
    B1, B2, BL = (40, 150, 255), (25, 105, 210), (190, 235, 255)
    block((1.8, 1.4, 1.6), (0, 0, 0), B1)
    block((1.3, 0.3, 0.55), (0, -0.7, -0.45), BL)
    for x in (-0.38, 0.38):
        block((0.42, 0.1, 0.5), (x, -0.72, 0.2), WHITE)
        block((0.22, 0.1, 0.3), (x - 0.03, -0.78, 0.17), NAVY)
    block((0.3, 0.7, 0.8), (0, 0, 1.0), B2, rot=(20, 0, 0))
    for x in (-1.0, 1.0):
        block((0.4, 0.2, 0.7), (x, 0.1, 0.1), B2, rot=(0, x * 30, 0))


def icon_Swords():
    for s in (-1, 1):
        r = (0, s * 40, 0)
        block((0.3, 0.2, 2.4), (s * 0.1, 0, 0.25), (220, 225, 235), rot=r, metal=True)
        block((0.9, 0.3, 0.22), (s * -0.55, 0, -0.55), GOLD, rot=r)
        block((0.25, 0.3, 0.6), (s * -0.75, 0, -0.85), WOOD_D, rot=r)


def icon_Heart():
    for s in (-1, 1):
        block((1.1, 0.6, 1.1), (s * 0.45, 0, 0.35), PINK, sphere=True)
    block((1.3, 0.6, 1.3), (0, 0, -0.25), PINK, rot=(0, 45, 0))
    block((0.35, 0.1, 0.2), (-0.5, -0.32, 0.6), (255, 225, 240), rot=(0, -30, 0))


def icon_Gift():
    block((1.8, 1.4, 1.4), (0, 0, -0.35), (40, 190, 200))
    block((2.0, 1.5, 0.4), (0, 0, 0.45), (30, 160, 175))
    block((0.35, 1.55, 1.85), (0, 0, -0.1), GOLD)
    block((2.05, 1.55, 0.3), (0, 0, 0.45), GOLD)
    for s in (-1, 1):
        block((0.7, 0.3, 0.55), (s * 0.35, 0, 0.9), GOLD, rot=(0, s * 35, 0))


def icon_Power():
    # golden trident
    block((0.25, 0.25, 2.6), (0, 0, -0.3), GOLD_D)
    block((1.4, 0.3, 0.25), (0, 0, 0.95), GOLD)
    for x in (-0.6, 0, 0.6):
        block((0.22, 0.25, 0.8 if x == 0 else 0.6), (x, 0, 1.4 if x == 0 else 1.25), GOLD)
        block((0.4, 0.25, 0.35), (x, 0, 1.85 if x == 0 else 1.6), GOLD, rot=(0, 45, 0))
    block((0.45, 0.4, 0.45), (0, -0.05, 0.95), (120, 230, 255), neon=True)


def icon_Lock():
    block((1.6, 0.8, 1.3), (0, 0, -0.4), GOLD)
    block((0.3, 0.6, 0.45), (0, -0.25, -0.4), NAVY)
    for x in (-0.5, 0.5):
        block((0.28, 0.4, 0.9), (x, 0, 0.55), (200, 205, 215), metal=True)
    block((1.28, 0.4, 0.28), (0, 0, 0.95), (200, 205, 215), metal=True)


def icon_Speed():
    for x in (-0.45, 0.45):
        bm_tri(x)


def bm_tri(x):
    # a fat right-pointing arrowhead made of 3 stacked blocks
    for i, (w, z) in enumerate(((0.3, 0.75), (0.3, 0.38), (0.3, 0.0), (0.3, -0.38), (0.3, -0.75))):
        depth = 1 - abs(i - 2) * 0.33
        block((0.9 * depth, 0.4, 0.4), (x + 0.45 * depth - 0.45, 0, z), GREEN)


def icon_Skull():
    block((1.6, 1.4, 1.4), (0, 0, 0.2), (245, 240, 230))
    block((1.1, 1.2, 0.5), (0, 0, -0.65), (245, 240, 230))
    for x in (-0.38, 0.38):
        block((0.45, 0.2, 0.45), (x, -0.62, 0.2), NAVY)
    for x in (-0.3, 0, 0.3):
        block((0.15, 0.2, 0.3), (x, -0.6, -0.65), NAVY)


def icon_Boss():
    icon_Skull()
    for x in (-0.7, 0.7):
        block((0.3, 0.3, 0.9), (x, 0, 1.15), RED, rot=(0, x * -40, 0))
    block((1.2, 0.3, 0.3), (0, 0, 1.05), GOLD)


def icon_LuckEgg():
    for i, (w, z) in enumerate(((1.1, -0.85), (1.5, -0.45), (1.6, 0.05), (1.4, 0.5), (1.0, 0.88), (0.55, 1.12))):
        block((w, w, 0.42 if i < 5 else 0.2), (0, 0, z), (255, 200, 130) if i % 2 == 0 else (255, 220, 160))
    for (x, z) in ((-0.3, 0.15), (0.3, 0.15), (0, 0.45), (0, -0.15)):
        block((0.38, 0.2, 0.38), (x + 0.55, -0.85, z - 0.45), GREEN, rot=(0, 45, 0))


def icon_Pedestal():
    block((1.8, 1.8, 0.4), (0, 0, -0.9), (240, 240, 250))
    block((1.5, 1.5, 0.8), (0, 0, -0.35), BLUE)
    for i, (w, z) in enumerate(((0.7, 0.2), (1.0, 0.5), (1.05, 0.85), (0.75, 1.15), (0.4, 1.35))):
        block((w, w, 0.32), (0, 0, z), (255, 140, 70) if i % 2 == 0 else (255, 180, 100))


def icon_Crate():
    block((1.8, 1.8, 1.6), (0, 0, -0.1), (60, 40, 110))
    for z in (-0.75, 0.55):
        block((1.9, 1.9, 0.25), (0, 0, z), (110, 70, 190))
    for x in (-0.82, 0.82):
        block((0.25, 1.9, 1.6), (x, 0, -0.1), (110, 70, 190))
    block((0.6, 0.2, 0.6), (0, -0.95, -0.1), (190, 120, 255), neon=True)


def icon_Robux():
    # a green price tag with a hole (no logo copying)
    block((1.9, 0.4, 1.2), (0.1, 0, 0), GREEN, rot=(0, 0, 0))
    block((0.9, 0.4, 0.9), (-0.85, 0, 0), GREEN, rot=(0, 45, 0))
    block((0.3, 0.45, 0.3), (-0.85, -0.02, 0), NAVY, sphere=True)


# ---------------------------------------------------------------------------
# Store icons: one per gamepass (Pass_*) and developer product (Prod_*). Same chunky style.
# Upload these as the item icons in Creator Hub (and Config.STORE_ICONS for the in-game shop).
# ---------------------------------------------------------------------------
def bolt(x=0, y=-0.3, z=0, s=1.0, color=GOLD):
    block((0.5 * s, 0.35, 0.9 * s), (x + 0.15 * s, y, z + 0.5 * s), color, rot=(0, 25, 0), neon=True)
    block((0.5 * s, 0.35, 0.9 * s), (x - 0.15 * s, y, z - 0.35 * s), color, rot=(0, 25, 0), neon=True)
    block((0.8 * s, 0.35, 0.3 * s), (x, y, z + 0.05 * s), color, neon=True)


def star(x=0, y=-0.3, z=0, s=1.0, color=GOLD):
    block((1.0 * s, 0.35, 1.0 * s), (x, y, z), color, rot=(0, 45, 0))
    block((1.0 * s, 0.35, 1.0 * s), (x, y, z), color, rot=(0, 0, 0))


def clover(colors, y=0):
    for i, (dx, dz) in enumerate(((-0.55, 0.55), (0.55, 0.55), (-0.55, -0.35), (0.55, -0.35))):
        block((1.0, 0.5, 1.0), (dx, y, dz), colors[i], sphere=True)
    block((0.22, 0.3, 1.0), (0.1, y, -1.0), (50, 140, 60), rot=(0, 0, -25))


def icon_Pass_VIP():
    block((2.2, 0.8, 0.7), (0, 0, -0.55), GOLD, metal=True)
    for x, h in ((-0.85, 1.2), (0, 1.6), (0.85, 1.2)):
        block((0.55, 0.7, h), (x, 0, -0.2 + h / 2), GOLD, metal=True)
        block((0.35, 0.45, 0.35), (x, -0.3, -0.2 + h + 0.15), (255, 90, 120), sphere=True)
    for x in (-0.7, 0, 0.7):
        block((0.3, 0.2, 0.3), (x, -0.45, -0.55), (120, 230, 255), neon=True)


def icon_Pass_DoubleCoins():
    coin(-0.45, 0, 0.15, 1.1)
    coin(0.65, 0.4, -0.35, 0.95)
    block((0.9, 0.3, 0.3), (0.0, -0.7, 0.95), GREEN)
    block((0.3, 0.3, 0.9), (0.0, -0.7, 0.95), GREEN)


def icon_Pass_FastFuse():
    for s in (-1, 1):
        block((1.1, 0.6, 1.1), (s * 0.45, 0.2, 0.35), PINK, sphere=True)
    block((1.3, 0.6, 1.3), (0, 0.2, -0.25), PINK, rot=(0, 45, 0))
    bolt(0.25, -0.5, 0.0, 1.0)


def icon_Pass_FastBattle():
    icon_Swords()
    bolt(0, -0.6, -0.9, 0.7)


def icon_Pass_ExtraPedestal():
    icon_Pedestal()
    block((1.0, 0.3, 0.3), (1.0, -0.9, 1.2), GREEN)
    block((0.3, 0.3, 1.0), (1.0, -0.9, 1.2), GREEN)


def icon_Prod_StarterPack():
    block((1.9, 1.4, 1.3), (0, 0, -0.4), (255, 90, 120))
    block((2.1, 1.5, 0.4), (0, 0, 0.4), (220, 60, 100))
    block((0.35, 1.55, 1.75), (0, 0, -0.05), WHITE)
    block((2.15, 0.35, 0.4), (0, 0, 0.4), WHITE)
    star(0, -0.1, 1.15, 0.9)


def icon_Prod_FuseLuck():
    clover([(70, 200, 100)] * 4)
    star(1.0, -0.4, 1.0, 0.5)


def icon_Prod_InsaneLuck():
    clover([(255, 90, 90), (255, 205, 50), (70, 210, 110), (90, 150, 255)])
    star(1.0, -0.5, 1.1, 0.55, (255, 120, 220))
    star(-1.0, -0.5, 0.9, 0.4, (120, 230, 255))


def icon_Prod_Revive():
    for s in (-1, 1):
        block((1.1, 0.6, 1.1), (s * 0.45, 0, 0.25), PINK, sphere=True)
    block((1.3, 0.6, 1.3), (0, 0, -0.35), PINK, rot=(0, 45, 0))
    block((0.8, 0.3, 0.25), (0, -0.5, 0.05), WHITE)
    block((0.25, 0.3, 0.8), (0, -0.5, 0.05), WHITE)
    block((1.2, 0.3, 0.3), (0, 0, 1.35), GOLD, metal=True, rot=(80, 0, 0))


def icon_Prod_SkipTimer():
    block((1.7, 1.7, 0.3), (0, 0, 1.1), WOOD)
    block((1.7, 1.7, 0.3), (0, 0, -1.1), WOOD)
    block((1.2, 1.2, 0.9), (0, 0, 0.55), (190, 235, 255), rot=(0, 0, 0))
    block((1.2, 1.2, 0.9), (0, 0, -0.55), (190, 235, 255))
    block((0.3, 0.3, 0.4), (0, 0, 0), (255, 205, 50))
    block((0.8, 0.8, 0.4), (0, 0, -0.85), (255, 205, 50))
    bolt(1.2, -0.7, 0.0, 0.8, GREEN)


def icon_Prod_CoinsSmall():
    block((2.0, 1.4, 1.0), (0, 0, -0.5), WOOD)
    block((2.1, 1.5, 0.5), (0, 0, 0.25), WOOD_D)
    for x in (-0.8, 0.8):
        block((0.2, 1.55, 1.6), (x, 0, -0.1), GOLD_D)
    coin(0, -0.9, 0.2, 0.7)


def icon_Prod_CoinsBig():
    block((1.8, 1.6, 1.8), (-0.4, 0.2, -0.3), (160, 110, 60), sphere=True)
    block((0.9, 0.5, 0.3), (-0.4, 0.2, 0.6), (120, 80, 40))
    coin(0.6, -0.4, -0.7, 0.9)
    coin(-1.0, -0.7, -0.9, 0.7)
    coin(0.1, -0.9, 0.05, 0.8)


def icon_Prod_PearlDragonPack():
    W = (250, 240, 250)
    block((1.7, 1.4, 1.5), (0, 0, 0), W)
    block((1.2, 0.8, 0.8), (0, -0.9, -0.35), (255, 215, 235))
    for x in (-0.4, 0.4):
        block((0.4, 0.2, 0.4), (x, -0.72, 0.3), WHITE)
        block((0.2, 0.2, 0.25), (x, -0.8, 0.28), NAVY)
        block((0.3, 0.3, 1.0), (x * 2.0, 0.1, 1.15), GOLD, rot=(0, x * -60, 0))
    block((0.55, 0.55, 0.55), (0, -1.35, -0.45), (240, 235, 255), sphere=True, neon=True)


def icon_Prod_ElementBundle():
    for (x, z, c) in ((-0.65, 0.6, (40, 160, 255)), (0.65, 0.6, (255, 110, 150)), (-0.65, -0.65, (255, 214, 40)), (0.65, -0.65, (150, 80, 230))):
        block((1.15, 1.0, 1.4), (x, 0, z), c, sphere=True)
        block((0.35, 0.2, 0.35), (x - 0.15, -0.45, z + 0.25), WHITE, sphere=True)


def icon_Prod_LimitedRoll():
    icon_Crate()
    for x in (-0.6, 0.6):
        block((0.2, 0.2, 0.9), (x, -0.95, 1.1), (60, 62, 80), metal=True)
    block((0.5, 0.2, 0.5), (0, -1.1, -0.1), (255, 240, 150), neon=True)


def icon_Prod_PowerSpins():
    cols = [(255, 90, 70), (255, 205, 50), (90, 200, 110), (80, 190, 255), (190, 110, 255), (255, 80, 200)]
    block((2.2, 2.2, 0.4), (0, 0, 0), (60, 40, 110), cyl=True, rot=(90, 0, 0))
    for i, c in enumerate(cols):
        a = i * 60
        block((0.7, 0.3, 0.95), (math.sin(math.radians(a)) * 0.6, -0.25, math.cos(math.radians(a)) * 0.6), c, rot=(0, a, 0))
    block((0.4, 0.4, 0.4), (0, -0.5, 0), GOLD, sphere=True)
    block((0.35, 0.3, 0.7), (0, -0.4, 1.3), RED, rot=(0, 45, 0))


STORE_ICONS = ["Pass_VIP", "Pass_DoubleCoins", "Pass_FastFuse", "Pass_FastBattle", "Pass_ExtraPedestal",
               "Prod_StarterPack", "Prod_FuseLuck", "Prod_InsaneLuck", "Prod_Revive", "Prod_SkipTimer",
               "Prod_CoinsSmall", "Prod_CoinsBig", "Prod_PearlDragonPack", "Prod_ElementBundle",
               "Prod_LimitedRoll", "Prod_PowerSpins"]

ICONS = ["Coin", "Pearl", "Shell", "Shop", "Event", "Index", "Team", "Swords", "Heart", "Gift", "Power",
         "Lock", "Speed", "Skull", "Boss", "LuckEgg", "Pedestal", "Crate", "Robux"]


def setup_scene():
    scn = bpy.data.scenes.get("Icons") or bpy.data.scenes.new("Icons")
    if bpy.context.window:
        bpy.context.window.scene = scn
    scn.render.engine = "BLENDER_EEVEE"
    scn.render.film_transparent = True
    scn.render.resolution_x = scn.render.resolution_y = 512
    scn.render.image_settings.file_format = "PNG"
    scn.render.image_settings.color_mode = "RGBA"
    scn.view_settings.view_transform = "Standard"
    if scn.world is None:
        scn.world = bpy.data.worlds.new("IconWorld")
    scn.world.use_nodes = True
    bg = scn.world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (1, 1, 1, 1)
    bg.inputs["Strength"].default_value = 0.7
    for ob in list(scn.collection.all_objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    cam_data = bpy.data.cameras.new("IconCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 3.6
    cam = bpy.data.objects.new("IconCam", cam_data)
    scn.collection.objects.link(cam)
    # front view, tilted down a little and to the side for a chunky 3D read
    cam.location = Vector((2.2, -9, 2.6))
    cam.rotation_euler = (Vector((0, 0, 0)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scn.camera = cam
    sun = bpy.data.objects.new("IconSun", bpy.data.lights.new("IconSun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(40), math.radians(15), math.radians(25))
    scn.collection.objects.link(sun)
    return scn


def fit_camera(scn):
    # scale the ortho camera to the icon's bounds so every icon fills its square
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
    cam.data.ortho_scale = size * 1.35
    cam.location = center + Vector((2.2, -9, 2.6))
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()


def render_all():
    global COLL
    scn = setup_scene()
    done = []
    # set ONLY = ["Pass_VIP", ...] before exec to render a subset; store icons go to png/store/
    todo = [n for n in ICONS + STORE_ICONS if not globals().get("ONLY") or n in ONLY]
    os.makedirs(os.path.join(OUT, "store"), exist_ok=True)
    for name in todo:
        COLL = bpy.data.collections.new("Icon_" + name)
        scn.collection.children.link(COLL)
        globals()["icon_" + name]()
        bpy.context.view_layer.update()
        fit_camera(scn)
        scn.render.filepath = os.path.join(OUT, "store" if name in STORE_ICONS else "", name + ".png")
        bpy.ops.render.render(write_still=True, scene=scn.name)
        for ob in list(COLL.objects):
            bpy.data.objects.remove(ob, do_unlink=True)
        bpy.data.collections.remove(COLL)
        done.append(name)
    return done


result = {"icons": render_all(), "out": OUT}
