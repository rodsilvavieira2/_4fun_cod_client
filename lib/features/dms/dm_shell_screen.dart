import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../servers/server_rail.dart';
import '../servers/servers_providers.dart';
import 'dm_chat_area.dart';
import 'dm_conversation_list.dart';
import 'dm_profile_panel.dart';
import 'dms_providers.dart';

/// Visão de Mensagens diretas (wireframe v3 §4.5 — UI shell, SEM contrato
/// de backend): rail + lista de conversas + chat + perfil do contato.
///
/// Desktop (≥800): `Row[ServerRail(dmActive) + lista 240 + chat + perfil]`.
/// Mobile (<800): rail 56 + lista full-width alternando com o chat (back).
/// O servidor ativo é o primeiro da lista do usuário (decisão da SPEC 3).
class DmShellScreen extends ConsumerWidget {
  const DmShellScreen({super.key});

  static const double _desktopBreakpoint = 800;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider).valueOrNull ?? const [];
    final serverId = servers.isEmpty ? null : servers.first.id;
    final selectedUserId = ref.watch(selectedDmConversationProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < _desktopBreakpoint;
        // Mobile: sem conversa selecionada → lista full-width; com → chat.
        final showChat = !isNarrow || selectedUserId != null;
        final showList = !isNarrow || selectedUserId == null;
        final showProfile = !isNarrow && selectedUserId != null;

        return Scaffold(
          body: serverId == null
              ? const Center(child: Text('Nenhum servidor ainda.'))
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // DM mobile: SEM rail fixo (SPEC 3 tarefa 16) — lista
                    // e chat alternam full-width com back; rota /dms é push
                    // (gesto/back do navegador sai da visão DM).
                    if (!isNarrow) const ServerRail(dmActive: true),
                    if (showList) ...[
                      const VerticalDivider(width: 1),
                      SizedBox(
                        width: isNarrow ? null : 240,
                        child: DmConversationList(serverId: serverId),
                      ),
                    ],
                    if (showChat) ...[
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: DmChatArea(
                          serverId: serverId,
                          userId: selectedUserId,
                          onBack: isNarrow
                              ? () => ref
                                  .read(selectedDmConversationProvider.notifier)
                                  .state = null
                              : null,
                        ),
                      ),
                    ],
                    if (showProfile) ...[
                      const VerticalDivider(width: 1),
                      DmProfilePanel(
                        serverId: serverId,
                        userId: selectedUserId,
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }
}
