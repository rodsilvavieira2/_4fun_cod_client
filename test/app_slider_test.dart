import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fourfun_cod_client/core/ui/inputs/app_slider.dart';

void main() {
  testWidgets('AppSlider usa padding horizontal explícito (sem inset fantasma)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSlider(value: 0.5, onChanged: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.padding, const EdgeInsets.symmetric(horizontal: 8));
    expect(slider.value, 0.5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppSlider repassa valor, limites e divisões', (tester) async {
    double? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSlider(
            value: 180,
            min: 0,
            max: 360,
            onChanged: (value) => changed = value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.min, 0);
    expect(slider.max, 360);
    slider.onChanged?.call(200);
    expect(changed, 200);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppSlider desabilitado repassa onChanged nulo', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppSlider(value: 0.5, onChanged: null)),
      ),
    );
    await tester.pumpAndSettle();

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.onChanged, isNull);
    expect(tester.takeException(), isNull);
  });
}
