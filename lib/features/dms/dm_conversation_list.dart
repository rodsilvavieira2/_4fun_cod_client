import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/ui.dart';
import 'dms_providers.dart';

/// Lista de conversas DM estilo macOS Sidebar:
/// Busca local + conversas com avatares estilizados, PresenceDot e alto contraste.
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
      color: AppTokens.surface1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                color: AppTokens.surface2,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppTokens.borderStrong, width: 1),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                style: const TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 13,
                  color: AppTokens.textPrimary,
                ),
                decoration: const InputDecoration(
                  hintText: 'Buscar conversas…',
                  hintStyle: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13,
                    color: AppTokens.textMuted,
                  ),
                  prefixIcon: Icon(Icons.search, size: 16, color: AppTokens.textSecondary),
                  prefixIconConstraints: BoxConstraints(minWidth: 32, minHeight: 32),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
              ),
            ),
          ),
          const Divider(height: 1, color: AppTokens.borderHairline),
          const SectionHeader('MENSAGENS'),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text(
                      'Nenhuma conversa.',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 13,
                        color: AppTokens.textMuted,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
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
    final fgColor = selected
        ? AppTokens.textPrimary
        : (_hovered ? AppTokens.textPrimary : AppTokens.textSecondary);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 38,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppTokens.surface3
                : (_hovered ? AppTokens.hoverOverlay : Colors.transparent),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: selected ? AppTokens.borderSubtle : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: AppTokens.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  border: Border.all(color: AppTokens.borderHairline, width: 1),
                ),
                alignment: Alignment.center,
                clipBehavior: Clip.antiAlias,
                child: conversation.avatarUrl != null
                    ? Image.network(
                        conversation.avatarUrl!,
                        width: 26,
                        height: 26,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _initial(conversation.name),
                      )
                    : _initial(conversation.name),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  conversation.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: fgColor,
                  ),
                ),
              ),
              PresenceDot(
                status: conversation.online ? PresenceStatus.online : PresenceStatus.offline,
                size: 8,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _initial(String name) {
    return Text(
      name.isEmpty ? '?' : name[0].toUpperCase(),
      style: const TextStyle(
        fontFamily: 'Geist',
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppTokens.textPrimary,
      ),
    );
  }
}
