import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';

import '../rtc/audio_device_normalizer.dart';
import '../rtc/rtc_service.dart';

/// Plataformas suportadas pelo cliente desktop.
///
/// A decisão fica concentrada na factory. Controllers e serviços não devem
/// consultar [Platform] diretamente.
enum AppRuntimePlatform { linux, windows }

enum NativeFailureCode {
  unavailable,
  permissionDenied,
  notSupported,
  deviceLost,
  cancelled,
  invalidBinding,
}

class NativeFailure implements Exception {
  const NativeFailure(this.code, this.message, {this.recoverable = true});

  final NativeFailureCode code;
  final String message;
  final bool recoverable;

  @override
  String toString() => message;
}

AppRuntimePlatform get currentRuntimePlatform {
  if (kIsWeb) {
    throw UnsupportedError(
      'Web não é suportado pelo 4FunCode. Use Linux ou Windows desktop.',
    );
  }
  if (Platform.isLinux) return AppRuntimePlatform.linux;
  if (Platform.isWindows) return AppRuntimePlatform.windows;
  throw UnsupportedError('Plataforma não suportada para mídia nativa.');
}

enum RtcScreenShareSourceKind { window, display }

/// Identidade local somente: nunca enviar estes campos à telemetria.
class NativeShareWindowTarget {
  const NativeShareWindowTarget(this.windowId, this.processId);
  final String windowId;
  final int processId;
}

class NativeShareWindowState {
  const NativeShareWindowState({
    required this.valid,
    required this.visible,
    required this.minimized,
    required this.foreground,
  });
  final bool valid;
  final bool visible;
  final bool minimized;
  final bool foreground;
  bool get capturable => valid && visible && !minimized;
}

abstract interface class NativeWindowShareBackend {
  Future<NativeShareWindowState> readWindowState(
    NativeShareWindowTarget target,
  );
  Future<String?> resolveWindowSource(NativeShareWindowTarget target);
}

class RtcScreenShareSelection {
  const RtcScreenShareSelection({
    required this.kind,
    required this.sourceId,
    required this.usesSystemPicker,
    this.windowTarget,
    this.attemptId,
  });

  final RtcScreenShareSourceKind kind;
  final String? sourceId;
  final bool usesSystemPicker;
  final NativeShareWindowTarget? windowTarget;
  final String? attemptId;
}

class RtcScreenShareSource {
  const RtcScreenShareSource({
    required this.id,
    required this.name,
    required this.kind,
    this.thumbnail,
    this.windowTarget,
    this.minimized = false,
  });

  final String id;
  final String name;
  final RtcScreenShareSourceKind kind;
  final Uint8List? thumbnail;
  final NativeShareWindowTarget? windowTarget;
  final bool minimized;
}

class ScreenShareCapabilities {
  const ScreenShareCapabilities({
    required this.usesSystemPicker,
    required this.supportsWindowSources,
    required this.supportsSystemAudio,
  });

  final bool usesSystemPicker;
  final bool supportsWindowSources;
  final bool supportsSystemAudio;
}

/// Porta para a seleção de fontes de compartilhamento de tela.
abstract interface class NativeScreenShareBackend {
  ScreenShareCapabilities get capabilities;

  Future<List<RtcScreenShareSource>> loadSources();

  bool canUseKind(RtcScreenShareSourceKind kind);

  String? disabledReasonFor(RtcScreenShareSourceKind kind);
}

/// Porta para a criação de uma track temporária de câmera.
abstract interface class NativeCameraBackend {
  Future<LocalVideoTrack> createCameraTrack(CameraCaptureOptions options);
}

/// Porta para enumeração e seleção de dispositivos fora de uma Room LiveKit.
abstract interface class NativeAudioDevicesBackend {
  Future<List<MediaDevice>> listInputs();

  Future<List<MediaDevice>> listOutputs();

  Future<void> selectInput(MediaDevice device);

  Future<void> selectOutput(MediaDevice device);
}

class NativeMediaServices {
  const NativeMediaServices({
    required this.screenShare,
    required this.camera,
    required this.audioDevices,
  });

  final NativeScreenShareBackend screenShare;
  final NativeCameraBackend camera;
  final NativeAudioDevicesBackend audioDevices;
}

abstract interface class NativeMediaServicesFactory {
  NativeMediaServices create(AppRuntimePlatform platform);
}

class DefaultNativeMediaServicesFactory implements NativeMediaServicesFactory {
  const DefaultNativeMediaServicesFactory();

  @override
  NativeMediaServices create(AppRuntimePlatform platform) {
    return switch (platform) {
      AppRuntimePlatform.linux => const NativeMediaServices(
        screenShare: LinuxScreenShareBackend(),
        camera: LinuxCameraBackend(),
        audioDevices: LinuxAudioDevicesBackend(),
      ),
      AppRuntimePlatform.windows => const NativeMediaServices(
        screenShare: WindowsScreenShareBackend(),
        camera: WindowsCameraBackend(),
        audioDevices: WindowsAudioDevicesBackend(),
      ),
    };
  }
}

abstract class _SystemPickerScreenShareBackend
    implements NativeScreenShareBackend {
  const _SystemPickerScreenShareBackend();

  @override
  bool canUseKind(RtcScreenShareSourceKind kind) => true;

  @override
  String? disabledReasonFor(RtcScreenShareSourceKind kind) => null;

  @override
  Future<List<RtcScreenShareSource>> loadSources() => Future.value(const []);
}

class LinuxScreenShareBackend extends _SystemPickerScreenShareBackend {
  const LinuxScreenShareBackend();

  @override
  ScreenShareCapabilities get capabilities => const ScreenShareCapabilities(
    usesSystemPicker: true,
    supportsWindowSources: true,
    supportsSystemAudio: true,
  );
}

class WindowsScreenShareBackend
    implements NativeScreenShareBackend, NativeWindowShareBackend {
  const WindowsScreenShareBackend();
  static const _channel = MethodChannel('FlutterWebRTC.Method');

  @override
  ScreenShareCapabilities get capabilities => const ScreenShareCapabilities(
    usesSystemPicker: false,
    supportsWindowSources: true,
    supportsSystemAudio: true,
  );

  @override
  bool canUseKind(RtcScreenShareSourceKind kind) => true;

  @override
  String? disabledReasonFor(RtcScreenShareSourceKind kind) => null;

  @override
  Future<List<RtcScreenShareSource>> loadSources() async {
    final sources = await rtc.desktopCapturer.getSources(
      types: const [rtc.SourceType.Window, rtc.SourceType.Screen],
    );
    final windows =
        await _channel.invokeListMethod<dynamic>('fourfunGetShareWindows') ??
        [];
    final candidates = <String, RtcScreenShareSource>{};
    for (final raw in windows) {
      final window = raw as Map;
      final id = window['id'] as String;
      candidates[id] = RtcScreenShareSource(
        id: id,
        name: window['name'] as String,
        kind: RtcScreenShareSourceKind.window,
        windowTarget: NativeShareWindowTarget(id, window['processId'] as int),
        minimized: window['minimized'] as bool,
      );
    }
    final result = <RtcScreenShareSource>[];
    for (final raw in sources) {
      final source = _screenShareSourceFromWebRtc(raw);
      final candidate = source.kind == RtcScreenShareSourceKind.window
          ? candidates.remove(source.id)
          : null;
      result.add(
        candidate == null
            ? source
            : RtcScreenShareSource(
                id: source.id,
                name: source.name,
                kind: source.kind,
                thumbnail: source.thumbnail,
                windowTarget: candidate.windowTarget,
                minimized: candidate.minimized,
              ),
      );
    }
    // Candidatos não são fontes RTC: só o resolver pode fornecer sourceId.
    result.addAll(candidates.values);
    return result;
  }

  @override
  Future<NativeShareWindowState> readWindowState(
    NativeShareWindowTarget target,
  ) async {
    final value = await _channel.invokeMapMethod<String, dynamic>(
      'fourfunGetShareWindowState',
      {'id': target.windowId, 'processId': target.processId},
    );
    return NativeShareWindowState(
      valid: value?['valid'] == true,
      visible: value?['visible'] == true,
      minimized: value?['minimized'] == true,
      foreground: value?['foreground'] == true,
    );
  }

  @override
  Future<String?> resolveWindowSource(NativeShareWindowTarget target) async {
    final sources = await rtc.desktopCapturer.getSources(
      types: const [rtc.SourceType.Window, rtc.SourceType.Screen],
    );
    for (final source in sources) {
      if (source.type == rtc.SourceType.Window &&
          source.id == target.windowId) {
        return source.id;
      }
    }
    return null;
  }
}

RtcScreenShareSource _screenShareSourceFromWebRtc(
  rtc.DesktopCapturerSource source,
) {
  final kind = source.type == rtc.SourceType.Window
      ? RtcScreenShareSourceKind.window
      : RtcScreenShareSourceKind.display;
  final fallbackName = kind == RtcScreenShareSourceKind.window
      ? 'Janela'
      : 'Display';
  final thumbnail = source.thumbnail;
  return RtcScreenShareSource(
    id: source.id,
    name: source.name.isEmpty ? fallbackName : source.name,
    kind: kind,
    thumbnail: thumbnail == null || thumbnail.isEmpty ? null : thumbnail,
  );
}

abstract class _LiveKitCameraBackend implements NativeCameraBackend {
  const _LiveKitCameraBackend();

  @override
  Future<LocalVideoTrack> createCameraTrack(CameraCaptureOptions options) =>
      LocalVideoTrack.createCameraTrack(options);
}

class LinuxCameraBackend extends _LiveKitCameraBackend {
  const LinuxCameraBackend();
}

class WindowsCameraBackend extends _LiveKitCameraBackend {
  const WindowsCameraBackend();
}

abstract class _HardwareAudioDevicesBackend
    implements NativeAudioDevicesBackend {
  const _HardwareAudioDevicesBackend();

  @override
  Future<List<MediaDevice>> listInputs() async => _normalize(
    await Hardware.instance.audioInputs(),
    RtcMediaDeviceKind.audioInput,
  );

  @override
  Future<List<MediaDevice>> listOutputs() async => _normalize(
    await Hardware.instance.audioOutputs(),
    RtcMediaDeviceKind.audioOutput,
  );

  @override
  Future<void> selectInput(MediaDevice device) =>
      Hardware.instance.selectAudioInput(device);

  @override
  Future<void> selectOutput(MediaDevice device) =>
      Hardware.instance.selectAudioOutput(device);

  List<MediaDevice> _normalize(
    List<MediaDevice> devices,
    RtcMediaDeviceKind kind,
  ) {
    final normalized = normalizeAudioDevices(
      devices.map(
        (device) => RtcAudioDevice(
          id: device.deviceId,
          label: device.label,
          kind: kind,
        ),
      ),
    );
    final ids = normalized.map((device) => device.id).toSet();
    return devices.where((device) => ids.contains(device.deviceId)).toList();
  }
}

class LinuxAudioDevicesBackend extends _HardwareAudioDevicesBackend {
  const LinuxAudioDevicesBackend();
}

class WindowsAudioDevicesBackend extends _HardwareAudioDevicesBackend {
  const WindowsAudioDevicesBackend();
}
