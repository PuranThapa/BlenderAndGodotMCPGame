"""Synthesizes every sound effect in the game (original work, CC0; no samples).

    python3 assets/audio/source/gen_audio.py

Writes 16-bit mono 44.1 kHz WAVs to assets/audio/. Loops are made seamless by
crossfading the tail into the head; Godot sets loop points at runtime.
"""
import os
import wave

import numpy as np

SR = 44100
OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
rng = np.random.default_rng(20261023)


def t_axis(sec):
    return np.arange(int(SR * sec)) / SR


def write(name, x, peak=0.8):
    x = np.asarray(x, dtype=np.float64)
    m = np.max(np.abs(x)) or 1.0
    x = x / m * peak
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("wrote", name, "%.2fs" % (len(x) / SR), "rms=%.3f" % float(np.sqrt(np.mean(x ** 2))))


def biquad(x, kind, f0, q):
    """RBJ biquad (lowpass/highpass/bandpass), f0 may be an array (time-varying)."""
    f0 = np.broadcast_to(np.asarray(f0, dtype=np.float64), x.shape)
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i in range(len(x)):
        w0 = 2 * np.pi * f0[i] / SR
        a = np.sin(w0) / (2 * q)
        c = np.cos(w0)
        if kind == "lp":
            b0, b1, b2 = (1 - c) / 2, 1 - c, (1 - c) / 2
        elif kind == "hp":
            b0, b1, b2 = (1 + c) / 2, -(1 + c), (1 + c) / 2
        else:
            b0, b1, b2 = a, 0.0, -a
        a0, a1, a2 = 1 + a, -2 * c, 1 - a
        yi = (b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
        x2, x1, y2, y1 = x1, x[i], y1, yi
        y[i] = yi
    return y


def lp1(x, alpha):
    """Cheap one-pole low-pass (vectorised via cumulative filter)."""
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += alpha * (v - acc)
        y[i] = acc
    return y


def loopify(x, fade_sec=0.25):
    """Crossfade the last `fade` into the first so the loop is seamless."""
    f = int(SR * fade_sec)
    head, body, tail = x[:f], x[f:-f], x[-f:]
    ramp = np.linspace(0, 1, f)
    return np.concatenate([tail * (1 - ramp) + head * ramp, body])


def env(t, attack, decay):
    return np.minimum(t / max(attack, 1e-4), 1.0) * np.exp(-t * decay)


def noise(sec):
    return rng.standard_normal(int(SR * sec))


def bell_strike(t, base, decay_scale=1.0):
    partials = [(1.0, 1.0, 2.2), (2.76, 0.5, 3.5), (5.40, 0.25, 6.0), (8.93, 0.12, 9.0)]
    return sum(a * np.sin(2 * np.pi * base * r * t) * np.exp(-t * d * decay_scale) for r, a, d in partials)


# ------------------------------------------------------------------ bike
def bike_bell():
    t = t_axis(1.6)
    x = bell_strike(t, 2150) * np.minimum(t / 0.002, 1)
    s2 = int(0.17 * SR)
    x[s2:] += 0.9 * bell_strike(t[: len(t) - s2], 2150) * np.minimum(t[: len(t) - s2] / 0.002, 1)
    write("bell.wav", x, 0.7)


def roll_loop():
    n = noise(2.5)
    x = lp1(n, 0.04) * 0.7 + biquad(n, "bp", 220, 0.7) * 0.3
    write("roll_loop.wav", loopify(x), 0.6)


def freewheel_loop():
    t = t_axis(1.0)
    x = np.zeros_like(t)
    rate = 24
    for k in range(rate):
        start = int(k / rate * SR)
        tt = t[: int(0.012 * SR)]
        click = np.sin(2 * np.pi * 3200 * tt) * np.exp(-tt * 600) + 0.4 * np.sin(2 * np.pi * 5100 * tt) * np.exp(-tt * 900)
        x[start:start + len(tt)] += click * (0.8 + 0.2 * rng.random())
    write("freewheel_loop.wav", x, 0.5)


def chain_loop():
    t = t_axis(1.0)
    n = biquad(noise(1.0), "bp", 1800, 1.2)
    x = n * (0.4 + 0.6 * np.abs(np.sin(np.pi * 2 * t))) * 0.5
    for k in range(8):
        start = int(k / 8 * SR)
        tt = t[: int(0.02 * SR)]
        x[start:start + len(tt)] += 0.3 * np.sin(2 * np.pi * 900 * tt) * np.exp(-tt * 300)
    write("chain_loop.wav", x, 0.45)


def brake_squeal():
    t = t_axis(0.7)
    vib = 1 + 0.01 * np.sin(2 * np.pi * 7 * t)
    tone = np.sin(2 * np.pi * np.cumsum(2900 * vib) / SR) + 0.3 * np.sin(2 * np.pi * np.cumsum(5800 * vib) / SR)
    x = (tone * 0.6 + biquad(noise(0.7), "hp", 2000, 0.7) * 0.2) * env(t, 0.03, 3.5)
    write("brake.wav", x, 0.4)


def thud():
    t = t_axis(0.5)
    x = np.sin(2 * np.pi * 70 * t * (1 - 0.3 * t)) * np.exp(-t * 9) + lp1(noise(0.5), 0.1) * np.exp(-t * 25) * 0.8
    write("thud.wav", x, 0.8)


def clatter():
    """Crash: thud plus metallic rattles."""
    t = t_axis(0.9)
    x = np.sin(2 * np.pi * 60 * t) * np.exp(-t * 8)
    for k in range(7):
        s = int(rng.uniform(0.0, 0.5) * SR)
        tt = t[: len(t) - s]
        f = rng.uniform(1500, 4500)
        x[s:] += 0.35 * np.sin(2 * np.pi * f * tt) * np.exp(-tt * rng.uniform(25, 60))
    x += biquad(noise(0.9), "bp", 2500, 0.8) * np.exp(-t * 12) * 0.4
    write("crash.wav", x, 0.85)


# ------------------------------------------------------------------ delivery / UI
def whoosh():
    t = t_axis(0.45)
    fc = 400 + 3000 * np.sin(np.pi * t / 0.45)
    x = biquad(noise(0.45), "bp", fc, 1.0) * np.sin(np.pi * t / 0.45) ** 2
    write("whoosh.wav", x, 0.5)


def paper_slap():
    t = t_axis(0.25)
    x = biquad(noise(0.25), "bp", 1200, 0.9) * np.exp(-t * 40) + 0.5 * np.sin(2 * np.pi * 140 * t) * np.exp(-t * 30)
    write("paper_land.wav", x, 0.6)


def notes(seq, note_len, decay, partial=2.0):
    total = note_len * len(seq) + 0.8
    t = t_axis(total)
    x = np.zeros_like(t)
    for i, f in enumerate(seq):
        s = int(i * note_len * SR)
        tt = t[: len(t) - s]
        x[s:] += (np.sin(2 * np.pi * f * tt) + 0.3 * np.sin(2 * np.pi * f * partial * tt)) * env(tt, 0.005, decay)
    return x


def ui_sounds():
    write("chime_good.wav", notes([1046.5, 1318.5], 0.11, 5.0), 0.5)
    write("fanfare.wav", notes([523.3, 659.3, 784.0, 1046.5], 0.13, 3.0), 0.55)
    t = t_axis(0.35)
    sq = np.sign(np.sin(2 * np.pi * 170 * t)) * 0.5 + np.sin(2 * np.pi * 170 * t)
    write("buzz_bad.wav", lp1(sq, 0.2) * env(t, 0.005, 9), 0.4)
    t = t_axis(0.06)
    write("click.wav", np.sin(2 * np.pi * 1800 * t) * np.exp(-t * 90), 0.35)


# ------------------------------------------------------------------ traffic
def engine_loop():
    t = t_axis(1.0)
    f0 = 45.0
    x = sum(a * np.sin(2 * np.pi * f0 * h * t + p) for h, a, p in [(1, 1.0, 0), (2, 0.6, 1), (3, 0.45, 2), (4, 0.3, 0.5), (6, 0.15, 1.3)])
    x = x * (1 + 0.15 * np.sin(2 * np.pi * 4 * t))
    x += loopify(lp1(noise(1.5), 0.05), 0.25)[: len(t)] * 0.6
    write("engine_loop.wav", x, 0.55)


def horn():
    t = t_axis(0.55)
    tone = np.zeros_like(t)
    for s, e in [(0.0, 0.18), (0.26, 0.5)]:
        m = (t >= s) & (t < e)
        tt = t[m] - s
        tone[m] = (np.sign(np.sin(2 * np.pi * 410 * tt)) + np.sign(np.sin(2 * np.pi * 515 * tt))) * np.minimum(tt / 0.01, 1) * np.minimum((e - s - tt) / 0.02, 1)
    write("horn.wav", lp1(tone, 0.25), 0.45)


# ------------------------------------------------------------------ animals
def bark():
    t = t_axis(0.32)
    f = 520 * np.exp(-t * 2.2)
    phase = 2 * np.pi * np.cumsum(f) / SR
    saw = sum(np.sin(k * phase) / k for k in range(1, 18))
    voiced = biquad(saw, "bp", 950, 1.6) + 0.5 * biquad(saw, "bp", 2300, 2.0)
    x = voiced * env(t, 0.008, 14) + biquad(noise(0.32), "bp", 1500, 1.0) * np.exp(-t * 60) * 0.6
    write("bark.wav", x, 0.75)


def meow():
    t = t_axis(0.75)
    shape = np.sin(np.pi * t / 0.75)
    f = 520 + 380 * shape
    phase = 2 * np.pi * np.cumsum(f) / SR
    saw = sum(np.sin(k * phase) / k for k in range(1, 14))
    formant = 700 + 1300 * shape
    x = biquad(saw, "bp", formant, 2.2) * shape ** 0.6
    write("meow.wav", x, 0.6)


def splash():
    t = t_axis(0.55)
    x = biquad(noise(0.55), "hp", 1500, 0.7) * env(t, 0.005, 9) * 0.7
    for k in range(10):
        s = int(rng.uniform(0.02, 0.4) * SR)
        tt = t[: int(0.03 * SR)]
        f = rng.uniform(900, 2600)
        x[s:s + len(tt)] += 0.4 * np.sin(2 * np.pi * f * (1 + 2 * tt) * tt) * np.exp(-tt * 120)
    write("splash.wav", x, 0.6)


# ------------------------------------------------------------------ ambience
def birds_loop():
    sec = 14.0
    t = t_axis(sec)
    x = np.zeros_like(t)
    # A few "species": (base Hz, sweep Hz, length s, notes in a phrase)
    species = [(3800, 1400, 0.09, 3), (5200, -1800, 0.06, 5), (2900, 900, 0.18, 2), (4400, 600, 0.04, 8)]
    when = 0.4
    while when < sec - 1.5:
        base, sweep, ln, count = species[rng.integers(len(species))]
        gap = ln * rng.uniform(1.2, 1.8)
        amp = rng.uniform(0.25, 1.0)
        for k in range(count):
            s = int((when + k * gap) * SR)
            tt = t[: int(ln * SR)]
            f = base + sweep * (tt / ln) + 150 * np.sin(2 * np.pi * 35 * tt)
            ch = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * tt / ln) ** 2
            x[s:s + len(tt)] += ch * amp
        when += count * gap + rng.uniform(0.6, 2.2)
    write("birds_loop.wav", loopify(x, 0.4), 0.35)


def city_loop():
    sec = 10.0
    t = t_axis(sec)
    b = lp1(noise(sec), 0.008) * 6
    hum = 0.15 * np.sin(2 * np.pi * 60 * t) + 0.1 * np.sin(2 * np.pi * 120 * t)
    swell = 0.7 + 0.3 * np.sin(2 * np.pi * t / sec)
    write("city_loop.wav", loopify((b + hum) * swell, 0.5), 0.3)


def wind_loop():
    sec = 9.0
    t = t_axis(sec)
    fc = 500 + 300 * np.sin(2 * np.pi * t / sec * 2) + 150 * np.sin(2 * np.pi * t / sec * 5)
    x = biquad(noise(sec), "bp", fc, 0.8) * (0.6 + 0.4 * np.sin(2 * np.pi * t / sec * 3) ** 2)
    write("wind_loop.wav", loopify(x, 0.5), 0.25)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for fn in [bike_bell, roll_loop, freewheel_loop, chain_loop, brake_squeal, thud, clatter, whoosh, paper_slap, ui_sounds,
               engine_loop, horn, bark, meow, splash, birds_loop, city_loop, wind_loop]:
        fn()
