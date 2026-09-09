import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/lab_ca_overrides.dart';
import 'core/desktop/desktop_lifecycle.dart';
import 'core/desktop/single_instance.dart';
import 'core/telemetry/telemetry_service.dart';
import 'core/updates/update_providers.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    runApp(const _UnsupportedWebApp());
    return;
  }

  // Desktop: confia na CA do lab para o wss:// do LiveKit (dart:io não lê
  // o trust store do sistema; ver lab_ca_overrides.dart).
  await trustLabCa();
  // Linux/Windows release: segunda cópia sinaliza a primeira e sai aqui,
  // antes de criar tray. Debug nunca impõe a trava.
  await ensureSingleInstanceOrExit(args);
  await initializeDesktopLifecycle();

  // Captura global de erros → OpenObserve (via `reportError`, com redação).
  // Container próprio para alcançar o TelemetryService fora da árvore.
  final container = ProviderContainer();
  // Windows/Linux: checagem de update em background (falha silenciosa —
  // update nunca derruba o boot).
  unawaited(scheduleStartupUpdateCheck(container));
  final telemetry = container.read(telemetryServiceProvider);
  FlutterError.onError = (details) =>
      telemetry.reportError('flutter', details.exception, details.stack);
  PlatformDispatcher.instance.onError = (error, stack) {
    telemetry.reportError('platform', error, stack);
    return true;
  };

  runZonedGuarded(
    () => runApp(
      UncontrolledProviderScope(container: container, child: const App()),
    ),
    (error, stack) => telemetry.reportError('zone', error, stack),
  );
  // O bootstrap de sessão acontece no AuthController.build() (disparado pelo
  // redirect do router): lê o storage, faz refresh silencioso se houver
  // refresh token e seta Authenticated/Unauthenticated. Logout limpa o
  // storage e o redirect leva para /login.
}

class _UnsupportedWebApp extends StatelessWidget {
  const _UnsupportedWebApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '4FunCode — Web não suportado',
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 520),
              child: Text(
                'Web não é suportado pelo 4FunCode. '
                'Use o cliente desktop Linux ou Windows.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, height: 1.35),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
