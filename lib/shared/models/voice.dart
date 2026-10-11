/// Informações para entrar num canal de voz (Fase 4 — LiveKit).
///
/// Resposta do `POST /servers/:serverId/channels/:channelId/join`: o token
/// é emitido SÓ pelo backend (10m de validade) e o cliente nunca tem o
/// secret de assinatura.
class VoiceJoinInfo {
  const VoiceJoinInfo({
    required this.livekitUrl,
    required this.token,
    required this.roomName,
  });

  /// Campos em camelCase, como o backend devolve.
  factory VoiceJoinInfo.fromJson(Map<String, dynamic> json) => VoiceJoinInfo(
    livekitUrl: json['livekitUrl'] as String,
    token: json['token'] as String,
    roomName: json['roomName'] as String,
  );

  /// URL WebSocket do servidor LiveKit.
  final String livekitUrl;

  /// Token JWT de acesso à sala (emitido pelo NestJS).
  final String token;

  /// Nome da sala LiveKit (`ch_<channelId>`).
  final String roomName;
}

/// Link de transmissão — `POST /servers/:serverId/channels/:channelId/share-links`.
///
/// Capability URL (`/w/<code>`) que abre o espectador em qualquer browser.
/// Expira quando a transmissão termina (novo share exige link novo).
class ScreenShareLinkInfo {
  const ScreenShareLinkInfo({
    required this.code,
    required this.url,
    this.expiresAt,
  });

  factory ScreenShareLinkInfo.fromJson(Map<String, dynamic> json) =>
      ScreenShareLinkInfo(
        code: json['code'] as String,
        url: json['url'] as String,
        expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
      );

  final String code;
  final String url;
  final DateTime? expiresAt;
}
