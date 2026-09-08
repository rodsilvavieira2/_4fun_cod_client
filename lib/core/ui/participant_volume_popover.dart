import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/voice/voice_volume_controller.dart';

/// Controle de volume individual de um participante remoto (0%–200%).
///
/// Widget reutilizável em `lib/core/ui` (tile da sala + lista lateral do
/// canal). Oculto para o participante local (o chamador retorna `SizedBox`
/// quando `isLocal`).
///
/// Abre um popover (dialog compacto, acessível por teclado/foco) com nome,
/// slider, valor atual e reset para 100%. O slider aplica em tempo real com
/// coalescing no serviço; a persistência tem debounce no controller.
class ParticipantVolumeButton extends ConsumerWidget {
  const ParticipantVolumeButton({
    super.key,
    required this.identity,
    required this.displayName,
  });

  /// Identity estável do LiveKit (`user_<userId>`).
  final String identity;

  final String displayName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final percent = ref.watch(
      voiceVolumeProvider.select((s) => s.percentOf(identity)),
    );
    return IconButton(
      tooltip: 'Volume de $displayName ($percent%)',
      icon: Icon(
        percent == 0
            ? Icons.volume_off
            : percent > 100
            ? Icons.volume_up
            : Icons.volume_down,
        size: 14,
      ),
      color: Colors.white,
      onPressed: () => showParticipantVolumeDialog(
        context: context,
        identity: identity,
        displayName: displayName,
      ),
    );
  }
}

/// Abre o popover de volume (usado pelo botão e pelo clique secundário).
Future<void> showParticipantVolumeDialog({
  required BuildContext context,
  required String identity,
  required String displayName,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) =>
        ParticipantVolumeDialog(identity: identity, displayName: displayName),
  );
}

/// Dialog compacto com o slider de volume do participante.
class ParticipantVolumeDialog extends ConsumerWidget {
  const ParticipantVolumeDialog({
    super.key,
    required this.identity,
    required this.displayName,
  });

  final String identity;
  final String displayName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final percent = ref.watch(
      voiceVolumeProvider.select((s) => s.percentOf(identity)),
    );
    final controller = ref.read(voiceVolumeProvider.notifier);
    return AlertDialog(
      title: Text(
        'Volume — $displayName',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: percent.toDouble(),
                    min: 0,
                    max: 200,
                    divisions: 40,
                    label: '$percent%',
                    onChanged: (value) => controller.setParticipantPercent(
                      identity,
                      value.round(),
                    ),
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    '$percent%',
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFeatures: const [],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: percent == 100
                    ? null
                    : () => controller.resetParticipant(identity),
                child: const Text('Redefinir para 100%'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}
