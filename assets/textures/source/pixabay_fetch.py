"""Pixabay texture sourcing for Paper Boy (uses the public Pixabay API).

The API key is read from $PIXABAY_API_KEY, or from the
`export PIXABAY_API_KEY=...` line in ~/.zshrc. It is never written to the repo.

    python3 pixabay_fetch.py search "asphalt texture" /tmp/sheet.png
        -> contact sheet of 12 candidates labelled with their Pixabay IDs
    python3 pixabay_fetch.py get <id> <name> [--crop cx,cy,frac] [--tile 1024]
        -> assets/textures/pixabay/<name>_albedo.jpg   (lighting-flattened, seamless)
           assets/textures/pixabay/<name>_normal.png   (from luminance)
           credits appended to assets/textures/pixabay/CREDITS.json

Pixabay Content License: free to use in games, no attribution required; we
still record the source of every image.
"""
import io
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(os.path.join(HERE, "..", "pixabay"))
API = "https://pixabay.com/api/"


def api_key() -> str:
    key = os.environ.get("PIXABAY_API_KEY", "")
    if not key:
        rc = os.path.expanduser("~/.zshrc")
        if os.path.exists(rc):
            for line in open(rc):
                m = re.match(r"\s*export\s+PIXABAY_API_KEY=(\S+)", line)
                if m:
                    key = m.group(1).strip("'\"")
    if not key:
        sys.exit("PIXABAY_API_KEY not set")
    return key


UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"


def fetch(url: str, tries: int = 4) -> bytes:
    for attempt in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=60) as r:
                data = r.read()
            time.sleep(0.4)       # be gentle with the CDN
            return data
        except urllib.error.HTTPError as e:
            if e.code != 429 or attempt == tries - 1:
                raise
            time.sleep(2.0 * (attempt + 1))
    raise RuntimeError("unreachable")


def cdn_url(hit: dict, size: int) -> str:
    """The API's signed /get/ links are blocked by Cloudflare from scripts, but the
    public CDN serves the same image at fixed sizes (640 and 1280 work)."""
    return re.sub(r"_150\.(jpg|png)$", r"_%d.\1" % size, hit["previewURL"])


def query(**params) -> dict:
    params["key"] = api_key()
    return json.loads(fetch(API + "?" + urllib.parse.urlencode(params)))


def search(q: str, sheet_path: str) -> None:
    res = query(q=q, image_type="photo", per_page=12, min_width=1600, safesearch="true")
    hits = res.get("hits", [])
    cell = 300
    sheet = Image.new("RGB", (cell * 4, (cell + 22) * 3), (30, 30, 30))
    d = ImageDraw.Draw(sheet)
    for i, h in enumerate(hits[:12]):
        img = Image.open(io.BytesIO(fetch(cdn_url(h, 640)))).convert("RGB")
        img.thumbnail((cell, cell))
        x, y = (i % 4) * cell, (i // 4) * (cell + 22)
        sheet.paste(img, (x, y))
        d.text((x + 4, y + cell + 4), "%d  %dx%d" % (h["id"], h["imageWidth"], h["imageHeight"]), fill=(255, 255, 0))
    sheet.save(sheet_path)
    for h in hits[:12]:
        print(h["id"], "|", h["user"], "|", h["tags"][:80])


def flatten_lighting(a: np.ndarray) -> np.ndarray:
    """Divide out large-scale shading so the tile doesn't show light gradients."""
    img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    low = np.asarray(img.filter(ImageFilter.GaussianBlur(a.shape[0] / 6)), dtype=np.float64) + 1.0
    mean = a.reshape(-1, 3).mean(axis=0)
    return a / low * mean


def make_seamless(a: np.ndarray) -> np.ndarray:
    """Blend with a half-offset copy using a cosine window (edges come from the
    offset copy, whose wrap is continuous). Good for stochastic surfaces."""
    n = a.shape[0]
    rolled = np.roll(np.roll(a, n // 2, axis=0), n // 2, axis=1)
    t = np.linspace(0, np.pi, n)
    w1 = np.sin(t) ** 0.8
    w = np.outer(w1, w1)[..., None]
    return a * w + rolled * (1.0 - w)


def normal_from(a: np.ndarray, strength: float = 2.0) -> np.ndarray:
    h = a.mean(axis=2) / 255.0
    h = np.asarray(Image.fromarray((h * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2)), dtype=np.float64) / 255.0
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * strength
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * strength
    nz = np.ones_like(h)
    n = np.stack([-dx, dy, nz], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return ((n * 0.5 + 0.5) * 255).astype(np.uint8)


def get(img_id: int, name: str, crop=(0.5, 0.5, 0.8), tile=1024, normal_strength=2.0, seamless=True) -> None:
    os.makedirs(OUT, exist_ok=True)
    res = query(id=img_id)
    h = res["hits"][0]
    src = Image.open(io.BytesIO(fetch(cdn_url(h, 1280)))).convert("RGB")
    w, ht = src.size
    side = int(min(w, ht) * crop[2])
    cx, cy = int(w * crop[0]), int(ht * crop[1])
    x0 = max(0, min(w - side, cx - side // 2))
    y0 = max(0, min(ht - side, cy - side // 2))
    sq = src.crop((x0, y0, x0 + side, y0 + side)).resize((tile, tile), Image.LANCZOS)
    a = np.asarray(sq, dtype=np.float64)
    a = flatten_lighting(a)
    if seamless:
        a = make_seamless(a)
    a = np.clip(a, 0, 255).astype(np.uint8)
    Image.fromarray(a).save(os.path.join(OUT, f"{name}_albedo.jpg"), quality=92)
    Image.fromarray(normal_from(a.astype(np.float64), normal_strength)).save(os.path.join(OUT, f"{name}_normal.png"))
    credits_path = os.path.join(OUT, "CREDITS.json")
    credits = json.load(open(credits_path)) if os.path.exists(credits_path) else {}
    credits[name] = {"pixabay_id": h["id"], "author": h["user"], "page": h["pageURL"], "tags": h["tags"],
                     "license": "Pixabay Content License", "source_size": [w, ht], "crop": list(crop)}
    json.dump(credits, open(credits_path, "w"), indent=2)
    print("saved", name, "from", h["pageURL"], "by", h["user"])


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "search":
        search(sys.argv[2], sys.argv[3])
    elif cmd == "get":
        crop = (0.5, 0.5, 0.8)
        strength = 2.0
        seamless = True
        args = sys.argv[4:]
        for i, a in enumerate(args):
            if a == "--crop":
                crop = tuple(float(v) for v in args[i + 1].split(","))
            if a == "--normal":
                strength = float(args[i + 1])
            if a == "--no-seamless":
                seamless = False
        get(int(sys.argv[2]), sys.argv[3], crop, normal_strength=strength, seamless=seamless)
