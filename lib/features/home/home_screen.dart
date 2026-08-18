import 'package:flutter/material.dart';

/// Home provisória (skeleton da Fase 0), exibida na rota raiz.
///
/// TODO(task 2 - servers): substituir pela lista de servidores
/// (features/servers).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('4fun Cod')),
      body: const Center(
        child: Text('Home (placeholder)'),
      ),
    );
  }
}
