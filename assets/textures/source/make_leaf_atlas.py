"""Builds leaf-cluster atlases for the trees from real leaf photos (Pixabay,
transparent cut-outs), plus the bark textures.

    python3 assets/textures/source/make_leaf_atlas.py

Outputs (assets/textures/trees/):
    leaves_broad.png  2048x2048 RGBA, 2x2 cluster cards (oak / maple)
    leaves_small.png  2048x2048 RGBA, 2x2 cluster cards (birch)
    bark_*_albedo.jpg / _normal.png come from pixabay_fetch.get() into ../pixabay
Each card: twigs from the bottom-centre with ~70-120 leaves stamped along them,
varied in angle, size and shade (inner leaves darker for self-shadowing).
"""
import io
import json
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pixabay_fetch as pf  # noqa: E402

OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "trees"))
LEAF_SOURCES = [1638813]               # transparent leaf cut-outs on Pixabay (3 clean leaves)
rng = random.Random(11)


def leaf_sprites() -> list:
    sprites = []
    credits = {}
    for pid in LEAF_SOURCES:
        hit = pf.query(id=pid)["hits"][0]
        img = Image.open(io.BytesIO(pf.fetch(pf.cdn_url(hit, 1280)))).convert("RGBA")
        a = np.asarray(img)[..., 3]
        labels, n = ndimage.label(a > 60)
        sizes = ndimage.sum(np.ones_like(a), labels, range(1, n + 1))
        for i, size in enumerate(sizes, start=1):
            if size < 2500:
                continue                      # specks
            ys, xs = np.where(labels == i)
            box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
            crop = img.crop(box)
            mask = Image.fromarray(((labels[box[1]:box[3], box[0]:box[2]] == i) * 255).astype(np.uint8))
            crop.putalpha(Image.fromarray(np.minimum(np.asarray(crop)[..., 3], np.asarray(mask))))
            sprites.append(crop)
        credits[str(pid)] = {"author": hit["user"], "page": hit["pageURL"], "license": "Pixabay Content License"}
    return sprites, credits


def tint(img: Image.Image, hue_rgb, amount: float, bright: float) -> Image.Image:
    a = np.asarray(img).astype(np.float64)
    rgb = a[..., :3]
    lum = rgb.mean(axis=2, keepdims=True)
    target = lum * np.array(hue_rgb)[None, None, :] / max(np.mean(hue_rgb), 1e-3)
    rgb = rgb * (1 - amount) + target * amount
    a[..., :3] = np.clip(rgb * bright, 0, 255)
    return Image.fromarray(a.astype(np.uint8))


def cluster_card(sprites, size, hue, leaf_scale, count, seed) -> Image.Image:
    r = random.Random(seed)
    card = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(card)
    margin = int(size * 0.04)
    base = (size // 2, size - margin)
    # Twig skeleton: a main stem with side shoots fanning upward.
    tips = []
    clamp = lambda q: (min(max(q[0], margin * 2), size - margin * 2), min(max(q[1], margin * 2), size - margin))
    for k in range(r.randint(4, 6)):
        ang = math.radians(r.uniform(-62, 62))
        length = size * r.uniform(0.5, 0.72)
        end = clamp((base[0] + math.sin(ang) * length, base[1] - math.cos(ang) * length))
        # Twig layout only; real wood comes from the 3D branches, so no lines are drawn.
        for j in range(3):
            t = r.uniform(0.35, 0.95)
            p = (base[0] + (end[0] - base[0]) * t, base[1] + (end[1] - base[1]) * t)
            a2 = ang + math.radians(r.choice([-1, 1]) * r.uniform(25, 55))
            l2 = length * r.uniform(0.25, 0.45)
            e2 = clamp((p[0] + math.sin(a2) * l2, p[1] - math.cos(a2) * l2))
            tips.append((p, e2))
        tips.append((base, end))
    # Leaves: deeper ones first and darker, outer ones brighter on top.
    for i in range(count):
        p0, p1 = r.choice(tips)
        t = r.uniform(0.3, 1.0)
        pos = (p0[0] + (p1[0] - p0[0]) * t + r.uniform(-18, 18), p0[1] + (p1[1] - p0[1]) * t + r.uniform(-18, 18))
        depth = i / count
        spr = r.choice(sprites)
        s = size * leaf_scale * r.uniform(0.7, 1.2) / max(spr.size)
        leaf = spr.resize((max(4, int(spr.width * s)), max(4, int(spr.height * s))), Image.LANCZOS)
        leaf = tint(leaf, hue, 0.55, 0.62 + 0.45 * depth + r.uniform(-0.06, 0.06))
        out_angle = math.degrees(math.atan2(pos[0] - base[0], base[1] - pos[1]))
        leaf = leaf.rotate(-out_angle + r.uniform(-50, 50), resample=Image.BICUBIC, expand=True)
        x0, y0 = int(pos[0] - leaf.width / 2), int(pos[1] - leaf.height / 2)
        # Keep every leaf fully inside the card so cards never show hard edges.
        if x0 < margin or y0 < margin or x0 + leaf.width > size - margin or y0 + leaf.height > size - margin:
            continue
        card.alpha_composite(leaf, (x0, y0))
    return card


def atlas(sprites, name, hue, leaf_scale, count, seed):
    cell = 1024
    out = Image.new("RGBA", (cell * 2, cell * 2), (0, 0, 0, 0))
    for k in range(4):
        card = cluster_card(sprites, cell, hue, leaf_scale, count, seed + k)
        out.alpha_composite(card, ((k % 2) * cell, (k // 2) * cell))
    # Bleed colour into transparent texels so mipmaps don't show dark fringes.
    a = np.asarray(out).astype(np.float64)
    alpha = a[..., 3:4] / 255.0
    rgb = a[..., :3]
    blur = np.asarray(out.convert("RGB").resize((64, 64), Image.BILINEAR).resize((cell * 2, cell * 2), Image.BILINEAR)).astype(np.float64)
    fill = np.array([60, 85, 40], dtype=np.float64)
    rgb = rgb * alpha + (blur * 0.5 + fill * 0.5) * (1 - alpha)
    res = np.concatenate([rgb, a[..., 3:4]], axis=-1).clip(0, 255).astype(np.uint8)
    Image.fromarray(res, "RGBA").save(os.path.join(OUT, name))
    print("saved", name)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    sprites, credits = leaf_sprites()
    print("leaf sprites:", len(sprites))
    atlas(sprites, "leaves_broad.png", (70, 120, 45), 0.19, 170, 100)
    atlas(sprites, "leaves_small.png", (115, 150, 55), 0.13, 260, 200)
    json.dump({"leaf_sources": credits}, open(os.path.join(OUT, "CREDITS.json"), "w"), indent=2)
