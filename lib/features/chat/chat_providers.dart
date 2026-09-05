import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/websocket/realtime_event.dart';
import '../../core/websocket/socket_service.dart';
import '../../shared/models/message.dart';
import '../servers/servers_providers.dart';

/// Estado do chat de um canal: mensagens carregadas (mais antigas primeiro)
/// + paginação. `firstMessageId` é o cursor do `loadMore` (mensagem mais
/// antiga da lista atual).
class ChatState {
  const ChatState({
    required this.messages,
    required this.hasMore,
    this.loadingMore = false,
  });

  final List<ChatMessage> messages;
  final bool hasMore;
  final bool loadingMore;

  String? get firstMessageId => messages.isEmpty ? null : messages.first.id;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? hasMore,
    bool? loadingMore,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      hasMore: hasMore ?? this.hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
    );
  }
}

/// Chat de um canal de texto — carrega as 50 mensagens mais recentes
/// (`GET /channels/:id/messages`) e aplica os eventos de tempo real SEM
/// refetch (append/update/delete local com dedupe por id).
class ChatController
    extends
        AutoDisposeFamilyAsyncNotifier<
          ChatState,
          ({String serverId, String channelId})
        > {
  StreamSubscription<RealtimeEvent>? _subscription;
  StreamSubscription<void>? _reconnectedSub;
  bool _disposed = false;

  @override
  Future<ChatState> build(({String serverId, String channelId}) arg) async {
    final socket = ref.watch(socketServiceProvider);

    // Rebuild (retry/invalidação): o Riverpod reutiliza a instância do
    // notifier — zera o flag (senão `_disposed` fica true para sempre e
    // loadMore/resync morrem silenciosamente após qualquer "Tentar
    // novamente") e cancela os listeners da build anterior.
    _disposed = false;

    // Listener registrado ANTES de qualquer await: eventos que chegam
    // durante o carregamento ficam em buffer e são aplicados quando o
    // estado nasce (broadcast stream não tem buffer próprio — sem isso,
    // mensagens se perdem na janela entre a resposta REST e o listen).
    // O critério é um flag LOCAL (`ready`), não `state.valueOrNull`:
    // durante um rebuild o estado anterior ainda está visível e eventos
    // cairiam no ramo errado.
    var ready = false;
    final pending = <RealtimeEvent>[];
    final eventsSub = socket.events.listen((event) {
      if (!ready) {
        pending.add(event);
      } else {
        _applyEvent(event);
      }
    });

    // Desliga os listeners da build anterior. A janela entre registrar o
    // novo e cancelar o antigo é inofensiva: um evento nesse intervalo
    // também chega no listener novo (buffered) e a aplicação no estado
    // antigo é sobrescrita pelo publish do fetch.
    await _subscription?.cancel();
    await _reconnectedSub?.cancel();
    _subscription = eventsSub;
    _reconnectedSub = null;

    ref.onDispose(() {
      _disposed = true;
      _subscription?.cancel();
      _reconnectedSub?.cancel();
    });

    // Reconexão após queda: refaz o fetch da primeira página e mescla com
    // o que já está em tela (dedupe por id) — cobre o gap da janela offline.
    _reconnectedSub = socket.reconnected.listen((_) => _resync());

    // Fecha a janela fetch↔join: aguarda o ack do `channel:join` (o servidor
    // só confirma após processar o join da room) ANTES do snapshot REST —
    // mensagens criadas nesse intervalo entram no snapshot; as posteriores
    // chegam como evento. Socket offline → segue sem join (o re-join
    // automático + _resync na reconexão cobrem a janela).
    try {
      await socket.joinChannelAndWait(arg.channelId);
    } catch (_) {
      // ack indisponível/falhou: não bloqueia o chat
    }

    final page = await ref
        .read(serversRepositoryProvider)
        .fetchMessages(arg.channelId, limit: 50);

    // A API retorna as mais recentes primeiro; a lista interna é oldest-first
    // (índice 0 = mais antiga, compatível com o scroll reverso da UI).
    var messages = page.messages.reversed.toList();
    if (_disposed) return ChatState(messages: messages, hasMore: false);

    // Publica o estado base e então aplica o buffer de eventos que chegaram
    // enquanto o fetch estava em voo (_applyEvent precisa de estado vivo).
    state = AsyncData(
      ChatState(messages: messages, hasMore: page.nextCursor != null),
    );
    ready = true;
    for (final event in pending) {
      _applyEvent(event);
    }
    return state.requireValue;
  }

  /// Envia via REST e aplica a mensagem CONFIRMADA (201) localmente. Sem
  /// otimismo: nada aparece antes da resposta do servidor. O dedupe por id
  /// no [_applyEvent] torna a inserção idempotente quando o evento
  /// `message.created` chegar pelo socket (autor fora da room durante uma
  /// queda de rede não perde a própria mensagem da tela).
  Future<void> send(String content) async {
    final message = await ref
        .read(serversRepositoryProvider)
        .sendMessage(arg.channelId, content);
    if (_disposed) return;
    final current = state.valueOrNull;
    if (current == null) return;
    _applyEvent(
      MessageCreatedEvent(channelId: arg.channelId, message: message),
    );
  }

  /// Carrega a página anterior (`before=<firstMessageId>`), insere no topo
  /// e atualiza o cursor — sem duplicar ids já presentes.
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || current.loadingMore || !current.hasMore) return;
    final cursor = current.firstMessageId;
    if (cursor == null) return;

    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref
          .read(serversRepositoryProvider)
          .fetchMessages(arg.channelId, limit: 50, before: cursor);
      if (_disposed) return;
      final next = state.valueOrNull;
      if (next == null) return;
      final existingIds = next.messages.map((m) => m.id).toSet();
      // Página da API vem newest-first; inverter para oldest-first antes de
      // concatenar no topo.
      final older = [
        for (final message in page.messages.reversed)
          if (!existingIds.contains(message.id)) message,
      ];
      state = AsyncData(
        next.copyWith(
          messages: [...older, ...next.messages],
          hasMore: page.nextCursor != null,
          loadingMore: false,
        ),
      );
    } catch (_) {
      // Falha de paginação: apenas desliga o indicador (novo scroll tenta
      // de novo); o chat já carregado continua utilizável.
      if (_disposed) return;
      final next = state.valueOrNull;
      if (next == null) return;
      state = AsyncData(next.copyWith(loadingMore: false));
    }
  }

  /// Refaz o fetch da primeira página após reconexão e mescla por id com a
  /// lista atual (mantém o que já estava em tela; não perde o scroll).
  Future<void> _resync() async {
    final current = state.valueOrNull;
    if (current == null) return;
    try {
      final page = await ref
          .read(serversRepositoryProvider)
          .fetchMessages(arg.channelId, limit: 50);
      if (_disposed) return;
      final next = state.valueOrNull;
      if (next == null) return;
      final byId = <String, ChatMessage>{
        // Página fresca da API vence sobre a cópia local (mensagens
        // editadas durante a queda voltam ao conteúdo atual).
        // Trade-off conhecido: uma mensagem DELETADA durante a queda pode
        // ressurgir se ainda estiver na lista local (merge por id não tem
        // tombstones; refetch completo de todas as páginas ficaria caro).
        for (final m in [...next.messages, ...page.messages.reversed]) m.id: m,
      };
      final merged = byId.values.toList()
        ..sort((a, b) {
          final byTime = a.createdAt.compareTo(b.createdAt);
          // Desempate por id: sort não é estável; createdAt idêntico em
          // rajadas não pode reordenar mensagens a cada resync.
          return byTime != 0 ? byTime : a.id.compareTo(b.id);
        });
      state = AsyncData(
        next.copyWith(
          messages: merged,
          hasMore: page.nextCursor != null || next.hasMore,
        ),
      );
    } catch (_) {
      // Resync best-effort: a próxima reconexão tenta de novo.
    }
  }

  void _applyEvent(RealtimeEvent event) {
    final current = state.valueOrNull;
    if (current == null) return;
    switch (event) {
      case MessageCreatedEvent(:final channelId, :final message):
        if (channelId != arg.channelId) return;
        if (current.messages.any((m) => m.id == message.id)) return; // dedupe
        state = AsyncData(
          current.copyWith(messages: [...current.messages, message]),
        );
      case MessageUpdatedEvent(:final channelId, :final message):
        if (channelId != arg.channelId) return;
        state = AsyncData(
          current.copyWith(
            messages: [
              for (final m in current.messages)
                if (m.id == message.id) message else m,
            ],
          ),
        );
      case MessageDeletedEvent(:final channelId, :final messageId):
        if (channelId != arg.channelId) return;
        state = AsyncData(
          current.copyWith(
            messages: [
              for (final m in current.messages)
                if (m.id != messageId) m,
            ],
          ),
        );
      case ChannelCreatedEvent() ||
          ChannelUpdatedEvent() ||
          ChannelDeletedEvent() ||
          MemberRemovedEvent() ||
          MemberRoleUpdatedEvent() ||
          PresenceChangedEvent() ||
          VoicePresenceChangedEvent():
        break; // não afetam a lista de mensagens
    }
  }
}

/// Provider do chat por `(serverId, channelId)` — autoDispose: sai do canal,
/// descarta o estado e cancela o listener.
final chatControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ChatController, ChatState, ({String serverId, String channelId})>(
      ChatController.new,
    );
