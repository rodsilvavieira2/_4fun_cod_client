import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/appearance_theme.dart';
import 'app_file_image.dart';
import 'app_icon.dart';
import 'app_icon_button.dart';
import 'chat_image_actions.dart';
import 'ds_tokens.dart';

/// Item de mídia exibido no lightbox (imagem anexada ou GIF externo).
///
/// - `url`: path interno (`/api/v1/files/...`) ou URL absoluta externa.
/// - `previewUrl`: thumbnail estático do GIF (usado no estado pausado).
/// - `label`: nome sugerido para salvar/copiar (ex. `imagem-<id>`).
class MediaItem {
  const MediaItem({
    required this.url,
    this.kind = MediaKind.image,
    this.previewUrl,
    this.label,
  });

  final String url;
  final MediaKind kind;
  final String? previewUrl;
  final String? label;

  bool get isGif => kind == MediaKind.gif;
}

enum MediaKind { image, gif }

/// Abre o visualizador full-screen estilo Discord.
///
/// - `items` já filtrado (só READY + gifUrl não-nulo); `initialIndex` é
///   clampado para dentro da lista.
/// - Header mostra avatar + nome + timestamp (+ `# canal` opcional).
/// - Toolbar: zoom in/out/reset + copiar + salvar + fechar.
/// - Teclado: `ESC` fecha, `←/→` navegam (reseta o zoom a cada troca).
Future<void> showMediaLightbox({
  required BuildContext context,
  required List<MediaItem> items,
  int initialIndex = 0,
  required String authorName,
  String? authorAvatarUrl,
  required DateTime sentAt,
  String? channelName,
}) {
  if (items.isEmpty) return Future.value();
  final clamped = initialIndex.clamp(0, items.length - 1);
  // showGeneralDialog (não showDialog+Dialog): o Dialog padrão centraliza
  // e limita a largura (Align+ConstrainedBox), o que prendia o header/
  // toolbar no centro acima da imagem. Aqui a página ocupa a tela cheia,
  // então o header estende de borda a borda e a pill vai para o canto
  // superior direito com o gap compacto (padding horizontal 12).
  return showGeneralDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.88),
    barrierDismissible: true,
    barrierLabel: 'Fechar visualizador de mídia',
    transitionDuration: const Duration(milliseconds: 150),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
    pageBuilder: (dialogContext, animation, secondaryAnimation) =>
        _MediaLightboxView(
          items: items,
          initialIndex: clamped,
          authorName: authorName,
          authorAvatarUrl: authorAvatarUrl,
          sentAt: sentAt,
          channelName: channelName,
        ),
  );
}

/// Corpo do viewer: header + stage com [InteractiveViewer] + overlays.
///
/// `ConsumerStatefulWidget` para reaproveitar `copyChatImage`/`saveChatImage`
/// (precisam de `WidgetRef`) sem duplicar a lógica de bytes autenticados.
class _MediaLightboxView extends ConsumerStatefulWidget {
  const _MediaLightboxView({
    required this.items,
    required this.initialIndex,
    required this.authorName,
    required this.sentAt,
    this.authorAvatarUrl,
    this.channelName,
  });

  final List<MediaItem> items;
  final int initialIndex;
  final String authorName;
  final String? authorAvatarUrl;
  final DateTime sentAt;
  final String? channelName;

  @override
  ConsumerState<_MediaLightboxView> createState() =>
      _MediaLightboxViewState();
}

class _MediaLightboxViewState extends ConsumerState<_MediaLightboxView> {
  static const _minScale = 1.0;
  static const _maxScale = 4.0;

  late int _index;
  late TransformationController _zoom;
  late FocusNode _focus;
  bool _gifPlaying = true;

  MediaItem get _current => widget.items[_index];

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _zoom = TransformationController();
    _focus = FocusNode()..requestFocus();
  }

  @override
  void dispose() {
    _zoom.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).maybePop();

  void _goTo(int next) {
    if (widget.items.length < 2) return;
    setState(() {
      _index = (next % widget.items.length + widget.items.length) %
          widget.items.length;
      _gifPlaying = true;
    });
    _resetZoom();
  }

  void _resetZoom() {
    _zoom.value = Matrix4.identity();
    setState(() {});
  }

  double get _scale => _zoom.value.getMaxScaleOnAxis();

  void _zoomBy(double factor) {
    final next = (_scale * factor).clamp(_minScale, _maxScale);
    _zoom.value = Matrix4.diagonal3Values(next, next, 1);
    setState(() {});
  }

  Future<void> _copy() => copyChatImage(
        context: context,
        ref: ref,
        url: _current.url,
      );

  Future<void> _save() => saveChatImage(
        context: context,
        ref: ref,
        url: _current.url,
        suggestedName: _current.label,
      );

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _goTo(_index + 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _goTo(_index - 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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
    if (isToday) return 'Hoje às $hh:$mm';
    final dd = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    return '$dd/$mo/${local.year} $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      // Material transparente fullscreen (sem Dialog): garante que o header
      // ocupe toda a largura e a toolbar fique no canto superior direito.
      child: Material(
        color: Colors.transparent,
        child: Semantics(
          label:
              'Visualizador de mídia, item ${_index + 1} de ${widget.items.length}',
          child: SizedBox.expand(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  authorName: widget.authorName,
                  authorAvatarUrl: widget.authorAvatarUrl,
                  sentAtLabel: _formatTime(widget.sentAt),
                  channelName: widget.channelName,
                  scale: _scale,
                  onZoomIn: () => _zoomBy(1.25),
                  onZoomOut: () => _zoomBy(0.8),
                  onZoomReset: _resetZoom,
                  onCopy: _copy,
                  onSave: _save,
                  onClose: _close,
                ),
                Expanded(child: _stage()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Stage central: imagem com zoom/pan + setas + contador + badge GIF.
  Widget _stage() {
    final item = _current;
    // GIF pausado mostra o preview estático (sem animar bytes).
    final displayUrl =
        (item.isGif && !_gifPlaying) ? (item.previewUrl ?? item.url) : item.url;
    final colors = context.appColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fullscreen cobre a barrier, então o "clique fora" é tratado aqui:
        // tap no fundo fecha; tap na imagem/setas/play é absorvido e não fecha.
        return GestureDetector(
          onTap: _close,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * 0.92,
                    maxHeight: constraints.maxHeight * 0.92,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    child: DecoratedBox(
                      decoration: const BoxDecoration(color: Colors.black),
                      child: GestureDetector(
                        onTap: () {},
                        onDoubleTap: () {
                          if (_scale > 1.01) {
                            _resetZoom();
                          } else {
                            _zoomBy(2.0);
                          }
                        },
                      child: InteractiveViewer(
                        transformationController: _zoom,
                        minScale: _minScale,
                        maxScale: _maxScale,
                        boundaryMargin: const EdgeInsets.all(double.infinity),
                        onInteractionEnd: (_) => setState(() {}),
                        child: _ViewerImage(
                          url: displayUrl,
                          isGif: item.isGif,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (item.isGif)
              Positioned(
                top: 12,
                left: 16,
                child: _GifBadge(),
              ),
            if (widget.items.length > 1) ...[
              Positioned(
                left: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _NavArrow(
                    icon: AppIcons.chevronLeft,
                    tooltip: 'Anterior',
                    onPressed: () => _goTo(_index - 1),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _NavArrow(
                    icon: AppIcons.chevronRight,
                    tooltip: 'Próxima',
                    onPressed: () => _goTo(_index + 1),
                  ),
                ),
              ),
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      border: Border.all(color: colors.borderSubtle),
                    ),
                    child: Text(
                      '${_index + 1} de ${widget.items.length}',
                      style: const TextStyle(
                        fontFamily: 'Geist Mono',
                        fontSize: 11.5,
                        color: AppTokens.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (item.isGif)
              Positioned(
                bottom: 12,
                right: 16,
                child: _PlayPauseButton(
                  playing: _gifPlaying,
                  onPressed: () =>
                      setState(() => _gifPlaying = !_gifPlaying),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Header do viewer: avatar + nome + timestamp à esquerda, pill de ações à
/// direita (zoom + mídia) + fechar separado — espelho do Discord.
///
/// Pill compacta estilo referência: só ícones em 100% (`%` e reset aparecem
/// apenas quando zoomado), botões 28px, sem divider e sem borda inferior no
/// header (flutuante). Com 28px centralizados nos 52px do header, o gap do
/// topo é 12px, seguindo o padrão compacto.
class _Header extends StatelessWidget {
  const _Header({
    required this.authorName,
    required this.sentAtLabel,
    required this.scale,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoomReset,
    required this.onCopy,
    required this.onSave,
    required this.onClose,
    this.authorAvatarUrl,
    this.channelName,
  });

  final String authorName;
  final String? authorAvatarUrl;
  final String sentAtLabel;
  final String? channelName;
  final double scale;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomReset;
  final VoidCallback onCopy;
  final VoidCallback onSave;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final authorColorIndex =
        authorName.codeUnits.fold(0, (a, b) => a + b) % 4;
    final zoomed = (scale * 100).round() != 100;
    return Container(
      height: AppLayout.headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      // Sem borda inferior: header flutuante sobre o dim, como no Discord.
      child: Row(
        children: [
          _AuthorAvatar(url: authorAvatarUrl, name: authorName),
          const SizedBox(width: 10),
          // Expanded (sem Spacer): Flexible+Spacer dividiam o espaço livre
          // e sobravam ~38px vazios à direita, afastando a pill do canto.
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        authorName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: colors.authorColors[authorColorIndex],
                        ),
                      ),
                    ),
                    if (channelName != null) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '# $channelName',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Geist',
                            fontSize: 12,
                            color: colors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  sentAtLabel,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 11,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: colors.surface2,
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(color: colors.borderSubtle, width: 1),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIconButton(
                  icon: AppIcons.zoomOut,
                  tooltip: 'Reduzir zoom',
                  minSize: 28,
                  iconSize: 16,
                  onPressed: onZoomOut,
                ),
                if (zoomed)
                  SizedBox(
                    width: 44,
                    child: Center(
                      child: Text(
                        '${(scale * 100).round()}%',
                        style: TextStyle(
                          fontFamily: 'Geist Mono',
                          fontSize: 10.5,
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                  ),
                AppIconButton(
                  icon: AppIcons.zoomIn,
                  tooltip: 'Ampliar zoom',
                  minSize: 28,
                  iconSize: 16,
                  onPressed: onZoomIn,
                ),
                if (zoomed)
                  AppIconButton(
                    icon: AppIcons.reload,
                    tooltip: 'Resetar zoom (100%)',
                    minSize: 28,
                    iconSize: 16,
                    onPressed: onZoomReset,
                  ),
                AppIconButton(
                  icon: AppIcons.copy,
                  tooltip: 'Copiar imagem',
                  minSize: 28,
                  iconSize: 16,
                  onPressed: onCopy,
                ),
                AppIconButton(
                  icon: AppIcons.download,
                  tooltip: 'Salvar imagem',
                  minSize: 28,
                  iconSize: 16,
                  onPressed: onSave,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: colors.surface2,
              shape: BoxShape.circle,
              border: Border.all(color: colors.borderSubtle, width: 1),
            ),
            child: AppIconButton(
              icon: AppIcons.close,
              tooltip: 'Fechar (Esc)',
              minSize: 28,
              iconSize: 16,
              onPressed: onClose,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthorAvatar extends StatelessWidget {
  const _AuthorAvatar({required this.name, this.url});

  final String name;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surface2,
        shape: BoxShape.circle,
        border: Border.all(color: colors.borderHairline, width: 1),
      ),
      child: url != null
          ? AppFileImage(
              path: url,
              width: 32,
              height: 32,
              fallback: _initial(colors),
            )
          : _initial(colors),
    );
  }

  Widget _initial(AppThemePalette colors) {
    return Text(
      name.isEmpty ? '?' : name[0].toUpperCase(),
      style: TextStyle(
        fontFamily: 'Geist',
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: colors.textPrimary,
      ),
    );
  }
}

/// Renderiza interno (proxy autenticado) ou externo (CDN pública de GIF).
bool _isInternalFileUrl(String raw) {
  if (raw.startsWith('/')) return true;
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme) return true;
  return uri.path.contains('/api/v1/files/');
}

class _ViewerImage extends StatelessWidget {
  const _ViewerImage({required this.url, required this.isGif});

  final String url;
  final bool isGif;

  @override
  Widget build(BuildContext context) {
    if (!_isInternalFileUrl(url)) {
      return Image.network(
        url,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          final total = progress.expectedTotalBytes;
          final done = progress.cumulativeBytesLoaded;
          final value = total != null && total > 0 ? done / total : null;
          return SizedBox(
            width: 480,
            height: 320,
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: value,
                ),
              ),
            ),
          );
        },
        errorBuilder: (_, _, _) => const _ViewerError(),
      );
    }
    return AppFileImage(
      path: url,
      fit: BoxFit.contain,
      fallback: const SizedBox(
        width: 480,
        height: 320,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
    );
  }
}

class _ViewerError extends StatelessWidget {
  const _ViewerError();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 480,
      height: 320,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              AppIcons.imageMissing,
              color: AppTokens.textMuted,
              size: 28,
            ),
            SizedBox(height: 8),
            Text(
              'Falha ao carregar a mídia.',
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 12.5,
                color: AppTokens.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GifBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppTokens.borderSubtle, width: 1),
      ),
      child: const Text(
        'GIF',
        style: TextStyle(
          fontFamily: 'Geist',
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppTokens.textPrimary,
        ),
      ),
    );
  }
}

class _NavArrow extends StatelessWidget {
  const _NavArrow({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final List<List<dynamic>> icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onPressed,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              shape: BoxShape.circle,
              border: Border.all(color: colors.borderSubtle, width: 1),
            ),
            child: AppIcon(icon, size: 20, color: colors.textPrimary),
          ),
        ),
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.playing, required this.onPressed});

  final bool playing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Tooltip(
      message: playing ? 'Pausar GIF' : 'Reproduzir GIF',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onPressed,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              shape: BoxShape.circle,
              border: Border.all(color: colors.borderSubtle, width: 1),
            ),
            child: AppIcon(
              playing ? AppIcons.pause : AppIcons.play,
              size: 20,
              color: colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
