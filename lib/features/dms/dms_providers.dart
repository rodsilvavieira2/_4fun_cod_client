import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../servers/servers_providers.dart';

/// Conversa de DM (UI shell — wireframe v3 §4.5). Mantida MÍNIMA de
/// propósito: quando o backend entregar DMs de verdade, a migração é
/// trocar o provider por uma chamada real sem remodelar a UI (risco
/// documentado na SPEC 3).
class DmConversation {
  const DmConversation({
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.online,
  });

  final String userId;
  final String name;
  final String? avatarUrl;
  final bool online;
}

/// Conversas de DM derivadas de dados REAIS (sem nada inventado solto):
/// 1 conversa por membro ONLINE do servidor, presença real via
/// `presenceProvider`. Zero dado fake de status.
///
/// O servidor "ativo" é o primeiro da lista do usuário (a rota `/dms` não
/// carrega serverId — SPEC 3 decisão "Provider sobre server ativo").
final dmConversationsProvider = Provider.family<List<DmConversation>, String>((
  ref,
  serverId,
) {
  final detail = ref.watch(serverDetailProvider(serverId)).valueOrNull;
  final online = ref.watch(presenceProvider(serverId));
  final members = detail?.members ?? const [];
  final conversations = <DmConversation>[];
  for (final member in members) {
    if (!online.contains(member.userId)) continue;
    conversations.add(
      DmConversation(
        userId: member.userId,
        name: member.user.name,
        avatarUrl: member.user.avatarUrl,
        online: true,
      ),
    );
  }
  return conversations;
});

/// Id do usuário com conversa DM selecionada (nulo = nenhuma). StateProvider
/// local da visão DM; a tela reseta ao sair (autoDispose por construção da
/// rota — ver SPEC 3 risco "conversa presa ao trocar servidor").
final selectedDmConversationProvider = StateProvider<String?>((ref) => null);
