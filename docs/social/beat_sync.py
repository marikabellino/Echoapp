"""Trova tempo e "drop" di un brano, per sincronizzare il reel di Dot.

Analizza il brano (spectral flux → autocorrelazione) e stampa:
  - bpm stimati;
  - il primo battito della griglia;
  - i 3 punti migliori per il drop (inizio della battuta dove l'energia
    sale di più), da passare a reel_dot_audio.py --music-at;
  - il comando completo per audio e video.

Uso: python3 beat_sync.py brano.mp3
"""
import subprocess
import sys

import numpy as np

SR = 22050
HOP = 256


def load(path):
    raw = subprocess.run(
        ['ffmpeg', '-v', 'error', '-i', path, '-f', 'f32le', '-ac', '1',
         '-ar', str(SR), '-'],
        check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(float)


def onset_envelope(x, max_hz=None):
    n_fft = 1024
    win = np.hanning(n_fft)
    frames = 1 + (len(x) - n_fft) // HOP
    idx = np.arange(n_fft)[None, :] + HOP * np.arange(frames)[:, None]
    spec = np.abs(np.fft.rfft(x[idx] * win, axis=1))
    if max_hz is not None:  # solo le basse: la cassa segna il battere
        spec = spec[:, : int(max_hz / (SR / n_fft)) + 1]
    spec = np.log1p(spec * 10)
    flux = np.maximum(0, np.diff(spec, axis=0)).sum(axis=1)
    flux = np.concatenate([[0], flux])
    flux -= np.convolve(flux, np.ones(16) / 16, mode='same')
    return np.maximum(0, flux)


def tempo(env):
    fps = SR / HOP
    ac = np.correlate(env, env, mode='full')[len(env) - 1:]
    best, best_bpm = -1, 120
    for bpm in np.arange(80, 160.01, 0.1):
        lag = 60 / bpm * fps
        score = 0
        for k in (1, 2, 4):
            l = lag * k
            i = int(l)
            if i + 1 < len(ac):
                score += ac[i] + (ac[i + 1] - ac[i]) * (l - i)
        # leggera preferenza per i tempi da club
        score *= 1.0 + 0.15 * np.exp(-((bpm - 124) / 20) ** 2)
        if score > best:
            best, best_bpm = score, bpm
    return float(best_bpm)


def phase(env, bpm):
    fps = SR / HOP
    period = 60 / bpm * fps
    best, best_off = -1, 0.0
    for off in np.arange(0, period, 0.25):
        pos = np.arange(off, len(env) - 1, period)
        s = np.interp(pos, np.arange(len(env)), env).sum()
        if s > best:
            best, best_off = s, off
    return best_off / fps


def main():
    path = sys.argv[1]
    x = load(path)
    env = onset_envelope(x)
    bpm = tempo(env)
    beat = 60 / bpm
    first = phase(onset_envelope(x, max_hz=150), bpm)
    dur = len(x) / SR

    # Energia battito per battito: il drop è il battito dopo il quale la
    # battuta successiva (4 battiti) è molto più forte di quella prima.
    starts = np.arange(first, dur - beat, beat)
    rms = np.array([
        np.sqrt(np.mean(x[int(s * SR):int((s + beat) * SR)] ** 2)) for s in starts
    ])
    jump = np.zeros(len(starts))
    for i in range(4, len(starts) - 4):
        jump[i] = rms[i:i + 4].mean() - rms[i - 4:i].mean()
    # serve almeno ~10 s di musica dopo il drop
    ok = starts + 10.5 < dur
    order = [i for i in np.argsort(-jump) if ok[i] and starts[i] >= 1.4][:3]

    print(f'durata     {dur:.1f} s')
    print(f'bpm        {bpm:.1f}  (battito ogni {beat:.3f} s)')
    print(f'griglia    primo battito (cassa) a {first:.3f} s')
    print('drop migliori (secondi nel brano):')
    for i in order:
        print(f'  {starts[i]:7.3f} s   salto di energia {jump[i]:.3f}')
    if order:
        at = starts[order[0]]
        print()
        print('Comandi:')
        print(f'  python3 reel_dot_audio.py reel_audio.wav --music "{path}" --music-at {at:.3f}')
        print(f'  # nel video: ?bpm={bpm:.2f}&beat0=3.0')


if __name__ == '__main__':
    main()
