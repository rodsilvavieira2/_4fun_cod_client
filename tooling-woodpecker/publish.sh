#!/usr/bin/env bash
# Publish — recolhe linux+windows do share, assina, monta o feed e sobe p/ VPS.
# Roda no workflow `publish` (.woodpecker/publish.yaml, depends_on dos builds).
# Unico escritor na VPS: dois uploads concorrentes nunca disputam os mesmos paths.
# BUILD_NUMBER e o mesmo do pipeline: os dois lados carimbaram com ele, sem
# mistura de builds (o sentinel com build-id morreu junto com o sftp na VM).
# Entradas: CI_COMMIT_TAG=vX.Y.Z, CI_PIPELINE_NUMBER, secrets via env
# (UPDATES_DEPLOY_KEY_B64, UPDATER_BUNDLE_B64/UPDATER_PASSPHRASE).
# Share montado em /share (volumes:, repo trusted).
set -euo pipefail

# shellcheck source=updates-common.sh
source "$(dirname "$0")/updates-common.sh"

echo "Publish $VERSION (build $BUILD_NUMBER) da tag $TAG"

export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y --no-install-recommends \
  curl ca-certificates openssh-client python3 >/dev/null
flutter --version
flutter pub get

# --- fail fast: o share tem tudo dos dois lados? ---
IN="$SHARE_ROOT/$TAG"
missing=0
for f in \
  "$IN/linux/${APP_SLUG}-linux-x64-${VERSION}.tar.gz" \
  "$IN/linux/${APP_SLUG}-linux-x64-${VERSION}.AppImage" \
  "$IN/linux/$APP_NAME-$VERSION-linux.zip" \
  "$IN/linux/release.json" \
  "$IN/windows/${APP_SLUG}-windows-x64-${VERSION}-portable.zip" \
  "$IN/windows/$APP_NAME-$VERSION-windows.zip" \
  "$IN/windows/release.json"; do
  [ -f "$f" ] || { echo "FALTANDO no share: $f"; missing=1; }
done
[ "$(find "$IN/windows" -maxdepth 1 -name '*.exe' | wc -l)" -ge 1 ] \
  || { echo "FALTANDO no share: setup.exe do Windows"; missing=1; }
if [ "$missing" = 1 ]; then
  echo "--- conteudo do share ---"
  find "$IN" -type f | sort
  exit 1
fi

# --- chave (file store no container: sem DPAPI, sem flake) + sign dos dois ---
echo "$UPDATER_BUNDLE_B64" | base64 -d > "$TMPD/release-key.dukey"
dart run desktop_updater:release keys import \
  --input "$TMPD/release-key.dukey" \
  --passphrase-env UPDATER_PASSPHRASE
shred -u "$TMPD/release-key.dukey"
mkdir -p dist/updater/feed
cp "$IN/linux/release.json" dist/updater/feed/release-linux.json
cp "$IN/windows/release.json" dist/updater/feed/release-windows.json
cp "$IN/linux/$APP_NAME-$VERSION-linux.zip" "$IN/windows/$APP_NAME-$VERSION-windows.zip" dist/updater/feed/
dart run desktop_updater:release sign --release dist/updater/feed/release-linux.json
dart run desktop_updater:release sign --release dist/updater/feed/release-windows.json

# --- feed (linux + windows): estende o publicado (VPS, fallback GitHub, ou novo) ---
if curl -sfL "$UPDATES_LATEST/app-archive.json" -o dist/updater/feed/app-archive.json; then
  echo "extending VPS feed"
  python3 -c "import json; p='dist/updater/feed/app-archive.json'; d=json.load(open(p)); d.pop('signature', None); json.dump(d, open(p, 'w'), indent=2)"
elif curl -sfL "https://github.com/rodsilvavieira2/_4fun_cod_client/releases/latest/download/app-archive.json" \
    -o dist/updater/feed/app-archive.json; then
  echo "seeding VPS feed from GitHub"
  python3 -c "import json; p='dist/updater/feed/app-archive.json'; d=json.load(open(p)); d.pop('signature', None); json.dump(d, open(p, 'w'), indent=2)"
else
  echo "first feed release"
  rm -f dist/updater/feed/app-archive.json
fi
for platform in linux windows; do
  dart run desktop_updater:app_archive upsert \
    --archive dist/updater/feed/app-archive.json \
    --app-name "$APP_NAME" \
    --version "$VERSION" \
    --build-number "$BUILD_NUMBER" \
    --platform "$platform" \
    --channel stable \
    --release-url "$UPDATES_BASE/release-$platform.json"
done
dart run desktop_updater:release sign --app-archive dist/updater/feed/app-archive.json

# --- SHA256 de tudo que sera publicado ---
mkdir -p dist/tag
cp "$IN/linux/"*.tar.gz "$IN/linux/"*.AppImage dist/tag/
cp "$IN/windows/"*-portable.zip "$IN/windows/"*.exe dist/tag/
cp dist/updater/feed/*.zip dist/updater/feed/release-*.json dist/updater/feed/app-archive.json dist/tag/
cd dist/tag
sha256sum ./*.tar.gz ./*.AppImage ./*.zip ./*.exe ./*.json > SHA256SUMS.txt
cat SHA256SUMS.txt
cd ../..

# --- upload unico p/ updates/<tag>/ + publica updates/latest/ + verifica ---
# sftp -b ABORTA no primeiro erro: mkdirs tolerantes vao isolados (|| true),
# batch so com puts, um por linha (glob duplo na mesma linha vira remoto invalido).
setup_updates_ssh
sftp_mkdir "$UPDATES_ROOT/$TAG"
sftp_mkdir "$UPDATES_ROOT/latest"
{
  for f in dist/tag/*; do printf 'put %s %s/%s/\n' "$f" "$UPDATES_ROOT" "$TAG"; done
} > "$TMPD/upload.batch"
# shellcheck disable=SC2086
sftp $SFTP_OPTS -b "$TMPD/upload.batch" "$UPDATES_USER@$UPDATES_HOST"
{
  for f in dist/tag/"$APP_NAME"-*.zip dist/tag/release-*.json dist/tag/app-archive.json; do
    printf 'put %s %s/latest/\n' "$f" "$UPDATES_ROOT"
  done
} > "$TMPD/latest.batch"
# shellcheck disable=SC2086
sftp $SFTP_OPTS -b "$TMPD/latest.batch" "$UPDATES_USER@$UPDATES_HOST" >/dev/null 2>&1 || \
sftp $SFTP_OPTS -b "$TMPD/latest.batch" "$UPDATES_USER@$UPDATES_HOST"
shred -u "$TMPD/updates_deploy_key"
for platform in linux windows; do
  for i in $(seq 1 12); do
    curl -sfL "$UPDATES_LATEST/release-$platform.json" -o "$TMPD/hosted-release-$platform.json" && break
    [ "$i" = 12 ] && { echo "verificacao hospedada falhou: release-$platform.json"; exit 1; }
    sleep 10
  done
done
for i in $(seq 1 12); do
  curl -sfL "$UPDATES_LATEST/app-archive.json" -o "$TMPD/hosted-app-archive.json" && break
  [ "$i" = 12 ] && { echo "verificacao hospedada falhou: app-archive.json"; exit 1; }
  sleep 10
done
for platform in linux windows; do
  dart run desktop_updater:verify --release "$TMPD/hosted-release-$platform.json"
done
echo "hosted feed OK — release $TAG publicada na VPS"

# --- limpa a area de transferencia (proxima tag comeca zerada) ---
rm -rf "$IN"
echo "share limpo: $IN"
