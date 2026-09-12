import 'dart:async';
import 'dart:io';

import 'package:window_manager/window_manager.dart';

abstract interface class VoiceFullscreenWindow {
  Future<void> ensureInitialized();

  Future<bool> isMinimized();

  Future<bool> isMaximized();

  Future<void> restore();

  Future<void> unmaximize();

  Future<void> maximize();

  Future<void> show();

  Future<void> focus();

  Future<void> setFullScreen(bool value);

  Future<bool> isFullScreen();
}

class WindowManagerVoiceFullscreenWindow implements VoiceFullscreenWindow {
  WindowManagerVoiceFullscreenWindow({WindowManager? window})
    : _window = window ?? WindowManager.instance;

  final WindowManager _window;

  @override
  Future<void> ensureInitialized() => _window.ensureInitialized();

  @override
  Future<bool> isMinimized() => _window.isMinimized();

  @override
  Future<bool> isMaximized() => _window.isMaximized();

  @override
  Future<void> restore() => _window.restore();

  @override
  Future<void> unmaximize() => _window.unmaximize();

  @override
  Future<void> maximize() => _window.maximize();

  @override
  Future<void> show() => _window.show();

  @override
  Future<void> focus() => _window.focus();

  @override
  Future<void> setFullScreen(bool value) => _window.setFullScreen(value);

  @override
  Future<bool> isFullScreen() => _window.isFullScreen();
}

class VoiceFullscreenWindowSession {
  const VoiceFullscreenWindowSession({
    required this.wasMaximized,
    required this.confirmedFullScreen,
  });

  final bool wasMaximized;
  final bool confirmedFullScreen;
}

Future<VoiceFullscreenWindowSession> enterVoiceFullscreenWindow({
  VoiceFullscreenWindow? window,
  bool? isWindows,
  Duration settleDelay = const Duration(milliseconds: 80),
}) async {
  final hostIsWindows = isWindows ?? Platform.isWindows;
  final controller = window ?? WindowManagerVoiceFullscreenWindow();

  await controller.ensureInitialized();
  if (await controller.isMinimized()) {
    await controller.restore();
    await _settle(settleDelay);
  }
  await controller.show();
  await controller.focus();

  final wasMaximized = await controller.isMaximized();
  try {
    if (hostIsWindows && wasMaximized) {
      await controller.unmaximize();
      await _settle(settleDelay);
    }

    await controller.setFullScreen(true);
    await _settle(settleDelay);

    var confirmedFullScreen = await controller.isFullScreen();
    if (!confirmedFullScreen) {
      await controller.setFullScreen(true);
      await _settle(settleDelay);
      confirmedFullScreen = await controller.isFullScreen();
    }

    await controller.focus();
    return VoiceFullscreenWindowSession(
      wasMaximized: wasMaximized,
      confirmedFullScreen: confirmedFullScreen,
    );
  } catch (_) {
    if (hostIsWindows && wasMaximized) {
      try {
        await controller.maximize();
      } catch (_) {
        // A falha original continua sendo a mais útil para o chamador.
      }
    }
    rethrow;
  }
}

Future<bool> exitVoiceFullscreenWindow({
  required VoiceFullscreenWindowSession? session,
  VoiceFullscreenWindow? window,
  bool? isWindows,
  Duration settleDelay = const Duration(milliseconds: 80),
}) async {
  final hostIsWindows = isWindows ?? Platform.isWindows;
  final controller = window ?? WindowManagerVoiceFullscreenWindow();

  await controller.ensureInitialized();
  await controller.setFullScreen(false);
  await _settle(settleDelay);
  final isStillFullScreen = await controller.isFullScreen();

  if (hostIsWindows && session?.wasMaximized == true) {
    await controller.maximize();
  }

  return isStillFullScreen;
}

Future<void> _settle(Duration duration) async {
  if (duration == Duration.zero) return;
  await Future<void>.delayed(duration);
}
