import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/voice/voice_volume_controller.dart';
import 'ds_tokens.dart';

class ParticipantVolumeButton extends ConsumerWidget {
  const ParticipantVolumeButton({
    super.key,
    required this.identity,
    required this.displayName,
    this.iconColor = AppTokens.textSecondary,
    this.iconSize = 14,
  });

  /// Identity estável do LiveKit (`user_<userId>`).
  final String identity;
  final String displayName;
  final Color iconColor;
  final double iconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ParticipantVolumeMenuAnchor(
      identity: identity,
      displayName: displayName,
      builder: (context, controller, percent, muted, child) {
        final label = muted ? 'silenciado' : '$percent%';
        return IconButton(
          tooltip: 'Volume de $displayName ($label)',
          icon: Icon(
            muted || percent == 0
                ? Icons.volume_off
                : percent > 100
                ? Icons.volume_up
                : Icons.volume_down,
            size: iconSize,
          ),
          color: iconColor,
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
  });

  final String identity;
  final String displayName;
  final bool enabled;
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
    final state = ref.watch(voiceVolumeProvider);
    final percent = state.percentOf(widget.identity);
    final muted = state.isParticipantMuted(widget.identity);
    return MenuAnchor(
      controller: _menuController,
      childFocusNode: _anchorFocusNode,
      useRootOverlay: true,
      consumeOutsideTap: true,
      clipBehavior: Clip.none,
      style: _menuStyle(width: 228),
      menuChildren: [
        _ParticipantVolumePanel(
          identity: widget.identity,
          displayName: widget.displayName,
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
  });

  final String identity;
  final String displayName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(voiceVolumeProvider);
    final percent = state.percentOf(identity);
    final muted = state.isParticipantMuted(identity);
    final controller = ref.read(voiceVolumeProvider.notifier);
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
              style: const TextStyle(
                fontFamily: 'Geist',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTokens.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            _VolumeRow(
              label: 'Volume do usuário',
              percent: percent,
              max: 200,
              onChanged: (value) =>
                  controller.setParticipantPercent(identity, value),
              onReset: percent == 100
                  ? null
                  : () => controller.resetParticipant(identity),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1, color: AppTokens.borderHairline),
            const SizedBox(height: 6),
            _MuteRow(
              muted: muted,
              onChanged: (value) =>
                  controller.setParticipantMuted(identity, value),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 12.5,
                  color: AppTokens.textPrimary,
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
            activeTrackColor: AppTokens.accentVercel,
            inactiveTrackColor: AppTokens.borderStrong,
            thumbColor: AppTokens.textPrimary,
            overlayColor: AppTokens.accentVercel.withValues(alpha: 0.16),
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
  const _MuteRow({required this.muted, required this.onChanged});

  final bool muted;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: () => onChanged(!muted),
      child: SizedBox(
        height: 32,
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Silenciar para mim',
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 12.5,
                  color: AppTokens.textPrimary,
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

MenuStyle _menuStyle({required double width}) {
  return MenuStyle(
    minimumSize: WidgetStatePropertyAll(Size(width, 0)),
    maximumSize: WidgetStatePropertyAll(Size(width, double.infinity)),
    backgroundColor: const WidgetStatePropertyAll(AppTokens.surface2),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    shadowColor: const WidgetStatePropertyAll(Colors.black87),
    elevation: const WidgetStatePropertyAll(16),
    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: AppTokens.borderSubtle, width: 1),
      ),
    ),
  );
}

class _OpenParticipantVolumeIntent extends Intent {
  const _OpenParticipantVolumeIntent();
}
