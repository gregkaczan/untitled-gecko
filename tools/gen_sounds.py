#!/usr/bin/env python3
"""Writes the game's sounds into sounds/*.wav: short synthesised
one-shots and two loops, 22050 Hz, 16-bit mono, pure Python (no numpy).
They are placeholders with a lo-fi character to match the pixels; a
parameter tweak here regenerates the set, and Godot's pitch_scale gives
each play a little variety (sound.gd).

    python3 tools/gen_sounds.py
"""
import math
import os
import random
import struct
import wave

RATE = 22050
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "sounds")
rng = random.Random(7)


def write(name, samples):
    path = os.path.join(OUT, name + ".wav")
    peak = max(1e-6, max(abs(s) for s in samples))
    scale = 0.9 / peak if peak > 0.9 else 1.0
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767)) for s in samples))
    print("%s: %.2f s" % (path, len(samples) / RATE))


def env(n, attack, decay, curve=2.0):
    """Attack then a curved decay, as a list of n gains."""
    out = []
    for i in range(n):
        t = i / RATE
        if t < attack:
            g = t / attack
        else:
            g = max(0.0, 1.0 - (t - attack) / decay) ** curve
        out.append(g)
    return out


def noise(n):
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


def lowpass(x, cutoff):
    """One-pole low-pass; cutoff may be a number or a list per sample."""
    out = []
    y = 0.0
    for i, v in enumerate(x):
        c = cutoff[i] if isinstance(cutoff, list) else cutoff
        a = 1.0 - math.exp(-2.0 * math.pi * c / RATE)
        y += a * (v - y)
        out.append(y)
    return out


def highpass(x, cutoff):
    lp = lowpass(x, cutoff)
    return [v - l for v, l in zip(x, lp)]


def sine_sweep(n, f0, f1, curve=1.0):
    out = []
    ph = 0.0
    for i in range(n):
        u = (i / n) ** curve
        f = f0 + (f1 - f0) * u
        ph += 2.0 * math.pi * f / RATE
        out.append(math.sin(ph))
    return out


def mix(*parts):
    n = max(len(p) for p in parts)
    out = [0.0] * n
    for p in parts:
        for i, v in enumerate(p):
            out[i] += v
    return out


def gain(x, g):
    return [v * g for v in x]


def mul(x, e):
    return [v * g for v, g in zip(x, e)]


def step():
    # A foot on rock: a soft click, a little low body.
    n = int(0.045 * RATE)
    click = mul(highpass(lowpass(noise(n), 2200.0), 300.0), env(n, 0.001, 0.03, 3.0))
    body = mul(sine_sweep(n, 180.0, 90.0), env(n, 0.001, 0.02, 2.0))
    return mix(gain(click, 0.7), gain(body, 0.35))


def bite():
    # A crunch: a thump under a burst of grit.
    n = int(0.16 * RATE)
    grit = mul(highpass(lowpass(noise(n), [1800.0 - 1400.0 * i / n for i in range(n)]), 200.0), env(n, 0.002, 0.11, 2.5))
    thump = mul(sine_sweep(n, 140.0, 55.0, 0.6), env(n, 0.002, 0.08, 2.0))
    return mix(gain(grit, 0.8), gain(thump, 0.6))


def swallow():
    # A gulp: a dropping tone with a little wet noise.
    n = int(0.22 * RATE)
    tone = mul(sine_sweep(n, 420.0, 110.0, 0.8), env(n, 0.01, 0.17, 1.5))
    wet = mul(lowpass(noise(n), 900.0), env(n, 0.02, 0.12, 2.0))
    return mix(gain(tone, 0.7), gain(wet, 0.25))


def tongue():
    # The tongue leaving: a quick wet pop.
    n = int(0.07 * RATE)
    pop = mul(lowpass(noise(n), 3000.0), env(n, 0.001, 0.025, 3.0))
    chirp = mul(sine_sweep(n, 900.0, 300.0, 0.7), env(n, 0.001, 0.04, 2.0))
    return mix(gain(pop, 0.6), gain(chirp, 0.5))


def snap():
    # The tongue landing or striking: a sharper tick.
    n = int(0.05 * RATE)
    tick = mul(highpass(lowpass(noise(n), 4000.0), 800.0), env(n, 0.0005, 0.02, 3.0))
    knock = mul(sine_sweep(n, 320.0, 160.0), env(n, 0.001, 0.03, 2.0))
    return mix(gain(tick, 0.7), gain(knock, 0.4))


def splash():
    # Into the water: a burst that closes down.
    n = int(0.3 * RATE)
    burst = mul(lowpass(noise(n), [2600.0 - 2200.0 * (i / n) ** 0.7 for i in range(n)]), env(n, 0.004, 0.22, 2.0))
    plop = mul(sine_sweep(n, 260.0, 90.0, 0.7), env(n, 0.003, 0.1, 2.0))
    return mix(gain(burst, 0.7), gain(plop, 0.5))


def drip():
    # A drop into a pool: a rising blip with a tiny echo.
    n = int(0.12 * RATE)
    blip = mul(sine_sweep(n, 700.0, 1500.0, 0.5), env(n, 0.002, 0.07, 2.5))
    out = gain(blip, 0.8)
    d = int(0.06 * RATE)
    out += [0.0] * d
    for i, v in enumerate(blip):
        out[i + d] += v * 0.25
    return out


def land():
    # A body landing: a dull thud.
    n = int(0.12 * RATE)
    thud = mul(sine_sweep(n, 110.0, 50.0, 0.6), env(n, 0.002, 0.09, 2.0))
    dust = mul(lowpass(noise(n), 700.0), env(n, 0.002, 0.06, 2.5))
    return mix(gain(thud, 0.8), gain(dust, 0.3))


def loop(seconds, voices, noise_cut, noise_gain, lfo=0.1):
    """A seamless loop: sines at whole cycles per loop, a slow swell,
    and a filtered noise bed faded across the join."""
    n = int(seconds * RATE)
    out = [0.0] * n
    for f, g in voices:
        cycles = max(1, round(f * seconds))
        fq = cycles / seconds
        for i in range(n):
            out[i] += g * math.sin(2.0 * math.pi * fq * i / RATE)
    bed = lowpass(noise(n), noise_cut)
    fade = int(0.25 * RATE)
    for i in range(n):
        g = 1.0
        if i < fade:
            g = i / fade
        elif i >= n - fade:
            g = (n - i) / fade
        swell = 0.85 + 0.15 * math.sin(2.0 * math.pi * lfo * i / RATE)
        out[i] = out[i] * swell + bed[i] * noise_gain * g
    # The bed's fades cross: add the tail's part at the head so the join is level.
    for i in range(fade):
        out[i] += bed[n - fade + i] * noise_gain * (1.0 - i / fade)
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    write("step", step())
    write("bite", bite())
    write("swallow", swallow())
    write("tongue", tongue())
    write("snap", snap())
    write("splash", splash())
    write("drip", drip())
    write("land", land())
    # The cave: a low hum under a breath of air, 6 s, whole cycles so it loops.
    write("drone", loop(6.0, [(55.0, 0.35), (82.5, 0.15), (110.0, 0.1), (164.0, 0.04)], 260.0, 0.12, 0.08))
    # Daylight at the crack: higher, airier, growing as the gecko climbs (sound.gd places it at the exit).
    write("hum", loop(6.0, [(220.0, 0.12), (330.0, 0.08), (440.0, 0.05), (660.0, 0.02)], 1800.0, 0.1, 0.15))


if __name__ == "__main__":
    main()
