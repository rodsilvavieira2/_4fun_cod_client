import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_state.dart';
import '../../core/rtc/media_devices_provider.dart';
import '../../core/rtc/rtc_service.dart';
import '../../core/ui/settings_modal.dart';
import '../../core/ui/settings_modal_sidebar.dart';
import '../../core/ui/ui.dart';
import '../voice/voice_controls_provider.dart';

/// Rodapé da sidebar (wireframe v4 macOS):
/// Avatar 32 + nome + status dot + controles de áudio (mic/fones/⚙️) estilo compacto.
class UserPanel extends ConsumerWidget {
  const UserPanel({super.key, this.onOpenSettings});

  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider).valueOrNull;
    final user = authState is Authenticated ? authState.user : null;
    final name = user?.name ?? '…';
    final avatarUrl = user?.avatarUrl;
    final devices = ref.watch(audioDevicesProvider);
    final controls = ref.watch(voiceControlsProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: AppTokens.surface1,
        border: Border(
          top: BorderSide(color: AppTokens.borderHairline, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Avatar com PresenceDot
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTokens.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: AppTokens.borderHairline, width: 1),
                ),
                alignment: Alignment.center,
                clipBehavior: Clip.antiAlias,
                child: avatarUrl != null
                    ? Image.network(
                        avatarUrl,
                        width: 32,
                        height: 32,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _initial(name),
                      )
                    : _initial(name),
              ),
              const Positioned(
                right: -2,
                bottom: -2,
                child: PresenceDot(status: PresenceStatus.online, size: 10),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.textPrimary,
                  ),
                ),
                const Text(
                  'Online',
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 11,
                    color: AppTokens.accentGreen,
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SplitMediaControl(
                icon: controls.isMicrophoneEnabled
                    ? Icons.mic_none
                    : Icons.mic_off_outlined,
                isActive: !controls.isMicrophoneEnabled,
                activeColor: AppTokens.accentPurple,
                tooltip: controls.isDeafened
                    ? 'Desative o ensurdecer para usar o microfone'
                    : (controls.isPushToTalkEnabled &&
                              !controls.isPushToTalkPressed &&
                              !controls.isMuted &&
                              controls.isPushToTalkRegistered
                          ? 'Push to Talk ativo: segure ${controls.pushToTalkBinding?.displayLabel ?? 'o atalho'} para transmitir'
                          : (controls.isMuted
                                ? 'Ativar microfone'
                                : 'Desativar microfone')),
                onMainPressed: controls.isDeafened || controls.isApplying
                    ? null
                    : () => unawaited(_toggleMicrophone(context, ref)),
                menu: _audioMenu(
                  context: context,
                  devices: devices.inputs,
                  selectedId: devices.preferredInputId,
                  unavailable: devices.preferredInputUnavailable,
                  title: 'Dispositivo de entrada',
                  onSelected: (id) => _selectInput(context, ref, id),
                ),
              ),
              _SplitMediaControl(
                icon: controls.isDeafened
                    ? Icons.headset_off_outlined
                    : Icons.headset_outlined,
                isActive: controls.isDeafened,
                activeColor: AppTokens.accentPurple,
                tooltip: controls.isDeafened
                    ? 'Parar de ensurdecer'
                    : 'Ensurdecer',
                onMainPressed: controls.isApplying
                    ? null
                    : () => unawaited(_toggleDeafen(context, ref)),
                menu: _audioMenu(
                  context: context,
                  devices: devices.outputs,
                  selectedId: devices.preferredOutputId,
                  unavailable: devices.preferredOutputUnavailable,
                  title: 'Dispositivo de saída',
                  onSelected: (id) => _selectOutput(context, ref, id),
                ),
              ),
              AppIconButton(
                icon: Icons.settings_outlined,
                tooltip: 'Configurações',
                minSize: 26,
                onPressed: onOpenSettings,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _selectInput(
    BuildContext context,
    WidgetRef ref,
    String? id,
  ) async {
    final changed = await ref
        .read(audioDevicesProvider.notifier)
        .selectInput(id);
    if (!changed && context.mounted) {
      final message = ref.read(audioDevicesProvider).errorMessage;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message ?? 'Não foi possível trocar o microfone.'),
        ),
      );
    }
  }

  Future<void> _toggleMicrophone(BuildContext context, WidgetRef ref) async {
    final changed = await ref
        .read(voiceControlsProvider.notifier)
        .toggleMicrophone();
    if (!changed && context.mounted) {
      final message = ref.read(voiceControlsProvider).errorMessage;
      if (message != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  Future<void> _toggleDeafen(BuildContext context, WidgetRef ref) async {
    final changed = await ref
        .read(voiceControlsProvider.notifier)
        .toggleDeafen();
    if (!changed && context.mounted) {
      final message = ref.read(voiceControlsProvider).errorMessage;
      if (message != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  Future<void> _selectOutput(
    BuildContext context,
    WidgetRef ref,
    String? id,
  ) async {
    final changed = await ref
        .read(audioDevicesProvider.notifier)
        .selectOutput(id);
    if (!changed && context.mounted) {
      final message = ref.read(audioDevicesProvider).errorMessage;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message ?? 'Não foi possível trocar a saída.')),
      );
    }
  }

  PopupMenuButton<String> _audioMenu({
    required BuildContext context,
    required List<RtcAudioDevice> devices,
    required String? selectedId,
    required bool unavailable,
    required String title,
    required Future<void> Function(String? id) onSelected,
  }) {
    const defaultValue = '__system_default__';
    const settingsValue = '__voice_settings__';
    return PopupMenuButton<String>(
      tooltip: title,
      padding: EdgeInsets.zero,
      color: AppTokens.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: AppTokens.borderSubtle, width: 1),
      ),
      elevation: 12,
      icon: const Icon(Icons.arrow_drop_down, size: 14, color: AppTokens.textSecondary),
      onSelected: (value) {
        if (value == settingsValue) {
          showSettingsModal(
            context,
            initialSection: SettingsSection.voiceVideo,
          );
          return;
        }
        unawaited(onSelected(value == defaultValue ? null : value));
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Text(
            title,
            style: const TextStyle(
              fontFamily: 'Geist',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTokens.textMuted,
            ),
          ),
        ),
        CheckedPopupMenuItem<String>(
          value: defaultValue,
          checked: selectedId == null,
          child: const Text('Padrão do sistema', style: TextStyle(fontFamily: 'Geist', fontSize: 13)),
        ),
        if (unavailable)
          const PopupMenuItem<String>(
            enabled: false,
            child: Text(
              'Preferido indisponível; usando o padrão.',
              style: TextStyle(fontFamily: 'Geist', fontSize: 12, color: AppTokens.accentAmber),
            ),
          ),
        for (var index = 0; index < devices.length; index++)
          CheckedPopupMenuItem<String>(
            value: devices[index].id,
            checked: devices[index].id == selectedId,
            child: Text(
              devices[index].label.isEmpty
                  ? '$title ${index + 1}'
                  : devices[index].label,
              style: const TextStyle(fontFamily: 'Geist', fontSize: 13),
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: settingsValue,
          child: Text('Configurações de voz', style: TextStyle(fontFamily: 'Geist', fontSize: 13)),
        ),
      ],
    );
  }

  Widget _initial(String name) {
    return Text(
      name.isEmpty ? '?' : name[0].toUpperCase(),
      style: const TextStyle(
        fontFamily: 'Geist',
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppTokens.textPrimary,
      ),
    );
  }
}

class _SplitMediaControl extends StatelessWidget {
  const _SplitMediaControl({
    required this.icon,
    required this.tooltip,
    required this.onMainPressed,
    required this.menu,
    this.isActive = false,
    this.activeColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onMainPressed;
  final PopupMenuButton<String> menu;
  final bool isActive;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIconButton(
          icon: icon,
          tooltip: tooltip,
          minSize: 26,
          iconSize: 16,
          isActive: isActive,
          activeColor: activeColor,
          onPressed: onMainPressed,
        ),
        SizedBox(width: 14, height: 26, child: menu),
      ],
    );
  }
}
