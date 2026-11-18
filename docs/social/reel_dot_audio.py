"""Colonna sonora originale del reel "Ciao, sono Dot" (17 s).

Tutti i suoni sono sintetizzati qui (nessun campione esterno, nessuna
licenza): rimbalzi "boing", pop delle parole, whoosh dell'esplosione fucsia,
brillantini e una musichetta pizzicata leggera. I tempi coincidono con la
timeline di reel-dot.html.

Uso: python3 reel_dot_audio.py out.wav
"""
import sys
import wave

import numpy as np

SR = 44100
DUR = 17.0
rng = np.random.default_rng(7)
out = np.zeros(int(SR * DUR))


def add(sig, t, gain=1.0):
    i = int(t * SR)
    end = min(len(out), i + len(sig))
    if i < len(out):
        out[i:end] += sig[: end - i] * gain


def tt(d):
    return np.arange(int(SR * d)) / SR


def env(t, attack=0.004, decay=8.0):
    return np.minimum(1, t / attack) * np.exp(-t * decay)


def blip(f):
    t = tt(0.12)
    freq = f * (1 + 0.35 * np.minimum(1, t / 0.05))
    return np.sin(2 * np.pi * np.cumsum(freq) / SR) * env(t, 0.003, 30)


def boing(f0):
    t = tt(0.45)
    freq = f0 * (0.55 + 0.75 * np.exp(-t * 9)) * (1 + 0.06 * np.sin(2 * np.pi * 22 * t))
    ph = 2 * np.pi * np.cumsum(freq) / SR
    return (np.sin(ph) + 0.25 * np.sin(2 * ph)) * env(t, 0.005, 7)


def thud():
    t = tt(0.18)
    freq = 140 * np.exp(-t * 18) + 55
    return np.sin(2 * np.pi * np.cumsum(freq) / SR) * env(t, 0.002, 22)


def pop(f):
    t = tt(0.1)
    freq = f * (1.8 * np.exp(-t * 60) + 0.6)
    s = np.sin(2 * np.pi * np.cumsum(freq) / SR) * env(t, 0.001, 38)
    click = rng.normal(0, 1, len(t)) * np.exp(-t * 400) * 0.15
    return s + click


def tick(f):
    t = tt(0.06)
    return np.sin(2 * np.pi * f * t) * env(t, 0.001, 70)


def whoosh(d=0.8):
    t = tt(d)
    noise = rng.normal(0, 1, len(t))
    # passa-basso a una via con taglio che sale: "fruscio" che si apre
    cutoff = 300 + 5000 * (t / d) ** 1.5
    alpha = 1 - np.exp(-2 * np.pi * cutoff / SR)
    y = np.zeros_like(noise)
    acc = 0.0
    for i in range(len(noise)):
        acc += alpha[i] * (noise[i] - acc)
        y[i] = acc
    shape = np.sin(np.pi * np.minimum(1, t / d)) ** 1.5
    return y * shape * 0.9


def sparkle():
    s = np.zeros(int(SR * 0.6))
    for k, f in enumerate([2093, 2637, 3136, 4186]):
        t = tt(0.35)
        n = np.sin(2 * np.pi * f * t) * env(t, 0.002, 14)
        i = int(k * 0.06 * SR)
        s[i:i + len(n)] += n * 0.5
    return s


def bell(f):
    t = tt(0.7)
    return (np.sin(2 * np.pi * f * t) + 0.4 * np.sin(2 * np.pi * f * 2.76 * t)) * env(t, 0.002, 6)


def pluck(f, d=0.5):
    t = tt(d)
    ph = 2 * np.pi * f * t
    return (np.sin(ph) + 0.45 * np.sin(2 * ph) + 0.15 * np.sin(3 * ph)) * env(t, 0.004, 6.5)


def bass(f):
    t = tt(0.5)
    return np.sin(2 * np.pi * f * t) * env(t, 0.006, 4)


def hat():
    t = tt(0.05)
    n = rng.normal(0, 1, len(t))
    n = np.diff(n, prepend=0)  # passa-alto grezzo
    return n * env(t, 0.001, 90)


# ── Effetti, sincronizzati con la timeline del video ────────────────────────
add(blip(1400), 0.42, 0.35)
add(blip(1750), 0.58, 0.35)
add(blip(1500), 1.45, 0.25)

for t0, f in [(1.6, 220), (2.1, 262), (2.55, 311)]:
    add(boing(f), t0, 0.55)
for t0 in [2.1, 2.55]:
    add(thud(), t0, 0.5)
add(thud(), 2.95, 0.8)

add(whoosh(0.8), 2.85, 0.45)
add(sparkle(), 3.05, 0.35)

for t0, f in [(4.0, 600), (4.55, 760), (4.82, 900)]:
    add(pop(f), t0, 0.55)
add(boing(392), 4.85, 0.35)
add(thud(), 5.3, 0.35)

for i in range(11):
    add(tick(1100 + (i % 3) * 180), 6.75 + i * 0.17, 0.35)
for t0, f in [(8.35, 980), (8.5, 1170), (8.65, 1320)]:
    add(pop(f), t0, 0.45)
add(sparkle(), 8.55, 0.4)

for t0, f in zip([10.05, 10.22, 10.5, 10.67, 10.95, 11.1, 11.25],
                 [600, 680, 760, 840, 900, 980, 1060]):
    add(pop(f), t0, 0.45)
add(bell(1568), 11.3, 0.25)

add(boing(330), 12.2, 0.5)
add(thud(), 12.6, 0.4)
add(boing(392), 12.6, 0.5)

# ── Finale col logo ──
add(whoosh(0.6), 12.95, 0.35)           # il buio si richiude
for i in range(5):                       # i pallini arrivano
    add(blip(900 + i * 120), 13.5 + i * 0.06, 0.18)
add(thud(), 14.02, 0.45)                 # si fondono: "bloop"
add(pop(420), 14.04, 0.4)
for k in range(6):                       # escono le lettere
    add(tick(1300 + k * 140), 14.3 + k * 0.055, 0.3)
add(sparkle(), 14.85, 0.3)               # Dot apre gli occhi
for f in (523.25, 659.25, 783.99, 1046.5):   # accordo finale (Do maggiore)
    add(bell(f), 15.15, 0.16)

# ── Musichetta (dall'esplosione fucsia in poi) ──────────────────────────────
music = np.zeros_like(out)


def madd(sig, t, gain):
    i = int(t * SR)
    end = min(len(music), i + len(sig))
    if i < len(music):
        music[i:end] += sig[: end - i] * gain


BPM = 112
eighth = 60 / BPM / 2
notes = {  # C maggiore: C – Am – F – G
    'C': [261.63, 329.63, 392.0, 523.25],
    'Am': [220.0, 261.63, 329.63, 440.0],
    'F': [174.61, 220.0, 261.63, 349.23],
    'G': [196.0, 246.94, 293.66, 392.0],
}
roots = {'C': 65.41, 'Am': 55.0, 'F': 87.31, 'G': 98.0}
prog = ['C', 'Am', 'F', 'G']
pattern = [0, 2, 1, 3, 2, 1, 3, 2]
t0 = 3.1
step = 0
while t0 + step * eighth < DUR:
    t = t0 + step * eighth
    chord = prog[(step // 8) % 4]
    madd(pluck(notes[chord][pattern[step % 8]]), t, 0.22)
    if step % 4 == 0:
        madd(bass(roots[chord] * 2), t, 0.35)
    if step % 2 == 1:
        madd(hat(), t, 0.05)
    step += 1

tm = np.arange(len(music)) / SR
fade = np.clip((tm - 3.1) / 0.5, 0, 1) * np.clip((13.6 - tm) / 0.6, 0, 1)
out += music * fade

# Normalizza e salva (stereo, leggermente allargato)
out = np.tanh(out * 1.1)
out /= np.max(np.abs(out)) / 0.89
left = out
right = np.roll(out, int(0.004 * SR)) * 0.98 + out * 0.02
stereo = (np.stack([left, right], axis=1) * 32767).astype(np.int16)
with wave.open(sys.argv[1], 'wb') as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(stereo.tobytes())
print('ok', sys.argv[1])
