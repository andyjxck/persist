"""Synthesises every sound in assets/audio from scratch (maths only, no samples).

Run:  python3 tool/make_sounds.py      (needs numpy)

The set is dry and mechanical: a clock escapement (tick / tock, plus tighter
versions for the last moments), a short dry press click, a two-part latch
when a round is cleared, and a dead low thud when you fail. No tones, no
chords, no reverb. Mono 22.05 kHz 16-bit, so every file is a few KB.
"""
import wave
from pathlib import Path

import numpy as np

RATE = 22050
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio"
rng = np.random.default_rng(11)


def n_of(dur):
    return int(RATE * dur)


def t_axis(n):
    return np.arange(n) / RATE


def decay(n, t60):
    """Instant attack, exponential fall to -60 dB after t60 seconds."""
    return np.exp(-6.9 * t_axis(n) / t60)


def resonator(x, freq, q):
    """Two-pole band-pass (a struck metal or wooden part ringing)."""
    w = 2 * np.pi * freq / RATE
    r = np.exp(-w / (2 * q))
    a1, a2 = -2 * r * np.cos(w), r * r
    y = np.zeros_like(x)
    y1 = y2 = 0.0
    for i, v in enumerate(x):
        y0 = (1 - r) * v - a1 * y1 - a2 * y2
        y[i] = y0
        y2, y1 = y1, y0
    return y


def impulse(n, width=0.0012):
    """A very short noise burst: the moment two hard parts hit."""
    x = np.zeros(n)
    k = max(2, n_of(width))
    x[:k] = rng.standard_normal(k) * np.linspace(1, 0, k)
    return x


def click(dur, parts, body=None, t60=0.02, contact=0.25):
    """A dry mechanical click: an impulse exciting a few resonances.

    parts: list of (freq, q, gain). body: optional (freq, gain, t60) for a
    low knock under the click."""
    n = n_of(dur)
    x = impulse(n)
    y = np.zeros(n)
    for f, q, g in parts:
        y += g * resonator(x, f, q)
    y *= decay(n, t60)
    y += contact * x  # the raw contact itself
    if body:
        f, g, bt = body
        t = t_axis(n)
        y += g * np.sin(2 * np.pi * f * t) * decay(n, bt)
    return y


def finish(y, peak):
    y = y - np.mean(y)
    m = np.max(np.abs(y)) or 1
    y = y / m * peak
    # 2 ms fade-out so nothing ends on a pop.
    k = min(len(y), n_of(0.002))
    y[-k:] *= np.linspace(1, 0, k)
    return y


def save(name, y):
    OUT.mkdir(parents=True, exist_ok=True)
    pcm = (np.clip(y, -1, 1) * 32767).astype("<i2")
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    print(f"{name:16s} {len(y) / RATE * 1000:5.0f} ms  {(OUT / name).stat().st_size:6d} bytes")


# --- The clock --------------------------------------------------------------
# Tick: the higher, brighter half of the escapement. Tock: lower, woodier.
# The tight versions are shorter and harder, for the last moments.

tick = click(0.07, [(3400, 18, 1.0), (5100, 22, 0.5), (1900, 10, 0.35)], body=(420, 0.05, 0.012), t60=0.03)
tock = click(0.08, [(1650, 14, 1.0), (2600, 16, 0.45), (900, 8, 0.4)], body=(260, 0.08, 0.016), t60=0.038, contact=0.06)
tick_t = click(0.04, [(4200, 12, 1.0), (6200, 14, 0.4)], t60=0.012)
tock_t = click(0.045, [(2300, 10, 1.0), (3600, 12, 0.4)], body=(300, 0.05, 0.008), t60=0.014, contact=0.08)

save("tick.wav", finish(tick, 0.8))
save("tock.wav", finish(tock, 0.8))
save("tick_tight.wav", finish(tick_t, 0.85))
save("tock_tight.wav", finish(tock_t, 0.85))

# --- Press: short, dry, close ------------------------------------------------
press = click(0.045, [(2400, 6, 1.0), (1200, 5, 0.6)], body=(150, 0.25, 0.012), t60=0.012, contact=0.08)
save("press.wav", finish(press, 0.7))

# --- Cleared: a latch, two parts settling ("k-chk"), quiet ---------------------
n = n_of(0.09)
latch = np.zeros(n)
a = click(0.05, [(2900, 10, 1.0), (1500, 8, 0.5)], t60=0.015)
b = click(0.05, [(2100, 10, 1.0), (1100, 8, 0.6)], body=(200, 0.15, 0.01), t60=0.02)
latch[: len(a)] += 0.55 * a
off = n_of(0.032)
latch[off: off + len(b)] += b[: n - off]
save("clear.wav", finish(latch, 0.6))

# --- Fail: a dead low thud, then nothing ---------------------------------------
n = n_of(0.42)
t = t_axis(n)
f = 38 + 52 * np.exp(-t / 0.035)  # pitch falls fast: a heavy thing landing
thud = np.sin(2 * np.pi * np.cumsum(f) / RATE) * decay(n, 0.34)
knock = resonator(impulse(n, 0.004), 140, 2.5) * decay(n, 0.06) * 6
contact = click(0.42, [(900, 4, 1.0)], t60=0.02)
save("fail.wav", finish(thud + knock + 0.2 * contact, 0.95))

# --- Reveal (the surprise TRY AGAIN): a hard relay snap, the clock restarts ----
n = n_of(0.16)
snap = np.zeros(n)
r1 = click(0.06, [(1800, 5, 1.0), (4000, 9, 0.6)], body=(120, 0.4, 0.03), t60=0.02)
snap[: len(r1)] += r1
snap[n_of(0.09): n_of(0.09) + len(tick_t)] += 0.7 * tick_t[: n - n_of(0.09)]
save("reveal.wav", finish(snap, 0.9))

# --- Glitch (the lights cut out, buttons jump): a burst of crackling static ---
n = n_of(0.12)
t = t_axis(n)
noise = rng.standard_normal(n)
gate = (np.sin(2 * np.pi * 55 * t) > 0.2).astype(float)  # stuttering on/off
crackle = resonator(noise, 2600, 1.2) * gate + 0.3 * resonator(noise, 700, 1.5)
save("glitch.wav", finish(crackle * decay(n, 0.11), 0.7))

# --- Buzz (HURRY): a short, ugly two-tone square buzzer --------------------------
n = n_of(0.2)
t = t_axis(n)
sq = np.sign(np.sin(2 * np.pi * 180 * t)) * 0.6 + np.sign(np.sin(2 * np.pi * 247 * t)) * 0.4
env = np.minimum(1, t / 0.004) * np.minimum(1, (0.2 - t) / 0.03)
save("buzz.wav", finish(resonator(sq, 900, 0.8) * env + 0.25 * sq * env, 0.55))
