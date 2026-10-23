"""Builds the delivery bicycle in Blender and exports it for Godot.

Run inside Blender (e.g. via Blender MCP):
    exec(open("<project>/assets/blender/build_bicycle.py").read())

Works in its own scene ("Bicycle") so the user's open file is untouched.
Coordinates are authored in *Godot space* (Y up, forward -Z) through g(), which
maps to Blender (Z up, forward +Y); the glTF exporter's +Y-up conversion maps
them back, so node origins land exactly where scripts/player/bike_visual.gd expects:

    Bike (root)
      Frame            mesh, origin at ground
      RearWheel        mesh, origin at rear axle   (spins about local X)
      Crank            mesh, origin at bottom bracket (spins about X)
        PedalL/PedalR  meshes at the crank ends
      SteerPivot       empty at the steering axis   (yaws about Y)
        Fork           mesh (fork, stem, bars, basket)
        FrontWheel     mesh, origin at front axle
        GripL/GripR    empties where the rider's hands go
"""
import bpy
import bmesh
import math
import os
from mathutils import Vector, Matrix

PROJECT = os.environ.get("PAPERBOY_ROOT", "/Users/shreeram/Desktop/paperboy 3d")
OUT_BLEND = os.path.join(PROJECT, "assets/blender/bicycle.blend")
OUT_GLB = os.path.join(PROJECT, "assets/models/bicycle.glb")
PREVIEW = os.path.join(PROJECT, "assets/reference/bicycle_preview.png")

WHEEL_R = 0.34
REAR_AXLE = (0, WHEEL_R, 0.525)
FRONT_AXLE = (0, WHEEL_R, -0.525)
BB = (0, 0.30, 0.05)
SEAT = (0, 0.86, 0.16)
HEAD_TOP = (0, 0.92, -0.40)
HEAD_BOT = (0, 0.74, -0.44)
STEER = (0, 0.0, -0.42)
CRANK_LEN = 0.17


def g(x, y=None, z=None):
    """Godot-space point -> Blender vector."""
    if y is None:
        x, y, z = x
    return Vector((x, -z, y))


def gadd(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


# ---------------------------------------------------------------- materials
def material(name, color, rough, metal=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    m.diffuse_color = (*color, 1.0)
    return m


MATS = {
    "paint": material("Bike_Paint", (0.45, 0.03, 0.03), 0.3, 0.4),
    "chrome": material("Bike_Chrome", (0.80, 0.80, 0.82), 0.18, 1.0),
    "rubber": material("Bike_Rubber", (0.025, 0.025, 0.025), 0.85),
    "dark": material("Bike_DarkMetal", (0.06, 0.06, 0.065), 0.45, 0.8),
    "leather": material("Bike_Leather", (0.18, 0.10, 0.06), 0.6),
    "wicker": material("Bike_Wicker", (0.42, 0.28, 0.13), 0.8),
    "paper": material("Bike_Newsprint", (0.80, 0.78, 0.72), 0.95),
}


# ---------------------------------------------------------------- geometry
class Builder:
    """Accumulates geometry for one object, tracking a material slot per face."""

    def __init__(self):
        self.bm = bmesh.new()
        self.slots = []

    def slot(self, key):
        if key not in self.slots:
            self.slots.append(key)
        return self.slots.index(key)

    def _tag(self, verts, key):
        idx = self.slot(key)
        for v in verts:
            for f in v.link_faces:
                f.material_index = idx

    def tube(self, a, b, r, key, seg=10):
        a, b = Vector(a), Vector(b)
        d = b - a
        length = d.length
        if length < 1e-5:
            return
        rot = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        mat = Matrix.Translation((a + b) / 2) @ rot
        res = bmesh.ops.create_cone(self.bm, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=length, matrix=mat)
        self._tag(res["verts"], key)
        for v in res["verts"]:
            for f in v.link_faces:
                f.smooth = len(f.verts) == 4

    def arc(self, center_g, radius, a0, a1, steps, r, key, sign=1.0):
        """Tube bent along a circle in the wheel plane (mudguards). Angles in degrees from +Y (up)."""
        prev = None
        for i in range(steps + 1):
            a = math.radians(a0 + (a1 - a0) * i / steps)
            p = g(0, center_g[1] + math.cos(a) * radius, center_g[2] + sign * math.sin(a) * radius)
            if prev is not None:
                self.tube(prev, p, r, key, 8)
            prev = p

    def box(self, center, size, key):
        mat = Matrix.Translation(Vector(center)) @ Matrix.Diagonal((*size, 1.0))
        res = bmesh.ops.create_cube(self.bm, size=1.0, matrix=mat)
        self._tag(res["verts"], key)

    def disc(self, center, r, depth, key, seg=24):
        """Cylinder whose axis is Blender X (the wheel/crank axis)."""
        mat = Matrix.Translation(Vector(center)) @ Matrix.Rotation(math.radians(90), 4, "Y")
        res = bmesh.ops.create_cone(self.bm, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=depth, matrix=mat)
        self._tag(res["verts"], key)

    def torus_x(self, center, major, minor, key, seg_u=48, seg_v=10):
        """Torus lying in the Blender YZ plane (axis = X)."""
        c = Vector(center)
        verts = []
        for i in range(seg_u):
            u = 2 * math.pi * i / seg_u
            ring = []
            for j in range(seg_v):
                v = 2 * math.pi * j / seg_v
                rr = major + minor * math.cos(v)
                ring.append(self.bm.verts.new(c + Vector((minor * math.sin(v), rr * math.cos(u), rr * math.sin(u)))))
            verts.append(ring)
        idx = self.slot(key)
        for i in range(seg_u):
            for j in range(seg_v):
                f = self.bm.faces.new((verts[i][j], verts[(i + 1) % seg_u][j], verts[(i + 1) % seg_u][(j + 1) % seg_v], verts[i][(j + 1) % seg_v]))
                f.material_index = idx
                f.smooth = True

    def to_object(self, name, coll, origin=Vector(), parent=None):
        """Geometry is authored in the object's local space; `origin` is its world position."""
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        for key in self.slots:
            me.materials.append(MATS[key])
        ob = bpy.data.objects.new(name, me)
        if coll is not None:
            coll.objects.link(ob)
        set_parent(ob, parent, origin)
        return ob


def set_parent(ob, parent, world_origin):
    ob.parent = parent
    if parent is not None:
        ob.location = Vector(world_origin) - parent.matrix_world.translation
    else:
        ob.location = Vector(world_origin)


def empty(name, coll, world_pos, parent=None):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = 0.05
    coll.objects.link(e)
    set_parent(e, parent, world_pos)
    bpy.context.view_layer.update()
    return e


# ---------------------------------------------------------------- build
def build():
    if bpy.app.background:
        # Headless run (blender -b --factory-startup): the context scene is a
        # throwaway factory scene, so build straight into it.
        scene = bpy.context.scene
        scene.name = "Bicycle"
    else:
        scene = bpy.data.scenes.get("Bicycle") or bpy.data.scenes.new("Bicycle")
        bpy.context.window.scene = scene
    for ob in list(scene.collection.all_objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for c in list(scene.collection.children):
        bpy.data.collections.remove(c)
    scene.unit_settings.system = "METRIC"
    bike_coll = bpy.data.collections.new("BikeExport")
    scene.collection.children.link(bike_coll)

    root = empty("Bike", bike_coll, Vector())

    # Frame -----------------------------------------------------------
    b = Builder()
    b.tube(g(BB), g(SEAT), 0.019, "paint")
    b.tube(g(gadd(SEAT, (0, -0.05, -0.02))), g(HEAD_TOP), 0.017, "paint")
    b.tube(g(BB), g(HEAD_BOT), 0.022, "paint")
    b.tube(g(HEAD_BOT), g(HEAD_TOP), 0.024, "paint")
    for s in (-0.055, 0.055):
        b.tube(g(gadd(REAR_AXLE, (s, 0, 0))), g(gadd(BB, (s * 0.4, 0, 0))), 0.010, "paint")
        b.tube(g(gadd(REAR_AXLE, (s, 0, 0))), g(gadd(SEAT, (s * 0.3, -0.07, 0))), 0.009, "paint")
    b.disc(g(BB), 0.03, 0.08, "dark", 16)
    # Seat post + sprung saddle.
    b.tube(g(SEAT), g(gadd(SEAT, (0, 0.07, 0.01))), 0.012, "chrome")
    b.box(g(gadd(SEAT, (0, 0.095, 0.03))), (0.15, 0.24, 0.045), "leather")
    b.box(g(gadd(SEAT, (0, 0.095, -0.09))), (0.06, 0.12, 0.035), "leather")
    for s in (-0.04, 0.04):
        b.tube(g(gadd(SEAT, (s, 0.07, 0.10))), g(gadd(SEAT, (s, 0.06, 0.05))), 0.006, "chrome")
    # Rear carrier with paper bundle and strap.
    rack_y = 0.66
    for s in (-0.07, 0.07):
        b.tube(g(s, rack_y, 0.30), g(s, rack_y, 0.70), 0.007, "chrome")
        b.tube(g(s, rack_y, 0.68), g(gadd(REAR_AXLE, (s, 0, 0))), 0.007, "chrome")
        b.tube(g(s, rack_y, 0.32), g(gadd(SEAT, (s * 0.4, -0.12, 0.02))), 0.006, "chrome")
    for z in (0.36, 0.50, 0.64):
        b.tube(g(-0.07, rack_y, z), g(0.07, rack_y, z), 0.006, "chrome")
    b.box(g(0, rack_y + 0.075, 0.50), (0.22, 0.30, 0.13), "paper")
    b.box(g(0, rack_y + 0.075, 0.50), (0.24, 0.03, 0.135), "dark")
    # Rear mudguard following the tyre from above the axle round to the back.
    b.arc(REAR_AXLE, 0.375, -25, 95, 12, 0.022, "paint", 1.0)
    # Chain: upper/lower runs plus rear cog.
    b.tube(g(0.06, BB[1] + 0.10, BB[2]), g(0.06, REAR_AXLE[1] + 0.04, REAR_AXLE[2]), 0.005, "dark")
    b.tube(g(0.06, BB[1] - 0.10, BB[2]), g(0.06, REAR_AXLE[1] - 0.04, REAR_AXLE[2]), 0.005, "dark")
    # Kickstand (folded).
    b.tube(g(0.05, BB[1] - 0.02, BB[2] + 0.08), g(0.07, 0.10, 0.40), 0.007, "dark")
    b.to_object("Frame", bike_coll, Vector(), root)

    # Wheels (front shares mesh data with rear) ------------------------
    w = Builder()
    w.torus_x(Vector(), WHEEL_R - 0.022, 0.022, "rubber", 48, 10)
    w.torus_x(Vector(), WHEEL_R - 0.050, 0.010, "chrome", 48, 6)
    w.disc(Vector(), 0.025, 0.10, "chrome", 12)
    for i in range(28):
        a = 2 * math.pi * i / 28
        side = 0.035 if i % 2 == 0 else -0.035
        hub = Vector((side, 0, 0))
        rim = Vector((0, math.cos(a + 0.1) * (WHEEL_R - 0.055), math.sin(a + 0.1) * (WHEEL_R - 0.055)))
        w.tube(hub, rim, 0.0018, "chrome", 4)
    rear = w.to_object("RearWheel", bike_coll, g(REAR_AXLE), root)
    rear.location = g(REAR_AXLE)  # mesh was authored at the origin
    cog = Builder()
    cog.disc(Vector((0.055, 0, 0)), 0.04, 0.006, "dark", 16)
    cog_ob = cog.to_object("RearCog", bike_coll, Vector(), rear)
    cog_ob.location = Vector()

    # Crank + pedals --------------------------------------------------
    c = Builder()
    c.disc(Vector((0.065, 0, 0)), 0.10, 0.006, "chrome", 32)
    c.disc(Vector((0.065, 0, 0)), 0.07, 0.008, "dark", 5)
    c.tube(Vector((0.08, 0, 0)), Vector((0.08, 0, -CRANK_LEN)), 0.011, "chrome")
    c.tube(Vector((-0.08, 0, 0)), Vector((-0.08, 0, CRANK_LEN)), 0.011, "chrome")
    c.tube(Vector((-0.09, 0, 0)), Vector((0.09, 0, 0)), 0.008, "chrome")
    crank = c.to_object("Crank", bike_coll, g(BB), root)
    for name, x, zz in (("PedalR", 0.13, -CRANK_LEN), ("PedalL", -0.13, CRANK_LEN)):
        pb = Builder()
        pb.box(Vector(), (0.09, 0.06, 0.02), "dark")
        pb.tube(Vector((-0.045, 0, 0)), Vector((0.045, 0, 0)), 0.006, "chrome", 6)
        ped = pb.to_object(name, bike_coll, Vector(), crank)
        ped.location = Vector((x, 0, zz))

    # Steering assembly ------------------------------------------------
    pivot = empty("SteerPivot", bike_coll, g(STEER), root)
    f = Builder()
    rel = lambda p: g(p) - g(STEER)
    fwd_axle = FRONT_AXLE
    for s in (-0.05, 0.05):
        f.tube(rel((s * 0.5, HEAD_BOT[1] - 0.02, HEAD_BOT[2])), rel(gadd(fwd_axle, (s, 0.0, 0.0))), 0.011, "chrome")
    f.box(rel((0, HEAD_BOT[1] - 0.02, HEAD_BOT[2])), (0.12, 0.04, 0.03), "chrome")
    stem_top = (0, 1.0, STEER[2] + 0.03)
    f.tube(rel(HEAD_TOP), rel(stem_top), 0.014, "chrome")
    # Swept-back handlebar.
    bar_pts = [(-0.29, 1.01, STEER[2] + 0.10), (-0.18, 1.0, STEER[2] + 0.04), (0.0, 1.0, STEER[2] + 0.03), (0.18, 1.0, STEER[2] + 0.04), (0.29, 1.01, STEER[2] + 0.10)]
    for p0, p1 in zip(bar_pts, bar_pts[1:]):
        f.tube(rel(p0), rel(p1), 0.011, "chrome", 8)
    grips = {}
    for side, p0, p1 in (("GripL", bar_pts[0], bar_pts[1]), ("GripR", bar_pts[4], bar_pts[3])):
        a, bpt = Vector(p0), Vector(p1)
        gp = a.lerp(bpt, 0.35)
        f.tube(rel(tuple(a)), rel(tuple(a.lerp(bpt, 0.75))), 0.016, "rubber", 10)
        grips[side] = tuple(gp)
        # Brake lever reaching forward under the bar.
        f.tube(rel(tuple(a.lerp(bpt, 0.85))), rel((gp[0] * 0.95, gp[1] - 0.03, gp[2] - 0.10)), 0.005, "chrome", 6)
    # Bell on the right of the stem.
    f.disc(rel((0.07, 1.025, STEER[2] + 0.04)), 0.025, 0.02, "chrome", 16)
    # Front basket (open top) with papers.
    bc = (0, 0.80, STEER[2] - 0.20)
    bw, bh, bd = 0.32, 0.18, 0.24
    f.box(rel(gadd(bc, (0, -bh / 2, 0))), (bw, bd, 0.01), "wicker")
    for sx in (-1, 1):
        f.box(rel(gadd(bc, (sx * bw / 2, 0, 0))), (0.01, bd, bh), "wicker")
    for sz in (-1, 1):
        f.box(rel(gadd(bc, (0, 0, sz * bd / 2))), (bw, 0.01, bh), "wicker")
    f.box(rel(gadd(bc, (0, -0.02, 0))), (0.26, 0.20, 0.10), "paper")
    f.tube(rel(gadd(bc, (0, 0.0, bd / 2))), rel((0, 0.95, STEER[2] + 0.0)), 0.006, "chrome")
    # Front mudguard (authored in world space, shifted into pivot space).
    fg = Builder()
    fg.arc(fwd_axle, 0.375, -40, 100, 12, 0.022, "paint", -1.0)
    bmesh.ops.translate(fg.bm, verts=fg.bm.verts, vec=-g(STEER))
    fg_ob = fg.to_object("FrontMudguard", None, Vector(), None)
    fork = f.to_object("Fork", bike_coll, Vector(), pivot)
    fork.location = Vector()
    bike_coll.objects.link(fg_ob)
    fg_ob.parent = pivot
    fg_ob.location = Vector()

    front = bpy.data.objects.new("FrontWheel", rear.data)
    bike_coll.objects.link(front)
    front.parent = pivot
    front.location = g(FRONT_AXLE) - g(STEER)
    for side, gp in grips.items():
        e = empty(side, bike_coll, Vector(), pivot)
        e.location = g(gp) - g(STEER)

    bpy.context.view_layer.update()
    return scene, bike_coll


def add_preview_rig(scene):
    prev = bpy.data.collections.new("PreviewRig")
    scene.collection.children.link(prev)
    cam_data = bpy.data.cameras.new("PreviewCam")
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    prev.objects.link(cam)
    cam.location = (2.1, -1.3, 1.1)
    target = Vector((0, 0, 0.5))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam_data.lens = 45
    scene.camera = cam
    sun_data = bpy.data.lights.new("PreviewSun", "SUN")
    sun_data.energy = 3.5
    sun = bpy.data.objects.new("PreviewSun", sun_data)
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(40))
    prev.objects.link(sun)
    ground = bpy.data.meshes.new("PreviewGround")
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=4)
    bm.to_mesh(ground)
    bm.free()
    ground.materials.append(material("Preview_Ground", (0.5, 0.5, 0.5), 0.9))
    gob = bpy.data.objects.new("PreviewGround", ground)
    prev.objects.link(gob)
    world = bpy.data.worlds.get("PreviewWorld") or bpy.data.worlds.new("PreviewWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.65, 0.8, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    scene.world = world
    scene.render.resolution_x = 960
    scene.render.resolution_y = 640
    scene.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE_NEXT"
    return prev


def export(scene, bike_coll):
    os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)
    for ob in scene.objects:
        ob.select_set(ob.name in bike_coll.objects)
    bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=True, export_yup=True, export_apply=True)
    # Save just this scene's datablocks so the user's own file isn't touched.
    bpy.data.libraries.write(OUT_BLEND, {scene}, fake_user=True, compress=True)


scene, bike_coll = build()
prev_rig = add_preview_rig(scene)
export(scene, bike_coll)
scene.render.filepath = PREVIEW
bpy.ops.render.render(write_still=True)

if bpy.app.background:
    print("BIKE_BUILD_OK")
result = {
    "objects": sorted(o.name for o in bike_coll.objects),
    "tris": sum(len(o.data.loop_triangles) if (o.type == "MESH" and (o.data.calc_loop_triangles() or True)) else 0 for o in bike_coll.objects),
    "glb": OUT_GLB,
    "glb_bytes": os.path.getsize(OUT_GLB),
    "blend": OUT_BLEND,
    "preview": PREVIEW,
}
print(result)
