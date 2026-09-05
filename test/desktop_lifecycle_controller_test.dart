import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/core/desktop/desktop_lifecycle_controller.dart';

class _FakeWindow implements DesktopWindowPort {
  _FakeWindow(this.calls);

  final List<String> calls;
  DesktopCloseHandler? onClose;
  bool minimized = false;
  bool disposed = false;

  @override
  Future<void> initialize({required DesktopCloseHandler onClose}) async {
    calls.add('window.initialize');
    this.onClose = onClose;
  }

  @override
  Future<void> setPreventClose(bool preventClose) async {
    calls.add('window.preventClose:$preventClose');
  }

  @override
  Future<void> hide() async {
    calls.add('window.hide');
  }

  @override
  Future<bool> isMinimized() async {
    calls.add('window.isMinimized');
    return minimized;
  }

  @override
  Future<void> restore() async {
    calls.add('window.restore');
  }

  @override
  Future<void> show() async {
    calls.add('window.show');
  }

  @override
  Future<void> focus() async {
    calls.add('window.focus');
  }

  @override
  Future<void> destroy() async {
    calls.add('window.destroy');
  }

  @override
  void dispose() {
    disposed = true;
    calls.add('window.dispose');
  }
}

class _FakeTray implements DesktopTrayPort {
  _FakeTray(this.calls);

  final List<String> calls;
  DesktopTrayActivationHandler? onActivate;
  DesktopTrayActionHandler? onAction;
  bool failInitialization = false;
  bool disposed = false;

  @override
  Future<void> initialize({
    required DesktopTrayActivationHandler onActivate,
    required DesktopTrayActionHandler onAction,
  }) async {
    calls.add('tray.initialize');
    this.onActivate = onActivate;
    this.onAction = onAction;
    if (failInitialization) throw StateError('tray unavailable');
  }

  @override
  Future<void> destroy() async {
    calls.add('tray.destroy');
  }

  @override
  void dispose() {
    disposed = true;
    calls.add('tray.dispose');
  }
}

void main() {
  late List<String> calls;
  late _FakeWindow window;
  late _FakeTray tray;
  late DesktopLifecycleController controller;

  setUp(() {
    calls = [];
    window = _FakeWindow(calls);
    tray = _FakeTray(calls);
    controller = DesktopLifecycleController(window: window, tray: tray);
  });

  test('inicializa a bandeja antes de impedir o fechamento', () async {
    await controller.initialize();
    await controller.initialize();

    expect(calls, [
      'window.initialize',
      'tray.initialize',
      'window.preventClose:true',
    ]);
  });

  test('fechar a janela apenas a esconde', () async {
    await controller.initialize();
    calls.clear();

    await window.onClose!();

    expect(calls, ['window.hide']);
  });

  test('ativar a bandeja restaura, exibe e foca a janela', () async {
    window.minimized = true;
    await controller.initialize();
    calls.clear();

    await tray.onActivate!();

    expect(calls, [
      'window.isMinimized',
      'window.restore',
      'window.show',
      'window.focus',
    ]);
  });

  test('menu Abrir mantém uma janela maximizada e a traz ao foco', () async {
    await controller.initialize();
    calls.clear();

    await tray.onAction!(DesktopTrayAction.showWindow);

    expect(calls, ['window.isMinimized', 'window.show', 'window.focus']);
  });

  test('menu Sair remove a bandeja e encerra uma única vez', () async {
    await controller.initialize();
    calls.clear();

    await tray.onAction!(DesktopTrayAction.quit);
    await window.onClose!();
    await tray.onAction!(DesktopTrayAction.quit);

    expect(calls, [
      'window.preventClose:false',
      'tray.destroy',
      'window.destroy',
    ]);
  });

  test('falha da bandeja não ativa preventClose e limpa adapters', () async {
    tray.failInitialization = true;

    await expectLater(controller.initialize(), throwsStateError);

    expect(calls, [
      'window.initialize',
      'tray.initialize',
      'window.preventClose:false',
      'tray.destroy',
      'tray.dispose',
      'window.dispose',
    ]);
    expect(tray.disposed, isTrue);
    expect(window.disposed, isTrue);
  });
}
