import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_lifecycle_controller.dart';

const _showWindowMenuKey = 'show_window';
const _quitMenuKey = 'quit';
const _statusNotifierWatcherName = 'org.kde.StatusNotifierWatcher';

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

/// Traz a primeira instância para frente quando uma segunda cópia é lançada.
///
/// Reusa o controller do close-to-tray (restaura da bandeja/minimizado).
/// Se a bandeja falhou na inicialização, cai para show/focus direto.
Future<void> restoreDesktopWindow() async {
  final controller = _desktopLifecycleController;
  if (controller == null) {
    await windowManager.ensureInitialized();
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await windowManager.show();
    await windowManager.focus();
    return;
  }
  await controller.showWindow();
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
    if (onClose != null) {
      _runGuarded('ocultar a janela', onClose);
    }
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
    if (!_isWindows && !await _hasUsableLinuxTray()) {
      throw UnsupportedError(
        'O ambiente Linux atual não possui um host de system tray acessível.',
      );
    }

    _onActivate = onActivate;
    _onAction = onAction;
    trayManager.addListener(this);
    _listening = true;

    await trayManager.setIcon(
      _isWindows
          ? 'windows/runner/resources/app_icon.ico'
          : _linuxTrayIconPath(),
    );
    if (_isWindows) {
      await trayManager.setToolTip('4FunCode');
    }
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: _showWindowMenuKey, label: 'Abrir 4FunCode'),
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
    if (onActivate != null) {
      _runGuarded('restaurar a janela', onActivate);
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    if (_isWindows) {
      _runGuarded('abrir o menu da bandeja', trayManager.popUpContextMenu);
    }
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
      _runGuarded('executar a ação ${action.name}', () => onAction(action));
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

void _runGuarded(String operation, Future<void> Function() callback) {
  unawaited(() async {
    try {
      await callback();
    } catch (error, stackTrace) {
      debugPrint('Falha ao $operation pelo system tray: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }());
}

Future<bool> _hasUsableLinuxTray() async {
  final environment = Platform.environment;
  final flatpakId = environment['FLATPAK_ID'];
  final snapName = environment['SNAP_NAME'];

  // O plugin interpreta o caminho como nome de ícone dentro de sandboxes.
  // Sem um ID de manifesto conhecido não há como registrar um ícone válido.
  final isGenericContainer =
      environment['container']?.isNotEmpty == true ||
      FileSystemEntity.isFileSync('/.dockerenv');
  final isPackagedSandbox =
      flatpakId?.isNotEmpty == true || snapName?.isNotEmpty == true;
  if ((isGenericContainer && !isPackagedSandbox) ||
      (environment.containsKey('FLATPAK_ID') &&
          flatpakId?.isNotEmpty != true) ||
      (environment.containsKey('SNAP') && snapName?.isNotEmpty != true)) {
    return false;
  }

  final desktop = environment['XDG_CURRENT_DESKTOP']?.toLowerCase() ?? '';
  final needsStatusNotifier =
      environment['WAYLAND_DISPLAY']?.isNotEmpty == true ||
      desktop.contains('gnome');
  if (!needsStatusNotifier) return true;

  final bus = DBusClient.session(introspectable: false);
  try {
    return await bus.nameHasOwner(_statusNotifierWatcherName);
  } catch (error, stackTrace) {
    debugPrint('Não foi possível consultar o host do system tray: $error');
    debugPrintStack(stackTrace: stackTrace);
    return false;
  } finally {
    await bus.close();
  }
}

String _linuxTrayIconPath() {
  final environment = Platform.environment;
  return environment['FLATPAK_ID'] ??
      environment['SNAP_NAME'] ??
      'web/favicon.png';
}
