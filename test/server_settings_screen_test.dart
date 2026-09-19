import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fourfun_cod_client/core/ui/app_icon.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/core/theme/app_theme.dart';
import 'package:fourfun_cod_client/features/servers/server_settings_modal.dart';
import 'package:fourfun_cod_client/features/servers/server_settings_screen.dart';
import 'package:fourfun_cod_client/features/servers/servers_providers.dart';
import 'package:fourfun_cod_client/shared/models/servers.dart';

const _server = Server(id: 'server-1', name: 'Servidor de teste');

class _AdminServerDetailController extends ServerDetailController {
  @override
  Future<ServerDetail> build(String serverId) async => const ServerDetail(
    server: _server,
    channels: [],
    members: [],
    myRole: ServerRole.admin,
  );
}

class _MemberServerDetailController extends ServerDetailController {
  @override
  Future<ServerDetail> build(String serverId) async => const ServerDetail(
    server: _server,
    channels: [],
    members: [],
    myRole: ServerRole.member,
  );
}

void main() {
  testWidgets(
    'ADMIN abre modal dedicado com formulário do servidor, sem opções pessoais',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            serverDetailProvider.overrideWith(_AdminServerDetailController.new),
          ],
          child: MaterialApp(
            theme: theme4funCod,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => unawaited(
                      showServerSettingsModal(context, serverId: 'server-1'),
                    ),
                    child: const Text('Abrir configurações'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir configurações'));
      await tester.pumpAndSettle();

      expect(find.text('Configurações do servidor'), findsOneWidget);
      expect(find.text('Administração'), findsOneWidget);
      expect(find.text('Administrador'), findsOneWidget);
      expect(find.byKey(const Key('server-settings-name')), findsOneWidget);
      expect(find.text('Nome do servidor'), findsOneWidget);
      expect(find.text('Alterar ícone'), findsOneWidget);
      expect(find.text('Salvar alterações'), findsOneWidget);

      for (final personalSettingsLabel in [
        'Conta',
        'Aparência',
        'Voz e Vídeo',
        'Notificações',
      ]) {
        expect(
          find.text(personalSettingsLabel),
          findsNothing,
          reason:
              'O modal do servidor não deve incluir a opção pessoal '
              '$personalSettingsLabel',
        );
      }
    },
  );

  testWidgets(
    'MEMBER em acesso direto vê bloqueio e nenhum formulário para salvar',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            serverDetailProvider.overrideWith(
              _MemberServerDetailController.new,
            ),
          ],
          child: MaterialApp(
            theme: theme4funCod,
            home: const ServerSettingsScreen(serverId: 'server-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Configurações do servidor'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is AppIcon && w.icon == AppIcons.lock), findsOneWidget);
      expect(
        find.text(
          'Apenas administradores podem acessar as configurações do servidor.',
        ),
        findsOneWidget,
      );
      expect(find.byType(Form), findsNothing);
      expect(find.byKey(const Key('server-settings-name')), findsNothing);
      expect(find.text('Nome do servidor'), findsNothing);
      expect(find.text('Salvar alterações'), findsNothing);
    },
  );
}
