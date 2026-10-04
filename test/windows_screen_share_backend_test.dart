import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fourfun_cod_client/core/native/native_media_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('FlutterWebRTC.Method');
  const backend = WindowsScreenShareBackend();
  var loads = 0;
  var restored = false;
  setUp(() {
    loads = 0;
    restored = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('FlutterWebRTC.Event'),
          (call) async => null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          Map<String, Object> source(String id, String type) => {
            'id': id,
            'name': type == 'window' ? 'Janela' : 'Display',
            'type': type,
            'thumbnailSize': {'width': 10, 'height': 10},
          };
          switch (call.method) {
            case 'initialize':
              return null;
            case 'getDesktopSources':
              loads++;
              return {
                'sources': [
                  source('0', 'screen'),
                  source('123', 'window'),
                  if (restored) source('456', 'window'),
                ],
              };
            case 'fourfunGetShareWindows':
              return [
                {
                  'id': '123',
                  'name': 'Janela',
                  'processId': 1,
                  'minimized': false,
                },
                {
                  'id': '456',
                  'name': 'Jogo',
                  'processId': 2,
                  'minimized': !restored,
                },
              ];
            case 'fourfunGetShareWindowState':
              expect(call.arguments, {'id': '456', 'processId': 2});
              return {
                'valid': true,
                'visible': true,
                'minimized': !restored,
                'foreground': restored,
              };
            default:
              throw StateError('Unexpected method: ${call.method}');
          }
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test(
    'união preserva displays e não duplica janelas presentes no RTC',
    () async {
      final sources = await backend.loadSources();
      expect(sources.map((s) => s.id), ['0', '123', '456']);
      expect(sources.first.windowTarget, isNull);
      expect(sources[1].windowTarget?.processId, 1);
      expect(sources.last.minimized, isTrue);
      expect(sources.last.windowTarget?.processId, 2);
    },
  );

  test(
    'resolver reenumera fontes reais e não retorna candidato minimizado',
    () async {
      const target = NativeShareWindowTarget('456', 2);
      expect(await backend.resolveWindowSource(target), isNull);
      restored = true;
      expect(await backend.resolveWindowSource(target), '456');
      expect(loads, 2);
      expect((await backend.readWindowState(target)).capturable, isTrue);
    },
  );
}
