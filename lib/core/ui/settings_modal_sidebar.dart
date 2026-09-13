import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import 'ui.dart';

/// Seções do modal de configurações (wireframe v4).
enum SettingsSection {
  account('Conta', Icons.person_outline),
  voiceVideo('Voz e vídeo', Icons.headset_mic_outlined),
  notifications('Notificações', Icons.notifications_none),
  appearance('Aparência', Icons.palette_outlined),
  updates('Atualizações', Icons.system_update_alt);

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
    final colors = context.appColors;
    final groups = <_SidebarGroup>[
      const _SidebarGroup('Perfil', [SettingsSection.account]),
      const _SidebarGroup('Comunicação', [
        SettingsSection.voiceVideo,
        SettingsSection.notifications,
      ]),
      const _SidebarGroup('Interface', [SettingsSection.appearance]),
      // Update in-place só existe no desktop (web = stub sem updater).
      if (!kIsWeb) const _SidebarGroup('Sistema', [SettingsSection.updates]),
    ];

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceBase,
        border: Border(
          right: BorderSide(color: colors.borderHairline, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Text(
              'Configurações',
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
                letterSpacing: 0,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Divider(height: 1, color: colors.borderHairline),
          ),
          const SizedBox(height: 6),
          for (final group in groups) ...[
            _SidebarGroupLabel(group.label),
            for (final item in group.items)
              _SidebarItem(
                item: item,
                selected: item == section,
                onTap: () => onSectionChanged(item),
              ),
            const SizedBox(height: 4),
          ],
          const Spacer(),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Divider(height: 1, color: colors.borderHairline),
          ),
          const SizedBox(height: 6),
          _SignOutButton(onTap: () => _confirmSignOut(context, ref)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final authController = ref.read(authControllerProvider.notifier);
    final confirmed = await showMacModalWindow<bool>(
      context: context,
      title: 'Encerrar sessão',
      maxWidth: 360,
      child: const _SignOutConfirmation(),
    );
    if (confirmed != true || !context.mounted) return;
    onClose();
    await authController.logout();
  }
}

class _SidebarGroup {
  const _SidebarGroup(this.label, this.items);

  final String label;
  final List<SettingsSection> items;
}

class _SidebarGroupLabel extends StatelessWidget {
  const _SidebarGroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Geist Mono',
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: colors.textMuted,
          letterSpacing: 0,
        ),
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
    final colors = context.appColors;
    final selected = widget.selected;
    final fgColor = selected
        ? colors.textPrimary
        : (_hovered ? colors.textPrimary : colors.textSecondary);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 30,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            color: selected
                ? colors.surface2
                : (_hovered ? colors.hoverOverlay : Colors.transparent),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: selected ? colors.borderSubtle : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 2,
                height: 14,
                decoration: BoxDecoration(
                  color: selected ? colors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
              const SizedBox(width: 7),
              Icon(widget.item.icon, size: 14.5, color: fgColor),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  widget.item.title,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: fgColor,
                    letterSpacing: 0,
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

/// Ação destrutiva da conta, isolada do fechamento normal do modal.
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
          height: 30,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: const Row(
            children: [
              Icon(Icons.logout, size: 14.5, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Encerrar sessão',
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: 0,
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

class _SignOutConfirmation extends StatelessWidget {
  const _SignOutConfirmation();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Sua sessão local será encerrada neste dispositivo.',
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 13,
              height: 1.35,
              color: AppTokens.textSecondary,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                label: 'Cancelar',
                variant: AppButtonVariant.ghost,
                onPressed: () => Navigator.of(context).pop(false),
              ),
              const SizedBox(width: 8),
              AppButton(
                label: 'Encerrar',
                variant: AppButtonVariant.danger,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
