import 'package:flutter/material.dart';

import '../../core/ui/ui.dart';

/// Tela exibida enquanto o AuthState é desconhecido (bootstrap da sessão).
///
/// O redirect do router (§7.2) mostra esta tela até o
/// [AuthController] terminar de validar os tokens.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppLogo(size: 64),
            SizedBox(height: 24),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
