import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_state.dart';
import '../../core/rtc/media_devices_provider.dart';
import '../../core/rtc/rtc_providers.dart';
import '../../core/rtc/rtc_service.dart';
import '../../core/rtc/screen_share_picker.dart';
import '../../core/ui/settings_modal.dart';
import '../../core/ui/settings_modal_sidebar.dart';
import '../../core/ui/ui.dart';
import '../voice/voice_controls_provider.dart';
import '../voice/voice_providers.dart';

/// Rodapé da sidebar no padrão Discord: sessão de voz no topo, ações de mídia
/// agrupadas e identidade/controles pessoais na base.
class UserPanel extends ConsumerWidget {
  const UserPanel({
    super.key,
    this.onOpenSettings,
    this.voiceArg,
    this.voiceChannelName,
    this.voiceState,
    this.onLeaveVoice,
    this.floating = false,
  });

  final VoidCallback? onOpenSettings;
  final ({String serverId, String channelId})? voiceArg;
  final String? voiceChannelName;
  final VoiceState? voiceState;
  final VoidCallback? onLeaveVoice;

  /// Card flutuante sobreposto à sidebar/rail (com sombra e raio maior),
  /// em vez do rodapé acoplado com fundo corrido.
  final bool floating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider).valueOrNull;
    final user = authState is Authenticated ? authState.user : null;
    final name = user?.username ?? '…';
    final avatarUrl = user?.avatarUrl;
    final devices = ref.watch(audioDevicesProvider);
    final controls = ref.watch(voiceControlsProvider);
    final activeVoiceState = voiceState;
    final showVoiceActions =
        voiceArg != null &&
        activeVoiceState != null &&
        activeVoiceState.status != VoiceSessionStatus.idle;
    final canToggleVoiceMedia =
        activeVoiceState?.status == VoiceSessionStatus.connected &&
        !(activeVoiceState?.isReconnecting ?? false);

    return Container(
      color: floating ? Colors.transparent : AppTokens.surface1,
      padding: floating
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(6, 0, 6, 6),
      child: Container(
        key: const Key('user-panel-card'),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTokens.surface2,
          borderRadius: BorderRadius.circular(
            floating ? AppRadius.lg : AppRadius.md,
          ),
          border: Border.all(color: AppTokens.borderSubtle, width: 1),
          boxShadow: floating
              ? const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showVoiceActions)
              _VoiceConnectionPanel(
                channelName: voiceChannelName ?? 'Canal de voz',
                state: voiceState!,
                canToggleMedia: canToggleVoiceMedia,
                onToggleCamera: () => unawaited(
                  ref
                      .read(voiceControllerProvider(voiceArg!).notifier)
                      .toggleCamera(),
                ),
                onToggleScreenShare: () =>
                    unawaited(_toggleScreenShare(context, ref)),
                onLeave: onLeaveVoice,
              ),
            Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppTokens.surface2,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTokens.borderHairline,
                          width: 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      clipBehavior: Clip.antiAlias,
                      child: avatarUrl != null
                          ? Image.network(
                              avatarUrl,
                              width: 34,
                              height: 34,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => _initial(name),
                            )
                          : _initial(name),
                    ),
                    const Positioned(
                      right: -2,
                      bottom: -2,
                      child: PresenceDot(
                        status: PresenceStatus.online,
                        size: 10,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 9),
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
                      activeColor: AppTokens.accentDanger,
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
                    const SizedBox(width: 6),
                    _SplitMediaControl(
                      icon: controls.isDeafened
                          ? Icons.headset_off_outlined
                          : Icons.headset_outlined,
                      isActive: controls.isDeafened,
                      activeColor: AppTokens.accentDanger,
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
                    const SizedBox(width: 6),
                    AppIconButton(
                      icon: Icons.settings_outlined,
                      tooltip: 'Configurações',
                      minSize: 28,
                      iconSize: 18,
                      onPressed: onOpenSettings,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleScreenShare(BuildContext context, WidgetRef ref) async {
    final arg = voiceArg;
    final current = voiceState;
    if (arg == null ||
        current == null ||
        current.status != VoiceSessionStatus.connected) {
      return;
    }
    final notifier = ref.read(voiceControllerProvider(arg).notifier);
    if (current.isScreenSharing) {
      await notifier.stopScreenShare();
      return;
    }
    final selection = await RtcScreenSharePicker.show(
      context,
      backend: ref.read(nativeMediaServicesProvider).screenShare,
    );
    if (selection == null) return;
    await notifier.startScreenShare(
      selection.sourceId,
      includeSystemAudio: current.includeSystemAudio,
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
      icon: const Icon(
        Icons.arrow_drop_down,
        size: 14,
        color: AppTokens.textSecondary,
      ),
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
          child: const Text(
            'Padrão do sistema',
            style: TextStyle(fontFamily: 'Geist', fontSize: 13),
          ),
        ),
        if (unavailable)
          const PopupMenuItem<String>(
            enabled: false,
            child: Text(
              'Preferido indisponível; usando o padrão.',
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 12,
                color: AppTokens.accentAmber,
              ),
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
          child: Text(
            'Configurações de voz',
            style: TextStyle(fontFamily: 'Geist', fontSize: 13),
          ),
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

class _VoiceConnectionPanel extends StatelessWidget {
  const _VoiceConnectionPanel({
    required this.channelName,
    required this.state,
    required this.canToggleMedia,
    required this.onToggleCamera,
    required this.onToggleScreenShare,
    this.onLeave,
  });

  final String channelName;
  final VoiceState state;
  final bool canToggleMedia;
  final VoidCallback onToggleCamera;
  final VoidCallback onToggleScreenShare;
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) {
    final isConnecting = state.status == VoiceSessionStatus.connecting;
    final isConnected = state.status == VoiceSessionStatus.connected;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.only(bottom: 8),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTokens.borderHairline, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ConnectionLatency(latencyMs: state.latencyMs),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isConnecting ? 'Conectando…' : 'Voz conectada',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isConnected
                            ? AppTokens.accentGreen
                            : AppTokens.textSecondary,
                      ),
                    ),
                    Text(
                      channelName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 10.5,
                        color: AppTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              AppIconButton(
                icon: Icons.call_end,
                tooltip: 'Sair do canal de voz',
                color: AppTokens.accentDanger,
                onPressed: onLeave,
                minSize: 28,
                iconSize: 17,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _VoiceActionButton(
                  icon: state.isCameraEnabled
                      ? Icons.videocam
                      : Icons.videocam_off_outlined,
                  tooltip: state.isCameraEnabled
                      ? 'Desativar câmera'
                      : 'Ativar câmera',
                  isActive: state.isCameraEnabled,
                  onPressed: canToggleMedia ? onToggleCamera : null,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _VoiceActionButton(
                  icon: Icons.present_to_all,
                  tooltip: state.isScreenSharing
                      ? 'Parar compartilhamento'
                      : 'Compartilhar tela',
                  isActive: state.isScreenSharing,
                  onPressed: canToggleMedia ? onToggleScreenShare : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConnectionLatency extends StatelessWidget {
  const _ConnectionLatency({required this.latencyMs});

  final int? latencyMs;

  @override
  Widget build(BuildContext context) {
    final latency = latencyMs;
    final color = switch (latency) {
      null => AppTokens.textMuted,
      <= 150 => AppTokens.accentGreen,
      <= 300 => AppTokens.accentAmber,
      _ => AppTokens.accentPurple,
    };
    return Tooltip(
      message: latency == null
          ? 'Medindo latência da conexão…'
          : 'Latência da conexão: $latency ms',
      child: Icon(
        Icons.wifi_rounded,
        size: 18,
        color: color,
        semanticLabel: 'Latência da conexão',
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
          minSize: 28,
          iconSize: 18,
          isActive: isActive,
          activeColor: activeColor,
          onPressed: onMainPressed,
        ),
        SizedBox(width: 14, height: 28, child: menu),
      ],
    );
  }
}

class _VoiceActionButton extends StatelessWidget {
  const _VoiceActionButton({
    required this.icon,
    required this.tooltip,
    required this.isActive,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        style: IconButton.styleFrom(
          foregroundColor: isActive
              ? AppTokens.accentDanger
              : AppTokens.accentGreen,
          disabledForegroundColor: AppTokens.textMuted,
          backgroundColor: AppTokens.surfaceBase,
          minimumSize: Size.zero,
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
      ),
    );
  }
}
