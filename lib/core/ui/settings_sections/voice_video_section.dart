import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../rtc/media_devices_provider.dart';
import '../../rtc/rtc_service.dart';
import '../section_header.dart';

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
