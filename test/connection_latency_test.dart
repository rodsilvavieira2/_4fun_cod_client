import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

import 'package:fourfun_cod_client/core/rtc/livekit_rtc_service.dart';

void main() {
  test('extrai RTT do par ICE apontado pelo relatório de transporte', () {
    final reports = [
      rtc.StatsReport('pair-old', 'candidate-pair', 1, {
        'selected': true,
        'currentRoundTripTime': 0.8,
      }),
      rtc.StatsReport('transport', 'transport', 1, {
        'selectedCandidatePairId': 'pair-livekit',
      }),
      rtc.StatsReport('pair-livekit', 'candidate-pair', 1, {
        'state': 'succeeded',
        'currentRoundTripTime': 0.0424,
      }),
    ];

    expect(connectionLatencyMsFromStats(reports), 42);
  });

  test('aceita par selecionado sem relatório de transporte', () {
    final reports = [
      rtc.StatsReport('pair', 'candidate-pair', 1, {
        'selected': true,
        'currentRoundTripTime': '0.151',
      }),
    ];

    expect(connectionLatencyMsFromStats(reports), 151);
  });

  test('retorna nulo quando o backend ainda não publicou RTT', () {
    final reports = [
      rtc.StatsReport('pair', 'candidate-pair', 1, {
        'selected': true,
        'state': 'succeeded',
      }),
    ];

    expect(connectionLatencyMsFromStats(reports), isNull);
  });
}
