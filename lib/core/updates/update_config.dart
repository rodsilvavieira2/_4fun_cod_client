/// Config pura do auto-update (sem dart:io → roda em teste e web).
///
/// Cobertura: Windows + Linux portátil, feed em GitHub Releases.
/// Web é no-op (stub) e macOS/mobile estão fora de escopo (AGENTS.md).
library;

/// `packageId` esperado pelo `release.json` em cada plataforma.
///
/// Windows = `name` do pubspec; Linux = `APPLICATION_ID` de
/// `linux/CMakeLists.txt`. Se o publish usar `--package-id`, o valor do
/// override tem que ser usado aqui (via [expectedPackageIdForPlatform]).
const String windowsPackageId = 'fourfun_cod_client';

/// Placeholder (`com.example.*`); trocar antes do primeiro publish e
/// republicar o feed com o mesmo `--package-id`.
const String linuxPackageId = 'com.example.u_4fun_cod_client';

/// Canal único nesta fase (estável).
const String updateChannel = 'stable';

/// Base do feed: `app-archive.json` sai de `<baseUrl>/app-archive.json`
/// (anexo da latest release). Ver `desktop_updater.yaml`.
const String updateBaseUrl =
    'https://github.com/rodsilvavieira2/_4fun_cod_client/releases/latest/download';

/// Página de releases (fallback de download manual).
const String updateReleasesPageUrl =
    'https://github.com/rodsilvavieira2/_4fun_cod_client/releases';

/// URL do índice assinado (`app-archive.json → release.json → artefato`).
Uri get updateAppArchiveUrl => Uri.parse('$updateBaseUrl/app-archive.json');

/// Retorna o `packageId` da plataforma ou `null` se fora de escopo.
String? expectedPackageIdForPlatform({
  required bool isWindows,
  required bool isLinux,
}) {
  if (isWindows) return windowsPackageId;
  if (isLinux) return linuxPackageId;
  return null;
}

/// Habilita update só em Windows/Linux não-web.
bool shouldEnableUpdates({
  required bool isWeb,
  required bool isLinux,
  required bool isWindows,
}) {
  if (isWeb) return false;
  return isLinux || isWindows;
}

/// Mapa keyId → chave pública Ed25519 pinada no app.
///
/// Placeholder até `dart run desktop_updater:release keygen`; a troca
/// acompanha [isUpdateSigningConfigured] (nunca commitar a privada).
const Map<String, String> trustedReleasePublicKeys = <String, String>{
  'release-placeholder': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
};

/// `true` quando houver chave real pinada. Enquanto `false`, o backend
/// nem faz request (startup silencioso, manual mostra "não configurado").
const bool isUpdateSigningConfigured = false;
