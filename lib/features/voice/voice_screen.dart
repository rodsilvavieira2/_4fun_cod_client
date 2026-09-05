import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rtc/rtc_providers.dart';
import '../../core/rtc/rtc_service.dart';
import '../../core/rtc/rtc_video_view.dart';
import '../../core/rtc/screen_share_picker.dart';
import '../../core/ui/ui.dart';
import 'voice_providers.dart';
import 'voice_video_tile.dart';

/// Canal de voz: painel de participantes (nome, mute, active speaker) +
/// barra de controles (entrar/sair, mute/unmute).
///
/// Embarcada no [ServerShellScreen] no lugar do placeholder da Fase 4 —
/// nenhuma rota nova (a view mora no shell, como o chat).
class VoiceScreen extends ConsumerWidget {
  const VoiceScreen({
    super.key,
    required this.serverId,
    required this.channelId,
    required this.channelName,
  });

  final String serverId;
  final String channelId;
  final String channelName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arg = (serverId: serverId, channelId: channelId);
    final state = ref.watch(voiceControllerProvider(arg));
    final notifier = ref.read(voiceControllerProvider(arg).notifier);

    // Erros de toggle DENTRO da sessão (mic/câmera) aparecem via SnackBar —
    // o `errorMessage` do painel só renderiza no ramo `error` do status.
    ref.listen(voiceControllerProvider(arg), (prev, next) {
      final message = next.errorMessage;
      if (message != null &&
          message != prev?.errorMessage &&
          next.status == VoiceSessionStatus.connected) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
    });

    final controls = _Controls(
      state: state,
      onJoin: notifier.join,
      onLeave: notifier.leave,
      onToggleMicrophone: notifier.toggleMicrophone,
      onToggleCamera: notifier.toggleCamera,
      onToggleScreenShare: () => _toggleScreenShare(context, ref),
      onToggleSystemAudio: notifier.toggleIncludeSystemAudio,
      onOpenSettings: () => _openCameraSettings(context, ref, arg),
      onOpenQuality: () => _openScreenShareQuality(context, ref, arg),
    );
    final connected = state.status == VoiceSessionStatus.connected;

    return Stack(
      children: [
        Column(
          children: [
            // Banner de reconexão automática: a sessão continua `connected`.
            if (state.isReconnecting && connected) const _ReconnectingBanner(),
            // Áudio remoto bloqueado pelo browser (autoplay policy no web).
            if (state.isAudioBlocked && connected)
              _AudioBlockedBanner(onTap: notifier.resumeAudio),
            Expanded(
              child: _ParticipantsPanel(
                state: state,
                notifier: notifier,
                arg: arg,
              ),
            ),
          ],
        ),
        if (connected)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Center(child: controls),
          )
        else
          Align(alignment: Alignment.bottomCenter, child: controls),
      ],
    );
  }

  /// Fluxo do botão de compartilhar tela: ativo → encerra; inativo → delega a
  /// escolha ao navegador no Web, ao portal no Linux ou ao seletor de fontes
  /// do desktopCapturer no Windows.
  Future<void> _toggleScreenShare(BuildContext context, WidgetRef ref) async {
    final arg = (serverId: serverId, channelId: channelId);
    final notifier = ref.read(voiceControllerProvider(arg).notifier);
    final current = ref.read(voiceControllerProvider(arg));
    if (current.isScreenSharing) {
      await notifier.stopScreenShare();
      return;
    }
    final selection = await RtcScreenSharePicker.show(
      context,
      backend: ref.read(nativeMediaServicesProvider).screenShare,
    );
    if (selection == null) return;
    await notifier.startScreenShare(
      selection.sourceId,
      includeSystemAudio: current.includeSystemAudio,
    );
  }

  /// Abre o sheet de settings de câmera; ao abrir, atualiza a lista de
  /// dispositivos (best-effort — falha de enumeração mantém o cache).
  Future<void> _openCameraSettings(
    BuildContext context,
    WidgetRef ref,
    ({String serverId, String channelId}) arg,
  ) async {
    unawaited(
      ref.read(voiceControllerProvider(arg).notifier).refreshCameraDevices(),
    );
    final rtc = ref.read(rtcServiceProvider);
    try {
      await showModalBottomSheet<void>(
        context: context,
        builder: (_) => _CameraSettingsSheet(arg: arg),
      );
    } finally {
      // Idempotente: só para a track de preview temporária. Uma câmera já
      // publicada continua transmitindo normalmente depois de fechar o sheet.
      await rtc.stopCameraPreview();
    }
  }

  /// Abre o sheet de qualidade do screen share. Não precisa de
  /// refresh — o estado do perfil já vive no controller.
  void _openScreenShareQuality(
    BuildContext context,
    WidgetRef ref,
    ({String serverId, String channelId}) arg,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => _ScreenShareQualitySheet(arg: arg),
    );
  }
}

/// Banner de reconexão automática do serviço: aparece com o
/// [ReconnectingEvent] e some no [ReconnectedEvent]. A sessão continua
/// `connected` — nenhum ramo de erro/idle é acionado; o banner é o ÚNICO
/// efeito visível durante a reconexão.
class _ReconnectingBanner extends StatelessWidget {
  const _ReconnectingBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.tertiaryContainer,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            'Reconectando…',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onTertiaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

/// Banner de áudio BLOQUEADO pelo browser (autoplay policy no web): o
/// playback remoto não toca até um gesto do usuário. O toque no banner
/// chama [VoiceController.resumeAudio] (que pede ao serviço `startAudio`).
/// Só aparece no web; desktop nunca emite [AudioPlaybackBlockedEvent].
class _AudioBlockedBanner extends StatelessWidget {
  const _AudioBlockedBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.errorContainer,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.volume_off,
                size: 18,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Áudio bloqueado pelo navegador — toque para ativar',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
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

class _ParticipantsPanel extends StatelessWidget {
  const _ParticipantsPanel({
    required this.state,
    required this.notifier,
    required this.arg,
  });

  final VoiceState state;
  final VoiceController notifier;
  final ({String serverId, String channelId}) arg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (state.status) {
      case VoiceSessionStatus.connecting:
        return const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        );
      case VoiceSessionStatus.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 40,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text(
                  state.errorMessage ?? 'Falha ao conectar.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        );
      case VoiceSessionStatus.idle:
        return Center(
          child: Text(
            'Você ainda não está neste canal de voz.\n'
            'Use o botão abaixo para entrar.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        );
      case VoiceSessionStatus.connected:
        if (state.spotlightParticipantId == null) {
          return ColoredBox(
            color: Colors.black,
            child: _VideoGrid(state: state, notifier: notifier, arg: arg),
          );
        }
        return ColoredBox(
          color: Colors.black,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 108),
            child: _SpotlightLayout(state: state, notifier: notifier, arg: arg),
          ),
        );
    }
  }
}

/// Resultado puro do cálculo do grid, exposto para validar diferentes
/// tamanhos de janela sem precisar abrir uma sessão RTC.
class VoiceGridGeometry {
  const VoiceGridGeometry({
    required this.columns,
    required this.rows,
    required this.tileSize,
    required this.gridSize,
  });

  final int columns;
  final int rows;
  final Size tileSize;
  final Size gridSize;
}

/// Escolhe a combinação de linhas/colunas que produz o maior tile 16:9
/// possível no espaço disponível. O mesmo cálculo atende câmeras, avatares e
/// compartilhamentos — não existe um layout especial que esconda os shares.
VoiceGridGeometry calculateVoiceGridGeometry({
  required Size viewport,
  required int tileCount,
  double gap = 10,
  double aspectRatio = 16 / 9,
  int maxColumns = 5,
}) {
  assert(tileCount > 0);
  final width = math.max(1.0, viewport.width);
  final height = math.max(1.0, viewport.height);
  VoiceGridGeometry? best;
  var bestArea = -1.0;
  var bestEmptySlots = tileCount;

  for (var columns = 1; columns <= math.min(tileCount, maxColumns); columns++) {
    final rows = (tileCount / columns).ceil();
    final widthPerTile = (width - gap * (columns - 1)) / columns;
    final heightPerTile = (height - gap * (rows - 1)) / rows;
    if (widthPerTile <= 0 || heightPerTile <= 0) continue;

    final maxTileWidth = tileCount == 1 ? 960.0 : 720.0;
    final tileWidth = math.min(
      maxTileWidth,
      math.min(widthPerTile, heightPerTile * aspectRatio),
    );
    final tileHeight = tileWidth / aspectRatio;
    final area = tileWidth * tileHeight;
    final emptySlots = rows * columns - tileCount;
    final isBetter =
        area > bestArea + 0.5 ||
        ((area - bestArea).abs() <= 0.5 && emptySlots < bestEmptySlots);
    if (!isBetter) continue;

    bestArea = area;
    bestEmptySlots = emptySlots;
    best = VoiceGridGeometry(
      columns: columns,
      rows: rows,
      tileSize: Size(tileWidth, tileHeight),
      gridSize: Size(
        columns * tileWidth + (columns - 1) * gap,
        rows * tileHeight + (rows - 1) * gap,
      ),
    );
  }

  return best ??
      VoiceGridGeometry(
        columns: 1,
        rows: tileCount,
        tileSize: const Size(1, 1),
        gridSize: Size(1, tileCount.toDouble()),
      );
}

class _VoiceMediaItem {
  const _VoiceMediaItem({required this.participant, required this.source});

  final RtcParticipant participant;
  final VoiceVideoSource source;

  String get key => '${participant.id}:${source.name}';
}

List<_VoiceMediaItem> _mediaItems(List<RtcParticipant> participants) {
  final shares = <_VoiceMediaItem>[];
  final people = <_VoiceMediaItem>[];
  for (final participant in participants) {
    if (participant.isScreenSharing) {
      shares.add(
        _VoiceMediaItem(
          participant: participant,
          source: VoiceVideoSource.screen,
        ),
      );
    }
    if (participant.isCameraEnabled) {
      people.add(
        _VoiceMediaItem(
          participant: participant,
          source: VoiceVideoSource.camera,
        ),
      );
    } else if (!participant.isScreenSharing) {
      people.add(
        _VoiceMediaItem(
          participant: participant,
          source: VoiceVideoSource.avatar,
        ),
      );
    }
  }
  // Compartilhamentos ficam visíveis primeiro, porém usam exatamente o
  // mesmo tamanho e componente das câmeras.
  return [...shares, ...people];
}

VoiceSpotlightSource _spotlightSource(VoiceVideoSource source) {
  return source == VoiceVideoSource.screen
      ? VoiceSpotlightSource.screen
      : VoiceSpotlightSource.camera;
}

/// Palco em grade: uma pessoa pode contribuir com dois tiles irmãos (tela e
/// câmera); participantes sem vídeo continuam presentes através do avatar.
class _VideoGrid extends StatelessWidget {
  const _VideoGrid({
    required this.state,
    required this.notifier,
    required this.arg,
  });

  final VoiceState state;
  final VoiceController notifier;
  final ({String serverId, String channelId}) arg;

  @override
  Widget build(BuildContext context) {
    final items = _mediaItems(state.participants);
    if (items.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        const horizontalPadding = 20.0;
        const topPadding = 14.0;
        const bottomControlsInset = 104.0;
        final availableSize = Size(
          math.max(1.0, constraints.maxWidth - horizontalPadding * 2),
          math.max(
            1.0,
            constraints.maxHeight - topPadding - bottomControlsInset,
          ),
        );
        final geometry = calculateVoiceGridGeometry(
          viewport: availableSize,
          tileCount: items.length,
          gap: gap,
        );

        return Padding(
          padding: const EdgeInsets.fromLTRB(
            horizontalPadding,
            topPadding,
            horizontalPadding,
            bottomControlsInset,
          ),
          child: Center(
            child: SizedBox(
              width: geometry.gridSize.width,
              height: geometry.gridSize.height,
              child: Wrap(
                alignment: WrapAlignment.center,
                runAlignment: WrapAlignment.center,
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final item in items)
                    SizedBox(
                      key: ValueKey(item.key),
                      width: geometry.tileSize.width,
                      height: geometry.tileSize.height,
                      child: VoiceVideoTile(
                        arg: arg,
                        participant: item.participant,
                        source: item.source,
                        role: VoiceVideoTileRole.grid,
                        onTap: item.source == VoiceVideoSource.avatar
                            ? null
                            : () => notifier.toggleSpotlight(
                                item.participant.id,
                                source: _spotlightSource(item.source),
                              ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Destaque opcional com todas as outras publicações na mesma faixa de
/// miniaturas. Câmera e tela da mesma pessoa continuam sendo itens distintos.
class _SpotlightLayout extends StatelessWidget {
  const _SpotlightLayout({
    required this.state,
    required this.notifier,
    required this.arg,
  });

  final VoiceState state;
  final VoiceController notifier;
  final ({String serverId, String channelId}) arg;

  @override
  Widget build(BuildContext context) {
    final items = _mediaItems(state.participants);
    final spotlightId = state.spotlightParticipantId;
    final spotlightSource = state.spotlightSource;
    _VoiceMediaItem? focused;
    for (final item in items) {
      final sourceMatches = switch (spotlightSource) {
        VoiceSpotlightSource.camera => item.source == VoiceVideoSource.camera,
        VoiceSpotlightSource.screen => item.source == VoiceVideoSource.screen,
        null => item.source != VoiceVideoSource.avatar,
      };
      if (item.participant.id == spotlightId && sourceMatches) {
        focused = item;
        break;
      }
    }
    if (focused == null) {
      return _VideoGrid(state: state, notifier: notifier, arg: arg);
    }
    final selected = focused;
    final others = [
      for (final item in items)
        if (item.key != selected.key) item,
    ];

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: VoiceVideoTile(
              arg: arg,
              participant: selected.participant,
              source: selected.source,
              role: VoiceVideoTileRole.spotlight,
              onTap: () => notifier.toggleSpotlight(
                selected.participant.id,
                source: _spotlightSource(selected.source),
              ),
            ),
          ),
        ),
        if (others.isNotEmpty)
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: others.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = others[index];
                return Center(
                  child: SizedBox(
                    width: 128,
                    height: 72,
                    child: VoiceVideoTile(
                      arg: arg,
                      participant: item.participant,
                      source: item.source,
                      role: VoiceVideoTileRole.miniature,
                      onTap: item.source == VoiceVideoSource.avatar
                          ? null
                          : () => notifier.toggleSpotlight(
                              item.participant.id,
                              source: _spotlightSource(item.source),
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.state,
    required this.onJoin,
    required this.onLeave,
    required this.onToggleMicrophone,
    required this.onToggleCamera,
    required this.onToggleScreenShare,
    required this.onToggleSystemAudio,
    required this.onOpenSettings,
    required this.onOpenQuality,
  });

  final VoiceState state;
  final VoidCallback onJoin;
  final VoidCallback onLeave;
  final VoidCallback onToggleMicrophone;
  final VoidCallback onToggleCamera;
  final VoidCallback onToggleScreenShare;
  final VoidCallback onToggleSystemAudio;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenQuality;

  @override
  Widget build(BuildContext context) {
    final connected = state.status == VoiceSessionStatus.connected;
    final connecting = state.status == VoiceSessionStatus.connecting;
    if (!connected) {
      if (!connecting && state.status == VoiceSessionStatus.idle) {
        return const SizedBox.shrink();
      }
      return FilledButton.icon(
        onPressed: connecting ? null : onJoin,
        icon: connecting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.headset),
        label: Text(connecting ? 'Conectando…' : 'Tentar novamente'),
      );
    }

    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTokens.surfaceGlass,
          borderRadius: AppRadius.brFull,
          border: Border.all(color: AppTokens.borderSubtle),
          boxShadow: AppShadows.popover,
        ),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            _mediaToggleButton(
              theme: theme,
              icon: state.isMicrophoneEnabled ? Icons.mic : Icons.mic_off,
              active: state.isMicrophoneEnabled,
              activeColor: theme.colorScheme.primary,
              tooltip: state.isMicrophoneEnabled
                  ? 'Desativar microfone'
                  : 'Ativar microfone',
              onPressed: onToggleMicrophone,
            ),
            _mediaToggleButton(
              theme: theme,
              icon: state.isCameraEnabled ? Icons.videocam : Icons.videocam_off,
              active: state.isCameraEnabled,
              activeColor: AppTokens.accentGreen,
              tooltip: state.isCameraEnabled
                  ? 'Desativar câmera'
                  : 'Ativar câmera',
              onPressed: onToggleCamera,
            ),
            _mediaToggleButton(
              theme: theme,
              icon: Icons.present_to_all,
              active: state.isScreenSharing,
              activeColor: AppTokens.accentPurple,
              tooltip: state.isScreenSharing
                  ? 'Parar compartilhamento'
                  : 'Compartilhar tela',
              onPressed: state.isReconnecting ? null : onToggleScreenShare,
            ),
            PopupMenuButton<String>(
              tooltip: 'Mais opções de voz',
              icon: const Icon(Icons.more_horiz),
              onSelected: (value) {
                switch (value) {
                  case 'quality':
                    onOpenQuality();
                    break;
                  case 'settings':
                    onOpenSettings();
                    break;
                  case 'systemAudio':
                    onToggleSystemAudio();
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'quality',
                  child: Row(
                    children: const [
                      Icon(Icons.hd),
                      SizedBox(width: 12),
                      Text('Qualidade de transmissão'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'settings',
                  child: Row(
                    children: const [
                      Icon(Icons.settings),
                      SizedBox(width: 12),
                      Text('Configurações de câmera'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'systemAudio',
                  enabled: !state.isScreenSharing && !state.isReconnecting,
                  child: Row(
                    children: [
                      Icon(
                        state.includeSystemAudio
                            ? Icons.volume_up
                            : Icons.volume_off,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        state.includeSystemAudio
                            ? 'Áudio de sistema: ligado'
                            : 'Áudio de sistema: desligado',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            IconButton(
              onPressed: onLeave,
              tooltip: 'Sair do canal de voz',
              style: IconButton.styleFrom(
                minimumSize: const Size.square(48),
                backgroundColor: AppTokens.accentPurple,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.call_end),
            ),
          ],
        ),
      ),
    );
  }

  /// Botão circular de mídia: o dock usa o mesmo controle em qualquer
  /// largura, quebrando linhas só quando a janela fica estreita.
  Widget _mediaToggleButton({
    required ThemeData theme,
    required IconData icon,
    required bool active,
    required Color activeColor,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return IconButton.filledTonal(
      onPressed: onPressed,
      tooltip: tooltip,
      style: IconButton.styleFrom(minimumSize: const Size.square(48)),
      icon: Icon(
        icon,
        color: active ? activeColor : theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Sheet de settings de câmera: abre uma captura LOCAL e temporária para o
/// preview, sem publicar vídeo na sala. A track é liberada pelo método que
/// abriu o modal; este state só controla loading, erro e renderização.
class _CameraSettingsSheet extends ConsumerStatefulWidget {
  const _CameraSettingsSheet({required this.arg});

  final ({String serverId, String channelId}) arg;

  @override
  ConsumerState<_CameraSettingsSheet> createState() =>
      _CameraSettingsSheetState();
}

class _CameraSettingsSheetState extends ConsumerState<_CameraSettingsSheet> {
  RtcVideoTrackRef? _previewTrack;
  bool _loadingPreview = true;
  bool _selectingCamera = false;
  String? _previewError;

  @override
  void initState() {
    super.initState();
    // Não inicie getUserMedia no mesmo ciclo que monta o bottom sheet: o
    // plugin pode demorar para abrir a webcam. Deixar o primeiro frame passar
    // garante que o usuário veja o spinner imediatamente.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_startPreviewAfterFirstFrame());
    });
  }

  Future<void> _startPreviewAfterFirstFrame() async {
    // Cede também a próxima volta do event loop para o frame do modal ser
    // apresentado pelo compositor antes da inicialização nativa da câmera.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await _startPreview();
  }

  Future<void> _startPreview() async {
    final selectedCameraId = ref
        .read(voiceControllerProvider(widget.arg))
        .selectedCameraId;
    if (mounted) {
      setState(() {
        _loadingPreview = true;
        _previewError = null;
      });
    }
    try {
      final track = await ref
          .read(rtcServiceProvider)
          .startCameraPreview(deviceId: selectedCameraId);
      if (!mounted) return;
      setState(() {
        _previewTrack = track;
        _loadingPreview = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _previewTrack = null;
        _loadingPreview = false;
        _previewError = 'Não foi possível iniciar o preview da câmera.';
      });
    }
  }

  Future<void> _selectCamera(VoiceController notifier, String deviceId) async {
    setState(() => _selectingCamera = true);
    final changed = await notifier.selectCamera(deviceId);
    if (!mounted) return;
    setState(() {
      _selectingCamera = false;
      if (!changed) {
        _previewError = 'Não foi possível trocar a câmera selecionada.';
      } else {
        _previewError = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(voiceControllerProvider(widget.arg));
    final notifier = ref.read(voiceControllerProvider(widget.arg).notifier);
    final devices = state.cameraDevices;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Câmera', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CameraPreviewSurface(
                      trackRef: _previewTrack,
                      loading: _loadingPreview,
                      error: _previewError,
                      onRetry: _loadingPreview ? null : _startPreview,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Este preview é visível apenas para você. Ative a câmera nos '
              'controles da chamada para transmitir aos participantes.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            if (devices.isEmpty)
              Text(
                'Nenhuma câmera encontrada.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              )
            else
              RadioGroup<String>(
                groupValue: state.selectedCameraId,
                onChanged: (id) {
                  if (_selectingCamera || id == null) return;
                  unawaited(_selectCamera(notifier, id));
                },
                child: Column(
                  children: [
                    for (var i = 0; i < devices.length; i++)
                      RadioListTile<String>(
                        value: devices[i].id,
                        // Label pode vir vazio antes da permissão (fato do
                        // contrato) — fallback numerado.
                        title: Text(
                          devices[i].label.isEmpty
                              ? 'Câmera ${i + 1}'
                              : devices[i].label,
                        ),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Superfície compartilhável do preview, exposta para manter o estado de
/// loading verificável sem precisar abrir uma sessão LiveKit em widget tests.
class CameraPreviewSurface extends StatelessWidget {
  const CameraPreviewSurface({
    super.key,
    required this.trackRef,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final RtcVideoTrackRef? trackRef;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (trackRef != null) RtcVideoView(trackRef: trackRef),
          if (!loading && trackRef == null)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.videocam_off,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        error!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                  if (onRetry != null) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: onRetry,
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ],
              ),
            ),
          if (loading)
            const ColoredBox(
              color: Color(0x66000000),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Rótulo PT-BR de cada perfil de screen share, com `Auto` no topo.
const Map<RtcScreenShareQuality, String> _screenShareQualityLabels = {
  RtcScreenShareQuality.auto: 'Auto',
  RtcScreenShareQuality.q1080p60: '1080p60',
  RtcScreenShareQuality.q1080p30: '1080p30',
  RtcScreenShareQuality.q1080p15: '1080p15',
  RtcScreenShareQuality.q720p15: '720p15',
  RtcScreenShareQuality.q360p3: '360p3',
};

/// Sheet de qualidade de screen share: lista vertical de perfis de publicação
/// com `Auto` no topo. A escolha é pendente ou aplicada ao vivo conforme o
/// estado do compartilhamento atual.
class _ScreenShareQualitySheet extends ConsumerWidget {
  const _ScreenShareQualitySheet({required this.arg});

  final ({String serverId, String channelId}) arg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(voiceControllerProvider(arg));
    final notifier = ref.read(voiceControllerProvider(arg).notifier);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Qualidade de transmissão',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              state.isScreenSharing
                  ? 'Aplica ao vivo no compartilhamento atual.'
                  : 'Aplica no próximo compartilhamento.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            RadioGroup<RtcScreenShareQuality>(
              groupValue: state.screenShareQuality,
              onChanged: (quality) {
                if (quality != null) notifier.setScreenShareQuality(quality);
              },
              child: Column(
                children: [
                  for (final entry in _screenShareQualityLabels.entries)
                    RadioListTile<RtcScreenShareQuality>(
                      value: entry.key,
                      title: Text(entry.value),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
