import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'settings_modal_sidebar.dart';
import 'settings_sections/account_section.dart';
import 'settings_sections/appearance_section.dart';
import 'settings_sections/notifications_section.dart';
import 'settings_sections/server_section.dart';
import 'settings_sections/voice_video_section.dart';

/// Modal de configurações (wireframe v3 §4.6 — UI shell): 660x440, sidebar
/// escura com 5 seções + Sair, fecha via X/ESC/clique fora. Nenhuma ação
/// grava estado fora do modal (toggles locais resetam ao reabrir).
///
/// [serverId] opcional: a seção `Servidor: <nome>` só aparece quando o
/// modal é aberto de dentro de um servidor (user panel / header de canal).
Future<void> showSettingsModal(
  BuildContext context, {
  String? serverId,
  SettingsSection initialSection = SettingsSection.account,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Fechar configurações',
    barrierColor: Colors.black.withValues(alpha: 0.65),
    transitionDuration: const Duration(milliseconds: 150),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
    pageBuilder: (context, animation, secondaryAnimation) {
      return _SettingsModal(serverId: serverId, initialSection: initialSection);
    },
  );
}

/// Estado da seção ativa é LOCAL ao modal (StatefulWidget) — reseta ao
/// reabrir; nada persiste (decisão da SPEC 3, não há fonte de verdade de
/// config no client).
class _SettingsModal extends StatefulWidget {
  const _SettingsModal({this.serverId, required this.initialSection});

  final String? serverId;
  final SettingsSection initialSection;

  @override
  State<_SettingsModal> createState() => _SettingsModalState();
}

class _SettingsModalState extends State<_SettingsModal> {
  late SettingsSection _section;

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection;
  }

  @override
  Widget build(BuildContext context) {
    return SettingsModalEscClose(
      child: Center(
        child: ConstrainedBox(
          // Clamp: telas menores que o modal não estouram (SPEC 3 verificação 5).
          constraints: const BoxConstraints(
            maxWidth: 660,
            maxHeight: 440,
            minWidth: 320,
            minHeight: 320,
          ),
          child: Material(
            color: AppThemeColors.card,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 180,
                  child: SettingsModalSidebar(
                    section: _section,
                    serverId: widget.serverId,
                    onSectionChanged: (section) =>
                        setState(() => _section = section),
                    onClose: () => Navigator.of(context).pop(),
                  ),
                ),
                Expanded(
                  child: _SettingsBody(
                    section: _section,
                    serverId: widget.serverId,
                    onClose: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsBody extends StatelessWidget {
  const _SettingsBody({
    required this.section,
    required this.onClose,
    this.serverId,
  });

  final SettingsSection section;
  final String? serverId;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header do modal: título + X (fecha).
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppThemeColors.hairline)),
          ),
          child: Row(
            children: [
              Text(
                section.title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Fechar',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: onClose,
              ),
            ],
          ),
        ),
        // Corpo: seção ativa.
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: switch (section) {
              SettingsSection.account => const AccountSection(),
              SettingsSection.appearance => const AppearanceSection(),
              SettingsSection.voiceVideo => const VoiceVideoSection(),
              SettingsSection.notifications => const NotificationsSection(),
              SettingsSection.server => ServerSection(serverId: serverId),
              // "Sair" nunca vira corpo: a sidebar fecha o modal direto.
              SettingsSection.signOut => const SizedBox.shrink(),
            },
          ),
        ),
      ],
    );
  }
}

/// Atalho de teclado: ESC fecha o modal.
class SettingsModalEscClose extends StatelessWidget {
  const SettingsModalEscClose({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
