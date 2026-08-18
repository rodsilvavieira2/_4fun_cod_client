import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../shared/models/servers.dart';
import 'servers_repository.dart';

/// Provider do repositório de servidores (dio por trás; UI nunca importa dio).
final serversRepositoryProvider = Provider<ServersRepository>(
  (ref) => ServersRepository(ref.watch(apiClientProvider)),
);

/// Lista de servidores do usuário (`GET /servers`).
class ServersController extends AsyncNotifier<List<Server>> {
  @override
  Future<List<Server>> build() {
    return ref.watch(serversRepositoryProvider).fetchServers();
  }

  /// Cria um servidor e recarrega a lista (sem mensagens otimistas).
  Future<Server> create(String name) async {
    final server = await ref.read(serversRepositoryProvider).createServer(name);
    ref.invalidateSelf();
    return server;
  }

  /// Sai do servidor (não-OWNER) e recarrega a lista.
  Future<void> leave(String serverId) async {
    await ref.read(serversRepositoryProvider).leaveServer(serverId);
    ref.invalidateSelf();
  }
}

final serversProvider =
    AsyncNotifierProvider<ServersController, List<Server>>(ServersController.new);

/// Detalhe de um servidor (`GET /servers/:id`): servidor + canais + membros
/// + papel do usuário.
class ServerDetailController
    extends AutoDisposeFamilyAsyncNotifier<ServerDetail, String> {
  @override
  Future<ServerDetail> build(String serverId) {
    return ref.watch(serversRepositoryProvider).fetchServerDetail(serverId);
  }

  /// Exclui o servidor (OWNER) e remove da lista. NÃO re-busca o detalhe
  /// (o recurso não existe mais — invalidateSelf causaria 404 garantido).
  Future<void> delete() async {
    await ref.read(serversRepositoryProvider).deleteServer(arg);
    ref.invalidate(serversProvider);
  }

  /// Renomeia o servidor (OWNER).
  Future<void> updateName(String name) async {
    await ref.read(serversRepositoryProvider).updateServer(arg, name: name);
    ref.invalidateSelf();
    ref.invalidate(serversProvider);
  }

  /// Atualiza o ícone do servidor (OWNER).
  Future<void> updateIcon(String iconUrl) async {
    await ref.read(serversRepositoryProvider).updateServer(arg, iconUrl: iconUrl);
    ref.invalidateSelf();
    ref.invalidate(serversProvider);
  }

  /// Remove um membro (OWNER).
  Future<void> removeMember(String userId) async {
    await ref.read(serversRepositoryProvider).removeMember(arg, userId);
    ref.invalidateSelf();
  }

  /// Cria um convite (OWNER).
  Future<InviteInfo> createInvite() {
    return ref.read(serversRepositoryProvider).createInvite(arg);
  }
}

final serverDetailProvider = AsyncNotifierProvider.autoDispose.family<
    ServerDetailController, ServerDetail, String>(ServerDetailController.new);

/// Resolução pública de convite (`GET /invites/:code`) — funciona
/// deslogado; o aceite (`POST`) exige sessão.
final inviteDetailProvider =
    FutureProvider.autoDispose.family<InviteDetail, String>((ref, code) {
  return ref.watch(serversRepositoryProvider).fetchInvite(code);
});
