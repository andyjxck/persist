"""Generates every sound in assets/audio from scratch (pure maths, no samples).

Run:  python3 tool/make_sounds.py
The output is original to this project, so it is free to use anywhere.
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio"


def write(name, samples):
    OUT.mkdir(parents=True, exist_ok=True)
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = 0.9 / peak
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(s * scale * 32767)) for s in samples))


def tone(freq, dur, kind="sine", attack=0.005, decay=None, slide=0.0):
    n = int(RATE * dur)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = freq + slide * (t / dur)
        phase += 2 * math.pi * f / RATE
        if kind == "sine":
            v = math.sin(phase)
        elif kind == "square":
            v = 1.0 if math.sin(phase) >= 0 else -1.0
        elif kind == "saw":
            v = 2 * ((phase / (2 * math.pi)) % 1.0) - 1
        else:
            v = math.sin(phase)
        env = min(1.0, t / attack) if attack > 0 else 1.0
        if decay:
            env *= math.exp(-t / decay)
        else:
            env *= max(0.0, 1 - t / dur)
        out.append(v * env)
    return out


def mix(*tracks):
    n = max(len(t) for t in tracks)
    return [sum(t[i] if i < len(t) else 0 for t in tracks) for i in range(n)]


def concat(*tracks):
    out = []
    for t in tracks:
        out.extend(t)
    return out


def silence(dur):
    return [0.0] * int(RATE * dur)


def noise(dur, decay):
    rnd = random.Random(7)
    n = int(RATE * dur)
    return [rnd.uniform(-1, 1) * math.exp(-(i / RATE) / decay) for i in range(n)]


def place(track, clip, at):
    start = int(at * RATE)
    for i, s in enumerate(clip):
        if start + i < len(track):
            track[start + i] += s


# Short click for every press.
write("tap.wav", tone(1400, 0.04, "square", decay=0.01))

# Two rising blips for a survived round.
write("success.wav", concat(tone(880, 0.06, "square", decay=0.03), tone(1320, 0.09, "square", decay=0.05)))

# Falling buzz for a loss.
write("fail.wav", mix(tone(220, 0.55, "saw", slide=-140), tone(110, 0.55, "square", slide=-60)))

# Glitchy rising sweep for the TRY AGAIN reveal.
write("reveal.wav", concat(noise(0.08, 0.03), tone(300, 0.35, "square", slide=900, decay=0.3)))

# A tense 2-bar loop at 120 bpm (4 seconds): bass pulse, hats, a nagging blip.
beat = 0.5
loop = silence(8 * beat)
bass_notes = [55, 55, 65.4, 55, 49, 49, 58.3, 61.7]
for i, f in enumerate(bass_notes):
    place(loop, [s * 0.9 for s in tone(f, beat * 0.9, "saw", decay=0.25)], i * beat)
for i in range(16):
    place(loop, [s * 0.25 for s in noise(0.05, 0.015)], i * beat / 2 + beat / 4)
for i in (0, 3, 6):
    place(loop, [s * 0.35 for s in tone(880, 0.08, "square", decay=0.04)], i * beat + beat / 2)
write("loop.wav", loop)

print("Wrote sounds to", OUT)
