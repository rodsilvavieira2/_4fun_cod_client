import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/appearance_theme.dart';
import '../../../core/ui/ds_tokens.dart';
import '../../../core/ui/menus/app_menu.dart';
import '../voice_providers.dart';
import 'theater_menus.dart';
import 'theater_ui_provider.dart';

/// Barra compacta bottom-center do theater: 8 ações com responsabilidade
/// única (decisão grill rodada 4-f). Sair fica em botão vermelho dedicado,
/// nunca dentro do `⋯`. O `⋯` é um [AppMenuButton] ancorado (padrão
/// compacto do app). Toda ação reutiliza controllers existentes.
class TheaterControlBar extends ConsumerWidget {
  const TheaterControlBar({
    super.key,
    required this.arg,
    required this.onToggleScreenShare,
    required this.onOpenSettings,
    required this.onToggleFullscreen,
    required this.onLeave,
  });

  final ({String serverId, String channelId}) arg;
  final VoidCallback onToggleScreenShare;
  final VoidCallback onOpenSettings;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voice = ref.watch(voiceControllerProvider(arg));
    final voiceNotifier = ref.read(voiceControllerProvider(arg).notifier);
    final ui = ref.watch(theaterUiControllerProvider(arg));
    final uiNotifier = ref.read(theaterUiControllerProvider(arg).notifier);
    final colors = context.appColors;

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: colors.surfaceGlass,
          borderRadius: AppRadius.brFull,
          border: Border.all(color: colors.borderSubtle),
          boxShadow: AppShadows.popover,
        ),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          runSpacing: 4,
          children: [
            _barButton(
              context,
              icon: voice.isMicrophoneEnabled ? Icons.mic : Icons.mic_off,
              tooltip: voice.isMicrophoneEnabled
                  ? 'Desativar microfone'
                  : 'Ativar microfone',
              active: !voice.isMicrophoneEnabled,
              onPressed: voiceNotifier.toggleMicrophone,
            ),
            _barButton(
              context,
              icon: voice.isDeafened ? Icons.headset_off : Icons.headset_mic,
              tooltip: voice.isDeafened
                  ? 'Ativar áudio'
                  : 'Ensurdecer (deafen)',
              active: voice.isDeafened,
              onPressed: voiceNotifier.toggleDeafen,
            ),
            _barButton(
              context,
              icon: voice.isCameraEnabled ? Icons.videocam : Icons.videocam_off,
              tooltip: voice.isCameraEnabled
                  ? 'Desativar câmera'
                  : 'Ativar câmera',
              active: voice.isCameraEnabled,
              onPressed: voiceNotifier.toggleCamera,
            ),
            _barButton(
              context,
              icon: Icons.present_to_all,
              tooltip: voice.isScreenSharing
                  ? 'Parar compartilhamento'
                  : 'Compartilhar tela',
              active: voice.isScreenSharing,
              onPressed: voice.isReconnecting ? null : onToggleScreenShare,
            ),
            _barButton(
              context,
              icon: Icons.chat_bubble_outline,
              tooltip: ui.chatOpen ? 'Fechar chat' : 'Abrir chat',
              active: ui.chatOpen,
              onPressed: uiNotifier.toggleChat,
            ),
            _barButton(
              context,
              icon: Icons.settings_outlined,
              tooltip: 'Configurações',
              onPressed: onOpenSettings,
            ),
            _moreButton(context, ref, ui),
            _barButton(
              context,
              icon: Icons.fullscreen,
              tooltip: 'Tela cheia',
              onPressed: onToggleFullscreen,
            ),
            IconButton(
              onPressed: onLeave,
              tooltip: 'Sair da chamada',
              style: IconButton.styleFrom(
                minimumSize: const Size.square(40),
                backgroundColor: AppTokens.accentDanger,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.call_end),
            ),
          ],
        ),
      ),
    );
  }

  /// Botão `⋯` ancorado no padrão [AppMenuButton] compacto do app, com
  /// a mesma pastilha tonal 40px dos demais botões da barra.
  Widget _moreButton(BuildContext context, WidgetRef ref, TheaterUiState ui) {
    final colors = context.appColors;
    return AppMenuButton<TheaterMoreAction>(
      tooltip: 'Layout e ações extras',
      offset: const Offset(0, -8),
      padding: EdgeInsets.zero,
      onSelected: (action) =>
          handleTheaterMoreAction(context, ref, arg, action),
      itemBuilder: (_) => theaterMoreMenuItems(ui),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: colors.textPrimary.withValues(alpha: 0.08),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(Icons.more_horiz, color: colors.textPrimary),
      ),
    );
  }

  Widget _barButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    bool active = false,
  }) {
    final colors = context.appColors;
    return IconButton.filledTonal(
      onPressed: onPressed,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(40),
        backgroundColor: active ? AppTokens.accentDanger : null,
        foregroundColor: colors.textPrimary,
      ),
      icon: Icon(icon),
    );
  }
}
