#!/usr/bin/env python3
"""W0 corpus: fala limpa + ruidos sinteticos a SNRs fixos (zero download).

In : /usr/share/sounds/speech-dispatcher/dummy-message.wav (16 kHz mono)
Out: corpus/clean.wav + corpus/mix_{white,keyboard,fan}_{0,5,10}db.wav (48 kHz S16)
"""
import os
import wave
import numpy as np
from scipy.signal import resample_poly

SR = 48000
SECS = (5.0, 15.0)  # trecho de 10 s
SNRS = (0, 5, 10)
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "corpus")
SRC = "/usr/share/sounds/speech-dispatcher/dummy-message.wav"


def load_clean():
    w = wave.open(SRC, "rb")
    assert (w.getnchannels(), w.getsampwidth(), w.getframerate()) == (1, 2, 16000)
    pcm = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64)
    w.close()
    up = resample_poly(pcm, 3, 1)  # 16k -> 48k
    up = up / max(1.0, np.abs(up).max()) * 0.5  # pico nominal -6 dBFS
    s = slice(int(SECS[0] * SR), int(SECS[1] * SR))
    return up[s]


def white(n, rng):
    return rng.standard_normal(n)


def keyboard(n, rng):
    x = np.zeros(n)
    for _ in range(28):
        pos = rng.integers(0, n - 2400)
        dur = 2400
        t = np.arange(dur) / SR
        freq = rng.uniform(1800, 4200)
        click = np.sin(2 * np.pi * freq * t) * np.exp(-t * 160)
        click += 0.4 * rng.standard_normal(dur) * np.exp(-t * 220)
        x[pos:pos + dur] += click * rng.uniform(0.5, 1.0)
    return x / max(1e-9, np.abs(x).max())


def fan(n, rng):
    brown = np.cumsum(rng.standard_normal(n))
    brown = brown / max(1e-9, np.abs(brown).max())
    t = np.arange(n) / SR
    hum = 0.3 * np.sin(2 * np.pi * 120 * t) + 0.15 * np.sin(2 * np.pi * 240 * t)
    return 0.7 * brown + 0.3 * hum


def apply_snr(clean, noise, snr_db):
    rc = np.sqrt(np.mean(clean ** 2)) + 1e-9
    rn = np.sqrt(np.mean(noise ** 2)) + 1e-9
    return noise * (rc / rn) / (10 ** (snr_db / 20))


def save(path, x):
    x = np.clip(x, -1.0, 1.0 - 1 / 32768)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32768).astype(np.int16).tobytes())


def main():
    os.makedirs(OUT, exist_ok=True)
    rng = np.random.default_rng(42)
    clean = load_clean()
    n = len(clean)
    save(os.path.join(OUT, "clean.wav"), clean)
    makers = {"white": white, "keyboard": keyboard, "fan": fan}
    for name, fn in makers.items():
        noise = fn(n, rng)
        for snr in SNRS:
            mix = clean + apply_snr(clean, noise, snr)
            save(os.path.join(OUT, f"mix_{name}_{snr}db.wav"), mix)
            print(f"mix_{name}_{snr}db.wav")
    print("clean.wav + 9 mixes em", OUT)


if __name__ == "__main__":
    main()
