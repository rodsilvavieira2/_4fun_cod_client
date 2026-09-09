import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/core/native/native_media_backend.dart';
import 'package:fourfun_cod_client/features/voice/push_to_talk.dart';
import 'package:fourfun_cod_client/features/voice/push_to_talk_backend.dart';
import 'package:fourfun_cod_client/features/voice/push_to_talk_input.dart';

class _FakePushToTalkBackend implements PushToTalkBackend {
  final eventsController = StreamController<PushToTalkInputEvent>.broadcast();
  PushToTalkBinding? configuredBinding;
  PushToTalkConfigResult registrationResult = const PushToTalkConfigResult.ok();

  @override
  Stream<PushToTalkInputEvent> get events => eventsController.stream;

  @override
  Future<PushToTalkConfigResult> configure(PushToTalkBinding? binding) async {
    configuredBinding = binding;
    return registrationResult;
  }
}

void main() {
  group('DefaultNativeMediaServicesFactory', () {
    const factory = DefaultNativeMediaServicesFactory();

    test('seleciona portal e captura Linux', () async {
      final services = factory.create(AppRuntimePlatform.linux);

      expect(services.screenShare, isA<LinuxScreenShareBackend>());
      expect(services.camera, isA<LinuxCameraBackend>());
      expect(services.audioDevices, isA<LinuxAudioDevicesBackend>());
      expect(services.screenShare.capabilities.usesSystemPicker, isTrue);
      expect(await services.screenShare.loadSources(), isEmpty);
    });

    test('seleciona fontes Windows e mantém contratos separados', () {
      final services = factory.create(AppRuntimePlatform.windows);

      expect(services.screenShare, isA<WindowsScreenShareBackend>());
      expect(services.camera, isA<WindowsCameraBackend>());
      expect(services.audioDevices, isA<WindowsAudioDevicesBackend>());
      expect(services.screenShare.capabilities.usesSystemPicker, isFalse);
      expect(services.screenShare.capabilities.supportsWindowSources, isTrue);
    });
  });

  test('factory de PTT seleciona o adapter desktop por plataforma', () {
    const factory = DefaultPushToTalkBackendFactory();

    expect(
      factory.create(AppRuntimePlatform.linux),
      isA<LinuxPushToTalkBackend>(),
    );
    expect(
      factory.create(AppRuntimePlatform.windows),
      isA<WindowsPushToTalkBackend>(),
    );
  });

  test(
    'PushToTalkInputService delega configuração e eventos ao backend',
    () async {
      final backend = _FakePushToTalkBackend();
      addTearDown(backend.eventsController.close);
      final service = PushToTalkInputService(backend: backend);
      const binding = PushToTalkBinding.mouse(
        mouseButton: 4,
        label: 'Botão do meio',
      );

      expect((await service.configure(binding)).isOk, isTrue);
      expect(backend.configuredBinding, binding);
      expectLater(service.events, emits(PushToTalkInputEvent.pressed));

      backend.eventsController.add(PushToTalkInputEvent.pressed);
    },
  );
}
