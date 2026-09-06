import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/app.dart';
import 'package:fourfun_cod_client/core/auth/auth_controller.dart';
import 'package:fourfun_cod_client/core/auth/auth_state.dart';
import 'package:fourfun_cod_client/core/ui/server_entry_dialog.dart';
import 'package:fourfun_cod_client/features/servers/server_rail.dart';
import 'package:fourfun_cod_client/features/servers/servers_providers.dart';
import 'package:fourfun_cod_client/shared/models/servers.dart';
import 'package:fourfun_cod_client/shared/models/user.dart';

/// Fake do AuthController: nunca toca em backend/storage/dio.
class _FakeAuthController extends AuthController {
  _FakeAuthController(this.initialState);

  final AuthState initialState;

  @override
  Future<AuthState> build() async => initialState;

  @override
  Future<void> login({required String email, required String password}) async {
    // Sem chamadas reais a backend no widget test.
  }
}

/// Fake do ServersController: nunca toca em dio.
class _FakeServersController extends ServersController {
  _FakeServersController(this.servers);

  final List<Server> servers;

  @override
  Future<List<Server>> build() async => servers;

  @override
  Future<Server> create(String name) async =>
      Server(id: 'new-1', name: name);
}

void main() {
  testWidgets('App renderiza login quando deslogado', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => _FakeAuthController(const Unauthenticated()),
          ),
          serversProvider.overrideWith(() => _FakeServersController(const [])),
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
          serversProvider.overrideWith(() => _FakeServersController(const [])),
        ],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();

    // Redirect (§7.2): Authenticated → home; sem servidores, empty state.
    expect(find.text('Crie seu primeiro servidor'), findsOneWidget);
    expect(find.byIcon(Icons.account_circle), findsOneWidget);
  });

  testWidgets('Rail renderiza os servidores do usuário', (WidgetTester tester) async {
    const servers = [
      Server(id: 'srv-1', name: 'Gamers'),
      Server(id: 'srv-2', name: 'Devs'),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serversProvider.overrideWith(() => _FakeServersController(servers)),
        ],
        child: const MaterialApp(home: Scaffold(body: ServerRail())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('G'), findsOneWidget); // inicial do servidor
    expect(find.text('D'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget); // botão de criar
  });

  testWidgets('Criar servidor valida nome vazio', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serversProvider.overrideWith(() => _FakeServersController(const [])),
        ],
        child: const MaterialApp(home: Scaffold(body: ServerEntryDialog())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Criar servidor'));
    await tester.pumpAndSettle();

    expect(find.text('Informe o nome do servidor.'), findsOneWidget);
  });
}
