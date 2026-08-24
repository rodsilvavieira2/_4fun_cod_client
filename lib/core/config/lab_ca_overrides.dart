import 'dart:io' show HttpClient, HttpOverrides, SecurityContext;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;

/// Confiança na CA do lab para o client DESKTOP (não-web).
///
/// O dart:io NÃO lê o trust store do sistema (NSS/etc.) — usa o bundle de
/// CAs embutido no SDK. O lab serve cert autoassinado pela "4fun Lab CA"
/// (proxy nginx 7443/8443/9443, ver stack em ~/work/config/lab/stacks/4fun_cod).
/// Sem esta confiança, o `room.connect('wss://192.168.0.217:7443', …)`
/// falha instantâneo e SILENCIOSO com CERTIFICATE_VERIFY_FAILED (34ms) —
/// o `/join` dá 200 mas a conexão LiveKit morre antes de tocar na rede
/// (nada chega ao nginx 7443). Sintoma do bug: join 200 + nenhum log de RTC.
///
/// Web NÃO precisa: o browser usa o trust store do SO/Chrome (a CA já é
/// instalada via NSS/certutil — ver skill 4fun-cod-codebase).
class LabCaOverrides extends HttpOverrides {
  LabCaOverrides(this._context);

  final SecurityContext _context;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context ?? _context);
}

/// Carrega `assets/certs/ca.crt` e faz TODO HttpClient do dart:io
/// (dio, livekit_client, socket.io) confiar nela, além das CAs raiz do SDK
/// (`withTrustedRoots: true` preserva o acesso ao resto da internet).
/// No-op em web. Chamar UMA vez no main(), após ensureInitialized().
Future<void> trustLabCa() async {
  if (kIsWeb) return;
  final caBytes = await rootBundle.load('assets/certs/ca.crt');
  final context = SecurityContext(withTrustedRoots: true)
    ..setTrustedCertificatesBytes(
      caBytes.buffer.asUint8List(caBytes.offsetInBytes, caBytes.lengthInBytes),
    );
  HttpOverrides.global = LabCaOverrides(context);
}
