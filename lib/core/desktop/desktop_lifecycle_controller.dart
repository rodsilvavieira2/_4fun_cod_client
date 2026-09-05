typedef DesktopCloseHandler = Future<void> Function();
typedef DesktopTrayActivationHandler = Future<void> Function();
typedef DesktopTrayActionHandler =
    Future<void> Function(DesktopTrayAction action);

enum DesktopTrayAction { showWindow, quit }

/// Operações de janela necessárias para implementar close-to-tray.
abstract interface class DesktopWindowPort {
  Future<void> initialize({required DesktopCloseHandler onClose});

  Future<void> setPreventClose(bool preventClose);

  Future<void> hide();

  Future<bool> isMinimized();

  Future<void> restore();

  Future<void> show();

  Future<void> focus();

  Future<void> destroy();

  void dispose();
}

/// Operações da bandeja necessárias para implementar close-to-tray.
abstract interface class DesktopTrayPort {
  Future<void> initialize({
    required DesktopTrayActivationHandler onActivate,
    required DesktopTrayActionHandler onAction,
  });

  Future<void> destroy();

  void dispose();
}

/// Coordena o ciclo de vida da janela principal e do system tray.
///
/// O controller não depende de plugins, permitindo validar o comportamento com
/// fakes. Os adapters nativos ficam em `desktop_lifecycle_io.dart`.
class DesktopLifecycleController {
  factory DesktopLifecycleController({
    required DesktopWindowPort window,
    required DesktopTrayPort tray,
  }) => DesktopLifecycleController._(window, tray);

  DesktopLifecycleController._(this._window, this._tray);

  final DesktopWindowPort _window;
  final DesktopTrayPort _tray;

  Future<void>? _initialization;
  bool _initialized = false;
  bool _isQuitting = false;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    await _window.initialize(onClose: handleWindowClose);
    try {
      await _tray.initialize(
        onActivate: showWindow,
        onAction: handleTrayAction,
      );
      // Só bloqueia o fechamento depois que existe uma forma de restaurar ou
      // encerrar o app pela bandeja.
      await _window.setPreventClose(true);
      _initialized = true;
    } catch (_) {
      // Reverte qualquer inicialização parcial. Em especial, não deixa a
      // janela invisível sem uma bandeja funcional para restaurá-la.
      try {
        await _window.setPreventClose(false);
      } catch (_) {
        // A falha original continua sendo a mais útil para diagnóstico.
      }
      try {
        await _tray.destroy();
      } catch (_) {
        // O ícone pode nem ter sido criado ainda.
      }
      _tray.dispose();
      _window.dispose();
      rethrow;
    }
  }

  Future<void> handleWindowClose() async {
    if (!_initialized || _isQuitting) return;
    await _window.hide();
  }

  Future<void> handleTrayAction(DesktopTrayAction action) => switch (action) {
    DesktopTrayAction.showWindow => showWindow(),
    DesktopTrayAction.quit => quit(),
  };

  Future<void> showWindow() async {
    if (!_initialized || _isQuitting) return;
    if (await _window.isMinimized()) {
      await _window.restore();
    }
    await _window.show();
    await _window.focus();
  }

  Future<void> quit() async {
    if (!_initialized || _isQuitting) return;
    _isQuitting = true;

    try {
      await _window.setPreventClose(false);
      await _tray.destroy();
    } finally {
      // `destroy` força o encerramento, sem gerar um novo ciclo de close.
      await _window.destroy();
    }
  }
}
