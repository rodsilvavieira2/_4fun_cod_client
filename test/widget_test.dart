import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:_4fun_cod_client/app.dart';

void main() {
  testWidgets('App renders home placeholder', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: App()));

    expect(find.text('4fun Cod'), findsOneWidget);
    expect(find.text('Home (placeholder)'), findsOneWidget);
  });
}
