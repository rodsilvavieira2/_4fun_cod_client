import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('empacota os ícones de tray para Linux e Windows', () async {
    final linuxIcon = await rootBundle.load('web/icons/Icon-192.png');
    final windowsIcon = await rootBundle.load(
      'windows/runner/resources/app_icon.ico',
    );

    expect(linuxIcon.lengthInBytes, greaterThan(0));
    expect(windowsIcon.lengthInBytes, greaterThan(0));
  });
}
