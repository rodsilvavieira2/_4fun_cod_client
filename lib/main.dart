import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const ProviderScope(child: App()));
  // O bootstrap de sessão acontece no AuthController.build() (disparado pelo
  // redirect do router): lê o storage, faz refresh silencioso se houver
  // refresh token e seta Authenticated/Unauthenticated. Logout limpa o
  // storage e o redirect leva para /login.
}
