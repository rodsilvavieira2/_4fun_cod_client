import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rtc/rtc_providers.dart';
import '../../core/rtc/rtc_service.dart';
import 'voice_providers.dart';

/// Canal de voz: painel de participantes (nome, mute, active speaker) +
/// barra de controles (entrar/sair, mute/unmute).
///
/// Embarcada no [ServerShellScreen] no lugar do placeholder da Fase 4 —
/// nenhuma rota nova (a view mora no shell, como o chat).
class VoiceScreen extends ConsumerWidget {
  const VoiceScreen({
    super.key,
    required this.serverId,
    required this.channelId,
    required this.channelName,
  });

  final String serverId;
  final String channelId;
  final String channelName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arg = (serverId: serverId, channelId: channelId);
    final state = ref.watch(voiceControllerProvider(arg));
    final notifier = ref.read(voiceControllerProvider(arg).notifier);

    return Column(
      children: [
        _Header(channelName: channelName, status: state.status),
        const Divider(height: 1),
        Expanded(child: _ParticipantsPanel(state: state)),
        const Divider(height: 1),
        _Controls(
          state: state,
          onJoin: notifier.join,
          onLeave: notifier.leave,
          onToggleMicrophone: notifier.toggleMicrophone,
        ),
        // Corrige o tom da barra inferior sobre o surface do tema.
        const SizedBox(height: 4),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.channelName, required this.status});

  final String channelName;
  final VoiceSessionStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusLabel = switch (status) {
      VoiceSessionStatus.idle => 'Fora do canal de voz',
      VoiceSessionStatus.connecting => 'Conectando…',
      VoiceSessionStatus.connected => 'Em voz',
      VoiceSessionStatus.error => 'Falha na conexão',
    };
    final statusColor = switch (status) {
      VoiceSessionStatus.connected => theme.colorScheme.primary,
      VoiceSessionStatus.error => theme.colorScheme.error,
      _ => theme.colorScheme.outline,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          const Icon(Icons.headset, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '#$channelName',
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            statusLabel,
            style: theme.textTheme.bodySmall?.copyWith(color: statusColor),
          ),
        ],
      ),
    );
  }
}

class _ParticipantsPanel extends StatelessWidget {
  const _ParticipantsPanel({required this.state});

  final VoiceState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (state.status) {
      case VoiceSessionStatus.connecting:
        return const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        );
      case VoiceSessionStatus.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 40,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text(
                  state.errorMessage ?? 'Falha ao conectar.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        );
      case VoiceSessionStatus.idle:
        return Center(
          child: Text(
            'Você ainda não está neste canal de voz.\n'
            'Use o botão abaixo para entrar.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        );
      case VoiceSessionStatus.connected:
        return _ParticipantList(participants: state.participants);
    }
  }
}

class _ParticipantList extends StatelessWidget {
  const _ParticipantList({required this.participants});

  final List<RtcParticipant> participants;

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) {
      return Center(
        child: Text(
          'Ninguém mais está aqui.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: participants.length,
      itemBuilder: (context, index) =>
          _ParticipantTile(participant: participants[index]),
    );
  }
}

class _ParticipantTile extends ConsumerWidget {
  const _ParticipantTile({required this.participant});

  final RtcParticipant participant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isLocal =
        participant.id == ref.read(rtcServiceProvider).localParticipantId;
    final name = participant.name;
    return ListTile(
      dense: true,
      // Active speaker: fundo destacado (highlight de fala).
      tileColor: participant.isSpeaking
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
          : null,
      leading: CircleAvatar(
        radius: 16,
        child: Text(
          name.isEmpty ? '?' : name[0].toUpperCase(),
          style: const TextStyle(fontSize: 13),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: participant.isSpeaking
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          ),
          if (isLocal) ...[
            const SizedBox(width: 6),
            const _LocalBadge(),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (participant.isSpeaking)
            Icon(
              Icons.graphic_eq,
              size: 18,
              color: theme.colorScheme.primary,
            ),
          const SizedBox(width: 10),
          Icon(
            participant.isMicrophoneEnabled ? Icons.mic : Icons.mic_off,
            size: 18,
            color: participant.isMicrophoneEnabled
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
          ),
        ],
      ),
    );
  }
}

class _LocalBadge extends StatelessWidget {
  const _LocalBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Você',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.state,
    required this.onJoin,
    required this.onLeave,
    required this.onToggleMicrophone,
  });

  final VoiceState state;
  final VoidCallback onJoin;
  final VoidCallback onLeave;
  final VoidCallback onToggleMicrophone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = state.status == VoiceSessionStatus.connected;
    final connecting = state.status == VoiceSessionStatus.connecting;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: connected
                ? FilledButton.tonalIcon(
                    onPressed: connecting ? null : onLeave,
                    icon: const Icon(Icons.call_end),
                    label: const Text('Sair do canal de voz'),
                  )
                : FilledButton.icon(
                    onPressed: connecting ? null : onJoin,
                    icon: connecting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.headset),
                    label: Text(connecting ? 'Conectando…' : 'Entrar'),
                  ),
          ),
          if (connected) ...[
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: onToggleMicrophone,
              tooltip: state.isMicrophoneEnabled
                  ? 'Desativar microfone'
                  : 'Ativar microfone',
              icon: Icon(
                state.isMicrophoneEnabled ? Icons.mic : Icons.mic_off,
                color: state.isMicrophoneEnabled
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
