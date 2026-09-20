#!/usr/bin/env python3
"""Sintetiza os 4 sons de voz/stream do app (originais, estilo Discord).

Design ativo (v11 "down-up", derivado da referencia error-08):
- voice_join.wav:  2 golpes metalicos 220 -> 300 Hz, ~500ms
- voice_leave.wav: espelho 300 -> 220 Hz, com release suave (sem corte seco)
- stream_start.wav: 2 notas 523 Hz + 784 Hz, 0.30s
- stream_stop.wav:  2 notas 784 Hz + 523 Hz, 0.30s

Variantes alternativas em DESIGNS (v1..v8): gerar com --preview para
audicao sem alterar os assets.

Formato: mono, 44100 Hz, 16-bit WAV, normalizado em -12 dBFS (v9 em -6).
Deterministico: re-rodar gera os mesmos bytes (sem dithering aleatorio).

Uso:
    python3 tools/synth_voice_sounds.py
    python3 tools/synth_voice_sounds.py --out assets/sounds --check
    python3 tools/synth_voice_sounds.py --preview /tmp/voice_preview
"""

from __future__ import annotations

import argparse
import math
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 44100
PEAK_DBFS = -12.0
FADE_MS = 5.0

PEAK = 10.0 ** (PEAK_DBFS / 20.0)


def _bloop(duration_s: float, f0: float, f1: float) -> list[float]:
    """Bloop estilo Discord: glide exponencial de pitch com ease-out.

    O glide linear soa como sirene/apito; interpolar a frequencia em escala
    log (como o ouvido percebe pitch) com ease-out cubico da o "pop"
    arredondado de entrar em call: sobe rapido e assenta no topo.
    Um toque de 2o/3o harmonico da corpo sem endurecer o timbre.
    """
    n = int(SAMPLE_RATE * duration_s)
    out: list[float] = []
    phase = 0.0
    ratio = f1 / f0
    for i in range(n):
        t = i / n
        eased = 1.0 - (1.0 - t) ** 3
        freq = f0 * (ratio**eased)
        phase += 2.0 * math.pi * freq / SAMPLE_RATE
        seconds = i / SAMPLE_RATE
        attack = 1.0 - math.exp(-seconds / 0.006)
        release_start = 0.75
        if t < release_start:
            release = 1.0
        else:
            u = (t - release_start) / (1.0 - release_start)
            release = 0.5 * (1.0 + math.cos(math.pi * u))
        tone = (
            0.85 * math.sin(phase)
            + 0.22 * math.sin(2.0 * phase)
            + 0.06 * math.sin(3.0 * phase)
        )
        out.append(tone * attack * release)
    return out


def _note(freq: float, duration_s: float) -> list[float]:
    n = int(SAMPLE_RATE * duration_s)
    out: list[float] = []
    for i in range(n):
        t = i / n
        env = math.exp(-2.5 * t) * (1.0 - math.exp(-60.0 * t))
        out.append(math.sin(2.0 * math.pi * freq * i / SAMPLE_RATE) * env)
    return out


def _silence(duration_s: float) -> list[float]:
    return [0.0] * int(SAMPLE_RATE * duration_s)


def _pop(freq: float = 180.0, duration_s: float = 0.05) -> list[float]:
    """Estalo grave curto (ataque percussivo de "porta abrindo")."""
    n = int(SAMPLE_RATE * duration_s)
    return [
        math.sin(2.0 * math.pi * freq * i / SAMPLE_RATE)
        * math.exp(-(i / SAMPLE_RATE) / 0.012)
        for i in range(n)
    ]


def _click(freq: float = 1800.0, duration_s: float = 0.008) -> list[float]:
    """Transiente percussivo de 8ms: marca o instante do evento.

    Deterministico (seno com decaimento rapido, sem ruido aleatorio).
    """
    n = int(SAMPLE_RATE * duration_s)
    return [
        0.6 * math.sin(2.0 * math.pi * freq * i / SAMPLE_RATE)
        * math.exp(-(i / SAMPLE_RATE) / 0.0015)
        for i in range(n)
    ]


def _tone(freq: float, duration_s: float, shimmer: bool = False) -> list[float]:
    """Nota redonda estilo chime: ataque suave, sustain cheio e release limpo.

    Diferente de `_note` (decaimento exponencial constante, que apaga a nota
    longa), aqui o corpo se mantem e so desce no release — a nota de chegada
    do two-tone termina presente, nao murcha.
    """
    n = int(SAMPLE_RATE * duration_s)
    out: list[float] = []
    phase = 0.0
    for i in range(n):
        t = i / n
        phase += 2.0 * math.pi * freq / SAMPLE_RATE
        seconds = i / SAMPLE_RATE
        attack = 1.0 - math.exp(-seconds / 0.008)
        release_start = 0.70
        if t < release_start:
            release = 1.0
        else:
            u = (t - release_start) / (1.0 - release_start)
            release = 0.5 * (1.0 + math.cos(math.pi * u))
        tone = (
            math.sin(phase)
            + 0.25 * math.sin(2.0 * phase)
            + 0.07 * math.sin(3.0 * phase)
            + (0.10 * math.sin(4.0 * phase) if shimmer else 0.0)
        )
        out.append(tone * attack * release)
    return out


def _apply_fade(samples: list[float]) -> list[float]:
    fade_n = max(1, int(SAMPLE_RATE * FADE_MS / 1000.0))
    n = len(samples)
    for i in range(min(fade_n, n)):
        gain = i / fade_n
        samples[i] *= gain
        samples[n - 1 - i] *= gain
    return samples


def _normalize(samples: list[float]) -> list[float]:
    peak = max((abs(s) for s in samples), default=0.0)
    if peak <= 0:
        return samples
    gain = PEAK / peak
    return [s * gain for s in samples]


def _write_wav(
    path: Path, samples: list[float], peak_dbfs: float = PEAK_DBFS
) -> None:
    peak = 10.0 ** (peak_dbfs / 20.0)
    peak_in = max((abs(s) for s in samples), default=0.0)
    gain = (peak / peak_in) if peak_in > 0 else 1.0
    samples = [s * gain for s in _apply_fade(list(samples))]
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        frames = b"".join(
            struct.pack("<h", max(-32768, min(32767, int(s * 32767))))
            for s in samples
        )
        wav.writeframes(frames)


def _fat_tone(freq: float, duration_s: float, shimmer: bool = False) -> list[float]:
    """Versao encorpada de `_tone`: sub-oitava + harmônicos mais cheios.

    O par soava "fino" (seno quase puro some em falante pequeno): a camada
    em f/2 e o rolloff harmonico mais lento dao peso sem perder a direcao.
    """
    n = int(SAMPLE_RATE * duration_s)
    out: list[float] = []
    phase = 0.0
    for i in range(n):
        t = i / n
        phase += 2.0 * math.pi * freq / SAMPLE_RATE
        seconds = i / SAMPLE_RATE
        attack = 1.0 - math.exp(-seconds / 0.008)
        release_start = 0.70
        if t < release_start:
            release = 1.0
        else:
            u = (t - release_start) / (1.0 - release_start)
            release = 0.5 * (1.0 + math.cos(math.pi * u))
        tone = (
            math.sin(phase)
            + 0.45 * math.sin(phase / 2.0)
            + 0.35 * math.sin(2.0 * phase)
            + 0.18 * math.sin(3.0 * phase)
            + 0.08 * math.sin(4.0 * phase)
            + (0.08 * math.sin(5.0 * phase) if shimmer else 0.0)
        )
        out.append(tone * attack * release)
    return out


def _rich_tone(freq: float, duration_s: float, shimmer: bool = False) -> list[float]:
    """Polimento de `_fat_tone`: mesma corpo com ataque mais macio e largura.

    - Voz desafinada em +5 cents (largura/chorus sutil, menos "sintetico puro").
    - Sub-oitava equilibrada (0.35 em vez de 0.45: peso sem boom).
    - Ataque de 10ms (transicao mais macia a partir do click).
    """
    n = int(SAMPLE_RATE * duration_s)
    out: list[float] = []
    phase = 0.0
    phase_wide = 0.0
    detune = 2.0 ** (5.0 / 1200.0)
    for i in range(n):
        t = i / n
        phase += 2.0 * math.pi * freq / SAMPLE_RATE
        phase_wide += 2.0 * math.pi * freq * detune / SAMPLE_RATE
        seconds = i / SAMPLE_RATE
        attack = 1.0 - math.exp(-seconds / 0.010)
        release_start = 0.70
        if t < release_start:
            release = 1.0
        else:
            u = (t - release_start) / (1.0 - release_start)
            release = 0.5 * (1.0 + math.cos(math.pi * u))
        tone = (
            math.sin(phase)
            + 0.15 * math.sin(phase_wide)
            + 0.35 * math.sin(phase / 2.0)
            + 0.30 * math.sin(2.0 * phase)
            + 0.14 * math.sin(3.0 * phase)
            + 0.06 * math.sin(4.0 * phase)
            + (0.06 * math.sin(5.0 * phase) if shimmer else 0.0)
        )
        out.append(tone * attack * release)
    return out


def _metal_bell(freq: float, duration_s: float, decay: float = 0.15) -> list[float]:
    """Sino metalico da v11: fundamental + parciais agudas de decaimento rapido.

    Recria o carater da referencia error-08 (300 -> 220 Hz com brilho
    metalico ~6-8x): corpo grave com faisca aguda que some rapido.
    """
    n = int(SAMPLE_RATE * duration_s)
    out: list[float] = []
    phase = 0.0
    for i in range(n):
        t = i / n
        seconds = i / SAMPLE_RATE
        phase += 2.0 * math.pi * freq / SAMPLE_RATE
        attack = 1.0 - math.exp(-seconds / 0.004)
        env = attack * math.exp(-seconds / decay)
        release_start = 0.70
        if t >= release_start:
            u = (t - release_start) / (1.0 - release_start)
            env *= 0.5 * (1.0 + math.cos(math.pi * u))
        tone = (
            math.sin(phase)
            + 0.20 * math.sin(2.0 * phase)
            + 0.15 * math.sin(7.7 * phase) * math.exp(-seconds / 0.030)
            + 0.10 * math.sin(5.8 * phase) * math.exp(-seconds / 0.050)
        )
        out.append(tone * env)
    return out


def _warm_tone(freq: float, duration_s: float, decay: float = 0.30) -> list[float]:
    """Nota calorosa da v10: fundamental + oitava suave, decaimento longo.

    Recria o carater da referencia (quinta A4+E5 com bloom de ~700ms):
    ataque macio de 8ms, corpo cheio e release em cosseno — sem corte seco.
    """
    n = int(SAMPLE_RATE * duration_s)
    out: list[float] = []
    phase = 0.0
    for i in range(n):
        t = i / n
        seconds = i / SAMPLE_RATE
        phase += 2.0 * math.pi * freq / SAMPLE_RATE
        attack = 1.0 - math.exp(-seconds / 0.008)
        env = attack * math.exp(-seconds / decay)
        release_start = 0.75
        if t >= release_start:
            u = (t - release_start) / (1.0 - release_start)
            env *= 0.5 * (1.0 + math.cos(math.pi * u))
        tone = (
            math.sin(phase)
            + 0.30 * math.sin(2.0 * phase)
            + 0.10 * math.sin(3.0 * phase)
        )
        out.append(tone * env)
    return out


#: Parcial inarmonica medida na referencia (~1250/350 Hz): carater de sino.
REF_BELL_PARTIAL = 3.57


def _bell(freq: float, duration_s: float, decay: float = 0.20) -> list[float]:
    """Sino inspirado na referencia: fundamental grave + parcial inarmonica.

    Ataque rapido e decaimento exponencial longo (a referencia leva ~500ms
    para sumir). Recriacao parametrica — nenhum sample da referencia e usado.
    """
    n = int(SAMPLE_RATE * duration_s)
    out: list[float] = []
    phase = 0.0
    for i in range(n):
        t = i / n
        seconds = i / SAMPLE_RATE
        phase += 2.0 * math.pi * freq / SAMPLE_RATE
        attack = 1.0 - math.exp(-seconds / 0.005)
        env = attack * math.exp(-seconds / decay)
        # Release: os ultimos 30% descem em cosseno ate zero — sem corte seco.
        release_start = 0.70
        if t >= release_start:
            u = (t - release_start) / (1.0 - release_start)
            env *= 0.5 * (1.0 + math.cos(math.pi * u))
        tone = (
            math.sin(phase)
            + 0.12 * math.sin(2.0 * phase)
            + 0.42 * math.sin(REF_BELL_PARTIAL * phase)
        )
        out.append(tone * env)
    return out


def _mix(
    base: list[float], overlay: list[float], offset_s: float
) -> list[float]:
    """Soma `overlay` sobre `base` a partir de `offset_s` (golpes sobrepostos)."""
    out = list(base)
    k = int(offset_s * SAMPLE_RATE)
    if len(out) < k + len(overlay):
        out += [0.0] * (k + len(overlay) - len(out))
    for i, value in enumerate(overlay):
        out[k + i] += value
    return out


def _mallet_tone(freq: float, duration_s: float) -> list[float]:
    """Timbre de mallet/vidro (Sosumi, navegacao do Windows): percussivo.

    Ataque rapido e harmonicos superiores com decaimento bem mais curto que
    a fundamental — o "ping" de vidro/xilofone dos sons classicos de sistema.
    Um toque de sub-oitava mantem o corpo em falante pequeno.
    """
    n = int(SAMPLE_RATE * duration_s)
    out: list[float] = []
    phase = 0.0
    for i in range(n):
        t = i / n
        seconds = i / SAMPLE_RATE
        phase += 2.0 * math.pi * freq / SAMPLE_RATE
        attack = 1.0 - math.exp(-seconds / 0.003)
        release_start = 0.70
        if t < release_start:
            release = 1.0
        else:
            u = (t - release_start) / (1.0 - release_start)
            release = 0.5 * (1.0 + math.cos(math.pi * u))
        tone = (
            math.sin(phase) * release
            + 0.25 * math.sin(phase / 2.0) * release
            + 0.40 * math.sin(2.0 * phase) * math.exp(-seconds / 0.060)
            + 0.25 * math.sin(3.0 * phase) * math.exp(-seconds / 0.030)
            + 0.12 * math.sin(4.0 * phase) * math.exp(-seconds / 0.015)
        )
        out.append(tone * attack)
    return out


def _design_v1() -> dict[str, list[float]]:
    """V1 "bloop": glide exponencial C5 -> A5 em 0.12s; saida = retrogrado."""
    join = _bloop(0.12, 523.25, 880.0)
    return {"join": join, "leave": join[::-1]}


def _design_v2() -> dict[str, list[float]]:
    """V2 "two-tone": E5 (70ms) + respiracao de 20ms + A5 (130ms).

    Direcao subir/descer obvia; a nota de chegada tem corpo cheio (sustain,
    nao murcha) e articulação marcada — "di-ding" de entrar, espelho ao sair.
    """
    join = _tone(659.25, 0.07) + _silence(0.02) + _tone(880.0, 0.13)
    return {"join": join, "leave": join[::-1]}


def _design_v3() -> dict[str, list[float]]:
    """V3 "pop+rises": estalo grave + subida; sensacao fisica de entrar."""
    join = _pop(180.0, 0.05) + _bloop(0.14, 349.23, 799.0)
    return {"join": join, "leave": join[::-1]}


def _design_v4() -> dict[str, list[float]]:
    """V4 "event": transiente percussivo + two-tone com brilho na chegada.

    O click de 8ms marca o instante (o "algo aconteceu"); a nota de chegada
    tem shimmer de oitava dupla. Saida espelha a gramatica: tons
    descendentes + click de "porta fechando" no fim. Par com mais presenca
    (pico em -6 dBFS em vez de -12).
    """
    join = (
        _click()
        + _tone(659.25, 0.07)
        + _silence(0.02)
        + _tone(880.0, 0.15, shimmer=True)
    )
    leave = (
        _tone(880.0, 0.07)
        + _silence(0.02)
        + _tone(659.25, 0.15, shimmer=True)
        + _click()
    )
    return {"join": join, "leave": leave}


def _design_v5() -> dict[str, list[float]]:
    """V5 "full": mesma gramatica da v4 com corpo (sub-oitava + harmonicos).

    Resposta ao feedback "muito fino": camada em f/2, rolloff harmonico mais
    lento, click quente em 1200Hz e nota de chegada mais longa.
    """
    join = (
        _click(freq=1200.0, duration_s=0.010)
        + _fat_tone(659.25, 0.07)
        + _silence(0.02)
        + _fat_tone(880.0, 0.16, shimmer=True)
    )
    leave = (
        _fat_tone(880.0, 0.07)
        + _silence(0.02)
        + _fat_tone(659.25, 0.16, shimmer=True)
        + _click(freq=1200.0, duration_s=0.010)
    )
    return {"join": join, "leave": leave}


def _design_v6() -> dict[str, list[float]]:
    """V6 "lenta": mesma gramatica encorpada da v5 em ritmo mais folgado.

    Resposta ao feedback "muito rapido": primeira nota 120ms, respiracao de
    40ms e nota de chegada com 260ms — da tempo de perceber o movimento de
    entrar/sair. Total ~430ms.
    """
    join = (
        _click(freq=1200.0, duration_s=0.010)
        + _fat_tone(659.25, 0.12)
        + _silence(0.04)
        + _fat_tone(880.0, 0.26, shimmer=True)
    )
    leave = (
        _fat_tone(880.0, 0.12)
        + _silence(0.04)
        + _fat_tone(659.25, 0.26, shimmer=True)
        + _click(freq=1200.0, duration_s=0.010)
    )
    return {"join": join, "leave": leave}


def _design_v7() -> dict[str, list[float]]:
    """V7 "polida": ritmo da v6 com timbre refinado (ataque macio + largura).

    Click quente mais suave, voz desafinada sutil e sub-oitava equilibrada.
    """
    join = (
        _click(freq=900.0, duration_s=0.010)
        + _rich_tone(659.25, 0.12)
        + _silence(0.04)
        + _rich_tone(880.0, 0.26, shimmer=True)
    )
    leave = (
        _rich_tone(880.0, 0.12)
        + _silence(0.04)
        + _rich_tone(659.25, 0.26, shimmer=True)
        + _click(freq=900.0, duration_s=0.010)
    )
    return {"join": join, "leave": leave}


def _design_v8() -> dict[str, list[float]]:
    """V8 "glass": two-tone E5 -> A5 em timbre de mallet, mesmo ritmo da v6.

    Inspirada nos classicos de sistema (Sosumi do macOS, navegacao do
    Windows): o ataque percussivo do proprio mallet dispensa click separado.
    120ms + 40ms de respiro + 260ms de chegada. Total ~430ms.
    """
    join = (
        _mallet_tone(659.25, 0.12)
        + _silence(0.04)
        + _mallet_tone(880.0, 0.26)
    )
    leave = (
        _mallet_tone(880.0, 0.12)
        + _silence(0.04)
        + _mallet_tone(659.25, 0.26)
    )
    return {"join": join, "leave": leave}


def _design_v9() -> dict[str, list[float]]:
    """V9 "reference": gramatica da referencia (2 golpes de sino sobrepostos).

    Sino grave F4 com parcial inarmonica 3.57x e decaimento longo, como o
    arquivo de referencia — mas com direcao: entrar sobe F4 -> C5 (quarta),
    sair desce C5 -> F4. Golpes a 190ms com release suave (sem corte seco).
    """
    join = _mix(_bell(349.23, 0.40), _bell(523.25, 0.40), 0.19)
    leave = _mix(_bell(523.25, 0.40), _bell(349.23, 0.40), 0.19)
    return {"join": join, "leave": leave}


def _design_v10() -> dict[str, list[float]]:
    """V10 "fifth": a quinta A4+E5 da referencia arpejada com direcao.

    Entrar sobe A4 -> E5, sair desce E5 -> A4; golpes sobrepostos a 140ms
    com o bloom longo da referencia. Total ~590ms.
    """
    join = _mix(_warm_tone(440.0, 0.35), _warm_tone(659.25, 0.45), 0.14)
    leave = _mix(_warm_tone(659.25, 0.35), _warm_tone(440.0, 0.45), 0.14)
    return {"join": join, "leave": leave}


def _design_v11() -> dict[str, list[float]]:
    """V11 "down-up": gramatica da referencia error-08 (2 golpes metalicos).

    A referencia desce 300 -> 220 Hz: a saida segue o arquivo e a entrada
    espelha subindo 220 -> 300 Hz. Golpes a 150ms, total ~500ms.
    """
    join = _mix(_metal_bell(220.0, 0.30), _metal_bell(300.0, 0.35), 0.15)
    leave = _mix(_metal_bell(300.0, 0.30), _metal_bell(220.0, 0.35), 0.15)
    return {"join": join, "leave": leave}


DESIGNS = {
    "v1": _design_v1,
    "v2": _design_v2,
    "v3": _design_v3,
    "v4": _design_v4,
    "v5": _design_v5,
    "v6": _design_v6,
    "v7": _design_v7,
    "v8": _design_v8,
    "v9": _design_v9,
    "v10": _design_v10,
    "v11": _design_v11,
}

#: Pico por variante (dBFS). v4+ tem mais presenca.
DESIGN_PEAK_DBFS = {
    "v1": -12.0,
    "v2": -12.0,
    "v3": -12.0,
    "v4": -6.0,
    "v5": -6.0,
    "v6": -6.0,
    "v7": -6.0,
    "v8": -6.0,
    "v9": -6.0,
    "v10": -6.0,
    "v11": -6.0,
}

#: Variante ativa nos assets do app. Trocar apos audicao em --preview.
ACTIVE_DESIGN = "v11"


def synth_all(
    out_dir: Path, design: str = ACTIVE_DESIGN
) -> dict[str, Path]:
    pair = DESIGNS[design]()
    start = _note(523.25, 0.15) + _note(783.99, 0.15)
    stop = _note(783.99, 0.15) + _note(523.25, 0.15)

    targets = {
        "voice_join.wav": pair["join"],
        "voice_leave.wav": pair["leave"],
        "stream_start.wav": start,
        "stream_stop.wav": stop,
    }
    written: dict[str, Path] = {}
    for name, samples in targets.items():
        path = out_dir / name
        _write_wav(path, samples)
        written[name] = path
    return written


def synth_preview(out_dir: Path) -> dict[str, Path]:
    """Gera v1/v2/v3/v4 lado a lado para audicao (NÃO vai para assets)."""
    written: dict[str, Path] = {}
    for name, design in DESIGNS.items():
        pair = design()
        peak = DESIGN_PEAK_DBFS.get(name, PEAK_DBFS)
        for kind, samples in pair.items():
            path = out_dir / f"{name}_{kind}.wav"
            _write_wav(path, samples, peak_dbfs=peak)
            written[f"{name}_{kind}.wav"] = path
    return written


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out",
        default="assets/sounds",
        help="Diretorio de saida dos WAVs (default: assets/sounds)",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Apenas verifica que os arquivos existem e sao WAV validos",
    )
    parser.add_argument(
        "--preview",
        default=None,
        help="Gera as 3 variantes (v1/v2/v3 join+leave) no diretorio dado "
        "para audicao; nao altera os assets do app",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    out_dir = (
        Path(args.out)
        if Path(args.out).is_absolute()
        else repo_root / args.out
    )

    if args.preview:
        preview_dir = (
            Path(args.preview)
            if Path(args.preview).is_absolute()
            else repo_root / args.preview
        )
        written = synth_preview(preview_dir)
        for name, path in written.items():
            size = path.stat().st_size
            print(f"preview {path} ({size} bytes)")
        return 0

    if args.check:
        missing = [
            name
            for name in (
                "voice_join.wav",
                "voice_leave.wav",
                "stream_start.wav",
                "stream_stop.wav",
            )
            if not (out_dir / name).is_file()
        ]
        if missing:
            print(f"FALTANDO: {missing} em {out_dir}")
            return 1
        print(f"OK: 4 sons presentes em {out_dir}")
        return 0

    written = synth_all(out_dir)
    for name, path in written.items():
        size = path.stat().st_size
        print(f"gerado {path} ({size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
