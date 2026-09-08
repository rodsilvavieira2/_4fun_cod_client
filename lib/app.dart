import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth/auth_controller.dart';
import 'core/auth/auth_state.dart';
import 'core/router/app_router.dart';
import 'core/telemetry/telemetry_service.dart';
import 'core/theme/app_theme.dart';
import 'features/voice/push_to_talk_listener.dart';

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
    // Fire-and-forget: no-op quando OTEL_ENABLED=false (default).
    final telemetry = ref.read(telemetryServiceProvider);
    telemetry.init();
    // Nível 1 — monitoramento por usuário: só o id (nunca PII) vai como
    // atributo `user_id` nos eventos/spans; logout limpa (null).
    ref.listen(authControllerProvider, (_, next) {
      final state = next.valueOrNull;
      telemetry.setUser(state is Authenticated ? state.user.id : null);
    });
    return PushToTalkListener(
      child: MaterialApp.router(
        title: '4FunCode',
        debugShowCheckedModeBanner: false,
        // Design system dark-only (Discord + Vercel dark/Geist).
        theme: theme4funCod,
        routerConfig: router,
      ),
    );
  }
}
