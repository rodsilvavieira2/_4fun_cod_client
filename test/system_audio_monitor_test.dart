import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' show MediaDevice;

import 'package:_4fun_cod_client/core/rtc/livekit_rtc_service.dart';

/// Testes da função PURA [findSystemAudioMonitorDevice] (Fase 6.1):
/// heurística de detecção do device monitor/loopback (áudio de sistema).
void main() {
  group('findSystemAudioMonitorDevice', () {
    MediaDevice device(String id, String label) =>
        MediaDevice(id, label, 'audioinput', null);

    test('acha o monitor do PipeWire (label com .monitor)', () {
      expect(
        findSystemAudioMonitorDevice([
          device('mic1', 'Built-in Audio Analog Stereo'),
          device(
            'mon1',
            'alsa_output.pci-0000_00_1f.3.analog-stereo.monitor',
          ),
        ]),
        'mon1',
      );
    });

    test('acha o monitor do PulseAudio ("Monitor of …")', () {
      expect(
        findSystemAudioMonitorDevice([
          device('mon1', 'Monitor of Built-in Audio Analog Stereo'),
        ]),
        'mon1',
      );
    });

    test('acha o VB-Cable ("CABLE Output", Windows)', () {
      expect(
        findSystemAudioMonitorDevice([
          device('cable1', 'CABLE Output (VB-Audio Virtual Cable)'),
        ]),
        'cable1',
      );
    });

    test('acha o loopback do pw-loopback ("[Loopback]")', () {
      expect(
        findSystemAudioMonitorDevice([
          device('loop1', '[Loopback]'),
        ]),
        'loop1',
      );
    });

    test('acha "Stereo Mix" (Realtek) e "What U Hear" (Creative)', () {
      expect(
        findSystemAudioMonitorDevice([
          device('sm1', 'Stereo Mix (Realtek(R) Audio)'),
        ]),
        'sm1',
      );
      expect(
        findSystemAudioMonitorDevice([
          device('wuh1', 'What U Hear (Sound Blaster)'),
        ]),
        'wuh1',
      );
    });

    test('heurística é case-insensitive', () {
      expect(
        findSystemAudioMonitorDevice([
          device('mon1', 'MONITOR OF Built-in Audio'),
        ]),
        'mon1',
      );
    });

    test('sem monitor/loopback → null (só mics comuns)', () {
      expect(
        findSystemAudioMonitorDevice([
          device('mic1', 'Built-in Audio Analog Stereo'),
          device('mic2', 'USB Webcam Microphone'),
        ]),
        isNull,
      );
    });

    test('lista vazia → null', () {
      expect(findSystemAudioMonitorDevice(const []), isNull);
    });

    test('múltiplos matches → primeiro da ordem do enumerate', () {
      expect(
        findSystemAudioMonitorDevice([
          device('mon1', 'alsa_output.pci-0.analog-stereo.monitor'),
          device('mon2', 'alsa_output.pci-1.analog-stereo.monitor'),
        ]),
        'mon1',
      );
    });
  });
}
