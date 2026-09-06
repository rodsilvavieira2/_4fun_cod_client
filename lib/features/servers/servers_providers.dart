import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/logging/app_logger.dart';
import '../../core/websocket/realtime_event.dart';
import '../../core/websocket/socket_service.dart';
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

final serversProvider = AsyncNotifierProvider<ServersController, List<Server>>(
  ServersController.new,
);

/// Detalhe de um servidor (`GET /servers/:id`): servidor + canais + membros
/// + papel do usuário.
class ServerDetailController
    extends AutoDisposeFamilyAsyncNotifier<ServerDetail, String> {
  StreamSubscription<RealtimeEvent>? _membershipSubscription;
  StreamSubscription<void>? _reconnectedSubscription;

  @override
  Future<ServerDetail> build(String serverId) async {
    _membershipSubscription?.cancel();
    _reconnectedSubscription?.cancel();
    final socket = ref.read(socketServiceProvider);
    _membershipSubscription = socket.events.listen((event) {
      final eventServerId = switch (event) {
        MemberRemovedEvent(:final serverId) => serverId,
        MemberRoleUpdatedEvent(:final serverId) => serverId,
        _ => null,
      };
      if (eventServerId == serverId) ref.invalidateSelf();
    });
    // A role event may have been missed while offline. Refetch on reconnect
    // so a demoted manager immediately loses the restricted UI as well.
    _reconnectedSubscription = socket.reconnected.listen(
      (_) => ref.invalidateSelf(),
    );
    ref.onDispose(() {
      _membershipSubscription?.cancel();
      _reconnectedSubscription?.cancel();
    });
    final log = ref.watch(appLoggerProvider);
    log.d('detail fetch: $serverId', tag: 'server-detail');
    // Timeout defensivo: mesmo com o interceptor corrigido, um fetch preso
    // (fila do dio, rede) nunca pode deixar o painel em loading eterno —
    // vira AsyncError (ícone de refresh) após 20s.
    try {
      final detail = await ref
          .watch(serversRepositoryProvider)
          .fetchServerDetail(serverId)
          .timeout(const Duration(seconds: 20));
      log.d(
        'detail ok: $serverId (${detail.channels.length} canais)',
        tag: 'server-detail',
      );
      return detail;
    } catch (e, st) {
      log.e(
        'detail falhou: $serverId',
        error: e,
        stackTrace: st,
        tag: 'server-detail',
      );
      rethrow;
    }
  }

  /// Exclui o servidor (OWNER) e remove da lista. NÃO re-busca o detalhe
  /// (o recurso não existe mais — invalidateSelf causaria 404 garantido).
  Future<void> delete() async {
    await ref.read(serversRepositoryProvider).deleteServer(arg);
    ref.invalidate(serversProvider);
  }

  /// Renomeia o servidor (OWNER ou ADMIN).
  Future<void> updateName(String name) async {
    await ref.read(serversRepositoryProvider).updateServer(arg, name: name);
    ref.invalidateSelf();
    ref.invalidate(serversProvider);
  }

  /// Envia um novo ícone do servidor (OWNER ou ADMIN).
  Future<void> uploadIcon({
    required List<int> bytes,
    required String fileName,
    required String contentType,
  }) async {
    await ref
        .read(serversRepositoryProvider)
        .uploadServerIcon(
          arg,
          bytes: bytes,
          fileName: fileName,
          contentType: contentType,
        );
    ref.invalidateSelf();
    ref.invalidate(serversProvider);
  }

  /// Remove o ícone do servidor (OWNER ou ADMIN).
  Future<void> removeIcon() async {
    await ref.read(serversRepositoryProvider).deleteServerIcon(arg);
    ref.invalidateSelf();
    ref.invalidate(serversProvider);
  }

  /// Remove um membro conforme a hierarquia do papel atual.
  Future<void> removeMember(String userId) async {
    await ref.read(serversRepositoryProvider).removeMember(arg, userId);
    ref.invalidateSelf();
  }

  /// Promove um membro a ADMIN ou rebaixa para MEMBER (apenas OWNER).
  Future<void> updateMemberRole(String userId, ServerRole role) async {
    await ref
        .read(serversRepositoryProvider)
        .updateMemberRole(arg, userId, role);
    ref.invalidateSelf();
  }

  /// Cria um convite (OWNER ou ADMIN).
  Future<InviteInfo> createInvite() {
    return ref.read(serversRepositoryProvider).createInvite(arg);
  }
}

final serverDetailProvider = AsyncNotifierProvider.autoDispose
    .family<ServerDetailController, ServerDetail, String>(
      ServerDetailController.new,
    );

/// Resolução pública de convite (`GET /invites/:code`) — funciona
/// deslogado; o aceite (`POST`) exige sessão.
final inviteDetailProvider = FutureProvider.autoDispose
    .family<InviteDetail, String>((ref, code) {
      return ref.watch(serversRepositoryProvider).fetchInvite(code);
    });

/// Presença online dos membros — `GET /servers/:id/presence` (estado
/// inicial) + eventos `presence.changed` aplicados em tempo real.
class PresenceController
    extends AutoDisposeFamilyNotifier<Set<String>, String> {
  StreamSubscription<RealtimeEvent>? _subscription;
  StreamSubscription<void>? _reconnectedSub;
  bool _disposed = false;
  // Usuários com evento recebido: o snapshot REST não pode decidir sobre
  // eles (evita ressuscitar quem ficou OFFLINE durante o fetch).
  final Set<String> _seenEvents = {};
  // Membros do servidor (filtro de escopo: o payload de presença não traz
  // serverId — eventos de outros servidores não podem vazar para este).
  Set<String>? _memberIds;

  @override
  Set<String> build(String serverId) {
    // Rebuild: mesma instância do notifier é reutilizada — zera o flag e
    // cancela listeners anteriores (senão eventos duplicam e _fetch morre).
    _disposed = false;
    _subscription?.cancel();
    _reconnectedSub?.cancel();
    _subscription = null;
    _reconnectedSub = null;
    // Escopo de membros: lido de forma SÍNCRONA via ref.read — o detail pode
    // já estar resolvido quando este controller nasce, e o ref.listen sem
    // fireImmediately não dispararia com o valor atual; com fireImmediately
    // tocaria `state` durante o build (não suportado pelo Riverpod).
    _memberIds = ref
        .read(serverDetailProvider(serverId))
        .valueOrNull
        ?.members
        .map((m) => m.userId)
        .toSet();
    ref.listen(serverDetailProvider(serverId), (_, next) {
      final members = next.valueOrNull?.members.map((m) => m.userId).toSet();
      _memberIds = members;
      if (members != null && !_disposed) {
        _seenEvents.removeWhere((id) => !members.contains(id));
        final cleaned = {...state}..removeWhere((id) => !members.contains(id));
        if (cleaned.length != state.length) state = cleaned;
      }
    });
    _subscription = ref.read(socketServiceProvider).events.listen((event) {
      if (event is! PresenceChangedEvent) return;
      final members = _memberIds;
      // Sem escopo (members ainda não carregou) → descarta o evento: o
      // snapshot REST do _fetch cobre o estado durante a carga; aceitar
      // eventos sem escopo poluiria _seenEvents com ids de outros servers.
      if (members == null || !members.contains(event.userId)) return;
      _seenEvents.add(event.userId);
      final online = {...state};
      if (event.status == PresenceStatus.online) {
        online.add(event.userId);
      } else {
        online.remove(event.userId);
      }
      state = online;
    });
    // Reconexão: presença é efêmera (TTL 60s) — refaz o snapshot para não
    // deixar fantasmas online após uma queda. Eventos pré-queda são MAIS
    // ANTIGOS que o snapshot novo: limpa o rastro (_seenEvents/state) para
    // que o snapshot decida tudo de novo.
    _reconnectedSub = ref.read(socketServiceProvider).reconnected.listen((_) {
      _seenEvents.clear();
      state = const {};
      _fetch(serverId);
    });
    ref.onDispose(() {
      _disposed = true;
      _subscription?.cancel();
      _reconnectedSub?.cancel();
    });
    _fetch(serverId);
    return const {};
  }

  Future<void> _fetch(String serverId) async {
    try {
      final presence = await ref
          .read(serversRepositoryProvider)
          .fetchPresence(serverId);
      if (_disposed) return;
      // Snapshot REST como base, exceto usuários com evento (o estado de
      // eventos é sempre mais recente que o snapshot).
      final fromSnapshot = {
        for (final userId in presence.online)
          if (!_seenEvents.contains(userId)) userId,
      };
      state = {...fromSnapshot, ...state};
    } catch (_) {
      // Presença é best-effort: sem resposta, todos aparecem offline.
    }
  }
}

/// Ids dos usuários online no servidor (autoDispose: sai da tela de membros,
/// cancela o listener).
final presenceProvider = NotifierProvider.autoDispose
    .family<PresenceController, Set<String>, String>(PresenceController.new);

/// Ocupantes de voz por canal (`channelId -> userIds`). É separado da
/// presença online para não alterar os consumidores existentes de
/// [presenceProvider], mas usa o mesmo snapshot REST e os eventos LiveKit.
class VoicePresenceController
    extends AutoDisposeFamilyNotifier<Map<String, Set<String>>, String> {
  StreamSubscription<RealtimeEvent>? _subscription;
  StreamSubscription<void>? _reconnectedSub;
  bool _disposed = false;
  final Map<({String channelId, String userId}), bool> _eventStates = {};

  @override
  Map<String, Set<String>> build(String serverId) {
    _disposed = false;
    _subscription?.cancel();
    _reconnectedSub?.cancel();
    _subscription = ref.read(socketServiceProvider).events.listen((event) {
      if (event is! VoicePresenceChangedEvent || event.serverId != serverId) {
        return;
      }
      _eventStates[(channelId: event.channelId, userId: event.userId)] =
          event.connected;
      final next = {
        for (final entry in state.entries) entry.key: {...entry.value},
      };
      final occupants = next.putIfAbsent(event.channelId, () => <String>{});
      if (event.connected) {
        occupants.add(event.userId);
      } else {
        occupants.remove(event.userId);
      }
      state = next;
    });
    _reconnectedSub = ref.read(socketServiceProvider).reconnected.listen((_) {
      _eventStates.clear();
      state = const {};
      _fetch(serverId);
    });
    ref.onDispose(() {
      _disposed = true;
      _subscription?.cancel();
      _reconnectedSub?.cancel();
    });
    _fetch(serverId);
    return const {};
  }

  Future<void> _fetch(String serverId) async {
    try {
      final presence = await ref
          .read(serversRepositoryProvider)
          .fetchPresence(serverId);
      if (_disposed) return;
      final next = <String, Set<String>>{
        for (final entry in presence.voiceByChannel.entries)
          entry.key: {...entry.value},
      };
      for (final entry in _eventStates.entries) {
        final occupants = next.putIfAbsent(
          entry.key.channelId,
          () => <String>{},
        );
        if (entry.value) {
          occupants.add(entry.key.userId);
        } else {
          occupants.remove(entry.key.userId);
        }
      }
      state = next;
    } catch (_) {
      // Presença de voz é best-effort; os eventos futuros ainda a preenchem.
    }
  }
}

final voicePresenceProvider = NotifierProvider.autoDispose
    .family<VoicePresenceController, Map<String, Set<String>>, String>(
      VoicePresenceController.new,
    );
