import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/ui/app_icon_button.dart';
import '../../shared/models/servers.dart';

/// Header de canal de 48px (wireframe v3 §4.3): `#nome` com ícone por
/// `type`, ações à direita (membros/convites/config). Fundo do chat
/// (canvas) com hairline inferior. No mobile (<800) ganha back button.
class ChannelHeader extends StatelessWidget {
  const ChannelHeader({
    super.key,
    required this.channelName,
    required this.channelType,
    this.onBack,
    this.onOpenMembers,
    this.onOpenInvites,
    this.onOpenSettings,
  });

  final String channelName;
  final ChannelType channelType;

  /// Mobile: volta para a lista de canais (nulo no desktop).
  final VoidCallback? onBack;

  /// Desktop: alterna o painel de membros; mobile: navega para a tela.
  final VoidCallback? onOpenMembers;
  final VoidCallback? onOpenInvites;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final icon = channelType == ChannelType.text
        ? Icons.tag
        : Icons.volume_up_outlined;
    return Container(
      // Wireframe: .channel-header height 48, padding 0 16px, gap 10.
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppThemeColors.canvas,
        border: Border(bottom: BorderSide(color: AppThemeColors.hairline)),
      ),
      child: Row(
        children: [
          if (onBack != null) ...[
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Voltar para canais',
              onPressed: onBack,
            ),
            const SizedBox(width: 6),
          ],
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              channelName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          AppIconButton(
            icon: Icons.group_outlined,
            tooltip: 'Membros',
            onPressed: onOpenMembers,
          ),
          AppIconButton(
            icon: Icons.link,
            tooltip: 'Convites',
            onPressed: onOpenInvites,
          ),
          AppIconButton(
            icon: Icons.settings_outlined,
            tooltip: 'Configurações',
            onPressed: onOpenSettings,
          ),
        ],
      ),
    );
  }
}
