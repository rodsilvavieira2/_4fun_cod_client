import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';

/// Seções do modal de configurações (wireframe v3 §4.6).
enum SettingsSection {
  account('Conta'),
  appearance('Aparência'),
  voiceVideo('Voz e Vídeo'),
  notifications('Notificações'),
  server('Servidor'),
  signOut('Sair');

  const SettingsSection(this.title);

  final String title;
}

/// Sidebar escura (bg rail) do modal de configurações: itens de seção +
/// "Sair" (cor roxa — v3 substitui vermelho). Estado da seção ativa é
/// LOCAL ao modal (SPEC 3: toggles/navegação resetam ao reabrir).
class SettingsModalSidebar extends ConsumerWidget {
  const SettingsModalSidebar({
    super.key,
    required this.section,
    required this.onSectionChanged,
    required this.onClose,
    this.serverId,
  });

  final SettingsSection section;
  final ValueChanged<SettingsSection> onSectionChanged;
  final VoidCallback onClose;

  /// Opcional: quando aberto de dentro de um servidor, mostra a seção
  /// `Servidor: <nome>`.
  final String? serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = <SettingsSection>[
      SettingsSection.account,
      SettingsSection.appearance,
      SettingsSection.voiceVideo,
      SettingsSection.notifications,
      if (serverId != null) SettingsSection.server,
    ];

    return Container(
      color: AppThemeColors.rail,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Configurações',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppThemeColors.hairline,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Divider(height: 1),
          ),
          const SizedBox(height: 8),
          for (final item in sections)
            _SidebarItem(
              title: item.title,
              selected: item == section,
              onTap: () => onSectionChanged(item),
            ),
          const Spacer(),
          const Divider(height: 1),
          _SidebarItem(
            title: 'Sair',
            selected: false,
            color: AppThemeColors.authorColors.last,
            onTap: () {
              // UI shell: logout real fica fora do escopo (SPEC 3 —
              // ações visuais apenas). Fecha o modal.
              onClose();
            },
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.title,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  /// Cor do texto (default: onSurface; "Sair" usa roxo do tema v3).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 36,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppOverlayColors.selected
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: color ?? theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
