import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'package:fourfun_cod_client/core/websocket/socket_service.dart';

class _Emission {
  const _Emission(this.event, this.data);

  final String event;
  final dynamic data;
}

class _FakeIoSocket implements io.Socket {
  final Map<String, List<dynamic Function(dynamic)>> _handlers = {};
  final Queue<Object?> ackResults = Queue<Object?>();
  final List<_Emission> ackEmissions = [];
  final List<_Emission> emissions = [];

  bool connectCalled = false;
  bool disposed = false;
  int? timeoutMs;

  @override
  bool connected = false;

  @override
  String? id = 'fake-socket';

  @override
  io.Socket connect() {
    connectCalled = true;
    return this;
  }

  void establish() {
    connected = true;
    _trigger('connect');
  }

  void drop([dynamic reason = 'transport close']) {
    connected = false;
    _trigger('disconnect', reason);
  }

  void _trigger(String event, [dynamic data]) {
    for (final handler in [...?_handlers[event]]) {
      handler(data);
    }
  }

  @override
  Function() on(String event, dynamic handler) {
    final callback = handler as dynamic Function(dynamic);
    _handlers.putIfAbsent(event, () => []).add(callback);
    return () => _handlers[event]?.remove(callback);
  }

  @override
  void emit(String event, [dynamic data]) {
    emissions.add(_Emission(event, data));
  }

  @override
  io.Socket timeout(int timeout) {
    timeoutMs = timeout;
    return this;
  }

  @override
  Future<dynamic> emitWithAckAsync(
    String event,
    dynamic data, {
    Function? ack,
    bool binary = false,
  }) {
    ackEmissions.add(_Emission(event, data));
    final result = ackResults.isEmpty ? true : ackResults.removeFirst();
    if (result is Exception) return Future<dynamic>.error(result);
    if (result is Future<dynamic>) return result;
    return Future<dynamic>.value(result);
  }

  @override
  void dispose() {
    disposed = true;
    connected = false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  group('socketOriginFromApiUrl', () {
    test('remove prefixo REST para conectar no namespace raiz', () {
      expect(
        socketOriginFromApiUrl('https://api.4funcod.dev/api/v1'),
        'https://api.4funcod.dev',
      );
      expect(
        socketOriginFromApiUrl('http://localhost:3000/api/v1/'),
        'http://localhost:3000',
      );
    });

    test('preserva origem que já veio sem path', () {
      expect(
        socketOriginFromApiUrl('https://api.4funcod.dev'),
        'https://api.4funcod.dev',
      );
    });
  });

  group('SocketService restore', () {
    late _FakeIoSocket socket;
    late dynamic factoryUri;
    late Map<String, dynamic> factoryOptions;
    late SocketService service;

    setUp(() {
      socket = _FakeIoSocket();
      service = SocketService(
        apiUrl: 'https://api.4funcod.dev/api/v1',
        socketFactory: (uri, options) {
          factoryUri = uri;
          factoryOptions = Map<String, dynamic>.from(options as Map);
          return socket;
        },
      );
    });

    tearDown(() => service.dispose());

    test('heartbeat imediato precede rejoin de servidor e canal', () async {
      service.joinServer('server-1');
      service.joinChannel('channel-1');
      service.connect('access-token');

      expect(factoryUri, 'https://api.4funcod.dev');
      expect(factoryOptions['auth'], {'token': 'access-token'});
      expect(factoryOptions.containsKey('retries'), isFalse);
      expect(socket.connectCalled, isTrue);

      socket.establish();
      await _flush();

      expect(socket.timeoutMs, 1000);
      expect(socket.ackEmissions.map((item) => item.event), [
        'presence:heartbeat',
        'server:join',
        'channel:join',
      ]);
      expect(socket.ackEmissions[1].data, {'serverId': 'server-1'});
      expect(socket.ackEmissions[2].data, {'channelId': 'channel-1'});
    });

    test('repete heartbeat sem ack antes de restaurar rooms', () async {
      socket.ackResults
        ..add(Exception('ack timeout'))
        ..add(true);
      service.joinServer('server-1');
      service.connect('access-token');

      socket.establish();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await _flush();

      expect(socket.ackEmissions.map((item) => item.event), [
        'presence:heartbeat',
        'presence:heartbeat',
        'server:join',
      ]);
    });

    test('sinaliza reconexão somente depois dos acks de restore', () async {
      service.joinServer('server-1');
      service.connect('access-token');
      socket.establish();
      await _flush();

      var reconnects = 0;
      final sub = service.reconnected.listen((_) => reconnects++);
      addTearDown(sub.cancel);
      final heartbeatAck = Completer<dynamic>();
      socket.ackResults.add(heartbeatAck.future);

      socket.drop();
      socket.establish();
      await _flush();
      expect(reconnects, 0);

      heartbeatAck.complete(true);
      await _flush();
      expect(reconnects, 1);
    });
  });
}
