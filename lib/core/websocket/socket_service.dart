import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/app_config.dart';
import '../logging/app_logger.dart';
import 'realtime_event.dart';

/// Cliente Socket.IO encapsulado — único lugar do app que importa
/// `socket_io_client` (a UI só enxerga [events] e os métodos de join/leave).
///
/// O handshake carrega o accessToken no `auth`; o servidor valida o JWT e,
/// se inválido/expirado, rejeita a conexão — sinalizado por [authFailures]
/// (quem cuida de auth trata como logout).
///
/// Reconexão automática (default do socket_io_client): no `connect`, os
/// joins de servidores/canais abertos são reemitidos a partir do estado
/// registrado por [joinServer]/[joinChannel], sem interação do usuário.
class SocketService {
  SocketService({required this.apiUrl, AppLogger? logger})
    : _log = logger ?? AppLogger();

  /// Base URL da API (mesma usada pelo dio; o gateway responde nela).
  final String apiUrl;

  final AppLogger _log;

  io.Socket? _socket;
  final StreamController<RealtimeEvent> _events =
      StreamController<RealtimeEvent>.broadcast();
  final StreamController<void> _authFailures =
      StreamController<void>.broadcast();
  final StreamController<void> _reconnected =
      StreamController<void>.broadcast();
  Timer? _heartbeat;

  /// Alguma conexão já foi estabelecida nesta sessão (não reseta em
  /// reconexões — inclusive as pós-auth-failure; só em logout/dispose).
  bool _hasConnectedOnce = false;

  /// Servidores com o shell aberto — re-join automático na reconexão.
  final Set<String> _openServers = {};

  /// Canal de texto aberto no shell — re-join automático na reconexão.
  String? _openChannelId;

  /// Eventos de domínio do servidor (mensagens, canais, presença...).
  Stream<RealtimeEvent> get events => _events.stream;

  /// Sinaliza que o servidor rejeitou o handshake (token inválido/expirado).
  Stream<void> get authFailures => _authFailures.stream;

  /// Emitido quando o socket reconecta após uma queda (não no primeiro
  /// connect) — quem consome pode refazer fetch/estado efêmero.
  Stream<void> get reconnected => _reconnected.stream;

  /// Conecta com o accessToken atual. Sempre (re)cria o socket para garantir
  /// auth fresca no handshake; o estado de join é preservado e reemitido no
  /// `connect` (cobre também a reconexão automática).
  void connect(String token) {
    _teardownSocket();
    final socket = io.io(
      apiUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .disableAutoConnect()
          .build(),
    );
    _socket = socket;
    _wire(socket);
    socket.connect();
  }

  /// Desconecta (logout) e limpa todo o estado de join.
  void disconnect() {
    _teardownSocket();
    _openServers.clear();
    _openChannelId = null;
    _hasConnectedOnce = false;
  }

  void joinServer(String serverId) {
    _openServers.add(serverId);
    _emit('server:join', {'serverId': serverId});
  }

  void leaveServer(String serverId) {
    _openServers.remove(serverId);
    _emit('server:leave', {'serverId': serverId});
  }

  void joinChannel(String channelId) {
    _openChannelId = channelId;
    _emit('channel:join', {'channelId': channelId});
  }

  /// Emite `channel:join` aguardando o ack do servidor (só confirma depois
  /// de processar validação + join da room). Usado pelo ChatController para
  /// fechar a janela fetch↔join: o snapshot REST roda APÓS o join, então
  /// mensagens criadas nesse intervalo entram no snapshot. Idempotente com
  /// o join fire-and-forget do shell. Lança se o socket estiver desconectado
  /// (quem chama decide: o re-join automático + resync cobrem o gap).
  Future<void> joinChannelAndWait(String channelId) async {
    _openChannelId = channelId;
    final socket = _socket;
    if (socket == null || !socket.connected) {
      throw StateError('socket desconectado');
    }
    // Timeout obrigatório: um ack perdido (queda no meio do emit) não pode
    // pendurar o fetch inicial do chat em loading para sempre — o resync da
    // reconexão cobre a janela.
    await socket
        .emitWithAckAsync('channel:join', {'channelId': channelId})
        .timeout(const Duration(seconds: 5));
  }

  void leaveChannel(String channelId) {
    if (_openChannelId != channelId) return;
    _openChannelId = null;
    _emit('channel:leave', {'channelId': channelId});
  }

  void _wire(io.Socket socket) {
    socket.on('connect', (_) {
      final wasConnected = _hasConnectedOnce;
      _hasConnectedOnce = true;
      _log.i(
        'socket conectado${wasConnected ? ' (reconexão)' : ''} '
        'id=${socket.id}',
        tag: 'socket',
      );
      _startHeartbeat();
      _rejoin();
      if (wasConnected) {
        _reconnected.add(null);
      }
    });
    socket.on('disconnect', (data) {
      _stopHeartbeat();
      _log.w('socket desconectado (data=$data)', tag: 'socket');
      // 'io server disconnect' = o servidor encerrou a conexão: handshake
      // rejeitado (token inválido) ou revogação de sessão. Em ambos os
      // casos o app deve tratar como falha de auth (logout/reconnect).
      if (data == 'io server disconnect') {
        _authFailures.add(null);
      }
    });
    socket.on('connect_error', (data) {
      _log.w('socket connect_error: ${_errorMessage(data)}', tag: 'socket');
      _handleConnectError(data);
    });
    socket.on('message.created', (data) => _dispatch('message.created', data));
    socket.on('message.updated', (data) => _dispatch('message.updated', data));
    socket.on('message.deleted', (data) => _dispatch('message.deleted', data));
    socket.on('channel.created', (data) => _dispatch('channel.created', data));
    socket.on('channel.updated', (data) => _dispatch('channel.updated', data));
    socket.on('channel.deleted', (data) => _dispatch('channel.deleted', data));
    socket.on('member.removed', (data) => _dispatch('member.removed', data));
    socket.on('member.left', (data) => _dispatch('member.left', data));
    socket.on(
      'member.role_updated',
      (data) => _dispatch('member.role_updated', data),
    );
    socket.on(
      'presence.changed',
      (data) => _dispatch('presence.changed', data),
    );
    socket.on(
      'voice.presence.changed',
      (data) => _dispatch('voice.presence.changed', data),
    );
  }

  void _dispatch(String type, dynamic data) {
    if (data is! Map) return;
    try {
      final event = RealtimeEvent.fromJson(
        type,
        Map<String, dynamic>.from(data),
      );
      if (event == null) return; // evento desconhecido: ignora
      _log.d('evento $type', tag: 'socket');
      _events.add(event);
    } catch (_) {
      // Payload malformado de tipo conhecido: ignora em vez de derrubar o
      // handler do socket (um único evento ruim não pode matar o stream).
    }
  }

  void _handleConnectError(dynamic data) {
    final message = _errorMessage(data).toLowerCase();
    final isAuthRejection =
        message.contains('unauthorized') ||
        message.contains('forbidden') ||
        message.contains('jwt') ||
        message.contains('token') ||
        message.contains('auth') ||
        message.contains('invalid');
    if (isAuthRejection) {
      _authFailures.add(null);
    }
  }

  String _errorMessage(dynamic data) {
    if (data is String) return data;
    if (data is Map) {
      final message = data['message'];
      if (message is String) return message;
      return data.toString();
    }
    if (data == null) return '';
    return data.toString();
  }

  /// Re-emite os joins registrados (chamado em todo `connect`, inclusive
  /// após reconexão automática).
  void _rejoin() {
    for (final serverId in _openServers) {
      _emit('server:join', {'serverId': serverId});
    }
    final channelId = _openChannelId;
    if (channelId != null) {
      _emit('channel:join', {'channelId': channelId});
    }
  }

  void _emit(String event, [Map<String, dynamic>? data]) {
    final socket = _socket;
    if (socket == null || !socket.connected) {
      _log.d('emit ignorado (desconectado): $event', tag: 'socket');
      return;
    }
    _log.d('emit $event', tag: 'socket');
    if (data == null) {
      socket.emit(event);
    } else {
      socket.emit(event, data);
    }
  }

  /// Heartbeat de presença a cada 30s enquanto conectado (TTL do Redis é
  /// 60s — o servidor derruba a presença se o heartbeat parar).
  void _startHeartbeat() {
    _heartbeat ??= Timer.periodic(const Duration(seconds: 30), (_) {
      _emit('presence:heartbeat');
    });
  }

  void _stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  void _teardownSocket() {
    _stopHeartbeat();
    final socket = _socket;
    _socket = null;
    socket?.dispose();
  }

  /// Encerramento definitivo (provider descartado / fim do app).
  void dispose() {
    _teardownSocket();
    _openServers.clear();
    _openChannelId = null;
    _hasConnectedOnce = false;
    _events.close();
    _authFailures.close();
    _reconnected.close();
  }
}

/// Instância única do socket — overridable em testes.
final socketServiceProvider = Provider<SocketService>((ref) {
  final service = SocketService(
    apiUrl: ref.watch(appConfigProvider).apiBaseUrl,
    logger: ref.watch(appLoggerProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
