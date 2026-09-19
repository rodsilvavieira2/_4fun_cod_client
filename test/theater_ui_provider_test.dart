import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/features/voice/theater/theater_ui_provider.dart';

void main() {
  group('TheaterUiController', () {
    const arg = (serverId: 's1', channelId: 'c1');
    late ProviderContainer container;

    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    TheaterUiState read() => container.read(theaterUiControllerProvider(arg));
    TheaterUiController notifier() =>
        container.read(theaterUiControllerProvider(arg).notifier);

    test('entrada sempre em default/auto/vazio com participantes visíveis', () {
      final state = read();
      expect(state.viewMode, TheaterViewMode.defaultMode);
      expect(state.layout, TheaterLayoutMode.auto);
      expect(state.pinnedStreamIds, isEmpty);
      expect(state.showParticipants, isTrue);
      expect(state.hideOverlays, isFalse);
      expect(state.chatOpen, isFalse);
      expect(state.effectiveLayout, TheaterLayoutMode.auto);
    });

    test('enter/exit theater não toca nos pins', () {
      notifier()
        ..togglePin('u1:screen')
        ..enterTheater();
      expect(read().viewMode, TheaterViewMode.theater);
      expect(read().pinnedStreamIds, ['u1:screen']);

      notifier().exitTheater();
      expect(read().viewMode, TheaterViewMode.defaultMode);
      expect(read().pinnedStreamIds, ['u1:screen']);
    });

    test('togglePin mantém ordem de pin e alterna', () {
      notifier()
        ..togglePin('u1:camera')
        ..togglePin('u2:screen')
        ..togglePin('u1:camera');
      expect(read().pinnedStreamIds, ['u2:screen']);
      expect(read().effectiveLayout, TheaterLayoutMode.focus);
    });

    test('prune remove stream terminada e vazio volta ao auto', () {
      notifier()
        ..togglePin('u1:screen')
        ..togglePin('u2:screen')
        ..prunePins({'u2:screen'});
      expect(read().pinnedStreamIds, ['u2:screen']);

      notifier().prunePins({});
      expect(read().pinnedStreamIds, isEmpty);
      expect(read().effectiveLayout, TheaterLayoutMode.auto);
    });

    test('layout grid com pins ainda resolve para focus efetivo', () {
      notifier()
        ..setLayout(TheaterLayoutMode.grid)
        ..togglePin('u1:screen');
      expect(read().layout, TheaterLayoutMode.grid);
      expect(read().effectiveLayout, TheaterLayoutMode.focus);
    });

    test('focusStream define foco único e clicar no foco é no-op', () {
      notifier()
        ..setLayout(TheaterLayoutMode.focus)
        ..focusStream('u1:screen');
      expect(read().pinnedStreamIds, ['u1:screen']);

      // Clicar no rail troca o foco (nunca acumula, nunca esvazia).
      notifier().focusStream('u2:camera');
      expect(read().pinnedStreamIds, ['u2:camera']);

      // Repetir o foco atual não emite nem esvazia.
      notifier().focusStream('u2:camera');
      expect(read().pinnedStreamIds, ['u2:camera']);
    });

    test('toggles de chat/participantes/overlays', () {
      notifier()
        ..toggleChat()
        ..toggleParticipants()
        ..toggleOverlays();
      final state = read();
      expect(state.chatOpen, isTrue);
      expect(state.showParticipants, isFalse);
      expect(state.hideOverlays, isTrue);
    });
  });
}
