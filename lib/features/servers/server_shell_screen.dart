import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/invite_dialog.dart';
import '../../core/ui/settings_modal.dart';
import '../../core/websocket/socket_service.dart';
import '../../shared/models/servers.dart';
import '../channels/channel_header.dart';
import '../channels/channel_list.dart';
import '../channels/channels_providers.dart';
import '../chat/chat_providers.dart';
import '../chat/chat_screen.dart';
import '../voice/voice_screen.dart';
import '../voice/voice_providers.dart';
import 'members_panel.dart';
import 'server_rail.dart';
import 'server_settings_modal.dart';
import 'servers_providers.dart';
import 'user_panel.dart';

/// Visão principal de um servidor (wireframe v3): rail + sidebar (canais +
/// user panel) + conteúdo do canal selecionado + painel de membros
/// (desktop ≥800). Cores por coluna explícitas (`AppThemeColors`) — o tema
/// default não expõe 3 fundos distintos.
///
/// Ao abrir, faz `server:join` no socket (e `server:leave` ao sair); ao
/// selecionar canal de TEXTO, `channel:join`/`channel:leave` — o join é
/// reemitido automaticamente pelo [SocketService] após reconexão.
class ServerShellScreen extends ConsumerStatefulWidget {
  const ServerShellScreen({
    super.key,
    required this.serverId,
    this.initialChannelId,
  });

  final String serverId;
  final String? initialChannelId;

  @override
  ConsumerState<ServerShellScreen> createState() => _ServerShellScreenState();
}

class _ServerShellScreenState extends ConsumerState<ServerShellScreen> {
  String? _selectedChannelId;
  String? _activeVoiceChannelId;
  // Room de texto com `channel:join` ativo. Pode diferir da seleção visível:
  // ao ver voz, a room de texto permanece conectada (volta sem refetch).
  String? _joinedTextChannelId;
  String? _appliedInitialChannelId;
  int _voiceSwitchEpoch = 0;
  bool _didSelectInitialChannel = false;
  bool _leavingServer = false;

  /// Painel de membros lateral (desktop): oculto por padrão, alternável pela ação do header.
  bool _showMembers = false;

  /// Container capturado no initState: o `ref` do widget já está morto quando
  /// o `State.dispose` roda (`context.mounted == false` no unmount) — todo
  /// cleanup de saída (rooms + leave da voz) usa o container direto.
  late final ProviderContainer _container;

  @override
  void initState() {
    super.initState();
    _container = ProviderScope.containerOf(context, listen: false);
    // Pós-frame: o socket pode ainda não ter conectado; o estado de join é
    // registrado e reemitido no 'connect'.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(socketServiceProvider).joinServer(widget.serverId);
    });
  }

  @override
  void didUpdateWidget(covariant ServerShellScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialChannelId != widget.initialChannelId) {
      _appliedInitialChannelId = null;
    }
  }

  @override
  void dispose() {
    final socket = _container.read(socketServiceProvider);
    final channelId = _selectedChannelId;
    if (channelId != null) {
      socket.leaveChannel(channelId);
    }
    final joinedTextChannelId = _joinedTextChannelId;
    if (joinedTextChannelId != null && joinedTextChannelId != channelId) {
      socket.leaveChannel(joinedTextChannelId);
    }
    final activeVoiceChannelId = _activeVoiceChannelId;
    if (activeVoiceChannelId != null) {
      unawaited(
        _container
            .read(
              voiceControllerProvider((
                serverId: widget.serverId,
                channelId: activeVoiceChannelId,
              )).notifier,
            )
            .leave(),
      );
    }
    socket.leaveServer(widget.serverId);
    super.dispose();
  }

  Future<void> _onChannelSelected(
    String channelId,
    List<ServerChannel> channels,
  ) async {
    final channel = channels.where((c) => c.id == channelId).firstOrNull;
    if (channel == null) return;
    _didSelectInitialChannel = true;
    if (_selectedChannelId == channelId) {
      if (channel.type == ChannelType.voice) {
        if (_activeVoiceChannelId != channelId) {
          setState(() => _activeVoiceChannelId = channelId);
          // Pós-frame: o `watch` do provider só existe após o rebuild. Sem
          // isso, o join rodaria numa instância sem listeners que o
          // autoDispose descartaria (sala órfã — ver VoiceController.join).
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _activeVoiceChannelId != channelId) return;
            unawaited(
              ref
                  .read(
                    voiceControllerProvider((
                      serverId: widget.serverId,
                      channelId: channelId,
                    )).notifier,
                  )
                  .join(),
            );
          });
          return;
        }
        final controller = ref.read(
          voiceControllerProvider((
            serverId: widget.serverId,
            channelId: channelId,
          )).notifier,
        );
        final state = ref.read(
          voiceControllerProvider((
            serverId: widget.serverId,
            channelId: channelId,
          )),
        );
        if (state.status == VoiceSessionStatus.idle ||
            state.status == VoiceSessionStatus.error) {
          await controller.join();
        }
      }
      return;
    }
    final previous = _selectedChannelId;
    final socket = ref.read(socketServiceProvider);
    if (channel.type == ChannelType.text) {
      // Texto → outro texto: troca a room. Voz → texto: a sessão de voz
      // segue intacta (só pausa o vídeo local abaixo).
      if (previous != null) {
        socket.leaveChannel(previous);
      }
      final joined = _joinedTextChannelId;
      if (joined != null && joined != channelId) {
        socket.leaveChannel(joined);
      }
      setState(() {
        _selectedChannelId = channelId;
        _joinedTextChannelId = channelId;
      });
      socket.joinChannel(channelId);
      // Voz → texto: a sessão PERMANECE (spec voz-persistente); só a
      // câmera/tela LOCAL pausa. Remotos continuam recebidos e religar é
      // manual ao voltar à sala.
      unawaited(_pauseLocalVideoOnTextView());
      return;
    }
    // Texto → voz: a room de texto PERMANECE conectada e o ChatController
    // segue vivo (watch em `build`) — voltar ao texto é instantâneo, sem
    // refetch, com os eventos aplicados em segundo plano. Só a seleção
    // visível muda; a voz troca com leave-then-join abaixo.
    setState(() => _selectedChannelId = channelId);

    final previousVoiceChannelId = _activeVoiceChannelId;
    // Retorno à MESMA voz com sessão viva: só seleciona — sem leave, sem
    // token novo, sem rejoin (spec voz-persistente: a sessão se mantém até
    // encerrar explícito ou trocar de voz). Join só se a sessão caiu.
    if (previousVoiceChannelId == channelId) {
      setState(() => _activeVoiceChannelId = channelId);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _activeVoiceChannelId != channelId) return;
        final arg = (serverId: widget.serverId, channelId: channelId);
        final status = ref.read(voiceControllerProvider(arg)).status;
        if (status == VoiceSessionStatus.idle ||
            status == VoiceSessionStatus.error) {
          unawaited(ref.read(voiceControllerProvider(arg).notifier).join());
        }
      });
      return;
    }

    final epoch = ++_voiceSwitchEpoch;
    if (previousVoiceChannelId != null) {
      await ref
          .read(
            voiceControllerProvider((
              serverId: widget.serverId,
              channelId: previousVoiceChannelId,
            )).notifier,
          )
          .leave();
    }
    if (!mounted || epoch != _voiceSwitchEpoch) return;
    setState(() => _activeVoiceChannelId = channelId);
    // Pós-frame: o `watch` do provider só existe após o rebuild. Iniciar o
    // join aqui (só com `read`) deixaria o autoDispose sem listeners e a
    // instância seria descartada no frame seguinte, órfã da sala LiveKit.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _voiceSwitchEpoch) return;
      if (_activeVoiceChannelId != channelId) return;
      unawaited(
        ref
            .read(
              voiceControllerProvider((
                serverId: widget.serverId,
                channelId: channelId,
              )).notifier,
            )
            .join(),
      );
    });
  }

  void _leaveActiveVoice() {
    final channelId = _activeVoiceChannelId;
    if (channelId == null) return;
    ++_voiceSwitchEpoch;
    unawaited(
      ref
          .read(
            voiceControllerProvider((
              serverId: widget.serverId,
              channelId: channelId,
            )).notifier,
          )
          .leave(),
    );
    setState(() => _activeVoiceChannelId = null);
  }

  /// Pausa o vídeo LOCAL ao exibir um chat de texto com voz ativa: a sessão
  /// LiveKit continua (voz publica, remotos recebidos), só câmera e tela
  /// locais param. Idempotente — só age sobre o que está ligado — e nunca
  /// religa nada sozinho (retorno à sala é manual, privacy-safe).
  Future<void> _pauseLocalVideoOnTextView() async {
    final voiceId = _activeVoiceChannelId;
    if (voiceId == null) return;
    final arg = (serverId: widget.serverId, channelId: voiceId);
    final controller = ref.read(voiceControllerProvider(arg).notifier);
    final state = ref.read(voiceControllerProvider(arg));
    if (state.status != VoiceSessionStatus.connected) return;
    if (state.isCameraEnabled) {
      await controller.toggleCamera();
    }
    if (!mounted) return;
    final afterCamera = ref.read(voiceControllerProvider(arg));
    if (afterCamera.status == VoiceSessionStatus.connected &&
        afterCamera.isScreenSharing) {
      await controller.stopScreenShare();
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(serverDetailProvider(widget.serverId));
    final channels = ref.watch(channelsControllerProvider(widget.serverId));
    final canManageServer =
        !detail.isLoading && (detail.valueOrNull?.canManageServer ?? false);
    final channelList = channels.valueOrNull ?? const <ServerChannel>[];
    final selectedChannel = channelList
        .where((c) => c.id == _selectedChannelId)
        .firstOrNull;
    final activeVoiceChannel = channelList
        .where((c) => c.id == _activeVoiceChannelId)
        .firstOrNull;
    final activeVoiceState = activeVoiceChannel == null
        ? null
        : ref.watch(
            voiceControllerProvider((
              serverId: widget.serverId,
              channelId: activeVoiceChannel.id,
            )),
          );

    final requestedChannelId = widget.initialChannelId;
    if (requestedChannelId != null &&
        requestedChannelId != _appliedInitialChannelId &&
        requestedChannelId != _selectedChannelId &&
        channels.hasValue) {
      final requestedChannel = channelList
          .where(
            (channel) =>
                channel.id == requestedChannelId &&
                channel.type == ChannelType.text,
          )
          .firstOrNull;
      if (requestedChannel != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _appliedInitialChannelId == requestedChannelId) {
            return;
          }
          _appliedInitialChannelId = requestedChannelId;
          unawaited(_onChannelSelected(requestedChannelId, channelList));
        });
      } else {
        _appliedInitialChannelId = requestedChannelId;
      }
    }

    // Como no Discord, abrir um servidor leva direto ao primeiro canal de
    // texto. Canais de voz nunca são conectados automaticamente.
    if (!_didSelectInitialChannel &&
        _selectedChannelId == null &&
        channels.hasValue &&
        (requestedChannelId == null ||
            requestedChannelId == _appliedInitialChannelId)) {
      final firstTextChannel = channelList
          .where((channel) => channel.type == ChannelType.text)
          .firstOrNull;
      if (firstTextChannel != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _selectedChannelId != null) return;
          _didSelectInitialChannel = true;
          setState(() {
            _selectedChannelId = firstTextChannel.id;
            _joinedTextChannelId = firstTextChannel.id;
          });
          ref.read(socketServiceProvider).joinChannel(firstTextChannel.id);
        });
      }
    }

    // Canal selecionado foi removido (owner deletou): sai do join e limpa a
    // seleção. O callback roda em pós-frame para não setState durante build.
    final removedId = _selectedChannelId;
    if (removedId != null && selectedChannel == null && channels.hasValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _selectedChannelId != removedId) return;
        ref.read(socketServiceProvider).leaveChannel(removedId);
        setState(() {
          _selectedChannelId = null;
          if (_joinedTextChannelId == removedId) _joinedTextChannelId = null;
        });
      });
    }

    // Room de texto em segundo plano removida (owner deletou enquanto a voz
    // estava em vista): sai do join e solta o keep-alive abaixo.
    final backgroundRemovedId = _joinedTextChannelId;
    if (backgroundRemovedId != null &&
        backgroundRemovedId != _selectedChannelId &&
        channels.hasValue &&
        channelList.where((c) => c.id == backgroundRemovedId).firstOrNull ==
            null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _joinedTextChannelId != backgroundRemovedId) return;
        ref.read(socketServiceProvider).leaveChannel(backgroundRemovedId);
        setState(() => _joinedTextChannelId = null);
      });
    }

    // Texto em segundo plano (vendo voz ou lista): mantém o ChatController
    // vivo para a volta ser instantânea, sem refetch — os eventos realtime
    // seguem aplicados porque a room continua conectada.
    final backgroundTextId = selectedChannel?.type == ChannelType.text
        ? null
        : _joinedTextChannelId;
    if (backgroundTextId != null) {
      ref.watch(
        chatControllerProvider((
          serverId: widget.serverId,
          channelId: backgroundTextId,
        )),
      );
    }

    // Layout responsivo pelo ESPAÇO disponível (skill flutter de layout) —
    // decisão por constraints.maxWidth, nunca por hardware/orientação.
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < AppLayout.compactBreakpoint;
        final canDockMembers =
            constraints.maxWidth >= AppLayout.auxiliaryPanelBreakpoint;
        // Mobile: com canal selecionado, o conteúdo ocupa a tela toda e o
        // header ganha o back para a lista de canais.
        final showContent = isNarrow && _selectedChannelId != null;
        return Scaffold(
          body: isNarrow
              ? (showContent
                    ? _channelContent(
                        context,
                        selectedChannel,
                        canManageServer: canManageServer,
                        onBack: () {
                          setState(() => _selectedChannelId = null);
                        },
                      )
                    : Row(
                        children: [
                          ServerRail(
                            selectedServerId: widget.serverId,
                            width: AppLayout.compactServerRailWidth,
                            compact: true,
                          ),
                          Expanded(
                            child: _channelListPanel(
                              context,
                              detail: detail,
                              canManageServer: canManageServer,
                              channelList: channelList,
                              activeVoiceChannel: activeVoiceChannel,
                              activeVoiceState: activeVoiceState,
                            ),
                          ),
                        ],
                      ))
              : _desktopBody(
                  context,
                  detail: detail,
                  canManageServer: canManageServer,
                  channelList: channelList,
                  selectedChannel: selectedChannel,
                  activeVoiceChannel: activeVoiceChannel,
                  activeVoiceState: activeVoiceState,
                  canDockMembers: canDockMembers,
                ),
        );
      },
    );
  }

  /// Layout desktop: rail + lista de canais fixa + conteúdo + membros.
  Widget _desktopBody(
    BuildContext context, {
    required AsyncValue<ServerDetail> detail,
    required bool canManageServer,
    required List<ServerChannel> channelList,
    required ServerChannel? selectedChannel,
    required ServerChannel? activeVoiceChannel,
    required VoiceState? activeVoiceState,
    required bool canDockMembers,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          // Bloco de navegação (rail + divisor + lista) como base do
          // overlay: o controller flutua sobre rail e canais (wireframe).
          width: AppLayout.serverRailWidth + 1 + AppLayout.navigationWidth,
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ServerRail(selectedServerId: widget.serverId),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: AppLayout.navigationWidth,
                    child: _channelListPanel(
                      context,
                      detail: detail,
                      canManageServer: canManageServer,
                      channelList: channelList,
                      activeVoiceChannel: activeVoiceChannel,
                      activeVoiceState: activeVoiceState,
                      floatingOverlayReserve: _floatingReserve(
                        activeVoiceChannel,
                        activeVoiceState,
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: _userPanel(activeVoiceChannel, activeVoiceState),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _channelContent(
            context,
            selectedChannel,
            canManageServer: canManageServer,
          ),
        ),
        if (_showMembers && canDockMembers) ...[
          const VerticalDivider(width: 1),
          MembersPanel(serverId: widget.serverId),
        ],
      ],
    );
  }

  /// Reserva de rolagem sob o card flutuante: cobre a altura do card
  /// (seção de voz + linha do usuário + margens) com folga, para o último
  /// canal nunca ficar escondido atrás do overlay.
  double _floatingReserve(
    ServerChannel? activeVoiceChannel,
    VoiceState? activeVoiceState,
  ) {
    final showVoiceActions =
        activeVoiceChannel != null &&
        activeVoiceState != null &&
        activeVoiceState.status != VoiceSessionStatus.idle;
    return showVoiceActions ? 176 : 96;
  }

  /// Controller da base da sidebar — flutuante no desktop (overlay),
  /// acoplado no mobile (rodapé da coluna).
  UserPanel _userPanel(
    ServerChannel? activeVoiceChannel,
    VoiceState? activeVoiceState, {
    bool floating = true,
  }) {
    return UserPanel(
      floating: floating,
      onOpenSettings: () => _openUserSettings(context),
      voiceArg: activeVoiceChannel == null
          ? null
          : (serverId: widget.serverId, channelId: activeVoiceChannel.id),
      voiceChannelName: activeVoiceChannel?.name,
      voiceState: activeVoiceState,
      onLeaveVoice: _leaveActiveVoice,
    );
  }

  /// Painel de canais: largura fixa no desktop, full-width no mobile.
  /// Rodapé = [UserPanel] (avatar + status + mic/fones/⚙️) — no desktop o
  /// painel flutua em overlay ([floatingOverlayReserve] != null) e a lista
  /// ganha reserva de rolagem; no mobile ele segue acoplado ao rodapé.
  Widget _channelListPanel(
    BuildContext context, {
    required AsyncValue<ServerDetail> detail,
    required bool canManageServer,
    required List<ServerChannel> channelList,
    required ServerChannel? activeVoiceChannel,
    required VoiceState? activeVoiceState,
    double? floatingOverlayReserve,
  }) {
    final colors = context.appColors;
    return Container(
      color: colors.surface1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: detail.when(
              loading: () => const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (error, _) => Center(
                child: IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Tentar novamente',
                  onPressed: () =>
                      ref.invalidate(serverDetailProvider(widget.serverId)),
                ),
              ),
              data: (serverDetail) => ChannelList(
                serverId: widget.serverId,
                canManageServer: canManageServer,
                canLeaveServer:
                    serverDetail.myRole != null &&
                    !serverDetail.myRole!.isOwner,
                selectedChannelId: _selectedChannelId,
                activeVoiceChannelId: activeVoiceChannel?.id,
                activeVoiceParticipants:
                    activeVoiceState?.participants ?? const [],
                listBottomPadding: floatingOverlayReserve ?? 8,
                onChannelSelected: (id) => _onChannelSelected(id, channelList),
                onOpenInvites: () =>
                    showInviteDialog(context, serverId: widget.serverId),
                onOpenMembers: () =>
                    context.push('/servers/${widget.serverId}/members'),
                onOpenSettings: canManageServer
                    ? () => _openServerSettings(context)
                    : null,
                onLeaveServer: () => unawaited(_leaveServer()),
              ),
            ),
          ),
          if (floatingOverlayReserve == null)
            _userPanel(activeVoiceChannel, activeVoiceState, floating: false),
        ],
      ),
    );
  }

  Widget _channelContent(
    BuildContext context,
    ServerChannel? selectedChannel, {
    required bool canManageServer,
    VoidCallback? onBack,
  }) {
    final channel = selectedChannel;
    final colors = context.appColors;
    return Container(
      color: colors.background,
      child: Column(
        children: [
          if (channel != null)
            ChannelHeader(
              channelName: channel.name,
              channelType: channel.type,
              onBack: onBack,
              onOpenMembers: () {
                final canDock =
                    MediaQuery.sizeOf(context).width >=
                    AppLayout.auxiliaryPanelBreakpoint;
                if (!canDock) {
                  context.push('/servers/${widget.serverId}/members');
                } else {
                  setState(() => _showMembers = !_showMembers);
                }
              },
              onOpenInvites: () =>
                  showInviteDialog(context, serverId: widget.serverId),
              onOpenSettings: canManageServer
                  ? () => _openServerSettings(context)
                  : null,
            ),
          Expanded(
            child: channel == null
                ? const _NoChannelSelected()
                : switch (channel.type) {
                    ChannelType.text => ChatScreen(
                      key: ValueKey(channel.id),
                      serverId: widget.serverId,
                      channelId: channel.id,
                      channelName: channel.name,
                    ),
                    ChannelType.voice => VoiceScreen(
                      key: ValueKey(channel.id),
                      serverId: widget.serverId,
                      channelId: channel.id,
                    ),
                  },
          ),
        ],
      ),
    );
  }

  void _openUserSettings(BuildContext context) {
    unawaited(showSettingsModal(context));
  }

  void _openServerSettings(BuildContext context) {
    unawaited(showServerSettingsModal(context, serverId: widget.serverId));
  }

  Future<void> _leaveServer() async {
    if (_leavingServer) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sair do servidor'),
        content: const Text('Você não fará mais parte deste servidor.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _leavingServer = true;
    try {
      await ref.read(serversProvider.notifier).leave(widget.serverId);
      ref.invalidate(serverDetailProvider(widget.serverId));
      ref.invalidate(channelsControllerProvider(widget.serverId));
      if (mounted) context.go('/');
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível sair do servidor.')),
        );
      }
    } finally {
      _leavingServer = false;
    }
  }
}

class _NoChannelSelected extends StatelessWidget {
  const _NoChannelSelected();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: const Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTokens.surface2,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Icon(
                    Icons.forum_outlined,
                    size: 30,
                    color: AppTokens.textSecondary,
                  ),
                ),
              ),
              SizedBox(height: 18),
              Text(
                'Escolha onde quer conversar',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.textPrimary,
                ),
              ),
              SizedBox(height: 7),
              Text(
                'Selecione um canal de texto ou entre em uma sala de voz pela barra lateral.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 13.5,
                  height: 1.45,
                  color: AppTokens.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
