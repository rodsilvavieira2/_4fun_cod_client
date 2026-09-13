import 'dart:ui';
import 'package:flutter/material.dart';

import '../../core/ui/ui.dart';
import '../../shared/models/servers.dart';

/// Header do canal: mantém o vidro do tema atual com a hierarquia compacta
/// de uma toolbar de comunidade.
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
  final VoidCallback? onBack;
  final VoidCallback? onOpenMembers;
  final VoidCallback? onOpenInvites;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final icon = channelType == ChannelType.text
        ? Icons.tag
        : Icons.volume_up_outlined;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          height: AppLayout.headerHeight,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: colors.background.withValues(alpha: 0.80),
            border: Border(
              bottom: BorderSide(color: colors.borderHairline, width: 1),
            ),
          ),
          child: Row(
            children: [
              if (onBack != null) ...[
                AppIconButton(
                  icon: Icons.arrow_back,
                  tooltip: 'Voltar para canais',
                  onPressed: onBack,
                ),
                const SizedBox(width: 6),
              ],
              Icon(icon, size: 16, color: colors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        channelName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      height: 18,
                      child: VerticalDivider(
                        color: colors.borderStrong,
                        width: 1,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        channelType == ChannelType.text
                            ? 'Conversa do servidor'
                            : 'Sala de voz e vídeo',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 12.5,
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              AppIconButton(
                icon: Icons.group_outlined,
                tooltip: 'Membros',
                onPressed: onOpenMembers,
              ),
              const SizedBox(width: 4),
              AppIconButton(
                icon: Icons.link,
                tooltip: 'Convites',
                onPressed: onOpenInvites,
              ),
              if (onOpenSettings != null) ...[
                const SizedBox(width: 4),
                AppIconButton(
                  icon: Icons.settings_outlined,
                  tooltip: 'Configurações do servidor',
                  onPressed: onOpenSettings,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
