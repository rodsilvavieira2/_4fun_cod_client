import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/ui.dart';
import 'dms_providers.dart';

/// Área de chat de uma conversa DM estilo macOS / Vercel:
/// Header translúcido com ações, placeholder de mensagens de alto contraste e composer integrado.
class DmChatArea extends ConsumerWidget {
  const DmChatArea({
    super.key,
    required this.serverId,
    this.userId,
    this.onBack,
  });

  final String serverId;
  final String? userId;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(dmConversationsProvider(serverId));
    final conversation = userId == null
        ? null
        : conversations.where((c) => c.userId == userId).firstOrNull;

    return Container(
      color: AppTokens.background,
      child: Column(
        children: [
          // Header estilo macOS Toolbar
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                height: AppLayout.headerHeight,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const BoxDecoration(
                  color: Color(0xCC000000),
                  border: Border(
                    bottom: BorderSide(
                      color: AppTokens.borderHairline,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    if (userId != null && onBack != null) ...[
                      AppIconButton(
                        icon: Icons.arrow_back,
                        tooltip: 'Voltar para conversas',
                        onPressed: onBack,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      conversation != null
                          ? '@${conversation.name}'
                          : 'Mensagens Diretas',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppTokens.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const Spacer(),
                    AppIconButton(
                      icon: Icons.search,
                      tooltip: 'Buscar',
                      onPressed: () {},
                    ),
                    const SizedBox(width: 4),
                    AppIconButton(
                      icon: Icons.call_outlined,
                      tooltip: 'Chamada de voz',
                      onPressed: () {},
                    ),
                    const SizedBox(width: 4),
                    AppIconButton(
                      icon: Icons.videocam_outlined,
                      tooltip: 'Chamada de vídeo',
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Placeholder com contraste nítido
          Expanded(
            child: Center(
              child: Text(
                conversation == null
                    ? 'Selecione uma conversa para começar'
                    : 'Nenhuma mensagem ainda com @${conversation.name}',
                style: const TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 14,
                  color: AppTokens.textMuted,
                ),
              ),
            ),
          ),
          _DmComposer(hintName: conversation?.name),
        ],
      ),
    );
  }
}

class _DmComposer extends StatefulWidget {
  const _DmComposer({this.hintName});

  final String? hintName;

  @override
  State<_DmComposer> createState() => _DmComposerState();
}

class _DmComposerState extends State<_DmComposer> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSend(String content) {
    if (content.isEmpty) return;
    _controller.clear();
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Mensagens diretas em breve')));
  }

  @override
  Widget build(BuildContext context) {
    return AppChatInput(
      controller: _controller,
      hintText: widget.hintName != null
          ? 'Mensagem para @${widget.hintName}…'
          : 'Digite sua mensagem…',
      sendActiveColor: AppTokens.textInverse,
      onSend: _handleSend,
    );
  }
}
