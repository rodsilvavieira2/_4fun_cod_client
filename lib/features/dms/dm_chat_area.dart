import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/ui/app_icon_button.dart';
import 'dms_providers.dart';

/// Área de chat de uma conversa DM (wireframe v3 §4.5): header `@nome`
/// com ações (busca/chamada/vídeo — sem efeito), placeholder de mensagens
/// e composer no padrão visual do chat de canal. Enviar → SnackBar
/// "em breve" (não grava nada).
class DmChatArea extends ConsumerWidget {
  const DmChatArea({
    super.key,
    required this.serverId,
    this.userId,
    this.onBack,
  });

  final String serverId;

  /// Id do usuário da conversa ativa; nulo = nenhuma selecionada.
  final String? userId;

  /// Mobile: volta para a lista de conversas (reseta a seleção).
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(dmConversationsProvider(serverId));
    final conversation = userId == null
        ? null
        : conversations.where((c) => c.userId == userId).firstOrNull;

    return Container(
      color: AppThemeColors.canvas,
      child: Column(
        children: [
          // Header 48px com o nome da conversa (ou placeholder).
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: AppThemeColors.canvas,
              border: Border(
                bottom: BorderSide(color: AppThemeColors.hairline),
              ),
            ),
            child: Row(
              children: [
                if (userId != null && onBack != null)
                  AppIconButton(
                    icon: Icons.arrow_back,
                    tooltip: 'Voltar para conversas',
                    onPressed: onBack,
                  ),
                Text(
                  conversation != null ? '@${conversation.name}' : 'DM',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                AppIconButton(
                  icon: Icons.search,
                  tooltip: 'Buscar',
                  onPressed: () {},
                ),
                AppIconButton(
                  icon: Icons.call_outlined,
                  tooltip: 'Chamada de voz',
                  onPressed: () {},
                ),
                AppIconButton(
                  icon: Icons.videocam_outlined,
                  tooltip: 'Chamada de vídeo',
                  onPressed: () {},
                ),
              ],
            ),
          ),
          // Corpo: mensagens vazias (placeholder).
          Expanded(
            child: Center(
              child: Text(
                conversation == null
                    ? 'Selecione uma conversa'
                    : 'Nenhuma mensagem ainda',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppThemeColors.hairline,
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

  void _handleSend() {
    final content = _controller.text.trim();
    if (content.isEmpty) return;
    _controller.clear();
    // UI shell: DMs não existem no backend — feedback claro, nada persiste.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mensagens diretas em breve')),
    );
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
                  minLines: 1,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText: widget.hintName != null
                        ? 'Mensagem para @${widget.hintName}'
                        : 'Mensagem',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(right: 6, bottom: 4),
                child: IconButton.filled(
                  onPressed: _handleSend,
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
