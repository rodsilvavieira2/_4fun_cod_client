import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/ui.dart';
import '../../shared/models/message.dart';
import '../../shared/models/user.dart';
import 'chat_grouping.dart';
import 'chat_providers.dart';

/// Chat de um canal de texto estilo macOS / Vercel:
/// Lista reversa com paginação no topo, timestamps em Geist Mono e composer flutuante elegante.
class ChatScreen extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(
      chatControllerProvider((serverId: serverId, channelId: channelId)),
    );
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
                  serverId: serverId,
                  channelId: channelId,
                )),
              ),
            ),
            data: (state) => _MessageList(
              state: state,
              channelName: channelName,
              onLoadMore: () => ref
                  .read(
                    chatControllerProvider((
                      serverId: serverId,
                      channelId: channelId,
                    )).notifier,
                  )
                  .loadMore(),
            ),
          ),
        ),
        _ChatComposer(serverId: serverId, channelId: channelId),
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
  });

  final ChatState state;
  final String channelName;
  final VoidCallback onLoadMore;

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
          constraints: const BoxConstraints(maxWidth: 420),
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
                    letterSpacing: -0.4,
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

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
        // A lista interna é oldest-first e a UI usa reverse:true, então o
        // índice visual é invertido. O agrupamento compara cada mensagem com
        // a anterior CRONOLÓGICA (mais antiga), não com a mais nova seguinte.
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
      padding: const EdgeInsets.symmetric(vertical: 12),
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
  const _MessageTile({required this.message, required this.showHeader});

  final ChatMessage message;
  final bool showHeader;

  @override
  State<_MessageTile> createState() => _MessageTileState();
}

class _MessageTileState extends State<_MessageTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final author = widget.message.author;
    final authorColorIndex = author.id.codeUnits.fold(0, (a, b) => a + b) % 4;
    final edited =
        widget.message.updatedAt != null &&
        widget.message.updatedAt!.isAfter(widget.message.createdAt);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        // Hover sutil na linha inteira, sem raio de "cartão": o fluxo
        // contínuo estilo Discord não quebra o grupo visualmente.
        decoration: BoxDecoration(
          color: _hovered ? AppTokens.chatRowHover : Colors.transparent,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Semantics(
          label:
              '${author.name}, ${_formatTime(widget.message.createdAt)}: ${widget.message.content}${edited ? ' (editada)' : ''}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.showHeader) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTokens.surface2,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(
                          color: AppTokens.borderHairline,
                          width: 1,
                        ),
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
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        author.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
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
              // Linha de conteúdo: avatar ocupa 36 + gap 12 = 48 de recuo.
              // Mensagens compactas mostram o horário curto no hover.
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
                    child: Text(
                      widget.message.content,
                      style: const TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 14,
                        height: 1.45,
                        color: AppTokens.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatarInitial(User author) {
    return Text(
      author.name.isEmpty ? '?' : author.name[0].toUpperCase(),
      style: const TextStyle(
        fontFamily: 'Geist',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppTokens.textPrimary,
      ),
    );
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

class _ChatComposer extends ConsumerStatefulWidget {
  const _ChatComposer({required this.serverId, required this.channelId});

  final String serverId;
  final String channelId;

  @override
  ConsumerState<_ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends ConsumerState<_ChatComposer> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSend(String content) async {
    if (content.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(
            chatControllerProvider((
              serverId: widget.serverId,
              channelId: widget.channelId,
            )).notifier,
          )
          .send(content);
      if (!mounted) return;
      _controller.clear();
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
      hintText: 'Digite sua mensagem… (Enter para enviar)',
      onSend: _handleSend,
    );
  }
}
