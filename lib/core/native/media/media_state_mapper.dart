/// Mapeamento engine -> estado da UI (§21, §23 do plano).
///
/// Projeta [EngineSnapshot] e [NativeEvent] em estruturas Riverpod-friendly:
/// separa preferências (Desired) do que roda de fato (Effective) e nunca
/// exibe badge "Studio ativo" com 0 hops processados.
library;

import 'media_bridge.dart';

/// Estado de mídia projetado para a UI.
class MediaUiState {
  const MediaUiState({
    required this.muted,
    required this.deafened,
    required this.mayTransmit,
    required this.pttEnabled,
    required this.requestedDsp,
    required this.effectiveDsp,
    required this.dspDegraded,
    required this.deviceEpoch,
    required this.generation,
  });

  /// `true` quando o DSP efetivo ficou abaixo do solicitado.
  final bool muted;
  final bool deafened;
  final bool mayTransmit;
  final bool pttEnabled;
  final String requestedDsp;
  final String effectiveDsp;
  final bool dspDegraded;
  final int deviceEpoch;
  final int generation;

  /// Badge honesto: só "Studio" quando efetivo é studio.
  String get dspBadge => effectiveDsp == 'studio' ? 'Studio' : effectiveDsp;
}

/// Projeta um snapshot em estado de UI.
MediaUiState projectSnapshotToUi(EngineSnapshot snapshot) {
  return MediaUiState(
    muted: snapshot.muted,
    deafened: snapshot.deafened,
    mayTransmit: snapshot.mayTransmit,
    pttEnabled: snapshot.pttEnabled,
    requestedDsp: snapshot.requestedDsp,
    effectiveDsp: snapshot.effectiveDsp,
    dspDegraded: snapshot.requestedDsp != snapshot.effectiveDsp,
    deviceEpoch: snapshot.deviceEpoch,
    generation: snapshot.generation,
  );
}

/// Reduz eventos discretos a mensagens de UI (coalescing simples).
String? describeEventForUi(NativeEvent event) {
  switch (event.kind) {
    case 'command_applied':
      return null; // silencioso: snapshot cobre
    case 'device_switch_completed':
      return 'Dispositivo trocado';
    case 'dsp_degraded':
      return 'DSP degradado: ${event.detail ?? 'modo básico'}';
    case 'ptt_expired':
      return 'Push-to-talk expirado (watchdog)';
    case 'metrics_tick':
      return null;
    default:
      return null;
  }
}
