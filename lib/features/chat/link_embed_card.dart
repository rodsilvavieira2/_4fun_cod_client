import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/links/external_link.dart';
import '../../core/ui/ui.dart';
import '../../shared/models/link_embed.dart';

/// URL do proxy de thumbnail (`GET /unfurl/image?url=`), ancorada na origem
/// da API para não duplicar prefixo (mesmo padrão de [resolveFileUrl]).
String unfurlImageProxyUrl(String restBase, String imageUrl) {
  final b = restBase.endsWith('/')
      ? restBase.substring(0, restBase.length - 1)
      : restBase;
  return '$b/unfurl/image?url=${Uri.encodeComponent(imageUrl)}';
}

/// Card de link embed estilo Discord (print Twitch): site pequeno em cima,
/// título azul clicável, descrição 2-3 linhas, thumb 84px à direita.
class LinkEmbedCard extends ConsumerWidget {
  const LinkEmbedCard({super.key, required this.embed});

  final LinkEmbed embed;

  Future<void> _open() async {
    await openExternalLink(embed.url);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final imageUrl = embed.imageUrl;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: colors.borderHairline, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      embed.siteName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: colors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _LinkTitle(title: embed.title, onOpen: _open),
                    if (embed.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        embed.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 13,
                          height: 1.4,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (imageUrl != null && imageUrl.isNotEmpty) ...[
                const SizedBox(width: 12),
                _EmbedThumb(imageUrl: imageUrl, onOpen: _open),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkTitle extends StatefulWidget {
  const _LinkTitle({required this.title, required this.onOpen});

  final String title;
  final Future<void> Function() onOpen;

  @override
  State<_LinkTitle> createState() => _LinkTitleState();
}

class _LinkTitleState extends State<_LinkTitle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        behavior: HitTestBehavior.opaque,
        child: Text(
          widget.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            height: 1.3,
            color: colors.accent,
            decoration: _hovered
                ? TextDecoration.underline
                : TextDecoration.none,
            decorationColor: colors.accent,
          ),
        ),
      ),
    );
  }
}

class _EmbedThumb extends ConsumerWidget {
  const _EmbedThumb({required this.imageUrl, required this.onOpen});

  final String imageUrl;
  final Future<void> Function() onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proxy = unfurlImageProxyUrl(
      ref.watch(appConfigProvider).apiRestBaseUrl,
      imageUrl,
    );
    final asyncBytes = ref.watch(fileImageBytesProvider(proxy));
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onOpen,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: SizedBox(
            width: 84,
            height: 84,
            child: ColoredBox(
              color: AppTokens.surface2,
              child: asyncBytes.when(
                data: (bytes) => Image.memory(
                  bytes,
                  width: 84,
                  height: 84,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const _ThumbFallback(),
                ),
                loading: () => const _ThumbFallback(loading: true),
                error: (_, _) => const _ThumbFallback(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback({this.loading = false});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return const Center(
      child: AppIcon(AppIcons.imageMissing, color: AppTokens.textMuted),
    );
  }
}

/// Skeleton enquanto o unfurl resolve (largura do card, sem layout shift).
class LinkEmbedSkeleton extends StatelessWidget {
  const LinkEmbedSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: colors.borderHairline, width: 1),
        ),
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SkeletonBar(width: 90, height: 10),
                    SizedBox(height: 8),
                    _SkeletonBar(width: 220, height: 13),
                    SizedBox(height: 6),
                    _SkeletonBar(width: double.infinity, height: 11),
                  ],
                ),
              ),
              SizedBox(width: 12),
              _SkeletonBar(width: 84, height: 84),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppTokens.surface3,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
    );
  }
}
