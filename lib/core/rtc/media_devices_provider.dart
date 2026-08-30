import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'rtc_providers.dart';
import 'rtc_service.dart';

/// Estado local das preferências de entrada e saída de áudio.
///
/// `preferred...Id` é o id salvo pelo usuário. Quando o dispositivo não está
/// conectado, ele continua salvo e a aplicação usa o padrão do sistema até
/// ele reaparecer.
class AudioDevicesState {
  const AudioDevicesState({
    this.inputs = const [],
    this.outputs = const [],
    this.cameras = const [],
    this.preferredInputId,
    this.preferredOutputId,
    this.preferredCameraId,
    this.isLoading = true,
    this.errorMessage,
  });

  final List<RtcAudioDevice> inputs;
  final List<RtcAudioDevice> outputs;
  final List<RtcVideoDevice> cameras;
  final String? preferredInputId;
  final String? preferredOutputId;
  final String? preferredCameraId;
  final bool isLoading;
  final String? errorMessage;

  bool get preferredInputUnavailable =>
      preferredInputId != null && !inputs.any((d) => d.id == preferredInputId);

  bool get preferredOutputUnavailable =>
      preferredOutputId != null &&
      !outputs.any((d) => d.id == preferredOutputId);

  bool get preferredCameraUnavailable =>
      preferredCameraId != null &&
      !cameras.any((d) => d.id == preferredCameraId);

  AudioDevicesState copyWith({
    List<RtcAudioDevice>? inputs,
    List<RtcAudioDevice>? outputs,
    List<RtcVideoDevice>? cameras,
    Object? preferredInputId = _unset,
    Object? preferredOutputId = _unset,
    Object? preferredCameraId = _unset,
    bool? isLoading,
    Object? errorMessage = _unset,
  }) {
    return AudioDevicesState(
      inputs: inputs ?? this.inputs,
      outputs: outputs ?? this.outputs,
      cameras: cameras ?? this.cameras,
      preferredInputId: identical(preferredInputId, _unset)
          ? this.preferredInputId
          : preferredInputId as String?,
      preferredOutputId: identical(preferredOutputId, _unset)
          ? this.preferredOutputId
          : preferredOutputId as String?,
      preferredCameraId: identical(preferredCameraId, _unset)
          ? this.preferredCameraId
          : preferredCameraId as String?,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

const Object _unset = Object();

/// Fonte de verdade para os seletores de áudio do painel e do modal.
///
/// O provider não é auto-dispose: as preferências precisam permanecer prontas
/// para o próximo join mesmo após sair de uma tela de voz.
class AudioDevicesController extends Notifier<AudioDevicesState> {
  static const _inputKey = 'voice.preferred_audio_input_id';
  static const _outputKey = 'voice.preferred_audio_output_id';
  static const _cameraKey = 'voice.preferred_video_input_id';

  StreamSubscription<void>? _deviceChanges;
  SharedPreferences? _preferences;
  Future<void>? _initialization;
  bool _disposed = false;

  @override
  AudioDevicesState build() {
    ref.onDispose(() {
      _disposed = true;
      _deviceChanges?.cancel();
    });
    _initialization = _initialize();
    unawaited(_initialization!);
    return const AudioDevicesState();
  }

  /// Garante que preferências persistidas foram aplicadas antes de uma sala
  /// publicar o microfone pela primeira vez.
  Future<void> ensureInitialized() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (_disposed) return;
      _preferences = preferences;
      state = state.copyWith(
        preferredInputId: preferences.getString(_inputKey),
        preferredOutputId: preferences.getString(_outputKey),
        preferredCameraId: preferences.getString(_cameraKey),
      );
      _deviceChanges = ref
          .read(rtcServiceProvider)
          .mediaDevicesChanged
          .listen((_) => unawaited(refresh()));
      await refresh();
    } catch (_) {
      if (_disposed) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Não foi possível carregar os dispositivos de áudio.',
      );
    }
  }

  Future<void> refresh() async {
    final rtc = ref.read(rtcServiceProvider);
    if (_disposed) return;
    state = state.copyWith(isLoading: true, errorMessage: null);

    final inputsFuture = _load(rtc.listAudioInputDevices);
    final outputsFuture = _load(rtc.listAudioOutputDevices);
    final camerasFuture = _load(rtc.listCameraDevices);
    final inputs = await inputsFuture;
    final outputs = await outputsFuture;
    final cameras = await camerasFuture;
    if (_disposed) return;

    final messages = <String>[];
    if (inputs.failed) {
      messages.add('Não foi possível listar os microfones.');
    }
    if (outputs.failed) {
      messages.add('Não foi possível listar as saídas de áudio.');
    }
    if (cameras.failed) {
      messages.add('Não foi possível listar as câmeras.');
    }
    state = state.copyWith(
      inputs: inputs.value ?? state.inputs,
      outputs: outputs.value ?? state.outputs,
      cameras: cameras.value ?? state.cameras,
      isLoading: false,
      errorMessage: messages.isEmpty ? null : messages.join(' '),
    );

    // Id indisponível não é apagado: aplica o padrão do sistema agora e a
    // preferência volta automaticamente quando o device retornar.
    try {
      await rtc.selectAudioInput(
        state.preferredInputUnavailable ? null : state.preferredInputId,
      );
    } catch (_) {
      messages.add('Não foi possível aplicar o microfone preferido.');
    }
    try {
      await rtc.selectAudioOutput(
        state.preferredOutputUnavailable ? null : state.preferredOutputId,
      );
    } catch (_) {
      messages.add('Não foi possível aplicar a saída de áudio preferida.');
    }
    try {
      if (!state.preferredCameraUnavailable &&
          state.preferredCameraId != null) {
        await rtc.switchCamera(state.preferredCameraId!);
      }
    } catch (_) {
      messages.add('Não foi possível aplicar a câmera preferida.');
    }
    if (_disposed) return;
    if (messages.isNotEmpty) {
      state = state.copyWith(errorMessage: messages.join(' '));
    }
  }

  Future<_LoadResult<T>> _load<T>(Future<T> Function() load) async {
    try {
      return _LoadResult.success(await load());
    } catch (_) {
      return const _LoadResult.failure();
    }
  }

  Future<bool> selectInput(String? deviceId) async {
    return _select(
      deviceId: deviceId,
      selector: ref.read(rtcServiceProvider).selectAudioInput,
      save: (preferences) => deviceId == null
          ? preferences.remove(_inputKey)
          : preferences.setString(_inputKey, deviceId),
      update: () => state = state.copyWith(
        preferredInputId: deviceId,
        errorMessage: null,
      ),
      error: 'Não foi possível trocar o microfone.',
    );
  }

  Future<bool> selectOutput(String? deviceId) async {
    return _select(
      deviceId: deviceId,
      selector: ref.read(rtcServiceProvider).selectAudioOutput,
      save: (preferences) => deviceId == null
          ? preferences.remove(_outputKey)
          : preferences.setString(_outputKey, deviceId),
      update: () => state = state.copyWith(
        preferredOutputId: deviceId,
        errorMessage: null,
      ),
      error: 'Não foi possível trocar a saída de áudio.',
    );
  }

  Future<bool> selectCamera(String deviceId) async {
    return _select(
      deviceId: deviceId,
      selector: (id) => ref.read(rtcServiceProvider).switchCamera(id!),
      save: (preferences) => preferences.setString(_cameraKey, deviceId),
      update: () => state = state.copyWith(
        preferredCameraId: deviceId,
        errorMessage: null,
      ),
      error: 'Não foi possível trocar a câmera.',
    );
  }

  Future<bool> _select({
    required String? deviceId,
    required Future<void> Function(String?) selector,
    required Future<bool> Function(SharedPreferences preferences) save,
    required void Function() update,
    required String error,
  }) async {
    try {
      await selector(deviceId);
      final preferences = _preferences;
      if (preferences != null) await save(preferences);
      if (_disposed) return false;
      update();
      return true;
    } catch (_) {
      if (_disposed) return false;
      state = state.copyWith(errorMessage: error);
      return false;
    }
  }
}

class _LoadResult<T> {
  const _LoadResult.success(this.value) : failed = false;

  const _LoadResult.failure() : value = null, failed = true;

  final T? value;
  final bool failed;
}

final audioDevicesProvider =
    NotifierProvider<AudioDevicesController, AudioDevicesState>(
      AudioDevicesController.new,
    );
