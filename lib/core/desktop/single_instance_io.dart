import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:unix_single_instance/unix_single_instance.dart';
import 'package:windows_single_instance/windows_single_instance.dart';

import 'desktop_lifecycle.dart';
import 'single_instance_policy.dart';

/// Nome do pipe no Windows. Fixo e único do app para não variar com o
/// caminho de lançamento (AppImage/xdg-open mudam o nome do processo).
const _windowsPipeName = 'fourfun_cod_single_instance';

/// Garante instância única no Linux/Windows. A segunda cópia sinaliza a
/// primeira — que restaura a janela via [restoreDesktopWindow] — e sai
/// sozinha dentro dos pacotes (`exit(0)`); o `exit` aqui é só o fallback
/// do Linux em erro de socket. Debug e web nunca impõem a trava.
Future<void> ensureSingleInstanceOrExit(List<String> args) async {
  if (!shouldEnforceSingleInstance(
    isWeb: kIsWeb,
    isDebug: kDebugMode,
    isLinux: Platform.isLinux,
    isWindows: Platform.isWindows,
  )) {
    return;
  }

  if (Platform.isWindows) {
    await WindowsSingleInstance.ensureSingleInstance(
      args,
      _windowsPipeName,
      onSecondWindow: (_) {
        unawaited(restoreDesktopWindow());
      },
    );
    return;
  }

  if (Platform.isLinux) {
    if (!await unixSingleInstance(args, (_) {
      unawaited(restoreDesktopWindow());
    })) {
      exit(0);
    }
  }
}
