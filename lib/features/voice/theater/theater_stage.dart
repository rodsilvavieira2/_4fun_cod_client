import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/rtc/rtc_service.dart';
import '../../../core/theme/appearance_theme.dart';
import '../voice_providers.dart';
import '../voice_video_tile.dart';
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
/// espaço (sem os tetos do default); `focus` (pins) exibe pinnadas em
/// destaque + resto em rail lateral (larga) ou faixa inferior (estreita).
/// Toque no tile alterna o pin (nunca o spotlight do default); o expandir
/// do overlay abre o menu `⋮` da stream. Troca de foco só move widgets
/// (chaves estáveis) — nunca reinscreve tracks.
class TheaterStage extends ConsumerWidget {
  const TheaterStage({super.key, required this.arg, this.onToggleFullscreen});

  final ({String serverId, String channelId}) arg;

  /// Fullscreen da sala (fornecido pelo [TheaterScreen]).
  final VoidCallback? onToggleFullscreen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voice = ref.watch(voiceControllerProvider(arg));
    final ui = ref.watch(theaterUiControllerProvider(arg));
    final voiceNotifier = ref.read(voiceControllerProvider(arg).notifier);
    final uiNotifier = ref.read(theaterUiControllerProvider(arg).notifier);

    if (voice.status != VoiceSessionStatus.connected) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 3));
    }
    final items = theaterStreamingItems(voice.participants);
    if (items.isEmpty) return const TheaterEmptyStage();

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
    final rest = [
      for (final i in items)
        if (!ui.pinnedStreamIds.contains(i.key)) i,
    ];
    final focusActive =
        ui.effectiveLayout == TheaterLayoutMode.focus && pinned.isNotEmpty;

    void onTapItem(TheaterMediaItem item) => uiNotifier.togglePin(item.key);

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

    if (!focusActive) {
      return _TheaterGrid(
        arg: arg,
        items: items,
        overlayVisible: overlayVisible,
        onTap: onTapItem,
        isWatching: watchingItem,
        onOpenMenu: openTileMenu,
        voiceNotifier: voiceNotifier,
      );
    }
    // Focus: pinnadas em destaque + restantes em rail lateral (larga)
    // ou faixa inferior (estreita).
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= kTheaterFocusBreakpoint;
        final main = Expanded(
          child: _TheaterGrid(
            arg: arg,
            items: pinned,
            overlayVisible: overlayVisible,
            role: VoiceVideoTileRole.spotlight,
            highlighted: true,
            onTap: onTapItem,
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
                  onTap: onTapItem,
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
                onTap: onTapItem,
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
    required this.onTap,
    required this.isWatching,
    required this.onOpenMenu,
    required this.voiceNotifier,
    this.role = VoiceVideoTileRole.grid,
    this.highlighted = false,
  });

  final ({String serverId, String channelId}) arg;
  final List<TheaterMediaItem> items;
  final bool overlayVisible;
  final void Function(TheaterMediaItem item) onTap;
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
    return TheaterStreamTile(
      arg: arg,
      participant: item.participant,
      source: item.source,
      role: role,
      isFocused: highlighted,
      isWatching: isWatching(item),
      onTap: () => onTap(item),
      onToggleWatch: _toggleWatch(item),
      onStopShare: _stopShare(item),
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

  VoidCallback? _stopShare(TheaterMediaItem item) {
    if (item.source != VoiceVideoSource.screen) return null;
    if (!voiceNotifier.isLocalParticipant(item.participant.id)) return null;
    return voiceNotifier.stopScreenShare;
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
            onStopShare: item.source == VoiceVideoSource.screen && local
                ? voiceNotifier.stopScreenShare
                : null,
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
            onStopShare: item.source == VoiceVideoSource.screen && local
                ? voiceNotifier.stopScreenShare
                : null,
            onExpand: () => onOpenMenu(item),
            overlayVisible: overlayVisible,
          ),
        );
      },
    );
  }
}

/// Estado vazio: sem transmissão, com CTA de câmera/share (usa tema atual).
class TheaterEmptyStage extends StatelessWidget {
  const TheaterEmptyStage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.theater_comedy, size: 30, color: colors.textSecondary),
            const SizedBox(height: 10),
            Text(
              'Nenhuma transmissão ativa',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Inicie sua câmera ou compartilhe sua tela.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 12,
                height: 1.35,
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
