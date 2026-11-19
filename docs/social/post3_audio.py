"""Effetti sonori del post 3 (video 7 s), a tempo con le animazioni CSS di posts.html.

Lettere che saltano su (0,05–0,40 s + rimbalzo), Dot che cade nel punto
(da 0,8 s, tocca terra a 1,34 s), frase che sale (1,6 s).
Uso: python3 post3_audio.py uscita.wav
"""
import sys
import wave

import numpy as np

SR = 48000
DUR = 7.0
rng = np.random.default_rng(3)
out = np.zeros(int(SR * DUR))


def add(sig, at, gain=1.0):
    i = int(at * SR)
    n = min(len(sig), len(out) - i)
    out[i:i + n] += sig[:n] * gain


def env(n, a=0.004, d=0.2):
    t = np.arange(n) / SR
    return np.minimum(1, t / a) * np.exp(-t / d)


def tone(f0, f1, dur, d=0.1):
    n = int(dur * SR)
    f = np.geomspace(f0, f1, n)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, d=d)


def noise(dur, lp=None, hp=None):
    n = int(dur * SR)
    X = np.fft.rfft(rng.standard_normal(n))
    fr = np.fft.rfftfreq(n, 1 / SR)
    if lp:
        X *= 1 / (1 + (fr / lp) ** 4)
    if hp:
        X *= 1 / (1 + (hp / np.maximum(fr, 1)) ** 4)
    return np.fft.irfft(X, n)


def mix(*xs):
    o = np.zeros(max(len(x) for x in xs))
    for x in xs:
        o[:len(x)] += x
    return o


def whoosh(dur, f0, f1):
    n = int(dur * SR)
    x = rng.standard_normal(n)
    y = np.zeros(n)
    f = np.geomspace(f0, f1, n)
    a = 0.0
    for i in range(n):
        a += (1 - np.exp(-2 * np.pi * f[i] / SR)) * (x[i] - a)
        y[i] = a
    return y * np.sin(np.linspace(0, np.pi, n)) / (np.abs(y).max() + 1e-9)


# tappeto morbido in sol minore, quasi impercettibile
n = len(out)
tt = np.arange(n) / SR
pad = sum(np.sin(2 * np.pi * f * tt) * g for f, g in ((98, .6), (146.83, .4), (196, .3), (233.08, .25)))
pad *= np.minimum(1, tt / 1.2) * np.minimum(1, (DUR - tt) / 1.0)
out += pad * 0.06

# lettere: sei "blip" a salire
for i, f in enumerate((392, 440, 494, 523, 587, 659)):
    add(tone(f * 1.6, f, 0.1, d=0.04), 0.36 + i * 0.07, 0.4)

# Dot cade: fischio che scende, tonfo, rimbalzino
add(tone(1400, 380, 0.5, d=0.6) * np.linspace(0.2, 1, int(0.5 * SR)), 0.84, 0.12)
add(mix(tone(170, 55, 0.3, d=0.09), 0.4 * noise(0.05, lp=1200) * env(2400, d=0.02)), 1.34, 0.9)
add(tone(300, 520, 0.14, d=0.06), 1.48, 0.25)
add(mix(tone(140, 70, 0.15, d=0.05), 0.2 * noise(0.03, lp=900) * env(1440, d=0.01)), 1.74, 0.4)
ding = sum(np.sin(2 * np.pi * f * np.arange(int(1.2 * SR)) / SR) * g for f, g in ((1046.5, 1), (1568, .45), (2093, .2)))
add(ding * env(int(1.2 * SR), a=0.002, d=0.4), 1.36, 0.22)

# la frase sale: fruscio leggero
add(whoosh(0.4, 600, 3500), 1.5, 0.18)


out = np.tanh(out * 1.2) * 0.85
st = np.stack([out, out], axis=1)
with wave.open(sys.argv[1], 'wb') as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes((st * 32767).astype('<i2').tobytes())
print('ok')
