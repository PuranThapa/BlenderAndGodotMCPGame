"""Render close-up previews of exported GLBs (checks the files Godot actually imports).

    Blender -b --factory-startup --python assets/blender/preview_glb.py -- out.png a.glb [b.glb ...]

Models are imported side by side along X, with a side-front 3/4 camera framed to fit.
"""
import bpy
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bkit  # noqa: E402
from mathutils import Vector  # noqa: E402

args = sys.argv[sys.argv.index("--") + 1:]
out, files = args[0], args[1:]
scene = bkit.fresh_scene("GLBPreview")
x = 0.0
lo = Vector((1e9, 1e9, 1e9))
hi = Vector((-1e9, -1e9, -1e9))
for f in files:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=f)
    new = [o for o in bpy.data.objects if o not in before]
    roots = [o for o in new if o.parent is None]
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ Vector(c) for o in new if o.type == "MESH" for c in o.bound_box]
    width = max(p.x for p in pts) - min(p.x for p in pts)
    for r in roots:
        r.location.x += x - min(p.x for p in pts)
    bpy.context.view_layer.update()
    for o in new:
        if o.type == "MESH":
            for c in o.bound_box:
                p = o.matrix_world @ Vector(c)
                lo = Vector(map(min, lo, p))
                hi = Vector(map(max, hi, p))
    x += width + 0.3
center = (lo + hi) / 2
size = max(hi.x - lo.x, hi.z - lo.z, 0.5)
bkit.preview_render(scene, out, center + Vector((size * 1.2, -size * 2.4, size * 0.7)), center, 40, (1280, 720))
print("PREVIEW_OK", out)
