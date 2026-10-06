/// Providers da mídia nativa (Fase 4 do plano).
///
/// O [rtcServiceProvider] existente segue `legacy` por padrão. Estes
/// providers expõem a ponte e a configuração do backend para opt-in de dev
/// (flags) e para a tela de diagnóstico — sem alterar o caminho de voz atual.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/native/media/media_bridge.dart';
import '../../core/rtc/livekit_rtc_service.dart';
import '../../core/rtc/media_backend_selector.dart';
import '../../core/rtc/native_rtc_service.dart';
import '../../core/rtc/rtc_providers.dart';
import '../../core/rtc/rtc_service.dart';

/// Configuração do backend (default: legacy). Testes/dev fazem override.
final mediaBackendConfigProvider = Provider<MediaBackendConfig>((ref) {
  return MediaBackendConfig.legacy;
});

/// Ponte com o engine nativo (em memória até o FRB da Fase 3).
final mediaBridgeProvider = Provider<MediaBridge>((ref) {
  return InMemoryMediaBridge();
});

/// Serviço RTC efetivo: legado por padrão; nativo (caminho A) quando as
/// flags resolvem para um backend native. Troca exige recriação do provider
/// (leave/rejoin, nunca duas Rooms concorrentes).
final effectiveRtcServiceProvider = Provider<RtcService>((ref) {
  final config = ref.watch(mediaBackendConfigProvider);
  if (config.effectiveBackend == MediaBackend.legacy) {
    return ref.watch(rtcServiceProvider);
  }
  final inner = LiveKitRtcService(
    nativeMediaServices: ref.read(nativeMediaServicesProvider),
  );
  final service = NativeRtcService(
    inner: inner,
    bridge: ref.read(mediaBridgeProvider),
    config: config,
    onDispose: inner.dispose,
  );
  ref.onDispose(service.dispose);
  return service;
});
