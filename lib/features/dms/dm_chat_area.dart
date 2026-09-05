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
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _focused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSend() {
    final content = _controller.text.trim();
    if (content.isEmpty) return;
    _controller.clear();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Mensagens diretas em breve')));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minHeight: 46),
          decoration: BoxDecoration(
            color: AppTokens.surface2,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: _focused ? AppTokens.borderFocus : AppTokens.borderStrong,
              width: _focused ? 1.2 : 1.0,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x44000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    minLines: 1,
                    maxLines: 5,
                    style: const TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 13.5,
                      color: AppTokens.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: widget.hintName != null
                          ? 'Mensagem para @${widget.hintName}…'
                          : 'Digite sua mensagem…',
                      hintStyle: const TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 13.5,
                        color: AppTokens.textMuted,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 0,
                        vertical: 10,
                      ),
                    ),
                    onSubmitted: (_) => _handleSend(),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: AppIconButton(
                    icon: Icons.arrow_upward,
                    tooltip: 'Enviar mensagem',
                    minSize: 30,
                    iconSize: 16,
                    isActive: _controller.text.trim().isNotEmpty,
                    activeColor: AppTokens.textInverse,
                    onPressed: _handleSend,
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
