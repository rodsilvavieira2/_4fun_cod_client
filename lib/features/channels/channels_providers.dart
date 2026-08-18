import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/servers.dart';
import '../servers/servers_providers.dart';

/// Canais de um servidor (`GET /servers/:id/channels`) + operações de
/// criação/exclusão (OWNER). Após mutações, invalida também o detalhe do
/// servidor para manter o shell consistente.
class ChannelsController
    extends AutoDisposeFamilyAsyncNotifier<List<ServerChannel>, String> {
  @override
  Future<List<ServerChannel>> build(String serverId) {
    return ref.watch(serversRepositoryProvider).fetchChannels(serverId);
  }

  Future<void> create(String name, ChannelType type) async {
    await ref
        .read(serversRepositoryProvider)
        .createChannel(arg, name: name, type: type);
    ref.invalidateSelf();
    ref.invalidate(serverDetailProvider(arg));
  }

  Future<void> delete(String channelId) async {
    await ref.read(serversRepositoryProvider).deleteChannel(channelId);
    ref.invalidateSelf();
    ref.invalidate(serverDetailProvider(arg));
  }
}

final channelsControllerProvider = AsyncNotifierProvider.autoDispose.family<
    ChannelsController, List<ServerChannel>, String>(ChannelsController.new);
