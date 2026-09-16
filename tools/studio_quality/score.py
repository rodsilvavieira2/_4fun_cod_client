#!/usr/bin/env python3
"""score.py — tabela comparativa Studio x Normal + veredito Gate 1.

Uso: score.py clean.wav studio_dir/ normal_dir/ [--dnsmos dnsmos.csv]
Metricas com referencia: PESQwb (16 kHz), STOI (10 kHz), SI-SDR (48 kHz),
  Composite CSIG/CBAK/COVL narrowband (8 kHz, via pysepm — como desenhado).
Sem referencia (Gate 1): SIG/BAK/OVRL via --dnsmos (csv do dnsmos_local.py,
  colunas file,sig,bak,ovrl; file = basename).
Veredito Gate 1 (SPEC): OVRL Studio>Normal (margem --margin, default 0.2),
  BAK melhor, SIG sem regressao (>= -0.1), PESQ/STOI em paridade (>= -5%).
Resample documentado: tudo parte de 48 kHz; PESQ exige 16k, STOI 10k,
  composite 8k — nunca comparar bandas diferentes.
"""
import argparse
import glob
import os
import sys
import wave

import numpy as np
from pesq import pesq
from pystoi import stoi
from scipy.signal import resample_poly

try:
    from pysepm import composite  # noqa
    HAVE_PYSEPM = True
except ImportError:  # pysepm fora do PyPI — composite fica para W2
    composite = None
    HAVE_PYSEPM = False


def read_wav(path, expect_sr=48000):
    w = wave.open(path, "rb")
    assert (w.getnchannels(), w.getsampwidth(), w.getframerate()) == (1, 2, expect_sr), path
    pcm = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64) / 32768.0
    w.close()
    return pcm


def to16(x):
    return resample_poly(x, 1, 3)  # 48k -> 16k


def to10(x):
    return resample_poly(x, 5, 24)  # 48k -> 10k


def to8(x):
    return resample_poly(x, 1, 6)  # 48k -> 8k


def frame_sig(x, win=240, hop=120):
    """Frames Hamming 30 ms @8k, 50% overlap. Retorna (nframes, win)."""
    if len(x) < win:
        return np.zeros((0, win))
    w = np.hamming(win)
    n = 1 + (len(x) - win) // hop
    return np.stack([x[i * hop:i * hop + win] * w for i in range(n)])


def levinson(r, order):
    """LPC via Levinson-Durbin. r: autocorr [0..order]. Retorna a (a[0]=1)."""
    a = np.zeros(order + 1)
    e = r[0] if r[0] > 0 else 1e-9
    a[0] = 1.0
    for i in range(1, order + 1):
        acc = sum(a[j] * r[i - j] for j in range(1, i))
        k = (r[i] - acc) / (e + 1e-12)
        prev = a.copy()
        a[i] = k
        for j in range(1, i):
            a[j] = prev[j] - k * prev[i - j]
        e *= 1.0 - k * k
    return a


def llr_mean(ref8, deg8, order=10):
    """Log-likelihood ratio medio (Hu & Loizou 2008).

    LLR_frame = ln((Ac.Re.Ac')/(Ae.Re.Ae')), >=0, 0 = identicos.
    Media sobre frames com fala (energia clean > pico-40 dB).
    Escala propria (sem normalizacao por frame da ref. MATLAB) — usar so
    relativo Studio x Normal na mesma condicao, nunca contra literatura.
    """
    fr, fd = frame_sig(ref8), frame_sig(deg8)
    n = min(len(fr), len(fd))
    if n == 0:
        return 0.0
    e = np.array([(f ** 2).sum() for f in fr[:n]])
    act = e > (e.max() * 1e-4)
    if not act.any():
        return 0.0
    vals = []
    for i in np.nonzero(act)[0]:
        rc = np.correlate(fr[i], fr[i], "full")[len(fr[i]) - 1:len(fr[i]) + order]
        re_ = np.correlate(fd[i], fd[i], "full")[len(fd[i]) - 1:len(fd[i]) + order]
        ac, ae = levinson(rc, order), levinson(re_, order)
        Re = np.array([re_[abs(i - j)] for i in range(order + 1)
                       for j in range(order + 1)]).reshape(order + 1, order + 1)
        num = float(ac @ Re @ ac) + 1e-12
        den = float(ae @ Re @ ae) + 1e-12
        vals.append(float(np.log(num / den)))
    return float(np.mean(vals))


def segsnr_mean(ref8, deg8, win=240, hop=120, clip=(-10.0, 35.0)):
    """SNR segmental medio (dB), frames com fala, clipado. 35 ~= identicos."""
    fr, fd = frame_sig(ref8, win, hop), frame_sig(deg8, win, hop)
    n = min(len(fr), len(fd))
    if n == 0:
        return clip[1]
    e = np.array([(f ** 2).sum() for f in fr[:n]])
    act = e > (e.max() * 1e-4)
    if not act.any():
        return clip[1]
    vals = []
    for i in np.nonzero(act)[0]:
        sig = (fr[i] ** 2).sum() + 1e-12
        noi = ((fr[i] - fd[i]) ** 2).sum() + 1e-12
        vals.append(float(np.clip(10 * np.log10(sig / noi), *clip)))
    return float(np.mean(vals))


def si_sdr(ref, deg):
    ref = ref - ref.mean()
    deg = deg - deg.mean()
    s_target = (np.dot(deg, ref) / (np.dot(ref, ref) + 1e-9)) * ref
    e_noise = deg - s_target
    return 10 * np.log10((np.dot(s_target, s_target) + 1e-9) / (np.dot(e_noise, e_noise) + 1e-9))


def estimate_delay(ref16, deg16, max_ms=64):
    """Atraso sistematico da cadeia (deg atrasado de `lag` amostras @16k).

    DF tem delay algoritmico (STFT+priming de FIFOs ~30 ms); APM ~7 ms.
    STOI/SI-SDR nao alinham sozinhos — sem compensar, medem delay, nao qualidade.
    """
    from scipy.signal import correlate
    n = min(len(ref16), len(deg16))
    r, y = ref16[:n], deg16[:n]
    seg = slice(n // 3, 2 * n // 3)
    lim = int(16 * max_ms)
    c = correlate(y[seg] - y[seg].mean(), r[seg] - r[seg].mean(), mode="full")
    zero = len(r[seg]) - 1
    lo, hi = max(0, zero - lim), min(len(c), zero + lim + 1)
    return int(np.argmax(c[lo:hi]) + lo - zero)


def metrics(ref48, deg48):
    n = min(len(ref48), len(deg48))
    ref48, deg48 = ref48[:n], deg48[:n]
    r16, d16 = to16(ref48), to16(deg48)
    lag16 = estimate_delay(r16, d16)
    lag48 = lag16 * 3  # 16k -> 48k
    if lag48 > 0:
        deg48 = deg48[lag48:]
    elif lag48 < 0:
        ref48 = ref48[-lag48:]
    n = min(len(ref48), len(deg48))
    ref48, deg48 = ref48[:n], deg48[:n]
    r16, d16 = to16(ref48), to16(deg48)
    m = min(len(r16), len(d16))
    pesq_wb = pesq(16000, r16[:m], d16[:m], "wb")
    r10, d10 = to10(ref48), to10(deg48)
    m = min(len(r10), len(d10))
    stoi_v = stoi(r10[:m], d10[:m], 10000, extended=False)
    sisdr = si_sdr(ref48, deg48)
    r8, d8 = to8(ref48), to8(deg48)
    m = min(len(r8), len(d8))
    llr_v = llr_mean(r8[:m], d8[:m])
    seg_v = segsnr_mean(r8[:m], d8[:m])
    comp = None
    if HAVE_PYSEPM and composite is not None:
        csig, cbak, covl = composite(r8[:m], d8[:m], 8000)
        comp = (float(csig), float(cbak), float(covl))
    return {"pesq": pesq_wb, "stoi": stoi_v, "sisdr": sisdr, "comp": comp,
            "llr": llr_v, "segsnr": seg_v, "delay_ms": lag16 / 16.0}


def load_dnsmos(path):
    import csv
    out = {}
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            low = {k.lower(): v for k, v in row.items() if k}
            key = os.path.basename(low.get("file", low.get("filename", "")))
            out[key] = {k: float(low[k]) for k in ("sig", "bak", "ovrl") if k in low}
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("clean")
    ap.add_argument("studio_dir")
    ap.add_argument("normal_dir")
    ap.add_argument("--dnsmos", default=None)
    ap.add_argument("--margin", type=float, default=0.2)
    a = ap.parse_args()

    ref = read_wav(a.clean)
    dns = load_dnsmos(a.dnsmos) if a.dnsmos else {}
    if not HAVE_PYSEPM:
        print("aviso: pysepm ausente — composite pulado", file=sys.stderr)

    rows = []
    for name in sorted(os.path.basename(p) for p in glob.glob(os.path.join(a.studio_dir, "mix_*.wav"))):
        s = metrics(ref, read_wav(os.path.join(a.studio_dir, name)))
        m = metrics(ref, read_wav(os.path.join(a.normal_dir, name)))
        rows.append((name, s, m))

    hdr = f"{'arquivo':28s} {'PESQ S/N':>13s} {'STOI S/N':>13s} {'SISDR S/N':>13s} {'LLR S/N':>13s} {'segSNR S/N':>13s} {'delayMs S/N':>13s}"
    if dns:
        hdr += f" {'OVRL S/N':>13s}"
    print(hdr)
    for name, s, m in rows:
        line = (f"{name:28s} {s['pesq']:6.2f}/{m['pesq']:<6.2f} "
                f"{s['stoi']:6.3f}/{m['stoi']:<6.3f} "
                f"{s['sisdr']:6.1f}/{m['sisdr']:<6.1f} "
                f"{s['llr']:6.1f}/{m['llr']:<6.1f} "
                f"{s['segsnr']:6.1f}/{m['segsnr']:<6.1f} ")
        line += f"{s['delay_ms']:6.1f}/{m['delay_ms']:<6.1f} "
        if dns:
            ds, dn = dns.get("studio_" + name, {}), dns.get("normal_" + name, {})
            if ds and dn:
                line += f"{ds.get('ovrl', float('nan')):6.2f}/{dn.get('ovrl', float('nan')):<6.2f}"
        print(line)

    # medios para o veredito
    def mean(k, idx):
        return float(np.mean([r[idx][k] for r in rows]))

    ps, pn = mean("pesq", 1), mean("pesq", 2)
    ss, sn = mean("stoi", 1), mean("stoi", 2)
    print(f"\nmedias: PESQ studio={ps:.2f} normal={pn:.2f} | STOI studio={ss:.3f} normal={sn:.3f}")
    if dns:
        ov = [(dns.get("studio_" + n, {}).get("ovrl"), dns.get("normal_" + n, {}).get("ovrl")) for n, _, _ in rows]
        ov = [(x, y) for x, y in ov if x is not None and y is not None]
        bk = [(dns.get("studio_" + n, {}).get("bak"), dns.get("normal_" + n, {}).get("bak")) for n, _, _ in rows]
        sg = [(dns.get("studio_" + n, {}).get("sig"), dns.get("normal_" + n, {}).get("sig")) for n, _, _ in rows]
        dov = np.mean([x - y for x, y in ov])
        dbk = np.mean([x - y for x, y in [(a, b) for a, b in bk if a is not None and b is not None]])
        dsg = np.mean([x - y for x, y in [(a, b) for a, b in sg if a is not None and b is not None]])
        print(f"DNSMOS medios: dOVRL={dov:+.2f} dBAK={dbk:+.2f} dSIG={dsg:+.2f} (margem OVRL {a.margin})")
        ok = (dov >= a.margin and dbk > 0 and dsg >= -0.1
              and ps >= 0.95 * pn and ss >= 0.95 * sn)
        print("GATE 1:", "PASSA — Studio vence no corpus" if ok else "NAO PASSA — tunar DSP e repetir")
    else:
        print("Gate 1: pendente DNSMOS (--dnsmos)")


if __name__ == "__main__":
    main()
