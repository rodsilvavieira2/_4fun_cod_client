import 'dart:async';

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

    return Column(
      children: [
        _Header(channelName: channelName, status: state.status),
        const Divider(height: 1),
        // Banner de reconexão automática: a sessão continua `connected` — o
        // serviço está restabelecendo; o painel abaixo segue o ramo normal
        // (participantes esvaziam e a lista mostra o estado transitório).
        if (state.isReconnecting &&
            state.status == VoiceSessionStatus.connected)
          const _ReconnectingBanner(),
        // Áudio remoto bloqueado pelo browser (autoplay policy no web):
        // banner tocável que chama resumeAudio num gesto do usuário.
        if (state.isAudioBlocked &&
            state.status == VoiceSessionStatus.connected)
          _AudioBlockedBanner(onTap: notifier.resumeAudio),
        Expanded(
          child: _ParticipantsPanel(state: state, notifier: notifier, arg: arg),
        ),
        const Divider(height: 1),
        _Controls(
          state: state,
          onJoin: notifier.join,
          onLeave: notifier.leave,
          onToggleMicrophone: notifier.toggleMicrophone,
          onToggleCamera: notifier.toggleCamera,
          onToggleScreenShare: () => _toggleScreenShare(context, ref),
          onToggleSystemAudio: notifier.toggleIncludeSystemAudio,
          onOpenSettings: () => _openCameraSettings(context, ref, arg),
          onOpenQuality: () => _openScreenShareQuality(context, ref, arg),
        ),
        // Corrige o tom da barra inferior sobre o surface do tema.
        const SizedBox(height: 4),
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
    final selection = await RtcScreenSharePicker.show(context);
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

class _Header extends StatelessWidget {
  const _Header({required this.channelName, required this.status});

  final String channelName;
  final VoiceSessionStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusLabel = switch (status) {
      VoiceSessionStatus.idle => 'Fora do canal de voz',
      VoiceSessionStatus.connecting => 'Conectando…',
      VoiceSessionStatus.connected => 'Em voz',
      VoiceSessionStatus.error => 'Falha na conexão',
    };
    final statusColor = switch (status) {
      VoiceSessionStatus.connected => theme.colorScheme.primary,
      VoiceSessionStatus.error => theme.colorScheme.error,
      _ => theme.colorScheme.outline,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          const Icon(Icons.headset, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '#$channelName',
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            statusLabel,
            style: theme.textTheme.bodySmall?.copyWith(color: statusColor),
          ),
        ],
      ),
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
        // Com ≥1 câmera OU tela ativa o painel vira canal de MÍDIA
        // (grid/spotlight); sem nenhuma mantém a lista da Fase 4 intacta.
        final hasMedia = state.participants.any(
          (p) => p.isCameraEnabled || p.isScreenSharing,
        );
        if (!hasMedia) {
          return _ParticipantList(participants: state.participants);
        }
        if (state.spotlightParticipantId == null) {
          return _VideoGrid(state: state, notifier: notifier, arg: arg);
        }
        return _SpotlightLayout(state: state, notifier: notifier, arg: arg);
    }
  }
}

/// GRID de tiles de vídeo (modo mídia): um tile por participante, colunas
/// responsivas pela largura do painel (≥900 → 3, ≥560 → 2, senão 1).
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 900 ? 3 : (width >= 560 ? 2 : 1);
        return GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 16 / 9,
          ),
          itemCount: state.participants.length,
          itemBuilder: (context, index) {
            final participant = state.participants[index];
            // Só tile COM vídeo (câmera ou tela) vira spotlight (toque
            // ignorado sem).
            return VoiceVideoTile(
              arg: arg,
              participant: participant,
              role: VoiceVideoTileRole.grid,
              onTap: participant.isCameraEnabled || participant.isScreenSharing
                  ? () => notifier.toggleSpotlight(participant.id)
                  : null,
            );
          },
        );
      },
    );
  }
}

/// SPOTLIGHT: tile em destaque (Expanded) + faixa de miniaturas dos demais.
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
    final spotlightId = state.spotlightParticipantId;

    // Defensivo: o controller já limpa destaque órfão no snapshot; ainda
    // assim, se não houver destaque válido, cai no grid.
    RtcParticipant? spotlight;
    for (final p in state.participants) {
      if (p.id == spotlightId && (p.isCameraEnabled || p.isScreenSharing)) {
        spotlight = p;
        break;
      }
    }
    if (spotlight == null) {
      return _VideoGrid(state: state, notifier: notifier, arg: arg);
    }
    // Promoção definitiva para o closure (variável mutável não promove
    // dentro de closure).
    final focused = spotlight;

    final others = [
      for (final p in state.participants)
        if (p.id != focused.id) p,
    ];

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: VoiceVideoTile(
              arg: arg,
              participant: focused,
              role: VoiceVideoTileRole.spotlight,
              // Toque no destaque → volta ao grid.
              onTap: () => notifier.toggleSpotlight(focused.id),
            ),
          ),
        ),
        if (others.isNotEmpty)
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final p in others)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Center(
                      // Miniatura 16:9 (~128×72), centralizada na faixa.
                      child: SizedBox(
                        width: 128,
                        height: 72,
                        child: VoiceVideoTile(
                          arg: arg,
                          participant: p,
                          role: VoiceVideoTileRole.miniature,
                          onTap: p.isCameraEnabled || p.isScreenSharing
                              ? () => notifier.toggleSpotlight(p.id)
                              : null,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _ParticipantList extends StatelessWidget {
  const _ParticipantList({required this.participants});

  final List<RtcParticipant> participants;

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) {
      return Center(
        child: Text(
          'Ninguém mais está aqui.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: participants.length,
      itemBuilder: (context, index) =>
          _ParticipantTile(participant: participants[index]),
    );
  }
}

class _ParticipantTile extends ConsumerWidget {
  const _ParticipantTile({required this.participant});

  final RtcParticipant participant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isLocal =
        participant.id == ref.read(rtcServiceProvider).localParticipantId;
    final name = participant.name;
    return ListTile(
      dense: true,
      // Active speaker: fundo destacado (highlight de fala).
      tileColor: participant.isSpeaking
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
          : null,
      leading: CircleAvatar(
        radius: 16,
        child: Text(
          name.isEmpty ? '?' : name[0].toUpperCase(),
          style: const TextStyle(fontSize: 13),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: participant.isSpeaking
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          ),
          if (isLocal) ...[const SizedBox(width: 6), const _LocalBadge()],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (participant.isSpeaking)
            Icon(Icons.graphic_eq, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Icon(
            participant.isCameraEnabled ? Icons.videocam : Icons.videocam_off,
            size: 18,
            color: participant.isCameraEnabled
                ? AppTokens.accentGreen
                : AppTokens.textMuted,
          ),
          const SizedBox(width: 10),
          Icon(
            participant.isMicrophoneEnabled ? Icons.mic : Icons.mic_off,
            size: 18,
            color: participant.isMicrophoneEnabled
                ? AppTokens.accentGreen
                : AppTokens.accentPurple,
          ),
        ],
      ),
    );
  }
}

class _LocalBadge extends StatelessWidget {
  const _LocalBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Você',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
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

  /// Abaixo desta largura a barra usa o padrão compacto (Discord mobile):
  /// botões circulares + sair grande central + menu ⋮ para o restante.
  static const double _compactBreakpoint = 520;

  @override
  Widget build(BuildContext context) {
    final connected = state.status == VoiceSessionStatus.connected;
    final connecting = state.status == VoiceSessionStatus.connecting;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!connected) {
            return FilledButton.icon(
              onPressed: connecting ? null : onJoin,
              icon: connecting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.headset),
              label: Text(connecting ? 'Conectando…' : 'Entrar'),
            );
          }
          if (constraints.maxWidth < _compactBreakpoint) {
            return _buildCompactControls(context);
          }
          return _buildWideControls(context);
        },
      ),
    );
  }

  /// Controles largos (≥520px, desktop/tablet): botão de sair expandido +
  /// todos os ícones inline — visual original inalterado.
  Widget _buildWideControls(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: onLeave,
            icon: const Icon(Icons.call_end),
            label: const Text('Sair do canal de voz'),
          ),
        ),
        const SizedBox(width: 8),
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
        const SizedBox(width: 8),
        _mediaToggleButton(
          theme: theme,
          icon: state.isCameraEnabled ? Icons.videocam : Icons.videocam_off,
          active: state.isCameraEnabled,
          activeColor: theme.colorScheme.error,
          tooltip: state.isCameraEnabled ? 'Desativar câmera' : 'Ativar câmera',
          onPressed: onToggleCamera,
        ),
        const SizedBox(width: 8),
        _mediaToggleButton(
          theme: theme,
          icon: Icons.present_to_all,
          active: state.isScreenSharing,
          activeColor: theme.colorScheme.error,
          tooltip: state.isScreenSharing
              ? 'Parar compartilhamento'
              : 'Compartilhar tela',
          onPressed: state.isReconnecting ? null : onToggleScreenShare,
        ),
        const SizedBox(width: 8),
        // Áudio de sistema (Fase 6.1): preferência do PRÓXIMO share.
        // Desabilitado com share ativo — a decisão é lida apenas no start.
        // Com share ativo o ícone reflete o estado REAL (isSystemAudioEnabled
        // — pode ter falhado a publicação); sem share, a preferência.
        _mediaToggleButton(
          theme: theme,
          icon:
              (state.isScreenSharing
                  ? state.isSystemAudioEnabled
                  : state.includeSystemAudio)
              ? Icons.volume_up
              : Icons.volume_off,
          active: state.isScreenSharing
              ? state.isSystemAudioEnabled
              : state.includeSystemAudio,
          activeColor: theme.colorScheme.primary,
          tooltip: state.isScreenSharing
              ? (state.isSystemAudioEnabled
                    ? 'Transmitindo áudio de sistema'
                    : 'Sem áudio de sistema neste compartilhamento')
              : (state.includeSystemAudio
                    ? 'Áudio de sistema no próximo compartilhamento'
                    : 'Incluir áudio de sistema no compartilhamento'),
          onPressed: state.isScreenSharing || state.isReconnecting
              ? null
              : onToggleSystemAudio,
        ),
        const SizedBox(width: 4),
        // Qualidade do screen share: botão sempre visível; sem share a
        // escolha fica pendente para o próximo compartilhamento.
        IconButton(
          onPressed: onOpenQuality,
          tooltip: 'Qualidade de transmissão',
          icon: Icon(
            Icons.hd,
            color: state.screenShareQuality != RtcScreenShareQuality.auto
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: onOpenSettings,
          tooltip: 'Configurações de câmera',
          icon: const Icon(Icons.settings),
        ),
      ],
    );
  }

  /// Controles compactos (<520px, mobile): botões circulares de mídia +
  /// botão de sair GRANDE central (padrão de call) + menu ⋮ com qualidade e
  /// settings — nada estoura na largura de um celular.
  Widget _buildCompactControls(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
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
        const SizedBox(width: 12),
        _mediaToggleButton(
          theme: theme,
          icon: state.isCameraEnabled ? Icons.videocam : Icons.videocam_off,
          active: state.isCameraEnabled,
          activeColor: theme.colorScheme.error,
          tooltip: state.isCameraEnabled ? 'Desativar câmera' : 'Ativar câmera',
          onPressed: onToggleCamera,
        ),
        const SizedBox(width: 12),
        IconButton(
          onPressed: onLeave,
          iconSize: 30,
          padding: const EdgeInsets.all(16),
          tooltip: 'Sair do canal de voz',
          style: IconButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          icon: const Icon(Icons.call_end),
        ),
        const SizedBox(width: 12),
        _mediaToggleButton(
          theme: theme,
          icon: Icons.present_to_all,
          active: state.isScreenSharing,
          activeColor: theme.colorScheme.error,
          tooltip: state.isScreenSharing
              ? 'Parar compartilhamento'
              : 'Compartilhar tela',
          onPressed: state.isReconnecting ? null : onToggleScreenShare,
        ),
        const SizedBox(width: 12),
        IconButton(
          onPressed: onOpenQuality,
          tooltip: 'Qualidade de transmissão',
          icon: Icon(
            Icons.hd,
            color: state.screenShareQuality != RtcScreenShareQuality.auto
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 4),
        PopupMenuButton<String>(
          tooltip: 'Mais opções',
          icon: const Icon(Icons.more_vert),
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
          // Lista NÃO const: o item de áudio de sistema depende do estado
          // (os itens individuais continuam const).
          itemBuilder: (context) => [
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
              // Mesmas condições do botão wide: desabilitado com share ativo
              // ou reconexão (a decisão é lida apenas no start).
              enabled: !state.isScreenSharing && !state.isReconnecting,
              child: Row(
                children: [
                  Icon(
                    (state.isScreenSharing
                            ? state.isSystemAudioEnabled
                            : state.includeSystemAudio)
                        ? Icons.volume_up
                        : Icons.volume_off,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    state.isScreenSharing
                        ? (state.isSystemAudioEnabled
                              ? 'Áudio de sistema: transmitindo'
                              : 'Áudio de sistema: sem áudio')
                        : (state.includeSystemAudio
                              ? 'Áudio de sistema: ligado'
                              : 'Áudio de sistema: desligado'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Botão circular de mídia (mic/câmera/tela): filledTonal com ícone na cor
  /// ativa/inativa — mesmo padrão visual nos dois modos.
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
