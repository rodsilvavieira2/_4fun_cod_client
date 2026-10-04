// Build only as a diagnostic target; never used by the production entrypoint.
// Companion: smoke-windows-window-share.ps1 (interactive Windows desktop).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:fourfun_cod_client/core/native/native_media_backend.dart';
import 'package:fourfun_cod_client/core/rtc/screen_share_window_waiter.dart';
import 'package:fourfun_cod_client/core/ui/screen_share_pending_notice.dart';

const _directory = String.fromEnvironment('SMOKE_DIR');
final _stage = ValueNotifier('loading');

Future<void> _status(
  String stage, [
  Map<String, Object?> details = const {},
]) async {
  _stage.value = stage;
  // Status is atomic so the PowerShell helper never reads partial JSON.
  final pending = File('$_directory/status.tmp');
  await pending.writeAsString(jsonEncode({'stage': stage, ...details}));
  await pending.rename('$_directory/status.json');
}

Future<void> _waitForMarker(String name) async {
  final elapsed = Stopwatch()..start();
  while (!await File('$_directory/$name').exists()) {
    if (elapsed.elapsed > const Duration(seconds: 15)) {
      throw StateError('Helper timed out: $name');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<Uint8List> _frame(rtc.MediaStreamTrack track, String name) async {
  final bytes = (await track.captureFrame().timeout(
    const Duration(seconds: 10),
  )).asUint8List();
  await File('$_directory/$name.png').writeAsBytes(bytes);
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  final pixels = (await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  ))!.buffer.asUint8List();
  final colors = <int>{};
  for (var i = 0; i < pixels.length; i += 4) {
    colors.add((pixels[i] << 16) | (pixels[i + 1] << 8) | pixels[i + 2]);
    if (colors.length > 16) break;
  }
  final valid = image.width > 100 && image.height > 100 && colors.length > 16;
  image.dispose();
  codec.dispose();
  if (!valid) throw StateError('Frame is blank or too small');
  return bytes;
}

Future<void> _gather(rtc.RTCPeerConnection peer) async {
  final deadline = Stopwatch()..start();
  while (await peer.getIceGatheringState() !=
      rtc.RTCIceGatheringState.RTCIceGatheringStateComplete) {
    if (deadline.elapsed > const Duration(seconds: 10)) {
      throw StateError('ICE gathering timed out');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<int> _decodedFrames(rtc.RTCPeerConnection peer) async {
  var frames = 0;
  for (final report in await peer.getStats()) {
    if (report.type == 'inbound-rtp') {
      frames += int.tryParse('${report.values['framesDecoded']}') ?? 0;
    }
  }
  return frames;
}

Future<void> _smoke() async {
  rtc.MediaStream? stream;
  rtc.RTCPeerConnection? sender;
  rtc.RTCPeerConnection? receiver;
  final renderer = rtc.RTCVideoRenderer();
  try {
    const backend = WindowsScreenShareBackend();
    final sources = await backend.loadSources();
    final source = sources.singleWhere(
      (s) => s.name == '4fun minimized smoke target',
    );
    if (!source.minimized || source.windowTarget == null) {
      throw StateError('Minimized candidate missing');
    }
    final target = source.windowTarget!;
    final wrongPid = await backend.readWindowState(
      NativeShareWindowTarget(target.windowId, target.processId + 1),
    );
    if (wrongPid.valid) throw StateError('PID mismatch accepted');
    final waiter = ScreenShareWindowWaiter(backend: backend, target: target);
    final id = await waiter.resolve(
      onWaiting: () {
        if (_stage.value != 'waiting') unawaited(_status('waiting'));
      },
    );
    final ready = await backend.readWindowState(target);
    if (!ready.capturable || !ready.foreground) {
      throw StateError('Started before target focus');
    }
    stream = await rtc.navigator.mediaDevices.getDisplayMedia({
      'audio': false,
      'video': {
        'deviceId': {'exact': id},
        'mandatory': {'frameRate': 15.0},
      },
    });
    // Host-only peer loopback checks received frames, not just local preview.
    sender = await rtc.createPeerConnection({'iceServers': []});
    receiver = await rtc.createPeerConnection({'iceServers': []});
    final received = Completer<rtc.RTCTrackEvent>();
    receiver.onTrack = (event) {
      if (event.track.kind == 'video' && !received.isCompleted) {
        received.complete(event);
      }
    };
    await sender.addTrack(stream.getVideoTracks().single, stream);
    await sender.setLocalDescription(await sender.createOffer());
    await _gather(sender);
    await receiver.setRemoteDescription((await sender.getLocalDescription())!);
    await receiver.setLocalDescription(await receiver.createAnswer());
    await _gather(receiver);
    await sender.setRemoteDescription((await receiver.getLocalDescription())!);
    final event = await received.future.timeout(const Duration(seconds: 10));
    final firstRendered = Completer<void>();
    renderer.onFirstFrameRendered = () {
      if (!firstRendered.isCompleted) firstRendered.complete();
    };
    await renderer.initialize();
    await renderer.setSrcObject(
      stream: event.streams.single,
      trackId: event.track.id,
    );
    await firstRendered.future.timeout(const Duration(seconds: 10));
    final track = stream.getVideoTracks().single;
    await Future<void>.delayed(const Duration(seconds: 1));
    // captureFrame's native lookup uses trackId, which can shadow a local
    // track in an in-process loopback. Receiver stats independently prove
    // decoding; snapshots validate that the native source is not black.
    final first = await _frame(track, 'before');
    final decodeDeadline = Stopwatch()..start();
    var framesBefore = await _decodedFrames(receiver);
    while (framesBefore == 0 &&
        decodeDeadline.elapsed < const Duration(seconds: 10)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      framesBefore = await _decodedFrames(receiver);
    }
    if (framesBefore == 0) {
      throw StateError('Receiver did not decode video');
    }
    await _status('captured_first');
    await _waitForMarker('minimized.marker');
    if (!(await backend.readWindowState(target)).minimized) {
      throw StateError('Helper did not minimize');
    }
    // Black/paused video while minimized is explicitly allowed.
    await Future<void>.delayed(const Duration(seconds: 2));
    await _status('restore_requested');
    await _waitForMarker('restored.marker');
    final framesAtRestore = await _decodedFrames(receiver);
    await Future<void>.delayed(const Duration(seconds: 1));
    final second = await _frame(track, 'after');
    final framesAfter = await _decodedFrames(receiver);
    if (framesAfter <= framesAtRestore) {
      throw StateError('Receiver stopped decoding after restoration');
    }
    if (listEquals(first, second)) {
      throw StateError('Frames did not advance after restoration');
    }
    for (final track in stream.getTracks()) {
      await track.stop();
    }
    await stream.dispose();
    stream = null;
    await sender.close();
    await receiver.close();
    await renderer.dispose();
    await _status('passed', {
      'minimized_listed': true,
      'identity_checked': true,
      'waited_for_focus': true,
      'frames_resumed_same_track': true,
      'received_via_peer_loopback': true,
      'received_frames_before': framesBefore,
      'received_frames_after': framesAfter,
    });
    exit(0);
  } catch (error) {
    await _status('failed', {
      'error_type': '${error.runtimeType}',
      'detail': '$error',
    });
    exit(1);
  }
}

void main() {
  if (!Platform.isWindows || _directory.isEmpty) {
    throw StateError('Windows and SMOKE_DIR are required');
  }
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ValueListenableBuilder<String>(
            valueListenable: _stage,
            builder: (context, value, child) => value == 'waiting'
                ? ScreenSharePendingNotice(
                    waiting: true,
                    onCancel: () => exit(2),
                  )
                : Text('Window share smoke: $value'),
          ),
        ),
      ),
    ),
  );
  unawaited(_smoke());
}
