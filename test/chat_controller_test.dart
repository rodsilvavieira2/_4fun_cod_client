import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/core/websocket/realtime_event.dart';
import 'package:fourfun_cod_client/core/websocket/socket_service.dart';
import 'package:fourfun_cod_client/features/chat/chat_providers.dart';
import 'package:fourfun_cod_client/features/servers/servers_providers.dart';
import 'package:fourfun_cod_client/features/servers/servers_repository.dart';
import 'package:fourfun_cod_client/shared/models/message.dart';
import 'package:fourfun_cod_client/shared/models/servers.dart';
import 'package:fourfun_cod_client/shared/models/user.dart';

/// Socket fake: expõe streams injetáveis para simular eventos do servidor
/// e reconexão.
class FakeSocketService extends SocketService {
  FakeSocketService() : super(apiUrl: 'http://localhost:3000');

  final StreamController<RealtimeEvent> controller =
      StreamController<RealtimeEvent>.broadcast();
  final StreamController<void> reconnectedController =
      StreamController<void>.broadcast();

  @override
  Stream<RealtimeEvent> get events => controller.stream;

  @override
  Stream<void> get reconnected => reconnectedController.stream;

  void push(RealtimeEvent event) => controller.add(event);

  void pushReconnected() => reconnectedController.add(null);
}

/// Repository fake: apenas os métodos usados pelo chat/presença; o restante
/// da interface cai em `noSuchMethod` (nunca chamado nos testes).
class FakeServersRepository implements ServersRepository {
  FutureOr<MessagePage> Function(String channelId, {int limit, String? before})?
  onFetchMessages;
  Future<ServerPresence> Function(String serverId)? onFetchPresence;
  final List<String> sentContents = [];
  int fetchCalls = 0;

  @override
  Future<MessagePage> fetchMessages(
    String channelId, {
    int limit = 50,
    String? before,
  }) async {
    fetchCalls++;
    return onFetchMessages?.call(channelId, limit: limit, before: before) ??
        const MessagePage(messages: []);
  }

  @override
  Future<ServerPresence> fetchPresence(String serverId) async {
    final handler = onFetchPresence;
    if (handler == null) {
      return const ServerPresence(online: {});
    }
    return handler(serverId);
  }

  @override
  Future<ChatMessage> sendMessage(String channelId, String content) async {
    sentContents.add(content);
    return _msg('sent-$content', channelId, content);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Detail fake: expõe membros fixos para o escopo de presença.
class FakeServerDetailController extends ServerDetailController {
  @override
  Future<ServerDetail> build(String serverId) async => ServerDetail(
    server: const Server(id: 's1', name: 'Servidor'),
    channels: const [],
    members: [
      ServerMember(
        id: 'm1',
        userId: 'u1',
        role: ServerRole.owner,
        joinedAt: _epoch,
        user: const User(id: 'u1', name: 'Ana', username: 'ana'),
      ),
      ServerMember(
        id: 'm2',
        userId: 'u2',
        role: ServerRole.member,
        joinedAt: _epoch,
        user: const User(id: 'u2', name: 'Bia', username: 'bia'),
      ),
      ServerMember(
        id: 'm3',
        userId: 'u3',
        role: ServerRole.member,
        joinedAt: _epoch,
        user: const User(id: 'u3', name: 'Caio', username: 'caio'),
      ),
    ],
    myRole: ServerRole.owner,
  );
}

final _epoch = DateTime.fromMillisecondsSinceEpoch(0);

ChatMessage _msg(String id, String channelId, String content) => ChatMessage(
  id: id,
  channelId: channelId,
  content: content,
  author: const User(id: 'u1', name: 'Ana', username: 'ana'),
  createdAt: DateTime.fromMillisecondsSinceEpoch(0),
);

Map<String, dynamic> _messageJson(
  String id,
  String channelId,
  String content,
) => {
  'id': id,
  'channelId': channelId,
  'content': content,
  'createdAt': '2026-08-18T20:00:00.000Z',
  'author': {'id': 'u1', 'name': 'Ana', 'username': 'ana'},
};

final _arg = (serverId: 's1', channelId: 'c1');

void main() {
  group('RealtimeEvent.fromJson', () {
    test('message.created', () {
      final event = RealtimeEvent.fromJson('message.created', {
        'channelId': 'c1',
        'message': _messageJson('m1', 'c1', 'oi'),
      });
      expect(event, isA<MessageCreatedEvent>());
      expect((event! as MessageCreatedEvent).message.content, 'oi');
    });

    test('message.updated', () {
      final event = RealtimeEvent.fromJson('message.updated', {
        'channelId': 'c1',
        'message': _messageJson('m1', 'c1', 'editado'),
      });
      expect(event, isA<MessageUpdatedEvent>());
      expect((event! as MessageUpdatedEvent).message.content, 'editado');
    });

    test('message.deleted', () {
      final event = RealtimeEvent.fromJson('message.deleted', {
        'channelId': 'c1',
        'messageId': 'm1',
      });
      expect(event, isA<MessageDeletedEvent>());
      expect((event! as MessageDeletedEvent).messageId, 'm1');
    });

    test('presence.changed ONLINE/OFFLINE', () {
      final online = RealtimeEvent.fromJson('presence.changed', {
        'userId': 'u2',
        'status': 'ONLINE',
      });
      expect((online! as PresenceChangedEvent).status, PresenceStatus.online);
      final offline = RealtimeEvent.fromJson('presence.changed', {
        'userId': 'u2',
        'status': 'OFFLINE',
      });
      expect((offline! as PresenceChangedEvent).status, PresenceStatus.offline);
    });

    test('channel.created', () {
      final event = RealtimeEvent.fromJson('channel.created', {
        'serverId': 's1',
        'channel': {'id': 'c2', 'name': 'geral', 'type': 'TEXT'},
      });
      expect(event, isA<ChannelCreatedEvent>());
      expect((event! as ChannelCreatedEvent).channel.name, 'geral');
    });

    test('member.removed', () {
      final event = RealtimeEvent.fromJson('member.removed', {
        'serverId': 's1',
        'userId': 'u9',
      });
      expect(event, isA<MemberRemovedEvent>());
      expect((event! as MemberRemovedEvent).userId, 'u9');
    });

    test('evento desconhecido retorna null', () {
      expect(RealtimeEvent.fromJson('evento.estranho', {'a': 1}), isNull);
    });
  });

  group('ChatController', () {
    late ProviderContainer container;
    late FakeServersRepository repo;
    late FakeSocketService socket;

    setUp(() {
      repo = FakeServersRepository();
      socket = FakeSocketService();
      container = ProviderContainer(
        overrides: [
          serversRepositoryProvider.overrideWithValue(repo),
          socketServiceProvider.overrideWithValue(socket),
        ],
      );
    });

    tearDown(() => container.dispose());

    /// Aguarda o build inicial e devolve o notifier. Mantém o provider vivo
    /// com um listener (autoDispose descarta sem listeners ativos).
    Future<ChatController> buildChat() async {
      final sub = container.listen(chatControllerProvider(_arg), (_, _) {});
      addTearDown(sub.close);
      final notifier = container.read(chatControllerProvider(_arg).notifier);
      await container.read(chatControllerProvider(_arg).future);
      return notifier;
    }

    List<ChatMessage> currentMessages() =>
        container.read(chatControllerProvider(_arg)).valueOrNull?.messages ??
        const [];

    test(
      'send chama o repository e aplica a mensagem CONFIRMADA (sem otimismo)',
      () async {
        repo.onFetchMessages = (channelId, {limit = 50, before}) =>
            const MessagePage(messages: []);
        final notifier = await buildChat();

        await notifier.send('olá');
        await pumpEventQueue();

        expect(repo.sentContents, ['olá']);
        // Sem otimismo: nada aparece antes do 201. Após a confirmação, a
        // mensagem retornada pelo servidor é aplicada localmente (autor fora
        // da room durante queda de rede não perde a própria mensagem); o
        // dedupe por id no _applyEvent torna idempotente quando o evento
        // message.created chegar pelo socket.
        expect(
          currentMessages().map((m) => m.id),
          ['sent-olá'],
          reason: 'mensagem confirmada aplicada localmente',
        );
      },
    );

    test(
      'build inverte a página (API newest-first → lista oldest-first)',
      () async {
        repo.onFetchMessages = (channelId, {limit = 50, before}) => MessagePage(
          messages: [_msg('m3', 'c1', 'nova'), _msg('m2', 'c1', 'antiga')],
          nextCursor: 'm1',
        );
        await buildChat();

        expect(currentMessages().map((m) => m.id), ['m2', 'm3']);
        expect(
          container.read(chatControllerProvider(_arg)).valueOrNull?.hasMore,
          isTrue,
        );
      },
    );

    test('eventos durante o fetch ficam em buffer e são aplicados', () async {
      final completer = Completer<MessagePage>();
      repo.onFetchMessages = (channelId, {limit = 50, before}) =>
          completer.future;
      final sub = container.listen(chatControllerProvider(_arg), (_, _) {});
      addTearDown(sub.close);
      final buildFuture = container.read(chatControllerProvider(_arg).future);

      // Evento chega enquanto o fetch ainda está em voo (janela do build).
      socket.push(
        MessageCreatedEvent(
          channelId: 'c1',
          message: _msg('mX', 'c1', 'em voo'),
        ),
      );
      await pumpEventQueue();
      completer.complete(MessagePage(messages: [_msg('m1', 'c1', 'base')]));
      await buildFuture;
      await pumpEventQueue();

      expect(currentMessages().map((m) => m.id), ['m1', 'mX']);
    });

    test('message.created faz append com dedupe por id', () async {
      repo.onFetchMessages = (channelId, {limit = 50, before}) =>
          const MessagePage(messages: []);
      await buildChat();

      socket.push(
        MessageCreatedEvent(
          channelId: 'c1',
          message: _msg('m1', 'c1', 'primeira'),
        ),
      );
      await pumpEventQueue();
      socket.push(
        MessageCreatedEvent(
          channelId: 'c1',
          message: _msg('m1', 'c1', 'primeira'),
        ),
      );
      await pumpEventQueue();

      expect(currentMessages().length, 1, reason: 'dedupe por id');
      expect(currentMessages().single.content, 'primeira');
    });

    test('message.created de outro canal é ignorado', () async {
      repo.onFetchMessages = (channelId, {limit = 50, before}) =>
          const MessagePage(messages: []);
      await buildChat();

      socket.push(
        MessageCreatedEvent(
          channelId: 'outro-canal',
          message: _msg('mX', 'outro-canal', 'fora'),
        ),
      );
      await pumpEventQueue();

      expect(currentMessages(), isEmpty);
    });

    test('message.updated substitui a mensagem no lugar', () async {
      repo.onFetchMessages = (channelId, {limit = 50, before}) =>
          const MessagePage(messages: []);
      await buildChat();
      socket.push(
        MessageCreatedEvent(
          channelId: 'c1',
          message: _msg('m1', 'c1', 'original'),
        ),
      );
      await pumpEventQueue();

      socket.push(
        MessageUpdatedEvent(
          channelId: 'c1',
          message: _msg('m1', 'c1', 'editada'),
        ),
      );
      await pumpEventQueue();

      expect(currentMessages().length, 1);
      expect(currentMessages().single.content, 'editada');
    });

    test('message.deleted remove a mensagem', () async {
      repo.onFetchMessages = (channelId, {limit = 50, before}) =>
          const MessagePage(messages: []);
      await buildChat();
      socket.push(
        MessageCreatedEvent(channelId: 'c1', message: _msg('m1', 'c1', 'some')),
      );
      await pumpEventQueue();

      socket.push(const MessageDeletedEvent(channelId: 'c1', messageId: 'm1'));
      await pumpEventQueue();

      expect(currentMessages(), isEmpty);
    });

    test('loadMore usa o cursor, insere no topo e para no fim', () async {
      repo.onFetchMessages = (channelId, {limit = 50, before}) {
        if (before == null) {
          // API newest-first: página 1 = [m3 (nova), m2]; cursor = m1.
          return MessagePage(
            messages: [_msg('m3', 'c1', 'nova'), _msg('m2', 'c1', 'antiga')],
            nextCursor: 'm1',
          );
        }
        // Página mais antiga (newest-first): [m1].
        return MessagePage(messages: [_msg('m1', 'c1', 'mais antiga')]);
      };
      final notifier = await buildChat();
      expect(currentMessages().map((m) => m.id), ['m2', 'm3']);

      await notifier.loadMore();
      await pumpEventQueue();

      expect(repo.fetchCalls, 2);
      expect(
        currentMessages().map((m) => m.id),
        ['m1', 'm2', 'm3'],
        reason: 'mais antigas no topo, ordem oldest-first, sem duplicar',
      );

      await notifier.loadMore();
      await pumpEventQueue();
      expect(repo.fetchCalls, 2, reason: 'sem nextCursor → não busca de novo');
    });

    test('reconexão dispara resync que mescla mensagens novas', () async {
      repo.onFetchMessages = (channelId, {limit = 50, before}) => MessagePage(
        messages: [_msg('m3', 'c1', 'nova'), _msg('m2', 'c1', 'antiga')],
        nextCursor: 'm1',
      );
      await buildChat();
      expect(currentMessages().map((m) => m.id), ['m2', 'm3']);

      // Durante a queda chegaram m4 e m5 (mais novas que as em tela).
      repo.onFetchMessages = (channelId, {limit = 50, before}) => MessagePage(
        messages: [
          _msg('m5', 'c1', 'mais nova'),
          _msg('m4', 'c1', 'nova'),
          _msg('m3', 'c1', 'nova'),
          _msg('m2', 'c1', 'antiga'),
        ],
      );
      socket.pushReconnected();
      await pumpEventQueue();
      await pumpEventQueue();

      expect(currentMessages().map((m) => m.id), ['m2', 'm3', 'm4', 'm5']);
    });
  });

  group('PresenceController', () {
    late ProviderContainer container;
    late FakeServersRepository repo;
    late FakeSocketService socket;

    setUp(() {
      repo = FakeServersRepository();
      socket = FakeSocketService();
      container = ProviderContainer(
        overrides: [
          serversRepositoryProvider.overrideWithValue(repo),
          socketServiceProvider.overrideWithValue(socket),
          // Escopo de membros para o filtro de presença (u1, u2, u3).
          serverDetailProvider.overrideWith(FakeServerDetailController.new),
        ],
      );
    });

    tearDown(() => container.dispose());

    Set<String> online() => container.read(presenceProvider('s1'));

    test('OFFLINE durante o fetch não é ressuscitado pelo snapshot', () async {
      final completer = Completer<ServerPresence>();
      repo.onFetchPresence = (serverId) => completer.future;
      final sub = container.listen(presenceProvider('s1'), (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();
      await pumpEventQueue();

      // Evento OFFLINE chega enquanto o snapshot REST está em voo (escopo
      // de membros já carregado via serverDetailProvider fake).
      socket.push(
        const PresenceChangedEvent(
          userId: 'u2',
          status: PresenceStatus.offline,
        ),
      );
      await pumpEventQueue();
      completer.complete(const ServerPresence(online: {'u1', 'u2'}));
      await pumpEventQueue();
      await pumpEventQueue();

      expect(online(), {'u1'}, reason: 'u2 ficou offline; snapshot não decide');
    });

    test('ONLINE durante o fetch é preservado no merge', () async {
      final completer = Completer<ServerPresence>();
      repo.onFetchPresence = (serverId) => completer.future;
      final sub = container.listen(presenceProvider('s1'), (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();
      await pumpEventQueue();

      socket.push(
        const PresenceChangedEvent(userId: 'u3', status: PresenceStatus.online),
      );
      await pumpEventQueue();
      completer.complete(const ServerPresence(online: {'u1'}));
      await pumpEventQueue();
      await pumpEventQueue();

      expect(online(), {'u1', 'u3'});
    });
  });
}
