import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rtc/rtc_service.dart';
import '../../features/voice/voice_volume_controller.dart';
import '../theme/appearance_theme.dart';
import 'ds_tokens.dart';

class ParticipantVolumeButton extends ConsumerWidget {
  const ParticipantVolumeButton({
    super.key,
    required this.identity,
    required this.displayName,
    this.source = RtcAudioSource.microphone,
    this.iconColor,
    this.iconSize = 14,
    this.padding,
    this.constraints,
    this.audioAvailable,
  });

  /// Identity estável do LiveKit (`user_<userId>`).
  final String identity;
  final String displayName;

  /// Fonte controlada: voz ou áudio da transmissão (tile de tela).
  final RtcAudioSource source;

  /// Se a fonte existe de verdade (null = desconhecido, comportamento atual).
  /// Tile de tela sem track de `screenShareAudio` passa false → ícone mutado
  /// (regra 6 da SPEC de áudio de sistema).
  final bool? audioAvailable;
  final Color? iconColor;
  final double iconSize;

  /// Padding/constraints do IconButton (default = padrão do Material).
  /// Overlays sobre vídeo passam versão compacta (zero + tight).
  final EdgeInsetsGeometry? padding;
  final BoxConstraints? constraints;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    return ParticipantVolumeMenuAnchor(
      identity: identity,
      displayName: displayName,
      source: source,
      builder: (context, controller, percent, muted, child) {
        final noAudio = audioAvailable == false;
        final label = noAudio
            ? 'sem áudio'
            : muted
            ? 'silenciado'
            : '$percent%';
        final tooltip = source == RtcAudioSource.screenShareAudio
            ? 'Volume da transmissão de $displayName ($label)'
            : 'Volume de $displayName ($label)';
        return IconButton(
          tooltip: tooltip,
          padding: padding ?? const EdgeInsets.all(8),
          constraints: constraints,
          icon: Icon(
            noAudio || muted || percent == 0
                ? Icons.volume_off
                : percent > 100
                ? Icons.volume_up
                : Icons.volume_down,
            size: iconSize,
          ),
          color: iconColor ?? colors.textSecondary,
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
        );
      },
    );
  }
}

class ParticipantVolumeMenuRegion extends StatelessWidget {
  const ParticipantVolumeMenuRegion({
    super.key,
    required this.identity,
    required this.displayName,
    required this.child,
    this.enabled = true,
  });

  final String identity;
  final String displayName;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ParticipantVolumeMenuAnchor(
      identity: identity,
      displayName: displayName,
      enabled: enabled,
      child: child,
      builder: (context, controller, percent, muted, child) {
        Offset? secondaryPosition;
        void openAtPointer() {
          if (!enabled) return;
          controller.open(position: secondaryPosition);
        }

        return Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.contextMenu):
                _OpenParticipantVolumeIntent(),
            SingleActivator(LogicalKeyboardKey.f10, shift: true):
                _OpenParticipantVolumeIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _OpenParticipantVolumeIntent:
                  CallbackAction<_OpenParticipantVolumeIntent>(
                    onInvoke: (_) {
                      openAtPointer();
                      return null;
                    },
                  ),
            },
            child: FocusableActionDetector(
              enabled: enabled,
              mouseCursor: SystemMouseCursors.basic,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onSecondaryTapDown: enabled
                    ? (details) => secondaryPosition = details.localPosition
                    : null,
                onSecondaryTap: enabled ? openAtPointer : null,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

class ParticipantVolumeMenuAnchor extends ConsumerStatefulWidget {
  const ParticipantVolumeMenuAnchor({
    super.key,
    required this.identity,
    required this.displayName,
    required this.builder,
    this.child,
    this.enabled = true,
    this.source = RtcAudioSource.microphone,
  });

  final String identity;
  final String displayName;
  final bool enabled;

  /// Fonte lida/controlada pelo painel (voz ou transmissão).
  final RtcAudioSource source;
  final Widget? child;
  final Widget Function(
    BuildContext context,
    MenuController controller,
    int percent,
    bool muted,
    Widget? child,
  )
  builder;

  @override
  ConsumerState<ParticipantVolumeMenuAnchor> createState() =>
      _ParticipantVolumeMenuAnchorState();
}

class _ParticipantVolumeMenuAnchorState
    extends ConsumerState<ParticipantVolumeMenuAnchor> {
  final MenuController _menuController = MenuController();
  final FocusNode _anchorFocusNode = FocusNode(
    debugLabel: 'participant-volume',
  );

  @override
  void didUpdateWidget(ParticipantVolumeMenuAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _menuController.isOpen) {
      _menuController.close();
    }
  }

  @override
  void dispose() {
    _anchorFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final state = ref.watch(voiceVolumeProvider);
    final percent = state.percentOf(widget.identity, source: widget.source);
    final muted = state.isParticipantMuted(
      widget.identity,
      source: widget.source,
    );
    return MenuAnchor(
      controller: _menuController,
      childFocusNode: _anchorFocusNode,
      useRootOverlay: true,
      consumeOutsideTap: true,
      clipBehavior: Clip.none,
      style: _menuStyle(width: 228, colors: colors),
      menuChildren: [
        _ParticipantVolumePanel(
          identity: widget.identity,
          displayName: widget.displayName,
          source: widget.source,
        ),
      ],
      builder: (context, controller, child) => Focus(
        focusNode: _anchorFocusNode,
        child: widget.builder(context, controller, percent, muted, child),
      ),
      child: widget.child,
    );
  }
}

class _ParticipantVolumePanel extends ConsumerWidget {
  const _ParticipantVolumePanel({
    required this.identity,
    required this.displayName,
    required this.source,
  });

  final String identity;
  final String displayName;
  final RtcAudioSource source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final state = ref.watch(voiceVolumeProvider);
    final percent = state.percentOf(identity, source: source);
    final muted = state.isParticipantMuted(identity, source: source);
    final controller = ref.read(voiceVolumeProvider.notifier);
    final isScreen = source == RtcAudioSource.screenShareAudio;
    return SizedBox(
      width: 228,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              displayName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            _VolumeRow(
              label: isScreen ? 'Volume da transmissão' : 'Volume do usuário',
              percent: percent,
              max: 200,
              onChanged: (value) => controller.setParticipantPercent(
                identity,
                value,
                source: source,
              ),
              onReset: percent == 100
                  ? null
                  : () => controller.resetParticipant(identity, source: source),
            ),
            const SizedBox(height: 8),
            Divider(height: 1, color: colors.borderHairline),
            const SizedBox(height: 6),
            _MuteRow(
              label: isScreen ? 'Silenciar transmissão' : 'Silenciar para mim',
              muted: muted,
              onChanged: (value) => controller.setParticipantMuted(
                identity,
                value,
                source: source,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VolumeRow extends StatelessWidget {
  const _VolumeRow({
    required this.label,
    required this.percent,
    required this.max,
    required this.onChanged,
    required this.onReset,
  });

  final String label;
  final int percent;
  final int max;
  final ValueChanged<int> onChanged;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 12.5,
                  color: colors.textPrimary,
                ),
              ),
            ),
            TextButton(
              onPressed: onReset,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(36, 24),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text('$percent%', style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: colors.accent,
            inactiveTrackColor: colors.borderStrong,
            thumbColor: colors.textPrimary,
            overlayColor: colors.accent.withValues(alpha: 0.16),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: percent.toDouble(),
            min: 0,
            max: max.toDouble(),
            divisions: max ~/ 5,
            label: '$percent%',
            onChanged: (value) => onChanged((value / 5).round() * 5),
          ),
        ),
      ],
    );
  }
}

class _MuteRow extends StatelessWidget {
  const _MuteRow({
    required this.label,
    required this.muted,
    required this.onChanged,
  });

  final String label;
  final bool muted;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: () => onChanged(!muted),
      child: SizedBox(
        height: 32,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 12.5,
                  color: colors.textPrimary,
                ),
              ),
            ),
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: muted,
                onChanged: (value) => onChanged(value ?? false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

MenuStyle _menuStyle({required double width, required AppThemePalette colors}) {
  return MenuStyle(
    minimumSize: WidgetStatePropertyAll(Size(width, 0)),
    maximumSize: WidgetStatePropertyAll(Size(width, double.infinity)),
    backgroundColor: WidgetStatePropertyAll(colors.surface2),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    shadowColor: const WidgetStatePropertyAll(Colors.black87),
    elevation: const WidgetStatePropertyAll(16),
    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: colors.borderSubtle, width: 1),
      ),
    ),
  );
}

class _OpenParticipantVolumeIntent extends Intent {
  const _OpenParticipantVolumeIntent();
}
