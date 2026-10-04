import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/core/auth/auth_controller.dart';
import 'package:fourfun_cod_client/core/auth/auth_state.dart';
import 'package:fourfun_cod_client/core/ui/app_file_image.dart';
import 'package:fourfun_cod_client/core/ui/inputs/app_select.dart';
import 'package:fourfun_cod_client/core/ui/settings_sections/account_section.dart';
import 'package:fourfun_cod_client/features/profile/profile_repository.dart';
import 'package:fourfun_cod_client/features/servers/servers_providers.dart';
import 'package:fourfun_cod_client/shared/models/profile.dart';
import 'package:fourfun_cod_client/shared/models/servers.dart';
import 'package:fourfun_cod_client/shared/models/user.dart';

class _AuthenticatedController extends AuthController {
  @override
  Future<AuthState> build() async => const Authenticated(
    user: User(
      id: 'user-123',
      name: 'Ana Silva',
      username: 'ana_silva',
      email: 'ana@example.com',
      avatarUrl: 'https://example.com/avatar.png',
    ),
  );
}

class _ServersController extends ServersController {
  @override
  Future<List<Server>> build() async => [];
}

class _ProfileRepository extends ProfileRepository {
  _ProfileRepository() : super(Dio());

  static const profile = ProfileData(
    userId: 'user-123',
    username: 'ana_silva',
    displayName: 'Ana Silva',
    name: 'Ana Silva',
    status: 'ONLINE',
    style: {
      'fontId': 'geist',
      'effectId': 'solid',
      'colors': ['#5B76FF'],
    },
  );

  @override
  Future<ProfileEditorData> editor([String? serverId]) async =>
      const ProfileEditorData(
        resolved: profile,
        mainResolved: profile,
        main: {},
      );

  @override
  Future<List<CosmeticItem>> catalog() async => [];

  @override
  Future<List<ProfileFont>> fonts() async => [
    const ProfileFont(id: 'geist', name: 'Geist', family: 'Geist'),
  ];
}

void main() {
  Future<void> pumpAccountSection(WidgetTester tester) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_AuthenticatedController.new),
          serversProvider.overrideWith(_ServersController.new),
          profileRepositoryProvider.overrideWithValue(_ProfileRepository()),
          // Sem rede em teste: a imagem cai no fallback (inicial do avatar).
          fileImageBytesProvider(
            'https://example.com/avatar.png',
          ).overrideWith((ref) => throw StateError('rede desabilitada')),
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
    expect(find.text('Escolher avatar'), findsOneWidget);
    expect(find.text('Prévia do perfil'), findsOneWidget);
    await tester.tap(find.byTooltip('Fechar'));
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

  testWidgets(
    'editor mantém prévia e ações visíveis, com recorte sob demanda',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpAccountSection(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Editar').first);
      await tester.pumpAndSettle();

      final preview = find.text('Prévia do perfil');
      final form = find.text('Identidade');
      expect(
        tester.getTopLeft(preview).dx,
        greaterThan(tester.getTopLeft(form).dx),
      );
      expect(find.text('Recorte do avatar'), findsNothing);
      expect(find.text('Salvar'), findsOneWidget);
      final usernameField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Nome de usuário',
      );
      final helper = find.text(
        'Identificador único: 3–20 letras, números ou _',
      );
      expect(
        tester.getBottomLeft(find.text('Nome de usuário').first).dy,
        lessThan(tester.getTopLeft(usernameField).dy),
      );
      expect(
        tester.getBottomLeft(usernameField).dy,
        lessThan(tester.getTopLeft(helper).dy),
      );
      expect(
        tester.getBottomLeft(helper).dy,
        lessThan(tester.getTopLeft(find.text('Nome de exibição').first).dy),
      );

      await tester.ensureVisible(find.text('Ajustar recorte').first);
      await tester.tap(find.text('Ajustar recorte').first);
      await tester.pump();
      expect(find.text('Recorte do avatar'), findsOneWidget);

      await tester.ensureVisible(find.text('Sólido'));
      await tester.tap(find.text('Sólido'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gradiente'));
      await tester.pump();
      expect(
        tester
            .widgetList<AppSelect<String>>(find.byType(AppSelect<String>))
            .where((select) => select.label == 'Efeito')
            .single
            .value,
        'gradient',
      );

      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.hintText == 'Nome de exibição',
        ),
        'Ana Atualizada',
      );
      await tester.pump();
      expect(find.text('Ana Atualizada'), findsWidgets);
      expect(find.text('Alterações não salvas'), findsOneWidget);
    },
  );

  testWidgets('editor cabe em tela estreita com prévia e rodapé acessíveis', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpAccountSection(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Editar').first);
    await tester.pumpAndSettle();

    expect(find.text('Prévia do perfil'), findsOneWidget);
    expect(find.text('Salvar'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Prévia do perfil')).dy,
      lessThan(tester.getTopLeft(find.text('Identidade')).dy),
    );
    expect(tester.takeException(), isNull);
  });
}
