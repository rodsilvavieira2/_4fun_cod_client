import 'package:flutter/material.dart';

import '../section_header.dart';

/// Seção Voz e Vídeo do modal (UI shell): dispositivos de entrada/saída
/// como placeholder "Em breve" — sem ação real.
class VoiceVideoSection extends StatelessWidget {
  const VoiceVideoSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('VOZ E VÍDEO'),
        const _DeviceRow(label: 'Dispositivo de entrada', value: 'Em breve'),
        const SizedBox(height: 8),
        const _DeviceRow(label: 'Dispositivo de saída', value: 'Em breve'),
        const SizedBox(height: 8),
        const _DeviceRow(label: 'Câmera', value: 'Em breve'),
      ],
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Text(value, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}
