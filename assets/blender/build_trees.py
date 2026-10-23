"""Realistic trees: recursive branching skeleton with UV-mapped photo bark and
leaf-cluster cards (photo leaves with alpha) at the twigs.

    python3 assets/textures/source/make_leaf_atlas.py        # leaf atlases first
    Blender -b --factory-startup --python assets/blender/build_trees.py

Exports assets/models/tree_oak.glb, tree_maple.glb, tree_birch.glb.
Each has two objects: "Wood" (material Bark_Oak / Bark_Birch, UVs: u around,
v along the branch) and "Leaves" (material Leaves_Broad / Leaves_Small, 2x2
atlas cards; custom normals point out of the crown for soft volumetric
shading). Godot swaps in its own leaf shader (alpha-scissor, two-sided,
translucent, wind) by material name.
"""
import bpy
import bmesh
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bkit  # noqa: E402
from bkit import g, empty  # noqa: E402
from mathutils import Vector, Matrix  # noqa: E402

TEX = os.path.join(bkit.PROJECT, "assets/textures")
OUT = os.path.join(bkit.PROJECT, "assets/models")


def image_material(name, image_path, alpha=False):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(image_path, check_existing=True)
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.85
    if alpha:
        # "Greater Than" on alpha => glTF alphaMode MASK (alpha clip).
        gt = nt.nodes.new("ShaderNodeMath")
        gt.operation = "GREATER_THAN"
        gt.inputs[1].default_value = 0.45
        nt.links.new(tex.outputs["Alpha"], gt.inputs[0])
        nt.links.new(gt.outputs["Value"], bsdf.inputs["Alpha"])
        m.use_backface_culling = False
        if hasattr(m, "surface_render_method"):
            m.surface_render_method = "DITHERED"
    return m


MATS = {
    "bark_oak": image_material("Bark_Oak", os.path.join(TEX, "pixabay/bark_oak_albedo.jpg")),
    "bark_birch": image_material("Bark_Birch", os.path.join(TEX, "pixabay/bark_birch_albedo.jpg")),
    "leaves_broad": image_material("Leaves_Broad", os.path.join(TEX, "trees/leaves_broad.png"), alpha=True),
    "leaves_small": image_material("Leaves_Small", os.path.join(TEX, "trees/leaves_small.png"), alpha=True),
}

SPECIES = {
    # trunk_h: trunk length; spread: limb angle from vertical (deg); levels of branching;
    # limbs/children per level; card: leaf card size (m); per_tip: cards per twig tip
    "oak": dict(trunk_h=5.6, trunk_r=0.30, spread=(40, 62), limbs=7, children=(4, 3), ratio=(0.72, 0.55, 0.5),
                droop=0.04, levels=3, card=1.2, per_tip=1, bark="bark_oak", leaves="leaves_broad", crown_h=0.85, seed=4),
    "maple": dict(trunk_h=6.5, trunk_r=0.24, spread=(30, 48), limbs=7, children=(4, 3), ratio=(0.55, 0.52, 0.5),
                  droop=0.02, levels=3, card=1.15, per_tip=1, bark="bark_oak", leaves="leaves_broad", crown_h=0.68, seed=9),
    "birch": dict(trunk_h=8.5, trunk_r=0.15, spread=(25, 40), limbs=11, children=(3, 3), ratio=(0.40, 0.55, 0.5),
                  droop=0.08, levels=3, card=0.9, per_tip=1, bark="bark_birch", leaves="leaves_small", crown_h=0.72, seed=21),
}


class TreeMesh:
    def __init__(self):
        self.wood = bmesh.new()
        self.wood_uv = self.wood.loops.layers.uv.new("UVMap")
        self.leaves = bmesh.new()
        self.leaves_uv = self.leaves.loops.layers.uv.new("UVMap")
        self.leaf_normals = []          # per created leaf vertex, in order

    def branch(self, pts, radii, sides):
        """Tube through points (Blender space) with bark UVs."""
        rings = []
        tangent_prev = None
        normal = None
        length_acc = 0.0
        for i, p in enumerate(pts):
            t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
            if normal is None:
                normal = t.orthogonal().normalized()
            else:
                # Parallel transport keeps the ring orientation from twisting.
                normal = (normal - t * normal.dot(t)).normalized()
            binormal = t.cross(normal)
            if i > 0:
                length_acc += (p - pts[i - 1]).length
            ring = []
            for k in range(sides + 1):
                a = 2 * math.pi * k / sides
                v = self.wood.verts.new(p + (normal * math.cos(a) + binormal * math.sin(a)) * radii[i])
                ring.append((v, k / sides, length_acc))
            rings.append(ring)
        u_repeat = max(1, round(2 * math.pi * radii[0] / 0.45))
        for i in range(len(rings) - 1):
            for k in range(sides):
                a, b = rings[i][k], rings[i][k + 1]
                c, d = rings[i + 1][k + 1], rings[i + 1][k]
                f = self.wood.faces.new((a[0], b[0], c[0], d[0]))
                f.smooth = True
                for loop, src in zip(f.loops, (a, b, c, d)):
                    loop[self.wood_uv].uv = (src[1] * u_repeat, src[2] / 0.9)

    def card(self, base, up, normal, size, cell, out_dir):
        """Leaf-cluster quad: bottom edge centre at `base`, growing along `up`."""
        up = (up - normal * up.dot(normal)).normalized()
        side = normal.cross(up).normalized()
        w = side * size * 0.5
        h = up * size
        corners = [base - w, base + w, base + w + h, base - w + h]
        cx, cy = cell % 2, cell // 2
        u0, v0 = cx * 0.5, 1.0 - (cy + 1) * 0.5
        uvs = [(u0, v0), (u0 + 0.5, v0), (u0 + 0.5, v0 + 0.5), (u0, v0 + 0.5)]
        verts = [self.leaves.verts.new(c) for c in corners]
        f = self.leaves.faces.new(verts)
        for loop, uv in zip(f.loops, uvs):
            loop[self.leaves_uv].uv = uv
        n = (out_dir * 0.65 + normal * 0.35).normalized()
        self.leaf_normals.extend([n] * 4)


def grow(tm, rng, sp, start, direction, length, radius, level, tips, crown_c):
    segs = max(3, int(length / 0.45))
    pts = [start]
    d = direction.normalized()
    for i in range(segs):
        jitter = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * (0.10 + 0.05 * level)
        d = (d + jitter + Vector((0, 0, -sp["droop"] * level))).normalized()
        if level == 0:
            d = (d * 0.6 + Vector((0, 0, 1)) * 0.4).normalized()
        pts.append(pts[-1] + d * length / segs)
    radii = [radius * (1.0 - 0.65 * i / segs) for i in range(segs + 1)]
    sides = [12, 8, 6, 4][min(level, 3)]
    tm.branch(pts, radii, sides)
    if level >= sp["levels"]:
        # Leaf anchors all along the outer part of each twig, so no bare twigs.
        for i in range(max(1, segs // 3), segs + 1):
            j = min(i, segs - 1)
            tips.append((pts[i], (pts[j + 1] - pts[j]).normalized() if j + 1 <= segs else d))
        return
    if level == sp["levels"] - 1:
        tips.append((pts[-1], (pts[-1] - pts[-2]).normalized()))
    count = sp["limbs"] if level == 0 else sp["children"][min(level - 1, 1)]
    t_lo = sp["crown_h"] * 0.55 if level == 0 else 0.25
    for c in range(count):
        t = t_lo + (0.98 - t_lo) * (c + rng.uniform(0.0, 0.8)) / count
        idx = min(int(t * segs), segs - 1)
        p = pts[idx].lerp(pts[idx + 1], t * segs - idx)
        parent_d = (pts[idx + 1] - pts[idx]).normalized()
        az = 2.39996 * (c + 1) + rng.uniform(-0.3, 0.3) + level * 1.3       # golden angle
        tilt = math.radians(rng.uniform(*sp["spread"]))
        perp = parent_d.orthogonal().normalized()
        perp.rotate(Matrix.Rotation(az, 3, parent_d))
        child_d = (parent_d * math.cos(tilt) + perp * math.sin(tilt)).normalized()
        child_len = length * sp["ratio"][min(level, 2)] * rng.uniform(0.85, 1.15) * (1.15 - 0.4 * (t - t_lo))
        grow(tm, rng, sp, p, child_d, child_len, max(radius * (1.0 - 0.65 * t) * 0.62, 0.012), level + 1, tips, crown_c)


def build_species(name, coll):
    sp = SPECIES[name]
    rng = random.Random(sp["seed"])
    root = empty("Tree_" + name.capitalize(), coll)
    tm = TreeMesh()
    tips = []
    crown_c = g(0, sp["trunk_h"] * 0.95, 0)
    grow(tm, rng, sp, g(0, 0, 0), Vector((0, 0, 1)), sp["trunk_h"], sp["trunk_r"], 0, tips, crown_c)
    # Root flare: a short wider ring at the base.
    tm.branch([g(0, -0.05, 0), g(0, 0.35, 0)], [sp["trunk_r"] * 1.45, sp["trunk_r"] * 1.05], 12)
    # Crown centre from the tips themselves.
    cc = sum((p for p, _ in tips), Vector()) / len(tips)
    for p, d in tips:
        for k in range(sp["per_tip"]):
            out = (p - cc)
            out = out.normalized() if out.length > 1e-3 else Vector((0, 0, 1))
            n = (out + Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.4, 1))) * 0.8).normalized()
            up = (d * 0.6 + Vector((0, 0, 0.6)) + Vector((rng.uniform(-0.4, 0.4), rng.uniform(-0.4, 0.4), 0))).normalized()
            size = sp["card"] * rng.uniform(0.8, 1.2)
            base = p - up * size * 0.25 + Vector((rng.uniform(-0.15, 0.15), rng.uniform(-0.15, 0.15), rng.uniform(-0.1, 0.1)))
            tm.card(base, up, n, size, rng.randrange(4), out)
    # Wood object.
    me = bpy.data.meshes.new(name + "_wood")
    tm.wood.to_mesh(me)
    tm.wood.free()
    me.materials.append(MATS[sp["bark"]])
    wood = bpy.data.objects.new("Wood", me)
    coll.objects.link(wood)
    wood.parent = root
    # Leaves object with custom (crown-outward) normals.
    lm = bpy.data.meshes.new(name + "_leaves")
    tm.leaves.to_mesh(lm)
    tm.leaves.free()
    lm.materials.append(MATS[sp["leaves"]])
    lm.normals_split_custom_set_from_vertices(tm.leaf_normals)
    leaves = bpy.data.objects.new("Leaves", lm)
    coll.objects.link(leaves)
    leaves.parent = root
    return root, len(tips)


scene = bkit.fresh_scene("Trees")
roots = []
for name in ("oak", "maple", "birch"):
    coll = bpy.data.collections.new("tree_" + name)
    scene.collection.children.link(coll)
    root, ntips = build_species(name, coll)
    bpy.context.view_layer.update()
    path = os.path.join(OUT, "tree_%s.glb" % name)
    bkit.export_glb(scene, root, path, images=False)
    print("tree_%s: tips=%d tris=%d bytes=%d" % (name, ntips, bkit.tri_count(root), os.path.getsize(path)))
    for ob in bkit.descendants(root):
        ob.name = name + "__" + ob.name
    roots.append(root)
for i, r in enumerate(roots):
    r.location = Vector((i * 11.0, 0, 0))
bpy.context.view_layer.update()
bpy.data.libraries.write(os.path.join(bkit.PROJECT, "assets/blender/trees.blend"), {scene}, fake_user=True, compress=True)
bkit.preview_render(scene, os.path.join(bkit.PROJECT, "assets/reference/trees_preview.png"), (11.0, -30.0, 6.0), (11.0, 0, 5.0), 35, (1600, 800))
print("TREES_BUILD_OK")
