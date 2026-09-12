import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/app_logger.dart';
import '../../core/rtc/rtc_providers.dart';
import 'push_to_talk.dart';
import 'push_to_talk_input.dart';

class VoiceControlsState {
  const VoiceControlsState({
    this.isMuted = false,
    this.isDeafened = false,
    this.isPushToTalkEnabled = false,
    this.pushToTalkBinding,
    this.pushToTalkReleaseDelayMs = 20,
    this.isPushToTalkPressed = false,
    this.isPushToTalkRegistered = false,
    this.isRecordingPushToTalk = false,
    this.isApplying = false,
    this.errorMessage,
  });

  final bool isMuted;
  final bool isDeafened;
  final bool isPushToTalkEnabled;
  final PushToTalkBinding? pushToTalkBinding;
  final int pushToTalkReleaseDelayMs;
  final bool isPushToTalkPressed;
  final bool isPushToTalkRegistered;
  final bool isRecordingPushToTalk;
  final bool isApplying;
  final String? errorMessage;

  bool get isMicrophoneEnabled =>
      !isMuted && !isDeafened && (!isPushToTalkEnabled || isPushToTalkPressed);

  VoiceControlsState copyWith({
    bool? isMuted,
    bool? isDeafened,
    bool? isPushToTalkEnabled,
    Object? pushToTalkBinding = _unset,
    int? pushToTalkReleaseDelayMs,
    bool? isPushToTalkPressed,
    bool? isPushToTalkRegistered,
    bool? isRecordingPushToTalk,
    bool? isApplying,
    Object? errorMessage = _unset,
  }) => VoiceControlsState(
    isMuted: isMuted ?? this.isMuted,
    isDeafened: isDeafened ?? this.isDeafened,
    isPushToTalkEnabled: isPushToTalkEnabled ?? this.isPushToTalkEnabled,
    pushToTalkBinding: identical(pushToTalkBinding, _unset)
        ? this.pushToTalkBinding
        : pushToTalkBinding as PushToTalkBinding?,
    pushToTalkReleaseDelayMs:
        pushToTalkReleaseDelayMs ?? this.pushToTalkReleaseDelayMs,
    isPushToTalkPressed: isPushToTalkPressed ?? this.isPushToTalkPressed,
    isPushToTalkRegistered:
        isPushToTalkRegistered ?? this.isPushToTalkRegistered,
    isRecordingPushToTalk: isRecordingPushToTalk ?? this.isRecordingPushToTalk,
    isApplying: isApplying ?? this.isApplying,
    errorMessage: identical(errorMessage, _unset)
        ? this.errorMessage
        : errorMessage as String?,
  );
}

const Object _unset = Object();

String _describePushToTalkBinding(PushToTalkBinding? binding) {
  if (binding == null) return 'nenhum';
  return '${binding.kind.name}:${binding.displayLabel} '
      'usage=${binding.physicalKeyUsage ?? '-'} '
      'mouse=${binding.mouseButton ?? '-'} '
      'ctrl=${binding.control} alt=${binding.alt} shift=${binding.shift}';
}

/// Persiste o mute manual, ensurdecer e Push to Talk. PTT é uma porta extra:
/// ele nunca desfaz mute/ensurdecer e só abre o microfone enquanto pressionado.
class VoiceControlsController extends Notifier<VoiceControlsState> {
  static const _mutedKey = 'voice.microphone_muted';
  static const _deafenedKey = 'voice.deafened';
  static const _pttEnabledKey = 'voice.push_to_talk.enabled';
  static const _pttBindingKey = 'voice.push_to_talk.binding';
  static const _pttReleaseDelayKey = 'voice.push_to_talk.release_delay_ms';

  SharedPreferences? _preferences;
  Future<void>? _initialization;
  Timer? _releaseTimer;
  late PushToTalkInputService _inputService;
  final PushToTalkChordRecorder _chordRecorder = PushToTalkChordRecorder();
  bool _enableAfterRecording = false;
  bool _disposed = false;

  @override
  VoiceControlsState build() {
    _inputService = ref.read(pushToTalkInputServiceProvider);
    _logPtt('controller inicializado');
    ref.onDispose(() {
      _disposed = true;
      _releaseTimer?.cancel();
    });
    _initialization = _initialize();
    unawaited(_initialization!);
    return const VoiceControlsState();
  }

  Future<void> ensureInitialized() => _initialization ??= _initialize();

  void _logPtt(String message) {
    if (_disposed) return;
    try {
      ref.read(appLoggerProvider).d(message, tag: 'ptt');
    } catch (_) {
      // O log é diagnóstico; nunca deve interferir no fluxo de voz.
    }
  }

  void _warnPtt(String message) {
    if (_disposed) return;
    try {
      ref.read(appLoggerProvider).w(message, tag: 'ptt');
    } catch (_) {}
  }

  void _errorPtt(String message, Object error, StackTrace stackTrace) {
    if (_disposed) return;
    try {
      ref
          .read(appLoggerProvider)
          .e(message, error: error, stackTrace: stackTrace, tag: 'ptt');
    } catch (_) {}
  }

  Future<void> _initialize() async {
    try {
      _logPtt('initialize: lendo preferências salvas');
      final preferences = await SharedPreferences.getInstance();
      final binding = _decodeBinding(preferences.getString(_pttBindingKey));
      final wasEnabled = preferences.getBool(_pttEnabledKey) ?? false;
      final pushToTalkEnabled = wasEnabled && binding != null;
      final restoredMuted = preferences.getBool(_mutedKey) ?? false;
      final restoredDeafened = preferences.getBool(_deafenedKey) ?? false;
      final delay = (preferences.getInt(_pttReleaseDelayKey) ?? 20).clamp(
        0,
        2000,
      );
      if (_disposed) return;
      _preferences = preferences;
      _logPtt(
        'initialize: restoredMuted=$restoredMuted '
        'restoredDeafened=$restoredDeafened wasPttEnabled=$wasEnabled '
        'effectivePttEnabled=$pushToTalkEnabled delayMs=$delay '
        'binding=${_describePushToTalkBinding(binding)}',
      );
      if (wasEnabled && binding == null) {
        _warnPtt(
          'initialize: PTT estava ativo, mas o binding salvo é inválido',
        );
      }
      state = state.copyWith(
        isMuted: pushToTalkEnabled ? false : restoredMuted,
        isDeafened: restoredDeafened,
        isPushToTalkEnabled: pushToTalkEnabled,
        pushToTalkBinding: binding,
        pushToTalkReleaseDelayMs: delay,
        errorMessage: wasEnabled && binding == null
            ? 'Push to Talk precisa de um atalho configurado.'
            : null,
      );
      if (pushToTalkEnabled && restoredMuted) {
        _logPtt('initialize: limpando mute manual antigo para PTT restaurado');
        await preferences.setBool(_mutedKey, false);
      }
      if (state.isPushToTalkEnabled) await _registerPushToTalk(binding!);
      await _applyToRtc();
      _logPtt('initialize: concluído');
    } catch (error, stackTrace) {
      _errorPtt(
        'initialize: falha ao restaurar controles de voz',
        error,
        stackTrace,
      );
      if (!_disposed) {
        state = state.copyWith(
          errorMessage: 'Não foi possível restaurar os controles de voz.',
        );
      }
    }
  }

  PushToTalkBinding? _decodeBinding(String? encoded) {
    if (encoded == null) return null;
    try {
      return PushToTalkBinding.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );
    } catch (error) {
      _warnPtt('decode binding: JSON inválido (${error.runtimeType})');
      return null;
    }
  }

  Future<bool> toggleMicrophone() async {
    await ensureInitialized();
    if (state.isApplying || state.isDeafened) {
      _logPtt(
        'toggle mic ignorado: applying=${state.isApplying} '
        'deafened=${state.isDeafened}',
      );
      return false;
    }
    _logPtt('toggle mic: próximo muted=${!state.isMuted}');
    return _change(isMuted: !state.isMuted, isDeafened: state.isDeafened);
  }

  Future<bool> toggleDeafen() async {
    await ensureInitialized();
    if (state.isApplying) {
      _logPtt('toggle deafen ignorado: applying=true');
      return false;
    }
    if (!state.isDeafened) _cancelPress();
    _logPtt('toggle deafen: próximo deafened=${!state.isDeafened}');
    return _change(isMuted: state.isMuted, isDeafened: !state.isDeafened);
  }

  Future<bool> _change({
    required bool isMuted,
    required bool isDeafened,
  }) async {
    final previous = state;
    _logPtt('change voice: muted=$isMuted deafened=$isDeafened');
    state = previous.copyWith(isApplying: true, errorMessage: null);
    try {
      await _applyToRtc(isMuted: isMuted, isDeafened: isDeafened);
    } catch (error, stackTrace) {
      _errorPtt('change voice: aplicação no RTC falhou', error, stackTrace);
      try {
        await _applyToRtc(
          isMuted: previous.isMuted,
          isDeafened: previous.isDeafened,
        );
      } catch (rollbackError, rollbackStackTrace) {
        _errorPtt(
          'change voice: rollback no RTC também falhou',
          rollbackError,
          rollbackStackTrace,
        );
      }
      if (!_disposed) {
        state = previous.copyWith(
          isApplying: false,
          errorMessage: isDeafened != previous.isDeafened
              ? 'Não foi possível alterar o ensurdecer.'
              : 'Não foi possível alternar o microfone.',
        );
      }
      return false;
    }
    await _saveManual(isMuted: isMuted, isDeafened: isDeafened);
    if (!_disposed) {
      state = state.copyWith(
        isMuted: isMuted,
        isDeafened: isDeafened,
        isApplying: false,
        errorMessage: null,
      );
    }
    _logPtt('change voice: concluído');
    return true;
  }

  Future<void> _saveManual({
    required bool isMuted,
    required bool isDeafened,
  }) async {
    final preferences = _preferences;
    if (preferences == null) return;
    try {
      await preferences.setBool(_mutedKey, isMuted);
      await preferences.setBool(_deafenedKey, isDeafened);
      _logPtt('save manual: muted=$isMuted deafened=$isDeafened');
    } catch (error, stackTrace) {
      _errorPtt(
        'save manual: falha ao persistir preferências',
        error,
        stackTrace,
      );
      if (!_disposed) {
        state = state.copyWith(
          errorMessage: 'Não foi possível salvar os controles de voz.',
        );
      }
    }
  }

  Future<bool> setPushToTalkEnabled(bool enabled) async {
    await ensureInitialized();
    _logPtt(
      'set enabled: requested=$enabled current=${state.isPushToTalkEnabled} '
      'registered=${state.isPushToTalkRegistered} '
      'binding=${_describePushToTalkBinding(state.pushToTalkBinding)}',
    );
    if (!enabled) {
      _enableAfterRecording = false;
      await resetPushToTalkPress();
      _logPtt('set enabled: removendo configuração nativa');
      await _inputService.configure(null);
      state = state.copyWith(
        isPushToTalkEnabled: false,
        isPushToTalkRegistered: false,
        isRecordingPushToTalk: false,
        errorMessage: null,
      );
      await _savePushToTalk();
      await _applyToRtc();
      _logPtt('set enabled: PTT desativado');
      return true;
    }
    if (state.pushToTalkBinding == null) {
      _enableAfterRecording = true;
      _logPtt(
        'set enabled: sem binding, iniciando gravação e ativando ao capturar',
      );
      startPushToTalkRecording();
      return false;
    }
    state = state.copyWith(
      isMuted: false,
      isPushToTalkEnabled: true,
      isPushToTalkPressed: false,
      errorMessage: null,
    );
    await _saveManual(isMuted: false, isDeafened: state.isDeafened);
    if (!await _registerPushToTalk(state.pushToTalkBinding!)) {
      _warnPtt(
        'set enabled: registro global falhou; fallback em foco segue disponível',
      );
      return false;
    }
    await _savePushToTalk();
    await _applyToRtc();
    _logPtt('set enabled: PTT ativo');
    return true;
  }

  void startPushToTalkRecording({bool enableAfterCapture = false}) {
    _logPtt(
      'recording: iniciar enableAfterCapture=$enableAfterCapture '
      'wasPressed=${state.isPushToTalkPressed}',
    );
    _cancelPress();
    if (enableAfterCapture) _enableAfterRecording = true;
    _chordRecorder.reset();
    state = state.copyWith(
      isRecordingPushToTalk: true,
      isPushToTalkPressed: false,
      errorMessage: null,
    );
    unawaited(_applyToRtc());
  }

  void cancelPushToTalkRecording() {
    _logPtt('recording: cancelar');
    _enableAfterRecording = false;
    _chordRecorder.reset();
    state = state.copyWith(isRecordingPushToTalk: false);
  }

  /// Gravação por chord: acumula teclas em qualquer ordem e confirma ao
  /// soltar. `control`/`alt`/`shift`/`meta` permitem injeção em testes; quando
  /// omitidos, refletem o [HardwareKeyboard] atual.
  Future<void> recordPushToTalkKey(
    KeyEvent event, {
    bool? control,
    bool? alt,
    bool? shift,
    bool? meta,
  }) async {
    await ensureInitialized();
    if (!state.isRecordingPushToTalk) return;
    if (event is KeyRepeatEvent) return;
    if (event is! KeyDownEvent && event is! KeyUpEvent) return;
    final keyboard = HardwareKeyboard.instance;
    final snapshot = (
      control: control ?? keyboard.isControlPressed,
      alt: alt ?? keyboard.isAltPressed,
      shift: shift ?? keyboard.isShiftPressed,
      meta: meta ?? keyboard.isMetaPressed,
    );
    final key = PushToTalkChordKey(
      usage: event.physicalKey.usbHidUsage,
      label: event.logicalKey.keyLabel,
      isModifier: isModifierKey(event.logicalKey),
      isEscape: event.logicalKey == LogicalKeyboardKey.escape,
      isClearKey:
          event.logicalKey == LogicalKeyboardKey.backspace ||
          event.logicalKey == LogicalKeyboardKey.delete,
    );
    final outcome = event is KeyDownEvent
        ? _chordRecorder.keyDown(
            key,
            control: snapshot.control,
            alt: snapshot.alt,
            shift: snapshot.shift,
            meta: snapshot.meta,
          )
        : _chordRecorder.keyUp(
            key,
            control: snapshot.control,
            alt: snapshot.alt,
            shift: snapshot.shift,
            meta: snapshot.meta,
          );
    _logPtt(
      'recording key: event=${event is KeyDownEvent ? 'down' : 'up'} '
      'label=${key.label.isEmpty ? '<empty>' : key.label} usage=${key.usage} '
      'ctrl=${snapshot.control} alt=${snapshot.alt} '
      'shift=${snapshot.shift} meta=${snapshot.meta} '
      'outcome=${outcome.runtimeType}',
    );
    switch (outcome) {
      case PushToTalkCaptureReady(:final binding):
        _logPtt(
          'recording key: binding pronto ${_describePushToTalkBinding(binding)}',
        );
        await _setPushToTalkBinding(binding);
      case PushToTalkCaptureCancelled():
        _logPtt('recording key: cancelado');
        cancelPushToTalkRecording();
      case PushToTalkCaptureClearRequested():
        _logPtt('recording key: limpar binding solicitado');
        await clearPushToTalkBinding();
      case PushToTalkCaptureRejected(:final message):
        _warnPtt('recording key: rejeitado "$message"');
        if (!_disposed) state = state.copyWith(errorMessage: message);
      case PushToTalkCapturePending():
      case PushToTalkCaptureIgnored():
        break;
    }
  }

  Future<void> recordPushToTalkMouse(
    int buttons, {
    bool control = false,
    bool alt = false,
    bool shift = false,
  }) async {
    final binding = bindingFromMouseButton(
      buttons,
      control: control,
      alt: alt,
      shift: shift,
    );
    _logPtt(
      'recording mouse: buttons=$buttons ctrl=$control alt=$alt shift=$shift '
      'binding=${_describePushToTalkBinding(binding)}',
    );
    if (binding != null) await _setPushToTalkBinding(binding);
  }

  Future<void> _setPushToTalkBinding(PushToTalkBinding binding) async {
    await ensureInitialized();
    _logPtt('set binding: ${_describePushToTalkBinding(binding)}');
    await resetPushToTalkPress();
    final shouldEnable = _enableAfterRecording || state.isPushToTalkEnabled;
    _enableAfterRecording = false;
    _logPtt('set binding: limpando configuração nativa anterior');
    await _inputService.configure(null);
    state = state.copyWith(
      pushToTalkBinding: binding,
      isRecordingPushToTalk: false,
      isPushToTalkEnabled: shouldEnable,
      isPushToTalkRegistered: false,
      isMuted: shouldEnable ? false : null,
      errorMessage: null,
    );
    if (shouldEnable) {
      _logPtt('set binding: ativação solicitada, limpando mute manual');
      await _saveManual(isMuted: false, isDeafened: state.isDeafened);
    }
    if (shouldEnable && !await _registerPushToTalk(binding)) {
      _warnPtt('set binding: registro global falhou após captura');
      return;
    }
    await _savePushToTalk();
    await _applyToRtc();
    _logPtt('set binding: concluído shouldEnable=$shouldEnable');
  }

  Future<void> clearPushToTalkBinding() async {
    await ensureInitialized();
    _logPtt('clear binding: removendo PTT');
    _enableAfterRecording = false;
    await resetPushToTalkPress();
    await _inputService.configure(null);
    state = state.copyWith(
      isPushToTalkEnabled: false,
      pushToTalkBinding: null,
      isPushToTalkRegistered: false,
      isRecordingPushToTalk: false,
      errorMessage: null,
    );
    await _savePushToTalk();
    await _applyToRtc();
  }

  Future<void> setPushToTalkReleaseDelay(int value) async {
    await ensureInitialized();
    final clamped = value.clamp(0, 2000);
    _logPtt('release delay: requested=$value applied=$clamped');
    state = state.copyWith(pushToTalkReleaseDelayMs: clamped);
    await _savePushToTalk();
  }

  Future<void> setPushToTalkPressed(
    bool pressed, {
    String source = 'unknown',
  }) async {
    final binding = state.pushToTalkBinding;
    if (!state.isPushToTalkEnabled || binding == null) {
      _logPtt(
        'press: ignored source=$source pressed=$pressed '
        'enabled=${state.isPushToTalkEnabled} binding=${binding != null}',
      );
      return;
    }
    if (pressed) {
      _cancelPress();
      if (state.isPushToTalkPressed) {
        _logPtt(
          'press: ignored source=$source pressed=true reason=already_pressed',
        );
        return;
      }
      _logPtt(
        'press: source=$source pressed=true registered=${state.isPushToTalkRegistered} '
        'binding=${_describePushToTalkBinding(binding)}',
      );
      state = state.copyWith(isPushToTalkPressed: true, errorMessage: null);
      await _applyToRtc();
      return;
    }
    if (!state.isPushToTalkPressed) {
      _logPtt(
        'press: ignored source=$source pressed=false reason=already_released',
      );
      return;
    }
    _releaseTimer?.cancel();
    if (state.pushToTalkReleaseDelayMs == 0) {
      _logPtt('press: source=$source pressed=false applying immediate release');
      state = state.copyWith(isPushToTalkPressed: false);
      await _applyToRtc();
      return;
    }
    _logPtt(
      'press: source=$source pressed=false scheduling release '
      'delayMs=${state.pushToTalkReleaseDelayMs}',
    );
    _releaseTimer = Timer(
      Duration(milliseconds: state.pushToTalkReleaseDelayMs),
      () {
        if (_disposed || !state.isPushToTalkEnabled) return;
        _logPtt('press: release timer fired');
        state = state.copyWith(isPushToTalkPressed: false);
        unawaited(_applyToRtc());
      },
    );
  }

  Future<void> resetPushToTalkPress() async {
    _cancelPress();
    if (!state.isPushToTalkPressed) return;
    _logPtt('press: reset forced');
    state = state.copyWith(isPushToTalkPressed: false);
    await _applyToRtc();
  }

  /// O runner informa esta condição quando uma permissão de atalho global é
  /// recusada depois da configuração inicial (por exemplo, pelo portal Linux).
  /// Mantemos o microfone fechado e preservamos a configuração para que ela
  /// possa ser registrada novamente quando a permissão for corrigida.
  Future<void> handlePushToTalkRegistrationFailure() async {
    await ensureInitialized();
    _warnPtt('native failure: runner informou falha/recusa no atalho global');
    _cancelPress();
    state = state.copyWith(
      isPushToTalkPressed: false,
      isPushToTalkRegistered: false,
      errorMessage:
          'O atalho global foi recusado ou não está disponível. O microfone permaneceu fechado.',
    );
    await _savePushToTalk();
    await _applyToRtc();
  }

  void _cancelPress() {
    if (_releaseTimer != null) {
      _logPtt('press: cancelando release timer pendente');
    }
    _releaseTimer?.cancel();
    _releaseTimer = null;
  }

  Future<bool> _registerPushToTalk(PushToTalkBinding binding) async {
    _logPtt('register: iniciando ${_describePushToTalkBinding(binding)}');
    state = state.copyWith(isPushToTalkRegistered: false);
    final PushToTalkConfigResult result;
    try {
      result = await _inputService.configure(binding);
    } catch (error, stackTrace) {
      _errorPtt('register: configure nativo lançou exceção', error, stackTrace);
      if (!_disposed) {
        state = state.copyWith(
          isPushToTalkRegistered: false,
          errorMessage:
              'Não foi possível registrar o atalho global. O microfone permaneceu fechado.',
        );
      }
      await _savePushToTalk();
      await _applyToRtc();
      return false;
    }
    if (_disposed) return false;
    if (!result.isOk) {
      _warnPtt(
        'register: falhou error=${result.error} message=${result.message ?? '-'}',
      );
      state = state.copyWith(
        isPushToTalkRegistered: false,
        errorMessage: switch (result.error) {
          PushToTalkConfigError.unsupportedKey =>
            result.message ??
                'Esta tecla não é suportada como atalho global nesta plataforma. Escolha outro atalho.',
          PushToTalkConfigError.conflicting =>
            result.message ??
                'Este atalho já está em uso por outro aplicativo. Escolha outro atalho.',
          _ =>
            result.message ??
                'Não foi possível registrar o atalho global. O microfone permaneceu fechado.',
        },
      );
      await _savePushToTalk();
      await _applyToRtc();
      return false;
    }
    _logPtt('register: sucesso');
    state = state.copyWith(isPushToTalkRegistered: true, errorMessage: null);
    return true;
  }

  Future<void> _savePushToTalk() async {
    final preferences = _preferences;
    if (preferences == null) return;
    try {
      await preferences.setBool(_pttEnabledKey, state.isPushToTalkEnabled);
      await preferences.setInt(
        _pttReleaseDelayKey,
        state.pushToTalkReleaseDelayMs,
      );
      final binding = state.pushToTalkBinding;
      if (binding == null) {
        await preferences.remove(_pttBindingKey);
      } else {
        await preferences.setString(
          _pttBindingKey,
          jsonEncode(binding.toJson()),
        );
      }
      _logPtt(
        'save ptt: enabled=${state.isPushToTalkEnabled} '
        'registered=${state.isPushToTalkRegistered} '
        'delayMs=${state.pushToTalkReleaseDelayMs} '
        'binding=${_describePushToTalkBinding(binding)}',
      );
    } catch (error, stackTrace) {
      _errorPtt('save ptt: falha ao persistir PTT', error, stackTrace);
      if (!_disposed) {
        state = state.copyWith(
          errorMessage: 'Não foi possível salvar o Push to Talk.',
        );
      }
    }
  }

  Future<void> _applyToRtc({bool? isMuted, bool? isDeafened}) async {
    final muted = isMuted ?? state.isMuted;
    final deafened = isDeafened ?? state.isDeafened;
    final microphoneEnabled =
        !muted &&
        !deafened &&
        (!state.isPushToTalkEnabled || state.isPushToTalkPressed);
    _logPtt(
      'rtc apply: muted=$muted deafened=$deafened '
      'pttEnabled=${state.isPushToTalkEnabled} '
      'pttPressed=${state.isPushToTalkPressed} '
      'registered=${state.isPushToTalkRegistered} '
      'microphoneEnabled=$microphoneEnabled',
    );
    final rtc = ref.read(rtcServiceProvider);
    try {
      if (deafened) {
        _logPtt('rtc apply: deafen ativo, desligando mic e áudio remoto');
        await rtc.disableMicrophone();
        await rtc.setRemoteAudioEnabled(false);
        return;
      }
      await rtc.setRemoteAudioEnabled(true);
      if (microphoneEnabled) {
        _logPtt('rtc apply: habilitando microfone');
        await rtc.enableMicrophone();
      } else {
        _logPtt('rtc apply: desabilitando microfone');
        await rtc.disableMicrophone();
      }
    } catch (error, stackTrace) {
      _errorPtt('rtc apply: falha na chamada RTC', error, stackTrace);
      rethrow;
    }
  }
}

final voiceControlsProvider =
    NotifierProvider<VoiceControlsController, VoiceControlsState>(
      VoiceControlsController.new,
    );
