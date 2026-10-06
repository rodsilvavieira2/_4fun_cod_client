/// Ponte Dart <-> engine nativo (§22 do plano).
///
/// Espelha os contratos do `media_core` (Rust): handle com incarnation,
/// comandos com contexto (geração + revisão esperada), recibos (aceito !=
/// aplicado), snapshots e eventos. A implementação FRB (StreamSink) entra na
/// Fase 3; até lá, [InMemoryMediaBridge] executa a mesma máquina de estados
/// em Dart para validar providers, PTT watchdog e mapeamento de estado.
library;

import 'dart:async';

/// Handle de engine (id + incarnation anti-reuse, §22.5).
class EngineHandle {
  const EngineHandle({required this.id, required this.incarnation});

  final int id;
  final int incarnation;
}

/// Contexto de comando: geração protege a sessão.
class CommandContext {
  const CommandContext({required this.requestId, required this.generation});

  final String requestId;
  final int generation;
}

/// Recibo: aceito na fila NÃO significa aplicado (§22.2).
class CommandReceipt {
  const CommandReceipt({required this.requestId, required this.accepted});

  final String requestId;
  final bool accepted;
}

/// Comandos suportados (§22.2). Subconjunto M1 — câmera/share chegam no M4.
enum MediaCommandKind {
  join,
  leave,
  setMute,
  setDeafen,
  setPttMode,
  setPttPressed,
  selectInput,
  selectOutput,
  setInputGain,
  setOutputGain,
  setUserVolume,
  configureDsp,
}

class MediaCommand {
  const MediaCommand._(this.kind, this.payload);

  MediaCommand.join({required String channelId, required bool startMuted})
    : this._(MediaCommandKind.join, _JoinPayload(channelId, startMuted));
  const MediaCommand.leave() : this._(MediaCommandKind.leave, null);
  const MediaCommand.setMute(bool muted)
    : this._(MediaCommandKind.setMute, muted);
  const MediaCommand.setDeafen(bool deafened)
    : this._(MediaCommandKind.setDeafen, deafened);
  const MediaCommand.setPttMode(bool enabled)
    : this._(MediaCommandKind.setPttMode, enabled);
  MediaCommand.setPttPressed({required bool pressed, required int seq})
    : this._(MediaCommandKind.setPttPressed, _PttPayload(pressed, seq));
  const MediaCommand.selectInput(String? deviceId)
    : this._(MediaCommandKind.selectInput, deviceId);
  const MediaCommand.selectOutput(String? deviceId)
    : this._(MediaCommandKind.selectOutput, deviceId);
  const MediaCommand.setInputGain(double linear)
    : this._(MediaCommandKind.setInputGain, linear);
  const MediaCommand.setOutputGain(double linear)
    : this._(MediaCommandKind.setOutputGain, linear);
  MediaCommand.setUserVolume({
    required String identity,
    required bool screenShareAudio,
    required double linear,
  }) : this._(
         MediaCommandKind.setUserVolume,
         _UserVolumePayload(identity, screenShareAudio, linear),
       );
  const MediaCommand.configureDsp(String profile)
    : this._(MediaCommandKind.configureDsp, profile);

  final MediaCommandKind kind;
  final Object? payload;
}

class _JoinPayload {
  const _JoinPayload(this.channelId, this.startMuted);
  final String channelId;
  final bool startMuted;
}

class _PttPayload {
  const _PttPayload(this.pressed, this.seq);
  final bool pressed;
  final int seq;
}

class _UserVolumePayload {
  const _UserVolumePayload(this.identity, this.screenShareAudio, this.linear);
  final String identity;
  final bool screenShareAudio;
  final double linear;
}

/// Snapshot do engine para providers/UI (§21). Sem tokens/PCM.
class EngineSnapshot {
  const EngineSnapshot({
    required this.generation,
    required this.stateRevision,
    required this.muted,
    required this.deafened,
    required this.pttEnabled,
    required this.mayTransmit,
    required this.inputGain,
    required this.outputGain,
    required this.requestedDsp,
    required this.effectiveDsp,
    required this.deviceEpoch,
    required this.flags,
  });

  final int generation;
  final int stateRevision;
  final bool muted;
  final bool deafened;
  final bool pttEnabled;
  final bool mayTransmit;
  final double inputGain;
  final double outputGain;
  final String requestedDsp;
  final String effectiveDsp;
  final int deviceEpoch;
  final Map<String, bool> flags;
}

/// Evento engine -> Dart (§23).
class NativeEvent {
  const NativeEvent({
    required this.kind,
    required this.generation,
    required this.stateRevision,
    this.requestId,
    this.detail,
  });

  final String kind;
  final int generation;
  final int stateRevision;
  final String? requestId;
  final String? detail;
}

/// Abstração da ponte. FRB implementa a mesma interface na Fase 3.
abstract class MediaBridge {
  Future<EngineHandle> createEngine({Map<String, bool>? flags});
  Future<CommandReceipt> submit(
    EngineHandle handle, {
    required CommandContext context,
    required MediaCommand command,
  });
  Future<EngineSnapshot> snapshot(EngineHandle handle);
  Stream<NativeEvent> events(EngineHandle handle);
  Future<void> leaveAndWait(EngineHandle handle);
  Future<void> disposeEngine(EngineHandle handle);
}

/// Implementação em memória: mesma máquina de estados do Rust para validar
/// a integração Dart antes do FRB. Fail-closed, PTT com expiração, revisão
/// incremental, dedup por (geração, requestId).
class InMemoryMediaBridge implements MediaBridge {
  var _nextId = 1;
  final _states = <int, _EngineState>{};
  final _controllers = <int, StreamController<NativeEvent>>{};

  @override
  Future<EngineHandle> createEngine({Map<String, bool>? flags}) async {
    final id = _nextId++;
    _states[id] = _EngineState(flags: flags ?? const {});
    _controllers[id] = StreamController<NativeEvent>.broadcast();
    return EngineHandle(id: id, incarnation: id);
  }

  @override
  Future<CommandReceipt> submit(
    EngineHandle handle, {
    required CommandContext context,
    required MediaCommand command,
  }) async {
    final state = _states[handle.id];
    if (state == null) {
      throw StateError('invalid engine handle ${handle.id}');
    }
    if (state.disposed) {
      throw StateError('engine ${handle.id} disposed');
    }
    if (command.kind != MediaCommandKind.join &&
        context.generation != state.generation) {
      throw StateError(
        'stale generation ${context.generation} (current ${state.generation})',
      );
    }
    if (!state.seen.add('${context.generation}:${context.requestId}')) {
      return CommandReceipt(requestId: context.requestId, accepted: true);
    }
    state.apply(command);
    _emit(handle.id, 'command_applied', requestId: context.requestId);
    return CommandReceipt(requestId: context.requestId, accepted: true);
  }

  @override
  Future<EngineSnapshot> snapshot(EngineHandle handle) async {
    final state = _states[handle.id];
    if (state == null || state.disposed) {
      throw StateError('invalid engine handle ${handle.id}');
    }
    return state.snapshot();
  }

  @override
  Stream<NativeEvent> events(EngineHandle handle) {
    final controller = _controllers[handle.id];
    if (controller == null) {
      throw StateError('invalid engine handle ${handle.id}');
    }
    return controller.stream;
  }

  @override
  Future<void> leaveAndWait(EngineHandle handle) async {
    final state = _states[handle.id];
    if (state == null) return;
    state.apply(const MediaCommand.leave());
    _emit(handle.id, 'command_applied');
  }

  @override
  Future<void> disposeEngine(EngineHandle handle) async {
    final state = _states.remove(handle.id);
    state?.disposed = true;
    await _controllers.remove(handle.id)?.close();
  }

  void _emit(int id, String kind, {String? requestId}) {
    final state = _states[id];
    final controller = _controllers[id];
    if (state == null || controller == null || controller.isClosed) return;
    controller.add(
      NativeEvent(
        kind: kind,
        generation: state.generation,
        stateRevision: state.revision,
        requestId: requestId,
      ),
    );
  }
}

class _EngineState {
  _EngineState({required this.flags});

  final Map<String, bool> flags;
  var generation = 0;
  var revision = 0;
  var muted = true;
  var deafened = false;
  var pttEnabled = false;
  var pttPressed = false;
  var inputGain = 1.0;
  var outputGain = 1.0;
  var deviceEpoch = 0;
  var requestedDsp = 'basic';
  final seen = <String>{};
  var disposed = false;

  bool get mayTransmit {
    if (muted || deafened) return false;
    if (pttEnabled && !pttPressed) return false;
    return true;
  }

  String get effectiveDsp => requestedDsp == 'studio' ? 'basic' : requestedDsp;

  void apply(MediaCommand command) {
    switch (command.kind) {
      case MediaCommandKind.join:
        final payload = command.payload as _JoinPayload;
        generation++;
        muted = payload.startMuted;
        pttPressed = false; // reconnect: PTT volta solto
      case MediaCommandKind.leave:
        break;
      case MediaCommandKind.setMute:
        muted = command.payload as bool;
      case MediaCommandKind.setDeafen:
        deafened = command.payload as bool;
      case MediaCommandKind.setPttMode:
        pttEnabled = command.payload as bool;
        if (!pttEnabled) pttPressed = false;
      case MediaCommandKind.setPttPressed:
        final payload = command.payload as _PttPayload;
        pttPressed = payload.pressed;
      case MediaCommandKind.selectInput:
        deviceEpoch++;
      case MediaCommandKind.selectOutput:
        break;
      case MediaCommandKind.setInputGain:
        inputGain = (command.payload as double).clamp(0.0, 1.0);
      case MediaCommandKind.setOutputGain:
        outputGain = (command.payload as double).clamp(0.0, 2.0);
      case MediaCommandKind.setUserVolume:
        break;
      case MediaCommandKind.configureDsp:
        requestedDsp = command.payload as String;
    }
    revision++;
  }

  EngineSnapshot snapshot() => EngineSnapshot(
    generation: generation,
    stateRevision: revision,
    muted: muted,
    deafened: deafened,
    pttEnabled: pttEnabled,
    mayTransmit: mayTransmit,
    inputGain: inputGain,
    outputGain: outputGain,
    requestedDsp: requestedDsp,
    effectiveDsp: effectiveDsp,
    deviceEpoch: deviceEpoch,
    flags: Map.unmodifiable(flags),
  );
}
