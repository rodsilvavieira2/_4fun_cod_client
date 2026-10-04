import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fourfun_cod_client/core/native/native_media_backend.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_providers.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_service.dart';
import 'package:fourfun_cod_client/core/telemetry/telemetry_service.dart';
import 'package:fourfun_cod_client/features/servers/servers_providers.dart';
import 'package:fourfun_cod_client/features/voice/voice_providers.dart';

import 'screen_share_window_waiter_test.dart'
    show FakeWindowBackend, target, readyWindow, minimizedWindow;
import 'voice_controller_test.dart' show FakeRtcService, FakeServersRepository;

class _DelayedRtc extends FakeRtcService
    implements RtcScreenShareSourceSwitcher {
  Completer<void>? releaseStart;
  void Function()? beforeStart;
  final replacementSources = <String>[];
  @override
  Future<void> startScreenShare(
    String? sourceId, {
    bool includeSystemAudio = true,
    RtcScreenShareQuality? quality,
  }) async {
    beforeStart?.call();
    if (releaseStart != null) await releaseStart!.future;
    await super.startScreenShare(
      sourceId,
      includeSystemAudio: includeSystemAudio,
      quality: quality,
    );
  }

  @override
  Future<void> replaceScreenShareSource(String sourceId) async {
    replacementSources.add(sourceId);
  }
}

class _Telemetry implements TelemetryService {
  final events = <({String name, Map<String, String> attributes})>[];
  @override
  void logEvent(String name, {Map<String, String>? attributes}) {
    events.add((name: name, attributes: attributes ?? {}));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  const arg = (serverId: 's1', channelId: 'c1');
  late ProviderContainer container;
  late VoiceController voice;
  late _DelayedRtc rtc;
  late FakeWindowBackend backend;
  late _Telemetry telemetry;
  VoiceState state() => container.read(voiceControllerProvider(arg));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    rtc = _DelayedRtc()..localId = 'local';
    backend = FakeWindowBackend();
    telemetry = _Telemetry();
    container = ProviderContainer(
      overrides: [
        rtcServiceProvider.overrideWithValue(rtc),
        telemetryServiceProvider.overrideWithValue(telemetry),
        serversRepositoryProvider.overrideWithValue(FakeServersRepository()),
        nativeMediaServicesProvider.overrideWithValue(
          NativeMediaServices(
            screenShare: backend,
            camera: const LinuxCameraBackend(),
            audioDevices: const LinuxAudioDevicesBackend(),
          ),
        ),
      ],
    );
    final subscription = container.listen(
      voiceControllerProvider(arg),
      (_, _) {},
    );
    addTearDown(subscription.close);
    voice = container.read(voiceControllerProvider(arg).notifier);
    await voice.join();
  });
  tearDown(() => container.dispose());

  test(
    'minimizada publica preto imediatamente e troca na primeira restauração',
    () async {
      final pending = voice.startScreenShare(
        null,
        windowTarget: target,
        attemptId: 'attempt-minimized',
        includeSystemAudio: false,
        quality: RtcScreenShareQuality.q1080p60,
      );
      await pumpEventQueue();
      expect(state().isScreenSharing, isTrue);
      expect(state().isScreenSharePending, isFalse);
      expect(rtc.startScreenShareSources, [windowsBlackScreenShareSourceId]);
      await voice.startScreenShare(null, windowTarget: target);
      backend.window = readyWindow;
      await pending;
      expect(rtc.replacementSources, ['123']);
      expect(rtc.startScreenShareSystemAudioFlags, [false]);
      expect(rtc.startScreenShareQualities, [RtcScreenShareQuality.q1080p60]);
      expect(state().isScreenSharing, isTrue);
      expect(state().isScreenSharePending, isFalse);
      expect(telemetry.events.map((e) => e.name), [
        'screen_share.start.started',
        'screen_share.start.ready',
        'screen_share.start.restored',
      ]);
      for (final event in telemetry.events) {
        expect(event.attributes['attempt_id'], 'attempt-minimized');
        expect(
          event.attributes.keys.toSet().difference({
            'attempt_id',
            'duration_ms',
            'audio_failed',
            'placeholder',
          }),
          isEmpty,
        );
      }
    },
  );

  test('cancelamento encerra o preto e não restaura depois', () async {
    final pending = voice.startScreenShare(null, windowTarget: target);
    await pumpEventQueue();
    voice.cancelPendingScreenShare();
    backend.window = readyWindow;
    await pending;
    expect(rtc.startScreenShareSources, [windowsBlackScreenShareSourceId]);
    expect(rtc.replacementSources, isEmpty);
    expect(rtc.stopScreenShareCalls, 1);
    expect(state().isScreenSharePending, isFalse);
    expect(state().errorMessage, isNull);
  });

  test('botão de parar encerra transmissão preta', () async {
    final pending = voice.startScreenShare(null, windowTarget: target);
    await pumpEventQueue();
    expect(state().isScreenSharing, isTrue);
    await voice.stopScreenShare();
    await pending;
    expect(rtc.stopScreenShareCalls, 1);
    expect(state().isScreenSharing, isFalse);
  });

  test('janela fechada após o início encerra o preto', () async {
    final pending = voice.startScreenShare(null, windowTarget: target);
    await pumpEventQueue();
    backend.window = const NativeShareWindowState(
      valid: false,
      visible: false,
      minimized: false,
      foreground: false,
    );
    await pending;
    expect(rtc.stopScreenShareCalls, 1);
    expect(state().isScreenSharing, isFalse);
    expect(state().errorMessage, contains('fechada'));
  });

  test('janela pronta inicia sem placeholder', () async {
    backend.window = readyWindow;
    await voice.startScreenShare(null, windowTarget: target);
    expect(rtc.startScreenShareSources, ['123']);
    expect(rtc.replacementSources, isEmpty);
    expect(state().isScreenSharing, isTrue);
  });

  test('leave cancela e não muda a sessão depois de restaurar', () async {
    final pending = voice.startScreenShare(null, windowTarget: target);
    await pumpEventQueue();
    await voice.leave();
    backend.window = readyWindow;
    await pending;
    expect(state().status, VoiceSessionStatus.idle);
    expect(rtc.replacementSources, isEmpty);
  });

  test('descarte do controller cancela consulta nativa em voo', () async {
    final response = Completer<NativeShareWindowState>();
    backend.onRead = () => response.future;
    final pending = voice.startScreenShare(null, windowTarget: target);
    await pumpEventQueue();
    container.invalidate(voiceControllerProvider(arg));
    response.complete(readyWindow);
    await pending;
    expect(rtc.startScreenShareCalls, 0);
  });

  for (final event in <RtcEvent>[
    const DisconnectedEvent(),
    const ReconnectingEvent(),
    const ReconnectedEvent(),
  ]) {
    test('${event.runtimeType} cancela espera', () async {
      final pending = voice.startScreenShare(null, windowTarget: target);
      await pumpEventQueue();
      rtc.eventsController.add(event);
      await pumpEventQueue();
      backend.window = readyWindow;
      await pending;
      expect(rtc.replacementSources, isEmpty);
      expect(state().isScreenSharePending, isFalse);
    });
  }

  test('fechamento mostra erro amigável sem publicar', () async {
    backend.window = const NativeShareWindowState(
      valid: false,
      visible: false,
      minimized: false,
      foreground: false,
    );
    await voice.startScreenShare(null, windowTarget: target);
    expect(rtc.startScreenShareCalls, 0);
    expect(state().errorMessage, contains('fechada'));
    expect(state().isScreenSharePending, isFalse);
  });

  test('cancelamento durante publish desfaz publicação tardia', () async {
    backend.window = readyWindow;
    rtc.releaseStart = Completer<void>();
    final pending = voice.startScreenShare(null, windowTarget: target);
    await pumpEventQueue();
    voice.cancelPendingScreenShare();
    rtc.releaseStart!.complete();
    await pending;
    expect(rtc.startScreenShareCalls, 1);
    expect(rtc.stopScreenShareCalls, 1);
    expect(state().isScreenSharing, isFalse);
    expect(state().isScreenSharePending, isFalse);
    expect(rtc.publishedSounds, isNot(contains(RtcVoiceSound.streamStart)));
  });

  test('Alt+Tab na criação publica preto e preserva opções', () async {
    backend.window = readyWindow;
    rtc.failStartScreenShareTimes = 1;
    var attempts = 0;
    rtc.beforeStart = () {
      if (++attempts == 1) backend.window = minimizedWindow;
    };
    final pending = voice.startScreenShare(
      null,
      windowTarget: target,
      includeSystemAudio: false,
    );
    await pumpEventQueue();
    expect(state().isScreenSharing, isTrue);
    expect(state().isScreenSharePending, isFalse);
    backend.window = readyWindow;
    await pending;
    expect(attempts, 2);
    expect(rtc.startScreenShareSources, [windowsBlackScreenShareSourceId]);
    expect(rtc.replacementSources, ['123']);
    expect(rtc.startScreenShareSystemAudioFlags, [false]);
  });
}
