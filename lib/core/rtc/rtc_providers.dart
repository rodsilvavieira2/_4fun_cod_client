import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../native/native_media_backend.dart';
import 'livekit_rtc_service.dart';
import 'rtc_service.dart';

/// Composition root dos adaptadores de mídia nativos. Testes podem sobrescrever
/// este provider sem simular [Platform] ou MethodChannels.
final nativeMediaServicesProvider = Provider<NativeMediaServices>((ref) {
  return const DefaultNativeMediaServicesFactory().create(
    currentRuntimePlatform,
  );
});

/// Provider de ciclo de vida do [RtcService] (uma única instância por app).
///
/// O [LiveKitRtcService] é o único ponto de contato com `livekit_client`
/// (invariante do projeto): a UI e os controllers enxergam apenas o
/// contrato [RtcService]. O `dispose` definitivo do serviço (fecha os
/// streams e libera os recursos nativos do WebRTC) roda quando o container
/// for descartado — o descarte POR VIEW (sair do canal de voz) é
/// responsabilidade do controller, via `disconnect()`.
final rtcServiceProvider = Provider<RtcService>((ref) {
  final service = LiveKitRtcService(
    nativeMediaServices: ref.read(nativeMediaServicesProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
