# Glossário — sons de voz

Termos usados no código e na ADR-0001.

- **Som local**: efeito de UI que toca só no aparelho de quem executou a ação
  (ex.: meu `join` ao entrar). Via `audioplayers`, nunca entra no LiveKit.
- **Sinal de som (broadcast)**: mensagem `voice-sound/v1` publicada na room
  avisando que uma ação aconteceu. Não carrega áudio, só o nome do som.
- **Som sinalizado**: som que toca no meu aparelho por causa de um sinal
  recebido (ex.: outro participante entrou). Toca o mesmo WAV local.
- **Eco**: sinal cujo remetente sou eu mesmo (`sender == localParticipantId`);
  sempre ignorado (minha ação já tocou o som local).
- **Cooldown de sinal**: janela de ~2s por som que coalesce sinais repetidos
  (rajada entra/sai vira 1 som).
- **Supressão de diff**: quando um sinal chega, o fallback por diff de
  participants do mesmo tipo é ignorado por 2s (evita som duplo entre
  clients novos e antigos).
- **Fallback de diff**: som remoto derivado do snapshot de participants;
  cobre clients antigos (que não publicam sinais) e saídas inesperadas
  (sem publish possível).
- **Deafen**: ensurdecido estilo Discord = mudo total, inclusive de sinais
  recebidos. Só afeta o que eu ouço, nunca o que eu anuncio.
