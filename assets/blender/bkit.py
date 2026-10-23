"""Shared Blender helpers for Paper Boy asset scripts.

Geometry is authored in *Godot space* (Y up, forward -Z) through g(); the glTF
exporter's +Y-up conversion maps it back, so what you write here is what
Godot sees.
"""
import bpy
import bmesh
import math
import os
import random
from mathutils import Vector, Matrix

PROJECT = os.environ.get("PAPERBOY_ROOT", os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")))


def g(x, y=None, z=None):
    """Godot-space point -> Blender vector."""
    if y is None:
        x, y, z = x
    return Vector((x, -z, y))


def gs(w, h, d):
    """Godot-order size (width, height, depth) -> Builder.box size (Blender X, Y, Z)."""
    return (w, d, h)


def material(name, color, rough, metal=0.0, emission=None):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 1.0
    m.diffuse_color = (*color, 1.0)
    return m


class Builder:
    """Accumulates geometry for one object; each part gets a material slot."""

    def __init__(self, mats):
        self.bm = bmesh.new()
        self.mats = mats
        self.slots = []

    def slot(self, key):
        if key not in self.slots:
            self.slots.append(key)
        return self.slots.index(key)

    def _tag(self, verts, key, smooth=None):
        idx = self.slot(key)
        for v in verts:
            for f in v.link_faces:
                f.material_index = idx
                if smooth is not None:
                    f.smooth = smooth(f)

    # All positions below are Blender-space Vectors (use g() to convert).
    def tube(self, a, b, r, key, seg=10, r2=None):
        a, b = Vector(a), Vector(b)
        d = b - a
        if d.length < 1e-5:
            return
        rot = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        mat = Matrix.Translation((a + b) / 2) @ rot
        res = bmesh.ops.create_cone(self.bm, cap_ends=True, segments=seg, radius1=r, radius2=r if r2 is None else r2, depth=d.length, matrix=mat)
        self._tag(res["verts"], key, lambda f: len(f.verts) == 4)

    def box(self, center, size, key, bevel=0.0):
        """`size` is in Blender axes (X, Y=depth, Z=height); use gs() for Godot order."""
        mat = Matrix.Translation(Vector(center)) @ Matrix.Diagonal((*size, 1.0))
        res = bmesh.ops.create_cube(self.bm, size=1.0, matrix=mat)
        verts = res["verts"]
        self._tag(verts, key)
        if bevel > 0.0:
            edges = list({e for v in verts for e in v.link_edges})
            bmesh.ops.bevel(self.bm, geom=edges, offset=bevel, segments=2, affect="EDGES", profile=0.5)
        return verts

    def disc_x(self, center, r, depth, key, seg=24):
        """Cylinder with its axis along Blender X (wheels)."""
        mat = Matrix.Translation(Vector(center)) @ Matrix.Rotation(math.radians(90), 4, "Y")
        res = bmesh.ops.create_cone(self.bm, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=depth, matrix=mat)
        self._tag(res["verts"], key, lambda f: len(f.verts) == 4)

    def ellipsoid(self, center, size, key, seg=16, rings=10, jitter=0.0, rng=None):
        mat = Matrix.Translation(Vector(center)) @ Matrix.Diagonal((size[0] / 2, size[1] / 2, size[2] / 2, 1.0))
        res = bmesh.ops.create_uvsphere(self.bm, u_segments=seg, v_segments=rings, radius=1.0, matrix=mat)
        if jitter > 0.0:
            rng = rng or random.Random(1)
            c = Vector(center)
            for v in res["verts"]:
                n = (v.co - c).normalized()
                v.co += n * rng.uniform(-jitter, jitter)
        self._tag(res["verts"], key, lambda f: True)

    def blob(self, center, radius, key, subdiv=2, jitter=0.15, squash=1.0, rng=None):
        """Lumpy icosphere for foliage clusters."""
        rng = rng or random.Random(1)
        mat = Matrix.Translation(Vector(center)) @ Matrix.Diagonal((1.0, 1.0, squash, 1.0))
        res = bmesh.ops.create_icosphere(self.bm, subdivisions=subdiv, radius=radius, matrix=mat)
        c = Vector(center)
        for v in res["verts"]:
            n = (v.co - c).normalized()
            v.co += n * radius * rng.uniform(-jitter, jitter)
        self._tag(res["verts"], key, lambda f: True)

    def to_object(self, name, coll, parent=None, location=Vector()):
        """Geometry is in the object's local space; `location` is relative to parent."""
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        for key in self.slots:
            me.materials.append(self.mats[key])
        ob = bpy.data.objects.new(name, me)
        coll.objects.link(ob)
        ob.parent = parent
        ob.location = Vector(location)
        return ob


def empty(name, coll, parent=None, location=Vector()):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = 0.1
    coll.objects.link(e)
    e.parent = parent
    e.location = Vector(location)
    return e


def fresh_scene(name):
    if bpy.app.background:
        scene = bpy.context.scene
        scene.name = name
    else:
        scene = bpy.data.scenes.get(name) or bpy.data.scenes.new(name)
        bpy.context.window.scene = scene
    for ob in list(scene.collection.all_objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for c in list(scene.collection.children):
        bpy.data.collections.remove(c)
    scene.unit_settings.system = "METRIC"
    return scene


def descendants(ob):
    out = [ob]
    for c in ob.children:
        out.extend(descendants(c))
    return out


def export_glb(scene, root, path, images=True):
    """images=False leaves textures out of the GLB (Godot applies its own materials)."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    keep = set(descendants(root))
    for ob in scene.objects:
        ob.select_set(ob in keep)
    extra = {} if images else {"export_image_format": "NONE"}
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=True, **extra)


def tri_count(root):
    n = 0
    for ob in descendants(root):
        if ob.type == "MESH":
            ob.data.calc_loop_triangles()
            n += len(ob.data.loop_triangles)
    return n


def preview_render(scene, path, cam_loc, target, lens=35, res=(1280, 720)):
    coll = bpy.data.collections.new("PreviewRig")
    scene.collection.children.link(coll)
    cam = bpy.data.objects.new("PreviewCam", bpy.data.cameras.new("PreviewCam"))
    coll.objects.link(cam)
    cam.location = Vector(cam_loc)
    cam.rotation_euler = (Vector(target) - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = lens
    cam.data.clip_end = 500
    scene.camera = cam
    sun = bpy.data.objects.new("PreviewSun", bpy.data.lights.new("PreviewSun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(55), math.radians(10), math.radians(35))
    coll.objects.link(sun)
    gm = bpy.data.meshes.new("PreviewGround")
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=60)
    bm.to_mesh(gm)
    bm.free()
    gm.materials.append(material("Preview_Ground", (0.45, 0.45, 0.43), 0.9))
    coll.objects.link(bpy.data.objects.new("PreviewGround", gm))
    world = bpy.data.worlds.get("PreviewWorld") or bpy.data.worlds.new("PreviewWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.65, 0.8, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    scene.world = world
    scene.render.resolution_x, scene.render.resolution_y = res
    engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    scene.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in engines else "BLENDER_EEVEE_NEXT"
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return coll
