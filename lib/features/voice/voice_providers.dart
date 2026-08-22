import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rtc/rtc_providers.dart';
import '../../core/rtc/rtc_service.dart';
import '../../shared/models/voice.dart';
import '../servers/servers_providers.dart';

/// Estado da sessão de voz de um canal.
enum VoiceSessionStatus { idle, connecting, connected, error }

/// Estado derivado do [RtcService] para o canal selecionado: status da
/// sessão, participantes ordenados (local primeiro, depois por nome) e o
/// estado do microfone LOCAL (para a barra de controles).
class VoiceState {
  const VoiceState({
    this.status = VoiceSessionStatus.idle,
    this.errorMessage,
    this.participants = const [],
    this.isMicrophoneEnabled = false,
  });

  final VoiceSessionStatus status;

  /// Mensagem amigável quando [status] é [VoiceSessionStatus.error].
  final String? errorMessage;

  /// Participantes da sala, local primeiro (ver [VoiceController._sort]).
  final List<RtcParticipant> participants;

  /// Se o microfone LOCAL está habilitado (espelho do botão mute; o
  /// participante local também aparece em [participants] com o mesmo
  /// estado, sincronizado pelos eventos do serviço).
  final bool isMicrophoneEnabled;

  VoiceState copyWith({
    VoiceSessionStatus? status,
    String? errorMessage,
    List<RtcParticipant>? participants,
    bool? isMicrophoneEnabled,
  }) {
    return VoiceState(
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      participants: participants ?? this.participants,
      isMicrophoneEnabled: isMicrophoneEnabled ?? this.isMicrophoneEnabled,
    );
  }
}

/// Sessão de voz de um canal (`autoDispose`): entrar/sair do canal,
/// mute/unmute e espelho dos participantes do [RtcService].
///
/// Ciclo de vida:
/// - [join]: `POST /servers/:id/channels/:id/join` (token emitido pelo
///   backend) + [RtcService.connect]. Se o connect falhar (token expirado
///   na janela POST→handshake, servidor fora), refaz o `/join` UMA vez com
///   token fresco e reconecta — é o papel do `tokenGenerator` do contrato,
///   já que o `livekit_client` 2.11.0 não tem suporte nativo a ele.
/// - [leave]: [RtcService.disconnect] e volta para `idle`.
/// - Troca de canal/fechamento da view: o `autoDispose` descarta o
///   provider e o `ref.onDispose` desconecta — o usuário nunca fica
///   "preso" numa sala depois de navegar para outro canal.
/// - Queda da sala por conta própria: [DisconnectedEvent] volta para
///   `idle` (o serviço já limpou o estado interno).
class VoiceController
    extends AutoDisposeFamilyNotifier<VoiceState,
        ({String serverId, String channelId})> {
  StreamSubscription<List<RtcParticipant>>? _participantsSub;
  StreamSubscription<RtcEvent>? _eventsSub;
  bool _disposed = false;

  @override
  VoiceState build(({String serverId, String channelId}) arg) {
    // Rebuild (invalidação/retry): o Riverpod reutiliza a instância do
    // notifier — zera o flag e cancela os listeners da build anterior.
    _disposed = false;
    _participantsSub?.cancel();
    _eventsSub?.cancel();

    final rtc = ref.watch(rtcServiceProvider);
    _participantsSub = rtc.participants.listen(_applyParticipants);
    _eventsSub = rtc.events.listen(_applyEvent);

    ref.onDispose(() {
      _disposed = true;
      _participantsSub?.cancel();
      _eventsSub?.cancel();
      // Sai da sala ao trocar de canal/fechar a view (autoDispose). O
      // `dispose` DEFINITIVO do serviço é do provider de ciclo de vida
      // (rtcServiceProvider); aqui apenas desconecta e limpa a sala.
      unawaited(rtc.disconnect());
    });

    return const VoiceState();
  }

  /// Entra no canal de voz: obtém token no backend e conecta no LiveKit.
  Future<void> join() async {
    final current = state;
    if (current.status == VoiceSessionStatus.connecting) return;
    state = current.copyWith(
      status: VoiceSessionStatus.connecting,
      errorMessage: null,
    );
    try {
      final info = await _freshJoinInfo();
      await _connect(info);
    } catch (_) {
      if (_disposed) return;
      state = state.copyWith(
        status: VoiceSessionStatus.error,
        errorMessage: 'Não foi possível entrar no canal de voz.',
      );
    }
  }

  /// Sai do canal de voz e volta para `idle`.
  Future<void> leave() async {
    await ref.read(rtcServiceProvider).disconnect();
    if (_disposed) return;
    state = state.copyWith(
      status: VoiceSessionStatus.idle,
      participants: const [],
      isMicrophoneEnabled: false,
      errorMessage: null,
    );
  }

  /// Liga/desliga o microfone local (botão da barra de controles).
  Future<void> toggleMicrophone() async {
    final current = state;
    if (current.status != VoiceSessionStatus.connected) return;
    final rtc = ref.read(rtcServiceProvider);
    try {
      if (current.isMicrophoneEnabled) {
        await rtc.disableMicrophone();
      } else {
        await rtc.enableMicrophone();
      }
    } catch (_) {
      // Falha de hardware/permissão: não derruba a sessão; volta para o
      // estado anterior (sem otimismo) e avisa o usuário.
      if (_disposed) return;
      state = state.copyWith(
        status: VoiceSessionStatus.connected,
        isMicrophoneEnabled: current.isMicrophoneEnabled,
        errorMessage: 'Não foi possível alternar o microfone.',
      );
      return;
    }
    // Otimista para o botão; os eventos MicEnabledChangedEvent do
    // participante local reconciliam com o estado real do LiveKit.
    if (_disposed) return;
    state = state.copyWith(
      isMicrophoneEnabled: !current.isMicrophoneEnabled,
      errorMessage: null,
    );
  }

  /// `POST /join` → informações para conectar (token de 10m do backend).
  Future<VoiceJoinInfo> _freshJoinInfo() {
    return ref
        .read(serversRepositoryProvider)
        .joinVoice(arg.serverId, arg.channelId);
  }

  /// Conecta no RtcService com o token do [VoiceJoinInfo]; se o connect
  /// falhar, refaz o `/join` uma vez e reconecta com token fresco (janela
  /// POST→handshake pode estourar o token; o `tokenGenerator` do contrato
  /// cobre reconexões futuras do mesmo jeito).
  Future<void> _connect(VoiceJoinInfo info) async {
    final rtc = ref.read(rtcServiceProvider);
    try {
      await rtc.connect(
        info.livekitUrl,
        info.token,
        tokenGenerator: _tokenGenerator,
      );
    } catch (_) {
      if (_disposed) return;
      try {
        final fresh = await _freshJoinInfo();
        await rtc.connect(
          fresh.livekitUrl,
          fresh.token,
          tokenGenerator: _tokenGenerator,
        );
      } catch (_) {
        if (_disposed) return;
        state = state.copyWith(
          status: VoiceSessionStatus.error,
          errorMessage: 'Não foi possível entrar no canal de voz.',
        );
        return;
      }
    }
    if (_disposed) return;
    // O mic entra publicado MUTADO por padrão (decisão da Fase 4).
    state = state.copyWith(
      status: VoiceSessionStatus.connected,
      isMicrophoneEnabled: false,
    );
  }

  /// Token fresco para reconexões futuras (o LiveKit 2.11.0 não tem
  /// tokenGenerator nativo — o controller o usa em retries manuais).
  Future<String> _tokenGenerator() => _freshJoinInfo().then((i) => i.token);

  void _applyParticipants(List<RtcParticipant> list) {
    if (_disposed) return;
    final localId = ref.read(rtcServiceProvider).localParticipantId;
    state = state.copyWith(participants: _sort(list, localId));
  }

  void _applyEvent(RtcEvent event) {
    if (_disposed) return;
    switch (event) {
      case DisconnectedEvent():
        // Sala caiu sozinha (servidor/rede): o serviço já limpou o estado;
        // volta para idle para permitir nova entrada.
        state = state.copyWith(
          status: VoiceSessionStatus.idle,
          participants: const [],
          isMicrophoneEnabled: false,
          errorMessage: null,
        );
      case MicEnabledChangedEvent(
          :final participantId,
          :final isMicrophoneEnabled,
        ):
        final localId = ref.read(rtcServiceProvider).localParticipantId;
        if (participantId == localId &&
            state.isMicrophoneEnabled != isMicrophoneEnabled) {
          state = state.copyWith(isMicrophoneEnabled: isMicrophoneEnabled);
        }
      case ParticipantJoinedEvent() ||
          ParticipantLeftEvent() ||
          SpeakingChangedEvent() ||
          CameraEnabledChangedEvent():
        break; // o snapshot de participants já reflete tudo
    }
  }

  /// Participantes ordenados: local primeiro (identidade visual no painel),
  /// depois por nome — ordem estável independente da ordem dos eventos.
  /// Se o local ainda não chegou no snapshot (corrida pós-connect), ordena
  /// só os demais — o próximo snapshot com o local corrige a posição.
  List<RtcParticipant> _sort(List<RtcParticipant> list, String? localId) {
    if (list.length < 2) return list;
    final local = localId == null
        ? const <RtcParticipant>[]
        : list.where((p) => p.id == localId).toList();
    final others = [
      for (final p in list)
        if (p.id != localId) p,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return [...local, ...others];
  }
}

/// Sessão de voz do canal — `autoDispose.family`: ao trocar de canal (ou
/// sair da view), o provider é descartado e o controller desconecta.
final voiceControllerProvider = AutoDisposeNotifierProvider.family<
    VoiceController, VoiceState, ({String serverId, String channelId})>(
  VoiceController.new,
);
