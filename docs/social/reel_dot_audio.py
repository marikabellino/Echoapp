"""Colonna sonora originale del reel "Sono Dot" (17 s).

Tutti i suoni sono sintetizzati qui (nessun campione esterno, nessuna
licenza): rimbalzi "boing", pop delle parole, whoosh dell'esplosione fucsia,
brillantini e una musichetta pizzicata leggera. I tempi coincidono con la
timeline di reel-dot.html.

Uso:
  python3 reel_dot_audio.py out.wav
      base musicale sintetizzata (house 124 bpm)
  python3 reel_dot_audio.py out.wav --music brano.mp3 --music-at 32.5
      brano esterno (es. "Stylish" di GlowCity, licenza Envato): il punto
      --music-at (secondi nel brano, idealmente il primo battito di un drop)
      cade esattamente sull'esplosione fucsia (3,0 s). Il brano entra in
      dissolvenza durante i rimbalzi e resta sotto il logo finale.
      I suoni di Dot restano sopra.
"""
import argparse
import subprocess
import sys
import wave

import numpy as np

ap = argparse.ArgumentParser()
ap.add_argument('out')
ap.add_argument('--music', help='brano esterno (mp3/wav/m4a)')
ap.add_argument('--music-at', type=float, default=0.0,
                help='secondo del brano da far cadere sul drop (3,0 s)')
ap.add_argument('--music-gain', type=float, default=0.62)
ap.add_argument('--music-only', action='store_true',
                help='solo la base musicale, senza i suoni di Dot (per anteprime)')
ARGS = ap.parse_args()

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

for t0, f in [(4.1, 640), (4.45, 860)]:       # "Sono" "Dot."
    add(pop(f), t0, 0.55)
add(boing(392), 4.5, 0.35)
add(thud(), 4.95, 0.35)

add(pop(700), 6.52, 0.5)                       # spunta il cappellino
add(tick(1800), 6.62, 0.35)                    # occhiali da sole
add(sparkle(), 6.7, 0.3)
add(whoosh(0.35), 9.85, 0.25)                  # via gli occhiali

for t0, f in zip([10.25, 10.6, 10.78, 11.0], [620, 760, 860, 980]):
    add(pop(f), t0, 0.5)                       # "Presto, nella tua città."
add(bell(1568), 11.3, 0.2)                     # occhiolino

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

if ARGS.music_only:
    out[:] = 0

music_stereo = None
if ARGS.music is None:
    # ── Base musicale: tech house, 120 bpm, sol minore ───────────────────
    # Sul riferimento mandato (115 bpm, sol minore), un filo più veloce e
    # più "tech". Niente rullata: durante i rimbalzi (1,6–3,0 s) il groove
    # suona già ma ovattato, il filtro si apre piano; sul fucsia (3,0 s) si
    # apre di colpo con cassa + colpo di sub. Swing sui sedicesimi.
    #  3,0–6,4   groove: cassa, basso che rolla, shaker, clap con coda
    #  6,4–10    picco della festa: in più accordo tech in levare e tom
    #  10–13,3   resta il groove; poi accordo aperto sul logo
    # Stesso tempo del video: render con ?bpm=120&beat0=3.0
    BPM = 120
    beat = 60 / BPM
    s16 = beat / 4
    SWING = 0.12
    DROP = 3.0
    INTRO = 1.6
    END = 13.35
    PEAK = (6.4, 10.0)
    T = 2 ** (-2 / 12)            # da La minore a Sol minore

    n = len(out)
    drums = np.zeros(n)
    bassb = np.zeros(n)
    keys = np.zeros(n)

    def madd(buf, sig, t, gain):
        i = int(t * SR)
        end = min(len(buf), i + len(sig))
        if 0 <= i < len(buf):
            buf[i:end] += sig[: end - i] * gain

    def lowpass(x, cutoff, taps=255):
        k = np.arange(taps) - (taps - 1) / 2
        h = np.sinc(2 * cutoff / SR * k) * np.hamming(taps)
        h /= h.sum()
        return np.convolve(x, h, mode='same')

    def bandpass(x, lo, hi, taps=255):
        return lowpass(x, hi, taps) - lowpass(x, lo, taps)

    def saw(f, d, detune=0.0):
        t = tt(d)
        return 2 * ((f * (1 + detune) * t) % 1) - 1

    def kick():
        t = tt(0.5)
        fr = 44 + 190 * np.exp(-t * 34)
        b_ = np.sin(2 * np.pi * np.cumsum(fr) / SR) * np.exp(-t * 5)
        return np.tanh((b_ + np.sin(2 * np.pi * 3000 * t) * np.exp(-t * 420) * 0.3) * 2.4)

    def boom():
        t = tt(1.2)
        fr = 38 + 60 * np.exp(-t * 8)
        return np.sin(2 * np.pi * np.cumsum(fr) / SR) * np.exp(-t * 2.5)

    def clap():
        t = tt(0.7)
        nz = rng.normal(0, 1, len(t))
        band = bandpass(nz, 1000, 3600, 63)
        hits = sum(np.exp(-np.maximum(0, t - k * 0.01) * 85) * (t >= k * 0.01) for k in range(4))
        return band * (hits + np.exp(-t * 4.5) * 0.28)

    def hat(open_=False):
        t = tt(0.25 if open_ else 0.03)
        nz = rng.normal(0, 1, len(t))
        return (nz - lowpass(nz, 8000, 31)) * env(t, 0.001, 11 if open_ else 150)

    def shaker():
        t = tt(0.05)
        return bandpass(rng.normal(0, 1, len(t)), 5000, 11000, 31) * np.sin(np.pi * np.minimum(1, t / 0.05))

    def rim():
        t = tt(0.05)
        return (np.sin(2 * np.pi * 1750 * t) + bandpass(rng.normal(0, 1, len(t)), 2000, 6000, 31) * 0.4) * env(t, 0.001, 90)

    def tom(f):
        t = tt(0.25)
        fr = f * (1 + 0.5 * np.exp(-t * 30))
        return np.sin(2 * np.pi * np.cumsum(fr) / SR) * env(t, 0.002, 12)

    def bass(f, d, c=900):
        t = tt(d)
        s_ = lowpass(saw(f, d) + saw(f, d, 0.004), c, 127)
        return np.tanh((s_ * 0.55 + np.sin(2 * np.pi * f / 2 * t) * 0.9) * 1.5) * np.minimum(1, t / 0.004) * np.exp(-t * 6)

    def stab(fs, d=0.28, c=1500):
        t = tt(d)
        s_ = sum(saw(f, d, dt) for f in fs for dt in (-0.005, 0.005)) / (len(fs) * 2)
        return lowpass(s_, c, 127) * env(t, 0.003, 9)

    def pad(fs, d, c=650):
        t = tt(d)
        s_ = sum(saw(f, d, dt) for f in fs for dt in (-0.006, 0, 0.006)) / (len(fs) * 3)
        return lowpass(s_, c) * np.minimum(1, t / 0.1) * np.minimum(1, (d - t) / 0.2)

    def sw(q):
        return q + (SWING * 0.25 if round(q * 4) % 2 == 1 else 0)

    root = 55.0 * T                # sol
    minor = [220 * T, 261.63 * T, 329.63 * T]   # sol minore (sol, sib, re)
    t = DROP - beat * 4            # il groove parte ovattato prima del drop
    b = -4
    kicks = []
    while t < END:
        drop = t >= DROP - 1e-6
        peak = PEAK[0] <= t < PEAK[1]
        if drop:
            madd(drums, kick(), t, 1.0)
            kicks.append(t)
        if b % 2:
            madd(drums, clap(), t, 0.34)
        madd(drums, hat(True), t + beat / 2, 0.15)
        for q in (0, 0.25, 0.5, 0.75):
            madd(drums, shaker(), t + sw(q) * beat, 0.09 if q in (0.25, 0.75) else 0.05)
        if b % 4 == 3:
            madd(drums, rim(), t + sw(0.75) * beat, 0.2)
        if peak and b % 8 == 7:
            madd(drums, tom(160), t + sw(0.25) * beat, 0.2)
            madd(drums, tom(120), t + sw(0.75) * beat, 0.2)
        for q, o, a in ((0.25, 1, 0.55), (0.5, 1, 1.0), (0.75, 2, 0.7)):
            madd(bassb, bass(root * 2 * o, s16 * 0.9), t + sw(q) * beat, 0.5 * a)
        if b % 8 == 0:
            madd(keys, pad(minor, beat * 8), t, 0.28)
        if (peak and b % 2 == 0) or (not peak and b % 4 == 2):
            madd(keys, stab([f * 2 for f in minor]), t + sw(0.75) * beat, 0.24 if peak else 0.16)
        t += beat
        b += 1

    tm = np.arange(n) / SR
    duck = np.ones(n)
    for k in kicks:
        i = int(k * SR)
        seg_t = tm[i:i + int(beat * SR)] - k
        duck[i:i + len(seg_t)] = np.minimum(duck[i:i + len(seg_t)], 1 - 0.8 * np.exp(-seg_t * 8))
    groove = drums + bassb * (0.55 + 0.45 * duck) + keys * duck

    # Rimbalzi: tutto ovattato, il filtro si apre piano fino al drop
    i0, i1 = int(INTRO * SR), int(DROP * SR)
    acc = 0.0
    for i in range(i0, i1):
        k = (i - i0) / (i1 - i0)
        c = 250 * (1100 / 250) ** (k ** 1.6)
        a = 1 - np.exp(-2 * np.pi * c / SR)
        acc += a * (groove[i] - acc)
        groove[i] = acc * (0.3 + 0.5 * k)
    groove[:i0] = 0
    madd(groove, boom(), DROP, 0.5)

    fade = np.clip((END - tm) / 0.45, 0, 1)
    out += np.tanh(groove * 1.15) * fade * 0.95

    # Coda sul logo: accordo aperto in sol minore (sol, sib, re, fa, la)
    madd(out, pad([196.0, 233.08, 293.66, 349.23, 440.0], 2.0, 1400), 15.1, 0.55)

else:
    # ── Brano esterno, allineato al drop ──────────────────────────────────
    raw = subprocess.run(
        ['ffmpeg', '-v', 'error', '-i', ARGS.music, '-f', 'f32le',
         '-ac', '2', '-ar', str(SR), '-'],
        check=True, capture_output=True).stdout
    track = np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).astype(float)
    track /= max(1e-9, np.max(np.abs(track))) / 0.9
    DROP = 3.0
    START = 1.6                      # entra durante i rimbalzi
    src0 = int((ARGS.music_at - (DROP - START)) * SR)
    music_stereo = np.zeros((len(out), 2))
    dst0 = int(START * SR)
    if src0 < 0:                     # brano troppo corto prima del drop
        dst0 -= src0
        src0 = 0
    n = min(len(out) - dst0, len(track) - src0)
    music_stereo[dst0:dst0 + n] = track[src0:src0 + n]
    tm = np.arange(len(out)) / SR
    gain = np.interp(tm, [START, DROP - 0.05, DROP, 13.0, 13.6, 16.2, DUR],
                         [0.0, 0.45, 1.0, 1.0, 0.45, 0.3, 0.0])
    music_stereo *= (gain * ARGS.music_gain)[:, None]

# Normalizza e salva (stereo, leggermente allargato)
left = out
right = np.roll(out, int(0.004 * SR)) * 0.98 + out * 0.02
mix = np.stack([left, right], axis=1)
if music_stereo is not None:
    mix = mix + music_stereo
mix = np.tanh(mix * 1.1)
mix /= np.max(np.abs(mix)) / 0.89
stereo = (mix * 32767).astype(np.int16)
with wave.open(ARGS.out, 'wb') as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(stereo.tobytes())
print('ok', ARGS.out)
