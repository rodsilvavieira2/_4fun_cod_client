import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Trava o design dos sons de voz/stream: arquivos presentes e pares
/// espelhados (join/leave e stream start/stop com mesma duração).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ByteData> load(String name) =>
      rootBundle.load('assets/sounds/$name');

  test('empacota os 4 sons de voz/stream', () async {
    final join = await load('voice_join.wav');
    final leave = await load('voice_leave.wav');
    final start = await load('stream_start.wav');
    final stop = await load('stream_stop.wav');

    for (final data in [join, leave, start, stop]) {
      expect(data.lengthInBytes, greaterThan(1000));
    }

    // Pares espelhados: mesma duração dentro do par.
    expect(join.lengthInBytes, equals(leave.lengthInBytes));
    expect(stop.lengthInBytes, equals(start.lengthInBytes));
  });
}
