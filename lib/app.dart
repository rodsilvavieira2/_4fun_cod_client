import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

/// Widget raiz da aplicação.
///
/// O [ProviderScope] (Riverpod) é aplicado no bootstrap em `main.dart`,
/// envolvendo este widget. O router (com redirect por estado de auth) é
/// exposto via [routerProvider].
class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: '4fun Cod',
      // Design system dark-only (Discord + Vercel dark/Geist).
      theme: theme4funCod,
      routerConfig: router,
    );
  }
}
