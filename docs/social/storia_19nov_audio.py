"""Effetti sonori della storia del 19 novembre (8 s), a tempo con l'animazione.

I tempi sono quelli di K in storia-special-19nov-video.html.
Uso: python3 storia_19nov_audio.py uscita.wav
"""
import sys
import wave

import numpy as np

SR = 48000
DUR = 8.0
rng = np.random.default_rng(19)
out = np.zeros(int(SR * DUR))


def add(sig, at, gain=1.0):
    i = int(at * SR)
    n = min(len(sig), len(out) - i)
    out[i:i + n] += sig[:n] * gain


def env(n, a=0.004, d=0.2):
    t = np.arange(n) / SR
    return np.minimum(1, t / a) * np.exp(-t / d)


def tone(f0, f1, dur, d=0.1, wave_='sine'):
    n = int(dur * SR)
    f = np.geomspace(f0, f1, n)
    ph = 2 * np.pi * np.cumsum(f) / SR
    s = np.sin(ph) if wave_ == 'sine' else 2 * ((ph / (2 * np.pi)) % 1) - 1
    return s * env(n, d=d)


def noise(dur, lp=None, hp=None):
    n = int(dur * SR)
    x = rng.standard_normal(n)
    X = np.fft.rfft(x)
    fr = np.fft.rfftfreq(n, 1 / SR)
    if lp:
        X *= 1 / (1 + (fr / lp) ** 4)
    if hp:
        X *= 1 / (1 + (hp / np.maximum(fr, 1)) ** 4)
    return np.fft.irfft(X, n)


def sweep_noise(dur, f0, f1, gain_up=True):
    """Fruscio filtrato che sale o scende: whoosh / riser."""
    n = int(dur * SR)
    x = rng.standard_normal(n)
    y = np.zeros(n)
    f = np.geomspace(f0, f1, n)
    a = 0.0
    for i in range(n):  # passa-basso a un polo con frequenza che cambia
        k = 1 - np.exp(-2 * np.pi * f[i] / SR)
        a += k * (x[i] - a)
        y[i] = a
    shape = np.linspace(0, 1, n) ** 2 if gain_up else np.sin(np.linspace(0, np.pi, n))
    return y * shape / (np.abs(y).max() + 1e-9)


def mix(*xs):
    """Somma segnali di lunghezza diversa."""
    n = max(len(x) for x in xs)
    o = np.zeros(n)
    for x in xs:
        o[:len(x)] += x
    return o


pop = lambda f=520: mix(tone(f * 1.8, f, 0.12, d=0.05), 0.3 * noise(0.02, hp=2000) * env(960, d=0.01))
click = lambda: noise(0.012, hp=3000) * env(576, a=0.0005, d=0.004)

# 1 · Dot entra, schiaccia i tasti
add(pop(480), 0.33, 0.8)
for k in range(6, 21):  # pressioni del joystick, 9 al secondo
    add(click(), k / 9, 0.35 if k % 2 else 0.22)

# occhiali che cadono: whoosh, poi "clack" e due rimbalzini
add(sweep_noise(0.27, 300, 4000), 1.55, 0.35)
for at, g in ((1.82, 0.9), (2.06, 0.35), (2.2, 0.15)):
    add(mix(tone(1800, 1400, 0.05, d=0.012), noise(0.03, hp=1500) * env(1440, d=0.006)), at, g)

# 2 · riser e impatto: si entra a Miami
add(sweep_noise(0.45, 200, 6000), 2.0, 0.45)
boom = mix(tone(110, 38, 0.9, d=0.35), 0.5 * noise(0.35, lp=900) * env(int(0.35 * SR), d=0.08))
add(boom, 2.45, 1.0)
# accordo "synthwave" (sol minore) sotto la scritta PAUSA
n = int(1.6 * SR)
tt = np.arange(n) / SR
chord = sum(np.sin(2 * np.pi * f * tt + 0.3 * np.sin(2 * np.pi * 5 * tt)) for f in (196.0, 233.08, 293.66, 392.0))
chord += 0.4 * sum(np.sign(np.sin(2 * np.pi * f * 1.003 * tt)) for f in (196.0, 293.66)) * 0.15
add(chord / 4 * np.minimum(1, tt / 0.02) * np.exp(-tt / 0.6), 2.7, 0.35)
add(pop(700), 2.92, 0.5)
# luccichio sotto "Torno presto"
for i, f in enumerate((1568, 1976, 2349, 3136)):
    add(tone(f, f, 0.25, d=0.08), 3.4 + i * 0.05, 0.12)

# 3 · logo: whoosh verso il buio, lettere a scalini, Dot che atterra
add(sweep_noise(0.35, 5000, 250, gain_up=False), 4.8, 0.3)
for i, f in enumerate((392, 440, 494, 523, 587, 659)):
    add(tone(f * 1.5, f, 0.09, d=0.04, wave_='sine'), 5.45 + i * 0.08, 0.45)
add(mix(tone(160, 60, 0.25, d=0.08), 0.4 * noise(0.05, lp=1200) * env(2400, d=0.02)), 6.1, 0.9)
add(pop(620), 6.36, 0.3)
ding = sum(np.sin(2 * np.pi * f * np.arange(int(1.4 * SR)) / SR) * g for f, g in ((1046.5, 1), (1568, .5), (2093, .25)))
add(ding * env(int(1.4 * SR), a=0.002, d=0.45), 6.12, 0.3)
add(click(), 6.62, 0.25)

out = np.tanh(out * 1.2) * 0.85
fade = np.ones_like(out)
fade[-int(0.4 * SR):] = np.linspace(1, 0, int(0.4 * SR))
out *= fade
st = np.stack([out, out], axis=1)
with wave.open(sys.argv[1], 'wb') as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes((st * 32767).astype('<i2').tobytes())
print('ok')
