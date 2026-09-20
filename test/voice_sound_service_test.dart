import 'package:flutter_test/flutter_test.dart';
import 'package:fourfun_cod_client/core/sound/voice_sound_service.dart';

class _FakePlayer implements VoiceSoundPlayer {
  final List<({String asset, double volume})> plays = [];

  @override
  Future<void> play(String assetPath, {required double volume}) async {
    plays.add((asset: assetPath, volume: volume));
  }
}

void main() {
  group('VoiceSound assets', () {
    test('4 sons com paths distintos em sounds/', () {
      final paths = VoiceSound.values.map((s) => s.assetPath).toList();
      expect(paths.toSet().length, 4);
      for (final path in paths) {
        expect(path, startsWith('sounds/'));
        expect(path, endsWith('.wav'));
      }
      expect(VoiceSound.join.assetPath, 'sounds/voice_join.wav');
      expect(VoiceSound.leave.assetPath, 'sounds/voice_leave.wav');
      expect(VoiceSound.streamStart.assetPath, 'sounds/stream_start.wav');
      expect(VoiceSound.streamStop.assetPath, 'sounds/stream_stop.wav');
    });
  });

  group('VoiceSoundService', () {
    test('não toca quando desabilitado', () async {
      final player = _FakePlayer();
      final service = VoiceSoundService(player: player);
      await service.play(
        VoiceSound.join,
        enabled: false,
        deafened: false,
      );
      expect(player.plays, isEmpty);
    });

    test('não toca quando ensurdecido (deafen = mudo total)', () async {
      final player = _FakePlayer();
      final service = VoiceSoundService(player: player);
      await service.play(VoiceSound.join, enabled: true, deafened: true);
      await service.play(
        VoiceSound.streamStart,
        remote: true,
        enabled: true,
        deafened: true,
      );
      expect(player.plays, isEmpty);
    });

    test('local toca com volume cheio, remoto mais baixo', () async {
      final player = _FakePlayer();
      final service = VoiceSoundService(player: player);
      await service.play(VoiceSound.join, enabled: true, deafened: false);
      await service.play(
        VoiceSound.join,
        remote: true,
        enabled: true,
        deafened: false,
      );
      expect(player.plays.length, 2);
      expect(player.plays[0].volume, 1.0);
      expect(player.plays[1].volume, lessThan(1.0));
      expect(player.plays[0].asset, player.plays[1].asset);
    });

    test('debounce coalesca rajada remota do mesmo som', () async {
      var now = DateTime(2026, 1, 1);
      final player = _FakePlayer();
      final service = VoiceSoundService(
        player: player,
        clock: () => now,
      );
      await service.play(
        VoiceSound.join,
        remote: true,
        enabled: true,
        deafened: false,
      );
      await service.play(
        VoiceSound.join,
        remote: true,
        enabled: true,
        deafened: false,
      );
      expect(player.plays.length, 1);

      now = now.add(const Duration(milliseconds: 501));
      await service.play(
        VoiceSound.join,
        remote: true,
        enabled: true,
        deafened: false,
      );
      expect(player.plays.length, 2);
    });

    test('debounce é por som (join não suprime stream)', () async {
      final player = _FakePlayer();
      final service = VoiceSoundService(player: player);
      await service.play(
        VoiceSound.join,
        remote: true,
        enabled: true,
        deafened: false,
      );
      await service.play(
        VoiceSound.streamStart,
        remote: true,
        enabled: true,
        deafened: false,
      );
      expect(player.plays.length, 2);
    });

    test('local nunca sofre debounce', () async {
      final player = _FakePlayer();
      final service = VoiceSoundService(player: player);
      await service.play(VoiceSound.leave, enabled: true, deafened: false);
      await service.play(VoiceSound.leave, enabled: true, deafened: false);
      expect(player.plays.length, 2);
    });
  });

  group('VoiceSoundService sinais (ADR-0001)', () {
    test('sinal toca com volume remoto e registra supressão', () async {
      final player = _FakePlayer();
      final service = VoiceSoundService(player: player);
      await service.playSignal(
        VoiceSound.join,
        enabled: true,
        deafened: false,
      );
      expect(player.plays.length, 1);
      expect(player.plays.single.volume, lessThan(1.0));
      expect(service.shouldSuppressRemoteDiff(VoiceSound.join), isTrue);
      expect(service.shouldSuppressRemoteDiff(VoiceSound.leave), isFalse);
    });

    test('sinal respeita desabilitado e deafen, mas suprime mesmo assim', () async {
      final player = _FakePlayer();
      final service = VoiceSoundService(player: player);
      await service.playSignal(
        VoiceSound.leave,
        enabled: false,
        deafened: false,
      );
      await service.playSignal(
        VoiceSound.streamStart,
        enabled: true,
        deafened: true,
      );
      expect(player.plays, isEmpty);
      // O evento aconteceu: o fallback por diff continua suprimido.
      expect(service.shouldSuppressRemoteDiff(VoiceSound.leave), isTrue);
      expect(service.shouldSuppressRemoteDiff(VoiceSound.streamStart), isTrue);
    });

    test('cooldown de 2s coalesce sinais repetidos', () async {
      var now = DateTime(2026, 1, 1);
      final player = _FakePlayer();
      final service = VoiceSoundService(
        player: player,
        clock: () => now,
      );
      await service.playSignal(
        VoiceSound.join,
        enabled: true,
        deafened: false,
      );
      await service.playSignal(
        VoiceSound.join,
        enabled: true,
        deafened: false,
      );
      expect(player.plays.length, 1);

      now = now.add(const Duration(seconds: 2, milliseconds: 1));
      await service.playSignal(
        VoiceSound.join,
        enabled: true,
        deafened: false,
      );
      expect(player.plays.length, 2);
    });

    test('supressão expira após 2s (fallback volta a valer)', () async {
      var now = DateTime(2026, 1, 1);
      final player = _FakePlayer();
      final service = VoiceSoundService(
        player: player,
        clock: () => now,
      );
      await service.playSignal(
        VoiceSound.leave,
        enabled: true,
        deafened: false,
      );
      expect(service.shouldSuppressRemoteDiff(VoiceSound.leave), isTrue);
      now = now.add(const Duration(seconds: 2, milliseconds: 1));
      expect(service.shouldSuppressRemoteDiff(VoiceSound.leave), isFalse);
    });
  });
}
