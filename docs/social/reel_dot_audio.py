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
    # ── Base musicale: club house spinta, 124 bpm ─────────────────────────
    # 1,6–3,0 s  crescendo (rullata + riser) durante i rimbalzi
    # 3,0 s      DROP: cassa grossa con sub, basso house in levare, hi-hat a
    #            sedicesimi, open hat, clap + snare, sidechain marcato; il
    #            filtro del basso si apre nelle prime battute
    # 6,4–10 s   picco: piano house sincopato + vocal chop con eco
    # 10–13,3 s  resta il groove; poi accordo aperto sul logo
    # Stesso tempo del ballo di Dot nel video (BEAT0 = 3,0 s, 124 bpm).
    music = np.zeros_like(out)
    keys = np.zeros_like(out)

    def madd(buf, sig, t, gain):
        i = int(t * SR)
        end = min(len(buf), i + len(sig))
        if 0 <= i < len(buf):
            buf[i:end] += sig[: end - i] * gain

    def lowpass(x, cutoff, taps=255):
        n = np.arange(taps) - (taps - 1) / 2
        h = np.sinc(2 * cutoff / SR * n) * np.hamming(taps)
        h /= h.sum()
        return np.convolve(x, h, mode='same')

    def bandpass(x, lo, hi, taps=255):
        return lowpass(x, hi, taps) - lowpass(x, lo, taps)

    def saw(f, d, detune=0.0):
        t = tt(d)
        return 2 * ((f * (1 + detune) * t) % 1) - 1

    def kick():
        t = tt(0.5)
        freq = 44 + 200 * np.exp(-t * 34)
        body = np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.exp(-t * 4.8)
        click = np.sin(2 * np.pi * 3200 * t) * np.exp(-t * 420) * 0.35
        return np.tanh((body + click) * 2.6)

    def snare():
        t = tt(0.16)
        n = rng.normal(0, 1, len(t))
        return (bandpass(n, 900, 6000, 63) + np.sin(2 * np.pi * 200 * t) * 0.5) * np.exp(-t * 22)

    def clap():
        t = tt(0.55)
        n = rng.normal(0, 1, len(t))
        band = bandpass(n, 900, 3500, 63)
        hits = sum(np.exp(-np.maximum(0, t - k * 0.01) * 80) * (t >= k * 0.01) for k in range(4))
        return band * (hits + np.exp(-t * 6) * 0.3)

    def hat(open_=False):
        t = tt(0.24 if open_ else 0.035)
        n = rng.normal(0, 1, len(t))
        n = n - lowpass(n, 8000, 31)
        return n * env(t, 0.001, 12 if open_ else 140)

    def crash():
        t = tt(1.8)
        n = rng.normal(0, 1, len(t))
        return (n - lowpass(n, 4000, 31)) * env(t, 0.002, 2.4)

    def riser(d):
        t = tt(d)
        noise = rng.normal(0, 1, len(t))
        hp = noise - lowpass(noise, 500, 63)
        freq = 200 * 2 ** (t / d * 3)
        tone = np.sin(2 * np.pi * np.cumsum(freq) / SR) * 0.25
        return (hp * 0.6 + tone) * (t / d) ** 2

    def house_bass(f, d, cutoff):
        # basso "organo" house: quadra + dente di sega filtrati, con sub
        t = tt(d)
        sq = np.sign(np.sin(2 * np.pi * f * t))
        s = lowpass(sq * 0.6 + saw(f, d) * 0.5, cutoff, 127)
        sub = np.sin(2 * np.pi * f / 2 * t)
        return np.tanh((s + sub) * 1.6) * np.minimum(1, t / 0.003) * np.exp(-t * 5)

    def piano(freqs, d=0.55):
        # piano house: armoniche con decadimenti diversi, attacco secco
        t = tt(d)
        s = np.zeros(len(t))
        for f in freqs:
            for k in range(1, 7):
                fk = f * k * (1 + 0.0004 * k * k)
                s += np.sin(2 * np.pi * fk * t) * (1 / k ** 1.1) * np.exp(-t * (3 + 2.2 * k))
        s /= len(freqs) * 2
        hammer = bandpass(rng.normal(0, 1, len(t)), 1500, 5000, 63) * np.exp(-t * 200) * 0.15
        return np.tanh((s + hammer) * 1.8) * np.minimum(1, t / 0.002)

    def chop(f, d=0.2):
        t = tt(d)
        vib = 1 + 0.01 * np.sin(2 * np.pi * 6 * t)
        src = 2 * ((np.cumsum(f * vib) / SR) % 1) - 1
        v = (bandpass(src, 650, 820, 127) + bandpass(src, 1000, 1200, 127) * 0.6
             + bandpass(src, 2300, 2600, 127) * 0.3)
        return np.tanh(v * 3) * np.minimum(1, t / 0.008) * np.exp(-t * 9)

    BPM = 124
    beat = 60 / BPM
    s16 = beat / 4
    DROP = 3.0
    END = 13.35
    PEAK = (6.4, 10.0)

    # Crescendo
    roll_t = 1.62
    while roll_t < DROP - 0.02:
        k = (roll_t - 1.62) / (DROP - 1.62)
        step = beat / 2 if k < 0.45 else beat / 4 if k < 0.8 else beat / 8
        madd(music, snare(), roll_t, 0.12 + 0.38 * k)
        roll_t += step
    madd(music, riser(DROP - 1.55), 1.55, 0.38)
    madd(music, crash(), DROP, 0.32)
    madd(music, riser(1.0), PEAK[0] - 1.0, 0.18)   # piccolo lancio prima del picco
    madd(music, crash(), PEAK[0], 0.22)

    # Am7 – Fmaj7 – Cmaj7 – G (voicing da piano house, mano destra)
    chords = [
        ([440.0, 523.25, 659.25, 783.99], 55.0),
        ([440.0, 523.25, 659.25, 698.46], 43.65),
        ([392.0, 493.88, 523.25, 659.25], 65.41),
        ([392.0, 493.88, 587.33, 739.99], 49.0),
    ]
    piano_pat = [0.0, 0.75, 1.5, 2.25, 2.75, 3.5]    # sincopi classiche
    chop_notes = [880.0, 1046.5, 987.77, 783.99]
    t = DROP
    b = 0
    kicks = []
    while t < END:
        notes, root = chords[(b // 4) % 4]
        peak = PEAK[0] <= t < PEAK[1]
        madd(music, kick(), t, 1.0)
        kicks.append(t)
        if b % 2 == 1:
            madd(music, clap(), t, 0.42)
            madd(music, snare(), t, 0.18)
        madd(music, hat(open_=True), t + beat / 2, 0.17)
        for q in range(4):
            madd(music, hat(), t + q * s16, 0.10 if q % 2 else 0.05)
        # basso house in levare; il filtro si apre nelle prime 2 battute
        cutoff = 350 + 1250 * min(1.0, (t - DROP) / (beat * 8))
        madd(music, house_bass(root * 2, beat * 0.42, cutoff), t + beat / 2, 0.62)
        if peak and b % 4 == 0:
            for q in piano_pat:
                madd(keys, piano(notes), t + q * beat, 0.55)
        if peak:
            f = chop_notes[b % 4]
            for e in range(3):
                madd(keys, chop(f), t + beat * 0.75 + e * beat * 0.75, 0.32 * (0.45 ** e))
        t += beat
        b += 1

    tm = np.arange(len(out)) / SR
    duck = np.ones_like(out)
    for k in kicks:
        i = int(k * SR)
        seg_t = tm[i:i + int(beat * SR)] - k
        duck[i:i + len(seg_t)] = np.minimum(duck[i:i + len(seg_t)], 1 - 0.8 * np.exp(-seg_t * 8))
    # sidechain anche sul basso: il "pompare" tipico della house
    music_ducked = music * (0.55 + 0.45 * duck)
    groove = music_ducked + keys * duck

    fade = np.clip((END - tm) / 0.45, 0, 1)
    out += np.tanh(groove * 1.15) * fade * 0.95

    # Coda sul logo: accordo di piano aperto + piatto
    madd(out, piano([261.63, 329.63, 392.0, 493.88, 587.33], 2.0), 15.1, 0.6)
    madd(out, crash(), 15.1, 0.12)

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
