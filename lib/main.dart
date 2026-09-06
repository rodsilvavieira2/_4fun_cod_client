import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/lab_ca_overrides.dart';
import 'core/desktop/desktop_lifecycle.dart';
import 'core/telemetry/telemetry_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop: confia na CA do lab para o wss:// do LiveKit (dart:io não lê
  // o trust store do sistema; ver lab_ca_overrides.dart). Web = no-op.
  await trustLabCa();
  await initializeDesktopLifecycle();

  // Captura global de erros → OpenObserve (via `reportError`, com redação).
  // Container próprio para alcançar o TelemetryService fora da árvore.
  final container = ProviderContainer();
  final telemetry = container.read(telemetryServiceProvider);
  FlutterError.onError = (details) => telemetry.reportError(
        'flutter',
        details.exception,
        details.stack,
      );
  PlatformDispatcher.instance.onError = (error, stack) {
    telemetry.reportError('platform', error, stack);
    return true;
  };

  runZonedGuarded(
    () => runApp(UncontrolledProviderScope(container: container, child: const App())),
    (error, stack) => telemetry.reportError('zone', error, stack),
  );
  // O bootstrap de sessão acontece no AuthController.build() (disparado pelo
  // redirect do router): lê o storage, faz refresh silencioso se houver
  // refresh token e seta Authenticated/Unauthenticated. Logout limpa o
  // storage e o redirect leva para /login.
}
