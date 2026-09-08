import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui.dart';

/// Seções do modal de configurações (wireframe v4).
enum SettingsSection {
  account('Conta', Icons.person_outline),
  appearance('Aparência', Icons.palette_outlined),
  voiceVideo('Voz e Vídeo', Icons.mic_none),
  notifications('Notificações', Icons.notifications_none),
  updates('Atualizações', Icons.system_update_alt),
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
  });

  final SettingsSection section;
  final ValueChanged<SettingsSection> onSectionChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = <SettingsSection>[
      SettingsSection.account,
      SettingsSection.appearance,
      SettingsSection.voiceVideo,
      SettingsSection.notifications,
      // Update in-place só existe no desktop (web = stub sem updater).
      if (!kIsWeb) SettingsSection.updates,
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
          _SignOutButton(onTap: onClose),
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
  });

  final SettingsSection item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final fgColor = selected
        ? AppTokens.textPrimary
        : (_hovered ? AppTokens.textPrimary : AppTokens.textSecondary);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
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

/// Botão "Sair": preenchimento vermelho ([AppTokens.accentDanger]) com
/// texto/ícone brancos. Mantém as mesmas medidas do [_SidebarItem].
class _SignOutButton extends StatefulWidget {
  const _SignOutButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_SignOutButton> createState() => _SignOutButtonState();
}

class _SignOutButtonState extends State<_SignOutButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bgColor = _pressed
        ? const Color(0xFF9E1F1F)
        : (_hovered ? const Color(0xFFD32F2F) : AppTokens.accentDanger);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: const Row(
            children: [
              Icon(Icons.logout, size: 15, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sair',
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
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
