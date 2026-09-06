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
  const ServerShellScreen({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<ServerShellScreen> createState() => _ServerShellScreenState();
}

class _ServerShellScreenState extends ConsumerState<ServerShellScreen> {
  String? _selectedChannelId;
  String? _activeVoiceChannelId;
  int _voiceSwitchEpoch = 0;
  bool _didSelectInitialChannel = false;
  bool _leavingServer = false;

  /// Painel de membros lateral (desktop): alternável pela ação do header.
  bool _showMembers = true;

  @override
  void initState() {
    super.initState();
    // Pós-frame: o socket pode ainda não ter conectado; o estado de join é
    // registrado e reemitido no 'connect'.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(socketServiceProvider).joinServer(widget.serverId);
    });
  }

  @override
  void dispose() {
    final socket = ref.read(socketServiceProvider);
    final channelId = _selectedChannelId;
    if (channelId != null) {
      socket.leaveChannel(channelId);
    }
    final activeVoiceChannelId = _activeVoiceChannelId;
    if (activeVoiceChannelId != null) {
      unawaited(
        ref
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
    if (previous != null) {
      socket.leaveChannel(previous);
    }
    setState(() => _selectedChannelId = channelId);
    if (channel.type == ChannelType.text) {
      socket.joinChannel(channelId);
      return;
    }

    final epoch = ++_voiceSwitchEpoch;
    final previousVoiceChannelId = _activeVoiceChannelId;
    if (previousVoiceChannelId != null && previousVoiceChannelId != channelId) {
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

    // Como no Discord, abrir um servidor leva direto ao primeiro canal de
    // texto. Canais de voz nunca são conectados automaticamente.
    if (!_didSelectInitialChannel &&
        _selectedChannelId == null &&
        channels.hasValue) {
      final firstTextChannel = channelList
          .where((channel) => channel.type == ChannelType.text)
          .firstOrNull;
      if (firstTextChannel != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _selectedChannelId != null) return;
          _didSelectInitialChannel = true;
          setState(() => _selectedChannelId = firstTextChannel.id);
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
        setState(() => _selectedChannelId = null);
      });
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

  /// Painel de canais: largura fixa no desktop, full-width no mobile.
  /// Rodapé = [UserPanel] (avatar + status + mic/fones/⚙️).
  Widget _channelListPanel(
    BuildContext context, {
    required AsyncValue<ServerDetail> detail,
    required bool canManageServer,
    required List<ServerChannel> channelList,
    required ServerChannel? activeVoiceChannel,
    required VoiceState? activeVoiceState,
  }) {
    return Container(
      color: AppThemeColors.card,
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
          UserPanel(
            onOpenSettings: () => _openUserSettings(context),
            voiceArg: activeVoiceChannel == null
                ? null
                : (serverId: widget.serverId, channelId: activeVoiceChannel.id),
            voiceChannelName: activeVoiceChannel?.name,
            voiceState: activeVoiceState,
            onLeaveVoice: _leaveActiveVoice,
          ),
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
    return Container(
      color: AppThemeColors.canvas,
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
                      channelName: channel.name,
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
