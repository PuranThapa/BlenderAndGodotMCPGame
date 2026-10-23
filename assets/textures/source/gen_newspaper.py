"""Renders the Daily Herald front page and inner spread as textures.

    python3 assets/textures/source/gen_newspaper.py

Text is rendered with macOS system serif fonts into original artwork (no font
files are shipped). Outputs assets/textures/newspaper_front.png (folded copy)
and newspaper_spread.png (open paper the depot clerk reads).
"""
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
rng = random.Random(7)
PAPER = (232, 228, 214)
INK = (28, 26, 24)
GREY = (95, 92, 86)

WORDS = ("the of and to in council park morning residents street new local school market said will "
         "maple heights community weekend plans road bakery library summer volunteers garden "
         "tuesday report mayor bridge repairs museum festival season rain sunshine traffic bus").split()


def font(name, size, index=0):
    for path in [f"/System/Library/Fonts/{name}", f"/System/Library/Fonts/Supplemental/{name}", f"/Library/Fonts/{name}"]:
        if os.path.exists(path):
            return ImageFont.truetype(path, size, index=index)
    return ImageFont.load_default()


def body_text(d, x0, y0, x1, y1, size=13, leading=16):
    f = font("Times.ttc", size)
    y = y0
    while y < y1 - leading:
        line = ""
        while True:
            w = rng.choice(WORDS)
            trial = (line + " " + w).strip()
            if d.textlength(trial, font=f) > x1 - x0:
                break
            line = trial
        # Paragraph breaks now and then.
        if rng.random() < 0.08:
            line = line[: max(5, len(line) // 2)]
        d.text((x0, y), line, fill=GREY, font=f)
        y += leading


def halftone_photo(img, box, kind):
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    photo = Image.new("L", (w, h), 170)
    pd = ImageDraw.Draw(photo)
    if kind == "park":
        pd.rectangle([0, int(h * 0.62), w, h], fill=120)                          # lawn
        pd.ellipse([int(w * 0.35), int(h * 0.68), int(w * 0.85), int(h * 0.9)], fill=200)  # pond
        for i in range(6):
            cx = int(w * (0.08 + i * 0.17))
            pd.rectangle([cx - 5, int(h * 0.42), cx + 5, int(h * 0.66)], fill=60)
            shade = 70 + (i % 2) * 20
            for ox, oy, r in [(-22, 0.30, 26), (20, 0.28, 28), (0, 0.18, 30), (-8, 0.40, 24), (16, 0.42, 22)]:
                pd.ellipse([cx + ox - r, int(h * oy) - r, cx + ox + r, int(h * oy) + r], fill=shade)
        pd.rectangle([0, 0, w, int(h * 0.18)], fill=210)
    else:
        pd.rectangle([0, int(h * 0.55), w, h], fill=90)
        pd.polygon([(int(w * 0.2), int(h * 0.55)), (int(w * 0.5), int(h * 0.15)), (int(w * 0.8), int(h * 0.55))], fill=60)
        pd.rectangle([int(w * 0.3), int(h * 0.55), int(w * 0.7), int(h * 0.95)], fill=140)
    photo = photo.filter(ImageFilter.GaussianBlur(1.5))
    # Newspaper halftone dots.
    dots = Image.new("RGB", (w, h), PAPER)
    dd = ImageDraw.Draw(dots)
    step = 5
    for yy in range(0, h, step):
        for xx in range(0, w, step):
            v = photo.getpixel((xx, yy)) / 255.0
            r = (1.0 - v) * step * 0.75
            if r > 0.3:
                dd.ellipse([xx - r, yy - r, xx + r, yy + r], fill=INK)
    img.paste(dots, (x0, y0))
    ImageDraw.Draw(img).rectangle(box, outline=INK, width=2)


def newsprint_base(w, h):
    img = Image.new("RGB", (w, h), PAPER)
    px = img.load()
    for _ in range(w * h // 30):
        x, y = rng.randrange(w), rng.randrange(h)
        c = px[x, y]
        k = rng.randint(-10, 6)
        px[x, y] = (c[0] + k, c[1] + k, c[2] + k)
    return img


def front_page():
    W, H = 1024, 724
    img = newsprint_base(W, H)
    d = ImageDraw.Draw(img)
    m = 36
    d.line([(m, 30), (W - m, 30)], fill=INK, width=2)
    mast = font("Times.ttc", 98, index=1)
    title = "The Daily Herald"
    tw = d.textlength(title, font=mast)
    d.text(((W - tw) / 2, 34), title, fill=INK, font=mast)
    d.line([(m, 150), (W - m, 150)], fill=INK, width=3)
    small = font("Times.ttc", 17)
    d.text((m, 156), "MAPLE HEIGHTS EDITION", fill=INK, font=small)
    date = "THURSDAY MORNING"
    d.text(((W - d.textlength(date, font=small)) / 2, 156), date, fill=INK, font=small)
    price = "25 CENTS"
    d.text((W - m - d.textlength(price, font=small), 156), price, fill=INK, font=small)
    d.line([(m, 182), (W - m, 182)], fill=INK, width=1)
    head = font("Times.ttc", 54, index=1)
    d.text((m, 192), "PARK POND REOPENS FOR SUMMER", fill=INK, font=head)
    sub = font("Times.ttc", 24, index=2)
    d.text((m, 254), "Residents return to Maple Heights park after spring repairs", fill=GREY, font=sub)
    halftone_photo(img, (m, 292, 600, 560), "park")
    cap = font("Times.ttc", 14, index=2)
    d.text((m, 566), "Families gather by the pond on Wednesday morning.", fill=GREY, font=cap)
    body_text(d, m, 590, 600, H - 20)
    # Right-hand column stories.
    d.line([(620, 292), (620, H - 20)], fill=INK, width=1)
    sh = font("Times.ttc", 26, index=1)
    d.text((636, 292), "New bus stop on Main Road", fill=INK, font=sh)
    body_text(d, 636, 330, W - m, 470)
    d.line([(636, 478), (W - m, 478)], fill=INK, width=1)
    d.text((636, 486), "Roadworks on Maple St.", fill=INK, font=sh)
    body_text(d, 636, 524, W - m, H - 20)
    img.save(os.path.join(OUT, "newspaper_front.png"))


def spread():
    W, H = 1448, 1024
    img = newsprint_base(W, H)
    d = ImageDraw.Draw(img)
    for page in range(2):
        x0 = page * W // 2 + 40
        x1 = (page + 1) * W // 2 - 40
        hf = font("Times.ttc", 40, index=1)
        d.text((x0, 30), ["LOCAL NEWS", "SPORTS & WEATHER"][page], fill=INK, font=hf)
        d.line([(x0, 82), (x1, 82)], fill=INK, width=2)
        if page == 0:
            halftone_photo(img, (x0, 100, x0 + 330, 330), "house")
            body_text(d, x0 + 350, 100, x1, 330)
        else:
            sh = font("Times.ttc", 30, index=1)
            d.text((x0, 100), "Sunny morning, light breeze", fill=INK, font=sh)
            body_text(d, x0, 145, x1, 330)
        cols = 3
        cw = (x1 - x0 - 20 * (cols - 1)) / cols
        for c in range(cols):
            cx = x0 + c * (cw + 20)
            sh = font("Times.ttc", 22, index=1)
            d.text((cx, 350), rng.choice(["Market day", "School fair", "Library news", "Bakery wins prize", "Garden club", "Cycling safety"]), fill=INK, font=sh)
            body_text(d, cx, 385, cx + cw, H - 30, 12, 15)
    d.line([(W // 2, 20), (W // 2, H - 20)], fill=(200, 196, 182), width=3)   # fold
    img.save(os.path.join(OUT, "newspaper_spread.png"))


if __name__ == "__main__":
    front_page()
    spread()
    print("NEWSPAPER_TEXTURES_OK")
