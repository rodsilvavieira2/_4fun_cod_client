import 'package:flutter/material.dart';

import '../rtc/rtc_service.dart';
import '../theme/appearance_theme.dart';
import 'ds_tokens.dart';
import 'participant_volume_popover.dart';

/// Toolbar individual do tile de transmissão (screen, grid/spotlight).
///
/// Mesmo visual do antigo dock global: pill [surfaceGlass], borda sutil,
/// sombra popover, botões 40px. Remoto = volume + assistir/parar; local =
/// só parar o share. Sem expandir (foco via click no tile, fullscreen via
/// botão do topo). Sem miniatura (sem espaço).
class TransmitTileToolbar extends StatelessWidget {
  const TransmitTileToolbar({
    super.key,
    required this.identity,
    required this.displayName,
    required this.isLocal,
    required this.isWatching,
    this.audioAvailable,
    this.onToggleWatch,
    this.onStopShare,
    this.visible = true,
  });

  final String identity;
  final String displayName;
  final bool isLocal;
  final bool isWatching;

  /// Se a transmissão tem áudio de sistema (null = desconhecido).
  /// Sem track, o volume mostra mutado (mesma regra do overlay de nome).
  final bool? audioAvailable;

  /// Assistir/parar (remoto). Nulo = sem botão.
  final VoidCallback? onToggleWatch;

  /// Parar o share (local). Nulo = sem botão.
  final VoidCallback? onStopShare;

  /// Fade-out individual do tile: false some com fade (fica só o vídeo).
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final buttons = <Widget>[
      if (!isLocal)
        ParticipantVolumeButton(
          identity: identity,
          displayName: displayName,
          source: RtcAudioSource.screenShareAudio,
          audioAvailable: audioAvailable,
          iconColor: colors.textPrimary,
          iconSize: 20,
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        ),
      if (!isLocal && onToggleWatch != null)
        _toolbarToggleButton(
          colors: colors,
          icon: isWatching ? Icons.visibility_off : Icons.visibility,
          tooltip: isWatching ? 'Parar de assistir' : 'Assistir transmissão',
          onPressed: onToggleWatch,
        ),
      if (isLocal && onStopShare != null)
        _toolbarToggleButton(
          colors: colors,
          icon: Icons.present_to_all,
          active: true,
          activeColor: AppTokens.accentDanger,
          tooltip: 'Parar compartilhamento',
          onPressed: onStopShare,
        ),
    ];
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      right: 0,
      bottom: 8,
      child: Center(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: visible ? 1 : 0,
          child: IgnorePointer(
            ignoring: !visible,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.surfaceGlass,
                  borderRadius: AppRadius.brFull,
                  border: Border.all(color: colors.borderSubtle),
                  boxShadow: AppShadows.popover,
                ),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: buttons,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Botão circular 40px — o mesmo controle do dock global extinto.
  Widget _toolbarToggleButton({
    required AppThemePalette colors,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    bool active = false,
    Color? activeColor,
  }) {
    return IconButton.filledTonal(
      onPressed: onPressed,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(40),
        backgroundColor: active ? activeColor : null,
        foregroundColor: colors.textPrimary,
      ),
      icon: Icon(icon),
    );
  }
}
