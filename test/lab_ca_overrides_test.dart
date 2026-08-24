import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:_4fun_cod_client/core/config/lab_ca_overrides.dart';

/// Não faz rede (o flutter_test mocka HTTP e o WebSocket.connect usa um
/// HttpClient estático por isolate — ver dart:io websocket_impl.dart).
/// Cobre: asset declarado/carregável + instalação do override.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('trustLabCa: carrega a CA do asset e instala o HttpOverrides',
      () async {
    final previous = HttpOverrides.current;
    addTearDown(() => HttpOverrides.global = previous);

    await trustLabCa();

    expect(HttpOverrides.current, isA<LabCaOverrides>());
  });
}
