"""Suoni del reel "Ogni angolo della tua città ha una storia" (12 s, stereo).

Il tema è la goccia: ogni ricordo che si apre è un "drop" che cade, con
riverbero; i salti di Dot sono fruscii d'aria che passano da un lato
all'altro; quando la mappa si allarga entra un accordo caldo con un arpeggio
che si apre; sul logo, marimba che sale, tonfo morbido e campana lunga.
Niente base musicale: resta lo spazio per un audio di Instagram (i salti
cadono uno al secondo, a tempo con un brano a 120 bpm).

Tempi come in reel-citta.html: Dot atterra a 1,5 / 2,5 / … / 6,5 s, la mappa
si allarga a 7,4 s, il logo arriva da 9,0 s.

Uso: python3 reel_citta_audio.py uscita.wav
"""
import argparse
import wave

import numpy as np

SR = 48000
DUR = 12.0
rng = np.random.default_rng(21)
n_tot = int(SR * DUR)
L = np.zeros(n_tot)
R = np.zeros(n_tot)
FX_L = np.zeros(n_tot)   # mandata al riverbero
FX_R = np.zeros(n_tot)


def tt(d):
    return np.arange(int(d * SR)) / SR


def place(sig, at, gain=1.0, pan=0.0, verb=0.3):
    """Mette un suono mono nel mix stereo (pan -1..1) con un po' di riverbero."""
    i = int(at * SR)
    k = min(len(sig), n_tot - i)
    if k <= 0:
        return
    gl, gr = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
    s = sig[:k] * gain
    L[i:i + k] += s * gl
    R[i:i + k] += s * gr
    FX_L[i:i + k] += s * gl * verb
    FX_R[i:i + k] += s * gr * verb


def lowpass(x, cutoff, taps=255):
    k = np.arange(taps) - (taps - 1) / 2
    h = np.sinc(2 * cutoff / SR * k) * np.hamming(taps)
    return np.convolve(x, h / h.sum(), mode='same')


def bandpass(x, lo, hi, taps=255):
    return lowpass(x, hi, taps) - lowpass(x, lo, taps)


# ─── strumenti ────────────────────────────────────────────────────────────────

def drop(f, size=1.0):
    """Goccia d'acqua: sinusoide che sale di colpo, poi un piccolo 'plic'."""
    t = tt(0.35 * size)
    fr = f * (0.55 + 0.9 * (1 - np.exp(-t * 90 / size)))
    body = np.sin(2 * np.pi * np.cumsum(fr) / SR) * np.exp(-t * 16 / size)
    tick = np.sin(2 * np.pi * f * 2.7 * t) * np.exp(-t * 160)
    return (body + tick * 0.25) * np.minimum(1, t / 0.002)


def air(d, f0, f1):
    """Fruscio d'aria: rumore filtrato che si sposta."""
    t = tt(d)
    x = rng.standard_normal(len(t))
    y = np.zeros_like(x)
    f = np.geomspace(f0, f1, len(t))
    a = 0.0
    for i in range(len(t)):
        a += (1 - np.exp(-2 * np.pi * f[i] / SR)) * (x[i] - a)
        y[i] = a
    return y / (np.abs(y).max() + 1e-9) * np.sin(np.pi * t / d) ** 2


def paper():
    t = tt(0.06)
    return bandpass(rng.standard_normal(len(t)), 2500, 7000, 63) * np.exp(-t * 70)


def marimba(f, d=0.6):
    t = tt(d)
    s = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * f * 4 * t) * np.exp(-t * 30)
    return s * np.exp(-t * 7) * np.minimum(1, t / 0.002)


def bell(f, d=2.5):
    t = tt(d)
    parts = ((1, 1), (2.76, .45), (5.4, .25), (8.93, .12))
    return sum(np.sin(2 * np.pi * f * m * t) * g * np.exp(-t * (1.6 + m * .5)) for m, g in parts) * np.minimum(1, t / 0.003)


def thump():
    t = tt(0.6)
    fr = 40 + 120 * np.exp(-t * 26)
    return np.tanh(np.sin(2 * np.pi * np.cumsum(fr) / SR) * np.exp(-t * 6) * 1.6)


def pad(fs, d, cutoff=900):
    t = tt(d)
    s = sum(2 * ((f * (1 + dt) * t) % 1) - 1 for f in fs for dt in (-.006, 0, .006)) / (len(fs) * 3)
    return lowpass(s, cutoff) * np.minimum(1, t / 0.6) * np.minimum(1, (d - t) / 0.5)


def swell(d):
    """Piatto al contrario: sale fino al momento giusto."""
    t = tt(d)
    x = bandpass(rng.standard_normal(len(t)), 3000, 12000, 63)
    return x * (t / d) ** 3


# ─── partitura ────────────────────────────────────────────────────────────────
# Sol minore pentatonica: le gocce salgono di nota a ogni ricordo.
G = 392.0
SCALE = [G, G * 2 ** (3 / 12), G * 2 ** (5 / 12), G * 2 ** (7 / 12), G * 2 ** (10 / 12), G * 2]

place(air(0.7, 300, 2500), 0.15, 0.25, pan=0, verb=0.2)          # Dot entra
for k in range(6):
    landing = 1.5 + k
    pan = -0.55 if k % 2 == 0 else 0.55
    place(air(0.48, 600, 3200), landing - 0.5, 0.16, pan=-pan, verb=0.15)
    place(drop(SCALE[k]), landing, 0.75, pan=pan * 0.6, verb=0.45)
    place(paper(), landing + 0.06, 0.18, pan=pan * 0.6, verb=0.1)

# la mappa si allarga
place(swell(1.0), 6.45, 0.22, verb=0.3)
chord = [G / 2, G / 2 * 2 ** (3 / 12), G / 2 * 2 ** (7 / 12), G / 2 * 2 ** (10 / 12), G * 2 ** (2 / 12)]
pd = pad(chord, 2.0)
place(pd, 7.45, 0.22, pan=-0.2, verb=0.5)
place(pad(chord, 2.0, 700), 7.47, 0.2, pan=0.2, verb=0.5)
arp = [G, G * 2 ** (3 / 12), G * 2 ** (7 / 12), G * 2 ** (10 / 12), G * 2, G * 2 * 2 ** (3 / 12), G * 2 * 2 ** (7 / 12)]
for i, f in enumerate(arp):
    place(drop(f, 0.6), 7.55 + i * 0.12, 0.28, pan=-0.8 + i * 0.26, verb=0.6)

# logo
place(air(0.4, 4000, 300), 8.9, 0.18, verb=0.2)
for i, f in enumerate([G, G * 2 ** (3 / 12), G * 2 ** (5 / 12), G * 2 ** (7 / 12), G * 2 ** (10 / 12), G * 2]):
    place(marimba(f), 9.62 + i * 0.08, 0.32, pan=-0.5 + i * 0.2, verb=0.35)
place(thump(), 10.3, 0.8, verb=0.1)
place(drop(G / 2, 2.0), 10.3, 0.5, verb=0.5)
for f, g in ((G * 2, .3), (G * 2 * 2 ** (7 / 12), .18), (G * 4 * 2 ** (3 / 12), .1)):
    place(bell(f), 10.34, g, verb=0.7)

ap = argparse.ArgumentParser()
ap.add_argument('out')
args = ap.parse_args()

# ─── riverbero e uscita ───────────────────────────────────────────────────────

def ir(seed):
    r = np.random.default_rng(seed)
    t = tt(1.6)
    return r.standard_normal(len(t)) * np.exp(-t * 3.2) * 0.06


L += np.convolve(lowpass(FX_L, 6000, 63), ir(1))[:n_tot]
R += np.convolve(lowpass(FX_R, 6000, 63), ir(2))[:n_tot]
mix = np.stack([L, R], axis=1)
mix = np.tanh(mix * 1.1) * 0.9
fade = int(0.5 * SR)
mix[-fade:] *= np.linspace(1, 0, fade)[:, None]
with wave.open(args.out, 'wb') as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes((mix * 32767).astype('<i2').tobytes())
print('ok', args.out)
