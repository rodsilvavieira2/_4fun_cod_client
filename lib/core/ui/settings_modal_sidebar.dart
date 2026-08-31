import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui.dart';

/// Seções do modal de configurações (wireframe v4).
enum SettingsSection {
  account('Conta', Icons.person_outline),
  appearance('Aparência', Icons.palette_outlined),
  voiceVideo('Voz e Vídeo', Icons.mic_none),
  notifications('Notificações', Icons.notifications_none),
  server('Servidor', Icons.dns_outlined),
  signOut('Sair', Icons.logout);

  const SettingsSection(this.title, this.icon);

  final String title;
  final IconData icon;
}

/// Sidebar escura do modal de configurações com alto contraste e ícones visíveis.
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
      decoration: const BoxDecoration(
        color: AppTokens.surfaceBase,
        border: Border(
          right: BorderSide(color: AppTokens.borderHairline, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Text(
              'Configurações',
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTokens.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Divider(height: 1, color: AppTokens.borderHairline),
          ),
          const SizedBox(height: 8),
          for (final item in sections)
            _SidebarItem(
              item: item,
              selected: item == section,
              onTap: () => onSectionChanged(item),
            ),
          const Spacer(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Divider(height: 1, color: AppTokens.borderHairline),
          ),
          const SizedBox(height: 6),
          _SidebarItem(
            item: SettingsSection.signOut,
            selected: false,
            color: AppTokens.accentPurple,
            onTap: onClose,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.item,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final SettingsSection item;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final fgColor = widget.color ??
        (selected
            ? AppTokens.textPrimary
            : (_hovered ? AppTokens.textPrimary : AppTokens.textSecondary));

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppTokens.surface3
                : (_hovered ? AppTokens.hoverOverlay : Colors.transparent),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: selected ? AppTokens.borderSubtle : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(widget.item.icon, size: 15, color: fgColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.item.title,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: fgColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
