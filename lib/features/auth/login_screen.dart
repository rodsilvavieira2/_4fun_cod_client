import 'package:flutter/material.dart';

/// Tela de login provisória (skeleton da Fase 0).
///
/// TODO(task 1 - auth): implementar login real via firebase_auth
/// (identidade) + backend (`/auth/firebase/login`).
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: const Center(
        child: Text('Login (placeholder)'),
      ),
    );
  }
}
