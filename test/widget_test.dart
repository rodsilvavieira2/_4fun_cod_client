import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:_4fun_cod_client/app.dart';
import 'package:_4fun_cod_client/core/auth/auth_controller.dart';
import 'package:_4fun_cod_client/core/auth/auth_state.dart';
import 'package:_4fun_cod_client/shared/models/user.dart';

/// Fake do AuthController: nunca toca em Firebase/storage/dio.
class _FakeAuthController extends AuthController {
  _FakeAuthController(this.initialState);

  final AuthState initialState;

  @override
  Future<AuthState> build() async => initialState;

  @override
  Future<void> login({required String email, required String password}) async {
    // Sem chamadas reais a Firebase/backend no widget test.
  }
}

void main() {
  testWidgets('App renderiza login quando deslogado', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => _FakeAuthController(const Unauthenticated()),
          ),
        ],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();

    // Redirect (§7.2): Unauthenticated → /login com os campos de entrada.
    expect(find.text('Entrar'), findsOneWidget);
    expect(find.text('E-mail'), findsOneWidget);
    expect(find.text('Senha'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Criar conta'), findsOneWidget);
    expect(find.text('Esqueci minha senha'), findsOneWidget);
  });

  testWidgets('App renderiza home quando autenticado', (WidgetTester tester) async {
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
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();

    // Redirect (§7.2): Authenticated → home com saudação e acesso ao perfil.
    expect(find.text('Olá, Rodrigo!'), findsOneWidget);
    expect(find.byIcon(Icons.account_circle), findsOneWidget);
  });
}
