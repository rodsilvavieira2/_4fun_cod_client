import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../shared/models/voice.dart';
import '../servers/servers_providers.dart';
import 'voice_providers.dart';

/// Estado do link de transmissão do share local.
enum ShareLinkStatus { idle, creating, ready, error }

/// Link ativo (`ready`) + ciclo de criação/erro. `idle` = sem link (nunca
/// criado ou já encerrado — encerrar sempre volta para `idle`, sem tela de
/// "revogado": o link morreu junto com o share).
class ScreenShareLinkState {
  const ScreenShareLinkState({
    this.status = ShareLinkStatus.idle,
    this.link,
    this.errorMessage,
  });

  final ShareLinkStatus status;
  final ScreenShareLinkInfo? link;
  final String? errorMessage;

  ScreenShareLinkState copyWith({
    ShareLinkStatus? status,
    ScreenShareLinkInfo? link,
    String? errorMessage,
  }) {
    return ScreenShareLinkState(
      status: status ?? this.status,
      link: link ?? this.link,
      errorMessage: errorMessage,
    );
  }
}

/// Link de espectador do share local (`autoDispose.family` por canal).
///
/// Criação é explícita ([createLink], via dialog). A expiração é AUTOMÁTICA:
/// observa `isScreenSharing` e revoga best-effort no `true → false` com
/// carência de 5s (cobre parar pelo tile, pela control bar, `leave` e
/// disconnect, sem matar o link num flicker transitório — o webhook no
/// backend é o garantidor final). Revogar sempre volta para `idle`: novo
/// share exige link novo.
///
/// Fechar o dialog NÃO revoga: o dispose do provider só cancela o debounce
/// pendente. (Antes o `onDispose` revogava — como só o dialog observa este
/// provider, fechar o modal matava o link ~15s após copiar.)
class ScreenShareLinkController
    extends
        AutoDisposeFamilyNotifier<
          ScreenShareLinkState,
          ({String serverId, String channelId})
        > {
  /// Carência antes de revogar no fim do share (anti-flicker).
  static const stopRevokeGrace = Duration(seconds: 5);

  Timer? _stopDebounce;
  bool _disposed = false;

  @override
  ScreenShareLinkState build(({String serverId, String channelId}) arg) {
    ref.listen(
      voiceControllerProvider(arg).select((voice) => voice.isScreenSharing),
      (previous, next) {
        if (previous == true && next == false) {
          _scheduleStopRevoke();
        } else if (next == true) {
          _stopDebounce?.cancel();
        }
      },
    );
    ref.onDispose(() {
      // Só cancela o debounce: fechar o dialog / trocar de tela não é fim
      // de share. O fim real revoga via listener acima; o webhook garante.
      _disposed = true;
      _stopDebounce?.cancel();
    });
    return const ScreenShareLinkState();
  }

  /// Agenda a revogação do fim do share; cancela se voltar a compartilhar
  /// (ou o provider for descartado) dentro da carência.
  void _scheduleStopRevoke() {
    _stopDebounce?.cancel();
    final code = state.link?.code;
    if (code == null) return;
    _stopDebounce = Timer(stopRevokeGrace, () {
      if (_disposed) return;
      final sharing = ref.read(
        voiceControllerProvider(arg).select((voice) => voice.isScreenSharing),
      );
      if (sharing) return;
      if (state.link?.code != code) return;
      unawaited(revokeActive());
    });
  }

  /// Cria o link (`POST share-links`). Erro vira `error` com mensagem —
  /// a sessão de voz nunca é afetada.
  Future<void> createLink() async {
    if (state.status == ShareLinkStatus.creating) return;
    state = const ScreenShareLinkState(status: ShareLinkStatus.creating);
    try {
      final link = await ref
          .read(serversRepositoryProvider)
          .createScreenShareLink(arg.serverId, arg.channelId);
      state = ScreenShareLinkState(status: ShareLinkStatus.ready, link: link);
    } on ApiException catch (e) {
      state = ScreenShareLinkState(
        status: ShareLinkStatus.error,
        errorMessage: e.message,
      );
    } catch (_) {
      state = const ScreenShareLinkState(
        status: ShareLinkStatus.error,
        errorMessage: 'Não foi possível criar o link. Tente novamente.',
      );
    }
  }

  /// Encerra o link ativo (best-effort) e volta para `idle`.
  Future<void> revokeActive() async {
    final code = state.link?.code;
    state = const ScreenShareLinkState();
    if (code != null) await _revokeBestEffort(code);
  }

  Future<void> _revokeBestEffort(String code) async {
    try {
      await ref
          .read(serversRepositoryProvider)
          .revokeScreenShareLink(arg.serverId, arg.channelId, code);
    } catch (_) {
      // Best-effort: o webhook do LiveKit encerra de qualquer jeito.
    }
  }
}

/// Link de espectador do share local — `autoDispose.family`: ao trocar de
/// canal o provider é descartado sem revogar (o fim real do share revoga
/// via listener/webhook; fechar dialog não mata o link).
final screenShareLinkProvider =
    AutoDisposeNotifierProvider.family<
      ScreenShareLinkController,
      ScreenShareLinkState,
      ({String serverId, String channelId})
    >(ScreenShareLinkController.new);
