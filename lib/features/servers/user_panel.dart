import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_state.dart';
import '../../core/rtc/media_devices_provider.dart';
import '../../core/rtc/rtc_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/app_icon_button.dart';
import '../../core/ui/settings_modal.dart';
import '../../core/ui/settings_modal_sidebar.dart';
import '../voice/voice_controls_provider.dart';

/// Rodapé da sidebar (wireframe v3 §4.2): avatar 32 + nome + status, e 3
/// ícones de ação (mic/fones/⚙️). O ⚙️ dispara [onOpenSettings] (SPEC 3
/// implementa o modal; aqui só a cablagem).
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
      // color + decoration simultâneos disparam a assert do Flutter
      // ("color is just a shorthand for decoration") — cor vai no
      // BoxDecoration. Padding 10/14 conforme wireframe (.user-panel).
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: AppThemeColors.card,
        border: Border(top: BorderSide(color: AppThemeColors.hairline)),
      ),
      child: Row(
        children: [
          // Avatar 32 com "ring" (wireframe: .up-avatar .ring radius 8,
          // borda hairline, fundo bg-surface).
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppThemeColors.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppThemeColors.hairline),
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
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Text(
                  'Online',
                  style: TextStyle(fontSize: 11, color: AppStatusColors.online),
                ),
              ],
            ),
          ),
          // Ícones 28x28 com gap 4 (wireframe: .up-icons gap 4, .up-icon
          // 28x28 radius 6).
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SplitMediaControl(
                icon: controls.isMicrophoneEnabled
                    ? Icons.mic_none
                    : Icons.mic_off_outlined,
                tooltip: controls.isDeafened
                    ? 'Desative o ensurdecer para usar o microfone'
                    : (controls.isMuted
                          ? 'Ativar microfone'
                          : 'Desativar microfone'),
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
                minSize: 28,
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
      icon: const Icon(Icons.arrow_drop_down, size: 16),
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
          child: Text(title, style: Theme.of(context).textTheme.labelLarge),
        ),
        CheckedPopupMenuItem<String>(
          value: defaultValue,
          checked: selectedId == null,
          child: const Text('Padrão do sistema'),
        ),
        if (unavailable)
          const PopupMenuItem<String>(
            enabled: false,
            child: Text('Preferido indisponível; usando o padrão.'),
          ),
        for (var index = 0; index < devices.length; index++)
          CheckedPopupMenuItem<String>(
            value: devices[index].id,
            checked: devices[index].id == selectedId,
            child: Text(
              devices[index].label.isEmpty
                  ? '$title ${index + 1}'
                  : devices[index].label,
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: settingsValue,
          child: Text('Configurações de voz'),
        ),
      ],
    );
  }

  Widget _initial(String name) {
    return Text(
      name.isEmpty ? '?' : name[0].toUpperCase(),
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
  }
}

class _SplitMediaControl extends StatelessWidget {
  const _SplitMediaControl({
    required this.icon,
    required this.tooltip,
    required this.onMainPressed,
    required this.menu,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onMainPressed;
  final PopupMenuButton<String> menu;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIconButton(
          icon: icon,
          tooltip: tooltip,
          minSize: 28,
          onPressed: onMainPressed,
        ),
        SizedBox(width: 16, height: 28, child: menu),
      ],
    );
  }
}
