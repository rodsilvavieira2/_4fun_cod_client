import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/core/auth/auth_controller.dart';
import 'package:fourfun_cod_client/core/auth/auth_state.dart';
import 'package:fourfun_cod_client/features/servers/user_panel.dart';
import 'package:fourfun_cod_client/shared/models/user.dart';

/// Fake do AuthController: nunca toca em backend/storage/dio.
class _FakeAuthController extends AuthController {
  _FakeAuthController(this.initialState);

  final AuthState initialState;

  @override
  Future<AuthState> build() async => initialState;
}

void main() {
  testWidgets(
      'UserPanel renderiza sem assert (color+decoration) com usuário autenticado',
      (WidgetTester tester) async {
    const user = User(
      id: 'user-1',
      name: 'Rodrigo',
      username: 'rodrigo',
      email: 'rodrigo@example.com',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => _FakeAuthController(const Authenticated(user: user)),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: UserPanel()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // O container não pode lançar a assert do Flutter ("color is just a
    // shorthand for decoration") — a presença dos widgets confirma o
    // build sem ErrorWidget.
    expect(find.text('Rodrigo'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
    expect(find.byIcon(Icons.headset_outlined), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });

  testWidgets('UserPanel tolera usuário ausente (estado de bootstrap)',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => _FakeAuthController(const AuthUnknown()),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: UserPanel()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Bootstrap sem usuário: painel renderiza com placeholder (avatar +
    // nome usam '…') — o importante é não lançar e manter o ⚙️.
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(find.text('…'), findsNWidgets(2));
  });
}
