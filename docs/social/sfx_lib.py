"""Funzioni di sintesi condivise dagli script audio dei social (effetti sonori)."""
import wave

import numpy as np

SR = 48000
rng = np.random.default_rng(19)


def out_buffer(dur):
    return np.zeros(int(SR * dur))


def add(out, sig, at, gain=1.0):
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


def sweep_noise(dur, f0, f1, gain_up=True):
    """Fruscio filtrato che sale o scende: whoosh / riser."""
    n = int(dur * SR)
    x = rng.standard_normal(n)
    y = np.zeros(n)
    f = np.geomspace(f0, f1, n)
    a = 0.0
    for i in range(n):
        a += (1 - np.exp(-2 * np.pi * f[i] / SR)) * (x[i] - a)
        y[i] = a
    shape = np.linspace(0, 1, n) ** 2 if gain_up else np.sin(np.linspace(0, np.pi, n))
    return y * shape / (np.abs(y).max() + 1e-9)


def write(out, path, fade_s=0.4):
    out = np.tanh(out * 1.2) * 0.85
    k = int(fade_s * SR)
    out[-k:] *= np.linspace(1, 0, k)
    st = np.stack([out, out], axis=1)
    with wave.open(path, 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((st * 32767).astype('<i2').tobytes())
