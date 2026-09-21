import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/message.dart';
import 'app_file_image.dart';
import 'app_icon.dart';
import 'chat_image_actions.dart';
import 'ds_tokens.dart';
import 'media_lightbox.dart';
import 'spoiler_overlay.dart';

/// Tamanho máximo de cada anexo (mesmo teto do avatar/ícone do servidor).
const kMaxChatAttachments = 10;

/// Lista vertical de imagens de uma mensagem.
///
/// - Cada imagem usa o mesmo tamanho do caso de imagem única (até 360 de
///   altura, respeita aspect ratio real com clamp 0.5–2.5).
/// - Uma embaixo da outra com espaçamento de 4px (sem grade estilo Discord).
/// - Anexo ainda PENDING/PROCESSING (url nula): spinner sobre o placeholder.
/// - FAILED: card de erro inline com botão Tentar de novo ([onRetry] recebe
///   o `uploadId` — o server re-enfileira o staging, sem bytes no client).
/// - Spoiler (`isSpoiler`): blur + badge até o 1º clique revelar (sessão
///   apenas); o 2º clique abre o lightbox ([onOpen], `url`).
/// - Toque numa imagem READY não-spoiler abre o lightbox direto.
class MessageImageGrid extends StatelessWidget {
  const MessageImageGrid({
    super.key,
    required this.attachments,
    this.onRetry,
    this.onOpen,
  });

  final List<MessageAttachment> attachments;

  /// `(uploadId)` — retry de anexo FAILED via `POST /uploads/:id/retry`.
  final ValueChanged<String>? onRetry;

  /// `(url)` — abrir lightbox.
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    final items = attachments.take(kMaxChatAttachments).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    if (items.length == 1) {
      return _SingleImage(
        attachment: items.first,
        onRetry: onRetry,
        onOpen: onOpen,
      );
    }
    // Múltiplas imagens: uma embaixo da outra, cada uma com o mesmo
    // tamanho do caso de imagem única (sem grade, sem overlay `+N`).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 4),
          _SingleImage(attachment: items[i], onRetry: onRetry, onOpen: onOpen),
        ],
      ],
    );
  }
}

/// Uma imagem no tamanho padrão do chat (até 360 de altura, aspect real).
class _SingleImage extends StatelessWidget {
  const _SingleImage({required this.attachment, this.onRetry, this.onOpen});

  final MessageAttachment attachment;
  final ValueChanged<String>? onRetry;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    // Altura SEMPRE limitada: sem isso o Stack(expand)+Center do _Cell
    // recebe h=Infinity dentro do ListView do chat e quebra o layout da
    // lista inteira (RenderPositionedBox → viewport envenenado).
    final ratio = attachment.aspectRatio.clamp(0.5, 2.5);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360),
      child: AspectRatio(
        aspectRatio: ratio,
        child: _Cell(attachment: attachment, onRetry: onRetry, onOpen: onOpen),
      ),
    );
  }
}

/// Lightbox simples: imagem em tamanho maior sobre fundo escuro.
///
/// Mantido por compatibilidade — delega para o viewer full-screen
/// ([showMediaLightbox]) com um único item.
@Deprecated('Use showMediaLightbox com MediaItem em vez disso')
Future<void> showImageLightbox(BuildContext context, String url) {
  return showMediaLightbox(
    context: context,
    items: [MediaItem(url: url)],
    authorName: '',
    sentAt: DateTime.now(),
  );
}

class _Cell extends ConsumerStatefulWidget {
  const _Cell({required this.attachment, this.onRetry, this.onOpen});

  final MessageAttachment attachment;
  final ValueChanged<String>? onRetry;
  final ValueChanged<String>? onOpen;

  @override
  ConsumerState<_Cell> createState() => _CellState();
}

class _CellState extends ConsumerState<_Cell> {
  bool _hovered = false;

  /// Reveal por sessão: volta a borrar ao trocar de mensagem/canal
  /// (novo `_Cell` / novo `attachment.id`).
  bool _revealed = false;

  @override
  void didUpdateWidget(covariant _Cell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.id != widget.attachment.id ||
        oldWidget.attachment.isSpoiler != widget.attachment.isSpoiler) {
      _revealed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final attachment = widget.attachment;
    final onRetry = widget.onRetry;
    final onOpen = widget.onOpen;
    final ref = this.ref;
    final failed = attachment.status == 'FAILED';
    final ready = attachment.url != null && !failed;
    final spoilered = attachment.isSpoiler && !_revealed;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTokens.surface2,
          border: Border.all(
            color: attachment.isSpoiler
                ? AppTokens.accentAmber.withValues(alpha: 0.45)
                : AppTokens.borderSubtle,
            width: 1,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (ready)
              MouseRegion(
                cursor: onOpen == null && !spoilered
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.click,
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() => _hovered = false),
                child: GestureDetector(
                  onTap: spoilered
                      ? () => setState(() => _revealed = true)
                      : (onOpen == null ? null : () => onOpen(attachment.url!)),
                  onSecondaryTapUp: (details) => showChatImageMenu(
                    context: context,
                    ref: ref,
                    globalPosition: details.globalPosition,
                    url: attachment.url!,
                    suggestedName: 'imagem-${attachment.id}',
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (spoilered)
                        SpoilerCover(
                          onReveal: () => setState(() => _revealed = true),
                          child: AppFileImage(
                            path: attachment.url,
                            fit: BoxFit.cover,
                            fallback: const _Spinner(),
                          ),
                        )
                      else ...[
                        AppFileImage(
                          path: attachment.url,
                          fit: BoxFit.cover,
                          fallback: const _Spinner(),
                        ),
                        // Overlay de hover estilo Discord: escurece + ícone
                        // expandir no canto para sinalizar que abre o viewer.
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 120),
                          opacity: _hovered && onOpen != null ? 1 : 0,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.28),
                              ),
                              child: const Align(
                                alignment: Alignment.bottomRight,
                                child: Padding(
                                  padding: EdgeInsets.all(8),
                                  child: _ExpandHint(),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (attachment.isSpoiler)
                          const Positioned(
                            top: 8,
                            left: 8,
                            child: SpoilerBadge(compact: true),
                          ),
                      ],
                    ],
                  ),
                ),
              )
            else if (failed)
              _FailedCell(
                onRetry: onRetry == null
                    ? null
                    : () => onRetry(attachment.uploadId),
              )
            else
              const _Spinner(),
          ],
        ),
      ),
    );
  }
}

/// Pill escura com ícone expandir (hover do thumbnail inline).
class _ExpandHint extends StatelessWidget {
  const _ExpandHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppTokens.borderSubtle, width: 1),
      ),
      child: AppIcon(
        AppIcons.expandDiagonal,
        size: 16,
        color: AppTokens.textPrimary,
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

class _FailedCell extends StatelessWidget {
  const _FailedCell({required this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(
            AppIcons.imageMissing,
            color: AppTokens.textMuted,
            size: 22,
          ),
          const SizedBox(height: 4),
          const Text(
            'Falha ao processar',
            style: TextStyle(color: AppTokens.textMuted, fontSize: 12),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 4),
            TextButton(onPressed: onRetry, child: const Text('Tentar de novo')),
          ],
        ],
      ),
    );
  }
}
