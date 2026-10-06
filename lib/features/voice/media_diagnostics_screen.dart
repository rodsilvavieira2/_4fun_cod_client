/// Tela de diagnóstico de mídia (§26 do plano).
///
/// Painel simples: backend efetivo, flags, snapshot do engine (input/output,
/// modo DSP efetivo, geração/epoch) e contadores. Detalhes técnicos ficam
/// aqui — fora do fluxo principal de voz. Opt-in via `nativeDiagnostics`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/native/media/media_state_mapper.dart';
import '../../core/rtc/native_rtc_service.dart';
import '../../core/rtc/rtc_providers.dart';
import '../../core/ui/section_header.dart';
import 'voice_media_providers.dart';

/// Estado de diagnóstico resolvido a partir dos providers.
class MediaDiagnostics {
  const MediaDiagnostics({
    required this.backendLabel,
    required this.flags,
    this.uiState,
  });

  final String backendLabel;
  final Map<String, bool> flags;
  final MediaUiState? uiState;
}

final mediaDiagnosticsProvider = FutureProvider<MediaDiagnostics>((ref) async {
  final config = ref.watch(mediaBackendConfigProvider);
  final service = ref.watch(effectiveRtcServiceProvider);
  MediaUiState? uiState;
  if (service is NativeRtcService) {
    try {
      final snapshot = await service.currentSnapshot();
      uiState = projectSnapshotToUi(snapshot);
    } on StateError {
      uiState = null; // engine ainda não criado: sem sessão
    }
  }
  return MediaDiagnostics(
    backendLabel: config.effectiveBackend.name,
    flags: config.toFlagMap(),
    uiState: uiState,
  );
});

class MediaDiagnosticsScreen extends ConsumerWidget {
  const MediaDiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diagnostics = ref.watch(mediaDiagnosticsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnóstico de mídia')),
      body: diagnostics.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Falha: $error')),
        data: (data) => ListView(
          children: [
            const SectionHeader('Backend'),
            ListTile(
              title: const Text('Backend efetivo'),
              trailing: Text(data.backendLabel),
            ),
            const SectionHeader('Flags'),
            for (final entry in data.flags.entries)
              ListTile(
                title: Text(entry.key),
                trailing: Text(entry.value ? 'on' : 'off'),
              ),
            const SectionHeader('Engine'),
            if (data.uiState == null)
              const ListTile(
                title: Text('Sem sessão nativa'),
                subtitle: Text('Engine ainda não criado neste backend'),
              )
            else ...[
              ListTile(
                title: const Text('DSP'),
                trailing: Text(
                  '${data.uiState!.requestedDsp} → ${data.uiState!.dspBadge}',
                ),
                subtitle: data.uiState!.dspDegraded
                    ? const Text('Degradado (modo efetivo abaixo do pedido)')
                    : null,
              ),
              ListTile(
                title: const Text('Transmissão'),
                trailing: Text(
                  data.uiState!.mayTransmit ? 'liberada' : 'bloqueada',
                ),
                subtitle: Text(
                  'mute=${data.uiState!.muted} '
                  'deafen=${data.uiState!.deafened} '
                  'ptt=${data.uiState!.pttEnabled}',
                ),
              ),
              ListTile(
                title: const Text('Sessão'),
                trailing: Text('gen ${data.uiState!.generation}'),
                subtitle: Text('epoch=${data.uiState!.deviceEpoch}'),
              ),
            ],
            const SectionHeader('Transporte (legado)'),
            _LegacyTransportTile(),
          ],
        ),
      ),
    );
  }
}

class _LegacyTransportTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final participants = ref.watch(rtcParticipantsProvider);
    return participants.when(
      loading: () => const ListTile(title: Text('Participantes: …')),
      error: (error, _) => ListTile(title: Text('Participantes: $error')),
      data: (list) => ListTile(
        title: const Text('Participantes na sala'),
        trailing: Text('${list.length}'),
      ),
    );
  }
}
