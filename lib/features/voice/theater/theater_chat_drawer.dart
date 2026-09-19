import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/appearance_theme.dart';
import '../../channels/channels_providers.dart';
import '../../chat/chat_screen.dart';

/// Drawer de chat do theater (Fase 5): embute o `ChatScreen` real com o
/// channelId de VOZ — o backend agora aceita VOICE (ADR 0003 B1) e o realtime
/// `channel:<id>/message.created` alimenta o mesmo `chatControllerProvider`.
/// Largura 320–380px no desktop; overlay em janelas estreitas (o chamador
/// decide resize vs overlay por `MediaQuery`).
class TheaterChatDrawer extends ConsumerWidget {
  const TheaterChatDrawer({
    super.key,
    required this.serverId,
    required this.channelId,
  });

  final String serverId;
  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final channels = ref.watch(channelsControllerProvider(serverId));
    final channelName = channels.maybeWhen(
      data: (list) =>
          list.where((c) => c.id == channelId).firstOrNull?.name ?? 'voz',
      orElse: () => 'voz',
    );
    // Largura vem do chamador (coluna 300–380px ou overlay 340px):
    // aqui só preenche — largura fixa estourava em janela estreita.
    // A borda/sombra vive no painel chamador; aqui só o fundo do tema.
    return Container(
      width: double.infinity,
      color: colors.surface1,
      child: ChatScreen(
        key: ValueKey(channelId),
        serverId: serverId,
        channelId: channelId,
        channelName: channelName,
      ),
    );
  }
}
