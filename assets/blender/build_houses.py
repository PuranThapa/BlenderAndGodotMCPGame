"""Builds the modular house kit and exports one GLB per piece.

    Blender -b --factory-startup --python assets/blender/build_houses.py

Every piece is authored so that local +Z points out of the wall (toward the
street) and the wall face is at z = 0, matching city_builder.gd's house frame.
Recolourable materials (per-instance overrides in Godot): "Door_Paint",
"Shutter_Paint".
    house_door      origin: bottom centre on the wall face      (1.2 x 2.3 m)
    house_window    origin: centre of the opening on the face  (1.3 x 1.4 m); child "Shutters"
    house_canopy    origin: wall face at canopy underside      (1.9 m wide)
    house_chimney   origin: bottom centre                      (0.7 x 1.6 x 0.6 m)
    fence_picket    origin: bottom centre, runs along X        (2.0 m long)
"""
import bpy
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bkit  # noqa: E402
from bkit import g, gs, Builder, material, empty  # noqa: E402
from mathutils import Vector  # noqa: E402

OUT_DIR = os.path.join(bkit.PROJECT, "assets/models")
PREVIEW = os.path.join(bkit.PROJECT, "assets/reference/house_kit_preview.png")

M = {
    "trim": material("Trim_White", (0.90, 0.89, 0.85), 0.55),
    "door": material("Door_Paint", (0.12, 0.30, 0.20), 0.45),
    "brass": material("Brass", (0.78, 0.60, 0.25), 0.3, 1.0),
    "glass": material("Window_Glass", (0.10, 0.14, 0.18), 0.05, 0.5),
    "stone": material("Stone_Sill", (0.68, 0.65, 0.60), 0.85),
    "shutter": material("Shutter_Paint", (0.18, 0.28, 0.22), 0.6),
    "roof": material("Canopy_Roof", (0.25, 0.25, 0.27), 0.8),
    "brick": material("Chimney_Brick", (0.50, 0.25, 0.18), 0.9),
    "pot": material("Chimney_Pot", (0.62, 0.33, 0.22), 0.8),
    "picket": material("Picket_White", (0.92, 0.91, 0.87), 0.7),
}


def door(coll):
    root = empty("HouseDoor", coll)
    b = Builder(M)
    # Frame (architrave) proud of the wall.
    b.box(g(-0.56, 1.15, 0.05), gs(0.1, 2.3, 0.1), "trim", 0.01)
    b.box(g(0.56, 1.15, 0.05), gs(0.1, 2.3, 0.1), "trim", 0.01)
    b.box(g(0, 2.33, 0.05), gs(1.32, 0.12, 0.12), "trim", 0.01)
    # Slab recessed into the reveal, four raised panels and a glazed top light.
    b.box(g(0, 1.06, 0.02), gs(1.02, 2.12, 0.05), "door", 0.005)
    for px in (-0.22, 0.22):
        b.box(g(px, 0.5, 0.05), gs(0.32, 0.62, 0.02), "door", 0.008)
        b.box(g(px, 1.25, 0.05), gs(0.32, 0.55, 0.02), "door", 0.008)
    b.box(g(0, 1.85, 0.047), gs(0.76, 0.28, 0.02), "glass")
    for gx in (-0.19, 0.0, 0.19):
        b.box(g(gx, 1.85, 0.06), gs(0.025, 0.28, 0.015), "door")
    # Brass knob, letter slot and kick plate.
    b.ellipsoid(g(0.38, 1.0, 0.09), (0.06, 0.06, 0.06), "brass", 10, 8)
    b.box(g(0, 1.02, 0.05), gs(0.28, 0.05, 0.02), "brass", 0.004)
    b.box(g(0, 0.08, 0.05), gs(0.9, 0.14, 0.01), "brass")
    b.to_object("Door", coll, root)
    return root


def window(coll):
    root = empty("HouseWindow", coll)
    b = Builder(M)
    w, h, t = 1.3, 1.4, 0.08
    b.box(g(0, h / 2 - t / 2, 0.03), gs(w, t, 0.1), "trim", 0.008)
    b.box(g(0, -h / 2 + t / 2, 0.03), gs(w, t, 0.1), "trim", 0.008)
    b.box(g(-w / 2 + t / 2, 0, 0.03), gs(t, h, 0.1), "trim", 0.008)
    b.box(g(w / 2 - t / 2, 0, 0.03), gs(t, h, 0.1), "trim", 0.008)
    # Glass sits just proud of the wall face: the game's walls are solid boxes.
    b.box(g(0, 0, 0.01), gs(w - 0.1, h - 0.1, 0.01), "glass")
    # Sash bars: one vertical, two horizontal (six lights).
    b.box(g(0, 0, 0.03), gs(0.04, h - 0.1, 0.03), "trim")
    for y in (-0.22, 0.22):
        b.box(g(0, y, 0.03), gs(w - 0.1, 0.04, 0.03), "trim")
    # Stone sill and lintel.
    b.box(g(0, -h / 2 - 0.04, 0.07), gs(w + 0.2, 0.07, 0.2), "stone", 0.01)
    b.box(g(0, h / 2 + 0.07, 0.03), gs(w + 0.16, 0.14, 0.08), "stone", 0.01)
    b.to_object("Frame", coll, root)
    s = Builder(M)
    for sx in (-1, 1):
        cx = sx * (w / 2 + 0.26)
        s.box(g(cx, 0, 0.03), gs(0.44, h, 0.04), "shutter", 0.006)
        for i in range(9):
            s.box(g(cx, -h / 2 + 0.12 + i * 0.145, 0.055), gs(0.38, 0.05, 0.015), "shutter")
    s.to_object("Shutters", coll, root)
    return root


def canopy(coll):
    root = empty("HouseCanopy", coll)
    b = Builder(M)
    roof = b.box(g(0, 0.12, 0.45), gs(1.9, 0.08, 0.95), "roof")
    for v in roof:      # slope it down toward the street
        if v.co.y < -0.3:          # Blender -Y = Godot +Z (outer edge)
            v.co.z -= 0.12
    b.box(g(0, 0.0, 0.88), gs(1.92, 0.12, 0.04), "trim")
    for sx in (-0.85, 0.85):
        b.tube(g(sx, -0.45, 0.02), g(sx, 0.02, 0.8), 0.03, "trim", 8)
        b.box(g(sx, -0.2, 0.03), gs(0.06, 0.6, 0.06), "trim")
    b.to_object("Canopy", coll, root)
    return root


def chimney(coll):
    root = empty("HouseChimney", coll)
    b = Builder(M)
    b.box(g(0, 0.8, 0), gs(0.7, 1.6, 0.6), "brick", 0.01)
    b.box(g(0, 1.62, 0), gs(0.84, 0.1, 0.74), "stone", 0.01)
    b.box(g(0, 1.2, 0), gs(0.74, 0.06, 0.64), "stone")
    for px in (-0.15, 0.15):
        b.tube(g(px, 1.66, 0), g(px, 1.95, 0), 0.09, "pot", 12, 0.075)
    b.to_object("Chimney", coll, root)
    return root


def picket_fence(coll):
    root = empty("FencePicket", coll)
    b = Builder(M)
    for px in (-0.97, 0.97):
        b.box(g(px, 0.5, 0), gs(0.09, 1.0, 0.09), "picket", 0.008)
        b.box(g(px, 1.03, 0), gs(0.12, 0.05, 0.12), "picket", 0.008)
    for y in (0.28, 0.72):
        b.box(g(0, y, -0.035), gs(1.9, 0.07, 0.025), "picket")
    n = 12
    for i in range(n):
        x = -0.85 + i * (1.7 / (n - 1))
        b.box(g(x, 0.43, 0.0), gs(0.075, 0.78, 0.02), "picket")
        b.tube(g(x, 0.82, 0.0), g(x, 0.9, 0.0), 0.05, "picket", 4, 0.001)
    b.to_object("Fence", coll, root)
    return root


ASSETS = [
    ("house_door", door, 1.6),
    ("house_window", window, 2.6),
    ("house_canopy", canopy, 2.3),
    ("house_chimney", chimney, 1.2),
    ("fence_picket", picket_fence, 2.4),
]

scene = bkit.fresh_scene("HouseKit")
roots = []
for fname, fn, _w in ASSETS:
    coll = bpy.data.collections.new(fname)
    scene.collection.children.link(coll)
    root = fn(coll)
    bpy.context.view_layer.update()
    bkit.export_glb(scene, root, os.path.join(OUT_DIR, fname + ".glb"))
    print(fname, "tris", bkit.tri_count(root))
    for ob in bkit.descendants(root):
        ob.name = fname + "__" + ob.name
    roots.append(root)

# Preview: pieces in a row against a backing wall.
x = 0.0
for (fname, _fn, w), root in zip(ASSETS, roots):
    x += w / 2
    root.location = Vector((x, 0, 1.2 if fname in ("house_window",) else (2.4 if fname == "house_canopy" else 0)))
    x += w / 2
wall = Builder({"w": material("Preview_Wall", (0.80, 0.74, 0.62), 0.9)})
wall.box(Vector((x / 2, 0.15, 1.6)), (x + 1, 0.3, 3.2), "w")
wall.to_object("PreviewWall", scene.collection)
bpy.context.view_layer.update()
bpy.data.libraries.write(os.path.join(bkit.PROJECT, "assets/blender/house_kit.blend"), {scene}, fake_user=True, compress=True)
bkit.preview_render(scene, PREVIEW, (x / 2 + 2.0, -9.0, 2.2), (x / 2, 0, 1.3), 32, (1600, 700))
print("HOUSEKIT_BUILD_OK")
