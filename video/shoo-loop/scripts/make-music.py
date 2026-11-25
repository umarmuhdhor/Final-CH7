#!/usr/bin/env python3
"""Synthesizes the exhibition loop's music from src/beats.json, so every kick, whoosh and impact lands on
the same frame as the picture.

128 BPM, 40 beats (18.75 s), A minor (Am7 · Fmaj7 · Cadd9 · G, one chord per bar), house groove:
  beats  0–8   intro: muffled heartbeat kick on every beat, pads opening from a low-pass, arp, claps from
               beat 5, snare roll + riser into a half-beat of silence, then
  beat   8     the drop: impact + crash, full groove (kick on every beat, claps on 2 and 4, offbeat bass
               and hats, chord stabs, arp with ping-pong echo)
  scenes       a whoosh into every scene change and a crash on it; typing ticks, the enter click, a scan
               sweep, a "thock" on each detection-layer card, a dropout + impact on "Diblokir", a two-note
               chime for the family push, a sparkle on the end logo
  beats 36–40  outro: drums and bass stop, the pads close back to the intro's low-pass, so the loop
               runs straight into beat 0
Everything (notes, tails, reverb) is mixed circularly over the loop length, so the end flows into the
start with no seam.
Run: python3 scripts/make-music.py  →  public/audio/music.wav (48 kHz stereo)
"""
import json
import os
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
MAP = json.load(open(os.path.join(HERE, "..", "src", "beats.json")))
OUT = os.path.join(HERE, "..", "public", "audio", "music.wav")

SR = 48000
BPM = MAP["bpm"]
SPB = 60 / BPM
NB = MAP["beats"]
N = int(round(NB * SPB * SR))
EV = MAP["events"]
DROP = MAP["music"]["drop"]
GROOVE_END = MAP["music"]["groove_end"]
DROPOUT = MAP["music"]["dropout"]
rng = np.random.default_rng(7)


def at(beat):
    return int(round(beat * SPB * SR)) % N


def tt(sec):
    return np.arange(int(sec * SR)) / SR


def mtof(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def add(bus, sig, beat, pan=0.0, gain=1.0):
    """Mix a mono or stereo signal into `bus` starting at `beat`, wrapping around the loop end."""
    if sig.ndim == 1:
        lg, rg = np.sqrt(0.5 * (1 - pan)), np.sqrt(0.5 * (1 + pan))
        sig = np.stack([sig * lg, sig * rg], axis=1) * np.sqrt(2)
    idx = (at(beat) + np.arange(len(sig))) % N
    bus[idx] += sig * gain


def fft_filter(x, lo=None, hi=None, order=2):
    n = len(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    h = np.ones_like(f)
    if hi:
        h *= 1 / np.sqrt(1 + (f / hi) ** (2 * order))
    if lo:
        h *= 1 / np.sqrt(1 + (lo / np.maximum(f, 1e-3)) ** (2 * order))
    axis = 0
    X = np.fft.rfft(x, axis=axis)
    return np.fft.irfft(X * (h if x.ndim == 1 else h[:, None]), n, axis=axis)


def noise(sec):
    return rng.standard_normal(int(sec * SR))


# ---------- drums ----------
def kick(punch=1.0):
    t = tt(0.5)
    f = 46 + 120 * np.exp(-t / 0.032) * punch
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.3)
    click = fft_filter(noise(0.5), lo=1500) * np.exp(-t / 0.004) * 0.35
    return np.tanh(1.6 * (body + click)) * 0.95


def muffled_kick():
    return fft_filter(kick(0.6), hi=180) * 0.9


def clap():
    t = tt(0.45)
    env = np.zeros_like(t)
    for d in (0.0, 0.011, 0.022):
        env += (t >= d) * np.exp(-np.maximum(t - d, 0) / 0.006)
    env += (t >= 0.03) * np.exp(-np.maximum(t - 0.03, 0) / 0.11) * 0.7
    return fft_filter(noise(0.45), lo=900, hi=4200) * env * 0.5


def hat(open_=False):
    d = 0.2 if open_ else 0.035
    t = tt(d * 5)
    return fft_filter(noise(d * 5), lo=7500) * np.exp(-t / d) * (0.32 if open_ else 0.26)


def shaker():
    t = tt(0.08)
    return fft_filter(noise(0.08), lo=5000, hi=12000) * np.exp(-t / 0.018) * 0.12


def crash():
    t = tt(2.4)
    return fft_filter(noise(2.4), lo=4000) * np.exp(-t / 0.7) * 0.32


# ---------- tonal ----------
CHORDS = [  # one per bar, MIDI
    [57, 60, 64, 67],  # Am7
    [53, 57, 60, 64],  # Fmaj7
    [48, 55, 62, 64],  # Cadd9
    [55, 59, 62, 67],  # G
]
ROOTS = [45, 41, 48, 43]  # A2 F2 C3 G2


def supersaw(m, sec, cutoff, voices=5, detune=0.12, attack=0.2, release=0.4):
    """Band-limited detuned saws, low-passed per harmonic. `cutoff` is a scalar or a per-sample array."""
    t = tt(sec)
    fc = np.broadcast_to(np.asarray(cutoff, dtype=float), t.shape)
    out = np.zeros_like(t)
    f0 = mtof(m)
    for v in range(voices):
        fv = f0 * 2 ** ((detune * (v - (voices - 1) / 2) / (voices - 1)) / 12 * 2)
        ph = rng.uniform(0, 2 * np.pi)
        kmax = int(min(9000, fc.max() * 4) // fv)
        for k in range(1, max(kmax, 1) + 1):
            g = (1 / k) / np.sqrt(1 + (k * fv / fc) ** 4)
            out += g * np.sin(2 * np.pi * k * fv * t + ph * k)
    env = np.minimum(1, t / attack) * np.minimum(1, (sec - t) / release)
    return out * env / voices


def pluck(m, sec=0.35, decay=0.09, bright=1.0):
    t = tt(sec)
    f = mtof(m)
    x = np.sin(2 * np.pi * f * t) + 0.35 * bright * np.sin(4 * np.pi * f * t) + 0.12 * bright * np.sin(6 * np.pi * f * t)
    return x * np.exp(-t / decay) * np.minimum(1, t / 0.002)


def stab(chord, cutoff=3200):
    sig = sum(supersaw(m + 12, 0.32, cutoff, voices=3, attack=0.003, release=0.2) for m in chord)
    t = tt(0.32)
    return sig * np.exp(-t / 0.11)


def bass_note(m, sec=0.2):
    t = tt(sec)
    f = mtof(m)
    sub = np.sin(2 * np.pi * f * t)
    saw = sum((1 / k) * np.sin(2 * np.pi * k * f * t) / np.sqrt(1 + (k * f / 520) ** 4) for k in range(1, 14))
    env = np.minimum(1, t / 0.004) * np.minimum(1, (sec - t) / 0.03) * (0.6 + 0.4 * np.exp(-t / 0.08))
    return np.tanh(1.3 * (0.8 * sub + 0.55 * saw)) * env


# ---------- fx ----------
def whoosh(beats_long):
    """Rising filtered noise that ends exactly on the hit (place it at hit - beats_long)."""
    sec = beats_long * SPB
    x = noise(sec)
    n = len(x)
    out = np.zeros(n)
    steps = 24
    for i in range(steps):
        a, z = i * n // steps, (i + 1) * n // steps
        c = 400 * (14000 / 400) ** (i / (steps - 1))
        seg = fft_filter(x[max(0, a - 2000) : z], lo=c * 0.5, hi=c)[a - max(0, a - 2000) :]
        out[a:z] = seg
    env = np.linspace(0, 1, n) ** 2.4
    return out * env * 0.55


def downlifter(sec):
    x = noise(sec)
    n = len(x)
    out = np.zeros(n)
    steps = 24
    for i in range(steps):
        a, z = i * n // steps, (i + 1) * n // steps
        c = 9000 * (300 / 9000) ** (i / (steps - 1))
        seg = fft_filter(x[max(0, a - 2000) : z], lo=c * 0.4, hi=c)[a - max(0, a - 2000) :]
        out[a:z] = seg
    return out * np.linspace(1, 0, n) ** 1.5 * 0.35


def impact():
    t = tt(1.6)
    f = 32 + 70 * np.exp(-t / 0.08)
    boom = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.5)
    hit = fft_filter(noise(1.6), lo=200, hi=6000) * np.exp(-t / 0.09) * 0.5
    return np.tanh(1.4 * (boom + hit)) * 0.85


def key_tick():
    t = tt(0.03)
    return fft_filter(noise(0.03), lo=2200, hi=7000) * np.exp(-t / 0.004) * 0.35


def enter_click():
    t = tt(0.25)
    thud = np.sin(2 * np.pi * 140 * t) * np.exp(-t / 0.05)
    tick = np.pad(key_tick(), (0, len(t) - int(0.03 * SR)))
    return tick * 1.6 + thud * 0.6


def scan_sweep(beats_long):
    sec = beats_long * SPB
    t = tt(sec)
    f = 500 * (1600 / 500) ** (t / sec)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * (0.5 + 0.5 * np.sin(2 * np.pi * 16 * t))
    return x * np.minimum(1, t / 0.05) * np.minimum(1, (sec - t) / 0.15) * 0.08


def thock():
    t = tt(0.3)
    f = 190 * (1 + 0.6 * np.exp(-t / 0.02))
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.07)
    snap = fft_filter(noise(0.3), lo=1800, hi=8000) * np.exp(-t / 0.012) * 0.5
    return (tone + snap) * 0.6


def alarm():
    # two short descending tones: "not safe"
    out = np.zeros(int(0.5 * SR))
    for i, m in enumerate([81, 76]):
        p = pluck(m, 0.3, 0.07, bright=1.6)
        a = int(i * 0.12 * SR)
        out[a : a + len(p)] += p
    return out * 0.35


def chime():
    out = np.zeros(int(1.2 * SR))
    for i, m in enumerate([88, 95]):  # E6, B6
        t = tt(0.9)
        f = mtof(m)
        x = (np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * 2.76 * f * t) * np.exp(-t / 0.1)) * np.exp(-t / 0.35)
        a = int(i * 0.11 * SR)
        out[a : a + len(t)] += x
    return out * 0.3


def sparkle():
    out = np.zeros(int(1.0 * SR))
    for i, m in enumerate([93, 96, 100, 105]):
        p = pluck(m, 0.4, 0.12, bright=0.5)
        a = int(i * 0.045 * SR)
        out[a : a + len(p)] += p
    return out * 0.18


def reverb_ir(sec=1.8, hp=300):
    t = tt(sec)
    l = fft_filter(noise(sec), lo=hp, hi=9000) * np.exp(-t / (sec / 5))
    r = fft_filter(noise(sec), lo=hp, hi=9000) * np.exp(-t / (sec / 5))
    ir = np.stack([l, r], axis=1)
    ir[: int(0.012 * SR)] = 0  # pre-delay
    return ir / np.sqrt((ir**2).sum() / 2)


def circular_conv(x, ir):
    X = np.fft.rfft(x, axis=0)
    H = np.fft.rfft(np.vstack([ir, np.zeros((N - len(ir), 2))]), axis=0)
    return np.fft.irfft(X * H, N, axis=0)


def main():
    drums = np.zeros((N, 2))
    bass = np.zeros((N, 2))
    music = np.zeros((N, 2))
    fx = np.zeros((N, 2))
    send = np.zeros((N, 2))  # reverb send

    in_groove = lambda beat: DROP <= beat < GROOVE_END and not (DROPOUT[0] <= beat < DROPOUT[1])
    kicks = []

    # --- drums
    for beat in range(NB):
        if beat < DROP:
            if beat < 7.75:
                add(drums, muffled_kick(), beat, gain=0.55 + 0.05 * beat)
                kicks.append((beat, 0.25))
        elif in_groove(beat):
            add(drums, kick(), beat)
            kicks.append((beat, 0.6))
    for beat in np.arange(0, NB, 0.5):
        off = beat % 1 == 0.5
        if in_groove(beat) and off:
            add(drums, hat(open_=(beat % 4 == 3.5)), beat, pan=0.15)
        if off and GROOVE_END <= beat < GROOVE_END + 2:  # hats fade out over the first outro bar half
            add(drums, hat(), beat, pan=0.15, gain=1 - (beat - GROOVE_END) / 2)
    for beat in np.arange(0, NB, 0.25):
        if in_groove(beat) and beat % 0.5 == 0.25:
            add(drums, shaker(), beat, pan=-0.25)
    # claps on 2 and 4 (odd beats), from beat 5 in the intro
    for beat in range(NB):
        if beat % 2 == 1 and ((5 <= beat < DROP - 1) or in_groove(beat)):
            c = clap()
            add(drums, c, beat, gain=0.9)
            add(send, c, beat, gain=0.35)
    # snare roll into the drop: 8ths then 16ths, rising
    for i, beat in enumerate(list(np.arange(6, 7, 0.5)) + list(np.arange(7, 7.75, 0.25))):
        add(drums, clap(), beat, gain=0.35 + 0.1 * i)

    # --- harmony
    bar_sec = 4 * SPB
    for bar in range(NB // 4):
        chord = CHORDS[bar % 4]
        b0 = bar * 4
        t = tt(bar_sec + 0.5)
        abs_beat = b0 + t / SPB
        # pad cutoff: intro opens 350 → 2600, groove 2600, outro closes back to 350 (matches beat 0)
        fc = np.interp(abs_beat, [0, DROP, GROOVE_END, NB], [350, 2600, 2600, 350])
        for m in chord:
            p = supersaw(m, bar_sec + 0.5, fc, voices=5, attack=0.15, release=0.5)
            add(music, p, b0, pan=0.0, gain=0.22)
            add(send, p, b0, gain=0.08)
        # offbeat bass in the groove
        for k in range(4):
            beat = b0 + k + 0.5
            if in_groove(beat):
                add(bass, bass_note(ROOTS[bar % 4]), beat, gain=0.55)
        # chord stabs on the "and" of 2 and 4
        for k in (1.5, 3.5):
            beat = b0 + k
            if in_groove(beat):
                s_ = stab(chord)
                add(music, s_, beat, gain=0.45)
                add(send, s_, beat, gain=0.18)
        # 16th arp: chord tones an octave up; muffled in the intro and outro
        pattern = [0, 1, 2, 3, 2, 1, 2, 3]
        for i in range(16):
            beat = b0 + i * 0.25
            if DROPOUT[0] <= beat < DROPOUT[1]:
                continue
            m = chord[pattern[i % 8]] + 12
            bright = float(np.interp(beat, [0, DROP, GROOVE_END, NB], [0.15, 1, 1, 0.15]))
            g = float(np.interp(beat, [0, DROP - 2, DROP, GROOVE_END, NB], [0.25, 0.6, 0.75, 0.75, 0.25]))
            p = pluck(m, 0.3, 0.07 + 0.04 * bright, bright=bright)
            if bright < 0.9:
                p = fft_filter(p, hi=500 + 3500 * bright)
            pan = -0.35 if i % 2 else 0.35
            add(music, p, beat, pan=pan, gain=0.2 * g)
            # dotted-8th ping-pong echo
            add(music, p, beat + 0.75, pan=-pan, gain=0.07 * g)
            add(send, p, beat, gain=0.05 * g)

    # --- fx on the picture's events
    scenes = MAP["scenes"]
    for name in ("link", "layers", "phone", "end"):
        hit = scenes[name]["in"]
        add(fx, whoosh(1), hit - 1, gain=0.7)
        cr = crash()
        add(fx, cr, hit, gain=0.8)
        add(send, cr, hit, gain=0.15)
    add(fx, whoosh(2), DROP - 2, gain=0.9)  # riser into the drop (louder, longer)
    add(fx, impact(), DROP, gain=0.9)
    add(send, impact(), DROP, gain=0.2)
    # typing: one tick per 16th
    for beat in np.arange(EV["type_start"], EV["type_end"] + 1e-6, 0.25):
        add(fx, key_tick(), float(beat), pan=float(rng.uniform(-0.2, 0.2)), gain=float(rng.uniform(0.7, 1.0)))
    add(fx, enter_click(), EV["enter"], gain=1.0)
    add(fx, scan_sweep(EV["scan_end"] - EV["enter"]), EV["enter"], gain=1.0)
    for i, beat in enumerate(EV["layers"]):
        add(fx, thock(), beat, gain=0.9)
        add(send, thock(), beat, gain=0.2)
    add(fx, whoosh(DROPOUT[1] - DROPOUT[0]), DROPOUT[0], gain=0.6)
    add(fx, impact(), EV["blocked"], gain=1.0)
    add(fx, alarm(), EV["blocked"] + 0.25, gain=0.8)
    add(send, alarm(), EV["blocked"] + 0.25, gain=0.3)
    add(fx, chime(), EV["push"], gain=1.0)
    add(send, chime(), EV["push"], gain=0.35)
    add(fx, sparkle(), EV["end_logo"], gain=1.0)
    add(send, sparkle(), EV["end_logo"], gain=0.4)
    add(fx, downlifter(3 * SPB), GROOVE_END, gain=0.8)

    # --- sidechain: duck pads, stabs, arp and bass under each kick
    duck = np.ones(N)
    span = int(0.42 * SR)
    tk = np.arange(span) / SR
    for beat, depth in kicks:
        idx = (at(beat) + np.arange(span)) % N
        g = 1 - depth * np.exp(-tk / 0.1) * np.minimum(1, tk / 0.004 + 0.3)
        duck[idx] = np.minimum(duck[idx], g)
    music *= duck[:, None]
    bass *= duck[:, None]

    rev = circular_conv(send, reverb_ir())
    mix = drums * 0.85 + bass * 0.75 + music * 0.6 + fx * 0.55 + rev * 0.5
    mix = fft_filter(mix, lo=28)
    mix /= np.max(np.abs(mix)) / 0.95
    mix = np.tanh(1.25 * mix) / np.tanh(1.25)
    mix *= 0.89 / np.max(np.abs(mix))

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with wave.open(OUT, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((mix * 32767).astype(np.int16).tobytes())
    print("wrote", os.path.abspath(OUT), f"{N / SR:.4f}s at {BPM} BPM, {NB} beats")


if __name__ == "__main__":
    main()
