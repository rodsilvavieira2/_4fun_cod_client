import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/ui/settings_modal.dart';
import '../../core/websocket/socket_service.dart';
import '../../shared/models/servers.dart';
import '../channels/channel_header.dart';
import '../channels/channel_list.dart';
import '../channels/channels_providers.dart';
import '../chat/chat_screen.dart';
import '../voice/voice_screen.dart';
import 'members_panel.dart';
import 'server_rail.dart';
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
    socket.leaveServer(widget.serverId);
    super.dispose();
  }

  void _onChannelSelected(String channelId, List<ServerChannel> channels) {
    if (_selectedChannelId == channelId) return;
    final previous = _selectedChannelId;
    final socket = ref.read(socketServiceProvider);
    if (previous != null) {
      socket.leaveChannel(previous);
    }
    setState(() => _selectedChannelId = channelId);
    final channel = channels.where((c) => c.id == channelId).firstOrNull;
    if (channel?.type == ChannelType.text) {
      socket.joinChannel(channelId);
    }
  }

  /// Abaixo desta largura o shell vira mobile (lista de canais full-width →
  /// push do conteúdo com back); em ≥ ela mantém as colunas do desktop.
  static const double _desktopBreakpoint = 800;

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(serverDetailProvider(widget.serverId));
    final channels = ref.watch(channelsControllerProvider(widget.serverId));
    final isOwner = detail.valueOrNull?.isOwner ?? false;
    final channelList = channels.valueOrNull ?? const <ServerChannel>[];
    final selectedChannel = channelList
        .where((c) => c.id == _selectedChannelId)
        .firstOrNull;

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
        final isNarrow = constraints.maxWidth < _desktopBreakpoint;
        // Mobile: com canal selecionado, o conteúdo ocupa a tela toda e o
        // header ganha o back para a lista de canais.
        final showContent = isNarrow && _selectedChannelId != null;
        return Scaffold(
          body: isNarrow
              ? (showContent
                    ? _channelContent(
                        context,
                        selectedChannel,
                        onBack: () {
                          setState(() => _selectedChannelId = null);
                        },
                      )
                    : Row(
                        children: [
                          ServerRail(
                            selectedServerId: widget.serverId,
                            width: 56,
                            compact: true,
                          ),
                          Expanded(
                            child: _channelListPanel(
                              context,
                              detail: detail,
                              isOwner: isOwner,
                              channelList: channelList,
                            ),
                          ),
                        ],
                      ))
              : _desktopBody(
                  context,
                  detail: detail,
                  isOwner: isOwner,
                  channelList: channelList,
                  selectedChannel: selectedChannel,
                ),
        );
      },
    );
  }

  /// Layout desktop: rail + lista de canais fixa + conteúdo + membros.
  Widget _desktopBody(
    BuildContext context, {
    required AsyncValue<ServerDetail> detail,
    required bool isOwner,
    required List<ServerChannel> channelList,
    required ServerChannel? selectedChannel,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ServerRail(selectedServerId: widget.serverId),
        const VerticalDivider(width: 1),
        SizedBox(
          width: 240,
          child: _channelListPanel(
            context,
            detail: detail,
            isOwner: isOwner,
            channelList: channelList,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _channelContent(context, selectedChannel)),
        if (_showMembers) ...[
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
    required bool isOwner,
    required List<ServerChannel> channelList,
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
              data: (_) => ChannelList(
                serverId: widget.serverId,
                isOwner: isOwner,
                selectedChannelId: _selectedChannelId,
                onChannelSelected: (id) => _onChannelSelected(id, channelList),
              ),
            ),
          ),
          UserPanel(onOpenSettings: () => _openSettings(context)),
        ],
      ),
    );
  }

  Widget _channelContent(
    BuildContext context,
    ServerChannel? selectedChannel, {
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
                final isNarrow =
                    MediaQuery.of(context).size.width < _desktopBreakpoint;
                if (isNarrow) {
                  context.push('/servers/${widget.serverId}/members');
                } else {
                  setState(() => _showMembers = !_showMembers);
                }
              },
              onOpenInvites: () =>
                  context.push('/servers/${widget.serverId}/invites'),
              onOpenSettings: () => _openSettings(context),
            ),
          Expanded(
            child: channel == null
                ? const Center(child: Text('Selecione um canal'))
                : switch (channel.type) {
                    ChannelType.text => ChatScreen(
                      key: ValueKey(channel.id),
                      serverId: widget.serverId,
                      channelId: channel.id,
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

  /// Gatilho do modal de configurações (SPEC 3): abre via
  /// [showSettingsModal] com o servidor ativo (seção "Servidor" do modal).
  void _openSettings(BuildContext context) {
    showSettingsModal(context, serverId: widget.serverId);
  }
}
