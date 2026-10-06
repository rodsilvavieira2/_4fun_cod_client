/// Adapter nativo — caminho A (§30 Fase 3 do plano).
///
/// Room Flutter (transporte [LiveKitRtcService]) + decisões locais de TX
/// (mute/deafen/PTT/volumes/DSP/devices) espelhadas no engine nativo via
/// [MediaBridge]. O engine é a fonte de verdade da autorização de envio;
/// o transporte legado move os bytes. Rollback = voltar ao `inner` direto,
/// sem conexões concorrentes.
///
/// Caminho B (Room C++ única) assume este mesmo contrato quando o adapter
/// de vídeo estiver validado — a UI não muda.
library;

// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'media_backend_selector.dart';
import '../native/media/media_bridge.dart';
import 'rtc_service.dart';

/// [RtcService] nativo (caminho A). Construído sob demanda quando
/// [MediaBackendConfig.effectiveBackend] != legacy.
class NativeRtcService implements RtcService {
  NativeRtcService({
    required RtcService inner,
    required MediaBridge bridge,
    required MediaBackendConfig config,
    void Function()? onDispose,
  }) : _inner = inner,
       _bridge = bridge,
       _config = config,
       _onDispose = onDispose;

  final RtcService _inner;
  final MediaBridge _bridge;
  MediaBackendConfig _config;
  final void Function()? _onDispose;

  EngineHandle? _handle;
  var _generation = 0;
  var _requestSeq = 0;
  var _disposed = false;

  /// Atualiza flags em runtime (vale para a próxima sessão).
  void updateConfig(MediaBackendConfig config) {
    _config = config;
  }

  MediaBackend get backend => _config.effectiveBackend;

  String _nextRequestId() => 'req-${++_requestSeq}';

  Future<EngineHandle> _ensureEngine() async {
    final existing = _handle;
    if (existing != null) return existing;
    final handle = await _bridge.createEngine(flags: _config.toFlagMap());
    _handle = handle;
    return handle;
  }

  Future<void> _submit(MediaCommand command) async {
    final handle = await _ensureEngine();
    await _bridge.submit(
      handle,
      context: CommandContext(
        requestId: _nextRequestId(),
        generation: _generation,
      ),
      command: command,
    );
  }

  /// Snapshot atual do engine (diagnóstico, §26).
  Future<EngineSnapshot> currentSnapshot() async {
    final handle = _handle;
    if (handle == null) throw StateError('engine not created');
    return _bridge.snapshot(handle);
  }

  @override
  Future<void> connect(
    String url,
    String token, {
    RtcTokenGenerator? tokenGenerator,
  }) async {
    if (_disposed) throw StateError('NativeRtcService disposed');
    final handle = await _ensureEngine();
    _generation++;
    await _bridge.submit(
      handle,
      context: CommandContext(requestId: _nextRequestId(), generation: 0),
      command: MediaCommand.join(channelId: 'voice', startMuted: true),
    );
    await _inner.connect(url, token, tokenGenerator: tokenGenerator);
  }

  @override
  Future<void> disconnect() async {
    final handle = _handle;
    if (handle != null) {
      await _bridge.leaveAndWait(handle);
    }
    await _inner.disconnect();
  }

  /// Fecha TX + transporte. Idempotente.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final handle = _handle;
    _handle = null;
    if (handle != null) {
      await _bridge.disposeEngine(handle);
    }
    _onDispose?.call();
  }

  @override
  Future<void> enableMicrophone() async {
    // Caminho A: o engine espelha a intenção (fonte de diagnóstico e do
    // gate TX nativo na Fase 3); os bytes seguem pelo transporte legado.
    await _submit(const MediaCommand.setMute(false));
    await _inner.enableMicrophone();
  }

  @override
  Future<void> disableMicrophone() async {
    await _submit(const MediaCommand.setMute(true));
    await _inner.disableMicrophone();
  }

  @override
  Future<void> enableCamera() => _inner.enableCamera();

  @override
  Future<void> disableCamera() => _inner.disableCamera();

  @override
  Future<RtcVideoTrackRef> startCameraPreview({String? deviceId}) =>
      _inner.startCameraPreview(deviceId: deviceId);

  @override
  Future<void> stopCameraPreview() => _inner.stopCameraPreview();

  @override
  Future<void> startScreenShare(
    String? sourceId, {
    bool includeSystemAudio = true,
    RtcScreenShareQuality? quality,
  }) => _inner.startScreenShare(
    sourceId,
    includeSystemAudio: includeSystemAudio,
    quality: quality,
  );

  @override
  Future<void> stopScreenShare() => _inner.stopScreenShare();

  @override
  RtcVideoTrackRef? screenTrackOf(String participantId) =>
      _inner.screenTrackOf(participantId);

  @override
  Future<void> setQuality(String participantId, RtcVideoQuality quality) =>
      _inner.setQuality(participantId, quality);

  @override
  Future<void> setScreenQuality(
    String participantId,
    RtcVideoQuality quality,
  ) => _inner.setScreenQuality(participantId, quality);

  @override
  Future<List<RtcVideoDevice>> listCameraDevices() =>
      _inner.listCameraDevices();

  @override
  Future<List<RtcAudioDevice>> listAudioInputDevices() =>
      _inner.listAudioInputDevices();

  @override
  Future<List<RtcAudioDevice>> listAudioOutputDevices() =>
      _inner.listAudioOutputDevices();

  @override
  Stream<void> get mediaDevicesChanged => _inner.mediaDevicesChanged;

  @override
  Future<void> selectAudioInput(String? deviceId) async {
    await _submit(MediaCommand.selectInput(deviceId));
    await _inner.selectAudioInput(deviceId);
  }

  @override
  Future<void> selectAudioOutput(String? deviceId) async {
    await _submit(MediaCommand.selectOutput(deviceId));
    await _inner.selectAudioOutput(deviceId);
  }

  @override
  Future<void> setRemoteAudioEnabled(bool enabled) =>
      _inner.setRemoteAudioEnabled(enabled);

  @override
  Future<void> setOutputVolume(double gain) async {
    await _submit(MediaCommand.setOutputGain(gain));
    await _inner.setOutputVolume(gain);
  }

  @override
  Future<void> setInputVolume(double gain) async {
    await _submit(MediaCommand.setInputGain(gain));
    await _inner.setInputVolume(gain);
  }

  @override
  Future<RtcNoiseSuppressionStatus> setNoiseSuppressionMode(
    RtcNoiseSuppressionMode mode,
  ) async {
    await _submit(
      MediaCommand.configureDsp(switch (mode) {
        RtcNoiseSuppressionMode.studio => 'studio',
        RtcNoiseSuppressionMode.webrtc => 'basic',
        RtcNoiseSuppressionMode.off => 'minimal',
      }),
    );
    return _inner.setNoiseSuppressionMode(mode);
  }

  @override
  Future<void> setParticipantVolume(String identity, double gain) async {
    await _submit(
      MediaCommand.setUserVolume(
        identity: identity,
        screenShareAudio: false,
        linear: gain,
      ),
    );
    await _inner.setParticipantVolume(identity, gain);
  }

  @override
  Future<void> setParticipantSourceVolume(
    String identity,
    RtcAudioSource source,
    double gain,
  ) async {
    await _submit(
      MediaCommand.setUserVolume(
        identity: identity,
        screenShareAudio: source == RtcAudioSource.screenShareAudio,
        linear: gain,
      ),
    );
    await _inner.setParticipantSourceVolume(identity, source, gain);
  }

  @override
  Future<void> setScreenShareAudioEnabled(String identity, bool enabled) =>
      _inner.setScreenShareAudioEnabled(identity, enabled);

  @override
  Future<void> publishVoiceSound(RtcVoiceSound sound) =>
      _inner.publishVoiceSound(sound);

  @override
  Future<void> switchCamera(String deviceId) =>
      _inner.switchCamera(deviceId);

  @override
  Future<void> setScreenShareQuality(RtcScreenShareQuality quality) =>
      _inner.setScreenShareQuality(quality);

  @override
  RtcScreenShareQuality get screenShareQuality => _inner.screenShareQuality;

  @override
  RtcScreenShareQuality get effectiveScreenShareQuality =>
      _inner.effectiveScreenShareQuality;

  @override
  Future<void> resumeAudio() => _inner.resumeAudio();

  @override
  RtcVideoTrackRef? videoTrackOf(String participantId) =>
      _inner.videoTrackOf(participantId);

  @override
  String? get localParticipantId => _inner.localParticipantId;

  @override
  Stream<List<RtcParticipant>> get participants => _inner.participants;

  @override
  Stream<RtcEvent> get events => _inner.events;
}
