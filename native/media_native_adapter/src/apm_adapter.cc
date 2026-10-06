// Adapter WebRTC APM (§10 do plano) — STUB M1.
// Responsabilidade futura: uma instância APM com reverse da saída real
// (pós-volume/limiter), AEC antes do enhancer, mesma proveniência do adapter
// (não misturar ABIs). Hoje o APM roda dentro do flutter_webrtc vendored
// (deep_filter_audio_processor.cc); a extração para cá acontece na Fase 2.

#include "fourfun_media.h"

// Nada a compilar no M1: ver livekit_adapter.cc.
