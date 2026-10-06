import 'package:flutter_test/flutter_test.dart';
import 'package:fourfun_cod_client/core/native/media/media_bridge.dart';
import 'package:fourfun_cod_client/core/native/media/media_state_mapper.dart';

EngineSnapshot _snapshot({String requested = 'basic', String effective = 'basic'}) =>
    EngineSnapshot(
      generation: 1,
      stateRevision: 3,
      muted: false,
      deafened: false,
      pttEnabled: false,
      mayTransmit: true,
      inputGain: 1.0,
      outputGain: 1.0,
      requestedDsp: requested,
      effectiveDsp: effective,
      deviceEpoch: 0,
      flags: const {},
    );

void main() {
  group('media_state_mapper', () {
    test('badge honesto: nunca Studio com efetivo abaixo', () {
      final degraded = projectSnapshotToUi(
        _snapshot(requested: 'studio', effective: 'basic'),
      );
      expect(degraded.dspDegraded, isTrue);
      expect(degraded.dspBadge, 'basic');

      final ok = projectSnapshotToUi(
        _snapshot(requested: 'studio', effective: 'studio'),
      );
      expect(ok.dspDegraded, isFalse);
      expect(ok.dspBadge, 'Studio');
    });

    test('eventos silenciosos retornam null; degradação descreve', () {
      expect(
        describeEventForUi(
          const NativeEvent(
            kind: 'command_applied',
            generation: 1,
            stateRevision: 1,
          ),
        ),
        isNull,
      );
      expect(
        describeEventForUi(
          const NativeEvent(
            kind: 'dsp_degraded',
            generation: 1,
            stateRevision: 1,
          ),
        ),
        contains('DSP'),
      );
      expect(
        describeEventForUi(
          const NativeEvent(
            kind: 'ptt_expired',
            generation: 1,
            stateRevision: 1,
          ),
        ),
        contains('Push-to-talk'),
      );
    });
  });
}
