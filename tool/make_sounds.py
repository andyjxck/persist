"""Synthesises every sound in assets/audio from scratch (maths only, no samples).

Run:  python3 tool/make_sounds.py      (needs numpy)

The set is designed as one family: everything is tuned to A minor, shares the
same small 'room' reverb, and is level-matched (RMS target per role, then a
soft limiter so nothing clips). Output is original to this project.
"""
import wave
from pathlib import Path

import numpy as np

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio"
rng = np.random.default_rng(7)


# ----------------------------------------------------------------------------
# Building blocks
# ----------------------------------------------------------------------------

def t_axis(dur):
    return np.arange(int(RATE * dur)) / RATE


def note(name):
    names = {"C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4, "F#": -3,
             "G": -2, "G#": -1, "A": 0, "A#": 1, "B": 2}
    pitch, octave = name[:-1], int(name[-1])
    return 440.0 * 2 ** ((names[pitch] + 12 * (octave - 4)) / 12)


def env(n, attack=0.003, decay=0.2, curve=1.0):
    """Fast linear attack, exponential decay (decay = time to -60 dB)."""
    t = np.arange(n) / RATE
    a = np.clip(t / max(attack, 1e-5), 0, 1)
    d = np.exp(-6.9 * np.maximum(t - attack, 0) / max(decay, 1e-4)) ** curve
    return a * d


def osc(freq, dur, kind="sine", phase=0.0):
    t = t_axis(dur)
    if np.isscalar(freq):
        ph = 2 * np.pi * freq * t + phase
    else:
        ph = 2 * np.pi * np.cumsum(freq) / RATE + phase
    if kind == "sine":
        return np.sin(ph)
    if kind == "tri":
        return 2 / np.pi * np.arcsin(np.sin(ph))
    if kind == "saw":  # band-limited-ish: sum of harmonics
        out = np.zeros_like(t)
        f0 = freq if np.isscalar(freq) else float(np.mean(freq))
        for k in range(1, int(min(40, 16000 / max(f0, 20)))):
            out += np.sin(k * ph) / k
        return out * 0.6
    if kind == "square":
        out = np.zeros_like(t)
        f0 = freq if np.isscalar(freq) else float(np.mean(freq))
        for k in range(1, int(min(40, 16000 / max(f0, 20))), 2):
            out += np.sin(k * ph) / k
        return out * 0.8
    raise ValueError(kind)


def glide(f0, f1, dur, curve=4.0):
    t = t_axis(dur) / dur
    return f1 + (f0 - f1) * np.exp(-curve * t)


def noise(dur):
    return rng.uniform(-1, 1, int(RATE * dur))


def biquad(x, kind, freq, q=0.707):
    """RBJ biquad. freq may be a scalar or a per-sample array (swept filter)."""
    n = len(x)
    f = np.full(n, float(freq)) if np.isscalar(freq) else np.asarray(freq, float)
    y = np.zeros(n)
    x1 = x2 = y1 = y2 = 0.0
    step = 32  # recompute coefficients every 32 samples
    for start in range(0, n, step):
        w = 2 * np.pi * min(f[start], RATE * 0.45) / RATE
        cw, sw = np.cos(w), np.sin(w)
        alpha = sw / (2 * q)
        if kind == "lp":
            b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2
        elif kind == "hp":
            b0, b1, b2 = (1 + cw) / 2, -(1 + cw), (1 + cw) / 2
        else:  # band-pass, constant peak gain
            b0, b1, b2 = alpha, 0.0, -alpha
        a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
        b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
        for i in range(start, min(start + step, n)):
            xi = x[i]
            yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2, x1, y2, y1 = x1, xi, y1, yi
            y[i] = yi
    return y


def room(x, size=0.35, mix=0.18, tone=6000):
    """Shared small-room reverb: convolution with a decaying noise burst."""
    ir_len = int(RATE * size * 2)
    t = np.arange(ir_len) / RATE
    ir = rng.standard_normal(ir_len) * np.exp(-6.9 * t / size)
    ir = biquad(ir, "lp", tone)
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    n = len(x) + ir_len
    size_fft = 1 << (n - 1).bit_length()
    wet = np.fft.irfft(np.fft.rfft(x, size_fft) * np.fft.rfft(ir, size_fft), size_fft)[:n]
    dry = np.concatenate([x, np.zeros(ir_len)])
    return dry * (1 - mix) + wet * mix * 1.4


def pad_to(x, n):
    return np.concatenate([x, np.zeros(max(0, n - len(x)))])[:n]


def mix_at(base, sig, at):
    i = int(at * RATE)
    end = min(len(base), i + len(sig))
    base[i:end] += sig[: end - i]
    return base


def trim_silence(x, thresh=1e-4):
    idx = np.where(np.abs(x) > thresh)[0]
    return x[: idx[-1] + 1] if len(idx) else x


def finish(x, rms_target, fade=0.01):
    """Level-match: scale to an RMS target (measured over the loud part),
    then soft-limit to -1 dBFS and add a short fade-out."""
    x = trim_silence(x)
    loud = x[np.abs(x) > np.max(np.abs(x)) * 0.05]
    rms = np.sqrt(np.mean(loud ** 2)) if len(loud) else 1
    x = x * (rms_target / max(rms, 1e-9))
    ceiling = 10 ** (-1 / 20)
    x = np.tanh(x / ceiling) * ceiling
    nf = min(len(x), int(RATE * fade))
    x[-nf:] *= np.linspace(1, 0, nf)
    return x


def write(name, x):
    OUT.mkdir(parents=True, exist_ok=True)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())
    print(f"{name:12s} {len(x) / RATE:5.2f}s  peak {20 * np.log10(np.max(np.abs(x)) + 1e-9):5.1f} dBFS")


def bell(freq, dur, index=2.2, ratio=3.5, decay=None):
    """FM bell / glassy pluck."""
    t = t_axis(dur)
    decay = decay or dur
    mod_env = np.exp(-t * 18)
    mod = np.sin(2 * np.pi * freq * ratio * t) * index * mod_env
    return np.sin(2 * np.pi * freq * t + mod) * env(len(t), 0.002, decay)


# ----------------------------------------------------------------------------
# Sound effects
# ----------------------------------------------------------------------------

def make_tap():
    # A soft, rubbery arcade 'thock': pitched body + tiny click + low knock.
    d = 0.16
    body = osc(glide(340, 150, d, 30), d) * env(int(RATE * d), 0.001, 0.09)
    knock = osc(glide(110, 70, d, 10), d) * env(int(RATE * d), 0.002, 0.07) * 0.8
    click = biquad(noise(d), "bp", 3800, 1.2) * env(int(RATE * d), 0.0005, 0.012) * 1.6
    x = body + knock + click
    return finish(room(x, 0.18, 0.08), 0.20)


def make_success():
    # Bright rising A-major-add9 sparkle: A5 C#6 E6 B6, quick strum, glassy FM.
    d = 0.9
    x = np.zeros(int(RATE * d))
    for i, n in enumerate(["A5", "C#6", "E6", "B6"]):
        f = note(n)
        tone = bell(f, d - i * 0.045, index=1.4, ratio=2.0, decay=0.55) * (0.9 - i * 0.08)
        tone += osc(f * 2, d - i * 0.045) * env(int(RATE * (d - i * 0.045)), 0.002, 0.25) * 0.15
        mix_at(x, tone, i * 0.045)
    sparkle = biquad(noise(d), "hp", 7000) * env(len(x), 0.004, 0.18) * 0.12
    thump = osc(glide(220, 110, 0.12, 12), 0.12) * env(int(RATE * 0.12), 0.001, 0.08) * 0.5
    x += sparkle
    mix_at(x, thump, 0)
    return finish(room(x, 0.5, 0.22), 0.17)


def make_fail():
    # A heavy deflating 'bwomp': detuned saws diving A2 -> A1 through a closing
    # filter, a sub thud and a crunchy noise hit.
    d = 0.9
    n = int(RATE * d)
    f = glide(note("A2"), note("A1") * 0.9, d, 3)
    saws = osc(f, d, "saw") + osc(f * 1.012, d, "saw") + osc(f * 0.5, d, "square") * 0.5
    saws = biquad(saws, "lp", glide(2600, 180, d, 4), 2.0)
    saws = np.tanh(saws * 1.8) * env(n, 0.004, 0.75)
    sub = osc(glide(90, 38, d, 6), d) * env(n, 0.002, 0.45) * 1.1
    crunch = biquad(noise(d), "bp", glide(1800, 400, d, 8), 0.9) * env(n, 0.001, 0.12) * 1.2
    x = saws * 0.8 + sub + crunch
    return finish(room(x, 0.45, 0.16), 0.30)


def make_reveal():
    # Tension sting: a reversed swell rushing in, then a dissonant stab
    # (A minor with a flat-five) and a low boom.
    swell_d = 0.55
    swell = biquad(noise(swell_d), "bp", np.geomspace(300, 5200, int(RATE * swell_d)), 1.4)
    swell *= np.linspace(0, 1, len(swell)) ** 2.5
    stab_d = 1.1
    stab = np.zeros(int(RATE * stab_d))
    for n_ in ["A3", "C4", "D#4", "A4"]:
        f = note(n_)
        s = osc(f, stab_d, "saw") + osc(f * 1.007, stab_d, "saw")
        stab += biquad(s, "lp", glide(5000, 700, stab_d, 5), 1.0) * env(len(s), 0.003, 0.9)
    boom = osc(glide(120, 40, stab_d, 5), stab_d) * env(int(RATE * stab_d), 0.002, 0.7) * 1.4
    x = np.zeros(int(RATE * (swell_d + stab_d)))
    mix_at(x, swell * 0.7, 0)
    mix_at(x, np.tanh(stab * 0.6) * 0.8 + boom, swell_d)
    return finish(room(x, 0.7, 0.25), 0.26)


def make_tick(freq, rms):
    # Woodblock-ish tick: two inharmonic partials and a tiny click.
    d = 0.07
    n = int(RATE * d)
    x = osc(freq, d) * env(n, 0.0005, 0.035) + osc(freq * 2.76, d) * env(n, 0.0005, 0.015) * 0.4
    x += biquad(noise(d), "hp", 5000) * env(n, 0.0003, 0.006) * 0.5
    return finish(room(x, 0.12, 0.06), rms)


def make_pop():
    # Buttons arriving: a soft bubbly upward blip.
    d = 0.12
    x = osc(np.geomspace(420, 980, int(RATE * d)), d) * env(int(RATE * d), 0.002, 0.07)
    return finish(room(x, 0.15, 0.1), 0.11)


def make_whoosh():
    # Round transition: a short filtered air sweep.
    d = 0.32
    n = int(RATE * d)
    shape = np.sin(np.linspace(0, np.pi, n)) ** 2
    x = biquad(noise(d), "bp", np.geomspace(600, 3800, n), 1.1) * shape
    return finish(x, 0.08)


# ----------------------------------------------------------------------------
# Music bed: 8 bars of nervous A-minor pulse at 120 BPM, loops seamlessly.
# ----------------------------------------------------------------------------

def make_music():
    bpm = 120
    beat = 60 / bpm
    bars = 8
    length = bars * 4 * beat
    n = int(RATE * length)
    tail = int(RATE * 1.5)
    x = np.zeros(n + tail)
    chords = [("A1", ["A3", "C4", "E4"]), ("A1", ["A3", "C4", "E4"]), ("F1", ["F3", "A3", "C4"]), ("E1", ["E3", "G#3", "B3"])] * 2

    # Kick (soft, on 1 and 3) and a sidechain envelope everything else ducks to.
    duck = np.ones(n + tail)
    for bar in range(bars):
        for b in (0, 2):
            at = (bar * 4 + b) * beat
            k = osc(glide(140, 45, 0.3, 14), 0.3) * env(int(RATE * 0.3), 0.001, 0.25)
            mix_at(x, k * 0.9, at)
            i = int(at * RATE)
            m = int(0.22 * RATE)
            duck[i:i + m] = np.minimum(duck[i:i + m], 0.45 + 0.55 * np.linspace(0, 1, m) ** 0.7)

    music = np.zeros(n + tail)
    for bar, (root, triad) in enumerate(chords):
        bar_t = bar * 4 * beat
        # Bass: pulsing 8ths, filtered saw.
        for e in range(8):
            d = beat / 2 * 0.9
            f = note(root) * (2 if e % 4 == 3 else 1)
            s = biquad(osc(f, d, "saw"), "lp", 420 + 300 * (e % 2), 1.4) * env(int(RATE * d), 0.004, d * 1.4)
            mix_at(music, s * 0.55, bar_t + e * beat / 2)
        # Arp: 16th-note glassy plucks, quiet.
        pattern = [0, 1, 2, 1, 0, 2, 1, 2] * 2
        for s16 in range(16):
            if s16 % 4 == 3:
                continue
            f = note(triad[pattern[s16]]) * 2
            p = bell(f, 0.25, index=0.9, ratio=2.0, decay=0.18) * (0.10 if s16 % 4 else 0.14)
            mix_at(music, p, bar_t + s16 * beat / 4)
        # Pad: soft detuned triangle chord.
        pad_d = 4 * beat
        pad = sum(osc(note(tn), pad_d, "tri") + osc(note(tn) * 1.004, pad_d, "tri") for tn in triad)
        shape = np.minimum(1, np.minimum(t_axis(pad_d) / 0.3, (pad_d - t_axis(pad_d)) / 0.3))
        mix_at(music, pad * shape * 0.035, bar_t)
    # Hats: closed 8ths with an open one before each bar line.
    for i in range(bars * 8):
        open_hat = i % 8 == 7
        d = 0.18 if open_hat else 0.04
        h = biquad(noise(d), "hp", 8000) * env(int(RATE * d), 0.0005, d)
        mix_at(music, h * (0.10 if i % 2 else 0.06), i * beat / 2)

    x += music * duck
    x = room(x, 0.6, 0.12)
    # Fold the tail (reverb, delays) back onto the start so the loop is seamless.
    looped = x[:n].copy()
    looped[: len(x) - n] += x[n:]
    looped = looped[:n]
    ceiling = 10 ** (-1.5 / 20)
    rms = np.sqrt(np.mean(looped ** 2))
    looped = np.tanh(looped * (0.12 / rms) / ceiling) * ceiling
    return looped


if __name__ == "__main__":
    write("tap.wav", make_tap())
    write("success.wav", make_success())
    write("fail.wav", make_fail())
    write("reveal.wav", make_reveal())
    write("tick.wav", make_tick(note("E6"), 0.10))
    write("tick_hi.wav", make_tick(note("A6"), 0.12))
    write("pop.wav", make_pop())
    write("whoosh.wav", make_whoosh())
    write("loop.wav", make_music())
