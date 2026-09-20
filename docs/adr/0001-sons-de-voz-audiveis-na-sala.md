# ADR-0001: Sons de voz audíveis por todos na sala

Data: 2026-09-20
Status: aceito
Origem: grill `/grill-with-docs` — "fazer com que esses sons sejam escutados por todos na sala de voz"

## Contexto

Os sons de UI de voz (entrar/sair da sala, início/fim de transmissão) tocavam
somente no aparelho de quem executou a ação (`audioplayers` local). O pedido é
que **todos na sala de voz escutem** os 4 sons — desvio deliberado do Discord,
onde esses sons são locais.

## Decisão

**Sinalização, não injeção de áudio.** Quem executa a ação publica um sinal
leve na sala de voz; cada client toca o WAV correspondente localmente.

- Transporte: LiveKit data messages (`publishData` reliable, tópico
  `voice-sound/v1`, payload `{"sound":"join"|"leave"|"streamStart"|"streamStop"}`).
  Sem mudança no backend: o sinal vive e morre dentro da room.
- Escopo: os 4 sons vão para todos (decisão do grill contra a alternativa
  "só stream").
- Anti-spam: cooldown de ~2s por som no recebimento + respeita o Deafen de
  quem recebe (ensurdecido = mudo total, inclusive de sinais).
- Compatibilidade: clients antigos não publicam sinais — o diff de
  participants (baseline) continua como fallback, mas é **suprimido por 2s**
  quando um sinal do mesmo tipo chega (evita som duplo com clients novos).
- Envio é incondicional: a preferência `voice.sounds_enabled` controla só o
  que EU ouço (sons próprios + sinais recebidos); o evento na sala é público
  e sempre anunciado. Falha de publish nunca derruba a sessão (best-effort).
- Eco: sinais do próprio `localParticipantId` são ignorados.
- Saída inesperada (`DisconnectedEvent`): sem publish possível — os outros
  tocam o fallback do diff.

## Alternativas rejeitadas

- **Injetar o WAV no áudio publicado** (todos ouvem literalmente o mesmo
  áudio): exigiria mixar o arquivo no pipeline de captura do LiveKit,
  com latência, eco e complexidade nativa — desproporcional ao ganho, já que
  todos os clients têm os mesmos WAVs.
- **Broadcast via backend/socket**: ida e volta ao servidor para algo que só
  interessa aos membros da room; data message resolve sem backend.
- **Sons de entrar/sair só locais (Discord puro)**: rejeitado pelo solicitante.

## Consequências

- `RtcService` ganha `publishVoiceSound` + evento `VoiceSoundSignalEvent`.
- `VoiceSoundService` ganha cooldown de sinal (2s) e supressão de diff.
- Tráfego desprezível (4–5 mensagens JSON por ação, reliable).
- Spam em massa (entra/sai repetido) é amortecido pelo cooldown; sem
  moderação por papel nesta v1 (assumido no grill).
