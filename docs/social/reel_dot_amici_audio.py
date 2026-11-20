"""Effetti sonori del reel "Si sta meglio in cerchia." (12 s, 120 bpm).

Tempi come in reel-dot-amici.html: Dot rosa arriva a 0,15 s, ambra a 1,0 s,
bianco a 1,5 s; si fondono 5,4–6,0 s e si separano 6,7–7,1 s (coriandoli);
il logo arriva da 9,0 s. La musica si aggiunge su Instagram.
Uso: python3 reel_dot_amici_audio.py uscita.wav
"""
import sys

import numpy as np

from sfx_lib import SR, add, env, mix, noise, out_buffer, sweep_noise, tone, write

out = out_buffer(12.0)

# arrivi: tonfo + "pop" con note diverse per ogni Dot
for at, f in ((0.62, 523.25), (1.32, 659.25), (1.82, 783.99)):
    add(out, mix(tone(150, 60, 0.2, d=0.07), 0.3 * noise(0.04, lp=1000) * env(1920, d=0.015)), at, 0.7)
    add(out, mix(tone(f * 1.6, f, 0.14, d=0.06), 0.25 * noise(0.02, hp=2500) * env(960, d=0.008)), at + 0.02, 0.5)
# occhiali da sole: "clack" (3,9 s)
add(out, mix(tone(1800, 1400, 0.05, d=0.012), noise(0.03, hp=1500) * env(1440, d=0.006)), 3.95, 0.6)
# salti alti, tutti insieme, a fine giro (battuta 8 di ogni ciclo)
for at in (3.5, 7.5):
    add(out, tone(300, 700, 0.18, d=0.1), at, 0.25)
# fusione: risucchio e "blob" morbido
add(out, sweep_noise(0.6, 3000, 300, gain_up=False), 5.4, 0.3)
n = int(0.5 * SR)
tt = np.arange(n) / SR
add(out, np.sin(2 * np.pi * (180 + 120 * np.sin(2 * np.pi * 9 * tt)) * tt) * env(n, d=0.18), 5.95, 0.5)
# separazione: "pop" grande + coriandoli
add(out, mix(tone(900, 300, 0.2, d=0.07), 0.5 * noise(0.06, hp=1200) * env(2880, d=0.02)), 6.72, 0.9)
rng = np.random.default_rng(3)
for i in range(16):
    f = float(rng.choice((1318.5, 1568.0, 1760.0, 2093.0)))
    add(out, tone(f, f, 0.12, d=0.04), 6.8 + i * 0.045 + rng.random() * 0.03, 0.07)
# finale: logo
add(out, sweep_noise(0.35, 5000, 250, gain_up=False), 8.9, 0.25)
for i, f in enumerate((392, 440, 494, 523, 587, 659)):
    add(out, tone(f * 1.5, f, 0.09, d=0.04), 9.62 + i * 0.08, 0.45)
add(out, mix(tone(160, 60, 0.25, d=0.08), 0.4 * noise(0.05, lp=1200) * env(2400, d=0.02)), 10.3, 0.9)
n = int(1.4 * SR)
ding = sum(np.sin(2 * np.pi * f * np.arange(n) / SR) * g for f, g in ((1046.5, 1), (1568, .5), (2093, .25)))
add(out, ding * env(n, a=0.002, d=0.45), 10.32, 0.3)

write(out, sys.argv[1])
