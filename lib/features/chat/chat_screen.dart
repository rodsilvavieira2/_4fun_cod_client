import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_state.dart';
import '../../core/storage/image_selection.dart';
import '../../core/ui/ui.dart';
import '../../shared/models/message.dart';
import '../../shared/models/servers.dart';
import '../../shared/models/user.dart';
import '../servers/servers_providers.dart';
import 'chat_grouping.dart';
import 'chat_providers.dart';
import 'emoji_catalog.dart';
import 'gif_repository.dart';
import 'mention_utils.dart';

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

  Future<void> _editMessage(ChatMessage message, String content) async {
    try {
      await ref
          .read(
            chatControllerProvider((
              serverId: widget.serverId,
              channelId: widget.channelId,
            )).notifier,
          )
          .editMessage(message.id, content);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível editar a mensagem.')),
      );
    }
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    try {
      await ref
          .read(
            chatControllerProvider((
              serverId: widget.serverId,
              channelId: widget.channelId,
            )).notifier,
          )
          .deleteMessage(message.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível excluir a mensagem.')),
      );
    }
  }

  /// Retry de anexo FAILED já vinculado: `POST /uploads/:id/retry`; a imagem
  /// chega via `message.updated` (sem estado local — o grid já mostra spinner
  /// enquanto o upload não está READY).
  Future<void> _retryAttachment(String uploadId) async {
    try {
      await ref
          .read(
            chatControllerProvider((
              serverId: widget.serverId,
              channelId: widget.channelId,
            )).notifier,
          )
          .retryAttachmentUpload(uploadId);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível tentar de novo.')),
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
    final serverDetail = ref.watch(serverDetailProvider(widget.serverId));
    final members = serverDetail.valueOrNull?.members ?? const <ServerMember>[];
    final onlineUserIds = ref.watch(presenceProvider(widget.serverId));

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
              members: members,
              onReply: _startReply,
              onReact: _toggleReaction,
              onEdit: _editMessage,
              onDelete: _deleteMessage,
              onRetryAttachment: _retryAttachment,
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
          members: members,
          onlineUserIds: onlineUserIds,
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
    required this.onEdit,
    required this.onDelete,
    required this.onRetryAttachment,
    this.members = const [],
    this.myUserId,
  });

  final ChatState state;
  final String channelName;
  final String? myUserId;
  final List<ServerMember> members;
  final VoidCallback onLoadMore;
  final ValueChanged<ChatMessage> onReply;
  final Future<void> Function(ChatMessage message, String emoji) onReact;
  final Future<void> Function(ChatMessage message, String content) onEdit;
  final Future<void> Function(ChatMessage message) onDelete;
  final ValueChanged<String> onRetryAttachment;

  @override
  State<_MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<_MessageList> {
  static const _loadMoreThreshold = 300.0;

  /// Distância do presente (offset 0, lista `reverse: true`) a partir da
  /// qual o pill "voltar ao presente" aparece.
  static const _awayFromPresentThreshold = 400.0;

  final ScrollController _scrollController = ScrollController();
  bool _awayFromPresent = false;

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
    final away = position.pixels > _awayFromPresentThreshold;
    if (away != _awayFromPresent) {
      setState(() => _awayFromPresent = away);
    }
  }

  void _jumpToPresent() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
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
    final mentionTargets = _mentionTargetsFor(widget.members);

    return Stack(
      children: [
        ListView.builder(
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
                  mentionTargets: mentionTargets,
                  quickReactionEmojis: quickReactionEmojis,
                  onReply: widget.onReply,
                  onReact: widget.onReact,
                  onEdit: widget.onEdit,
                  onDelete: widget.onDelete,
                  onRetryAttachment: widget.onRetryAttachment,
                ),
              ],
            );
          },
        ),
        Positioned(
          bottom: 12,
          left: 0,
          right: 0,
          child: Center(
            child: AnimatedOpacity(
              opacity: _awayFromPresent ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_awayFromPresent,
                child: JumpToPresentPill(onPressed: _jumpToPresent),
              ),
            ),
          ),
        ),
      ],
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
    required this.mentionTargets,
    required this.quickReactionEmojis,
    required this.onReply,
    required this.onReact,
    required this.onEdit,
    required this.onDelete,
    required this.onRetryAttachment,
    this.myUserId,
  });

  final ChatMessage message;
  final bool showHeader;
  final String? myUserId;
  final List<MentionTarget> mentionTargets;
  final List<String> quickReactionEmojis;
  final ValueChanged<ChatMessage> onReply;
  final Future<void> Function(ChatMessage message, String emoji) onReact;
  final Future<void> Function(ChatMessage message, String content) onEdit;
  final Future<void> Function(ChatMessage message) onDelete;
  final ValueChanged<String> onRetryAttachment;

  @override
  State<_MessageTile> createState() => _MessageTileState();
}

class _MessageTileState extends State<_MessageTile> {
  bool _hovered = false;
  bool _editing = false;

  bool get _isOwner {
    final myUserId = widget.myUserId;
    if (myUserId == null) return false;
    // Bolha otimista local ainda sem id real: sem ações de dono.
    if (widget.message.id.startsWith('local-')) return false;
    return widget.message.author.id == myUserId;
  }

  Future<void> _pickReaction(BuildContext anchorContext) async {
    final emoji = await _showEmojiPopup(anchorContext, title: 'Reagir');
    if (emoji == null) return;
    if (!mounted) return;
    await widget.onReact(widget.message, emoji);
  }

  @override
  void didUpdateWidget(covariant _MessageTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Tiles sem key podem ser reaproveitados para outra mensagem (ex. após
    // excluir): nunca vazar o modo de edição para a mensagem errada.
    if (oldWidget.message.id != widget.message.id && _editing) {
      setState(() => _editing = false);
    }
  }

  Future<void> _showMoreMenu(BuildContext anchorContext) async {
    final canEdit = widget.message.kind != ChatMessageKind.gif;
    final action = await _showAnchoredPopup<String>(
      anchorContext: anchorContext,
      preferredSize: Size(AppMenu.minWidth, canEdit ? 80 : 40),
      builder: (onSelected, onClose) => _MessageMoreMenu(
        canEdit: canEdit,
        onSelected: onSelected,
        onClose: onClose,
      ),
    );
    if (!mounted) return;
    if (action == 'edit') {
      _startEdit();
    } else if (action == 'delete') {
      await _confirmDelete();
    }
  }

  /// Entra em edição inline (estilo Discord): o texto vira campo no lugar,
  /// sem modal.
  void _startEdit() {
    if (_editing) return;
    setState(() => _editing = true);
  }

  void _cancelEdit() {
    if (!_editing) return;
    setState(() => _editing = false);
  }

  Future<void> _saveEdit(String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty || trimmed == widget.message.content) {
      _cancelEdit();
      return;
    }
    setState(() => _editing = false);
    await widget.onEdit(widget.message, trimmed);
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTokens.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppTokens.borderSubtle),
        ),
        title: const Text(
          'Excluir mensagem',
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTokens.textPrimary,
          ),
        ),
        content: const Text(
          'Tem certeza que deseja excluir esta mensagem? Essa ação não pode ser desfeita.',
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: 13.5,
            height: 1.45,
            color: AppTokens.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: AppTokens.accentDanger,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) return;
    await widget.onDelete(widget.message);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final author = widget.message.author;
    final mentionTargets = _mergeMentionTargets(
      widget.mentionTargets,
      widget.message.mentions,
    );
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
          color: _hovered ? colors.chatRowHover : Colors.transparent,
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
                              color: colors.authorColors[authorColorIndex],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatTime(widget.message.createdAt),
                          style: TextStyle(
                            fontFamily: 'Geist Mono',
                            fontSize: 11,
                            color: colors.textMuted,
                          ),
                        ),
                        if (edited) ...[
                          const SizedBox(width: 6),
                          Text(
                            '(editada)',
                            style: TextStyle(
                              fontFamily: 'Geist',
                              fontSize: 11,
                              color: colors.textMuted,
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
                                style: TextStyle(
                                  fontFamily: 'Geist Mono',
                                  fontSize: 10.5,
                                  color: colors.textMuted,
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
                            if (_editing)
                              _InlineMessageEditor(
                                initialText: widget.message.content,
                                onSave: _saveEdit,
                                onCancel: _cancelEdit,
                              )
                            else if (widget.message.content.isNotEmpty)
                              Padding(
                                padding: EdgeInsets.only(
                                  bottom:
                                      widget.message.kind == ChatMessageKind.gif
                                      ? 8
                                      : 0,
                                ),
                                child: _MentionMessageText(
                                  text: widget.message.content,
                                  targets: mentionTargets,
                                ),
                              ),
                            if (widget.message.kind == ChatMessageKind.gif &&
                                widget.message.gifUrl != null)
                              _GifEmbed(url: widget.message.gifUrl!),
                            if (widget.message.attachments.isNotEmpty)
                              Padding(
                                padding: EdgeInsets.only(
                                  top:
                                      widget.message.content.isNotEmpty ||
                                          (widget.message.kind ==
                                                  ChatMessageKind.gif &&
                                              widget.message.gifUrl != null)
                                      ? 6
                                      : 0,
                                ),
                                child: MessageImageGrid(
                                  attachments: widget.message.attachments,
                                  onRetry: widget.onRetryAttachment,
                                  onOpen: (url) =>
                                      showImageLightbox(context, url),
                                ),
                              ),
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
            if (!_editing)
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
                      isOwner: _isOwner,
                      onReact: widget.onReact,
                      onPickReaction: _pickReaction,
                      onShowMoreMenu: _showMoreMenu,
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
    if (message.kind == ChatMessageKind.image ||
        message.attachments.isNotEmpty) {
      final count = message.attachments.length;
      final images = count == 1 ? '1 imagem' : '$count imagens';
      return message.content.isEmpty ? images : '${message.content} ($images)';
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
    final colors = context.appColors;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: colors.surface2,
        shape: BoxShape.circle,
        border: Border.all(color: colors.borderHairline, width: 1),
      ),
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      child: author.avatarUrl != null
          ? AppFileImage(
              path: author.avatarUrl,
              width: 36,
              height: 36,
              fallback: _avatarInitial(author, colors),
            )
          : _avatarInitial(author, colors),
    );
  }

  Widget _avatarInitial(User author, AppThemePalette colors) {
    return Text(
      author.name.isEmpty ? '?' : author.name[0].toUpperCase(),
      style: TextStyle(
        fontFamily: 'Geist',
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: colors.textPrimary,
      ),
    );
  }
}

class _MentionMessageText extends StatelessWidget {
  const _MentionMessageText({required this.text, required this.targets});

  final String text;
  final List<MentionTarget> targets;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final baseStyle = TextStyle(
      fontFamily: 'Geist',
      fontSize: 14.5,
      height: 1.42,
      color: colors.textPrimary,
    );
    final parts = buildMentionTextParts(text, targets);
    if (parts.length == 1 && !parts.first.isMention) {
      return SelectableText(text, style: baseStyle);
    }

    return SelectableText.rich(
      TextSpan(
        style: baseStyle,
        children: [
          for (final part in parts)
            TextSpan(
              text: part.text,
              style: part.isMention
                  ? TextStyle(
                      color: colors.accent,
                      fontWeight: FontWeight.w700,
                      backgroundColor: colors.accent.withValues(alpha: 0.20),
                    )
                  : null,
            ),
        ],
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

/// Editor inline estilo Discord: substitui o texto no lugar da mensagem.
/// `Enter` salva, `Shift+Enter` quebra linha e `Esc` cancela.
class _InlineMessageEditor extends StatefulWidget {
  const _InlineMessageEditor({
    required this.initialText,
    required this.onSave,
    required this.onCancel,
  });

  final String initialText;
  final ValueChanged<String> onSave;
  final VoidCallback onCancel;

  @override
  State<_InlineMessageEditor> createState() => _InlineMessageEditorState();
}

class _InlineMessageEditorState extends State<_InlineMessageEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText)
      ..selection = TextSelection.collapsed(offset: widget.initialText.length);
    _focusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onCancel();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter &&
            !HardwareKeyboard.instance.isShiftPressed) {
          widget.onSave(_controller.text);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    )..requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: true,
          minLines: 1,
          maxLines: 8,
          maxLength: 4000,
          buildCounter:
              (
                context, {
                required int currentLength,
                required bool isFocused,
                int? maxLength,
              }) => const SizedBox.shrink(),
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          style: const TextStyle(
            fontFamily: 'Geist',
            fontSize: 14.5,
            height: 1.42,
            color: AppTokens.textPrimary,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppTokens.surface1,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: const BorderSide(color: AppTokens.borderSubtle),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: const BorderSide(color: AppTokens.borderSubtle),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: const BorderSide(color: AppTokens.accentVercel),
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'esc para cancelar • enter para salvar',
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: 11,
            color: AppTokens.textMuted,
          ),
        ),
      ],
    );
  }
}

class _MessageActionBar extends StatelessWidget {
  const _MessageActionBar({
    required this.message,
    required this.quickReactionEmojis,
    required this.isOwner,
    required this.onReact,
    required this.onPickReaction,
    required this.onShowMoreMenu,
    required this.onReply,
  });

  final ChatMessage message;
  final List<String> quickReactionEmojis;
  final bool isOwner;
  final Future<void> Function(ChatMessage message, String emoji) onReact;
  final Future<void> Function(BuildContext anchorContext) onPickReaction;
  final Future<void> Function(BuildContext anchorContext) onShowMoreMenu;
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
            if (isOwner)
              Builder(
                builder: (anchorContext) => AppIconButton(
                  icon: Icons.more_horiz,
                  tooltip: 'Mais ações',
                  minSize: 28,
                  iconSize: 16,
                  onPressed: () => onShowMoreMenu(anchorContext),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Menu âncora do ⋯ (só dono) no padrão compacto [AppMenu] dos demais
/// menus do app (`channel_list`, `user_panel`, `voice_screen`): itens de
/// 32px, ícone 16 [AppTokens.textSecondary] e divisor de 8px antes da ação
/// destrutiva (— que mantém o vermelho [AppTokens.accentDanger], como no
/// Discord).
class _MessageMoreMenu extends StatelessWidget {
  const _MessageMoreMenu({
    required this.canEdit,
    required this.onSelected,
    required this.onClose,
  });

  final bool canEdit;
  final ValueChanged<String> onSelected;
  final VoidCallback onClose;

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
        padding: AppMenu.menuPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canEdit)
              _CompactMenuEntry(
                icon: Icons.edit_outlined,
                label: 'Editar mensagem',
                onTap: () => onSelected('edit'),
              ),
            if (canEdit)
              const Divider(
                height: AppMenu.dividerHeight,
                color: AppTokens.borderHairline,
              ),
            _CompactMenuEntry(
              icon: Icons.delete_outline,
              label: 'Excluir mensagem',
              destructive: true,
              onTap: () => onSelected('delete'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactMenuEntry extends StatelessWidget {
  const _CompactMenuEntry({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? AppTokens.accentDanger
        : AppTokens.textSecondary;
    return SizedBox(
      height: AppMenu.itemHeight,
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: AppTokens.hoverOverlay,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Padding(
            padding: AppMenu.itemPadding,
            child: Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: destructive
                        ? AppMenu.itemTextStyle.copyWith(color: color)
                        : AppMenu.itemTextStyle,
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

/// Slot de imagem do composer (uploads-primeiro, spec-chat-imagens).
///
/// Os bytes vivem só aqui: o `POST /uploads` roda no pick e o slot guarda o
/// `uploadId` (PENDING no servidor). Campos mutáveis para atualizar cada slot
/// sem reindexar a lista durante os `POST`s em paralelo.
class _ChatComposer extends ConsumerStatefulWidget {
  const _ChatComposer({
    required this.serverId,
    required this.channelId,
    required this.channelName,
    required this.members,
    required this.onlineUserIds,
    required this.onCancelReply,
    this.replyTo,
  });

  final String serverId;
  final String channelId;
  final String channelName;
  final List<ServerMember> members;
  final Set<String> onlineUserIds;
  final ChatMessage? replyTo;
  final VoidCallback onCancelReply;

  @override
  ConsumerState<_ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends ConsumerState<_ChatComposer> {
  static const _mentionLimit = 8;

  final TextEditingController _controller = TextEditingController();
  bool _sending = false;
  String? _gifUrl;
  ActiveMention? _activeMention;
  int _selectedMentionIndex = 0;

  /// Slots de imagem (upload-no-enviar): só bytes locais; o `POST /uploads`
  /// roda em [ChatController.sendImageMessage] ao apertar enviar.
  List<ChatImageSlot> _attachments = [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncMentionState);
  }

  @override
  void dispose() {
    _controller.removeListener(_syncMentionState);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.members != widget.members ||
        oldWidget.onlineUserIds != widget.onlineUserIds) {
      _clampSelectedMention();
    }
  }

  void _syncMentionState() {
    final next = findActiveMention(_controller.value);
    if (next == _activeMention) {
      _clampSelectedMention();
      return;
    }
    setState(() {
      _activeMention = next;
      _selectedMentionIndex = 0;
    });
  }

  List<_MentionOption> _currentMentionOptions() {
    final active = _activeMention;
    if (active == null) return const [];
    final membersByUserId = {
      for (final member in widget.members) member.userId: member,
    };
    return [
      for (final target in rankMentionTargets(
        _mentionTargetsFor(widget.members, onlineUserIds: widget.onlineUserIds),
        active.query,
        limit: _mentionLimit,
      ))
        if (membersByUserId[target.userId] != null)
          _MentionOption(
            target: target,
            member: membersByUserId[target.userId]!,
            online: widget.onlineUserIds.contains(target.userId),
          ),
    ];
  }

  void _clampSelectedMention() {
    final options = _currentMentionOptions();
    final maxIndex = options.isEmpty ? 0 : options.length - 1;
    if (_selectedMentionIndex <= maxIndex) return;
    setState(() => _selectedMentionIndex = maxIndex);
  }

  KeyEventResult _handleComposerKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _activeMention == null) {
      return KeyEventResult.ignored;
    }
    final options = _currentMentionOptions();
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      setState(() {
        _activeMention = null;
        _selectedMentionIndex = 0;
      });
      return KeyEventResult.handled;
    }
    if (options.isEmpty) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedMentionIndex = (_selectedMentionIndex + 1) % options.length;
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedMentionIndex =
            (_selectedMentionIndex - 1 + options.length) % options.length;
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.tab) {
      _insertMention(options[_selectedMentionIndex].target);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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

  void _insertMention(MentionTarget target) {
    final active = _activeMention;
    if (active == null) return;
    final current = _controller.value;
    if (active.start < 0 ||
        active.end > current.text.length ||
        active.start > active.end) {
      return;
    }
    final replacement = '${target.mentionText} ';
    _controller.value = current.copyWith(
      text: current.text.replaceRange(active.start, active.end, replacement),
      selection: TextSelection.collapsed(
        offset: active.start + replacement.length,
      ),
      composing: TextRange.empty,
    );
    setState(() {
      _activeMention = null;
      _selectedMentionIndex = 0;
    });
  }

  Future<void> _pickEmoji(BuildContext anchorContext) async {
    final emoji = await _showEmojiPopup(anchorContext, title: 'Emoji');
    if (emoji == null) return;
    if (!mounted) return;
    _insertText(emoji);
  }

  Future<void> _pickGif(BuildContext anchorContext) async {
    final gif = await _showGifPopup(
      anchorContext,
      repository: ref.read(gifRepositoryProvider),
    );
    if (gif == null) return;
    if (!mounted) return;
    setState(() => _gifUrl = gif.imageUrl);
  }

  void _clearGif() {
    if (_gifUrl == null) return;
    setState(() => _gifUrl = null);
  }

  Future<void> _handleSend(String content) async {
    final hasGif = _gifUrl != null;
    final slots = _attachments;
    if ((content.isEmpty && !hasGif && slots.isEmpty) || _sending) return;
    final controller = ref.read(
      chatControllerProvider((
        serverId: widget.serverId,
        channelId: widget.channelId,
      )).notifier,
    );
    setState(() => _sending = true);
    try {
      if (slots.isNotEmpty) {
        // Upload-no-enviar: bolha otimista "enviando" + uploads + mensagem.
        // Limpa o composer já (os slots vivem na cópia local para restore).
        final auth = ref.read(authControllerProvider).valueOrNull;
        final user = auth is Authenticated ? auth.user : null;
        if (user == null) throw StateError('no-auth');
        setState(() {
          _attachments = [];
          _controller.clear();
        });
        widget.onCancelReply();
        try {
          await controller.sendImageMessage(
            content: content,
            slots: slots,
            author: user,
            replyToId: widget.replyTo?.id,
          );
        } catch (_) {
          // Tudo-ou-nada: bolha removida, draft restaurado para reenvio.
          if (!mounted) return;
          setState(() => _attachments = slots);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Falha ao enviar as imagens. Tente de novo.'),
            ),
          );
        }
        return;
      }
      await controller.send(
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

  /// Pick multiplo (file_selector, linux/windows): só bytes locais + preview.
  /// Nenhum `POST /uploads` aqui — o upload roda ao apertar enviar.
  Future<void> _pickImages() async {
    if (_sending || _gifUrl != null) return;
    final files = await openFiles(acceptedTypeGroups: const [imageTypeGroup]);
    if (files.isEmpty || !mounted) return;
    final slots = [..._attachments];
    for (final file in files) {
      if (slots.length >= kMaxChatAttachments) break;
      final contentType = contentTypeForFileName(file.name);
      if (contentType == null) {
        _showPickError('Formato não suportado: ${file.name}');
        continue;
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.length > maxImageBytes) {
        _showPickError('${file.name}: máximo de 5 MB.');
        continue;
      }
      slots.add(
        ChatImageSlot(
          bytes: bytes,
          fileName: file.name,
          contentType: contentType,
        ),
      );
    }
    setState(() => _attachments = slots);
  }

  void _showPickError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AppChatInput(
      controller: _controller,
      enabled: !_sending,
      hintText: 'Mensagem em #${widget.channelName}',
      canSendEmpty: _gifUrl != null || _attachments.isNotEmpty,
      trailingActions: [
        AppIconButton(
          icon: Icons.image_outlined,
          tooltip: 'Anexar imagens',
          minSize: 30,
          iconSize: 18,
          onPressed: _sending || _gifUrl != null ? null : _pickImages,
        ),
        const SizedBox(width: 2),
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
        Builder(
          builder: (anchorContext) => AppIconButton(
            icon: Icons.gif_box_outlined,
            tooltip: 'Inserir GIF',
            minSize: 30,
            iconSize: 18,
            onPressed: _sending || _attachments.isNotEmpty
                ? null
                : () => _pickGif(anchorContext),
          ),
        ),
      ],
      topPanel: _composerPanel(),
      onKeyEvent: _handleComposerKey,
      onSend: _handleSend,
    );
  }

  Widget? _composerPanel() {
    final replyTo = widget.replyTo;
    final gifUrl = _gifUrl;
    final mentionOptions = _currentMentionOptions();
    final showMentions = _activeMention != null;
    final hasAttachments = _attachments.isNotEmpty;
    if (!showMentions && replyTo == null && gifUrl == null && !hasAttachments) {
      return null;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showMentions) ...[
          _MentionSuggestionsPanel(
            options: mentionOptions,
            selectedIndex: _selectedMentionIndex,
            onSelected: _insertMention,
          ),
          if (replyTo != null || gifUrl != null || hasAttachments)
            const SizedBox(height: 8),
        ],
        if (replyTo != null || gifUrl != null || hasAttachments)
          DecoratedBox(
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
                if (replyTo != null && (gifUrl != null || hasAttachments))
                  const Divider(height: 1, color: AppTokens.borderHairline),
                if (gifUrl != null)
                  _ComposerGifPanel(url: gifUrl, onCancel: _clearGif),
                if (gifUrl == null && hasAttachments) ...[
                  if (replyTo != null)
                    const Divider(height: 1, color: AppTokens.borderHairline),
                  _ComposerAttachmentsPanel(
                    attachments: _attachments,
                    onRemove: (slot) => setState(
                      () => _attachments = [..._attachments]..remove(slot),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
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

/// Preview dos slots de imagem do composer (upload-no-enviar): só miniatura
/// local + remover. Nenhum upload acontece antes de apertar enviar.
class _ComposerAttachmentsPanel extends StatelessWidget {
  const _ComposerAttachmentsPanel({
    required this.attachments,
    required this.onRemove,
  });

  final List<ChatImageSlot> attachments;
  final ValueChanged<ChatImageSlot> onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final slot in attachments)
            SizedBox(
              width: 86,
              height: 86,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppTokens.surface2,
                        border: Border.all(
                          color: AppTokens.borderSubtle,
                          width: 1,
                        ),
                      ),
                      child: Image.memory(slot.bytes, fit: BoxFit.cover),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: () => onRemove(slot),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0xAA000000),
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MentionOption {
  const _MentionOption({
    required this.target,
    required this.member,
    required this.online,
  });

  final MentionTarget target;
  final ServerMember member;
  final bool online;
}

class _MentionSuggestionsPanel extends StatelessWidget {
  const _MentionSuggestionsPanel({
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_MentionOption> options;
  final int selectedIndex;
  final ValueChanged<MentionTarget> onSelected;

  @override
  Widget build(BuildContext context) {
    final visibleRows = options.isEmpty ? 1 : options.length;
    final maxHeight = 38.0 + visibleRows.clamp(1, 8).toDouble() * 42.0 + 8.0;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTokens.surface2,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppTokens.borderSubtle, width: 1),
          boxShadow: AppShadows.popover,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 10, 12, 7),
              child: Row(
                children: [
                  Icon(
                    Icons.alternate_email,
                    size: 14,
                    color: AppTokens.textMuted,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'MEMBROS',
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppTokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppTokens.borderHairline),
            if (options.isEmpty)
              const SizedBox(
                height: 42,
                child: Center(
                  child: Text(
                    'Nenhum membro encontrado',
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 12.5,
                      color: AppTokens.textMuted,
                    ),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                  shrinkWrap: true,
                  itemExtent: 40,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final option = options[index];
                    return _MentionSuggestionRow(
                      option: option,
                      selected: index == selectedIndex,
                      onSelected: () => onSelected(option.target),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MentionSuggestionRow extends StatefulWidget {
  const _MentionSuggestionRow({
    required this.option,
    required this.selected,
    required this.onSelected,
  });

  final _MentionOption option;
  final bool selected;
  final VoidCallback onSelected;

  @override
  State<_MentionSuggestionRow> createState() => _MentionSuggestionRowState();
}

class _MentionSuggestionRowState extends State<_MentionSuggestionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final target = widget.option.target;
    final active = widget.selected || _hovered;
    return Tooltip(
      message: target.mentionText,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onSelected,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: active ? AppTokens.surface3 : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              children: [
                _MentionAvatar(option: widget.option),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    target.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 13.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                      color: active
                          ? AppTokens.textPrimary
                          : AppTokens.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  target.mentionText,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Geist Mono',
                    fontSize: 11,
                    color: AppTokens.textMuted,
                  ),
                ),
                const SizedBox(width: 8),
                ServerRoleBadge(
                  role: widget.option.member.role,
                  showLabel: false,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MentionAvatar extends StatelessWidget {
  const _MentionAvatar({required this.option});

  final _MentionOption option;

  @override
  Widget build(BuildContext context) {
    final target = option.target;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppTokens.surface1,
            shape: BoxShape.circle,
            border: Border.all(color: AppTokens.borderHairline, width: 1),
          ),
          alignment: Alignment.center,
          clipBehavior: Clip.antiAlias,
          child: target.avatarUrl != null
              ? Image.network(
                  target.avatarUrl!,
                  width: 28,
                  height: 28,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _MentionInitial(target: target),
                )
              : _MentionInitial(target: target),
        ),
        Positioned(
          right: -2,
          bottom: -2,
          child: PresenceDot(
            status: option.online
                ? PresenceStatus.online
                : PresenceStatus.offline,
            size: 8,
          ),
        ),
      ],
    );
  }
}

class _MentionInitial extends StatelessWidget {
  const _MentionInitial({required this.target});

  final MentionTarget target;

  @override
  Widget build(BuildContext context) {
    return Text(
      target.label.isEmpty ? '?' : target.label[0].toUpperCase(),
      style: const TextStyle(
        fontFamily: 'Geist',
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: AppTokens.textPrimary,
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
    preferredSize: const Size(340, 300),
    builder: (onSelected, onClose) => _EmojiPickerPopup(
      title: title,
      onSelected: onSelected,
      onClose: onClose,
    ),
  );
}

Future<GifResult?> _showGifPopup(
  BuildContext anchorContext, {
  required GifRepository repository,
}) {
  return _showAnchoredPopup<GifResult>(
    anchorContext: anchorContext,
    preferredSize: const Size(520, 480),
    builder: (onSelected, onClose) => _GifPickerPopup(
      repository: repository,
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
    final options = emojiCatalogEntries
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
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppTokens.textPrimary,
                  ),
                ),
                const Spacer(),
                AppIconButton(
                  icon: Icons.close,
                  tooltip: 'Fechar',
                  minSize: 26,
                  iconSize: 14,
                  onPressed: widget.onClose,
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 34,
              child: TextField(
                controller: _searchController,
                autofocus: true,
                cursorColor: AppTokens.borderFocus,
                textAlignVertical: TextAlignVertical.center,
                style: const TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 13,
                  color: AppTokens.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Buscar emoji',
                  prefixIcon: const Icon(Icons.search, size: 15),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  isDense: true,
                  filled: true,
                  fillColor: AppTokens.surface1,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: const BorderSide(
                      color: AppTokens.borderHairline,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: const BorderSide(color: AppTokens.borderFocus),
                  ),
                ),
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
              ),
            ),
            const SizedBox(height: 10),
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
                  : GridView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: options.length,
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 34,
                            mainAxisSpacing: 4,
                            crossAxisSpacing: 4,
                            childAspectRatio: 1,
                          ),
                      itemBuilder: (context, index) {
                        return _PickerEmojiButton(
                          option: options[index],
                          onSelected: widget.onSelected,
                        );
                      },
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

  final EmojiCatalogEntry option;
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
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hovered ? AppTokens.hoverOverlay : AppTokens.surface1,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppTokens.borderHairline, width: 1),
            ),
            child: Text(
              widget.option.value,
              style: const TextStyle(fontSize: 19, height: 1),
            ),
          ),
        ),
      ),
    );
  }
}

class _GifPickerPopup extends StatefulWidget {
  const _GifPickerPopup({
    required this.repository,
    required this.onSelected,
    required this.onClose,
  });

  final GifRepository repository;
  final ValueChanged<GifResult> onSelected;
  final VoidCallback onClose;

  @override
  State<_GifPickerPopup> createState() => _GifPickerPopupState();
}

class _GifPickerPopupState extends State<_GifPickerPopup> {
  static const _perPage = 18;
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<GifResult> _items = const [];
  bool _loading = true;
  String? _error;
  int _requestVersion = 0;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _load(value));
  }

  Future<void> _load(String query) async {
    final version = ++_requestVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = query.trim().isEmpty
          ? await widget.repository.trending(perPage: _perPage)
          : await widget.repository.search(query: query, perPage: _perPage);
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on GifRepositoryException catch (error) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _items = const [];
        _error = error.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _items = const [];
        _error = 'Não foi possível carregar GIFs.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTokens.surface2,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppTokens.borderSubtle, width: 1),
        boxShadow: AppShadows.popover,
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                const Text(
                  'GIFs',
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppTokens.textPrimary,
                  ),
                ),
                const Spacer(),
                AppIconButton(
                  icon: Icons.close,
                  tooltip: 'Fechar',
                  minSize: 26,
                  iconSize: 14,
                  onPressed: widget.onClose,
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 34,
              child: TextField(
                controller: _searchController,
                autofocus: true,
                cursorColor: AppTokens.borderFocus,
                textAlignVertical: TextAlignVertical.center,
                style: const TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 13,
                  color: AppTokens.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: widget.repository.searchHint,
                  prefixIcon: const Icon(Icons.search, size: 15),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  isDense: true,
                  filled: true,
                  fillColor: AppTokens.surface1,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: const BorderSide(
                      color: AppTokens.borderHairline,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: const BorderSide(color: AppTokens.borderFocus),
                  ),
                ),
                onChanged: _onSearchChanged,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            error,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Geist',
              fontSize: 12.5,
              height: 1.35,
              color: AppTokens.textMuted,
            ),
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text(
          'Nenhum GIF encontrado',
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: 13,
            color: AppTokens.textMuted,
          ),
        ),
      );
    }
    return GridView.builder(
      padding: EdgeInsets.zero,
      itemCount: _items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.5,
      ),
      itemBuilder: (context, index) {
        return _GifTile(gif: _items[index], onSelected: widget.onSelected);
      },
    );
  }
}

class _GifTile extends StatefulWidget {
  const _GifTile({required this.gif, required this.onSelected});

  final GifResult gif;
  final ValueChanged<GifResult> onSelected;

  @override
  State<_GifTile> createState() => _GifTileState();
}

class _GifTileState extends State<_GifTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.gif.title,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: () => widget.onSelected(widget.gif),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              color: AppTokens.surface1,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color: _hovered
                    ? AppTokens.borderFocus
                    : AppTokens.borderHairline,
                width: _hovered ? 1.2 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  widget.gif.previewUrl,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      size: 18,
                      color: AppTokens.textMuted,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(color: Color(0xB0000000)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      child: Text(
                        widget.gif.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 11,
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

List<MentionTarget> _mentionTargetsFor(
  List<ServerMember> members, {
  Set<String> onlineUserIds = const <String>{},
}) {
  final ordered = [...members]
    ..sort((left, right) {
      final leftOnline = onlineUserIds.contains(left.userId);
      final rightOnline = onlineUserIds.contains(right.userId);
      if (leftOnline != rightOnline) return leftOnline ? -1 : 1;
      final byRole = left.role.index.compareTo(right.role.index);
      if (byRole != 0) return byRole;
      return left.user.username.compareTo(right.user.username);
    });
  return [
    for (final member in ordered)
      MentionTarget(
        userId: member.userId,
        name: member.user.name,
        username: member.user.username,
        avatarUrl: member.user.avatarUrl,
      ),
  ];
}

List<MentionTarget> _mergeMentionTargets(
  List<MentionTarget> baseTargets,
  List<MessageMention> mentions,
) {
  if (mentions.isEmpty) return baseTargets;
  final byUsername = {
    for (final target in baseTargets) target.username.toLowerCase(): target,
  };
  for (final mention in mentions) {
    final user = mention.user;
    byUsername.putIfAbsent(
      user.username.toLowerCase(),
      () => MentionTarget(
        userId: user.id,
        name: user.name,
        username: user.username,
        avatarUrl: user.avatarUrl,
      ),
    );
  }
  return byUsername.values.toList(growable: false);
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
