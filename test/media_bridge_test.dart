import 'package:flutter_test/flutter_test.dart';
import 'package:fourfun_cod_client/core/native/media/media_bridge.dart';

Future<EngineHandle> _create(MediaBridge bridge) =>
    bridge.createEngine(flags: const {'media_backend_native': true});

void main() {
  group('InMemoryMediaBridge', () {
    test('join abre geração e mute bloqueia TX (fail-closed)', () async {
      final bridge = InMemoryMediaBridge();
      final handle = await _create(bridge);
      await bridge.submit(
        handle,
        context: const CommandContext(requestId: 'j1', generation: 0),
        command: MediaCommand.join(
          channelId: 'ch',
          startMuted: true,
        ),
      );
      var snapshot = await bridge.snapshot(handle);
      expect(snapshot.generation, 1);
      expect(snapshot.mayTransmit, isFalse);

      await bridge.submit(
        handle,
        context: const CommandContext(requestId: 'u1', generation: 1),
        command: const MediaCommand.setMute(false),
      );
      snapshot = await bridge.snapshot(handle);
      expect(snapshot.mayTransmit, isTrue);
    });

    test('geração antiga é rejeitada', () async {
      final bridge = InMemoryMediaBridge();
      final handle = await _create(bridge);
      await bridge.submit(
        handle,
        context: const CommandContext(requestId: 'j', generation: 0),
        command: MediaCommand.join(
          channelId: 'ch',
          startMuted: false,
        ),
      );
      expect(
        bridge.submit(
          handle,
          context: const CommandContext(requestId: 'old', generation: 0),
          command: const MediaCommand.setMute(true),
        ),
        throwsStateError,
      );
    });

    test('request duplicado não reenfileira (dedup)', () async {
      final bridge = InMemoryMediaBridge();
      final handle = await _create(bridge);
      const ctx = CommandContext(requestId: 'dup', generation: 0);
      final cmd = MediaCommand.join(channelId: 'ch', startMuted: true);
      final first = await bridge.submit(handle, context: ctx, command: cmd);
      final second = await bridge.submit(handle, context: ctx, command: cmd);
      expect(first.accepted, isTrue);
      expect(second.accepted, isTrue);
      final snapshot = await bridge.snapshot(handle);
      // Um único join aplicado: geração 1, não 2.
      expect(snapshot.generation, 1);
    });

    test('deafen bloqueia e PTT exige pressionar', () async {
      final bridge = InMemoryMediaBridge();
      final handle = await _create(bridge);
      Future<void> submit(String id, MediaCommand cmd, [int gen = 1]) =>
          bridge.submit(
            handle,
            context: CommandContext(requestId: id, generation: gen),
            command: cmd,
          );
      await submit(
        'j',
        MediaCommand.join(channelId: 'ch', startMuted: false),
        0,
      );
      await submit('ptt-on', const MediaCommand.setPttMode(true));
      expect((await bridge.snapshot(handle)).mayTransmit, isFalse);
      await submit(
        'ptt-press',
        MediaCommand.setPttPressed(pressed: true, seq: 1),
      );
      expect((await bridge.snapshot(handle)).mayTransmit, isTrue);
      await submit('deafen', const MediaCommand.setDeafen(true));
      expect((await bridge.snapshot(handle)).mayTransmit, isFalse);
    });

    test('selectInput incrementa epoch; ganhos com clamp', () async {
      final bridge = InMemoryMediaBridge();
      final handle = await _create(bridge);
      await bridge.submit(
        handle,
        context: const CommandContext(requestId: 'j', generation: 0),
        command: MediaCommand.join(
          channelId: 'ch',
          startMuted: true,
        ),
      );
      await bridge.submit(
        handle,
        context: const CommandContext(requestId: 's', generation: 1),
        command: const MediaCommand.selectInput('mic-1'),
      );
      await bridge.submit(
        handle,
        context: const CommandContext(requestId: 'g', generation: 1),
        command: const MediaCommand.setOutputGain(99.0),
      );
      final snapshot = await bridge.snapshot(handle);
      expect(snapshot.deviceEpoch, 1);
      expect(snapshot.outputGain, 2.0);
    });

    test('eventos fluem e dispose invalida o handle', () async {
      final bridge = InMemoryMediaBridge();
      final handle = await _create(bridge);
      final future = bridge.events(handle).first;
      await bridge.submit(
        handle,
        context: const CommandContext(requestId: 'j', generation: 0),
        command: MediaCommand.join(
          channelId: 'ch',
          startMuted: true,
        ),
      );
      final event = await future;
      expect(event.kind, 'command_applied');
      expect(event.requestId, 'j');

      await bridge.disposeEngine(handle);
      expect(bridge.snapshot(handle), throwsStateError);
    });
  });
}
