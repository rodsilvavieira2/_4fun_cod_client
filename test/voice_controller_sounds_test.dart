import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fourfun_cod_client/core/rtc/rtc_providers.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_service.dart';
import 'package:fourfun_cod_client/core/sound/voice_sound_provider.dart';
import 'package:fourfun_cod_client/core/sound/voice_sound_service.dart';
import 'package:fourfun_cod_client/features/servers/servers_providers.dart';
import 'package:fourfun_cod_client/features/servers/servers_repository.dart';
import 'package:fourfun_cod_client/features/voice/voice_providers.dart';
import 'package:fourfun_cod_client/shared/models/voice.dart';

class _RecordingSoundService extends VoiceSoundService {
  _RecordingSoundService() : super(player: _NullPlayer());

  final List<({VoiceSound sound, bool remote})> calls = [];

  /// Sinais recebidos (registra a chamada mesmo sob cooldown — cada teste
  /// envia o sinal uma única vez; o cooldown em si é coberto no teste
  /// unitário do serviço).
  final List<VoiceSound> signalCalls = [];

  @override
  Future<void> play(
    VoiceSound sound, {
    bool remote = false,
    required bool enabled,
    required bool deafened,
  }) async {
    if (!enabled || deafened) return;
    calls.add((sound: sound, remote: remote));
  }

  @override
  Future<void> playSignal(
    VoiceSound sound, {
    required bool enabled,
    required bool deafened,
  }) async {
    await super.playSignal(sound, enabled: enabled, deafened: deafened);
    signalCalls.add(sound);
  }
}

class _NullPlayer implements VoiceSoundPlayer {
  @override
  Future<void> play(String assetPath, {required double volume}) async {}
}

class _FakeRtc implements RtcService {
  final participantsController =
      StreamController<List<RtcParticipant>>.broadcast();
  final eventsController = StreamController<RtcEvent>.broadcast();

  String? localId = 'user_u1';

  @override
  String? get localParticipantId => localId;

  @override
  Stream<List<RtcParticipant>> get participants =>
      participantsController.stream;

  @override
  Stream<RtcEvent> get events => eventsController.stream;

  @override
  Future<void> connect(String url, String token, {tokenGenerator}) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> enableMicrophone() async {}

  @override
  Future<void> disableMicrophone() async {}

  @override
  Future<void> setRemoteAudioEnabled(bool enabled) async {}

  @override
  Future<void> startScreenShare(
    String? sourceId, {
    bool includeSystemAudio = true,
    RtcScreenShareQuality? quality,
  }) async {}

  @override
  Future<void> stopScreenShare() async {}

  @override
  RtcScreenShareQuality get screenShareQuality => RtcScreenShareQuality.auto;

  @override
  RtcScreenShareQuality get effectiveScreenShareQuality =>
      RtcScreenShareQuality.auto;

  final List<RtcVoiceSound> publishedSounds = [];

  @override
  Future<void> publishVoiceSound(RtcVoiceSound sound) async {
    publishedSounds.add(sound);
  }

  @override
  Future<RtcNoiseSuppressionStatus> setNoiseSuppressionMode(
    RtcNoiseSuppressionMode mode,
  ) async => RtcNoiseSuppressionStatus(
    requestedMode: mode,
    effectiveMode: mode,
    deepFilterNetAvailable: false,
  );

  @override
  Future<List<RtcVideoDevice>> listCameraDevices() async => const [];

  @override
  Future<List<RtcAudioDevice>> listAudioInputDevices() async => const [];

  @override
  Future<List<RtcAudioDevice>> listAudioOutputDevices() async => const [];

  @override
  Stream<void> get mediaDevicesChanged => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRepo implements ServersRepository {
  @override
  Future<VoiceJoinInfo> joinVoice(String serverId, String channelId) async =>
      const VoiceJoinInfo(
        livekitUrl: 'wss://livekit.test',
        token: 'token-1',
        roomName: 'ch_c1',
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _arg = (serverId: 's1', channelId: 'c1');

RtcParticipant _p(String id, String name, {bool screenShare = false}) =>
    RtcParticipant(
      id: id,
      name: name,
      isMicrophoneEnabled: true,
      isCameraEnabled: false,
      isScreenSharing: screenShare,
      isSystemAudioEnabled: false,
      isSpeaking: false,
    );

void main() {
  group('VoiceController sounds', () {
    late ProviderContainer container;
    late _FakeRtc rtc;
    late _RecordingSoundService sounds;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      rtc = _FakeRtc();
      sounds = _RecordingSoundService();
      container = ProviderContainer(
        overrides: [
          serversRepositoryProvider.overrideWithValue(_FakeRepo()),
          rtcServiceProvider.overrideWithValue(rtc),
          voiceSoundServiceProvider.overrideWithValue(sounds),
        ],
      );
    });

    tearDown(() => container.dispose());

    VoiceController buildVoice() {
      final sub = container.listen(voiceControllerProvider(_arg), (_, _) {});
      addTearDown(sub.close);
      return container.read(voiceControllerProvider(_arg).notifier);
    }

    Future<void> settle() => pumpEventQueue(times: 20);

    test('join toca som local e leave toca som local', () async {
      final notifier = buildVoice();
      await notifier.join();
      await settle();
      expect(
        sounds.calls.any((c) => c.sound == VoiceSound.join && !c.remote),
        isTrue,
      );

      await notifier.leave();
      await settle();
      expect(
        sounds.calls.any((c) => c.sound == VoiceSound.leave && !c.remote),
        isTrue,
      );
    });

    test('remoto entrando/saindo toca join/leave remoto (baseline pula)', () async {
      final notifier = buildVoice();
      await notifier.join();
      await settle();
      sounds.calls.clear();

      // Baseline: eu + remota já na sala → sem som remoto.
      rtc.participantsController.add([_p('user_u1', 'eu'), _p('user_u2', 'b')]);
      await settle();
      expect(sounds.calls, isEmpty);

      // Remota nova entra → join remoto.
      rtc.participantsController.add([
        _p('user_u1', 'eu'),
        _p('user_u2', 'b'),
        _p('user_u3', 'c'),
      ]);
      await settle();
      expect(
        sounds.calls.any((c) => c.sound == VoiceSound.join && c.remote),
        isTrue,
      );
      sounds.calls.clear();

      // Remota sai → leave remoto.
      rtc.participantsController.add([_p('user_u1', 'eu'), _p('user_u2', 'b')]);
      await settle();
      expect(
        sounds.calls.any((c) => c.sound == VoiceSound.leave && c.remote),
        isTrue,
      );
      expect(notifier, isNotNull);
    });

    test('stream remoto start/stop toca sons remotos', () async {
      final notifier = buildVoice();
      await notifier.join();
      await settle();
      rtc.participantsController.add([_p('user_u1', 'eu'), _p('user_u2', 'b')]);
      await settle();
      sounds.calls.clear();

      rtc.participantsController.add([
        _p('user_u1', 'eu'),
        _p('user_u2', 'b', screenShare: true),
      ]);
      await settle();
      expect(
        sounds.calls.any((c) => c.sound == VoiceSound.streamStart && c.remote),
        isTrue,
      );
      sounds.calls.clear();

      rtc.participantsController.add([_p('user_u1', 'eu'), _p('user_u2', 'b')]);
      await settle();
      expect(
        sounds.calls.any((c) => c.sound == VoiceSound.streamStop && c.remote),
        isTrue,
      );
      expect(notifier, isNotNull);
    });

    test('start/stop locais tocam sons locais', () async {
      final notifier = buildVoice();
      await notifier.join();
      await settle();
      sounds.calls.clear();

      await notifier.startScreenShare(null);
      await settle();
      expect(
        sounds.calls.any((c) => c.sound == VoiceSound.streamStart && !c.remote),
        isTrue,
      );
      sounds.calls.clear();

      await notifier.stopScreenShare();
      await settle();
      expect(
        sounds.calls.any((c) => c.sound == VoiceSound.streamStop && !c.remote),
        isTrue,
      );
    });

    test('DisconnectedEvent toca leave local', () async {
      buildVoice();
      final notifier = container.read(voiceControllerProvider(_arg).notifier);
      await notifier.join();
      await settle();
      sounds.calls.clear();

      rtc.eventsController.add(const DisconnectedEvent());
      await settle();
      expect(
        sounds.calls.any((c) => c.sound == VoiceSound.leave && !c.remote),
        isTrue,
      );
    });

    test('ações locais publicam sinal para a sala', () async {
      final notifier = buildVoice();
      await notifier.join();
      await settle();
      expect(rtc.publishedSounds, contains(RtcVoiceSound.join));

      await notifier.startScreenShare(null);
      await settle();
      expect(rtc.publishedSounds, contains(RtcVoiceSound.streamStart));

      await notifier.stopScreenShare();
      await settle();
      expect(rtc.publishedSounds, contains(RtcVoiceSound.streamStop));

      await notifier.leave();
      await settle();
      expect(rtc.publishedSounds, contains(RtcVoiceSound.leave));
    });

    test('sinal recebido de outro toca som remoto', () async {
      buildVoice();
      final notifier = container.read(voiceControllerProvider(_arg).notifier);
      await notifier.join();
      await settle();
      sounds.calls.clear();

      rtc.eventsController.add(
        const VoiceSoundSignalEvent(
          participantId: 'user_u2',
          sound: RtcVoiceSound.streamStart,
        ),
      );
      await settle();
      expect(sounds.signalCalls, contains(VoiceSound.streamStart));
    });

    test('eco próprio é ignorado', () async {
      buildVoice();
      final notifier = container.read(voiceControllerProvider(_arg).notifier);
      await notifier.join();
      await settle();
      final before = sounds.calls.length;

      rtc.eventsController.add(
        const VoiceSoundSignalEvent(
          participantId: 'user_u1',
          sound: RtcVoiceSound.join,
        ),
      );
      await settle();
      expect(sounds.calls.length, before);
    });

    test('sinal suprime o fallback por diff (sem som duplo)', () async {
      buildVoice();
      final notifier = container.read(voiceControllerProvider(_arg).notifier);
      await notifier.join();
      await settle();
      rtc.participantsController.add([_p('user_u1', 'eu'), _p('user_u2', 'b')]);
      await settle();
      sounds.calls.clear();

      // Cliente novo anuncia; o snapshot com o entrante chega em seguida.
      rtc.eventsController.add(
        const VoiceSoundSignalEvent(
          participantId: 'user_u3',
          sound: RtcVoiceSound.join,
        ),
      );
      await settle();
      expect(sounds.signalCalls, [VoiceSound.join]);
      final diffPlays = sounds.calls.length;

      rtc.participantsController.add([
        _p('user_u1', 'eu'),
        _p('user_u2', 'b'),
        _p('user_u3', 'c'),
      ]);
      await settle();
      // Nenhum som extra do diff: o sinal já cobriu.
      expect(sounds.calls.length, diffPlays);
      expect(notifier, isNotNull);
    });
  });
}
