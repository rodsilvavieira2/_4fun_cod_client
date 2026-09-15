import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

import 'package:fourfun_cod_client/core/rtc/livekit_rtc_service.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_service.dart';
import 'package:fourfun_cod_client/core/rtc/screen_share_adaptive.dart';

const _good = ScreenShareNetworkSample(rttMs: 42, lossFraction: 0.0);
const _badRtt = ScreenShareNetworkSample(rttMs: 450, lossFraction: 0.0);
const _badLoss = ScreenShareNetworkSample(rttMs: 42, lossFraction: 0.08);
const _neutral = ScreenShareNetworkSample(rttMs: 250, lossFraction: 0.03);

/// Avança o controlador até trocar de degrau (ou esgotar [samples]).
/// Retorna a qualidade proposta ou null.
RtcScreenShareQuality? _drive(
  ScreenShareAdaptiveController controller,
  ScreenShareNetworkSample sample, [
  int samples = 10,
]) {
  for (var i = 0; i < samples; i++) {
    final proposed = controller.propose(sample);
    if (proposed != null) return proposed;
  }
  return null;
}

void main() {
  group('ScreenShareAdaptiveController', () {
    test('rede saudável: efetiva == objetivo o tempo todo', () {
      final controller = ScreenShareAdaptiveController(
        target: RtcScreenShareQuality.q1080p30,
      );
      // Efetiva começa no teto; 30 amostras boas não propõem nada acima.
      controller.commit(RtcScreenShareQuality.q1080p30);
      expect(_drive(controller, _good, 30), isNull);
      expect(controller.effective, RtcScreenShareQuality.q1080p30);
    });

    test('2 amostras ruins seguidas descem 1 degrau', () {
      final controller = ScreenShareAdaptiveController(
        target: RtcScreenShareQuality.q1080p30,
        cooldownSamples: 0,
      );
      expect(controller.propose(_badRtt), isNull);
      expect(controller.propose(_badRtt), RtcScreenShareQuality.q720p60);
    });

    test('perda > 5% também derruba (sem RTT alto)', () {
      final controller = ScreenShareAdaptiveController(
        target: RtcScreenShareQuality.q720p15,
        cooldownSamples: 0,
      );
      expect(controller.propose(_badLoss), isNull);
      expect(controller.propose(_badLoss), RtcScreenShareQuality.q480p30);
    });

    test('amostra neutra quebra a sequência de ruins', () {
      final controller = ScreenShareAdaptiveController(
        target: RtcScreenShareQuality.q1080p30,
        cooldownSamples: 0,
      );
      expect(controller.propose(_badRtt), isNull);
      expect(controller.propose(_neutral), isNull);
      expect(controller.propose(_badRtt), isNull);
      expect(controller.propose(_neutral), isNull);
    });

    test('sobe 1 degrau após 6 boas e nunca passa do objetivo', () {
      final controller = ScreenShareAdaptiveController(
        target: RtcScreenShareQuality.q1080p30,
        cooldownSamples: 0,
      );
      // Desce degrau a degrau na escada nova (1080p30 → 720p60 → 1080p15).
      var proposed = _drive(controller, _badRtt);
      expect(proposed, RtcScreenShareQuality.q720p60);
      controller.commit(proposed!);
      proposed = _drive(controller, _badRtt);
      expect(proposed, RtcScreenShareQuality.q1080p15);
      controller.commit(proposed!);

      // 5 boas não bastam; a 6ª sobe um degrau.
      for (var i = 0; i < 5; i++) {
        expect(controller.propose(_good), isNull);
      }
      expect(controller.propose(_good), RtcScreenShareQuality.q720p60);
      controller.commit(RtcScreenShareQuality.q720p60);

      // Ainda abaixo do teto: 6 boas sobem mais um degrau (q1080p30).
      expect(_drive(controller, _good), RtcScreenShareQuality.q1080p30);
      controller.commit(RtcScreenShareQuality.q1080p30);

      // No teto, nenhuma boa propõe nada (nunca passa do objetivo).
      expect(_drive(controller, _good, 12), isNull);
      expect(controller.effective, RtcScreenShareQuality.q1080p30);
    });

    test('piso: Baixa (480p30) só desce até 360p3', () {
      final controller = ScreenShareAdaptiveController(
        target: RtcScreenShareQuality.q480p30,
        cooldownSamples: 0,
      );
      var proposed = _drive(controller, _badRtt);
      expect(proposed, RtcScreenShareQuality.q360p3);
      controller.commit(proposed!);
      expect(_drive(controller, _badRtt, 10), isNull);
      expect(controller.effective, RtcScreenShareQuality.q360p3);
    });

    test('auto desce do topo e volta para auto (escada inteira)', () {
      final controller = ScreenShareAdaptiveController(
        target: RtcScreenShareQuality.auto,
        cooldownSamples: 0,
      );
      // Topo = 1080p60: primeiro degrau abaixo é 1080p30, depois 720p60.
      var down = _drive(controller, _badRtt);
      expect(down, RtcScreenShareQuality.q1080p30);
      controller.commit(down!);
      down = _drive(controller, _badRtt);
      expect(down, RtcScreenShareQuality.q720p60);
      controller.commit(down!);
      // Recuperação total volta a auto (não a um degrau fixo).
      controller.commit(RtcScreenShareQuality.q1080p30);
      final up = _drive(controller, _good);
      expect(up, RtcScreenShareQuality.auto);
    });

    test('objetivo baixo limita a subida', () {
      final controller = ScreenShareAdaptiveController(
        target: RtcScreenShareQuality.q720p15,
        cooldownSamples: 0,
      );
      final down = _drive(controller, _badRtt);
      expect(down, RtcScreenShareQuality.q480p30);
      controller.commit(down!);
      final up = _drive(controller, _good);
      expect(up, RtcScreenShareQuality.q720p15);
      controller.commit(up!);
      // Teto do objetivo: para por aqui.
      expect(_drive(controller, _good, 12), isNull);
    });

    test('cooldown congela a adaptação após cada troca', () {
      final controller = ScreenShareAdaptiveController(
        target: RtcScreenShareQuality.q1080p30,
      );
      final down = _drive(controller, _badRtt);
      expect(down, RtcScreenShareQuality.q720p60);
      controller.commit(down!);
      // 2 amostras de cooldown: nem 2 ruins seguidas propõem.
      expect(controller.propose(_badRtt), isNull);
      expect(controller.propose(_badRtt), isNull);
      // Após o cooldown, a contagem recomeça.
      expect(controller.propose(_badRtt), isNull);
      expect(controller.propose(_badRtt), RtcScreenShareQuality.q1080p15);
    });

    test('setTarget assume o teto na hora (ação do usuário)', () {
      final controller = ScreenShareAdaptiveController(
        target: RtcScreenShareQuality.q1080p30,
        cooldownSamples: 0,
      );
      final down = _drive(controller, _badRtt);
      controller.commit(down!);
      controller.setTarget(RtcScreenShareQuality.q720p15);
      expect(controller.target, RtcScreenShareQuality.q720p15);
      expect(controller.effective, RtcScreenShareQuality.q720p15);
    });

    test('cpu-limited é neutro (não derruba nem sobe)', () {
      final controller = ScreenShareAdaptiveController(
        target: RtcScreenShareQuality.q1080p30,
        cooldownSamples: 0,
      );
      const cpu = ScreenShareNetworkSample(rttMs: 42, limitationReason: 'cpu');
      expect(_drive(controller, cpu, 10), isNull);
      expect(controller.effective, RtcScreenShareQuality.q1080p30);
    });

    test('bandwidth-limited derruba mesmo com RTT/perda bons', () {
      final controller = ScreenShareAdaptiveController(
        target: RtcScreenShareQuality.q1080p30,
        cooldownSamples: 0,
      );
      const limited = ScreenShareNetworkSample(
        rttMs: 42,
        lossFraction: 0.0,
        limitationReason: 'bandwidth',
      );
      expect(controller.propose(limited), isNull);
      expect(controller.propose(limited), RtcScreenShareQuality.q720p60);
    });
  });

  group('adaptiveLimitationFromStats', () {
    test('bandwidth tem prioridade e none/vazio vira null', () {
      final reports = [
        rtc.StatsReport('o1', 'outbound-rtp', 1, {
          'qualityLimitationReason': 'cpu',
        }),
        rtc.StatsReport('o2', 'outbound-rtp', 1, {
          'qualityLimitationReason': 'bandwidth',
        }),
      ];
      expect(adaptiveLimitationFromStats(reports), 'bandwidth');
    });

    test('retorna null sem outbound-rtp ou só none', () {
      expect(adaptiveLimitationFromStats(const []), isNull);
      expect(
        adaptiveLimitationFromStats([
          rtc.StatsReport('o', 'outbound-rtp', 1, {
            'qualityLimitationReason': 'none',
          }),
        ]),
        isNull,
      );
    });
  });

  group('adaptiveLossFromStats', () {
    test('prefere fractionLost 0..1 do remote-inbound-rtp', () {
      final reports = [
        rtc.StatsReport('r', 'remote-inbound-rtp', 1, {'fractionLost': 0.07}),
      ];
      expect(adaptiveLossFromStats(reports), closeTo(0.07, 0.0001));
    });

    test('normaliza fractionLost 0..255', () {
      final reports = [
        rtc.StatsReport('r', 'remote-inbound-rtp', 1, {'fractionLost': 13}),
      ];
      expect(adaptiveLossFromStats(reports), closeTo(13 / 256, 0.0001));
    });

    test('ignora contadores cumulativos (só fractionLost vale)', () {
      // packetsLost alto em histórico antigo NÃO pode derrubar: sem
      // fractionLost de intervalo, a dimensão é ignorada (null).
      final inbound = [
        rtc.StatsReport('r', 'remote-inbound-rtp', 1, {
          'packetsLost': 500,
          'packetsReceived': 95,
        }),
      ];
      expect(adaptiveLossFromStats(inbound), isNull);

      final outbound = [
        rtc.StatsReport('o', 'outbound-rtp', 1, {
          'packetsLost': 50,
          'packetsSent': 99,
        }),
      ];
      expect(adaptiveLossFromStats(outbound), isNull);
    });

    test('retorna null sem dados de perda', () {
      expect(adaptiveLossFromStats(const []), isNull);
      expect(
        adaptiveLossFromStats([
          rtc.StatsReport('o', 'outbound-rtp', 1, {'bytesSent': 10}),
        ]),
        isNull,
      );
    });
  });
}
