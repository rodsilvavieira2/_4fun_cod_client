import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui/settings_modal.dart';
import '../home/home_screen.dart';

/// Compatibilidade para links antigos de `/profile`: a única experiência de
/// edição é o modal de Configurações > Conta.
class ProfileSettingsRedirectScreen extends StatefulWidget {
  const ProfileSettingsRedirectScreen({super.key});

  @override
  State<ProfileSettingsRedirectScreen> createState() =>
      _ProfileSettingsRedirectScreenState();
}

class _ProfileSettingsRedirectScreenState
    extends State<ProfileSettingsRedirectScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openSettings());
  }

  Future<void> _openSettings() async {
    await showSettingsModal(context);
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) => const HomeScreen();
}
