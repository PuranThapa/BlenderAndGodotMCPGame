"""Builds street props, vegetation, a car and animals; exports one GLB each.

Run headless:
    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python assets/blender/build_props.py

Each asset has a root empty at the ground origin, faces Godot -Z (Blender +Y),
and uses real-world metres. Animated parts are separate child objects whose
origins sit at their pivots:
    car:  WheelFL/WheelFR/WheelRL/WheelRR (spin about X); paint material "Car_Paint"
    dog/cat: Head, LegFL/LegFR/LegRL/LegRR (pivot at hip), Tail (pivot at base)
"""
import bpy
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bkit  # noqa: E402
from bkit import g, gs, Builder, material, empty  # noqa: E402
from mathutils import Vector  # noqa: E402

OUT_DIR = os.path.join(bkit.PROJECT, "assets/models")
PREVIEW = os.path.join(bkit.PROJECT, "assets/reference/props_preview.png")

M = {
    "bark": material("Bark", (0.22, 0.16, 0.11), 0.95),
    "bark_birch": material("Bark_Birch", (0.78, 0.76, 0.70), 0.9),
    "leaf_a": material("Leaves_A", (0.13, 0.29, 0.08), 0.9),
    "leaf_b": material("Leaves_B", (0.20, 0.36, 0.10), 0.9),
    "leaf_c": material("Leaves_C", (0.27, 0.40, 0.12), 0.9),
    "iron": material("Iron_Dark", (0.08, 0.09, 0.09), 0.5, 0.7),
    "lamp_glass": material("Lamp_Glass", (0.85, 0.82, 0.70), 0.2),
    "wood": material("Wood_Weathered", (0.40, 0.27, 0.16), 0.85),
    "wood_post": material("Wood_Post", (0.30, 0.22, 0.15), 0.9),
    "mailbox": material("Mailbox_Metal", (0.10, 0.14, 0.22), 0.45, 0.6),
    "flag": material("Mailbox_Flag", (0.75, 0.08, 0.06), 0.5),
    "concrete": material("Concrete_Base", (0.55, 0.54, 0.51), 0.9),
    "paint": material("Car_Paint", (0.12, 0.25, 0.48), 0.25, 0.55),
    "glass": material("Car_Glass", (0.06, 0.08, 0.10), 0.05, 0.3),
    "trim": material("Car_Trim", (0.05, 0.05, 0.055), 0.55),
    "tyre": material("Car_Tyre", (0.03, 0.03, 0.03), 0.85),
    "rim": material("Car_Rim", (0.70, 0.71, 0.73), 0.25, 1.0),
    "headlight": material("Car_Headlight", (0.95, 0.95, 0.90), 0.1, 0.2),
    "taillight": material("Car_Taillight", (0.60, 0.03, 0.03), 0.2),
    "plate": material("Car_Plate", (0.92, 0.92, 0.88), 0.5),
    "dog_fur": material("Dog_Fur", (0.55, 0.36, 0.18), 0.9),
    "dog_light": material("Dog_FurLight", (0.88, 0.82, 0.70), 0.9),
    "dog_dark": material("Dog_FurDark", (0.25, 0.16, 0.09), 0.9),
    "cat_fur": material("Cat_Fur", (0.45, 0.44, 0.42), 0.9),
    "cat_dark": material("Cat_FurDark", (0.22, 0.21, 0.20), 0.9),
    "cat_light": material("Cat_FurLight", (0.85, 0.83, 0.80), 0.9),
    "eye": material("Eye", (0.02, 0.02, 0.02), 0.1),
    "shrub_a": material("Shrub_A", (0.15, 0.30, 0.10), 0.9),
    "shrub_b": material("Shrub_B", (0.22, 0.38, 0.14), 0.9),
    "soil": material("Soil", (0.24, 0.17, 0.11), 0.95),
    "edging": material("Bed_Edging", (0.55, 0.52, 0.48), 0.85),
    "petal_red": material("Petal_Red", (0.80, 0.12, 0.15), 0.6),
    "petal_yellow": material("Petal_Yellow", (0.95, 0.80, 0.20), 0.6),
    "petal_purple": material("Petal_Purple", (0.55, 0.30, 0.75), 0.6),
    "petal_white": material("Petal_White", (0.95, 0.94, 0.90), 0.6),
    "nose": material("Nose", (0.05, 0.03, 0.03), 0.3),
}


def tree_round(coll, seed=3):
    rng = random.Random(seed)
    root = empty("TreeRound", coll)
    b = Builder(M)
    b.tube(g(0, 0, 0), g(0.05, 2.6, 0.02), 0.20, "bark", 10, 0.12)
    b.tube(g(0, 0, 0), g(0, 0.25, 0), 0.26, "bark", 10, 0.20)
    for i in range(5):
        a = i / 5 * math.tau + rng.uniform(-0.3, 0.3)
        start = g(0.04, rng.uniform(1.8, 2.4), 0.02)
        end = g(math.cos(a) * 1.2, rng.uniform(3.0, 3.8), math.sin(a) * 1.2)
        b.tube(start, end, 0.08, "bark", 7, 0.035)
    b.to_object("Trunk", coll, root)
    f = Builder(M)
    for i in range(9):
        a = rng.uniform(0, math.tau)
        rad = rng.uniform(0.3, 1.3)
        c = g(math.cos(a) * rad, rng.uniform(3.2, 4.9), math.sin(a) * rad)
        f.blob(c, rng.uniform(1.0, 1.45), rng.choice(["leaf_a", "leaf_b", "leaf_c"]), 3, 0.14, 0.85, rng)
    f.blob(g(0, 5.3, 0), 1.1, "leaf_b", 3, 0.14, 0.9, rng)
    f.to_object("Canopy", coll, root)
    return root


def tree_tall(coll, seed=7):
    rng = random.Random(seed)
    root = empty("TreeTall", coll)
    b = Builder(M)
    b.tube(g(0, 0, 0), g(0, 5.5, 0), 0.14, "bark_birch", 10, 0.05)
    for i in range(6):
        a = rng.uniform(0, math.tau)
        y = rng.uniform(1.8, 4.5)
        b.tube(g(0, y, 0), g(math.cos(a) * 0.7, y + 0.9, math.sin(a) * 0.7), 0.04, "bark_birch", 6, 0.015)
    b.to_object("Trunk", coll, root)
    f = Builder(M)
    for i in range(10):
        y = 2.4 + i * 0.42
        w = 0.95 * math.sin(min(1.0, (i + 1) / 10) * math.pi) + 0.35
        a = rng.uniform(0, math.tau)
        f.blob(g(math.cos(a) * 0.25, y, math.sin(a) * 0.25), w, rng.choice(["leaf_b", "leaf_c"]), 3, 0.16, 1.1, rng)
    f.to_object("Canopy", coll, root)
    return root


def street_lamp(coll):
    """Arm reaches toward local -Z (toward the road)."""
    root = empty("StreetLamp", coll)
    b = Builder(M)
    b.box(g(0, 0.15, 0), gs(0.32, 0.3, 0.32), "concrete", 0.02)
    b.tube(g(0, 0.3, 0), g(0, 6.0, 0), 0.085, "iron", 12, 0.055)
    b.tube(g(0, 0.3, 0), g(0, 0.9, 0), 0.11, "iron", 12, 0.09)
    prev = g(0, 5.7, 0)
    for i in range(1, 9):
        t = i / 8
        p = g(0, 5.7 + math.sin(t * math.pi * 0.5) * 0.4, -1.4 * t)
        b.tube(prev, p, 0.04, "iron", 8)
        prev = p
    b.box(g(0, 6.05, -1.45), gs(0.28, 0.12, 0.55), "iron", 0.03)
    b.box(g(0, 5.98, -1.45), gs(0.22, 0.03, 0.45), "lamp_glass")
    b.to_object("Lamp", coll, root)
    return root


def mailbox(coll):
    """Post at the origin; the door faces local +Z (the street side)."""
    root = empty("Mailbox", coll)
    b = Builder(M)
    b.box(g(0, 0.55, 0), gs(0.09, 1.1, 0.09), "wood_post")
    b.box(g(0, 1.08, 0), gs(0.18, 0.05, 0.42), "wood_post")
    b.box(g(0, 1.21, 0), gs(0.22, 0.2, 0.48), "mailbox", 0.015)
    b.tube(g(0, 1.31, -0.24), g(0, 1.31, 0.24), 0.11, "mailbox", 16)
    b.box(g(0, 1.23, 0.245), gs(0.2, 0.24, 0.015), "mailbox")
    b.box(g(0.125, 1.32, 0.05), gs(0.012, 0.04, 0.18), "flag")
    b.box(g(0.125, 1.38, 0.12), gs(0.012, 0.1, 0.07), "flag")
    b.to_object("Box", coll, root)
    return root


def bench(coll):
    root = empty("Bench", coll)
    b = Builder(M)
    for i in range(3):
        b.box(g(0, 0.45, -0.18 + i * 0.13), gs(1.8, 0.035, 0.11), "wood", 0.008)
    for i in range(2):
        b.box(g(0, 0.62 + i * 0.16, 0.26 + i * 0.03), gs(1.8, 0.11, 0.035), "wood", 0.008)
    for sx in (-0.78, 0.78):
        b.tube(g(sx, 0, -0.22), g(sx, 0.44, -0.18), 0.025, "iron", 8)
        b.tube(g(sx, 0, 0.22), g(sx, 0.44, 0.2), 0.025, "iron", 8)
        b.tube(g(sx, 0.43, -0.24), g(sx, 0.43, 0.24), 0.022, "iron", 8)
        b.tube(g(sx, 0.43, 0.22), g(sx, 0.9, 0.32), 0.022, "iron", 8)
        b.tube(g(sx, 0.62, -0.22), g(sx, 0.62, 0.0), 0.02, "iron", 8)
    b.to_object("Bench", coll, root)
    return root


def car(coll):
    """Compact hatchback, 4.1 m x 1.76 m x 1.45 m. Front is local -Z."""
    root = empty("Car", coll)
    b = Builder(M)
    # Lower body.
    b.box(g(0, 0.66, 0), (1.76, 4.1, 0.62), "paint", 0.09)
    # Bonnet slope and rear hatch shoulders.
    b.box(g(0, 0.98, -1.45), (1.66, 1.1, 0.08), "paint", 0.03)
    # Cabin (glass) with tapered top.
    cab_verts = b.box(g(0, 1.2, 0.25), (1.62, 2.3, 0.52), "glass")
    top_z = max(v.co.z for v in cab_verts)
    for v in cab_verts:
        if v.co.z > top_z - 1e-4:
            v.co.x *= 0.86
            if v.co.y > g(0, 0, 0.25).y:      # front-top (toward +Blender Y)
                v.co.y -= 0.55
            else:
                v.co.y += 0.12
    # Roof panel and pillars.
    b.box(g(0, 1.475, 0.42), (1.38, 1.5, 0.05), "paint", 0.02)
    for sx in (-0.8, 0.8):
        b.box(g(sx * 0.94, 1.2, 0.35), (0.06, 0.08, 0.5), "paint")
    # Bumpers, grille, lights, plates, mirrors, arches.
    b.box(g(0, 0.45, -2.07), (1.72, 0.12, 0.25), "trim", 0.03)
    b.box(g(0, 0.45, 2.07), (1.72, 0.12, 0.25), "trim", 0.03)
    b.box(g(0, 0.75, -2.06), (0.8, 0.04, 0.16), "trim")
    for sx in (-0.62, 0.62):
        b.box(g(sx, 0.82, -2.03), (0.32, 0.06, 0.13), "headlight", 0.015)
        b.box(g(sx, 0.9, 2.04), (0.28, 0.06, 0.16), "taillight", 0.015)
        b.box(g(sx * 1.45, 1.1, -0.85), (0.06, 0.16, 0.1), "trim", 0.01)
    b.box(g(0, 0.55, -2.13), (0.5, 0.01, 0.12), "plate")
    b.box(g(0, 0.7, 2.13), (0.5, 0.01, 0.12), "plate")
    for sx in (-0.86, 0.86):
        for sz in (-1.3, 1.3):
            b.box(g(sx, 0.55, sz), (0.06, 0.82, 0.3), "trim")
        b.box(g(sx, 0.8, 0.2), (0.02, 0.02, 0.06), "trim")  # door handle
    b.to_object("Body", coll, root)
    for name, sx, sz in (("WheelFL", -0.76, -1.3), ("WheelFR", 0.76, -1.3), ("WheelRL", -0.76, 1.3), ("WheelRR", 0.76, 1.3)):
        w = Builder(M)
        w.disc_x(Vector(), 0.32, 0.21, "tyre", 24)
        w.disc_x(Vector((0.11 if sx > 0 else -0.11, 0, 0)), 0.2, 0.02, "rim", 16)
        w.disc_x(Vector((0.12 if sx > 0 else -0.12, 0, 0)), 0.06, 0.02, "trim", 8)
        w.to_object(name, coll, root, g(sx, 0.32, sz))
    return root


# Real-world proportions (metres). body_y = body centre height, leg_y = hip
# pivot height (legs reach the ground from there).
DOG = dict(body_y=0.44, body=(0.30, 0.30, 0.72), leg_y=0.42, leg_r=(0.05, 0.038), hip_x=0.09, hip_z=0.25,
           neck=((0.52, -0.26), (0.62, -0.36)), neck_r=0.085, head_at=(0.64, -0.38), tail_at=(0.50, 0.34))
CAT = dict(body_y=0.21, body=(0.16, 0.17, 0.44), leg_y=0.20, leg_r=(0.026, 0.02), hip_x=0.05, hip_z=0.15,
           neck=((0.25, -0.16), (0.30, -0.21)), neck_r=0.045, head_at=(0.31, -0.22), tail_at=(0.25, 0.21))


def quadruped(coll, name, P, fur, light, dark, cat=False):
    """Dog/cat. Leg origins at hips/shoulders (swing about X); Head at the
    neck; Tail at its base. Faces Godot -Z."""
    root = empty(name, coll)
    bw, bh, bl = P["body"]
    by = P["body_y"]
    b = Builder(M)
    b.ellipsoid(g(0, by, 0), (bw, bl, bh), fur, 18, 12)
    # Chest/shoulders and haunches give the silhouette some shape.
    b.ellipsoid(g(0, by + bh * 0.05, -bl * 0.28), (bw * 1.05, bl * 0.42, bh * 1.08), light if not cat else fur, 14, 10)
    b.ellipsoid(g(0, by + bh * 0.05, bl * 0.30), (bw * 1.05, bl * 0.38, bh * 1.0), fur, 14, 10)
    (n0y, n0z), (n1y, n1z) = P["neck"]
    b.tube(g(0, n0y, n0z), g(0, n1y, n1z), P["neck_r"], fur, 12, P["neck_r"] * 0.85)
    b.to_object("Body", coll, root)

    hy, hz = P["head_at"]
    h = Builder(M)
    if cat:
        h.ellipsoid(g(0, 0.02, -0.03), (0.11, 0.10, 0.10), fur, 14, 10)
        h.ellipsoid(g(0, -0.01, -0.08), (0.06, 0.04, 0.045), light, 10, 6)
        for sx in (-1, 1):
            h.tube(g(sx * 0.03, 0.06, -0.03), g(sx * 0.04, 0.11, -0.025), 0.022, fur, 6, 0.002)
            h.ellipsoid(g(sx * 0.025, 0.03, -0.075), (0.018, 0.02, 0.012), "eye", 8, 6)
        h.ellipsoid(g(0, 0.0, -0.105), (0.016, 0.012, 0.01), "nose", 6, 4)
    else:
        h.ellipsoid(g(0, 0.04, -0.05), (0.19, 0.18, 0.18), fur, 14, 10)
        h.ellipsoid(g(0, 0.0, -0.17), (0.1, 0.16, 0.09), light, 12, 8)
        h.ellipsoid(g(0, 0.02, -0.25), (0.045, 0.03, 0.035), "nose", 8, 6)
        for sx in (-1, 1):
            h.ellipsoid(g(sx * 0.095, -0.01, -0.03), (0.04, 0.08, 0.15), dark, 8, 6)
            h.ellipsoid(g(sx * 0.045, 0.08, -0.12), (0.028, 0.03, 0.022), "eye", 8, 6)
    h.to_object("Head", coll, root, g(0, hy, hz))

    r0, r1 = P["leg_r"]
    ly = P["leg_y"]
    for lname, sx, sz in (("LegFL", -1, -1), ("LegFR", 1, -1), ("LegRL", -1, 1), ("LegRR", 1, 1)):
        L = Builder(M)
        L.ellipsoid(g(0, 0.0, 0), (r0 * 2.6, r0 * 2.6, r0 * 3.0), fur, 8, 6)    # shoulder/thigh
        L.tube(g(0, 0.0, 0), g(0, -ly + r1, 0), r0, fur, 8, r1)
        L.ellipsoid(g(0, -ly + r1 * 0.8, -r1 * 0.6), (r1 * 2.4, r1 * 3.2, r1 * 1.6), light if cat else fur, 8, 6)
        L.to_object(lname, coll, root, g(sx * P["hip_x"], ly, sz * P["hip_z"]))

    ty, tz = P["tail_at"]
    t = Builder(M)
    if cat:
        prev = g(0, 0, 0)
        for i in range(1, 9):
            a = i / 8
            p = g(0, a * 0.22, 0.05 + math.sin(a * 2.4) * 0.09)
            t.tube(prev, p, 0.018, dark if i % 2 else fur, 6, 0.016)
            prev = p
    else:
        t.tube(g(0, 0, 0), g(0, 0.16, 0.22), 0.035, fur, 8, 0.014)
    t.to_object("Tail", coll, root, g(0, ty, tz))
    return root


def shrub(coll, seed=11):
    rng = random.Random(seed)
    root = empty("Shrub", coll)
    b = Builder(M)
    for i in range(6):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(0.0, 0.35)
        b.blob(g(math.cos(a) * r, rng.uniform(0.35, 0.6), math.sin(a) * r), rng.uniform(0.32, 0.48), rng.choice(["shrub_a", "shrub_b"]), 2, 0.2, 0.85, rng)
    b.to_object("Shrub", coll, root)
    return root


def flower_bed(coll, seed=17):
    """1.6 m x 0.6 m raised bed with mixed flowers; long axis along X."""
    rng = random.Random(seed)
    root = empty("FlowerBed", coll)
    b = Builder(M)
    b.box(g(0, 0.07, 0), gs(1.6, 0.14, 0.6), "edging", 0.01)
    b.box(g(0, 0.145, 0), gs(1.5, 0.02, 0.5), "soil")
    # Leafy mounds first, then dense flower heads poking out of them.
    for i in range(9):
        x = -0.65 + i * 0.165
        b.blob(g(x, 0.2, rng.uniform(-0.08, 0.08)), rng.uniform(0.14, 0.19), rng.choice(["shrub_a", "shrub_b"]), 1, 0.2, 0.8, rng)
    for i in range(46):
        x = rng.uniform(-0.7, 0.7)
        z = rng.uniform(-0.2, 0.2)
        h = rng.uniform(0.2, 0.36)
        b.tube(g(x, 0.15, z), g(x, 0.15 + h, z), 0.007, "shrub_b", 4)
        b.ellipsoid(g(x, 0.16 + h, z), (0.1, 0.1, 0.06), rng.choice(["petal_red", "petal_yellow", "petal_purple", "petal_white"]), 8, 5)
    b.to_object("Bed", coll, root)
    return root


ASSETS = [
    ("tree_round", tree_round),
    ("tree_tall", tree_tall),
    ("street_lamp", street_lamp),
    ("mailbox", mailbox),
    ("bench", bench),
    ("car_hatchback", car),
    ("dog", lambda c: quadruped(c, "Dog", DOG, "dog_fur", "dog_light", "dog_dark")),
    ("cat", lambda c: quadruped(c, "Cat", CAT, "cat_fur", "cat_light", "cat_dark", cat=True)),
    ("shrub", shrub),
    ("flower_bed", flower_bed),
]

scene = bkit.fresh_scene("Props")
report = {}
roots = []
for fname, fn in ASSETS:
    coll = bpy.data.collections.new(fname)
    scene.collection.children.link(coll)
    root = fn(coll)
    bpy.context.view_layer.update()
    path = os.path.join(OUT_DIR, fname + ".glb")
    bkit.export_glb(scene, root, path)
    report[fname] = {"tris": bkit.tri_count(root), "bytes": os.path.getsize(path), "nodes": sorted(o.name for o in bkit.descendants(root))}
    roots.append(root)
    # Blender object names are global; free them so the next asset's parts
    # (Head, LegFL, ...) export without ".001" suffixes.
    for ob in bkit.descendants(root):
        ob.name = fname + "__" + ob.name
        if ob.data is not None and ob.data.users == 1:
            ob.data.name = ob.name

# Lay them out in a row for one preview render (after export, so GLB origins stay at 0).
x = 0.0
widths = {"tree_round": 5.5, "tree_tall": 3.5, "street_lamp": 2.5, "mailbox": 1.2, "bench": 2.5, "car_hatchback": 3.6, "dog": 2.2, "cat": 1.6, "shrub": 1.6, "flower_bed": 2.0}
for (fname, _), root in zip(ASSETS, roots):
    x += widths[fname] / 2
    root.location = Vector((x, 0, 0))
    x += widths[fname] / 2
bpy.context.view_layer.update()
bpy.data.libraries.write(os.path.join(bkit.PROJECT, "assets/blender/props.blend"), {scene}, fake_user=True, compress=True)
bkit.preview_render(scene, PREVIEW, (x / 2, -15.0, 4.0), (x / 2, 0, 1.6), 30, (1600, 640))
print("PROPS_BUILD_OK")
for k, v in report.items():
    print(k, v)
