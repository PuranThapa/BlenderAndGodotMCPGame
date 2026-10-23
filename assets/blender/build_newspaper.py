"""Builds textured newspaper models and exports them for Godot.

    python3 assets/textures/source/gen_newspaper.py      # textures first
    Blender -b --factory-startup --python assets/blender/build_newspaper.py

newspaper_folded.glb  0.34 x 0.24 m folded copy lying flat; printed front
                      page on top (headline toward local -Z), page edges,
                      fold and a red rubber band. Origin at its underside.
newspaper_open.glb    0.70 x 0.48 m open broadsheet, slightly V-folded, held
                      upright. Inside spread faces +Z (the reader), front page
                      faces -Z (everyone else). Origin at bottom centre.
"""
import bpy
import bmesh
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bkit  # noqa: E402
from bkit import g, gs, Builder, material, empty  # noqa: E402

TEX = os.path.join(bkit.PROJECT, "assets/textures")
OUT = os.path.join(bkit.PROJECT, "assets/models")


def image_material(name, image_file):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(os.path.join(TEX, image_file), check_existing=True)
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.95
    return m


M = {
    "front": image_material("Newsprint_FrontPage", "newspaper_front.png"),
    "spread": image_material("Newsprint_Spread", "newspaper_spread.png"),
    "plain": material("Newsprint_Plain", (0.85, 0.83, 0.77), 0.95),
    "edge": material("Newsprint_Edge", (0.78, 0.76, 0.70), 0.95),
    "band": material("Rubber_Band", (0.72, 0.08, 0.06), 0.6),
}


def textured_sheet(bm, uv, slot, nx, ny, pos_fn, uv_fn):
    """Grid surface: pos_fn(i/nx, j/ny) -> Blender Vector, uv_fn(u, v) -> (u, v)."""
    verts = [[bm.verts.new(pos_fn(i / nx, j / ny)) for i in range(nx + 1)] for j in range(ny + 1)]
    for j in range(ny):
        for i in range(nx):
            f = bm.faces.new((verts[j][i], verts[j][i + 1], verts[j + 1][i + 1], verts[j + 1][i]))
            f.material_index = slot
            f.smooth = True
            for loop in f.loops:
                for jj in range(ny + 1):
                    for ii in range(nx + 1):
                        if verts[jj][ii] is loop.vert:
                            loop[uv].uv = uv_fn(ii / nx, jj / ny)
    return verts


def folded(coll):
    root = empty("NewspaperFolded", coll)
    W, D, T = 0.34, 0.24, 0.012
    bow = 0.008
    b = Builder(M)
    for k in ("front", "plain", "edge", "band"):
        b.slot(k)
    uv = b.bm.loops.layers.uv.new("UVMap")

    # Top: printed front page. u along +X, v toward -Z (top of the page).
    def top(u, v):
        x = (u - 0.5) * W
        z = (0.5 - v) * D
        y = T + bow * math.sin(math.pi * u) * math.sin(math.pi * v)
        return g(x, y, z)
    textured_sheet(b.bm, uv, b.slot("front"), 12, 8, top, lambda u, v: (u, v))

    # Underside (faces down): plain newsprint.
    def under(u, v):
        return g((0.5 - u) * W, 0.0, (0.5 - v) * D)
    textured_sheet(b.bm, uv, b.slot("plain"), 2, 2, under, lambda u, v: (u, v))
    # Page edges (stack of sheets) on three sides, rounded fold along the top edge.
    b.box(g(0, T / 2, D / 2 - 0.001), gs(W, T, 0.002), "edge")
    b.box(g(-W / 2 + 0.001, T / 2, 0), gs(0.002, T, D), "edge")
    b.box(g(W / 2 - 0.001, T / 2, 0), gs(0.002, T, D), "edge")
    b.tube(g(-W / 2, T / 2, -D / 2), g(W / 2, T / 2, -D / 2), T / 2, "plain", 8)
    # Rubber band around the short side, near the right end (clear of the headline).
    bx = W * 0.36
    b.box(g(bx, T + bow * 0.3 + 0.002, 0), gs(0.012, 0.003, D + 0.004), "band")
    b.box(g(bx, -0.0015, 0), gs(0.012, 0.003, D + 0.004), "band")
    b.box(g(bx, T / 2, D / 2 + 0.002), gs(0.012, T + 0.006, 0.003), "band")
    b.box(g(bx, T / 2, -D / 2 - 0.002), gs(0.012, T + 0.006, 0.003), "band")
    b.to_object("Paper", coll, root)
    return root


def opened(coll):
    root = empty("NewspaperOpen", coll)
    W, H = 0.70, 0.48
    fold = math.radians(14)
    b = Builder(M)
    for k in ("spread", "front"):
        b.slot(k)
    uv = b.bm.loops.layers.uv.new("UVMap")

    # V-fold: each half rotates toward the reader (+Z) about the spine.
    def surf(u, v, offset):
        x = (u - 0.5) * W
        z = abs(x) * math.sin(fold) + offset
        return g(x * math.cos(fold), v * H, z)

    # Reader's side (+Z): inside spread, u along +X.
    textured_sheet(b.bm, uv, b.slot("spread"), 10, 6, lambda u, v: surf(u, v, 0.001), lambda u, v: (u, v))
    # Outer side (-Z): front page, mirrored so it reads correctly from the front.
    textured_sheet(b.bm, uv, b.slot("front"), 10, 6, lambda u, v: surf(1.0 - u, v, -0.001), lambda u, v: (u, v))
    b.to_object("Paper", coll, root)
    return root


scene = bkit.fresh_scene("Newspaper")
report = {}
roots = []
for fname, fn in (("newspaper_folded", folded), ("newspaper_open", opened)):
    coll = bpy.data.collections.new(fname)
    scene.collection.children.link(coll)
    root = fn(coll)
    bpy.context.view_layer.update()
    bkit.export_glb(scene, root, os.path.join(OUT, fname + ".glb"))
    report[fname] = bkit.tri_count(root)
    for ob in bkit.descendants(root):
        ob.name = fname + "__" + ob.name
    roots.append(root)
roots[0].location = (0.0, 0.0, 0.0)
roots[1].location = (0.55, 0.15, 0.0)
bpy.context.view_layer.update()
bkit.preview_render(scene, os.path.join(bkit.PROJECT, "assets/reference/newspaper_preview.png"), (0.15, -0.95, 0.75), (0.28, 0.0, 0.12), 45, (1200, 800))
print("NEWSPAPER_BUILD_OK", report)
