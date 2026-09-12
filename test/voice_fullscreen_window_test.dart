import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/features/voice/voice_fullscreen_window.dart';

void main() {
  test(
    'Windows desmaximiza antes do fullscreen e restaura maximizado ao sair',
    () async {
      final window = _FakeVoiceFullscreenWindow(maximized: true);

      final session = await enterVoiceFullscreenWindow(
        window: window,
        isWindows: true,
        settleDelay: Duration.zero,
      );

      expect(session.wasMaximized, isTrue);
      expect(session.confirmedFullScreen, isTrue);
      expect(
        window.calls,
        containsAllInOrder([
          'ensureInitialized',
          'isMinimized',
          'show',
          'focus',
          'isMaximized',
          'unmaximize',
          'setFullScreen:true',
          'isFullScreen',
          'focus',
        ]),
      );

      window.calls.clear();
      final stillFullScreen = await exitVoiceFullscreenWindow(
        session: session,
        window: window,
        isWindows: true,
        settleDelay: Duration.zero,
      );

      expect(stillFullScreen, isFalse);
      expect(window.calls, [
        'ensureInitialized',
        'setFullScreen:false',
        'isFullScreen',
        'maximize',
      ]);
    },
  );

  test(
    'Linux não altera maximização ao entrar ou sair do fullscreen',
    () async {
      final window = _FakeVoiceFullscreenWindow(maximized: true);

      final session = await enterVoiceFullscreenWindow(
        window: window,
        isWindows: false,
        settleDelay: Duration.zero,
      );

      expect(session.wasMaximized, isTrue);
      expect(window.calls, isNot(contains('unmaximize')));

      window.calls.clear();
      await exitVoiceFullscreenWindow(
        session: session,
        window: window,
        isWindows: false,
        settleDelay: Duration.zero,
      );

      expect(window.calls, isNot(contains('maximize')));
    },
  );

  test('restaura janela minimizada antes de entrar em fullscreen', () async {
    final window = _FakeVoiceFullscreenWindow(minimized: true);

    await enterVoiceFullscreenWindow(
      window: window,
      isWindows: true,
      settleDelay: Duration.zero,
    );

    expect(
      window.calls,
      containsAllInOrder([
        'isMinimized',
        'restore',
        'show',
        'focus',
        'setFullScreen:true',
      ]),
    );
  });

  test(
    'repete solicitação quando fullscreen não confirma na primeira leitura',
    () async {
      final window = _FakeVoiceFullscreenWindow(
        fullScreenResponses: [false, true],
      );

      final session = await enterVoiceFullscreenWindow(
        window: window,
        isWindows: true,
        settleDelay: Duration.zero,
      );

      expect(session.confirmedFullScreen, isTrue);
      expect(
        window.calls.where((call) => call == 'setFullScreen:true'),
        hasLength(2),
      );
    },
  );

  test(
    'restaura maximizado se a entrada em fullscreen falhar no Windows',
    () async {
      final window = _FakeVoiceFullscreenWindow(
        maximized: true,
        failSetFullScreen: true,
      );

      await expectLater(
        enterVoiceFullscreenWindow(
          window: window,
          isWindows: true,
          settleDelay: Duration.zero,
        ),
        throwsStateError,
      );
      expect(
        window.calls,
        containsAllInOrder(['unmaximize', 'setFullScreen:true', 'maximize']),
      );
    },
  );
}

class _FakeVoiceFullscreenWindow implements VoiceFullscreenWindow {
  _FakeVoiceFullscreenWindow({
    this.minimized = false,
    this.maximized = false,
    this.failSetFullScreen = false,
    List<bool>? fullScreenResponses,
  }) : _fullScreenResponses = fullScreenResponses ?? [];

  final List<String> calls = [];
  final List<bool> _fullScreenResponses;
  bool minimized;
  bool maximized;
  bool failSetFullScreen;
  bool fullScreen = false;

  @override
  Future<void> ensureInitialized() async {
    calls.add('ensureInitialized');
  }

  @override
  Future<void> focus() async {
    calls.add('focus');
  }

  @override
  Future<bool> isFullScreen() async {
    calls.add('isFullScreen');
    if (_fullScreenResponses.isNotEmpty) {
      return _fullScreenResponses.removeAt(0);
    }
    return fullScreen;
  }

  @override
  Future<bool> isMaximized() async {
    calls.add('isMaximized');
    return maximized;
  }

  @override
  Future<bool> isMinimized() async {
    calls.add('isMinimized');
    return minimized;
  }

  @override
  Future<void> maximize() async {
    calls.add('maximize');
    maximized = true;
  }

  @override
  Future<void> restore() async {
    calls.add('restore');
    minimized = false;
  }

  @override
  Future<void> setFullScreen(bool value) async {
    calls.add('setFullScreen:$value');
    if (failSetFullScreen) {
      throw StateError('setFullScreen failed');
    }
    fullScreen = value;
  }

  @override
  Future<void> show() async {
    calls.add('show');
  }

  @override
  Future<void> unmaximize() async {
    calls.add('unmaximize');
    maximized = false;
  }
}
