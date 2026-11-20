"""Effetti sonori del reel "Ogni angolo della tua città ha una storia" (12 s).

Tempi come in reel-citta.html: Dot atterra su un ricordo ogni secondo da
1,5 s a 6,5 s; la mappa si allarga a 7,4 s; il logo arriva da 9,0 s.
Prima versione dei suoni, con il suono del logo uguale agli altri video.
Uso: python3 reel_citta_v1_audio.py uscita.wav
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
# stesso suono del logo di post 3 e storia: fischio di Dot che cade, tonfo
# all'atterraggio (10,30 s), rimbalzino, secondo tonfo e "ding"
add(out, tone(1400, 380, 0.5, d=0.6) * np.linspace(0.2, 1, int(0.5 * SR)), 9.80, 0.12)
add(out, mix(tone(170, 55, 0.3, d=0.09), 0.4 * noise(0.05, lp=1200) * env(2400, d=0.02)), 10.30, 0.9)
add(out, tone(300, 520, 0.14, d=0.06), 10.44, 0.25)
add(out, mix(tone(140, 70, 0.15, d=0.05), 0.2 * noise(0.03, lp=900) * env(1440, d=0.01)), 10.70, 0.4)
n = int(1.2 * SR)
ding = sum(np.sin(2 * np.pi * f * np.arange(n) / SR) * g for f, g in ((1046.5, 1), (1568, .45), (2093, .2)))
add(out, ding * env(n, a=0.002, d=0.4), 10.32, 0.22)

write(out, sys.argv[1])
