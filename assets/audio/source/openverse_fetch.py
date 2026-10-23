"""Openverse sound sourcing for Paper Boy (https://api.openverse.org, no key needed).

    python3 openverse_fetch.py search "dog bark" [shortest|short|medium]
        -> lists candidates (commercial use + modification allowed only)
    python3 openverse_fetch.py get <id> <name> [--start s] [--dur s] [--loop] [--gain dB]
                                         [--thresh dB] [--maxdur s]
        -> assets/audio/openverse/<name>.wav  (mono 44.1 kHz, trimmed, levelled;
           --loop makes it seamless), a waveform+spectrogram PNG in
           assets/audio/openverse/check/, and credits in CREDITS.json

Only CC0 / PDM / CC-BY / CC-BY-SA results are returned (license_type=
commercial,modification), so every sound may be used and edited in the game.
Attribution for BY/BY-SA is recorded in CREDITS.json and the asset manifest.
"""
import json
import os
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
import wave

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(os.path.join(HERE, "..", "openverse"))
API = "https://api.openverse.org/v1/audio/"
UA = "PaperBoyGame-AssetTool/1.0 (local game development)"
SR = 44100


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=90) as r:
        return r.read()


def search(q: str, length: str = "shortest", n: int = 20) -> list:
    params = {"q": q, "license_type": "commercial,modification", "page_size": n}
    if length:
        params["length"] = length
    d = json.loads(fetch(API + "?" + urllib.parse.urlencode(params)))
    rows = d.get("results", [])
    for r in rows:
        print("%s | %-38s | %-6s %-4s | %-9s | %6.1fs | %s" % (r["id"], r["title"][:38], r["license"], r.get("license_version") or "",
              r.get("source"), (r.get("duration") or 0) / 1000.0, r["creator"][:22]))
    return rows


def decode(path: str) -> np.ndarray:
    """Any format -> mono float32 at 44.1 kHz via ffmpeg."""
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def trim_silence(x: np.ndarray, thresh_db: float = -45.0, pad: float = 0.02) -> np.ndarray:
    win = int(SR * 0.01)
    if len(x) < win * 3:
        return x
    env = np.sqrt(np.convolve(x ** 2, np.ones(win) / win, mode="same"))
    peak = env.max() or 1.0
    loud = np.where(20 * np.log10(env / peak + 1e-9) > thresh_db)[0]
    if len(loud) == 0:
        return x
    a = max(0, loud[0] - int(SR * pad))
    b = min(len(x), loud[-1] + int(SR * pad))
    return x[a:b]


def loopify(x: np.ndarray, fade: float = 0.4) -> np.ndarray:
    f = min(int(SR * fade), len(x) // 4)
    ramp = np.linspace(0, 1, f)
    return np.concatenate([x[-f:] * (1 - ramp) + x[:f] * ramp, x[f:-f]])


def write_wav(path: str, x: np.ndarray) -> None:
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def check_image(path: str, x: np.ndarray, title: str) -> None:
    """Waveform (top) + spectrogram 0-11 kHz (bottom) for visual inspection."""
    W, H = 900, 360
    img = Image.new("RGB", (W, H), (18, 18, 22))
    d = ImageDraw.Draw(img)
    mid = 70
    n = len(x)
    for px in range(W):
        seg = x[int(px / W * n):int((px + 1) / W * n) + 1]
        if len(seg):
            d.line([(px, mid - seg.max() * 60), (px, mid - seg.min() * 60)], fill=(120, 200, 255))
    hop = max(1, (n - 1024) // W)
    cols = []
    for i in range(W):
        s = x[i * hop:i * hop + 1024]
        if len(s) < 1024:
            s = np.pad(s, (0, 1024 - len(s)))
        cols.append(np.abs(np.fft.rfft(s * np.hanning(1024)))[:256])
    S = 20 * np.log10(np.array(cols).T + 1e-7)
    S = np.clip((S - S.max() + 70) / 70, 0, 1)[::-1]
    spec = Image.fromarray((np.stack([S ** 0.8, S ** 1.8 * 0.85, (1 - S) * 0.25 + S ** 3], -1) * 255).astype(np.uint8)).resize((W, H - 150))
    img.paste(spec, (0, 150))
    d.text((6, 4), title, fill=(255, 255, 0))
    d.text((6, 134), "%.2fs  peak %.2f  rms %.3f" % (n / SR, np.abs(x).max(), np.sqrt(np.mean(x ** 2))), fill=(220, 220, 220))
    img.save(path)


def get(oid: str, name: str, start: float = 0.0, dur: float = 0.0, loop: bool = False, gain_db: float = 0.0,
        thresh_db: float = -45.0, max_dur: float = 0.0) -> None:
    os.makedirs(os.path.join(OUT, "check"), exist_ok=True)
    meta = json.loads(fetch(API + oid + "/"))
    url = meta["url"]
    with tempfile.NamedTemporaryFile(suffix="." + (meta.get("filetype") or "mp3"), delete=False) as tf:
        tf.write(fetch(url))
        src = tf.name
    try:
        x = decode(src)
    finally:
        os.unlink(src)
    if start or dur:
        x = x[int(start * SR):int((start + dur) * SR) if dur else None]
    if not loop:
        x = trim_silence(x, thresh_db)
        if max_dur:
            x = x[:int(max_dur * SR)]
    x = x - x.mean()
    peak = np.abs(x).max() or 1.0
    x = x / peak * 0.89 * (10 ** (gain_db / 20))           # ~ -1 dBFS peak
    fl = min(int(SR * 0.005), len(x) // 4)
    if not loop:
        x[:fl] *= np.linspace(0, 1, fl)
        x[-fl * 4:] *= np.linspace(1, 0, fl * 4)
    else:
        x = loopify(x)
    out = os.path.join(OUT, name + ".wav")
    write_wav(out, x)
    check_image(os.path.join(OUT, "check", name + ".png"), x, "%s  <-  %s (%s)" % (name, meta["title"][:50], meta["creator"][:24]))
    credits_path = os.path.join(OUT, "CREDITS.json")
    credits = json.load(open(credits_path)) if os.path.exists(credits_path) else {}
    credits[name] = {
        "title": meta["title"], "creator": meta["creator"], "creator_url": meta.get("creator_url"),
        "license": "%s %s" % (meta["license"].upper(), meta.get("license_version") or ""), "license_url": meta.get("license_url"),
        "source": meta.get("source"), "page": meta.get("foreign_landing_url"), "openverse_id": oid,
        "edits": "mono 44.1 kHz, trimmed%s, levelled%s" % (" %.1f-%.1fs" % (start, start + dur) if (start or dur) else "", ", looped" if loop else ""),
    }
    json.dump(credits, open(credits_path, "w"), indent=2)
    print("saved %s (%.2fs) <- %s by %s [%s]" % (name, len(x) / SR, meta["title"], meta["creator"], credits[name]["license"]))


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "search":
        search(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "shortest")
    elif cmd == "get":
        a = sys.argv[4:]
        opt = lambda k, d: float(a[a.index(k) + 1]) if k in a else d
        get(sys.argv[2], sys.argv[3], opt("--start", 0.0), opt("--dur", 0.0), "--loop" in a, opt("--gain", 0.0),
            opt("--thresh", -45.0), opt("--maxdur", 0.0))
