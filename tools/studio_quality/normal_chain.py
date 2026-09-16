#!/usr/bin/env python3
"""Cadeia Normal (baseline): pywebrtc-audio APM upstream (NS+AGC, sem EC offline).

In : corpus/mix_*.wav (48 kHz S16) | Out: normal/<mesmo nome>.wav
Ressalva da SPEC: APM upstream, nao o build exato do fork — honesto, nao bit-exato.
"""
import glob
import os
import wave
import numpy as np
from pywebrtc_audio import AudioProcessor

HERE = os.path.dirname(os.path.abspath(__file__))
CORPUS = os.path.join(HERE, "corpus")
OUT = os.path.join(HERE, "normal")
HOP = 480


def read_s16(path):
    w = wave.open(path, "rb")
    assert (w.getnchannels(), w.getsampwidth(), w.getframerate()) == (1, 2, 48000)
    pcm = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)
    w.close()
    return pcm


def save_s16(path, x):
    x = np.clip(np.asarray(x, dtype=np.float64), -32768, 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(48000)
        w.writeframes(x.tobytes())


def run_file(path):
    ap = AudioProcessor(sample_rate=48000, noise_suppression=True,
                        echo_cancellation=False, auto_gain_control=True)
    x = read_s16(path)
    assert len(x) % HOP == 0, path
    outs = [np.asarray(ap.process(x[i:i + HOP], None), dtype=np.int16)
            for i in range(0, len(x), HOP)]
    return np.concatenate(outs)


def main():
    os.makedirs(OUT, exist_ok=True)
    for path in sorted(glob.glob(os.path.join(CORPUS, "mix_*.wav"))):
        y = run_file(path)
        save_s16(os.path.join(OUT, os.path.basename(path)), y)
        print("normal/" + os.path.basename(path),
              f"rms_in->out {np.sqrt(np.mean(read_s16(path).astype(np.float64)**2)):.0f}->"
              f"{np.sqrt(np.mean(y.astype(np.float64)**2)):.0f}")


if __name__ == "__main__":
    main()
