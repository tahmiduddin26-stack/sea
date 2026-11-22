# Renders the store art for Tide Tamers with the real monster models:
#   icon.png      1024x1024  Tsunamaw front and centre, Splashfin + Zappy either side, title
#   thumb_battle.png 1920x1080  three sea dragons on the water facing Maw rising out of the sea
#   thumb_fuse.png   1920x1080  two monsters fusing into a glowing egg with hearts
# Run inside Blender:
#   exec(open(r"G:\Projects\CODES\sea\assets\marketing\build_marketing.py").read())
import bpy, math, os
from mathutils import Vector

MARKETING_IMPORT = True
exec(open(r"G:\Projects\CODES\sea\assets\monsters\build_blender.py").read(), globals())

OUT = r"G:\Projects\CODES\sea\assets\marketing"
FONT = r"C:\Windows\Fonts\ariblk.ttf"
by_id = {c.id: c for c in spec.CREATURES}


def fresh_scene():
    scn = bpy.data.scenes.get("Marketing") or bpy.data.scenes.new("Marketing")
    bpy.context.window.scene = scn
    for ob in list(scn.collection.all_objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for c in list(scn.collection.children):
        for cc in list(c.children):
            bpy.data.collections.remove(cc)
        bpy.data.collections.remove(c)
    scn.render.engine = "BLENDER_EEVEE"
    scn.view_settings.view_transform = "Standard"
    scn.render.fps = 24
    if scn.world is None:
        scn.world = bpy.data.worlds.new("MktWorld")
    w = scn.world
    w.use_nodes = True
    nt = w.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    grad = nt.nodes.new("ShaderNodeTexGradient")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeMapping")
    # sky: bright cyan at the horizon to deep blue overhead
    ramp.color_ramp.elements[0].color = srgb((150, 225, 255))
    ramp.color_ramp.elements[1].color = srgb((40, 120, 230))
    nt.links.new(tc.outputs["Generated"], sep.inputs["Vector"])
    sep.inputs["Rotation"].default_value = (0, math.radians(-90), 0)
    nt.links.new(sep.outputs["Vector"], grad.inputs["Vector"])
    nt.links.new(grad.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 1.1
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])
    coll = bpy.data.collections.new("Mkt")
    scn.collection.children.link(coll)
    sun = bpy.data.objects.new("MktSun", bpy.data.lights.new("MktSun", "SUN"))
    sun.data.energy = 4.0
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(150))
    coll.objects.link(sun)
    return scn, coll


def water(coll, size=400):
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, 0))
    ob = bpy.context.active_object
    for c in ob.users_collection:
        c.objects.unlink(ob)
    coll.objects.link(ob)
    m = bpy.data.materials.new("MktWater")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = srgb((15, 100, 200))
    b.inputs["Roughness"].default_value = 0.08
    nt = m.node_tree
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 6
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.25
    nt.links.new(noise.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    ob.data.materials.append(m)
    return ob


def place(coll, cid, loc, yaw_deg=0, scale=1.0, sink=0.35):
    cr = by_id[cid]
    arm, objs = build_creature(cr, coll)
    # pose at the idle's first frame
    bpy.context.scene.frame_set(1)
    arm.scale = (scale, scale, scale)
    low = min(pc["pos"][1] - pc["size"][1] / 2 for pc in cr.pieces)
    arm.location = Vector((loc[0], loc[1], -low * scale - sink * scale + loc[2]))
    # roblox faces -Z = blender +Y; yaw turns it
    arm.rotation_euler = (0, 0, math.radians(yaw_deg))
    return arm


def title(coll, text, loc, size, rot=(90, 0, 180), color=(255, 215, 50)):
    curve = bpy.data.curves.new("Title", "FONT")
    curve.body = text
    curve.font = bpy.data.fonts.load(FONT, check_existing=True)
    curve.size = size
    curve.extrude = size * 0.12
    curve.bevel_depth = size * 0.025
    curve.align_x = "CENTER"
    curve.align_y = "CENTER"
    ob = bpy.data.objects.new("Title", curve)
    coll.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = tuple(math.radians(a) for a in rot)
    m = bpy.data.materials.new("TitleMat")
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = srgb(color)
    bsdf.inputs["Emission Color"].default_value = srgb(color)
    bsdf.inputs["Emission Strength"].default_value = 0.35
    curve.materials.append(m)
    # navy outline: a fatter dark copy just behind
    back = ob.copy()
    back.data = curve.copy()
    back.data.offset = size * 0.06
    back.data.extrude = size * 0.1
    mb = bpy.data.materials.new("TitleBack")
    mb.use_nodes = True
    mb.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = srgb((16, 22, 44))
    back.data.materials.clear()
    back.data.materials.append(mb)
    coll.objects.link(back)
    back.location = Vector(loc) + Vector((0, -0.15 * size, 0))
    return ob


def camera(scn, coll, loc, target, lens=40):
    cam = bpy.data.objects.new("MktCam", bpy.data.cameras.new("MktCam"))
    cam.data.lens = lens
    coll.objects.link(cam)
    cam.location = loc
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    scn.camera = cam
    return cam


def sparkle(coll, loc, color, n=14, spread=4.0, size=0.25):
    import random
    random.seed(7)
    m = bpy.data.materials.new("Spark")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Emission Color"].default_value = srgb(color)
    b.inputs["Emission Strength"].default_value = 6
    for _ in range(n):
        bpy.ops.mesh.primitive_cube_add(size=size, location=(loc[0] + random.uniform(-spread, spread), loc[1] + random.uniform(-1, 1), loc[2] + random.uniform(0, spread)))
        ob = bpy.context.active_object
        for c in ob.users_collection:
            c.objects.unlink(ob)
        coll.objects.link(ob)
        ob.rotation_euler = (random.random() * 3, random.random() * 3, 0)
        ob.data.materials.append(m)


def render(scn, path, w, h):
    scn.render.resolution_x, scn.render.resolution_y = w, h
    scn.render.filepath = path
    bpy.ops.render.render(write_still=True)


done = []

# ---- icon -------------------------------------------------------------------
scn, coll = fresh_scene()
water(coll)
place(coll, "Tsunamaw", (0, 0, 0), yaw_deg=0, scale=1.9)
place(coll, "Splashfin", (-4.6, 2.2, 0), yaw_deg=-25, scale=1.5)
place(coll, "Zapjelly", (4.6, 2.2, 0), yaw_deg=25, scale=1.5)
title(coll, "TIDE TAMERS", (0, 3.5, 8.4), 1.55)
sparkle(coll, (0, 1, 3), (255, 240, 150))
camera(scn, coll, (0, 17, 5.5), (0, 0, 3.8), lens=38)
render(scn, os.path.join(OUT, "icon.png"), 1024, 1024)
done.append("icon")

# ---- battle thumbnail ----------------------------------------------------------
scn, coll = fresh_scene()
water(coll)
place(coll, "Tsunamaw", (7, 1, 0), yaw_deg=70, scale=1.6)
place(coll, "Thunderjaw", (9.5, -3.5, 0), yaw_deg=75, scale=1.5)
place(coll, "Coralord", (4, -4.5, 0), yaw_deg=80, scale=1.5)
place(coll, "Maw", (-8, -6, 0), yaw_deg=-90, scale=1.6, sink=0.1)
title(coll, "TIDE TAMERS", (6, 4, 11), 1.7)
sparkle(coll, (1, -1, 3), (150, 240, 255), n=20, spread=5)
camera(scn, coll, (-2, 24, 7), (0, -2, 5), lens=30)
render(scn, os.path.join(OUT, "thumb_battle.png"), 1920, 1080)
done.append("battle")

# ---- fuse thumbnail ------------------------------------------------------------
scn, coll = fresh_scene()
water(coll)
place(coll, "Kelpdrake", (-5.5, 0, 0), yaw_deg=-50, scale=1.6)
place(coll, "Voltfin", (5.5, 0, 0), yaw_deg=50, scale=1.6)
place(coll, "PearlDragon", (0, -4, 1.5), yaw_deg=0, scale=1.9)
title(coll, "FUSE!", (0, 2, 9.2), 2.0, color=(255, 120, 180))
sparkle(coll, (0, 0, 2), (255, 140, 200), n=24, spread=6, size=0.35)
camera(scn, coll, (0, 22, 6), (0, -1, 4.5), lens=32)
render(scn, os.path.join(OUT, "thumb_fuse.png"), 1920, 1080)
done.append("fuse")

result = {"rendered": done}
