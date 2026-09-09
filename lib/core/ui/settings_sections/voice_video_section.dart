import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../rtc/media_devices_provider.dart';
import '../../rtc/rtc_service.dart';
import '../section_header.dart';
import '../../../features/voice/voice_controls_provider.dart';
import '../../../features/voice/voice_volume_controller.dart';

/// Configuração de dispositivos de voz e vídeo. As trocas são aplicadas na
/// hora e ficam salvas no dispositivo; não existe botão "Salvar".
class VoiceVideoSection extends ConsumerWidget {
  const VoiceVideoSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(audioDevicesProvider);
    final controller = ref.read(audioDevicesProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: SectionHeader('VOZ E VÍDEO')),
            IconButton(
              tooltip: 'Atualizar dispositivos',
              onPressed: state.isLoading
                  ? null
                  : () => unawaited(controller.refresh()),
              icon: const Icon(Icons.refresh, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _AudioDeviceField(
          label: 'Dispositivo de entrada',
          devices: state.inputs,
          selectedId: state.preferredInputId,
          unavailable: state.preferredInputUnavailable,
          loading: state.isLoading,
          onChanged: (id) => unawaited(controller.selectInput(id)),
        ),
        const SizedBox(height: 16),
        _AudioDeviceField(
          label: 'Dispositivo de saída',
          devices: state.outputs,
          selectedId: state.preferredOutputId,
          unavailable: state.preferredOutputUnavailable,
          loading: state.isLoading,
          onChanged: (id) => unawaited(controller.selectOutput(id)),
        ),
        const SizedBox(height: 16),
        _CameraField(
          devices: state.cameras,
          selectedId: state.preferredCameraId,
          unavailable: state.preferredCameraUnavailable,
          loading: state.isLoading,
          onChanged: (id) => unawaited(controller.selectCamera(id)),
        ),
        const SizedBox(height: 24),
        const _InputVolumeField(),
        const SizedBox(height: 16),
        const _OutputVolumeField(),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 16),
        const _PushToTalkSettings(),
        if (state.errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            state.errorMessage!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}

class _AudioDeviceField extends StatelessWidget {
  const _AudioDeviceField({
    required this.label,
    required this.devices,
    required this.selectedId,
    required this.unavailable,
    required this.loading,
    required this.onChanged,
  });

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
      label: label,
      unavailable: unavailable,
      child: DropdownButtonFormField<String>(
        key: ValueKey(value),
        initialValue: value,
        isExpanded: true,
        decoration: const InputDecoration(isDense: true),
        onChanged: loading
            ? null
            : (value) => onChanged(value == _systemDefault ? null : value),
        items: [
          const DropdownMenuItem(
            value: _systemDefault,
            child: Text('Padrão do sistema'),
          ),
          for (var index = 0; index < devices.length; index++)
            DropdownMenuItem(
              value: devices[index].id,
              child: Text(_deviceLabel(devices[index], label, index)),
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
      label: 'Câmera',
      unavailable: unavailable,
      child: DropdownButtonFormField<String>(
        key: ValueKey(value),
        initialValue: value,
        isExpanded: true,
        decoration: const InputDecoration(isDense: true),
        hint: const Text('Padrão do sistema'),
        onChanged: loading || devices.isEmpty
            ? null
            : (id) {
                if (id != null) onChanged(id);
              },
        items: [
          for (var index = 0; index < devices.length; index++)
            DropdownMenuItem(
              value: devices[index].id,
              child: Text(_deviceLabel(devices[index], 'Câmera', index)),
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
      label: 'Volume de entrada',
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
      label: 'Volume de saída',
      percent: percent,
      max: 200,
      onChanged: controller.setOutputPercent,
      onReset: percent == 100 ? null : controller.resetOutput,
    );
  }
}

class _VolumeField extends StatelessWidget {
  const _VolumeField({
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ),
            Text('$percent%'),
            TextButton(onPressed: onReset, child: const Text('100%')),
          ],
        ),
        Slider(
          value: percent.toDouble(),
          min: 0,
          max: max.toDouble(),
          divisions: max ~/ 5,
          label: '$percent%',
          onChanged: (value) => onChanged((value / 5).round() * 5),
        ),
      ],
    );
  }
}

class _DeviceFieldShell extends StatelessWidget {
  const _DeviceFieldShell({
    required this.label,
    required this.unavailable,
    required this.child,
  });

  final String label;
  final bool unavailable;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 6),
        child,
        if (unavailable)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Dispositivo preferido indisponível; usando o padrão do sistema.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('PUSH TO TALK'),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                'Push to Talk',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            Switch(
              value: state.isPushToTalkEnabled,
              onChanged: state.isApplying
                  ? null
                  : (enabled) =>
                        unawaited(controller.setPushToTalkEnabled(enabled)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Atalho do Push to Talk',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Text(
          state.isRecordingPushToTalk
              ? 'Pressione o atalho em qualquer ordem e solte para confirmar. Ctrl, Alt ou Ctrl+Alt isolados valem. ESC cancela; Backspace limpa.'
              : 'No navegador, o Push to Talk funciona enquanto esta aba estiver focada.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (!kIsWeb &&
            defaultTargetPlatform == TargetPlatform.linux &&
            binding?.kind.name == 'mouse') ...[
          const SizedBox(height: 4),
          Text(
            'No Linux, botões globais do mouse exigem instalar a regra de acesso do aplicativo.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: Theme.of(context).inputDecorationTheme.fillColor,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  state.isRecordingPushToTalk
                      ? 'Aguardando entrada…'
                      : binding?.displayLabel ?? 'Nenhum atalho definido',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: binding == null && !state.isRecordingPushToTalk
                        ? Theme.of(context).hintColor
                        : null,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: state.isRecordingPushToTalk
                  ? controller.cancelPushToTalkRecording
                  : controller.startPushToTalkRecording,
              child: Text(state.isRecordingPushToTalk ? 'Cancelar' : 'Gravar'),
            ),
            if (binding != null) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Limpar atalho',
                onPressed: () => unawaited(controller.clearPushToTalkBinding()),
                icon: const Icon(Icons.clear, size: 18),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                'Atraso de liberação',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            Text('${state.pushToTalkReleaseDelayMs} ms'),
          ],
        ),
        Slider(
          value: state.pushToTalkReleaseDelayMs.toDouble(),
          min: 0,
          max: 2000,
          divisions: 200,
          label: '${state.pushToTalkReleaseDelayMs} ms',
          onChanged: binding == null
              ? null
              : (value) => unawaited(
                  controller.setPushToTalkReleaseDelay(value.round()),
                ),
        ),
        if (state.isPushToTalkEnabled && !state.isPushToTalkRegistered) ...[
          const SizedBox(height: 2),
          Text(
            'O atalho global não está disponível; o microfone permanece fechado.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ] else if (state.isPushToTalkEnabled && !state.isPushToTalkPressed) ...[
          const SizedBox(height: 2),
          Text(
            'Pronto: segure ${binding?.displayLabel ?? 'o atalho'} para transmitir.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (state.errorMessage case final message?) ...[
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}
