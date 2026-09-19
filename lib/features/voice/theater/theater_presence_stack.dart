import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/participant_avatar.dart';
import '../../servers/servers_providers.dart';
import '../voice_providers.dart';

/// Largura visível da pilha: até 4 avatares. Acima disso, scroll lateral.
const int kTheaterPresenceMaxVisible = 4;

/// Passo da sobreposição (avatar de 22px com overlap de 4px).
const double _kPresenceStep = 18.0;

/// Largura da pilha para [count] avatares (22px do primeiro + passo).
double _presenceWidth(int count) => 24.0 + (count - 1) * _kPresenceStep;

/// Identity do LiveKit (`user_<userId>`) → userId para buscar o membro e a
/// foto de perfil. Retorna nulo quando a identity não segue o prefixo (nunca
/// deve acontecer em produção, mas o stack não pode quebrar por isso).
String? _userIdFromIdentity(String identity) {
  const prefix = 'user_';
  if (!identity.startsWith(prefix)) return null;
  final userId = identity.substring(prefix.length);
  return userId.isEmpty ? null : userId;
}

/// Pilha de presença do theater: só avatares (sem contagem — a contagem
/// `N na sala` foi removida do header em 2026-09-19).
///
/// Cada avatar mostra a foto de perfil (`User.avatarUrl` via [ParticipantAvatar]
/// autenticado) quando houver; sem foto mantém a inicial. Quem está falando
/// ganha o anel de acento ([RtcParticipant.isSpeaking]).
///
/// Até 4 participantes, todos visíveis; acima disso, scroll lateral.
///
/// A sobreposição usa [Stack]/[Positioned]: margem negativa em [Container]
/// quebra a assertion `margin.isNonNegative` do framework (regressão
/// capturada em 2026-09-19 — ver `theater_presence_stack_test.dart`).
class TheaterPresenceStack extends ConsumerWidget {
  const TheaterPresenceStack({super.key, required this.arg});

  final ({String serverId, String channelId}) arg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voice = ref.watch(voiceControllerProvider(arg));
    final total = voice.participants.length;
    if (total == 0) return const SizedBox.shrink();
    final members =
        ref.watch(serverDetailProvider(arg.serverId)).valueOrNull?.members ??
        const [];
    final membersById = {for (final member in members) member.userId: member};
    final visibleCount = math.min(total, kTheaterPresenceMaxVisible);
    return SizedBox(
      width: _presenceWidth(visibleCount),
      height: 24,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: _presenceWidth(total),
          height: 24,
          child: Stack(
            children: [
              for (var i = 0; i < voice.participants.length; i++)
                Positioned(
                  left: i * _kPresenceStep,
                  child: Builder(
                    builder: (context) {
                      final participant = voice.participants[i];
                      final userId = _userIdFromIdentity(participant.id);
                      final avatarUrl = userId == null
                          ? null
                          : membersById[userId]?.user.avatarUrl;
                      return Tooltip(
                        message: participant.name,
                        child: ParticipantAvatar(
                          displayName: participant.name,
                          avatarUrl: avatarUrl,
                          speaking: participant.isSpeaking,
                          accent: voiceAvatarAccent(
                            '${userId ?? participant.id}|${participant.name}',
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
