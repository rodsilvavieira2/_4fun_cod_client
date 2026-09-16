import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/voice/voice_audio_processing_provider.dart';
import '../../../features/voice/voice_controls_provider.dart';
import '../../../features/voice/voice_volume_controller.dart';
import '../../rtc/media_devices_provider.dart';
import '../../rtc/rtc_service.dart';
import '../settings_section_layout.dart';
import '../ui.dart';

/// Configuração de dispositivos de voz e vídeo. As trocas são aplicadas na
/// hora e ficam salvas no dispositivo; não existe botão "Salvar".
class VoiceVideoSection extends ConsumerWidget {
  const VoiceVideoSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(audioDevicesProvider);
    final controller = ref.read(audioDevicesProvider.notifier);
    return SettingsStack(
      children: [
        SettingsGroup(
          title: 'Dispositivos',
          trailing: AppIconButton(
            tooltip: 'Atualizar dispositivos',
            onPressed: state.isLoading
                ? null
                : () => unawaited(controller.refresh()),
            icon: Icons.refresh,
          ),
          children: [
            _AudioDeviceField(
              icon: Icons.mic_none,
              label: 'Entrada',
              devices: state.inputs,
              selectedId: state.preferredInputId,
              unavailable: state.preferredInputUnavailable,
              loading: state.isLoading,
              onChanged: (id) => unawaited(controller.selectInput(id)),
            ),
            _AudioDeviceField(
              icon: Icons.volume_up_outlined,
              label: 'Saída',
              devices: state.outputs,
              selectedId: state.preferredOutputId,
              unavailable: state.preferredOutputUnavailable,
              loading: state.isLoading,
              onChanged: (id) => unawaited(controller.selectOutput(id)),
            ),
            _CameraField(
              devices: state.cameras,
              selectedId: state.preferredCameraId,
              unavailable: state.preferredCameraUnavailable,
              loading: state.isLoading,
              onChanged: (id) => unawaited(controller.selectCamera(id)),
            ),
          ],
        ),
        if (state.errorMessage != null)
          SettingsNotice(
            message: state.errorMessage!,
            tone: SettingsNoticeTone.danger,
          ),
        const SettingsGroup(
          title: 'Áudio',
          children: [
            _InputVolumeField(),
            _NoiseSuppressionField(),
            _OutputVolumeField(),
          ],
        ),
        const _PushToTalkSettings(),
      ],
    );
  }
}

class _NoiseSuppressionField extends ConsumerWidget {
  const _NoiseSuppressionField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(voiceAudioProcessingProvider);
    final controller = ref.read(voiceAudioProcessingProvider.notifier);
    final fallbackMessage =
        state.requestedMode == RtcNoiseSuppressionMode.studio &&
            state.effectiveMode == RtcNoiseSuppressionMode.webrtc
        ? 'Studio indisponível neste dispositivo. Usando Normal.'
        : state.errorMessage;
    return SettingsRow(
      icon: Icons.graphic_eq_outlined,
      title: 'Supressão de ruído',
      subtitle: fallbackMessage,
      subtitleColor: context.appColors.accent,
      trailing: SizedBox(
        width: 456,
        child: IgnorePointer(
          ignoring: state.isApplying,
          child: Opacity(
            opacity: state.isApplying ? 0.6 : 1,
            child: AppSegmentedControl<RtcNoiseSuppressionMode>(
              height: 34,
              selectedValue: state.requestedMode,
              onChanged: (mode) =>
                  unawaited(controller.setNoiseSuppressionMode(mode)),
              items: const [
                SegmentItem(
                  value: RtcNoiseSuppressionMode.off,
                  label: 'Desativada',
                  icon: Icons.mic_none_outlined,
                ),
                SegmentItem(
                  value: RtcNoiseSuppressionMode.webrtc,
                  label: 'Normal',
                  icon: Icons.graphic_eq_outlined,
                ),
                SegmentItem(
                  value: RtcNoiseSuppressionMode.studio,
                  label: 'Studio',
                  icon: Icons.auto_awesome_outlined,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AudioDeviceField extends StatelessWidget {
  const _AudioDeviceField({
    required this.icon,
    required this.label,
    required this.devices,
    required this.selectedId,
    required this.unavailable,
    required this.loading,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final List<RtcAudioDevice> devices;
  final String? selectedId;
  final bool unavailable;
  final bool loading;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final value = devices.any((device) => device.id == selectedId)
        ? selectedId
        : _systemDefault;
    return _DeviceFieldShell(
      icon: icon,
      label: label,
      unavailable: unavailable,
      child: DropdownButtonFormField<String>(
        key: ValueKey(value),
        initialValue: value,
        isExpanded: true,
        menuMaxHeight: 280,
        style: TextStyle(
          fontFamily: 'Geist',
          fontSize: 12.5,
          color: context.appColors.textPrimary,
        ),
        decoration: _compactFieldDecoration(context),
        onChanged: loading
            ? null
            : (value) => onChanged(value == _systemDefault ? null : value),
        items: [
          const DropdownMenuItem(
            value: _systemDefault,
            child: Text('Padrão do sistema', overflow: TextOverflow.ellipsis),
          ),
          for (var index = 0; index < devices.length; index++)
            DropdownMenuItem(
              value: devices[index].id,
              child: Text(
                _deviceLabel(devices[index], label, index),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

class _CameraField extends StatelessWidget {
  const _CameraField({
    required this.devices,
    required this.selectedId,
    required this.unavailable,
    required this.loading,
    required this.onChanged,
  });

  final List<RtcVideoDevice> devices;
  final String? selectedId;
  final bool unavailable;
  final bool loading;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final value = devices.any((device) => device.id == selectedId)
        ? selectedId
        : null;
    return _DeviceFieldShell(
      icon: Icons.videocam_outlined,
      label: 'Câmera',
      unavailable: unavailable,
      child: DropdownButtonFormField<String>(
        key: ValueKey(value),
        initialValue: value,
        isExpanded: true,
        menuMaxHeight: 280,
        style: TextStyle(
          fontFamily: 'Geist',
          fontSize: 12.5,
          color: context.appColors.textPrimary,
        ),
        decoration: _compactFieldDecoration(context),
        hint: const Text('Padrão do sistema', overflow: TextOverflow.ellipsis),
        onChanged: loading || devices.isEmpty
            ? null
            : (id) {
                if (id != null) onChanged(id);
              },
        items: [
          for (var index = 0; index < devices.length; index++)
            DropdownMenuItem(
              value: devices[index].id,
              child: Text(
                _deviceLabel(devices[index], 'Câmera', index),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

/// Slider do ganho do microfone publicado (0%–100%, padrão 100%).
class _InputVolumeField extends ConsumerWidget {
  const _InputVolumeField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final percent = ref.watch(
      voiceVolumeProvider.select((s) => s.inputPercent),
    );
    final controller = ref.read(voiceVolumeProvider.notifier);
    return _VolumeField(
      icon: Icons.keyboard_voice_outlined,
      label: 'Volume de entrada',
      subtitle: 'Ganho publicado do microfone',
      percent: percent,
      max: 100,
      onChanged: controller.setInputPercent,
      onReset: percent == 100 ? null : controller.resetInput,
    );
  }
}

/// Slider mestre do volume de saída (0%–200%, padrão 100%).
///
/// Aplica em tempo real com coalescing no serviço; a persistência usa debounce
/// no controller. Ganhos acima de 100% dependem do backend RTC desktop.
class _OutputVolumeField extends ConsumerWidget {
  const _OutputVolumeField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final percent = ref.watch(
      voiceVolumeProvider.select((s) => s.outputPercent),
    );
    final controller = ref.read(voiceVolumeProvider.notifier);
    return _VolumeField(
      icon: Icons.speaker_outlined,
      label: 'Volume de saída',
      subtitle: 'Volume mestre local',
      percent: percent,
      max: 200,
      onChanged: controller.setOutputPercent,
      onReset: percent == 100 ? null : controller.resetOutput,
    );
  }
}

class _VolumeField extends StatelessWidget {
  const _VolumeField({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.percent,
    required this.max,
    required this.onChanged,
    required this.onReset,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final int percent;
  final int max;
  final ValueChanged<int> onChanged;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      icon: icon,
      title: label,
      subtitle: subtitle,
      minHeight: 58,
      trailing: SizedBox(
        width: 330,
        child: Row(
          children: [
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2.5,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                    disabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
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
            ),
            SizedBox(
              width: 52,
              child: SettingsValueText('$percent%', monospace: true),
            ),
            const SizedBox(width: 6),
            AppIconButton(
              icon: Icons.restart_alt,
              tooltip: 'Redefinir para 100%',
              onPressed: onReset,
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceFieldShell extends StatelessWidget {
  const _DeviceFieldShell({
    required this.icon,
    required this.label,
    required this.unavailable,
    required this.child,
  });

  final IconData icon;
  final String label;
  final bool unavailable;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      icon: icon,
      title: label,
      subtitle: unavailable
          ? 'Dispositivo preferido indisponível; usando o padrão do sistema.'
          : null,
      subtitleColor: unavailable ? AppTokens.accentAmber : null,
      minHeight: unavailable ? 64 : 52,
      trailing: SizedBox(width: 330, child: child),
    );
  }
}

InputDecoration _compactFieldDecoration(BuildContext context) {
  final colors = context.appColors;
  final border = OutlineInputBorder(
    borderRadius: AppRadius.brSm,
    borderSide: BorderSide(color: colors.borderStrong, width: 1),
  );
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: colors.surface2,
    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    border: border,
    enabledBorder: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: AppRadius.brSm,
      borderSide: BorderSide(color: colors.borderFocus, width: 1.2),
    ),
  );
}

const _systemDefault = '__system_default__';

String _deviceLabel(RtcMediaDevice device, String category, int index) =>
    device.label.isEmpty ? '$category ${index + 1}' : device.label;

class _PushToTalkSettings extends ConsumerWidget {
  const _PushToTalkSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(voiceControlsProvider);
    final controller = ref.read(voiceControlsProvider.notifier);
    final binding = state.pushToTalkBinding;
    final shortcutLabel = state.isRecordingPushToTalk
        ? 'Aguardando entrada…'
        : binding?.displayLabel ?? 'Nenhum atalho definido';
    final statusLabel = state.isPushToTalkEnabled
        ? (state.isPushToTalkRegistered ? 'Ativo' : 'Somente em foco')
        : 'Desativado';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          title: 'Push to Talk',
          children: [
            SettingsRow(
              icon: Icons.radio_button_checked,
              title: 'Modo',
              subtitle: statusLabel,
              trailing: SettingsSwitch(
                value: state.isPushToTalkEnabled,
                onChanged: state.isApplying
                    ? null
                    : (enabled) =>
                          unawaited(controller.setPushToTalkEnabled(enabled)),
              ),
            ),
            SettingsRow(
              icon: Icons.keyboard_alt_outlined,
              title: 'Atalho',
              subtitle: shortcutLabel,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppButton(
                    label: state.isRecordingPushToTalk ? 'Cancelar' : 'Gravar',
                    icon: state.isRecordingPushToTalk
                        ? Icons.close
                        : Icons.fiber_manual_record,
                    size: AppButtonSize.sm,
                    variant: state.isRecordingPushToTalk
                        ? AppButtonVariant.ghost
                        : AppButtonVariant.secondary,
                    onPressed: state.isRecordingPushToTalk
                        ? controller.cancelPushToTalkRecording
                        : () => controller.startPushToTalkRecording(
                            enableAfterCapture: true,
                          ),
                  ),
                  if (binding != null) ...[
                    const SizedBox(width: 4),
                    AppIconButton(
                      tooltip: 'Limpar atalho',
                      onPressed: () =>
                          unawaited(controller.clearPushToTalkBinding()),
                      icon: Icons.clear,
                    ),
                  ],
                ],
              ),
            ),
            _PushToTalkDelayField(
              delayMs: state.pushToTalkReleaseDelayMs,
              enabled: binding != null,
              onChanged: (value) => unawaited(
                controller.setPushToTalkReleaseDelay(value.round()),
              ),
            ),
          ],
        ),
        if (state.isRecordingPushToTalk) ...[
          const SizedBox(height: 8),
          const SettingsNotice(
            message:
                'Pressione o atalho em qualquer ordem e solte para confirmar. ESC cancela; Backspace limpa.',
            tone: SettingsNoticeTone.neutral,
          ),
        ],
        if (!kIsWeb &&
            defaultTargetPlatform == TargetPlatform.linux &&
            binding?.kind.name == 'mouse') ...[
          const SizedBox(height: 8),
          const SettingsNotice(
            message:
                'No Linux, botões globais do mouse exigem instalar a regra de acesso do aplicativo.',
            tone: SettingsNoticeTone.warning,
          ),
        ],
        if (state.isPushToTalkEnabled && !state.isPushToTalkRegistered) ...[
          const SizedBox(height: 8),
          const SettingsNotice(
            message:
                'O atalho global não está disponível; com o app em foco, o Push to Talk ainda funciona.',
            tone: SettingsNoticeTone.warning,
          ),
        ],
        if (state.errorMessage case final message?) ...[
          const SizedBox(height: 8),
          SettingsNotice(message: message, tone: SettingsNoticeTone.danger),
        ],
      ],
    );
  }
}

class _PushToTalkDelayField extends StatelessWidget {
  const _PushToTalkDelayField({
    required this.delayMs,
    required this.enabled,
    required this.onChanged,
  });

  final int delayMs;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      icon: Icons.timelapse_outlined,
      title: 'Atraso de liberação',
      subtitle: enabled ? null : 'Disponível após definir um atalho',
      minHeight: 58,
      trailing: SizedBox(
        width: 330,
        child: Row(
          children: [
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2.5,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                    disabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                ),
                child: Slider(
                  value: delayMs.toDouble(),
                  min: 0,
                  max: 2000,
                  divisions: 200,
                  label: '$delayMs ms',
                  onChanged: enabled ? onChanged : null,
                ),
              ),
            ),
            SizedBox(
              width: 64,
              child: SettingsValueText('$delayMs ms', monospace: true),
            ),
          ],
        ),
      ),
    );
  }
}
