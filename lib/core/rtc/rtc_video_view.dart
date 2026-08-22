import 'package:flutter/material.dart';

// ÚNICO widget do projeto autorizado a importar `livekit_client` para
// RENDERIZAÇÃO (o service segue sendo o único ponto de contato de lógica).
// A UI em features/ usa apenas este widget + RtcVideoTrackRef.
import 'package:livekit_client/livekit_client.dart'
    show VideoRenderMode, VideoTrackRenderer;

import 'livekit_rtc_service.dart' show LiveKitVideoTrackRef;
import 'rtc_service.dart' show RtcVideoTrackRef;

/// Widget de renderização de vídeo da sala (Fase 5).
///
/// ÚNICO widget do projeto autorizado a importar `livekit_client` para
/// renderização — a UI em features/ passa o [RtcVideoTrackRef] opaco vindo
/// de [RtcService.videoTrackOf] e nunca enxerga o tipo LiveKit.
///
/// Regras de exibição (espelham o contrato da Fase 5):
/// - [trackRef] null (câmera OFF/ausente, publicação mutada, desconectado)
///   → placeholder neutro ([SizedBox.shrink]); "OFF" é decisão da UI não
///   montar o view, então o vazio aqui é proposital;
/// - [trackRef] de tipo desconhecido (defensivo) → mesmo placeholder.
class RtcVideoView extends StatelessWidget {
  const RtcVideoView({super.key, required this.trackRef});

  /// Referência renderizável vinda de [RtcService.videoTrackOf]; null
  /// quando a câmera está OFF/ausente.
  final RtcVideoTrackRef? trackRef;

  @override
  Widget build(BuildContext context) {
    final trackRef = this.trackRef;
    if (trackRef is! LiveKitVideoTrackRef) {
      // Câmera OFF/ausente ou ref desconhecido: placeholder neutro (a
      // feature decide o visual ao redor do tile).
      return const SizedBox.shrink();
    }
    // 2.11.0: o widget real é VideoTrackRenderer (VideoView NÃO existe no
    // código). autoDisposeRenderer default true — o renderer gerencia o
    // ciclo de vida da track; renderMode auto resolve para texture em
    // todas as plataformas; fit default (contain) OK para o contrato.
    return VideoTrackRenderer(
      trackRef.track,
      renderMode: VideoRenderMode.auto,
    );
  }
}
