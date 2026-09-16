# Perna B — protocolo de validacao ecologica (W3)

## Roteiro pareado (falar 2x: 1x Normal, 1x Studio)

Mesmo mic, mesma posicao, mesmo comodo, mesmo ganho. ~60-90 s por modo.

1. **Fala limpa (20 s):** ler um paragrafo em ritmo natural (ex.: esta SPEC em voz alta).
2. **Teclado (20 s):** continuar falando enquanto digita forte (teclado mecanico perto do mic).
3. **Ruido continuo (20 s):** falar com fan/ventilador ligado a ~1 m (ou ruido rosa via caixa).
4. **Pausas (10 s):** 3 silencios de ~3 s entre frases (mede pumping do AGC / gate).

Arquivos: `pernab/normal_YYYYMMDD_HHMM.wav`, `pernab/studio_YYYYMMDD_HHMM.wav`
(captura 48 kHz mono direto do app em cada modo; sem pos-processamento).

## Metricas

- `dnsmos_local.py -t pernab -o pernab.csv` → SIG/BAK/OVRL por arquivo.
- NISQA (quando disponivel): `noisiness/coloration/discontinuity/loudness`.
- Gate 2: DNSMOS acompanha Gate 1 (dOVRL mesmo sinal) **e** escuta cega ≥ 75%.

## Escuta cega (mini-MUSHRA)

1. Recortar N=8 pares (mesmo trecho, normal×studio), ~8 s cada.
2. Renomear aleatorio (`par03_a.wav`, `par03_b.wav`), embaralhar A/B por par
   (script: `blind_pairs.py`, seed registrada, mapa em `blind_map.json` privado).
3. Ouvinte vota por par: prefere A / prefere B / empate. Sem saber o mapa.
4. Contar apenas A/B (empates fora do denominador). PASSA se Studio ≥ 75%.
5. Vies: o autor conhece a propria voz — preferivel segundo ouvinte; se so o
   autor, repetir em dia diferente e checar consistencia.
