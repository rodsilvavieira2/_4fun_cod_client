import 'package:flutter/material.dart';

import '../../shared/models/message.dart';
import 'app_file_image.dart';
import 'ds_tokens.dart';

/// Tamanho máximo de cada anexo (mesmo teto do avatar/ícone do servidor).
const kMaxChatAttachments = 10;

/// Grade de imagens de uma mensagem (estilo Discord, spec-chat-imagens).
///
/// - 1 imagem: cheia (até 360x360, respeita aspect ratio real).
/// - 2: lado a lado. 3+: grade 2 colunas (4ª célula vira `+N`).
/// - Anexo ainda PENDING/PROCESSING (url nula): spinner sobre o placeholder.
/// - FAILED: card de erro inline com botão Tentar de novo ([onRetry] recebe
///   o `uploadId` — o server re-enfileira o staging, sem bytes no client).
/// - Toque numa imagem READY abre o lightbox ([onOpen], `url`).
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
      // Altura SEMPRE limitada: sem isso o Stack(expand)+Center do _Cell
      // recebe h=Infinity dentro do ListView do chat e quebra o layout da
      // lista inteira (RenderPositionedBox → viewport envenenado).
      final ratio = items.first.aspectRatio.clamp(0.5, 2.5);
      return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: AspectRatio(
          aspectRatio: ratio,
          child: _Cell(
            attachment: items.first,
            onRetry: onRetry,
            onOpen: onOpen,
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth > 0 ? constraints.maxWidth : 360.0;
        final cellW = (maxW - 4) / 2;
        final shown = items.take(4).toList();
        final extra = items.length - shown.length;
        return Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (var i = 0; i < shown.length; i++)
              SizedBox(
                width: cellW,
                height: 150,
                child: _Cell(
                  attachment: shown[i],
                  overlayCount: i == 3 && extra > 0 ? extra : 0,
                  onRetry: onRetry,
                  onOpen: onOpen,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Lightbox simples: imagem em tamanho maior sobre fundo escuro.
Future<void> showImageLightbox(BuildContext context, String url) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: AppFileImage(
                  path: url,
                  fit: BoxFit.contain,
                  fallback: const SizedBox(
                    width: 320,
                    height: 240,
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
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: 'Fechar',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.attachment,
    this.overlayCount = 0,
    this.onRetry,
    this.onOpen,
  });

  final MessageAttachment attachment;
  final int overlayCount;
  final ValueChanged<String>? onRetry;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    final failed = attachment.status == 'FAILED';
    final ready = attachment.url != null && !failed;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTokens.surface2,
          border: Border.all(color: AppTokens.borderSubtle, width: 1),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (ready)
              GestureDetector(
                onTap: onOpen == null ? null : () => onOpen!(attachment.url!),
                child: AppFileImage(
                  path: attachment.url,
                  fit: BoxFit.cover,
                  fallback: const _Spinner(),
                ),
              )
            else if (failed)
              _FailedCell(
                onRetry: onRetry == null
                    ? null
                    : () => onRetry!(attachment.uploadId),
              )
            else
              const _Spinner(),
            if (overlayCount > 0)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                ),
                child: Center(
                  child: Text(
                    '+$overlayCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
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
          const Icon(
            Icons.broken_image_outlined,
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
