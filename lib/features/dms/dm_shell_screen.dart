import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/settings_modal.dart';
import '../../core/ui/ui.dart';
import '../servers/server_rail.dart';
import '../servers/servers_providers.dart';
import '../servers/user_panel.dart';
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider).valueOrNull ?? const [];
    final serverId = servers.isEmpty ? null : servers.first.id;
    final selectedUserId = ref.watch(selectedDmConversationProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final activeServerId = serverId;
        if (activeServerId == null) {
          return const Scaffold(
            body: Center(child: Text('Nenhum servidor ainda.')),
          );
        }
        final isNarrow = constraints.maxWidth < AppLayout.compactBreakpoint;
        // Mobile: sem conversa selecionada → lista full-width; com → chat.
        final showChat = !isNarrow || selectedUserId != null;
        final showList = !isNarrow || selectedUserId == null;
        final showProfile =
            constraints.maxWidth >= AppLayout.auxiliaryPanelBreakpoint &&
            selectedUserId != null;
        final conversationPanel = Column(
          children: [
            Expanded(child: DmConversationList(serverId: activeServerId)),
            UserPanel(onOpenSettings: () => showSettingsModal(context)),
          ],
        );

        return Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // DM mobile: SEM rail fixo (SPEC 3 tarefa 16) — lista
              // e chat alternam full-width com back; rota /dms é push
              // (gesto/back do navegador sai da visão DM).
              if (!isNarrow) const ServerRail(dmActive: true),
              if (showList) ...[
                const VerticalDivider(width: 1),
                if (isNarrow)
                  Expanded(child: conversationPanel)
                else
                  SizedBox(
                    width: AppLayout.navigationWidth,
                    child: conversationPanel,
                  ),
              ],
              if (showChat) ...[
                const VerticalDivider(width: 1),
                Expanded(
                  child: DmChatArea(
                    serverId: activeServerId,
                    userId: selectedUserId,
                    onBack: isNarrow
                        ? () =>
                              ref
                                      .read(
                                        selectedDmConversationProvider.notifier,
                                      )
                                      .state =
                                  null
                        : null,
                  ),
                ),
              ],
              if (showProfile) ...[
                const VerticalDivider(width: 1),
                DmProfilePanel(
                  serverId: activeServerId,
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
