// Adapter LiveKit C++ (§15–§16 do plano) — STUB M1.
// Responsabilidade futura: Room C++ única (caminho B), publicação de PCM
// via AudioSource::captureFrame e recepção via AudioStream por track.
// Hoje o transporte é 100% Flutter (LiveKitRtcService); este arquivo documenta
// a fronteira e falha explicitamente até o spike M0 fechar o pin do SDK
// (documentação consultada identifica 1.12.0 — validar contra o lab).
//
// Próximos passos (Fase 3):
// 1. Pinar livekit-cpp-sdk como submódulo/CMake FetchContent + hash.
// 2. Implementar publish_microphone/submit/close sobre AudioSource.
// 3. Converter float32 48kHz <-> int16 interleaved na fronteira (ver
//    media_core audio::format).
// 4. Uma identidade por sessão: nunca duas Rooms concorrentes (§4).

#include "fourfun_media.h"

// Nada a compilar no M1: a Room ativa vive no SDK Flutter.
// Este TU existe para o CMake validar o include path da ABI.
