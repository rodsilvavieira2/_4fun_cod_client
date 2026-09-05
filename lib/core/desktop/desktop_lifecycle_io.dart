import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_lifecycle_controller.dart';

const _showWindowMenuKey = 'show_window';
const _quitMenuKey = 'quit';

DesktopLifecycleController? _desktopLifecycleController;

/// Habilita close-to-tray exclusivamente no Linux e no Windows.
Future<void> initializeDesktopLifecycle() async {
  if ((!Platform.isLinux && !Platform.isWindows) ||
      _desktopLifecycleController != null) {
    return;
  }

  final controller = DesktopLifecycleController(
    window: _WindowManagerPort(),
    tray: _TrayManagerPort(Platform.isWindows),
  );

  try {
    await controller.initialize();
    _desktopLifecycleController = controller;
  } catch (error, stackTrace) {
    // Falhar ao criar a bandeja não pode impedir a abertura do aplicativo.
    debugPrint('Não foi possível inicializar o system tray: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

class _WindowManagerPort with WindowListener implements DesktopWindowPort {
  DesktopCloseHandler? _onClose;
  bool _listening = false;

  @override
  Future<void> initialize({required DesktopCloseHandler onClose}) async {
    await windowManager.ensureInitialized();
    _onClose = onClose;
    windowManager.addListener(this);
    _listening = true;
  }

  @override
  void onWindowClose() {
    final onClose = _onClose;
    if (onClose != null) unawaited(onClose());
  }

  @override
  Future<void> setPreventClose(bool preventClose) =>
      windowManager.setPreventClose(preventClose);

  @override
  Future<void> hide() => windowManager.hide();

  @override
  Future<bool> isMinimized() => windowManager.isMinimized();

  @override
  Future<void> restore() => windowManager.restore();

  @override
  Future<void> show() => windowManager.show();

  @override
  Future<void> focus() => windowManager.focus();

  @override
  Future<void> destroy() => windowManager.destroy();

  @override
  void dispose() {
    if (!_listening) return;
    windowManager.removeListener(this);
    _onClose = null;
    _listening = false;
  }
}

class _TrayManagerPort with TrayListener implements DesktopTrayPort {
  _TrayManagerPort(this._isWindows);

  final bool _isWindows;
  DesktopTrayActivationHandler? _onActivate;
  DesktopTrayActionHandler? _onAction;
  bool _listening = false;

  @override
  Future<void> initialize({
    required DesktopTrayActivationHandler onActivate,
    required DesktopTrayActionHandler onAction,
  }) async {
    _onActivate = onActivate;
    _onAction = onAction;
    trayManager.addListener(this);
    _listening = true;

    await trayManager.setIcon(
      _isWindows
          ? 'windows/runner/resources/app_icon.ico'
          : 'web/icons/Icon-192.png',
    );
    if (_isWindows) {
      await trayManager.setToolTip('4fun Cod');
    }
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: _showWindowMenuKey, label: 'Abrir 4fun Cod'),
          MenuItem.separator(),
          MenuItem(key: _quitMenuKey, label: 'Sair do aplicativo'),
        ],
      ),
    );
  }

  @override
  void onTrayIconMouseDown() {
    // No Linux/AppIndicator o clique abre o menu nativo; este callback é útil
    // no Windows, onde o clique esquerdo restaura a janela diretamente.
    if (!_isWindows) return;
    final onActivate = _onActivate;
    if (onActivate != null) unawaited(onActivate());
  }

  @override
  void onTrayIconRightMouseDown() {
    if (_isWindows) unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final action = switch (menuItem.key) {
      _showWindowMenuKey => DesktopTrayAction.showWindow,
      _quitMenuKey => DesktopTrayAction.quit,
      _ => null,
    };
    final onAction = _onAction;
    if (action != null && onAction != null) {
      unawaited(onAction(action));
    }
  }

  @override
  Future<void> destroy() => trayManager.destroy();

  @override
  void dispose() {
    if (!_listening) return;
    trayManager.removeListener(this);
    _onActivate = null;
    _onAction = null;
    _listening = false;
  }
}
