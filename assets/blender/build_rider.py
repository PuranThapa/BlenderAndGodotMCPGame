"""Builds the paperboy rider as rigid body segments and exports assets/models/rider.glb.

    Blender -b --factory-startup --python assets/blender/build_rider.py

The game poses each segment every frame (pedal/grip IK in bike_visual.gd), so
each one is a separate object whose origin is its joint pivot:
    Torso     pivot at hip centre, extends +Y to the shoulders (0.5 m)
    Head      pivot at the base of the neck, extends +Y
    UpperArmL/R  pivot at shoulder, extends -Y 0.30 m to the elbow
    ForearmL/R   pivot at elbow, extends -Y; hand centre at -0.30 m
    ThighL/R     pivot at hip joint, extends -Y 0.46 m to the knee
    ShinL/R      pivot at knee, extends -Y 0.44 m to the ankle
    FootL/R      pivot at ankle, shoe extends toward -Z (forward)
All segments face Godot -Z.
"""
import bpy
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bkit  # noqa: E402
from bkit import g, gs, Builder, material, empty  # noqa: E402

# `-- pedestrian` builds the townsfolk variant: same segments, no satchel or cap.
PEDESTRIAN = "pedestrian" in (sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
NAME = "pedestrian" if PEDESTRIAN else "rider"
OUT = os.path.join(bkit.PROJECT, "assets/models/%s.glb" % NAME)
PREVIEW = os.path.join(bkit.PROJECT, "assets/reference/%s_preview.png" % NAME)

M = {
    "skin": material("Rider_Skin", (0.74, 0.53, 0.38), 0.6),
    "shirt": material("Rider_Shirt", (0.16, 0.33, 0.58), 0.85),
    "shirt_dark": material("Rider_ShirtCollar", (0.10, 0.20, 0.38), 0.85),
    "jeans": material("Rider_Jeans", (0.17, 0.22, 0.33), 0.9),
    "shoe": material("Rider_Shoe", (0.12, 0.10, 0.09), 0.7),
    "sole": material("Rider_Sole", (0.88, 0.87, 0.84), 0.8),
    "cap": material("Rider_Cap", (0.70, 0.11, 0.09), 0.8),
    "hair": material("Rider_Hair", (0.12, 0.08, 0.05), 0.9),
    "eye": material("Rider_Eye", (0.03, 0.03, 0.03), 0.2),
    "bag": material("Rider_Satchel", (0.62, 0.42, 0.16), 0.75),
    "bag_strap": material("Rider_Strap", (0.40, 0.26, 0.10), 0.8),
    "paper": material("Rider_Newsprint", (0.86, 0.84, 0.78), 0.95),
}

TORSO_LEN = 0.50
UPPER_ARM = 0.30
FOREARM = 0.30
THIGH = 0.46
SHIN = 0.44


def torso(coll, root):
    b = Builder(M)
    b.ellipsoid(g(0, 0.04, 0.0), (0.32, 0.20, 0.20), "jeans", 16, 10)           # pelvis
    b.ellipsoid(g(0, 0.20, 0.0), (0.30, 0.22, 0.30), "shirt", 16, 10)           # waist
    b.ellipsoid(g(0, 0.34, -0.005), (0.36, 0.24, 0.30), "shirt", 16, 10)        # chest
    b.ellipsoid(g(0, 0.45, 0.01), (0.42, 0.20, 0.13), "shirt", 16, 8)           # shoulders
    b.tube(g(0, 0.49, 0.0), g(0, 0.53, -0.005), 0.065, "shirt_dark", 12)         # collar
    # Satchel strap across the chest, left shoulder to right hip.
    if PEDESTRIAN:
        return b.to_object("Torso", coll, root)
    # Straps follow the shirt surface (chest/back ellipsoids are ~0.15 m deep).
    for sz in (-1, 1):
        b.tube(g(-0.15, 0.50, sz * 0.05), g(-0.05, 0.38, sz * 0.165), 0.02, "bag_strap", 6)
        b.tube(g(-0.05, 0.38, sz * 0.165), g(0.10, 0.20, sz * 0.16), 0.02, "bag_strap", 6)
        b.tube(g(0.10, 0.20, sz * 0.16), g(0.19, 0.10, sz * 0.10), 0.02, "bag_strap", 6)
    # Satchel on the right hip with papers poking out.
    b.box(g(0.21, 0.02, 0.0), gs(0.10, 0.28, 0.34), "bag", 0.02)
    b.box(g(0.215, 0.13, 0.0), gs(0.11, 0.08, 0.35), "bag_strap", 0.01)
    for i, z in enumerate((-0.09, 0.0, 0.09)):
        b.tube(g(0.20, 0.10, z), g(0.20, 0.21 + 0.02 * i, z + 0.01), 0.03, "paper", 8)
    return b.to_object("Torso", coll, root)


def head(coll, root):
    b = Builder(M)
    b.tube(g(0, 0.0, 0), g(0, 0.09, -0.01), 0.055, "skin", 10)
    b.ellipsoid(g(0, 0.17, -0.02), (0.18, 0.22, 0.20), "skin", 16, 12)
    b.ellipsoid(g(0, 0.15, -0.115), (0.035, 0.05, 0.04), "skin", 8, 6)          # nose
    for sx in (-1, 1):
        b.ellipsoid(g(sx * 0.093, 0.17, 0.0), (0.03, 0.06, 0.04), "skin", 8, 6)  # ears
        b.ellipsoid(g(sx * 0.04, 0.19, -0.105), (0.025, 0.022, 0.015), "eye", 8, 6)
    b.ellipsoid(g(0, 0.2, 0.03), (0.19, 0.2, 0.17), "hair", 14, 10)             # hair at the back
    if PEDESTRIAN:
        b.ellipsoid(g(0, 0.25, 0.0), (0.195, 0.12, 0.2), "hair", 14, 8)          # hair on top
        return b.to_object("Head", coll, root)
    # Cap: crown, button and forward brim.
    b.ellipsoid(g(0, 0.25, -0.01), (0.205, 0.13, 0.215), "cap", 16, 10)
    b.ellipsoid(g(0, 0.31, -0.01), (0.025, 0.015, 0.025), "cap", 6, 4)
    b.box(g(0, 0.235, -0.15), gs(0.17, 0.015, 0.11), "cap", 0.005)
    return b.to_object("Head", coll, root)


def upper_arm(coll, root, side):
    b = Builder(M)
    b.ellipsoid(g(0, -0.01, 0), (0.11, 0.12, 0.11), "shirt", 10, 8)
    b.tube(g(0, 0, 0), g(0, -0.17, 0), 0.052, "shirt", 10, 0.048)
    b.tube(g(0, -0.17, 0), g(0, -UPPER_ARM, 0), 0.042, "skin", 10, 0.038)
    return b.to_object("UpperArm" + side, coll, root)


def forearm(coll, root, side):
    b = Builder(M)
    b.tube(g(0, 0, 0), g(0, -0.25, 0), 0.038, "skin", 10, 0.03)
    b.ellipsoid(g(0, -FOREARM + 0.01, -0.005), (0.075, 0.1, 0.045), "skin", 10, 8)     # hand
    b.ellipsoid(g(0, -FOREARM - 0.025, -0.02), (0.07, 0.05, 0.04), "skin", 8, 6)      # fingers wrapped
    return b.to_object("Forearm" + side, coll, root)


def thigh(coll, root, side):
    b = Builder(M)
    b.tube(g(0, 0.02, 0), g(0, -THIGH, 0), 0.075, "jeans", 12, 0.058)
    return b.to_object("Thigh" + side, coll, root)


def shin(coll, root, side):
    b = Builder(M)
    b.ellipsoid(g(0, 0, 0), (0.12, 0.12, 0.12), "jeans", 10, 8)
    b.tube(g(0, 0, 0), g(0, -SHIN + 0.04, 0), 0.056, "jeans", 12, 0.046)
    return b.to_object("Shin" + side, coll, root)


def foot(coll, root, side):
    b = Builder(M)
    b.ellipsoid(g(0, -0.035, -0.06), (0.10, 0.09, 0.26), "shoe", 12, 8)
    b.box(g(0, -0.075, -0.06), gs(0.105, 0.025, 0.27), "sole", 0.008)
    return b.to_object("Foot" + side, coll, root)


scene = bkit.fresh_scene("Pedestrian" if PEDESTRIAN else "Rider")
coll = bpy.data.collections.new("RiderExport")
scene.collection.children.link(coll)
root = empty("Rider", coll)
torso(coll, root)
head(coll, root).location = g(0, TORSO_LEN, 0)
for side, sx in (("L", -1), ("R", 1)):
    upper_arm(coll, root, side).location = g(sx * 0.19, 0.46, 0)
    forearm(coll, root, side).location = g(sx * 0.19, 0.46 - UPPER_ARM, 0)
    thigh(coll, root, side).location = g(sx * 0.09, 0.0, 0)
    shin(coll, root, side).location = g(sx * 0.09, -THIGH, 0)
    foot(coll, root, side).location = g(sx * 0.09, -THIGH - SHIN, 0)
# Stand the reference pose on the ground (hips at leg length) for the preview.
root.location = g(0, THIGH + SHIN + 0.08, 0)
bpy.context.view_layer.update()
root.location = g(0, 0, 0)
bkit.export_glb(scene, root, OUT)
tris = bkit.tri_count(root)
bpy.data.libraries.write(os.path.join(bkit.PROJECT, "assets/blender/%s.blend" % NAME), {scene}, fake_user=True, compress=True)
root.location = g(0, THIGH + SHIN + 0.08, 0)
root.rotation_euler = (0, 0, math.radians(200))
bpy.context.view_layer.update()
bkit.preview_render(scene, PREVIEW, (1.4, -2.6, 1.3), (0, 0, 0.9), 50, (900, 900))
print("RIDER_BUILD_OK %s tris=%d" % (NAME, tris))
