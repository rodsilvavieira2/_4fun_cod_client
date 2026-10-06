import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fourfun_cod_client/core/native/media/media_bridge.dart';
import 'package:fourfun_cod_client/core/rtc/media_backend_selector.dart';
import 'package:fourfun_cod_client/core/rtc/native_rtc_service.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_service.dart';

/// Fake mínimo do transporte: registra chamadas, sem rede/hardware.
class FakeTransport implements RtcService {
  var connectCalls = 0;
  var disconnectCalls = 0;
  var micEnabled = false;
  var outputGain = 1.0;
  final _participants = StreamController<List<RtcParticipant>>.broadcast();
  final _events = StreamController<RtcEvent>.broadcast();

  @override
  Future<void> connect(
    String url,
    String token, {
    RtcTokenGenerator? tokenGenerator,
  }) async {
    connectCalls++;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
  }

  @override
  Future<void> enableMicrophone() async {
    micEnabled = true;
  }

  @override
  Future<void> disableMicrophone() async {
    micEnabled = false;
  }

  @override
  Future<void> enableCamera() async {}

  @override
  Future<void> disableCamera() async {}

  @override
  Future<RtcVideoTrackRef> startCameraPreview({String? deviceId}) =>
      throw UnimplementedError();

  @override
  Future<void> stopCameraPreview() async {}

  @override
  Future<void> startScreenShare(
    String? sourceId, {
    bool includeSystemAudio = true,
    RtcScreenShareQuality? quality,
  }) async {}

  @override
  Future<void> stopScreenShare() async {}

  @override
  RtcVideoTrackRef? screenTrackOf(String participantId) => null;

  @override
  Future<void> setQuality(String participantId, RtcVideoQuality quality) async {}

  @override
  Future<List<RtcVideoDevice>> listCameraDevices() async => const [];

  @override
  Future<List<RtcAudioDevice>> listAudioInputDevices() async => const [];

  @override
  Future<List<RtcAudioDevice>> listAudioOutputDevices() async => const [];

  @override
  Stream<void> get mediaDevicesChanged => const Stream.empty();

  @override
  Future<void> selectAudioInput(String? deviceId) async {}

  @override
  Future<void> selectAudioOutput(String? deviceId) async {}

  @override
  Future<void> setRemoteAudioEnabled(bool enabled) async {}

  @override
  Future<void> setOutputVolume(double gain) async {
    outputGain = gain;
  }

  @override
  Future<void> setInputVolume(double gain) async {}

  @override
  Future<RtcNoiseSuppressionStatus> setNoiseSuppressionMode(
    RtcNoiseSuppressionMode mode,
  ) async => RtcNoiseSuppressionStatus(
    requestedMode: mode,
    effectiveMode: mode,
    deepFilterNetAvailable: false,
  );

  @override
  Future<void> setParticipantVolume(String identity, double gain) async {}

  @override
  Future<void> setParticipantSourceVolume(
    String identity,
    RtcAudioSource source,
    double gain,
  ) async {}

  // Herdados com default no-op no contrato; implementados aqui para o
  // analyzer não exigir corpo concreto no fake.
  @override
  Future<void> setScreenQuality(
    String participantId,
    RtcVideoQuality quality,
  ) async {}

  @override
  Future<void> setScreenShareAudioEnabled(String identity, bool enabled) async {}

  @override
  Future<void> publishVoiceSound(RtcVoiceSound sound) async {}

  @override
  Future<void> switchCamera(String deviceId) async {}

  @override
  Future<void> setScreenShareQuality(RtcScreenShareQuality quality) async {}

  @override
  RtcScreenShareQuality get screenShareQuality =>
      RtcScreenShareQuality.auto;

  @override
  RtcScreenShareQuality get effectiveScreenShareQuality =>
      RtcScreenShareQuality.auto;

  @override
  Future<void> resumeAudio() async {}

  @override
  RtcVideoTrackRef? videoTrackOf(String participantId) => null;

  @override
  String? get localParticipantId => null;

  @override
  Stream<List<RtcParticipant>> get participants => _participants.stream;

  @override
  Stream<RtcEvent> get events => _events.stream;
}

NativeRtcService _service(FakeTransport transport) => NativeRtcService(
  inner: transport,
  bridge: InMemoryMediaBridge(),
  config: const MediaBackendConfig(
    backend: MediaBackend.flutterNativeAudio,
    nativeAudioCapture: true,
  ),
);

void main() {
  group('NativeRtcService (caminho A)', () {
    test('connect abre engine + transporte; mute espelha no engine',
        () async {
      final transport = FakeTransport();
      final service = _service(transport);

      await service.connect('ws://localhost:7880', 'token');
      expect(transport.connectCalls, 1);

      var snapshot = await service.currentSnapshot();
      expect(snapshot.generation, 1);

      await service.disableMicrophone();
      expect(transport.micEnabled, isFalse);
      snapshot = await service.currentSnapshot();
      expect(snapshot.muted, isTrue);
      expect(snapshot.mayTransmit, isFalse);

      await service.enableMicrophone();
      expect(transport.micEnabled, isTrue);
      expect((await service.currentSnapshot()).mayTransmit, isTrue);

      await service.disconnect();
      expect(transport.disconnectCalls, 1);
      await service.dispose();
    });

    test('volumes espelham engine + transporte; dispose idempotente',
        () async {
      final transport = FakeTransport();
      final service = _service(transport);

      await service.setOutputVolume(1.5);
      expect(transport.outputGain, 1.5);
      expect((await service.currentSnapshot()).outputGain, 1.5);

      await service.setNoiseSuppressionMode(RtcNoiseSuppressionMode.studio);
      expect(
        (await service.currentSnapshot()).requestedDsp,
        'studio',
      );

      await service.dispose();
      await service.dispose(); // idempotente, sem throw
    });
  });
}
