"""Effetti sonori del reel "Ogni angolo della tua città ha una storia" (12 s).

Tempi come in reel-citta.html: Dot atterra su un ricordo ogni secondo da
1,5 s a 6,5 s; la mappa si allarga a 7,4 s; il logo arriva da 9,0 s.
Uso: python3 reel_citta_audio.py uscita.wav
"""
import sys


import numpy as np

from sfx_lib import SR, add, env, mix, noise, out_buffer, sweep_noise, tone, write

DUR = 12.0
out = out_buffer(DUR)

# Dot entra dal basso
add(out, sweep_noise(0.5, 300, 3000), 0.2, 0.25)
# sei salti: fruscio in volo, "pop" all'atterraggio con nota che sale
notes = (523.25, 587.33, 659.25, 698.46, 783.99, 880.0)
for k, f in enumerate(notes):
    landing = 1.5 + k
    add(out, sweep_noise(0.45, 500, 2500), landing - 0.5, 0.12)
    add(out, mix(tone(f * 1.6, f, 0.14, d=0.06), 0.25 * noise(0.02, hp=2500) * env(960, d=0.008)), landing, 0.6)
    add(out, tone(f * 2, f * 2, 0.35, d=0.12), landing + 0.04, 0.08)
# la mappa si allarga: salita e pioggia di puntini
add(out, sweep_noise(1.0, 200, 5000), 7.3, 0.3)
rng = np.random.default_rng(7)
for i in range(18):
    f = float(rng.choice((1046.5, 1174.7, 1318.5, 1568.0)))
    add(out, tone(f, f, 0.12, d=0.04), 7.7 + i * 0.05 + rng.random() * 0.03, 0.08)
# finale: buio, lettere, Dot che atterra nel punto, "ding"
add(out, sweep_noise(0.35, 5000, 250, gain_up=False), 8.9, 0.25)
for i, f in enumerate((392, 440, 494, 523, 587, 659)):
    add(out, tone(f * 1.5, f, 0.09, d=0.04), 9.62 + i * 0.08, 0.45)
add(out, mix(tone(160, 60, 0.25, d=0.08), 0.4 * noise(0.05, lp=1200) * env(2400, d=0.02)), 10.3, 0.9)
n = int(1.4 * SR)
ding = sum(np.sin(2 * np.pi * f * np.arange(n) / SR) * g for f, g in ((1046.5, 1), (1568, .5), (2093, .25)))
add(out, ding * env(n, a=0.002, d=0.45), 10.32, 0.3)

write(out, sys.argv[1])
