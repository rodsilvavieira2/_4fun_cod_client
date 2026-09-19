import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/rtc/rtc_providers.dart';
import '../../../core/theme/appearance_theme.dart';
import '../../../core/ui/app_icon.dart';
import '../../../core/ui/app_icon_button.dart';
import '../../../core/ui/ds_tokens.dart';
import '../../../core/ui/settings_modal.dart';
import '../go_live_modal.dart';
import '../voice_fullscreen_window.dart';
import '../voice_providers.dart';
import 'theater_presence_stack.dart';
import 'theater_chat_drawer.dart';
import 'theater_control_bar.dart';
import 'theater_stage.dart';
import 'theater_strip.dart';
import 'theater_ui_provider.dart';

/// Largura em que o chat vira coluna real (terceira coluna). Abaixo disso
/// vira overlay/drawer — medido via LayoutBuilder, nunca resolução física.
const double kTheaterChatColumnBreakpoint = 960;
const double kTheaterChatMinWidth = 300;
const double kTheaterChatMaxWidth = 380;
const double kTheaterChatFraction = 0.22;

/// Takeover de janela toda do Modo Teatro (ADR 0003): mesma sala LiveKit
/// (mesmo `voiceControllerProvider(arg)`), só apresentação diferente.
/// Entrada sempre em default/auto; saída restaura o default intacto.
class TheaterScreen extends ConsumerStatefulWidget {
  const TheaterScreen({
    super.key,
    required this.serverId,
    required this.channelId,
  });

  final String serverId;
  final String channelId;

  @override
  ConsumerState<TheaterScreen> createState() => _TheaterScreenState();
}

class _TheaterScreenState extends ConsumerState<TheaterScreen> {
  Timer? _hideTimer;

  /// Vira `true` na primeira abertura do chat e nunca volta: a partir daí
  /// o drawer permanece montado em `Offstage` quando colapsado, então o
  /// `chatControllerProvider` (autoDispose) nunca perde o último listener
  /// e não refaz `joinChannelAndWait + fetchMessages` a cada toggle.
  /// Lazy: enquanto o usuário nunca abrir, nada é montado/buscado.
  bool _chatEverOpened = false;

  ({String serverId, String channelId}) get arg =>
      (serverId: widget.serverId, channelId: widget.channelId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(theaterUiControllerProvider(arg).notifier).enterTheater();
    });
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      final voice = ref.read(voiceControllerProvider(arg));
      if (voice.isFullscreen) {
        ref
            .read(theaterUiControllerProvider(arg).notifier)
            .setControlsVisible(false);
      }
    });
  }

  void _reveal() {
    _scheduleHide();
    ref
        .read(theaterUiControllerProvider(arg).notifier)
        .setControlsVisible(true);
  }

  Future<void> _exit() async {
    ref.read(theaterUiControllerProvider(arg).notifier).exitTheater();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _leave() async {
    try {
      await exitVoiceFullscreenWindow(session: null);
    } catch (_) {
      // Sem janela (testes): o estado cobre a UI.
    }
    ref.read(voiceControllerProvider(arg).notifier).setFullscreen(false);
    await ref.read(voiceControllerProvider(arg).notifier).leave();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _toggleFullscreen() async {
    final notifier = ref.read(voiceControllerProvider(arg).notifier);
    VoiceFullscreenWindowSession? session;
    notifier.setFullscreen(true);
    try {
      session = await enterVoiceFullscreenWindow();
    } catch (_) {
      // Takeover in-app cobre a falha de janela.
    }
    if (!mounted) {
      notifier.setFullscreen(false);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              TheaterStage(arg: arg),
              Positioned(
                top: kTheaterGap,
                right: kTheaterGap,
                child: IconButton(
                  tooltip: 'Sair da tela cheia',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                    foregroundColor: Colors.white,
                  ),
                  icon: AppIcon(AppIcons.fullscreenExit),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    try {
      await exitVoiceFullscreenWindow(session: session);
    } catch (_) {
      // Janela já fechada: nada a devolver.
    }
    notifier.setFullscreen(false);
  }

  Future<void> _toggleScreenShare() async {
    final notifier = ref.read(voiceControllerProvider(arg).notifier);
    final current = ref.read(voiceControllerProvider(arg));
    if (current.isScreenSharing) {
      await notifier.stopScreenShare();
      return;
    }
    final goLive = await showGoLiveModal(
      context,
      backend: ref.read(nativeMediaServicesProvider).screenShare,
      pendingQuality: ref.read(rtcServiceProvider).screenShareQuality,
    );
    if (goLive == null) return;
    await notifier.startScreenShare(
      goLive.sourceId,
      includeSystemAudio: goLive.includeAudio,
      quality: goLiveQualityFor(goLive.quality),
      kind: goLive.kind,
    );
  }

  @override
  Widget build(BuildContext context) {
    final voice = ref.watch(voiceControllerProvider(arg));
    final ui = ref.watch(theaterUiControllerProvider(arg));
    // Marca a primeira abertura sem `setState`: o frame atual já monta o
    // chat via `ui.chatOpen`; a flag só importa nos próximos builds
    // (colapsado → mantém montado em Offstage em vez de desmontar).
    if (ui.chatOpen) _chatEverOpened = true;
    final immersive = voice.isFullscreen && !ui.controlsVisible;
    final overlayVisible = !immersive || !ui.hideOverlays;
    final colors = context.appColors;

    return MouseRegion(
      onEnter: (_) => _reveal(),
      onHover: (_) => _reveal(),
      cursor: overlayVisible
          ? SystemMouseCursors.basic
          : SystemMouseCursors.none,
      child: Scaffold(
        backgroundColor: colors.background,
        body: Column(
          children: [
            _TheaterHeader(
              arg: arg,
              chatOpen: ui.chatOpen,
              onExit: _exit,
              onToggleChat: () => ref
                  .read(theaterUiControllerProvider(arg).notifier)
                  .toggleChat(),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxW = constraints.maxWidth;
                  final wide = maxW >= kTheaterChatColumnBreakpoint;
                  final chatColumnVisible = ui.chatOpen && wide;
                  final chatOverlayVisible = ui.chatOpen && !wide;
                  // Após a 1ª abertura, mantém montado (Offstage) nos dois
                  // slots para que ao menos um listener do
                  // `chatControllerProvider` sobreviva ao toggle e ao resize
                  // coluna↔overlay — sem refetch/rejoin.
                  final chatMounted = _chatEverOpened;
                  final chatColumnMounted = chatMounted && wide;
                  final chatOverlayMounted = chatMounted && !wide;
                  final chatWidth = wide
                      ? (maxW * kTheaterChatFraction).clamp(
                          kTheaterChatMinWidth,
                          kTheaterChatMaxWidth,
                        )
                      : 340.0;
                  return Padding(
                    padding: const EdgeInsets.all(kTheaterGap),
                    child: Stack(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: voice.isReconnecting
                                        ? const Center(
                                            child: CircularProgressIndicator(
                                              strokeWidth: 3,
                                            ),
                                          )
                                        : TheaterStage(
                                            arg: arg,
                                            onToggleFullscreen:
                                                _toggleFullscreen,
                                          ),
                                  ),
                                  TheaterStrip(arg: arg),
                                  // Controles flutuantes compactos, próximos
                                  // da composição (sem textos laterais). No
                                  // fullscreen imersivo somem (auto-hide).
                                  if (!immersive)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Center(
                                        child: TheaterControlBar(
                                          arg: arg,
                                          onToggleScreenShare:
                                              _toggleScreenShare,
                                          onOpenSettings: () =>
                                              showSettingsModal(context),
                                          onToggleFullscreen: _toggleFullscreen,
                                          onLeave: _leave,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (chatColumnMounted) ...[
                              const SizedBox(width: kTheaterGap),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOutCubic,
                                width: chatColumnVisible ? chatWidth : 0,
                                // Recorta o painel de largura fixa durante a
                                // animação 0↔chatWidth (sem decoration o
                                // `clipBehavior` do Container assertaria).
                                child: ClipRect(
                                  child: Offstage(
                                    offstage: !chatColumnVisible,
                                    child: TickerMode(
                                      enabled: chatColumnVisible,
                                      child: SizedBox(
                                        width: chatWidth,
                                        child: _TheaterChatPanel(
                                          serverId: widget.serverId,
                                          channelId: widget.channelId,
                                          onClose: () => ref
                                              .read(
                                                theaterUiControllerProvider(
                                                  arg,
                                                ).notifier,
                                              )
                                              .toggleChat(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        // Janela estreita: chat vira overlay/drawer à direita.
                        // Mantido montado em Offstage após a 1ª abertura.
                        if (chatOverlayMounted)
                          Positioned(
                            top: 0,
                            bottom: 0,
                            right: 0,
                            width: math.min(340, math.max(0, maxW - 24)),
                            child: Offstage(
                              offstage: !chatOverlayVisible,
                              child: TickerMode(
                                enabled: chatOverlayVisible,
                                child: _TheaterChatPanel(
                                  serverId: widget.serverId,
                                  channelId: widget.channelId,
                                  onClose: () => ref
                                      .read(
                                        theaterUiControllerProvider(arg).notifier,
                                      )
                                      .toggleChat(),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Painel de chat do theater: card arredondado do tema com sombra +
/// botão fechar. Como coluna preenche a altura; como overlay flutua
/// à direita sem comprimir o stage.
class _TheaterChatPanel extends StatelessWidget {
  const _TheaterChatPanel({
    required this.serverId,
    required this.channelId,
    required this.onClose,
  });

  final String serverId;
  final String channelId;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: colors.borderSubtle),
          boxShadow: AppShadows.popover,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: TheaterChatDrawer(
                serverId: serverId,
                channelId: channelId,
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: AppIconButton(
                icon: AppIcons.close,
                tooltip: 'Fechar chat',
                minSize: 28,
                onPressed: onClose,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Header compacto do theater: marca + sala à esquerda; toggle,
/// presença e chat à direita. Visual leve, sem consumir altura.
class _TheaterHeader extends ConsumerWidget {
  const _TheaterHeader({
    required this.arg,
    required this.chatOpen,
    required this.onExit,
    required this.onToggleChat,
  });

  final ({String serverId, String channelId}) arg;
  final bool chatOpen;
  final VoidCallback onExit;
  final VoidCallback onToggleChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: kTheaterGap),
      decoration: BoxDecoration(
        color: colors.surface1,
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '4fun',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 10),
              AppIcon(AppIcons.volumeHigh, size: 14, color: colors.textMuted),
              const SizedBox(width: 6),
              Text(
                'Sala de voz e vídeo',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: colors.textMuted),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Toggle Modo Teatro (ON aqui; desligar = sair).
              Tooltip(
                message: 'Sair do Modo Teatro',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: colors.accent),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIcon(
                        AppIcons.theater,
                        size: 14,
                        color: colors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Modo Teatro',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(width: 2),
                      SizedBox(
                        height: 26,
                        child: FittedBox(
                          child: Switch.adaptive(
                            value: true,
                            activeThumbColor: colors.accent,
                            onChanged: (_) => onExit(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              TheaterPresenceStack(arg: arg),
              const SizedBox(width: 4),
              AppIconButton(
                icon: AppIcons.chat,
                tooltip: chatOpen ? 'Fechar chat' : 'Abrir chat',
                isActive: chatOpen,
                onPressed: onToggleChat,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
