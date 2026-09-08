import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fourfun_cod_client/core/ui/app_logo.dart';

void main() {
  testWidgets('AppLogo exibe o ícone oficial do 4FunCode', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppLogo(size: 44))),
    );
    await tester.pumpAndSettle();

    final image = tester.widget<Image>(find.byType(Image)).image as AssetImage;
    expect(image.assetName, 'assets/branding/app_logo.png');
    expect(tester.takeException(), isNull);
  });
}
