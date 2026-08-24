import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/message.dart';
import 'chat_providers.dart';

/// Chat de um canal de texto (wireframe v3 §4.3): lista reversa (mais
/// recente embaixo), paginação no topo, agrupamento por autor/tempo e
/// composer flutuante (#121212, radius 8, sem borda).
class ChatScreen extends ConsumerWidget {
  const ChatScreen({
    super.key,
    required this.serverId,
    required this.channelId,
  });

  final String serverId;
  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(
      chatControllerProvider((serverId: serverId, channelId: channelId)),
    );
    return Column(
      children: [
        Expanded(
          child: chat.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => _ChatError(
              onRetry: () => ref.invalidate(
                chatControllerProvider(
                  (serverId: serverId, channelId: channelId),
                ),
              ),
            ),
            data: (state) => _MessageList(
              state: state,
              onLoadMore: () => ref
                  .read(
                    chatControllerProvider(
                      (serverId: serverId, channelId: channelId),
                    ).notifier,
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
          const Text('Não foi possível carregar as mensagens.'),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: onRetry,
            child: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}

class _MessageList extends StatefulWidget {
  const _MessageList({required this.state, required this.onLoadMore});

  final ChatState state;
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
    // reverse:true → offset 0 é o fim (mensagem mais recente); o topo
    // (mensagens mais antigas) fica em maxScrollExtent.
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
        child: Text(
          'Nenhuma mensagem ainda',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      itemCount: messages.length + (state.loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        // Índice do item no topo (mais antigo) quando carregando mais.
        if (index == messages.length && state.loadingMore) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        // reverse:true → index 0 fica embaixo (mensagem mais recente).
        final message = messages[messages.length - 1 - index];
        return _MessageTile(
          message: message,
          showHeader: _shouldShowHeader(messages, index),
        );
      },
    );
  }

  /// Cabeçalho (autor + hora) quando o autor muda ou o gap com a mensagem
  /// mais nova (a de baixo na lista reversa) passa de 5 minutos.
  bool _shouldShowHeader(List<ChatMessage> messages, int index) {
    if (index == 0) return true; // mais recente: sempre mostra
    final message = messages[messages.length - 1 - index];
    final newer = messages[messages.length - index];
    if (newer.author.id != message.author.id) return true;
    return newer.createdAt.difference(message.createdAt) >
        const Duration(minutes: 5);
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
    final theme = Theme.of(context);
    final author = widget.message.author;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _hovered ? AppThemeColors.messageHover : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showHeader) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Avatar 40px (radius 20).
                  CircleAvatar(
                    radius: 20,
                    foregroundImage: author.avatarUrl != null
                        ? NetworkImage(author.avatarUrl!)
                        : null,
                    child: author.avatarUrl == null
                        ? Text(
                            author.name.isEmpty
                                ? '?'
                                : author.name[0].toUpperCase(),
                            style: const TextStyle(fontSize: 12),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      author.name,
                      overflow: TextOverflow.ellipsis,
                      // 4 tons por hash do id do autor (decoração, não
                      // identidade — wireframe v3).
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppThemeColors.authorColors[
                            author.id.codeUnits
                                .fold(0, (a, b) => a + b) %
                                4],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _formatTime(widget.message.createdAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFA1A1AA),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
            // Corpo a 56px (40 avatar + 16 gap).
            Padding(
              padding: const EdgeInsets.only(left: 56),
              child: Text(widget.message.content),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    final now = DateTime.now();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final isToday = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    if (isToday) return '$hh:$mm';
    final dd = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    return '$dd/$mo/${local.year} $hh:$mm';
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

  Future<void> _handleSend() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(
            chatControllerProvider(
              (serverId: widget.serverId, channelId: widget.channelId),
            ).notifier,
          )
          .send(content);
      // O usuário pode ter saído da tela durante o await: o controller de
      // texto já está disposed — clear() lançaria e o catch genérico
      // reportaria falha de envio mesmo com o REST tendo sucesso.
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
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(
            color: AppThemeColors.card,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  enabled: !_sending,
                  minLines: 1,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    hintText: 'Enviar mensagem',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(right: 6, bottom: 4),
                child: IconButton.filled(
                  onPressed: _sending ? null : _handleSend,
                  icon: const Icon(Icons.send, size: 18),
                  tooltip: 'Enviar',
                  style: IconButton.styleFrom(
                    minimumSize: const Size(44, 44),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
