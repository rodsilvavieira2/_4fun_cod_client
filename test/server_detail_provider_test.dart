import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/core/websocket/realtime_event.dart';
import 'package:fourfun_cod_client/core/websocket/socket_service.dart';
import 'package:fourfun_cod_client/features/servers/servers_providers.dart';
import 'package:fourfun_cod_client/features/servers/servers_repository.dart';
import 'package:fourfun_cod_client/shared/models/servers.dart';

class _FakeSocketService extends SocketService {
  _FakeSocketService() : super(apiUrl: 'http://localhost:3000');

  final _events = StreamController<RealtimeEvent>.broadcast();
  final _reconnected = StreamController<void>.broadcast();

  @override
  Stream<RealtimeEvent> get events => _events.stream;

  @override
  Stream<void> get reconnected => _reconnected.stream;

  void reconnect() => _reconnected.add(null);

  Future<void> closeStreams() async {
    await _events.close();
    await _reconnected.close();
  }
}

class _FakeServersRepository implements ServersRepository {
  int fetchDetailCalls = 0;
  final secondFetchStarted = Completer<void>();

  @override
  Future<ServerDetail> fetchServerDetail(String serverId) async {
    fetchDetailCalls++;
    if (fetchDetailCalls == 2 && !secondFetchStarted.isCompleted) {
      secondFetchStarted.complete();
    }

    return ServerDetail(
      server: Server(id: serverId, name: 'Servidor'),
      channels: const [],
      members: const [],
      myRole: fetchDetailCalls == 1 ? ServerRole.admin : ServerRole.member,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  test(
    'serverDetailProvider refaz o fetch na reconexão e atualiza a role',
    () async {
      final repository = _FakeServersRepository();
      final socket = _FakeSocketService();
      final container = ProviderContainer(
        overrides: [
          serversRepositoryProvider.overrideWithValue(repository),
          socketServiceProvider.overrideWithValue(socket),
        ],
      );
      final provider = serverDetailProvider('server-1');
      final subscription = container.listen(provider, (_, _) {});

      try {
        final initial = await container.read(provider.future);
        expect(initial.myRole, ServerRole.admin);
        expect(initial.canManageServer, isTrue);
        expect(repository.fetchDetailCalls, 1);

        socket.reconnect();
        await repository.secondFetchStarted.future;

        final refreshed = await container.read(provider.future);
        expect(repository.fetchDetailCalls, 2);
        expect(refreshed.myRole, ServerRole.member);
        expect(refreshed.canManageServer, isFalse);
      } finally {
        subscription.close();
        container.dispose();
        await socket.closeStreams();
      }
    },
  );
}
