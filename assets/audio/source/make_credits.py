"""Regenerates res://credits.txt (shown in-game: Pause -> Credits) from the
Openverse sound and Pixabay texture credit files."""
import json, os
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
lines = ["PAPER BOY: MORNING DELIVERY", "", "Made with Godot Engine and Blender.",
         "Models, newspaper art and synthesized sounds: original work for this game.", "",
         "SOUND RECORDINGS (via Openverse / Freesound)"]
snd = json.load(open(os.path.join(ROOT, "assets/audio/openverse/CREDITS.json")))
for k, v in sorted(snd.items()):
    lines.append('"%s" by %s - %s - %s' % (v["title"], v["creator"], v["license"].strip(), v["page"]))
lines += ["", "PHOTO TEXTURES (Pixabay Content License)"]
tex = json.load(open(os.path.join(ROOT, "assets/textures/pixabay/CREDITS.json")))
for k, v in sorted(tex.items()):
    lines.append("%s: photo by %s - %s" % (k, v["author"], v["page"]))
lc = json.load(open(os.path.join(ROOT, "assets/textures/trees/CREDITS.json")))["leaf_sources"]
for k, v in lc.items():
    lines.append("leaf cut-outs: photo by %s - %s" % (v["author"], v["page"]))
open(os.path.join(ROOT, "credits.txt"), "w").write("\n".join(lines) + "\n")
print("credits.txt:", len(lines), "lines")
