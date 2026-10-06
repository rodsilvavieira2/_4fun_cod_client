/// Seletor de backend de mídia (§29 do plano).
///
/// Ordem de degradação: native_livekit > flutter_native_audio > legacy.
/// Defaults seguem `legacy` até os gates (kill switch impede novas sessões
/// nativas). Troca de backend exige leave/rejoin — nunca duas Rooms
/// concorrentes.
library;

/// Backend de mídia efetivo.
enum MediaBackend {
  /// Backend Flutter atual ([LiveKitRtcService]) — default até o gate.
  legacy,

  /// Caminho A: Room Flutter + captura/playback/DSP nativos via adapter.
  flutterNativeAudio,

  /// Caminho B (destino): Room C++ única assumida pelo [NativeRtcService].
  nativeLivekit,
}

/// Flags de rollout (§29.2). Resolução no início da sessão; snapshot expõe
/// o conjunto efetivo para diagnóstico.
class MediaBackendConfig {
  const MediaBackendConfig({
    this.backend = MediaBackend.legacy,
    this.nativeAudioCapture = false,
    this.nativeAudioPlayback = false,
    this.nativeDpdfnet2 = false,
    this.nativeApm = false,
    this.nativeSystemAudio = false,
    this.nativeVideoBridge = false,
    this.nativeDeviceHotSwap = false,
    this.nativeDiagnostics = false,
    this.killSwitch = false,
  });

  /// Default seguro: tudo legado.
  static const legacy = MediaBackendConfig();

  final MediaBackend backend;
  final bool nativeAudioCapture;
  final bool nativeAudioPlayback;
  final bool nativeDpdfnet2;
  final bool nativeApm;
  final bool nativeSystemAudio;
  final bool nativeVideoBridge;
  final bool nativeDeviceHotSwap;
  final bool nativeDiagnostics;

  /// Kill switch: quando true, nenhuma sessão nativa nova é aberta e o
  /// enhancer pode ser desabilitado sem trocar o transporte.
  final bool killSwitch;

  /// Backend efetivo após invariantes de compatibilidade:
  /// - kill switch força `legacy`;
  /// - `nativeLivekit` exige `nativeVideoBridge` validado quando há vídeo;
  /// - captura/playback native nunca combinam com engine legacy abrindo os
  ///   mesmos endpoints (aqui: qualquer captura/playback native fora de um
  ///   backend native cai para `legacy`).
  MediaBackend get effectiveBackend {
    if (killSwitch) return MediaBackend.legacy;
    switch (backend) {
      case MediaBackend.legacy:
        return MediaBackend.legacy;
      case MediaBackend.flutterNativeAudio:
      case MediaBackend.nativeLivekit:
        if (!nativeAudioCapture && !nativeAudioPlayback) {
          return MediaBackend.legacy;
        }
        return backend;
    }
  }

  /// `true` quando o engine nativo pode abrir o microfone nesta sessão.
  bool get mayOpenNativeCapture =>
      effectiveBackend != MediaBackend.legacy && nativeAudioCapture;

  /// `true` quando o engine nativo pode renderizar nesta sessão.
  bool get mayOpenNativePlayback =>
      effectiveBackend != MediaBackend.legacy && nativeAudioPlayback;

  Map<String, bool> toFlagMap() => {
    'media_backend_native': effectiveBackend != MediaBackend.legacy,
    'native_audio_capture': nativeAudioCapture,
    'native_audio_playback': nativeAudioPlayback,
    'native_dpdfnet2': nativeDpdfnet2,
    'native_apm': nativeApm,
    'native_system_audio': nativeSystemAudio,
    'native_video_bridge': nativeVideoBridge,
    'native_device_hot_swap': nativeDeviceHotSwap,
    'native_diagnostics': nativeDiagnostics,
  };

  MediaBackendConfig copyWith({
    MediaBackend? backend,
    bool? nativeAudioCapture,
    bool? nativeAudioPlayback,
    bool? nativeDpdfnet2,
    bool? nativeApm,
    bool? nativeSystemAudio,
    bool? nativeVideoBridge,
    bool? nativeDeviceHotSwap,
    bool? nativeDiagnostics,
    bool? killSwitch,
  }) {
    return MediaBackendConfig(
      backend: backend ?? this.backend,
      nativeAudioCapture: nativeAudioCapture ?? this.nativeAudioCapture,
      nativeAudioPlayback: nativeAudioPlayback ?? this.nativeAudioPlayback,
      nativeDpdfnet2: nativeDpdfnet2 ?? this.nativeDpdfnet2,
      nativeApm: nativeApm ?? this.nativeApm,
      nativeSystemAudio: nativeSystemAudio ?? this.nativeSystemAudio,
      nativeVideoBridge: nativeVideoBridge ?? this.nativeVideoBridge,
      nativeDeviceHotSwap: nativeDeviceHotSwap ?? this.nativeDeviceHotSwap,
      nativeDiagnostics: nativeDiagnostics ?? this.nativeDiagnostics,
      killSwitch: killSwitch ?? this.killSwitch,
    );
  }
}
