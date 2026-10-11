import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/core/api/api_exception.dart';
import 'package:fourfun_cod_client/features/servers/servers_providers.dart';
import 'package:fourfun_cod_client/features/servers/servers_repository.dart';
import 'package:fourfun_cod_client/features/voice/share_link_providers.dart';
import 'package:fourfun_cod_client/features/voice/voice_providers.dart';
import 'package:fourfun_cod_client/shared/models/voice.dart';

const _arg = (serverId: 's-1', channelId: 'c-1');

/// VoiceController fake: só o flag de share local interessa aqui (o resto
/// do ciclo de voz é coberto em `voice_controller_test.dart`).
class _FakeVoiceController extends VoiceController {
  @override
  VoiceState build(({String serverId, String channelId}) arg) =>
      const VoiceState();

  void setSharing(bool value) {
    state = state.copyWith(isScreenSharing: value);
  }
}

class _FakeServersRepository implements ServersRepository {
  int createCalls = 0;
  final List<String> revokedCodes = [];
  Object? createError;

  @override
  Future<ScreenShareLinkInfo> createScreenShareLink(
    String serverId,
    String channelId,
  ) async {
    createCalls++;
    final error = createError;
    if (error != null) throw error;
    return ScreenShareLinkInfo(
      code: 'CODE123456',
      url: 'http://localhost:3000/w/CODE123456',
    );
  }

  @override
  Future<void> revokeScreenShareLink(
    String serverId,
    String channelId,
    String code,
  ) async {
    revokedCodes.add(code);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('ScreenShareLinkController', () {
    late ProviderContainer container;
    late _FakeServersRepository repo;

    setUp(() {
      repo = _FakeServersRepository();
      container = ProviderContainer(
        overrides: [
          serversRepositoryProvider.overrideWithValue(repo),
          voiceControllerProvider.overrideWith(_FakeVoiceController.new),
        ],
      );
    });

    tearDown(() => container.dispose());

    /// Mantém o provider vivo (autoDispose) e devolve o notifier.
    ScreenShareLinkController buildLinks() {
      final sub = container.listen(screenShareLinkProvider(_arg), (_, _) {});
      addTearDown(sub.close);
      return container.read(screenShareLinkProvider(_arg).notifier);
    }

    ScreenShareLinkState state() =>
        container.read(screenShareLinkProvider(_arg));

    _FakeVoiceController voice() =>
        container.read(voiceControllerProvider(_arg).notifier)
            as _FakeVoiceController;

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('createLink → ready com o link do backend', () async {
      final notifier = buildLinks();
      expect(state().status, ShareLinkStatus.idle);

      await notifier.createLink();
      await settle();

      expect(repo.createCalls, 1);
      expect(state().status, ShareLinkStatus.ready);
      expect(state().link?.url, 'http://localhost:3000/w/CODE123456');
      expect(state().errorMessage, isNull);
    });

    test('createLink com erro → error com mensagem, sem derrubar nada', () async {
      repo.createError = const ApiException(message: 'Canal de voz esperado');
      final notifier = buildLinks();

      await notifier.createLink();
      await settle();

      expect(state().status, ShareLinkStatus.error);
      expect(state().errorMessage, 'Canal de voz esperado');
      expect(state().link, isNull);
    });

    test('fim do share (true→false) revoga o link após a carência', () async {
      final notifier = buildLinks();
      await notifier.createLink();
      await settle();
      expect(state().status, ShareLinkStatus.ready);

      voice().setSharing(true);
      await settle();
      expect(state().status, ShareLinkStatus.ready);

      voice().setSharing(false);
      await settle();
      // Dentro da carência ainda não revogou.
      expect(repo.revokedCodes, isEmpty);
      expect(state().status, ShareLinkStatus.ready);

      await Future<void>.delayed(
        ScreenShareLinkController.stopRevokeGrace + const Duration(seconds: 1),
      );

      expect(repo.revokedCodes, ['CODE123456']);
      expect(state().status, ShareLinkStatus.idle);
      expect(state().link, isNull);
    });

    test('flicker transitório (false→true na carência) não revoga', () async {
      buildLinks();
      await container
          .read(screenShareLinkProvider(_arg).notifier)
          .createLink();
      await settle();

      voice().setSharing(true);
      await settle();
      voice().setSharing(false);
      await settle();
      voice().setSharing(true);
      await Future<void>.delayed(
        ScreenShareLinkController.stopRevokeGrace + const Duration(seconds: 1),
      );

      expect(repo.revokedCodes, isEmpty);
      expect(state().status, ShareLinkStatus.ready);
    });

    test('fechar o dialog (dispose) NÃO revoga o link', () async {
      final sub = container.listen(screenShareLinkProvider(_arg), (_, _) {});
      await container
          .read(screenShareLinkProvider(_arg).notifier)
          .createLink();
      await settle();
      expect(state().status, ShareLinkStatus.ready);

      // Dialog fechado = sem listeners = autoDispose.
      sub.close();
      await settle();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(repo.revokedCodes, isEmpty);
    });

    test('fim do share sem link ativo não chama o backend', () async {
      buildLinks();
      voice().setSharing(true);
      await settle();
      voice().setSharing(false);
      await settle();

      expect(repo.revokedCodes, isEmpty);
      expect(state().status, ShareLinkStatus.idle);
    });

    test('revokeActive encerra explícito e volta a idle', () async {
      final notifier = buildLinks();
      await notifier.createLink();
      await settle();

      await notifier.revokeActive();
      await settle();

      expect(repo.revokedCodes, ['CODE123456']);
      expect(state().status, ShareLinkStatus.idle);
    });
  });
}
