/// Config pura do auto-update (sem dart:io → roda em teste e web).
///
/// Cobertura: Windows + Linux portátil, feed na VPS
/// (`updates.srv1849611.hstgr.cloud/latest`).
/// Web é no-op (stub) e macOS/mobile estão fora de escopo (AGENTS.md).
library;

/// `packageId` esperado pelo `release.json` em cada plataforma.
///
/// Windows = `name` do pubspec; Linux = `APPLICATION_ID` de
/// `linux/CMakeLists.txt`. Se o publish usar `--package-id`, o valor do
/// override tem que ser usado aqui (via [expectedPackageIdForPlatform]).
const String windowsPackageId = 'fourfun_cod_client';

/// ID de produção (opção B, ancorado no GitHub). Deve ser idêntico ao
/// `APPLICATION_ID` de `linux/CMakeLists.txt` e ao `--package-id` do
/// `dart run desktop_updater:release publish --platform linux`.
/// Imutável na prática após o primeiro feed publicado.
const String linuxPackageId = 'io.github.rodsilvavieira2.fourfun';

/// Canal único nesta fase (estável).
const String updateChannel = 'stable';

/// Base do feed: `app-archive.json` sai de `<baseUrl>/app-archive.json`
/// (feed estático na VPS — SPEC spec-private-releases-vps 2026-09-17).
const String updateBaseUrl = 'https://updates.srv1849611.hstgr.cloud/latest';

/// Listing do feed na VPS (fallback de download manual quando a versão
/// ainda é desconhecida).
const String updatesReleasesListingUrl =
    'https://updates.srv1849611.hstgr.cloud/latest/';

/// Extrai o core semver de `versão+build` (`1.2.4+59` → `1.2.4`).
/// Retorna `null` quando o rótulo é nulo, vazio ou inválido.
String? extractUpdateVersionCore(String? versionLabel) {
  final raw = versionLabel?.trim();
  if (raw == null || raw.isEmpty) return null;
  final core = raw.split('+').first.trim();
  if (core.isEmpty) return null;
  final ok = RegExp(r'^\d+\.\d+\.\d+$').hasMatch(core);
  return ok ? core : null;
}

/// URL de download manual direto da VPS por plataforma.
///
/// Linux → `tar.gz` (extração, cobre auto-update); Windows → `setup.exe`
/// (Inno). Sem versão conhecida, retorna o listing `/latest/`.
String manualDownloadUrl({
  required bool isWindows,
  required bool isLinux,
  String? latestVersion,
}) {
  final version = extractUpdateVersionCore(latestVersion);
  if (version == null) return updatesReleasesListingUrl;
  if (isWindows) {
    return 'https://updates.srv1849611.hstgr.cloud/v$version/4fun-cod-windows-x64-$version-setup.exe';
  }
  if (isLinux) {
    return 'https://updates.srv1849611.hstgr.cloud/v$version/4fun-cod-linux-x64-$version.tar.gz';
  }
  return updatesReleasesListingUrl;
}

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
/// Gerado via `dart run desktop_updater:release keygen` (keyId
/// `release-de4dba08820a7c59511f86ce`). A privada vive só no bundle
/// criptografado (secrets `DESKTOP_UPDATER_KEY_BUNDLE` /
/// `DESKTOP_UPDATER_KEY_PASSPHRASE`) — nunca commitar a privada.
const Map<String, String> trustedReleasePublicKeys = <String, String>{
  'release-de4dba08820a7c59511f86ce':
      'MUceP/D/eQGYTiNhtcu3B6p0czGJW+LVWsHyhUjkJgE=',
};

/// `true` quando houver chave real pinada. Enquanto `false`, o backend
/// nem faz request (startup silencioso, manual mostra "não configurado").
const bool isUpdateSigningConfigured = true;
