import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fourfun_cod_client/core/rtc/media_devices_provider.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_providers.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_service.dart';

class _FakeRtcService implements RtcService {
  final devicesChanged = StreamController<void>.broadcast();
  List<RtcAudioDevice> inputs = const [];
  List<RtcAudioDevice> outputs = const [];
  List<RtcVideoDevice> cameras = const [];
  final List<String?> inputSelections = [];
  final List<String?> outputSelections = [];
  final List<String> cameraSelections = [];

  @override
  Stream<void> get mediaDevicesChanged => devicesChanged.stream;

  @override
  Future<List<RtcAudioDevice>> listAudioInputDevices() async => inputs;

  @override
  Future<List<RtcAudioDevice>> listAudioOutputDevices() async => outputs;

  @override
  Future<List<RtcVideoDevice>> listCameraDevices() async => cameras;

  @override
  Future<void> selectAudioInput(String? deviceId) async {
    inputSelections.add(deviceId);
  }

  @override
  Future<void> selectAudioOutput(String? deviceId) async {
    outputSelections.add(deviceId);
  }

  @override
  Future<void> switchCamera(String deviceId) async {
    cameraSelections.add(deviceId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('AudioDevicesController', () {
    late _FakeRtcService rtc;
    late ProviderContainer container;

    setUp(() {
      SharedPreferences.setMockInitialValues({
        'voice.preferred_audio_input_id': 'mic-usb',
      });
      rtc = _FakeRtcService()
        ..inputs = const [
          RtcAudioDevice(
            id: 'mic-usb',
            label: 'Microfone USB',
            kind: RtcMediaDeviceKind.audioInput,
          ),
        ]
        ..outputs = const [
          RtcAudioDevice(
            id: 'speaker',
            label: 'Alto-falante',
            kind: RtcMediaDeviceKind.audioOutput,
          ),
        ];
      container = ProviderContainer(
        overrides: [rtcServiceProvider.overrideWithValue(rtc)],
      );
    });

    tearDown(() {
      container.dispose();
      rtc.devicesChanged.close();
    });

    Future<void> settle() => pumpEventQueue();

    test(
      'restaura preferência, usa fallback e reaplica ao dispositivo voltar',
      () async {
        final subscription = container.listen(audioDevicesProvider, (_, _) {});
        addTearDown(subscription.close);
        await settle();

        expect(
          container.read(audioDevicesProvider).preferredInputId,
          'mic-usb',
        );
        expect(rtc.inputSelections.last, 'mic-usb');

        rtc.inputs = const [];
        rtc.devicesChanged.add(null);
        await settle();

        expect(
          container.read(audioDevicesProvider).preferredInputUnavailable,
          isTrue,
        );
        expect(rtc.inputSelections.last, isNull);

        rtc.inputs = const [
          RtcAudioDevice(
            id: 'mic-usb',
            label: 'Microfone USB',
            kind: RtcMediaDeviceKind.audioInput,
          ),
        ];
        rtc.devicesChanged.add(null);
        await settle();

        expect(
          container.read(audioDevicesProvider).preferredInputUnavailable,
          isFalse,
        );
        expect(rtc.inputSelections.last, 'mic-usb');
      },
    );

    test('salva seleção de saída localmente', () async {
      final subscription = container.listen(audioDevicesProvider, (_, _) {});
      addTearDown(subscription.close);
      await settle();

      expect(
        await container
            .read(audioDevicesProvider.notifier)
            .selectOutput('speaker'),
        isTrue,
      );

      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString('voice.preferred_audio_output_id'),
        'speaker',
      );
      expect(rtc.outputSelections.last, 'speaker');
    });
  });
}
