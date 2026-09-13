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
  ConsumerState<DmConversationList> createState() => _DmConversationListState();
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
    final colors = context.appColors;
    final conversations = ref.watch(dmConversationsProvider(widget.serverId));
    final selectedUserId = ref.watch(selectedDmConversationProvider);
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? conversations
        : conversations
              .where((c) => c.name.toLowerCase().contains(query))
              .toList();

    return Container(
      color: colors.surface1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: AppLayout.headerHeight,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colors.borderHairline, width: 1),
              ),
            ),
            child: Text(
              'Mensagens diretas',
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                color: colors.surface2,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: colors.borderStrong, width: 1),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 13,
                  color: colors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Buscar conversas…',
                  hintStyle: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13,
                    color: colors.textMuted,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 16,
                    color: colors.textSecondary,
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                ),
              ),
            ),
          ),
          const SectionHeader('MENSAGENS'),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'Nenhuma conversa.',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 13,
                        color: colors.textMuted,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final conversation = filtered[index];
                      final selected = conversation.userId == selectedUserId;
                      return _ConversationRow(
                        conversation: conversation,
                        selected: selected,
                        onTap: () =>
                            ref
                                .read(selectedDmConversationProvider.notifier)
                                .state = conversation
                                .userId,
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
    final colors = context.appColors;
    final conversation = widget.conversation;
    final selected = widget.selected;
    final fgColor = selected
        ? colors.textPrimary
        : (_hovered ? colors.textPrimary : colors.textSecondary);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
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
                ? colors.surface3
                : (_hovered ? colors.hoverOverlay : Colors.transparent),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: selected ? colors.borderSubtle : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: colors.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  border: Border.all(color: colors.borderHairline, width: 1),
                ),
                alignment: Alignment.center,
                clipBehavior: Clip.antiAlias,
                child: conversation.avatarUrl != null
                    ? AppFileImage(
                        path: conversation.avatarUrl,
                        width: 26,
                        height: 26,
                        fallback: _initial(conversation.name, colors),
                      )
                    : _initial(conversation.name, colors),
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
                status: conversation.online
                    ? PresenceStatus.online
                    : PresenceStatus.offline,
                size: 8,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _initial(String name, AppThemePalette colors) {
    return Text(
      name.isEmpty ? '?' : name[0].toUpperCase(),
      style: TextStyle(
        fontFamily: 'Geist',
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
      ),
    );
  }
}
