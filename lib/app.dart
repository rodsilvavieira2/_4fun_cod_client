import 'package:flutter/material.dart';

import 'core/router/app_router.dart';

/// Widget raiz da aplicação.
///
/// O [ProviderScope] (Riverpod) é aplicado no bootstrap em `main.dart`,
/// envolvendo este widget, de modo que o `routerConfig` e todas as telas
/// têm acesso aos providers.
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '4fun Cod',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      routerConfig: appRouter,
    );
  }
}
