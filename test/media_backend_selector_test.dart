import 'package:flutter_test/flutter_test.dart';
import 'package:fourfun_cod_client/core/rtc/media_backend_selector.dart';

void main() {
  group('MediaBackendConfig', () {
    test('default é legacy com tudo desligado', () {
      const config = MediaBackendConfig.legacy;
      expect(config.effectiveBackend, MediaBackend.legacy);
      expect(config.mayOpenNativeCapture, isFalse);
      expect(config.mayOpenNativePlayback, isFalse);
    });

    test('backend native sem captura/playback cai para legacy', () {
      const config = MediaBackendConfig(
        backend: MediaBackend.flutterNativeAudio,
      );
      expect(config.effectiveBackend, MediaBackend.legacy);
    });

    test('caminho A resolve quando há captura native', () {
      const config = MediaBackendConfig(
        backend: MediaBackend.flutterNativeAudio,
        nativeAudioCapture: true,
      );
      expect(config.effectiveBackend, MediaBackend.flutterNativeAudio);
      expect(config.mayOpenNativeCapture, isTrue);
      expect(config.mayOpenNativePlayback, isFalse);
    });

    test('kill switch força legacy', () {
      const config = MediaBackendConfig(
        backend: MediaBackend.nativeLivekit,
        nativeAudioCapture: true,
        nativeAudioPlayback: true,
        killSwitch: true,
      );
      expect(config.effectiveBackend, MediaBackend.legacy);
      expect(config.mayOpenNativeCapture, isFalse);
    });

    test('toFlagMap expõe conjunto efetivo (sem segredos)', () {
      const config = MediaBackendConfig(
        backend: MediaBackend.flutterNativeAudio,
        nativeAudioCapture: true,
        nativeDiagnostics: true,
      );
      final flags = config.toFlagMap();
      expect(flags['media_backend_native'], isTrue);
      expect(flags['native_audio_capture'], isTrue);
      expect(flags['native_diagnostics'], isTrue);
      expect(flags['native_audio_playback'], isFalse);
      expect(flags.values, everyElement(isA<bool>()));
    });
  });
}
