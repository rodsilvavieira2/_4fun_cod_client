import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/message.dart';
import '../../shared/models/user.dart';
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showHeader) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Avatar 40px quadrado com ring (wireframe: .msg .avatar
                  // 40x40 radius 10, borda hairline, fundo bg-surface).
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppThemeColors.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppThemeColors.hairline),
                    ),
                    alignment: Alignment.center,
                    clipBehavior: Clip.antiAlias,
                    child: author.avatarUrl != null
                        ? Image.network(
                            author.avatarUrl!,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _avatarInitial(author),
                          )
                        : _avatarInitial(author),
                  ),
                  const SizedBox(width: 16),
                  Flexible(
                    child: Text(
                      author.name,
                      overflow: TextOverflow.ellipsis,
                      // 4 tons por hash do id do autor (decoração, não
                      // identidade — wireframe v3).
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppThemeColors.authorColors[
                            author.id.codeUnits
                                .fold(0, (a, b) => a + b) %
                                4],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatTime(widget.message.createdAt),
                    // Wireframe: .msg .time Geist Mono 11px muted.
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: const Color(0xFF71717A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
            ],
            // Corpo a 56px (40 avatar + 16 gap) — .msg.compact .text.
            Padding(
              padding: const EdgeInsets.only(left: 56),
              child: Text(
                widget.message.content,
                style: const TextStyle(
                  fontSize: 14.5,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatarInitial(User author) {
    return Text(
      author.name.isEmpty ? '?' : author.name[0].toUpperCase(),
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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
        // Wireframe: .composer-wrap padding 0 20px 24px.
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Container(
          // Wireframe: .composer — bg-surface, border hairline, radius 8,
          // min-height 48, padding 6/8/6/16, shadow-md.
          constraints: const BoxConstraints(minHeight: 48),
          decoration: BoxDecoration(
            color: AppThemeColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppThemeColors.hairline),
            boxShadow: const [
              BoxShadow(
                color: Color(0x80000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
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
                          EdgeInsets.symmetric(horizontal: 0, vertical: 10),
                    ),
                  ),
                ),
                // Wireframe: .composer .send 32x32 radius 6, bg
                // bg-surface-hover, border subtle.
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: _sending ? null : _handleSend,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppThemeColors.hairline),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.send,
                      size: 14,
                      color: _sending
                          ? Theme.of(context).colorScheme.secondary
                          : Theme.of(context).colorScheme.onSurface,
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
