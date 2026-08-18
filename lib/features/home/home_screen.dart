import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_state.dart';

/// Home provisória (Fase 1): saúda o usuário autenticado e dá acesso ao
/// perfil. Na Fase 2 vira a lista de servidores.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider).valueOrNull;
    final user = authState is Authenticated ? authState.user : null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('4fun Cod'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle),
            tooltip: 'Perfil',
            onPressed: () => context.go('/profile'),
          ),
        ],
      ),
      body: Center(
        child: Text(user == null ? 'Home (placeholder)' : 'Olá, ${user.name}!'),
      ),
    );
  }
}
