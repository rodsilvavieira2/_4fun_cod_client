import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_update_state.dart';
import 'update_backend.dart';

/// Backend de auto-update da sessão (io real / stub web via export
/// condicional — seguro importar em `main.dart` e widgets).
final appUpdateBackendProvider = ChangeNotifierProvider<AppUpdateBackend>((_) {
  // Sem ref.onDispose: o ChangeNotifierProvider já faz dispose do notifier;
  // duplicar causava "used after being disposed" (widget_test).
  return createAppUpdateBackend();
});

/// Checagem de startup: não-bloqueante e silenciosa (nunca lança).
Future<void> scheduleStartupUpdateCheck(ProviderContainer container) async {
  try {
    await container
        .read(appUpdateBackendProvider)
        .checkOnStartup()
        .timeout(const Duration(seconds: 30));
  } catch (_) {
    // Intencional: update nunca derruba o boot.
  }
}
