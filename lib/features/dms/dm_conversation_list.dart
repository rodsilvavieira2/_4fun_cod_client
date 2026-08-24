import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/ui/presence_dot.dart';
import '../../core/ui/section_header.dart';
import 'dms_providers.dart';

/// Lista de conversas DM (wireframe v3 §4.5): busca local + conversas
/// derivadas de membros online reais. Row ativa com pill/bg do token
/// hover/selected.
class DmConversationList extends ConsumerStatefulWidget {
  const DmConversationList({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<DmConversationList> createState() =>
      _DmConversationListState();
}

class _DmConversationListState extends ConsumerState<DmConversationList> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conversations = ref.watch(dmConversationsProvider(widget.serverId));
    final selectedUserId = ref.watch(selectedDmConversationProvider);
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? conversations
        : conversations
            .where((c) => c.name.toLowerCase().contains(query))
            .toList();

    return Container(
      color: AppThemeColors.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'Buscar conversas',
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const Divider(height: 1),
          const SectionHeader('MENSAGENS'),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text(
                      'Nenhuma conversa.',
                      style: TextStyle(color: AppThemeColors.hairline),
                    ),
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final conversation = filtered[index];
                      final selected =
                          conversation.userId == selectedUserId;
                      return _ConversationRow(
                        conversation: conversation,
                        selected: selected,
                        onTap: () => ref
                            .read(selectedDmConversationProvider.notifier)
                            .state = conversation.userId,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ConversationRow extends StatefulWidget {
  const _ConversationRow({
    required this.conversation,
    required this.selected,
    required this.onTap,
  });

  final DmConversation conversation;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ConversationRow> createState() => _ConversationRowState();
}

class _ConversationRowState extends State<_ConversationRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final conversation = widget.conversation;
    final selected = widget.selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: selected
              ? AppOverlayColors.selected
              : (_hovered ? AppOverlayColors.hover : Colors.transparent),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                foregroundImage: conversation.avatarUrl != null
                    ? NetworkImage(conversation.avatarUrl!)
                    : null,
                child: conversation.avatarUrl == null
                    ? Text(
                        conversation.name.isEmpty
                            ? '?'
                            : conversation.name[0].toUpperCase(),
                        style: const TextStyle(fontSize: 11),
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  conversation.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ),
              PresenceDot(online: conversation.online, size: 8),
            ],
          ),
        ),
      ),
    );
  }
}
