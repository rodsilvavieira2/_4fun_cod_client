import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/rtc/rtc_service.dart';
import '../../../core/theme/appearance_theme.dart';
import '../../../core/ui/app_icon.dart';
import '../../../core/ui/ds_tokens.dart';
import '../voice_providers.dart';
import '../voice_video_tile.dart';
import 'theater_empty_illustration.dart';
import 'theater_menus.dart';
import 'theater_stream_tile.dart';
import 'theater_ui_provider.dart';

/// Espaçamento do Theater (usa tokens do tema quando possível).
///
/// - [kTheaterGap]: margem externa + entre colunas principais (12).
/// - [kTheaterRailGap]: entre cards do rail secundário (8).
const double kTheaterGap = 12.0;
const double kTheaterRailGap = 8.0;

/// Largura do rail secundário: ~20% do stage, com limites úteis.
const double kTheaterRailMinWidth = 200;
const double kTheaterRailMaxWidth = 320;
const double kTheaterRailFraction = 0.24;

/// Abaixo desta largura o focus empilha (faixa inferior) em vez da
/// coluna lateral — medido via LayoutBuilder, nunca resolução física.
const double kTheaterFocusBreakpoint = 560;

/// Item de mídia do theater: cada publicação (tela/câmera) vira um tile.
/// Chave `<participantId>:<camera|screen>` — mesma usada em `pinnedStreamIds`.
class TheaterMediaItem {
  const TheaterMediaItem({required this.participant, required this.source});

  final RtcParticipant participant;
  final VoiceVideoSource source;

  String get key => '${participant.id}:${source.name}';
}

/// Publicações com vídeo (tela primeiro, depois câmera). Avatares ficam na
/// strip e NÃO contam no grid.
List<TheaterMediaItem> theaterStreamingItems(List<RtcParticipant> parts) {
  final shares = <TheaterMediaItem>[];
  final cameras = <TheaterMediaItem>[];
  for (final p in parts) {
    if (p.isScreenSharing) {
      shares.add(
        TheaterMediaItem(participant: p, source: VoiceVideoSource.screen),
      );
    }
    if (p.isCameraEnabled) {
      cameras.add(
        TheaterMediaItem(participant: p, source: VoiceVideoSource.camera),
      );
    }
  }
  return [...shares, ...cameras];
}

VoiceSpotlightSource _spotlightOf(VoiceVideoSource source) =>
    source == VoiceVideoSource.screen
    ? VoiceSpotlightSource.screen
    : VoiceSpotlightSource.camera;

/// Media Stage do theater: `auto`/`grid` usam grid 16:9 que preenche o
/// espaço (sem os tetos do default, sem clique); `focus` exibe SEMPRE uma
/// stream em destaque + resto em rail lateral (larga) ou faixa inferior
/// (estreita). Clicar no rail troca o foco (nunca esvazia, nunca toca o
/// spotlight do default); o expandir do overlay abre o menu `⋮` da stream.
/// Troca de foco só move widgets (chaves estáveis) — nunca reinscreve tracks.
class TheaterStage extends ConsumerWidget {
  const TheaterStage({
    super.key,
    required this.arg,
    this.onToggleFullscreen,
    this.onShareScreen,
  });

  final ({String serverId, String channelId}) arg;

  /// Fullscreen da sala (fornecido pelo [TheaterScreen]).
  final VoidCallback? onToggleFullscreen;

  /// Fluxo "Compartilhar tela" (modal Go Live + `startScreenShare`,
  /// fornecido pelo [TheaterScreen]). Nulo no takeover fullscreen — lá o
  /// CTA de share do estado vazio fica desabilitado (a câmera continua
  /// ligável direto pelo provider).
  final VoidCallback? onShareScreen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voice = ref.watch(voiceControllerProvider(arg));
    final ui = ref.watch(theaterUiControllerProvider(arg));
    final voiceNotifier = ref.read(voiceControllerProvider(arg).notifier);
    final uiNotifier = ref.read(theaterUiControllerProvider(arg).notifier);
    final colors = context.appColors;
    final items = theaterStreamingItems(voice.participants);

    final Widget body;
    if (voice.status != VoiceSessionStatus.connected) {
      body = const Center(child: CircularProgressIndicator(strokeWidth: 3));
    } else if (items.isEmpty) {
      body = TheaterEmptyStage(arg: arg, onShareScreen: onShareScreen);
    } else {
      body = _streamingBody(context, ref, ui, voiceNotifier, uiNotifier, items);
    }

    // Fundo temático do palco em TODOS os estados (loading, vazio, grid,
    // focus): glows do accent + anéis vazados atrás de spinners, cards e
    // tiles — nunca hardcoded, sempre do tema atual.
    return Stack(
      children: [
        Positioned.fill(
          child: TheaterStageBackdrop(
            accent: colors.accent,
            ring: colors.borderHairline,
          ),
        ),
        Positioned.fill(child: body),
      ],
    );
  }

  /// Palco com transmissões (grid `auto`/`grid` ou destaque `focus`):
  /// extraído do `build` para que o backdrop temático envolva todos os
  /// estados sem duplicar a decoração.
  Widget _streamingBody(
    BuildContext context,
    WidgetRef ref,
    TheaterUiState ui,
    VoiceController voiceNotifier,
    TheaterUiController uiNotifier,
    List<TheaterMediaItem> items,
  ) {
    // Remove pins de streams encerradas sem tocar no resto do estado.
    final validKeys = {for (final i in items) i.key};
    if (ui.pinnedStreamIds.any((k) => !validKeys.contains(k))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(theaterUiControllerProvider(arg).notifier)
            .prunePins(validKeys);
      });
    }

    final overlayVisible = !ui.hideOverlays;
    final byKey = {for (final i in items) i.key: i};
    final pinned = [
      for (final k in ui.pinnedStreamIds)
        if (byKey.containsKey(k)) byKey[k]!,
    ];

    bool watchingItem(TheaterMediaItem item) => _watching(voiceNotifier, item);

    void openTileMenu(TheaterMediaItem item) {
      showStreamTileMenu(
        context: context,
        ref: ref,
        arg: arg,
        streamKey: item.key,
        participantId: item.participant.id,
        source: item.source,
        onToggleFullscreen: onToggleFullscreen ?? () {},
      );
    }

    // auto/grid: grade pura, sem clique (a troca de foco só existe no foco).
    final isFocusLayout = ui.layout == TheaterLayoutMode.focus;
    if (!isFocusLayout) {
      return _TheaterGrid(
        arg: arg,
        items: items,
        overlayVisible: overlayVisible,
        onTap: null,
        isWatching: watchingItem,
        onOpenMenu: openTileMenu,
        voiceNotifier: voiceNotifier,
      );
    }
    // Focus: SEMPRE um destaque (primeiro pin válido ou primeira stream) +
    // restantes no rail. Clicar no rail vira o novo foco; clicar no foco
    // é no-op (nunca esvazia).
    final focused = pinned.isNotEmpty ? pinned.first : items.first;
    final rest = [
      for (final i in items)
        if (i.key != focused.key) i,
    ];

    void onFocusItem(TheaterMediaItem item) {
      if (item.key == focused.key) return;
      uiNotifier.focusStream(item.key);
    }

    // Focus: destaque + restantes em rail lateral (larga)
    // ou faixa inferior (estreita).
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= kTheaterFocusBreakpoint;
        final main = Expanded(
          child: _TheaterGrid(
            arg: arg,
            items: [focused],
            overlayVisible: overlayVisible,
            role: VoiceVideoTileRole.spotlight,
            highlighted: true,
            onTap: null,
            isWatching: watchingItem,
            onOpenMenu: openTileMenu,
            voiceNotifier: voiceNotifier,
          ),
        );
        if (rest.isEmpty) return Row(children: [main]);
        if (wide) {
          final railWidth = (constraints.maxWidth * kTheaterRailFraction).clamp(
            kTheaterRailMinWidth,
            kTheaterRailMaxWidth,
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              main,
              SizedBox(width: kTheaterGap),
              SizedBox(
                width: railWidth,
                child: _TheaterSideColumn(
                  arg: arg,
                  items: rest,
                  overlayVisible: overlayVisible,
                  onTap: onFocusItem,
                  isWatching: watchingItem,
                  onOpenMenu: openTileMenu,
                  voiceNotifier: voiceNotifier,
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            main,
            const SizedBox(height: kTheaterRailGap),
            SizedBox(
              height: 132,
              child: _TheaterBottomStrip(
                arg: arg,
                items: rest,
                overlayVisible: overlayVisible,
                onTap: onFocusItem,
                isWatching: watchingItem,
                onOpenMenu: openTileMenu,
                voiceNotifier: voiceNotifier,
              ),
            ),
          ],
        );
      },
    );
  }

  bool _watching(VoiceController notifier, TheaterMediaItem item) {
    if (notifier.isLocalParticipant(item.participant.id)) return true;
    return notifier.isWatching(item.participant.id, _spotlightOf(item.source));
  }
}

class _TheaterGrid extends StatelessWidget {
  const _TheaterGrid({
    required this.arg,
    required this.items,
    required this.overlayVisible,
    required this.isWatching,
    required this.onOpenMenu,
    required this.voiceNotifier,
    this.onTap,
    this.role = VoiceVideoTileRole.grid,
    this.highlighted = false,
  });

  final ({String serverId, String channelId}) arg;
  final List<TheaterMediaItem> items;
  final bool overlayVisible;

  /// Nulo = tile sem clique (grade auto/grid e tile já em foco).
  /// Fora do modo `focus` o clique nunca troca foco.
  final void Function(TheaterMediaItem item)? onTap;
  final bool Function(TheaterMediaItem item) isWatching;
  final void Function(TheaterMediaItem item) onOpenMenu;
  final VoiceController voiceNotifier;
  final VoiceVideoTileRole role;

  /// Destaque do foco usa o accent do tema (nunca hardcoded).
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = kTheaterGap;
        final viewport = Size(
          math.max(1.0, constraints.maxWidth),
          math.max(1.0, constraints.maxHeight),
        );
        const aspectRatio = 16 / 9;
        // Tile único preenche o máximo 16:9 cabível — sem teto de 960px
        // do grid geral, para não deixar canvas vazio no theater.
        late final Size tileSize;
        late final Size gridSize;
        if (items.length == 1) {
          final width = math.min(viewport.width, viewport.height * aspectRatio);
          final height = width / aspectRatio;
          tileSize = Size(width, height);
          gridSize = Size(viewport.width, viewport.height);
        } else {
          final geometry = _theaterGridGeometry(
            viewport: viewport,
            tileCount: items.length,
            gap: gap,
          );
          tileSize = geometry.tileSize;
          gridSize = geometry.gridSize;
        }
        return SizedBox(
          width: gridSize.width,
          height: gridSize.height,
          child: Center(
            child: SizedBox(
              width: items.length == 1 ? gridSize.width : gridSize.width,
              height: items.length == 1 ? gridSize.height : gridSize.height,
              child: items.length == 1
                  ? Center(
                      child: SizedBox(
                        key: ValueKey(items.first.key),
                        width: tileSize.width,
                        height: tileSize.height,
                        child: _buildTile(items.first),
                      ),
                    )
                  : Wrap(
                      alignment: WrapAlignment.center,
                      runAlignment: WrapAlignment.center,
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final item in items)
                          SizedBox(
                            key: ValueKey(item.key),
                            width: tileSize.width,
                            height: tileSize.height,
                            child: _buildTile(item),
                          ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTile(TheaterMediaItem item) {
    final onTap = this.onTap;
    return TheaterStreamTile(
      arg: arg,
      participant: item.participant,
      source: item.source,
      role: role,
      isFocused: highlighted,
      isWatching: isWatching(item),
      onTap: onTap == null ? null : () => onTap(item),
      onToggleWatch: _toggleWatch(item),
      // Theater nunca exibe o botão de encerrar no preview: parar o share
      // vive só na control bar global (sem duplicar o hang-up por tile).
      onStopShare: null,
      onExpand: () => onOpenMenu(item),
      overlayVisible: overlayVisible,
    );
  }

  VoidCallback? _toggleWatch(TheaterMediaItem item) {
    if (item.source != VoiceVideoSource.screen) return null;
    if (voiceNotifier.isLocalParticipant(item.participant.id)) return null;
    return () => voiceNotifier.toggleWatch(
      item.participant.id,
      _spotlightOf(item.source),
    );
  }
}

class _TheaterGridGeometry {
  const _TheaterGridGeometry({required this.tileSize, required this.gridSize});
  final Size tileSize;
  final Size gridSize;
}

/// Geometria do theater: igual ao default, mas SEM os tetos de 960/720px —
/// o palco deve usar quase todo o espaço disponível.
_TheaterGridGeometry _theaterGridGeometry({
  required Size viewport,
  required int tileCount,
  double gap = 12,
  double aspectRatio = 16 / 9,
  int maxColumns = 5,
}) {
  assert(tileCount > 0);
  final width = math.max(1.0, viewport.width);
  final height = math.max(1.0, viewport.height);
  _TheaterGridGeometry? best;
  var bestArea = -1.0;
  var bestEmpty = tileCount;
  for (var columns = 1; columns <= math.min(tileCount, maxColumns); columns++) {
    final rows = (tileCount / columns).ceil();
    final wPerTile = (width - gap * (columns - 1)) / columns;
    final hPerTile = (height - gap * (rows - 1)) / rows;
    if (wPerTile <= 0 || hPerTile <= 0) continue;
    final tileW = math.min(wPerTile, hPerTile * aspectRatio);
    final tileH = tileW / aspectRatio;
    final area = tileW * tileH;
    final empty = rows * columns - tileCount;
    final better =
        area > bestArea + 0.5 ||
        ((area - bestArea).abs() <= 0.5 && empty < bestEmpty);
    if (!better) continue;
    bestArea = area;
    bestEmpty = empty;
    best = _TheaterGridGeometry(
      tileSize: Size(tileW, tileH),
      gridSize: Size(
        columns * tileW + (columns - 1) * gap,
        rows * tileH + (rows - 1) * gap,
      ),
    );
  }
  return best ??
      _TheaterGridGeometry(
        tileSize: const Size(1, 1),
        gridSize: Size(1, tileCount.toDouble()),
      );
}

/// Rail lateral do focus (janela larga): cards 16:9 em lista vertical
/// com gaps e raio consistentes.
class _TheaterSideColumn extends StatelessWidget {
  const _TheaterSideColumn({
    required this.arg,
    required this.items,
    required this.overlayVisible,
    required this.onTap,
    required this.isWatching,
    required this.onOpenMenu,
    required this.voiceNotifier,
  });

  final ({String serverId, String channelId}) arg;
  final List<TheaterMediaItem> items;
  final bool overlayVisible;
  final void Function(TheaterMediaItem item) onTap;
  final bool Function(TheaterMediaItem item) isWatching;
  final void Function(TheaterMediaItem item) onOpenMenu;
  final VoiceController voiceNotifier;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: kTheaterRailGap),
      itemBuilder: (context, index) {
        final item = items[index];
        final local = voiceNotifier.isLocalParticipant(item.participant.id);
        return AspectRatio(
          aspectRatio: 16 / 9,
          child: TheaterStreamTile(
            key: ValueKey(item.key),
            arg: arg,
            participant: item.participant,
            source: item.source,
            role: VoiceVideoTileRole.miniature,
            isFocused: false,
            isWatching: isWatching(item),
            onTap: () => onTap(item),
            onToggleWatch: item.source == VoiceVideoSource.screen && !local
                ? () => voiceNotifier.toggleWatch(
                    item.participant.id,
                    VoiceSpotlightSource.screen,
                  )
                : null,
            // Sem botão de encerrar no preview (só na control bar global).
            onStopShare: null,
            onExpand: () => onOpenMenu(item),
            overlayVisible: overlayVisible,
          ),
        );
      },
    );
  }
}

/// Faixa inferior do focus (janela estreita): rail horizontal compacto.
class _TheaterBottomStrip extends StatelessWidget {
  const _TheaterBottomStrip({
    required this.arg,
    required this.items,
    required this.overlayVisible,
    required this.onTap,
    required this.isWatching,
    required this.onOpenMenu,
    required this.voiceNotifier,
  });

  final ({String serverId, String channelId}) arg;
  final List<TheaterMediaItem> items;
  final bool overlayVisible;
  final void Function(TheaterMediaItem item) onTap;
  final bool Function(TheaterMediaItem item) isWatching;
  final void Function(TheaterMediaItem item) onOpenMenu;
  final VoiceController voiceNotifier;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.zero,
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(width: kTheaterRailGap),
      itemBuilder: (context, index) {
        final item = items[index];
        final local = voiceNotifier.isLocalParticipant(item.participant.id);
        return AspectRatio(
          aspectRatio: 16 / 9,
          child: TheaterStreamTile(
            key: ValueKey(item.key),
            arg: arg,
            participant: item.participant,
            source: item.source,
            role: VoiceVideoTileRole.miniature,
            isFocused: false,
            isWatching: isWatching(item),
            onTap: () => onTap(item),
            onToggleWatch: item.source == VoiceVideoSource.screen && !local
                ? () => voiceNotifier.toggleWatch(
                    item.participant.id,
                    VoiceSpotlightSource.screen,
                  )
                : null,
            // Sem botão de encerrar no preview (só na control bar global).
            onStopShare: null,
            onExpand: () => onOpenMenu(item),
            overlayVisible: overlayVisible,
          ),
        );
      },
    );
  }
}

/// Estado vazio: sem transmissão, com ilustração undraw recolorida no accent
/// do tema, CTAs de câmera/share e ajuda. O fundo temático vem do
/// [TheaterStage], que o mantém atrás do palco em todos os estados —
/// aqui só o card central.
class TheaterEmptyStage extends ConsumerWidget {
  const TheaterEmptyStage({super.key, required this.arg, this.onShareScreen});

  final ({String serverId, String channelId}) arg;

  /// Ver [TheaterStage.onShareScreen].
  final VoidCallback? onShareScreen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final voice = ref.watch(voiceControllerProvider(arg));
    final voiceNotifier = ref.read(voiceControllerProvider(arg).notifier);
    final busy = voice.isReconnecting;
    final shareAction = busy ? null : onShareScreen;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          decoration: BoxDecoration(
            color: colors.surface1,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colors.accent.withValues(alpha: 0.22)),
            boxShadow: AppShadows.popover,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const TheaterEmptyIllustration(height: 148),
              const SizedBox(height: 16),
              Text(
                'Nenhuma transmissão ativa',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Inicie sua câmera ou compartilhe sua tela para começar',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 13,
                  height: 1.4,
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: busy ? null : voiceNotifier.toggleCamera,
                    icon: const AppIcon(AppIcons.video, size: 16),
                    label: const Text('Iniciar câmera'),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.accent,
                      foregroundColor: colors.onAccent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: const StadiumBorder(),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: shareAction,
                    icon: const AppIcon(AppIcons.screenShare, size: 16),
                    label: const Text('Compartilhar tela'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.textPrimary,
                      side: BorderSide(
                        color: colors.accent.withValues(alpha: 0.55),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: const StadiumBorder(),
                    ).copyWith(
                      mouseCursor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.disabled)
                            ? SystemMouseCursors.basic
                            : SystemMouseCursors.click,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(height: 1, color: colors.borderHairline),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => showTheaterEmptyHelp(context),
                icon: AppIcon(AppIcons.info, size: 14, color: colors.textMuted),
                label: Text(
                  'Saiba como funciona',
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 12,
                    color: colors.textMuted,
                    decoration: TextDecoration.underline,
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

/// Ajuda do estado vazio: diálogo simples na língua dos modais do app.
Future<void> showTheaterEmptyHelp(BuildContext context) {
  final colors = context.appColors;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: colors.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: BorderSide(color: colors.borderSubtle),
      ),
      title: Text(
        'Como funciona o Modo Teatro',
        style: Theme.of(
          dialogContext,
        ).textTheme.titleMedium?.copyWith(color: colors.textPrimary),
      ),
      content: Text(
        'Quando alguém ligar a câmera ou compartilhar a tela, a transmissão '
        'aparece aqui no palco. Use os botões acima para iniciar a sua — ou '
        'os controles abaixo para microfone, câmera e tela a qualquer momento.',
        style: TextStyle(
          fontFamily: 'Geist',
          fontSize: 13,
          height: 1.45,
          color: colors.textSecondary,
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          style: FilledButton.styleFrom(
            backgroundColor: colors.accent,
            foregroundColor: colors.onAccent,
          ),
          child: const Text('Entendi'),
        ),
      ],
    ),
  );
}

/// Fundo temático do palco do Modo Teatro: glow do accent no topo + dois
/// anéis vazados nas laterais. Montado pelo [TheaterStage] atrás do conteúdo
/// em TODOS os estados (loading, vazio, grid, focus) — nunca hardcoded,
/// sempre do tema atual.
class TheaterStageBackdrop extends StatelessWidget {
  const TheaterStageBackdrop({
    super.key,
    required this.accent,
    required this.ring,
  });

  final Color accent;
  final Color ring;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TheaterStageBackdropPainter(accent: accent, ring: ring),
    );
  }
}

class _TheaterStageBackdropPainter extends CustomPainter {
  _TheaterStageBackdropPainter({required this.accent, required this.ring});

  final Color accent;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    // Glow principal: topo-centro, na cor do tema.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader =
            RadialGradient(
              colors: [accent.withValues(alpha: 0.14), Colors.transparent],
            ).createShader(
              Rect.fromCircle(
                center: Offset(size.width / 2, -size.height * 0.1),
                radius: size.width * 0.5,
              ),
            ),
    );
    // Glows laterais suaves (eco dos cantos da referência).
    for (final center in [
      Offset(size.width * 0.08, -size.height * 0.05),
      Offset(size.width * 0.92, -size.height * 0.05),
    ]) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader =
              RadialGradient(
                colors: [accent.withValues(alpha: 0.07), Colors.transparent],
              ).createShader(
                Rect.fromCircle(center: center, radius: size.width * 0.22),
              ),
      );
    }
    // Anéis vazados nas laterais, parcialmente fora da tela.
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = ring;
    final radius = math.min(size.width, size.height) * 0.42;
    canvas.drawCircle(
      Offset(-radius * 0.4, size.height * 0.52),
      radius,
      ringPaint,
    );
    canvas.drawCircle(
      Offset(size.width + radius * 0.4, size.height * 0.52),
      radius,
      ringPaint,
    );
  }

  @override
  bool shouldRepaint(_TheaterStageBackdropPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.ring != ring;
}
