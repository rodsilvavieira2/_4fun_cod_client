import 'package:flutter_test/flutter_test.dart';
import 'package:fourfun_cod_client/core/websocket/realtime_event.dart';
import 'package:fourfun_cod_client/shared/models/servers.dart';

void main() {
  group('ServerRole', () {
    test('expõe a matriz de capacidades da hierarquia', () {
      expect(ServerRole.owner.canManageServer, isTrue);
      expect(ServerRole.owner.canManageRoles, isTrue);
      expect(ServerRole.owner.canRemove(ServerRole.admin), isTrue);

      expect(ServerRole.admin.canManageServer, isTrue);
      expect(ServerRole.admin.canManageRoles, isFalse);
      expect(ServerRole.admin.canRemove(ServerRole.member), isTrue);
      expect(ServerRole.admin.canRemove(ServerRole.admin), isFalse);

      expect(ServerRole.member.canManageServer, isFalse);
      expect(ServerRole.member.canManageRoles, isFalse);
      expect(ServerRole.member.canRemove(ServerRole.member), isFalse);
    });

    test('converte os valores do contrato da API', () {
      expect(ServerRole.fromApi('OWNER'), ServerRole.owner);
      expect(ServerRole.fromApi('ADMIN'), ServerRole.admin);
      expect(ServerRole.fromApi('MEMBER'), ServerRole.member);
      expect(ServerRole.fromApi('UNKNOWN'), isNull);
    });
  });

  test('ServerDetail preserva os cargos do usuário e dos membros', () {
    final detail = ServerDetail.fromJson({
      'server': {'id': 'server-1', 'name': '4fun', 'iconUrl': null},
      'channels': <Object?>[],
      'members': [
        {
          'id': 'membership-1',
          'userId': 'user-1',
          'role': 'ADMIN',
          'joinedAt': '2026-09-04T00:00:00.000Z',
          'user': {
            'id': 'user-1',
            'name': 'Rodrigo',
            'username': 'rodrigo',
            'avatarUrl': null,
          },
        },
      ],
      'myRole': 'ADMIN',
    });

    expect(detail.myRole, ServerRole.admin);
    expect(detail.canManageServer, isTrue);
    expect(detail.members.single.role, ServerRole.admin);
  });

  test('evento realtime de cargo é tipado e mantém o escopo do servidor', () {
    final event = RealtimeEvent.fromJson('member.role_updated', {
      'serverId': 'server-1',
      'userId': 'user-1',
      'role': 'ADMIN',
    });

    expect(event, isA<MemberRoleUpdatedEvent>());
    final roleEvent = event! as MemberRoleUpdatedEvent;
    expect(roleEvent.serverId, 'server-1');
    expect(roleEvent.userId, 'user-1');
    expect(roleEvent.role, ServerRole.admin);
  });
}
