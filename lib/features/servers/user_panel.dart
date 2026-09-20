import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_state.dart';
import '../../core/rtc/media_devices_provider.dart';
import '../../core/rtc/rtc_providers.dart';
import '../../core/rtc/rtc_service.dart';
import '../voice/go_live_modal.dart';
import '../../core/ui/settings_modal.dart';
import '../../core/ui/settings_modal_sidebar.dart';
import '../../core/ui/ui.dart';
import '../voice/voice_controls_provider.dart';
import '../voice/voice_providers.dart';
import '../voice/voice_volume_controller.dart';

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
    final colors = context.appColors;
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
      color: floating ? Colors.transparent : colors.surface1,
      padding: floating
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(6, 0, 6, 6),
      child: Container(
        key: const Key('user-panel-card'),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(
            floating ? AppRadius.lg : AppRadius.md,
          ),
          border: Border.all(color: colors.borderSubtle, width: 1),
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
                        color: colors.surface2,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colors.borderHairline,
                          width: 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      clipBehavior: Clip.antiAlias,
                      child: avatarUrl != null
                          ? AppFileImage(
                              path: avatarUrl,
                              width: 34,
                              height: 34,
                              fallback: _initial(name),
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
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
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
                          ? AppIcons.mic
                          : AppIcons.micOff,
                      isActive: !controls.isMicrophoneEnabled,
                      activeColor: AppTokens.accentDanger,
                      tooltip: controls.isDeafened
                          ? 'Desative o ensurdecer para usar o microfone'
                          : (controls.isPushToTalkEnabled &&
                                    !controls.isPushToTalkPressed &&
                                    !controls.isMuted
                                ? (controls.isPushToTalkRegistered
                                      ? 'Push to Talk ativo: segure ${controls.pushToTalkBinding?.displayLabel ?? 'o atalho'} para transmitir'
                                      : 'Push to Talk ativo em foco: segure ${controls.pushToTalkBinding?.displayLabel ?? 'o atalho'} para transmitir')
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
                        loading: devices.isLoading,
                        title: 'Dispositivo de entrada',
                        deviceIcon: AppIcons.mic,
                        isInput: true,
                        onSelected: (id) => _selectInput(context, ref, id),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _SplitMediaControl(
                      icon: controls.isDeafened
                          ? AppIcons.headsetOff
                          : AppIcons.headset,
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
                        loading: devices.isLoading,
                        title: 'Dispositivo de saída',
                        deviceIcon: AppIcons.headset,
                        isInput: false,
                        onSelected: (id) => _selectOutput(context, ref, id),
                      ),
                    ),
                    const SizedBox(width: 6),
                    AppIconButton(
                      icon: AppIcons.settings,
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
    // Modal Go Live (tipo + qualidade) → seletor do tipo → start. Cancelar em
    // qualquer etapa retorna null e nada inicia.
    final goLive = await showGoLiveModal(
      context,
      backend: ref.read(nativeMediaServicesProvider).screenShare,
      pendingQuality: ref.read(rtcServiceProvider).screenShareQuality,
      channelName: voiceChannelName,
    );
    if (goLive == null) return;
    await notifier.startScreenShare(
      goLive.sourceId,
      includeSystemAudio: goLive.includeAudio,
      quality: goLiveQualityFor(goLive.quality),
      kind: goLive.kind,
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

  Widget _audioMenu({
    required BuildContext context,
    required List<RtcAudioDevice> devices,
    required String? selectedId,
    required bool unavailable,
    required bool loading,
    required String title,
    required List<List<dynamic>> deviceIcon,
    required bool isInput,
    required Future<void> Function(String? id) onSelected,
  }) {
    return _AudioQuickMenu(
      devices: devices,
      selectedId: selectedId,
      unavailable: unavailable,
      loading: loading,
      title: title,
      deviceIcon: deviceIcon,
      isInput: isInput,
      onSelected: onSelected,
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
                icon: AppIcons.callEnd,
                tooltip: 'Sair do canal de voz',
                color: AppTokens.accentDanger,
                onPressed: onLeave,
                // Botão de encerrar 21% maior que o padrão (28/17): 10% + 10%
                // compostos, arredondado para inteiro (fração gerava offsets
                // fracionários e ruído de ponto flutuante no layout).
                minSize: 34,
                iconSize: 21,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _VoiceActionButton(
                  icon: state.isCameraEnabled
                      ? AppIcons.video
                      : AppIcons.videoOff,
                  label: 'Câmera',
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
                  icon: AppIcons.screenShare,
                  label: 'Tela',
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
      child: AppIcon(
        AppIcons.wifi,
        size: 18,
        color: color,
      ),
    );
  }
}

class _AudioQuickMenu extends ConsumerStatefulWidget {
  const _AudioQuickMenu({
    required this.devices,
    required this.selectedId,
    required this.unavailable,
    required this.loading,
    required this.title,
    required this.deviceIcon,
    required this.isInput,
    required this.onSelected,
  });

  final List<RtcAudioDevice> devices;
  final String? selectedId;
  final bool unavailable;
  final bool loading;
  final String title;
  final List<List<dynamic>> deviceIcon;
  final bool isInput;
  final Future<void> Function(String? id) onSelected;

  @override
  ConsumerState<_AudioQuickMenu> createState() => _AudioQuickMenuState();
}

class _AudioQuickMenuState extends ConsumerState<_AudioQuickMenu> {
  final MenuController _menuController = MenuController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'audio-quick-menu');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final volumeState = ref.watch(voiceVolumeProvider);
    final percent = widget.isInput
        ? volumeState.inputPercent
        : volumeState.outputPercent;
    return MenuAnchor(
      controller: _menuController,
      childFocusNode: _focusNode,
      useRootOverlay: true,
      consumeOutsideTap: true,
      clipBehavior: Clip.none,
      alignmentOffset: const Offset(-218, -4),
      style: _quickMenuStyle(width: 260, colors: colors),
      menuChildren: [
        _AudioQuickPanel(
          devices: widget.devices,
          selectedId: widget.selectedId,
          unavailable: widget.unavailable,
          loading: widget.loading,
          title: widget.title,
          deviceIcon: widget.deviceIcon,
          isInput: widget.isInput,
          percent: percent,
          onSelected: widget.onSelected,
          menuController: _menuController,
        ),
      ],
      builder: (context, controller, child) => Focus(
        focusNode: _focusNode,
        child: IconButton(
          tooltip: widget.title,
          padding: EdgeInsets.zero,
          icon: AppIcon(
            controller.isOpen ? AppIcons.chevronUp : AppIcons.chevronDown,
            size: 16,
            color: colors.textSecondary,
          ),
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
        ),
      ),
    );
  }
}

class _AudioQuickPanel extends ConsumerWidget {
  const _AudioQuickPanel({
    required this.devices,
    required this.selectedId,
    required this.unavailable,
    required this.loading,
    required this.title,
    required this.deviceIcon,
    required this.isInput,
    required this.percent,
    required this.onSelected,
    required this.menuController,
  });

  final List<RtcAudioDevice> devices;
  final String? selectedId;
  final bool unavailable;
  final bool loading;
  final String title;
  final List<List<dynamic>> deviceIcon;
  final bool isInput;
  final int percent;
  final Future<void> Function(String? id) onSelected;
  final MenuController menuController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final volumeController = ref.read(voiceVolumeProvider.notifier);
    final subtitle = _selectedDeviceLabel(
      devices: devices,
      selectedId: selectedId,
      title: title,
      unavailable: unavailable,
    );
    return SizedBox(
      width: 260,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SubmenuButton(
              menuStyle: _quickMenuStyle(width: 260, colors: colors),
              menuChildren: [
                _DeviceMenuItem(
                  checked: selectedId == null,
                  enabled: !loading,
                  icon: deviceIcon,
                  label: 'Padrão do sistema',
                  onPressed: () => _selectDevice(null),
                ),
                if (unavailable)
                  const SizedBox(
                    width: 236,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        'Preferido indisponível; usando o padrão.',
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 12,
                          color: AppTokens.accentAmber,
                        ),
                      ),
                    ),
                  ),
                for (var index = 0; index < devices.length; index++)
                  _DeviceMenuItem(
                    checked: devices[index].id == selectedId,
                    enabled: !loading,
                    icon: deviceIcon,
                    label: _audioDeviceLabel(devices[index], title, index),
                    onPressed: () => _selectDevice(devices[index].id),
                  ),
              ],
              style: _submenuButtonStyle(colors),
              child: _MenuSummaryRow(
                title: title,
                subtitle: subtitle,
                icon: deviceIcon,
              ),
            ),
            const SizedBox(height: 8),
            Divider(height: 1, color: colors.borderHairline),
            const SizedBox(height: 10),
            _QuickVolumeSlider(
              label: isInput ? 'Volume de entrada' : 'Volume de saída',
              percent: percent,
              max: isInput ? 100 : 200,
              onChanged: (value) {
                if (isInput) {
                  volumeController.setInputPercent(value);
                } else {
                  volumeController.setOutputPercent(value);
                }
              },
              onReset: percent == 100
                  ? null
                  : () {
                      if (isInput) {
                        volumeController.resetInput();
                      } else {
                        volumeController.resetOutput();
                      }
                    },
            ),
            const SizedBox(height: 8),
            const Divider(height: 1, color: AppTokens.borderHairline),
            const SizedBox(height: 6),
            _QuickCommandRow(
              icon: AppIcons.settings,
              label: 'Configurações de voz',
              onTap: () {
                menuController.close();
                showSettingsModal(
                  context,
                  initialSection: SettingsSection.voiceVideo,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _selectDevice(String? id) {
    menuController.close();
    unawaited(onSelected(id));
  }
}

class _MenuSummaryRow extends StatelessWidget {
  const _MenuSummaryRow({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final List<List<dynamic>> icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          AppIcon(icon, size: 17, color: colors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 12.5,
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 11,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceMenuItem extends StatelessWidget {
  const _DeviceMenuItem({
    required this.checked,
    required this.enabled,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final bool checked;
  final bool enabled;
  final List<List<dynamic>> icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return MenuItemButton(
      onPressed: enabled ? onPressed : null,
      style: _menuItemStyle(colors),
      leadingIcon: AppIcon(
        checked ? AppIcons.check : icon,
        size: 16,
        color: checked ? colors.accent : colors.textSecondary,
      ),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'Geist',
          fontSize: 12.5,
          color: colors.textPrimary,
        ),
      ),
    );
  }
}

class _QuickVolumeSlider extends StatelessWidget {
  const _QuickVolumeSlider({
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

class _QuickCommandRow extends StatelessWidget {
  const _QuickCommandRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final List<List<dynamic>> icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: onTap,
      child: SizedBox(
        height: 34,
        child: Row(
          children: [
            AppIcon(icon, size: 17, color: AppTokens.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 12.5,
                  color: AppTokens.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

MenuStyle _quickMenuStyle({
  required double width,
  required AppThemePalette colors,
}) {
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

ButtonStyle _submenuButtonStyle(AppThemePalette colors) {
  return ButtonStyle(
    alignment: Alignment.centerLeft,
    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
    minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
    foregroundColor: WidgetStatePropertyAll(colors.textPrimary),
    overlayColor: WidgetStatePropertyAll(colors.hoverOverlay),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
    ),
  );
}

ButtonStyle _menuItemStyle(AppThemePalette colors) {
  return ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(236, 32)),
    maximumSize: const WidgetStatePropertyAll(Size(236, 32)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
    foregroundColor: WidgetStatePropertyAll(colors.textPrimary),
    overlayColor: WidgetStatePropertyAll(colors.hoverOverlay),
  );
}

String _selectedDeviceLabel({
  required List<RtcAudioDevice> devices,
  required String? selectedId,
  required String title,
  required bool unavailable,
}) {
  if (selectedId == null) return 'Padrão do sistema';
  if (unavailable) return 'Preferido indisponível';
  for (var index = 0; index < devices.length; index++) {
    if (devices[index].id == selectedId) {
      return _audioDeviceLabel(devices[index], title, index);
    }
  }
  return 'Padrão do sistema';
}

String _audioDeviceLabel(RtcAudioDevice device, String category, int index) =>
    device.label.isEmpty ? '$category ${index + 1}' : device.label;

class _SplitMediaControl extends StatelessWidget {
  const _SplitMediaControl({
    required this.icon,
    required this.tooltip,
    required this.onMainPressed,
    required this.menu,
    this.isActive = false,
    this.activeColor,
  });

  final List<List<dynamic>> icon;
  final String tooltip;
  final VoidCallback? onMainPressed;
  final Widget menu;
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
        SizedBox(width: 24, height: 28, child: menu),
      ],
    );
  }
}

class _VoiceActionButton extends StatefulWidget {
  const _VoiceActionButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.isActive,
    required this.onPressed,
  });

  final List<List<dynamic>> icon;
  final String label;
  final String tooltip;
  final bool isActive;
  final VoidCallback? onPressed;

  @override
  State<_VoiceActionButton> createState() => _VoiceActionButtonState();
}

class _VoiceActionButtonState extends State<_VoiceActionButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final foreground = _foregroundColor(enabled);
    final background = _backgroundColor(enabled);
    final border = _borderColor(enabled);
    final shadow = _shadow(enabled);

    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        selected: widget.isActive,
        label: widget.tooltip,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() {
            _hovered = false;
            _pressed = false;
          }),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
            onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
            onTapCancel: enabled
                ? () => setState(() => _pressed = false)
                : null,
            child: AnimatedScale(
              scale: _pressed ? 0.985 : 1,
              duration: const Duration(milliseconds: 90),
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                key: ValueKey('voice-action-button-${widget.label}'),
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: border, width: 1),
                  boxShadow: shadow,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(widget.icon, size: 16, color: foreground),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 12,
                          height: 1,
                          fontWeight: widget.isActive
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: foreground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _foregroundColor(bool enabled) {
    final colors = context.appColors;
    if (!enabled) return colors.textMuted.withValues(alpha: 0.48);
    if (widget.isActive) return Colors.white;
    return colors.onAccent;
  }

  Color _backgroundColor(bool enabled) {
    final colors = context.appColors;
    if (!enabled) {
      return Color.alphaBlend(
        Colors.white.withValues(alpha: 0.018),
        colors.surfaceBase,
      );
    }
    if (widget.isActive) {
      if (_pressed) {
        return Color.alphaBlend(
          Colors.black.withValues(alpha: 0.14),
          AppTokens.accentDanger,
        );
      }
      if (_hovered) {
        return Color.alphaBlend(
          Colors.white.withValues(alpha: 0.08),
          AppTokens.accentDanger,
        );
      }
      return AppTokens.accentDanger;
    }
    if (_pressed) {
      return Color.alphaBlend(
        Colors.black.withValues(alpha: 0.14),
        colors.accent,
      );
    }
    if (_hovered) {
      return Color.alphaBlend(
        Colors.white.withValues(alpha: 0.10),
        colors.accent,
      );
    }
    return colors.accent;
  }

  Color _borderColor(bool enabled) {
    if (!enabled) return Colors.white.withValues(alpha: 0.035);
    if (widget.isActive) return Colors.transparent;
    return Colors.transparent;
  }

  List<BoxShadow> _shadow(bool enabled) {
    final colors = context.appColors;
    if (!enabled) return const [];
    if (widget.isActive) {
      return [
        BoxShadow(
          color: AppTokens.accentDanger.withValues(alpha: 0.28),
          blurRadius: 16,
          spreadRadius: -7,
          offset: const Offset(0, 6),
        ),
      ];
    }
    return [
      BoxShadow(
        color: colors.accent.withValues(alpha: 0.28),
        blurRadius: 16,
        spreadRadius: -7,
        offset: const Offset(0, 6),
      ),
    ];
  }
}
