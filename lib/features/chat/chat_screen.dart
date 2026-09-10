import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_state.dart';
import '../../core/ui/ui.dart';
import '../../shared/models/message.dart';
import '../../shared/models/user.dart';
import 'chat_grouping.dart';
import 'chat_providers.dart';

/// Chat de um canal de texto: fluxo contínuo estilo Discord, com ações no
/// hover, replies, reações, emoji no composer e GIFs.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.serverId,
    required this.channelId,
    required this.channelName,
  });

  final String serverId;
  final String channelId;
  final String channelName;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  ChatMessage? _replyTo;

  void _startReply(ChatMessage message) {
    setState(() => _replyTo = message);
  }

  void _clearReply() {
    if (_replyTo == null) return;
    setState(() => _replyTo = null);
  }

  Future<void> _toggleReaction(ChatMessage message, String emoji) async {
    try {
      await ref
          .read(
            chatControllerProvider((
              serverId: widget.serverId,
              channelId: widget.channelId,
            )).notifier,
          )
          .toggleReaction(message.id, emoji);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível reagir à mensagem.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(
      chatControllerProvider((
        serverId: widget.serverId,
        channelId: widget.channelId,
      )),
    );
    final auth = ref.watch(authControllerProvider).valueOrNull;
    final myUserId = auth is Authenticated ? auth.user.id : null;

    return Column(
      children: [
        Expanded(
          child: chat.when(
            loading: () => const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (_, _) => _ChatError(
              onRetry: () => ref.invalidate(
                chatControllerProvider((
                  serverId: widget.serverId,
                  channelId: widget.channelId,
                )),
              ),
            ),
            data: (state) => _MessageList(
              state: state,
              channelName: widget.channelName,
              myUserId: myUserId,
              onReply: _startReply,
              onReact: _toggleReaction,
              onLoadMore: () => ref
                  .read(
                    chatControllerProvider((
                      serverId: widget.serverId,
                      channelId: widget.channelId,
                    )).notifier,
                  )
                  .loadMore(),
            ),
          ),
        ),
        _ChatComposer(
          serverId: widget.serverId,
          channelId: widget.channelId,
          channelName: widget.channelName,
          replyTo: _replyTo,
          onCancelReply: _clearReply,
        ),
      ],
    );
  }
}

class _ChatError extends StatelessWidget {
  const _ChatError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Não foi possível carregar as mensagens.',
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 13.5,
              color: AppTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          AppButton(
            label: 'Tentar novamente',
            variant: AppButtonVariant.secondary,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

class _MessageList extends StatefulWidget {
  const _MessageList({
    required this.state,
    required this.channelName,
    required this.onLoadMore,
    required this.onReply,
    required this.onReact,
    this.myUserId,
  });

  final ChatState state;
  final String channelName;
  final String? myUserId;
  final VoidCallback onLoadMore;
  final ValueChanged<ChatMessage> onReply;
  final Future<void> Function(ChatMessage message, String emoji) onReact;

  @override
  State<_MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<_MessageList> {
  static const _loadMoreThreshold = 300.0;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final state = widget.state;
    if (position.maxScrollExtent - position.pixels <= _loadMoreThreshold &&
        state.hasMore &&
        !state.loadingMore) {
      widget.onLoadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final messages = state.messages;
    if (messages.isEmpty && !state.loadingMore) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppTokens.surface2,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Icon(
                      Icons.tag,
                      size: 30,
                      color: AppTokens.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Boas-vindas a #${widget.channelName}!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 7),
                const Text(
                  'Este é o começo da conversa. Envie a primeira mensagem para o canal.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13.5,
                    height: 1.45,
                    color: AppTokens.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final quickReactionEmojis = _quickReactionEmojisFor(
      messages,
      widget.myUserId,
    );

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
      itemCount: messages.length + (state.loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == messages.length && state.loadingMore) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final message = messages[messages.length - 1 - index];
        final chronologicalIndex = messages.length - 1 - index;
        final previous = chronologicalIndex > 0
            ? messages[chronologicalIndex - 1]
            : null;
        final showDayDivider = ChatGrouping.shouldShowDayDivider(
          current: message,
          previous: previous,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showDayDivider) _DayDivider(time: message.createdAt),
            _MessageTile(
              message: message,
              showHeader: ChatGrouping.shouldStartNewGroup(
                current: message,
                previous: previous,
              ),
              myUserId: widget.myUserId,
              quickReactionEmojis: quickReactionEmojis,
              onReply: widget.onReply,
              onReact: widget.onReact,
            ),
          ],
        );
      },
    );
  }
}

class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.time});

  final DateTime time;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider(color: AppTokens.borderHairline)),
          const SizedBox(width: 12),
          Text(
            _formatDay(time),
            style: const TextStyle(
              fontFamily: 'Geist',
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppTokens.textMuted,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Divider(color: AppTokens.borderHairline)),
        ],
      ),
    );
  }

  String _formatDay(DateTime time) {
    final local = time.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Hoje';
    if (diff == 1) return 'Ontem';
    final dd = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    return '$dd/$mo/${local.year}';
  }
}

class _MessageTile extends StatefulWidget {
  const _MessageTile({
    required this.message,
    required this.showHeader,
    required this.quickReactionEmojis,
    required this.onReply,
    required this.onReact,
    this.myUserId,
  });

  final ChatMessage message;
  final bool showHeader;
  final String? myUserId;
  final List<String> quickReactionEmojis;
  final ValueChanged<ChatMessage> onReply;
  final Future<void> Function(ChatMessage message, String emoji) onReact;

  @override
  State<_MessageTile> createState() => _MessageTileState();
}

class _MessageTileState extends State<_MessageTile> {
  bool _hovered = false;

  Future<void> _pickReaction(BuildContext anchorContext) async {
    final emoji = await _showEmojiPopup(anchorContext, title: 'Reagir');
    if (emoji == null) return;
    if (!mounted) return;
    await widget.onReact(widget.message, emoji);
  }

  @override
  Widget build(BuildContext context) {
    final author = widget.message.author;
    final authorColorIndex = author.id.codeUnits.fold(0, (a, b) => a + b) % 4;
    final edited =
        widget.message.updatedAt != null &&
        widget.message.updatedAt!.isAfter(widget.message.createdAt);
    final summaries = _ReactionSummary.from(
      widget.message.reactions,
      widget.myUserId,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: _hovered ? AppTokens.chatRowHover : Colors.transparent,
        ),
        padding: EdgeInsets.fromLTRB(16, widget.showHeader ? 6 : 2, 16, 2),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Semantics(
              label:
                  '${author.name}, ${_formatTime(widget.message.createdAt)}: ${_semanticContent(widget.message)}${edited ? ' (editada)' : ''}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.showHeader) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _Avatar(author: author),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            author.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Geist',
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: AppTokens.authorColors[authorColorIndex],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatTime(widget.message.createdAt),
                          style: const TextStyle(
                            fontFamily: 'Geist Mono',
                            fontSize: 11,
                            color: AppTokens.textMuted,
                          ),
                        ),
                        if (edited) ...[
                          const SizedBox(width: 6),
                          const Text(
                            '(editada)',
                            style: TextStyle(
                              fontFamily: 'Geist',
                              fontSize: 11,
                              color: AppTokens.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 48,
                        child: _hovered && !widget.showHeader
                            ? Text(
                                _formatCompactTime(widget.message.createdAt),
                                textAlign: TextAlign.left,
                                style: const TextStyle(
                                  fontFamily: 'Geist Mono',
                                  fontSize: 10.5,
                                  color: AppTokens.textMuted,
                                ),
                              )
                            : null,
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.message.replyTo != null) ...[
                              _ReplyPreview(replyTo: widget.message.replyTo!),
                              const SizedBox(height: 4),
                            ],
                            if (widget.message.content.isNotEmpty)
                              Padding(
                                padding: EdgeInsets.only(
                                  bottom:
                                      widget.message.kind == ChatMessageKind.gif
                                      ? 8
                                      : 0,
                                ),
                                child: SelectableText(
                                  widget.message.content,
                                  style: const TextStyle(
                                    fontFamily: 'Geist',
                                    fontSize: 14.5,
                                    height: 1.42,
                                    color: AppTokens.textPrimary,
                                  ),
                                ),
                              ),
                            if (widget.message.kind == ChatMessageKind.gif &&
                                widget.message.gifUrl != null)
                              _GifEmbed(url: widget.message.gifUrl!),
                            if (summaries.isNotEmpty) ...[
                              const SizedBox(height: 7),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final summary in summaries)
                                    _ReactionChip(
                                      summary: summary,
                                      onPressed: () => widget.onReact(
                                        widget.message,
                                        summary.emoji,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: !_hovered,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 100),
                  opacity: _hovered ? 1 : 0,
                  child: _MessageActionBar(
                    message: widget.message,
                    quickReactionEmojis: widget.quickReactionEmojis,
                    onReact: widget.onReact,
                    onPickReaction: _pickReaction,
                    onReply: widget.onReply,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _semanticContent(ChatMessage message) {
    if (message.kind == ChatMessageKind.gif) {
      return message.content.isEmpty ? 'GIF' : '${message.content} GIF';
    }
    return message.content;
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    final now = DateTime.now();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final isToday =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    if (isToday) return '$hh:$mm';
    final dd = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    return '$dd/$mo/${local.year} $hh:$mm';
  }

  String _formatCompactTime(DateTime time) {
    final local = time.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.author});

  final User author;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AppTokens.surface2,
        shape: BoxShape.circle,
        border: Border.all(color: AppTokens.borderHairline, width: 1),
      ),
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      child: author.avatarUrl != null
          ? Image.network(
              author.avatarUrl!,
              width: 36,
              height: 36,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _avatarInitial(author),
            )
          : _avatarInitial(author),
    );
  }

  Widget _avatarInitial(User author) {
    return Text(
      author.name.isEmpty ? '?' : author.name[0].toUpperCase(),
      style: const TextStyle(
        fontFamily: 'Geist',
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AppTokens.textPrimary,
      ),
    );
  }
}

class _ReplyPreview extends StatelessWidget {
  const _ReplyPreview({required this.replyTo});

  final MessageReplyPreview replyTo;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 16,
          margin: const EdgeInsets.only(right: 8),
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(color: AppTokens.borderStrong, width: 2),
              top: BorderSide(color: AppTokens.borderStrong, width: 2),
            ),
            borderRadius: BorderRadius.only(topLeft: AppRadius.rSm),
          ),
        ),
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTokens.surface1,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppTokens.borderHairline, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  flex: 0,
                  child: Text(
                    replyTo.author.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTokens.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _replySnippet(replyTo),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 12,
                      color: AppTokens.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _replySnippet(MessageReplyPreview reply) {
    if (reply.kind == ChatMessageKind.gif) {
      return reply.content.isEmpty ? 'GIF' : '${reply.content} - GIF';
    }
    return reply.content.replaceAll('\n', ' ');
  }
}

class _GifEmbed extends StatelessWidget {
  const _GifEmbed({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360, maxHeight: 240),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppTokens.surface2,
            border: Border.all(color: AppTokens.borderSubtle, width: 1),
          ),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const SizedBox(
                width: 280,
                height: 168,
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            },
            errorBuilder: (_, _, _) => const SizedBox(
              width: 280,
              height: 168,
              child: Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: AppTokens.textMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageActionBar extends StatelessWidget {
  const _MessageActionBar({
    required this.message,
    required this.quickReactionEmojis,
    required this.onReact,
    required this.onPickReaction,
    required this.onReply,
  });

  final ChatMessage message;
  final List<String> quickReactionEmojis;
  final Future<void> Function(ChatMessage message, String emoji) onReact;
  final Future<void> Function(BuildContext anchorContext) onPickReaction;
  final ValueChanged<ChatMessage> onReply;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTokens.surface2,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppTokens.borderSubtle, width: 1),
        boxShadow: AppShadows.popover,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final emoji in quickReactionEmojis)
              _ToolbarEmojiButton(
                emoji: emoji,
                tooltip: 'Reagir com $emoji',
                onPressed: () => onReact(message, emoji),
              ),
            Builder(
              builder: (anchorContext) => AppIconButton(
                icon: Icons.add_reaction_outlined,
                tooltip: 'Escolher reação',
                minSize: 28,
                iconSize: 15,
                onPressed: () => onPickReaction(anchorContext),
              ),
            ),
            AppIconButton(
              icon: Icons.reply,
              tooltip: 'Responder',
              minSize: 28,
              iconSize: 16,
              onPressed: () => onReply(message),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarEmojiButton extends StatefulWidget {
  const _ToolbarEmojiButton({
    required this.emoji,
    required this.tooltip,
    required this.onPressed,
  });

  final String emoji;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  State<_ToolbarEmojiButton> createState() => _ToolbarEmojiButtonState();
}

class _ToolbarEmojiButtonState extends State<_ToolbarEmojiButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hovered ? AppTokens.hoverOverlay : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              widget.emoji,
              style: const TextStyle(fontSize: 16, height: 1),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({required this.summary, required this.onPressed});

  final _ReactionSummary summary;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final active = summary.reactedByMe;
    return Tooltip(
      message: summary.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onPressed,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: active ? const Color(0x1F0070F3) : const Color(0x14111111),
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(
                color: active
                    ? const Color(0xAA0070F3)
                    : AppTokens.borderHairline,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(summary.emoji, style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 5),
                Text(
                  '${summary.count}',
                  style: TextStyle(
                    fontFamily: 'Geist Mono',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: active
                        ? const Color(0xFF7AB7FF)
                        : AppTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReactionSummary {
  const _ReactionSummary({
    required this.emoji,
    required this.count,
    required this.reactedByMe,
    required this.tooltip,
  });

  final String emoji;
  final int count;
  final bool reactedByMe;
  final String tooltip;

  static List<_ReactionSummary> from(
    List<MessageReaction> reactions,
    String? myUserId,
  ) {
    final buckets = <String, List<MessageReaction>>{};
    for (final reaction in reactions) {
      buckets.putIfAbsent(reaction.emoji, () => []).add(reaction);
    }
    return [
      for (final entry in buckets.entries)
        _ReactionSummary(
          emoji: entry.key,
          count: entry.value.length,
          reactedByMe:
              myUserId != null && entry.value.any((r) => r.userId == myUserId),
          tooltip: _reactionTooltip(entry.key, entry.value),
        ),
    ];
  }

  static String _reactionTooltip(
    String emoji,
    List<MessageReaction> reactions,
  ) {
    final names = [
      for (final reaction in reactions)
        reaction.user?.name ?? reaction.user?.username ?? reaction.userId,
    ];
    if (names.isEmpty) return emoji;
    final visible = names.take(3).join(', ');
    final extra = names.length > 3 ? ' e mais ${names.length - 3}' : '';
    return '$emoji $visible$extra';
  }
}

class _ChatComposer extends ConsumerStatefulWidget {
  const _ChatComposer({
    required this.serverId,
    required this.channelId,
    required this.channelName,
    required this.onCancelReply,
    this.replyTo,
  });

  final String serverId;
  final String channelId;
  final String channelName;
  final ChatMessage? replyTo;
  final VoidCallback onCancelReply;

  @override
  ConsumerState<_ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends ConsumerState<_ChatComposer> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;
  String? _gifUrl;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _insertText(String value) {
    final current = _controller.value;
    final start = current.selection.start >= 0
        ? current.selection.start
        : current.text.length;
    final end = current.selection.end >= 0
        ? current.selection.end
        : current.text.length;
    _controller.value = current.copyWith(
      text: current.text.replaceRange(start, end, value),
      selection: TextSelection.collapsed(offset: start + value.length),
      composing: TextRange.empty,
    );
    setState(() {});
  }

  Future<void> _pickEmoji(BuildContext anchorContext) async {
    final emoji = await _showEmojiPopup(anchorContext, title: 'Emoji');
    if (emoji == null) return;
    if (!mounted) return;
    _insertText(emoji);
  }

  Future<void> _pickGif() async {
    final gifUrl = await showDialog<String>(
      context: context,
      builder: (context) => const _GifPickerDialog(),
    );
    if (gifUrl == null) return;
    setState(() => _gifUrl = gifUrl);
  }

  void _clearGif() {
    if (_gifUrl == null) return;
    setState(() => _gifUrl = null);
  }

  Future<void> _handleSend(String content) async {
    final hasGif = _gifUrl != null;
    if ((content.isEmpty && !hasGif) || _sending) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(
            chatControllerProvider((
              serverId: widget.serverId,
              channelId: widget.channelId,
            )).notifier,
          )
          .send(
            content,
            kind: hasGif ? ChatMessageKind.gif : ChatMessageKind.text,
            gifUrl: _gifUrl,
            replyToId: widget.replyTo?.id,
          );
      if (!mounted) return;
      _controller.clear();
      _clearGif();
      widget.onCancelReply();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível enviar a mensagem.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppChatInput(
      controller: _controller,
      enabled: !_sending,
      hintText: 'Mensagem em #${widget.channelName}',
      canSendEmpty: _gifUrl != null,
      leadingActions: [
        Builder(
          builder: (anchorContext) => AppIconButton(
            icon: Icons.add_reaction_outlined,
            tooltip: 'Inserir emoji',
            minSize: 30,
            iconSize: 17,
            onPressed: _sending ? null : () => _pickEmoji(anchorContext),
          ),
        ),
        const SizedBox(width: 2),
        AppIconButton(
          icon: Icons.gif_box_outlined,
          tooltip: 'Inserir GIF',
          minSize: 30,
          iconSize: 18,
          onPressed: _sending ? null : _pickGif,
        ),
      ],
      topPanel: _composerPanel(),
      onSend: _handleSend,
    );
  }

  Widget? _composerPanel() {
    final replyTo = widget.replyTo;
    final gifUrl = _gifUrl;
    if (replyTo == null && gifUrl == null) return null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTokens.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppTokens.borderHairline, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replyTo != null)
            _ComposerReplyPanel(
              message: replyTo,
              onCancel: widget.onCancelReply,
            ),
          if (replyTo != null && gifUrl != null)
            const Divider(height: 1, color: AppTokens.borderHairline),
          if (gifUrl != null)
            _ComposerGifPanel(url: gifUrl, onCancel: _clearGif),
        ],
      ),
    );
  }
}

class _ComposerReplyPanel extends StatelessWidget {
  const _ComposerReplyPanel({required this.message, required this.onCancel});

  final ChatMessage message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          const Icon(Icons.reply, size: 16, color: AppTokens.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: const TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 12.5,
                  color: AppTokens.textMuted,
                ),
                children: [
                  const TextSpan(text: 'Respondendo a '),
                  TextSpan(
                    text: message.author.name,
                    style: const TextStyle(
                      color: AppTokens.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(text: ' - ${_messageSnippet(message)}'),
                ],
              ),
            ),
          ),
          AppIconButton(
            icon: Icons.close,
            tooltip: 'Cancelar resposta',
            minSize: 28,
            iconSize: 15,
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }

  String _messageSnippet(ChatMessage message) {
    if (message.kind == ChatMessageKind.gif) {
      return message.content.isEmpty ? 'GIF' : '${message.content} - GIF';
    }
    return message.content.replaceAll('\n', ' ');
  }
}

class _ComposerGifPanel extends StatelessWidget {
  const _ComposerGifPanel({required this.url, required this.onCancel});

  final String url;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Image.network(
              url,
              width: 86,
              height: 54,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox(
                width: 86,
                height: 54,
                child: ColoredBox(
                  color: AppTokens.surface2,
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: AppTokens.textMuted,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'GIF anexado',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppTokens.textSecondary,
              ),
            ),
          ),
          AppIconButton(
            icon: Icons.close,
            tooltip: 'Remover GIF',
            minSize: 28,
            iconSize: 15,
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

Future<String?> _showEmojiPopup(
  BuildContext anchorContext, {
  required String title,
}) {
  return _showAnchoredPopup<String>(
    anchorContext: anchorContext,
    preferredSize: const Size(380, 366),
    builder: (onSelected, onClose) => _EmojiPickerPopup(
      title: title,
      onSelected: onSelected,
      onClose: onClose,
    ),
  );
}

Future<T?> _showAnchoredPopup<T>({
  required BuildContext anchorContext,
  required Size preferredSize,
  required Widget Function(ValueChanged<T> onSelected, VoidCallback onClose)
  builder,
}) {
  final overlayState = Overlay.of(anchorContext, rootOverlay: true);
  final anchorBox = anchorContext.findRenderObject() as RenderBox?;
  final overlayBox = overlayState.context.findRenderObject() as RenderBox?;
  if (anchorBox == null ||
      overlayBox == null ||
      !anchorBox.hasSize ||
      !overlayBox.hasSize) {
    return Future.value();
  }

  const margin = 12.0;
  const gap = 8.0;
  final overlaySize = overlayBox.size;
  final maxWidth = overlaySize.width - margin * 2;
  final maxHeight = overlaySize.height - margin * 2;
  final width = maxWidth <= 0 || preferredSize.width <= maxWidth
      ? preferredSize.width
      : maxWidth;
  final height = maxHeight <= 0 || preferredSize.height <= maxHeight
      ? preferredSize.height
      : maxHeight;
  final anchorTopLeft = anchorBox.localToGlobal(
    Offset.zero,
    ancestor: overlayBox,
  );
  final anchorRect = anchorTopLeft & anchorBox.size;
  final left = _clampDouble(
    anchorRect.right - width,
    margin,
    overlaySize.width - width - margin,
  );
  final spaceAbove = anchorRect.top - margin;
  final spaceBelow = overlaySize.height - anchorRect.bottom - margin;
  final openAbove = spaceAbove >= height || spaceAbove > spaceBelow;
  final top = _clampDouble(
    openAbove ? anchorRect.top - height - gap : anchorRect.bottom + gap,
    margin,
    overlaySize.height - height - margin,
  );

  final completer = Completer<T?>();
  late final OverlayEntry entry;

  void close([T? value]) {
    if (entry.mounted) {
      entry.remove();
    }
    if (!completer.isCompleted) {
      completer.complete(value);
    }
  }

  entry = OverlayEntry(
    builder: (context) {
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => close(),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            width: width,
            height: height,
            child: Material(
              type: MaterialType.transparency,
              child: builder((value) => close(value), () => close()),
            ),
          ),
        ],
      );
    },
  );

  overlayState.insert(entry);
  return completer.future;
}

double _clampDouble(double value, double min, double max) {
  if (max < min) return min;
  return value.clamp(min, max).toDouble();
}

class _EmojiPickerPopup extends StatefulWidget {
  const _EmojiPickerPopup({
    required this.title,
    required this.onSelected,
    required this.onClose,
  });

  final String title;
  final ValueChanged<String> onSelected;
  final VoidCallback onClose;

  @override
  State<_EmojiPickerPopup> createState() => _EmojiPickerPopupState();
}

class _EmojiPickerPopupState extends State<_EmojiPickerPopup> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = _emojiOptions
        .where((option) => option.matches(_query))
        .toList();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTokens.surface2,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppTokens.borderSubtle, width: 1),
        boxShadow: AppShadows.popover,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTokens.textPrimary,
                  ),
                ),
                const Spacer(),
                AppIconButton(
                  icon: Icons.close,
                  tooltip: 'Fechar',
                  minSize: 28,
                  iconSize: 15,
                  onPressed: widget.onClose,
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _searchController,
              autofocus: true,
              cursorColor: AppTokens.borderFocus,
              style: const TextStyle(
                fontFamily: 'Geist',
                fontSize: 13.5,
                color: AppTokens.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Buscar emoji',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                filled: true,
                fillColor: AppTokens.surface1,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: const BorderSide(color: AppTokens.borderHairline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: const BorderSide(color: AppTokens.borderFocus),
                ),
              ),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: options.isEmpty
                  ? const Center(
                      child: Text(
                        'Nenhum emoji encontrado',
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 13,
                          color: AppTokens.textMuted,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final option in options)
                            _PickerEmojiButton(
                              option: option,
                              onSelected: widget.onSelected,
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerEmojiButton extends StatefulWidget {
  const _PickerEmojiButton({required this.option, required this.onSelected});

  final _EmojiOption option;
  final ValueChanged<String> onSelected;

  @override
  State<_PickerEmojiButton> createState() => _PickerEmojiButtonState();
}

class _PickerEmojiButtonState extends State<_PickerEmojiButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.option.label,
        child: GestureDetector(
          onTap: () => widget.onSelected(widget.option.value),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hovered ? AppTokens.hoverOverlay : AppTokens.surface1,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppTokens.borderHairline, width: 1),
            ),
            child: Text(
              widget.option.value,
              style: const TextStyle(fontSize: 22),
            ),
          ),
        ),
      ),
    );
  }
}

class _GifPickerDialog extends StatefulWidget {
  const _GifPickerDialog();

  @override
  State<_GifPickerDialog> createState() => _GifPickerDialogState();
}

class _GifPickerDialogState extends State<_GifPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = _gifOptions
        .where((option) => option.title.toLowerCase().contains(_query))
        .toList();
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppTokens.surface2,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppTokens.borderSubtle, width: 1),
            boxShadow: AppShadows.modalWindow,
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text(
                      'GIFs',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTokens.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    AppIconButton(
                      icon: Icons.close,
                      tooltip: 'Fechar',
                      minSize: 28,
                      iconSize: 15,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  style: const TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13.5,
                    color: AppTokens.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Buscar GIF',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    filled: true,
                    fillColor: AppTokens.surface1,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: const BorderSide(
                        color: AppTokens.borderHairline,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: const BorderSide(
                        color: AppTokens.borderFocus,
                      ),
                    ),
                  ),
                  onChanged: (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: GridView.builder(
                    itemCount: options.length,
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 180,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1.35,
                        ),
                    itemBuilder: (context, index) {
                      final option = options[index];
                      return _GifOptionTile(option: option);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GifOptionTile extends StatefulWidget {
  const _GifOptionTile({required this.option});

  final _GifOption option;

  @override
  State<_GifOptionTile> createState() => _GifOptionTileState();
}

class _GifOptionTileState extends State<_GifOptionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.option.title,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(widget.option.url),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              color: AppTokens.surface1,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: _hovered
                    ? AppTokens.borderFocus
                    : AppTokens.borderSubtle,
                width: _hovered ? 1.2 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  widget.option.url,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: AppTokens.textMuted,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(color: Color(0xCC000000)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      child: Text(
                        widget.option.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTokens.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GifOption {
  const _GifOption({required this.title, required this.url});

  final String title;
  final String url;
}

class _EmojiOption {
  const _EmojiOption({
    required this.value,
    required this.label,
    this.aliases = const [],
  });

  final String value;
  final String label;
  final List<String> aliases;

  bool matches(String query) {
    if (query.isEmpty) return true;
    final normalized = query.replaceAll(':', '');
    return value.contains(query) ||
        label.toLowerCase().contains(normalized) ||
        aliases.any((alias) => alias.contains(normalized));
  }
}

List<String> _quickReactionEmojisFor(
  List<ChatMessage> messages,
  String? myUserId,
) {
  if (myUserId == null) return _defaultQuickReactionEmojis;

  final counts = <String, int>{};
  final mostRecent = <String, DateTime>{};
  for (final message in messages) {
    for (final reaction in message.reactions) {
      if (reaction.userId != myUserId) continue;
      counts.update(reaction.emoji, (value) => value + 1, ifAbsent: () => 1);
      final recent = mostRecent[reaction.emoji];
      if (recent == null || reaction.createdAt.isAfter(recent)) {
        mostRecent[reaction.emoji] = reaction.createdAt;
      }
    }
  }

  if (counts.isEmpty) return _defaultQuickReactionEmojis;

  final ranked = counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      if (byCount != 0) return byCount;
      final recentA = mostRecent[a] ?? DateTime.fromMillisecondsSinceEpoch(0);
      final recentB = mostRecent[b] ?? DateTime.fromMillisecondsSinceEpoch(0);
      return recentB.compareTo(recentA);
    });
  final seen = <String>{};
  return [
    for (final emoji in ranked)
      if (seen.add(emoji)) emoji,
    for (final emoji in _defaultQuickReactionEmojis)
      if (seen.add(emoji)) emoji,
  ].take(3).toList(growable: false);
}

const _defaultQuickReactionEmojis = ['✅', '👍', '❤️'];

const _emojiOptions = [
  _EmojiOption(value: '😀', label: 'Sorriso', aliases: ['grinning', 'smile']),
  _EmojiOption(value: '😄', label: 'Feliz', aliases: ['happy', 'laugh']),
  _EmojiOption(value: '😂', label: 'Rindo', aliases: ['joy', 'lol']),
  _EmojiOption(value: '😊', label: 'Fofo', aliases: ['blush']),
  _EmojiOption(value: '😍', label: 'Amei', aliases: ['heart eyes', 'love']),
  _EmojiOption(value: '😮', label: 'Surpreso', aliases: ['surprised', 'wow']),
  _EmojiOption(value: '😢', label: 'Triste', aliases: ['sad', 'cry']),
  _EmojiOption(value: '😡', label: 'Bravo', aliases: ['angry']),
  _EmojiOption(value: '👍', label: 'Joinha', aliases: ['thumbsup', 'like']),
  _EmojiOption(value: '👎', label: 'Negativo', aliases: ['thumbsdown']),
  _EmojiOption(value: '👏', label: 'Palmas', aliases: ['clap']),
  _EmojiOption(value: '🙏', label: 'Obrigado', aliases: ['pray', 'thanks']),
  _EmojiOption(value: '🔥', label: 'Fogo', aliases: ['fire']),
  _EmojiOption(value: '🎉', label: 'Festa', aliases: ['party']),
  _EmojiOption(value: '✅', label: 'Confirmado', aliases: ['check', 'ok']),
  _EmojiOption(value: '❤️', label: 'Coração', aliases: ['heart', 'love']),
  _EmojiOption(value: '💯', label: 'Cem', aliases: ['100', 'perfect']),
  _EmojiOption(value: '🚀', label: 'Foguete', aliases: ['rocket', 'ship']),
  _EmojiOption(value: '👀', label: 'Olhos', aliases: ['eyes']),
  _EmojiOption(value: '✨', label: 'Brilho', aliases: ['sparkles']),
  _EmojiOption(value: '🤝', label: 'Acordo', aliases: ['handshake']),
  _EmojiOption(value: '🫡', label: 'Salute', aliases: ['sir', 'ok']),
  _EmojiOption(value: '😎', label: 'Legal', aliases: ['cool']),
  _EmojiOption(value: '🤔', label: 'Pensando', aliases: ['thinking']),
];

const _gifOptions = [
  _GifOption(
    title: 'Nice',
    url: 'https://media.giphy.com/media/111ebonMs90YLu/giphy.gif',
  ),
  _GifOption(
    title: 'Celebrando',
    url: 'https://media.giphy.com/media/3oz8xAFtqoOUUrsh7W/giphy.gif',
  ),
  _GifOption(
    title: 'Aprovado',
    url: 'https://media.giphy.com/media/l0HlBO7eyXzSZkJri/giphy.gif',
  ),
  _GifOption(
    title: 'Opa',
    url: 'https://media.giphy.com/media/xT9IgG50Fb7Mi0prBC/giphy.gif',
  ),
  _GifOption(
    title: 'Trabalho',
    url: 'https://media.giphy.com/media/13HgwGsXF0aiGY/giphy.gif',
  ),
  _GifOption(
    title: 'Foco',
    url: 'https://media.giphy.com/media/26tn33aiTi1jkl6H6/giphy.gif',
  ),
  _GifOption(
    title: 'Perfeito',
    url: 'https://media.giphy.com/media/26u4lOMA8JKSnL9Uk/giphy.gif',
  ),
  _GifOption(
    title: 'Obrigado',
    url: 'https://media.giphy.com/media/3oEdva9BUHPIs2SkGk/giphy.gif',
  ),
  _GifOption(
    title: 'Ship it',
    url: 'https://media.giphy.com/media/5GoVLqeAOo6PK/giphy.gif',
  ),
];
