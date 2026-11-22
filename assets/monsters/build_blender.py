# Builds every creature in spec.py inside Blender: bevelled voxel blocks, one armature per
# creature (one bone per moving part, rigid skinning), baked A_<Id>_Idle / _Swim / _Attack
# actions using the same formulas as shared/MonsterModels.luau, one FBX per creature in
# assets/monsters/fbx, a contact sheet (preview.png) and monsters.blend. Also rewrites
# src/shared/MonsterShapes.luau so Blender and the game never drift.
#
# Run inside Blender:
#   exec(open(r"G:\Projects\CODES\sea\assets\monsters\build_blender.py").read())
import bpy, bmesh, math, os, sys
from mathutils import Matrix, Vector

HERE = r"G:\Projects\CODES\sea\assets\monsters"
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import importlib
import spec
importlib.reload(spec)

OUT_FBX = os.path.join(HERE, "fbx")
OUT_PREVIEW = os.path.join(HERE, "preview.png")
OUT_BLEND = os.path.join(HERE, "monsters.blend")

B = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))  # roblox -> blender basis


def V(x, y, z):
    return Vector((x, -z, y))


def rot3(rdeg):
    rx, ry, rz = (math.radians(a) for a in rdeg)
    m = Matrix.Rotation(rx, 3, "X") @ Matrix.Rotation(ry, 3, "Y") @ Matrix.Rotation(rz, 3, "Z")
    return B @ m @ B.transposed()


def srgb(c):
    def g(v):
        v = v / 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return (g(c[0]), g(c[1]), g(c[2]), 1)


MATS = {}


def material(color, kind):
    key = (tuple(color), kind)
    if key in MATS:
        return MATS[key]
    m = bpy.data.materials.new("Mon_%s_%02x%02x%02x" % (kind, *color))
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = srgb(color)
    bsdf.inputs["Roughness"].default_value = 0.4
    if kind == "n":
        bsdf.inputs["Emission Color"].default_value = srgb(color)
        bsdf.inputs["Emission Strength"].default_value = 3.0
    elif kind == "g":
        bsdf.inputs["Alpha"].default_value = 0.6
        bsdf.inputs["Roughness"].default_value = 0.05
        m.surface_render_method = "BLENDED"
    elif kind == "m":
        bsdf.inputs["Metallic"].default_value = 0.9
        bsdf.inputs["Roughness"].default_value = 0.25
    m.diffuse_color = srgb(color)
    MATS[key] = m
    return m


def add_geometry(bm, kind, size, matrix):
    tmp = bmesh.new()
    if kind == "B":
        bmesh.ops.create_cube(tmp, size=1.0)
        bmesh.ops.transform(tmp, matrix=Matrix.Diagonal((size[0], size[2], size[1], 1)), verts=tmp.verts)
        bev = min(0.04, min(size) * 0.12)
        bmesh.ops.bevel(tmp, geom=list(tmp.edges), offset=bev, segments=1, affect="EDGES")
    else:
        bmesh.ops.create_uvsphere(tmp, u_segments=16, v_segments=10, radius=0.5)
        bmesh.ops.transform(tmp, matrix=Matrix.Diagonal((size[0], size[2], size[1], 1)), verts=tmp.verts)
    bmesh.ops.transform(tmp, matrix=matrix, verts=tmp.verts)
    me = bpy.data.meshes.new("tmp")
    tmp.to_mesh(me)
    tmp.free()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)


def build_creature(cr, coll):
    sub = bpy.data.collections.new(cr.id)
    coll.children.link(sub)
    arm_data = bpy.data.armatures.new(cr.id + "_Rig")
    arm = bpy.data.objects.new(cr.id + "_Rig", arm_data)
    sub.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for b in cr.bones:
        eb = arm_data.edit_bones.new(b["name"])
        eb.head = V(*b["pivot"])
        eb.tail = V(*b["pivot"]) + Vector((0, 0, 0.3))
        if b["parent"]:
            eb.parent = arm_data.edit_bones[b["parent"]]
    bpy.ops.object.mode_set(mode="OBJECT")

    groups = {}
    for pc in cr.pieces:
        groups.setdefault((pc["bone"], tuple(pc["color"]), pc["mat"]), []).append(pc)
    objs = []
    for gi, ((bone, color, mk), pcs) in enumerate(groups.items()):
        bm = bmesh.new()
        for pc in pcs:
            m = Matrix.Translation(V(*pc["pos"])) @ rot3(pc["rot"]).to_4x4()
            add_geometry(bm, pc["kind"], pc["size"], m)
        name = "%s_%s_%d" % (cr.id, bone, gi)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        for poly in me.polygons:
            poly.use_smooth = False
        me.materials.append(material(color, mk))
        ob = bpy.data.objects.new(name, me)
        sub.objects.link(ob)
        ob.parent = arm
        vg = ob.vertex_groups.new(name=bone)
        vg.add(list(range(len(me.vertices))), 1.0, "REPLACE")
        mod = ob.modifiers.new("Armature", "ARMATURE")
        mod.object = arm
        objs.append(ob)

    # Attack and Swim first, Idle last so Idle is the active action the FBX bakes
    bake_action(arm, arm_data, cr, "A_%s_Attack" % cr.id, lambda b: b["swim"], lunge=True)
    bake_action(arm, arm_data, cr, "A_%s_Swim" % cr.id, lambda b: b["swim"])
    bake_action(arm, arm_data, cr, "A_%s_Idle" % cr.id, lambda b: b)
    return arm, objs


def bake_action(arm, arm_data, cr, name, params_of, lunge=False):
    fps = bpy.context.scene.render.fps
    frames = int(spec.LOOP * fps)
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data_create()
    arm.animation_data.action = act
    ax = {"X": Vector((1, 0, 0)), "Y": Vector((0, 1, 0)), "Z": Vector((0, 0, 1))}
    for b in cr.bones:
        m = params_of(b)
        pb = arm.pose.bones[b["name"]]
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
        bone_rest = arm_data.bones[b["name"]].matrix_local.to_3x3()
        for fr in range(0, frames + 1, 2):
            t = fr / fps
            loc = Vector((0, 0, 0))
            q = Matrix.Identity(3)
            if m and m["anim"]:
                axis_b = B @ ax[m["axis"]]
                axis_local = (bone_rest.inverted() @ axis_b).normalized()
                w = math.tau * m["speed"] * t / spec.LOOP
                if m["anim"] == "rot":
                    q = Matrix.Rotation(math.radians(m["amp"]) * math.sin(w + m["phase"]), 3, axis_local)
                elif m["anim"] == "spin":
                    q = Matrix.Rotation(w, 3, axis_local)
                elif m["anim"] == "move":
                    loc = bone_rest.inverted() @ (axis_b * (m["amp"] * math.sin(w + m["phase"])))
            if lunge and b["parent"] is None:
                # the root lunges forward (roblox -Z) and back once per loop, like the game's attack
                k = max(0.0, math.sin(math.tau * t / spec.LOOP))
                loc = loc + bone_rest.inverted() @ (B @ Vector((0, 0, -1.2 * k)))
            pb.rotation_quaternion = q.to_quaternion()
            pb.keyframe_insert("rotation_quaternion", frame=fr + 1)
            pb.location = loc
            pb.keyframe_insert("location", frame=fr + 1)


def build_all():
    os.makedirs(OUT_FBX, exist_ok=True)
    scn = bpy.data.scenes.get("Monsters") or bpy.data.scenes.new("Monsters")
    bpy.context.window.scene = scn
    for ob in list(scn.collection.all_objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for c in list(scn.collection.children):
        for cc in list(c.children):
            bpy.data.collections.remove(cc)
        bpy.data.collections.remove(c)
    for a in list(bpy.data.actions):
        if a.name.startswith("A_"):
            bpy.data.actions.remove(a)
    scn.render.fps = 24
    scn.frame_start, scn.frame_end = 1, int(spec.LOOP * 24) + 1
    coll = bpy.data.collections.new("Monsters")
    scn.collection.children.link(coll)

    report = {}
    cols = 6
    for i, cr in enumerate(spec.CREATURES):
        arm, objs = build_creature(cr, coll)
        bpy.ops.object.select_all(action="DESELECT")
        arm.select_set(True)
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = arm
        bpy.ops.export_scene.fbx(filepath=os.path.join(OUT_FBX, cr.id + ".fbx"), use_selection=True,
                                 axis_forward="-Z", axis_up="Y", apply_unit_scale=True,
                                 apply_scale_options="FBX_SCALE_ALL", object_types={"ARMATURE", "MESH"},
                                 add_leaf_bones=False, bake_anim=True, bake_anim_use_all_actions=True,
                                 bake_anim_use_nla_strips=False, mesh_smooth_type="FACE")
        # lay out on a grid for the contact sheet (mirrored: the camera looks down -Y)
        arm.location = Vector(((cols - 1 - i % cols) * 5.5, 0, -(i // cols) * 5.0))
        report[cr.id] = {"bones": len(cr.bones), "pieces": len(cr.pieces),
                         "tris": sum(len(o.data.polygons) for o in objs)}
    return scn, report


def render_preview(scn):
    cam_data = bpy.data.cameras.new("MonCam")
    cam = bpy.data.objects.new("MonCam", cam_data)
    scn.collection.objects.link(cam)
    cam_data.type = "ORTHO"
    cols, rows = 6, (len(spec.CREATURES) + 5) // 6
    cam_data.ortho_scale = cols * 5.5 + 2
    target = Vector(((cols - 1) * 5.5 / 2, 0, -(rows - 1) * 5.0 / 2))
    cam.location = target + Vector((10, 40, 9))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scn.camera = cam
    sun = bpy.data.objects.new("MonSun", bpy.data.lights.new("MonSun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(-30))
    scn.collection.objects.link(sun)
    if scn.world is None:
        scn.world = bpy.data.worlds.new("MonWorld")
    scn.world.use_nodes = True
    bg = scn.world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = srgb((190, 230, 250))
    bg.inputs["Strength"].default_value = 1.0
    scn.render.engine = "BLENDER_EEVEE"
    scn.render.resolution_x, scn.render.resolution_y = 2000, int(2000 * rows * 5.0 / (cols * 5.5)) + 200
    scn.view_settings.view_transform = "Standard"
    scn.render.filepath = OUT_PREVIEW
    scn.frame_set(1)
    bpy.ops.render.render(write_still=True)


# MARKETING_IMPORT = True lets other scripts reuse the builders without a full rebuild
if not globals().get("MARKETING_IMPORT"):
    spec.write_luau()
    _scn, RESULT = build_all()
    render_preview(_scn)
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
    result = {"creatures": len(spec.CREATURES), "total_tris": sum(r["tris"] for r in RESULT.values()), "detail": RESULT}
