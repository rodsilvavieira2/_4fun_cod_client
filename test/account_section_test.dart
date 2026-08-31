import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/core/auth/auth_controller.dart';
import 'package:fourfun_cod_client/core/auth/auth_state.dart';
import 'package:fourfun_cod_client/core/ui/settings_sections/account_section.dart';
import 'package:fourfun_cod_client/shared/models/user.dart';

class _AuthenticatedController extends AuthController {
  @override
  Future<AuthState> build() async => const Authenticated(
    user: User(
      id: 'user-123',
      name: 'Ana Silva',
      username: 'ana_silva',
      email: 'ana@example.com',
    ),
  );
}

void main() {
  Future<void> pumpAccountSection(WidgetTester tester) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_AuthenticatedController.new),
        ],
        child: const MaterialApp(home: Scaffold(body: AccountSection())),
      ),
    );
  }

  testWidgets('mascara o e-mail e permite revelá-lo', (tester) async {
    await pumpAccountSection(tester);
    await tester.pumpAndSettle();

    expect(find.text('a••••@example.com'), findsOneWidget);
    expect(find.text('ana@example.com'), findsNothing);

    await tester.tap(find.text('Revelar'));
    await tester.pump();

    expect(find.text('ana@example.com'), findsOneWidget);
    expect(find.text('Ocultar'), findsOneWidget);
  });

  testWidgets('abre os diálogos de perfil, e-mail e senha', (tester) async {
    await pumpAccountSection(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Editar').first);
    await tester.pumpAndSettle();
    expect(find.text('Editar perfil'), findsOneWidget);
    expect(find.text('Alterar avatar'), findsOneWidget);
    await tester.tap(find.byTooltip('Fechar (ESC)'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Editar e-mail'));
    await tester.pumpAndSettle();
    expect(find.text('Alterar e-mail'), findsOneWidget);
    expect(find.text('Novo e-mail'), findsOneWidget);
    await tester.tap(find.byTooltip('Fechar (ESC)'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alterar'));
    await tester.pumpAndSettle();
    expect(find.text('Alterar senha'), findsNWidgets(2));
    expect(find.text('Confirmar nova senha'), findsOneWidget);
  });
}
