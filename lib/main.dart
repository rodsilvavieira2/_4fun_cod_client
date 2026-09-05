import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/lab_ca_overrides.dart';
import 'core/desktop/desktop_lifecycle.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop: confia na CA do lab para o wss:// do LiveKit (dart:io não lê
  // o trust store do sistema; ver lab_ca_overrides.dart). Web = no-op.
  await trustLabCa();
  await initializeDesktopLifecycle();

  runApp(const ProviderScope(child: App()));
  // O bootstrap de sessão acontece no AuthController.build() (disparado pelo
  // redirect do router): lê o storage, faz refresh silencioso se houver
  // refresh token e seta Authenticated/Unauthenticated. Logout limpa o
  // storage e o redirect leva para /login.
}
