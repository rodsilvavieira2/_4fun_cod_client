#!/usr/bin/env bash
# Release Linux — build + publica o feed na VPS (SPEC spec-private-releases-vps).
# Roda dentro do step `release` de .woodpecker/build-linux.yaml (gate v* no yaml).
# Entradas: CI_COMMIT_TAG=vX.Y.Z, CI_PIPELINE_NUMBER, secrets via env
# (API_URL/LIVEKIT_URL/OTEL_*, UPDATES_DEPLOY_KEY_B64, UPDATER_BUNDLE_B64/UPDATER_PASSPHRASE).
set -euo pipefail

TAG="$CI_COMMIT_TAG"
VERSION="${TAG#v}"
BUILD_NUMBER="$CI_PIPELINE_NUMBER"
APP_NAME="4FunCode"
APP_SLUG="4fun-cod"
TMPD="$(mktemp -d)"

# --- feed na VPS ---
UPDATES_HOST="179.197.236.24"
UPDATES_USER="updates-deploy"
UPDATES_ROOT="/docker/updates/data"
UPDATES_BASE="https://updates.srv1849611.hstgr.cloud/$TAG"
UPDATES_LATEST="https://updates.srv1849611.hstgr.cloud/latest"
PINNED_HOSTKEY="179.197.236.24 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGD9/TjlwFN/vbVM1IQvCyqXK51vAU5gsov+LI9EiUvt"

echo "Release Linux $VERSION (build $BUILD_NUMBER) da tag $TAG"

setup_updates_ssh() {
  command -v sftp >/dev/null || { echo "sftp nao encontrado (openssh-client?)"; exit 1; }
  [ -n "${UPDATES_DEPLOY_KEY_B64:-}" ] || { echo "UPDATES_DEPLOY_KEY_B64 vazio (secret updates_deploy_key?)"; exit 1; }
  echo "$UPDATES_DEPLOY_KEY_B64" | base64 -d > "$TMPD/updates_deploy_key"
  chmod 600 "$TMPD/updates_deploy_key"
  printf '%s\n' "$PINNED_HOSTKEY" > "$TMPD/updates_known_hosts"
  SFTP_OPTS="-i $TMPD/updates_deploy_key -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$TMPD/updates_known_hosts -o ConnectTimeout=30"
  export SFTP_OPTS
}

# $1 = arquivo batch. mkdir do dir da tag tolera "ja existe" (Windows cria antes).
sftp_mkdir_tag() {
  printf 'mkdir %s/%s\n' "$UPDATES_ROOT" "$TAG" > "$TMPD/mkdir.batch"
  # shellcheck disable=SC2086
  sftp $SFTP_OPTS -b "$TMPD/mkdir.batch" "$UPDATES_USER@$UPDATES_HOST" >/dev/null 2>&1 || true
}

# --- sysdeps (mesmo step: container novo por step) + rustup ---
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y --no-install-recommends clang cmake git ninja-build pkg-config \
  libgtk-3-dev libsecret-1-dev libstdc++-12-dev libudev-dev libgstreamer1.0-dev \
  libgstreamer-plugins-base1.0-dev libunwind-dev libayatana-appindicator3-dev \
  liblzma-dev software-properties-common lsb-release \
  wget curl xz-utils zip unzip file patchelf zsync desktop-file-utils openssh-client ca-certificates
export PATH="$HOME/.cargo/bin:$HOME/.rustup/toolchains/stable-x86_64-unknown-linux-gnu/bin:$PATH"
if ! command -v cargo >/dev/null; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable
fi
rustc --version && cargo --version
flutter --version
flutter pub get

# --- version stamp (exe == feed): sem carimbo o updater nunca veria update ---
sed -i -E "s/^version: .*/version: $VERSION+$BUILD_NUMBER/" pubspec.yaml
grep '^version:' pubspec.yaml

# --- build versionado ---
set -o pipefail
flutter build linux -v \
  --release \
  --build-name "$VERSION" \
  --build-number "$BUILD_NUMBER" \
  --dart-define=API_URL="$API_URL" \
  --dart-define=LIVEKIT_URL="$LIVEKIT_URL" \
  --dart-define=OTEL_ENABLED="$OTEL_ENABLED" \
  --dart-define=OTEL_VIA_API="$OTEL_VIA_API" \
  --dart-define=OTEL_ENDPOINT="$OTEL_ENDPOINT" \
  --dart-define=OTEL_ORG="$OTEL_ORG" \
  >"$TMPD/build-linux-verbose.log" 2>&1 || {
  echo '--- build failed, verbose tail ---'
  tail -c 2000000 "$TMPD/build-linux-verbose.log"
  exit 1
}

# --- bundle tray native deps (fecho transitivo ayatana/appindicator) ---
BUNDLE="build/linux/x64/release/bundle"
PAT='lib(ayatana|appindicator|indicator|ido|dbusmenu)[^ ]*\.so\.[0-9]+'
for pass in 1 2 3 4; do
  NEW=0
  for so in "$BUNDLE"/lib/*.so "$BUNDLE"/_4fun_cod_client; do
    [ -f "$so" ] || continue
    for need in $(readelf -d "$so" 2>/dev/null | grep -o -E "$PAT" | sort -u); do
      if [ ! -f "$BUNDLE/lib/$need" ]; then
        path="$(ldconfig -p | grep -m1 -F "$need" | awk '{print $NF}')"
        if [ -n "$path" ]; then
          cp -L "$path" "$BUNDLE/lib/"
          echo "bundled: $need"
          NEW=1
        fi
      fi
    done
  done
  [ "$NEW" = 0 ] && break
done
MISSING=0
for so in "$BUNDLE"/lib/*.so; do
  for need in $(readelf -d "$so" 2>/dev/null | grep -o -E "$PAT" | sort -u); do
    if [ ! -f "$BUNDLE/lib/$need" ]; then
      echo "FALTANDO no bundle: $need (pedido por $so)"
      MISSING=1
    fi
  done
done
[ "$MISSING" = 0 ] || exit 1

# --- tar.gz ---
mkdir -p "package/$APP_SLUG" dist/linux
cp -a build/linux/x64/release/bundle/. "package/$APP_SLUG/"
tar -C package -czf "dist/linux/${APP_SLUG}-linux-x64-${VERSION}.tar.gz" "$APP_SLUG"
ls -lh dist/linux

# --- updater: chave + package + sign ---
echo "$UPDATER_BUNDLE_B64" | base64 -d > "$TMPD/release-key.dukey"
dart run desktop_updater:release keys import \
  --input "$TMPD/release-key.dukey" \
  --passphrase-env UPDATER_PASSPHRASE
shred -u "$TMPD/release-key.dukey"
dart run desktop_updater:package \
  --input "build/linux/x64/release/bundle" \
  --output "dist/updater/linux" \
  --package-id "io.github.rodsilvavieira2.fourfun" \
  --app-name "$APP_NAME" \
  --version "$VERSION" \
  --build-number "$BUILD_NUMBER" \
  --platform linux \
  --channel stable \
  --artifact-url "$UPDATES_BASE/$APP_NAME-$VERSION-linux.zip"
dart run desktop_updater:release sign --release "dist/updater/linux/release.json"

# --- AppImage ---
rm -rf AppDir
mkdir -p "AppDir/usr/bin" dist/linux
cp -a "$BUNDLE/." "AppDir/usr/bin/"
cp "packaging/linux/4fun-cod.desktop" "AppDir/4fun-cod.desktop"
cp "packaging/linux/4fun-cod.png" "AppDir/4fun-cod.png"
cat > AppDir/AppRun <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/usr/lib:$HERE/usr/bin/lib:$LD_LIBRARY_PATH"
exec "$HERE/usr/bin/_4fun_cod_client" "$@"
EOF
chmod +x AppDir/AppRun
wget -q "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage" -O appimagetool
chmod +x appimagetool
./appimagetool --appimage-extract-and-run AppDir "dist/linux/${APP_SLUG}-linux-x64-${VERSION}.AppImage"
ls -lh dist/linux

# --- espera o Windows subir o sentinel no feed da VPS ---
echo "aguardando .windows-done em $UPDATES_BASE ..."
for i in $(seq 1 90); do
  if curl -sfL "$UPDATES_BASE/.windows-done" -o /dev/null; then
    echo "sentinel encontrado apos ~$((i - 1))min"
    break
  fi
  [ "$i" = 90 ] && { echo "timeout esperando o job Windows"; exit 1; }
  sleep 60
done

# --- baixa artefatos Windows do feed da VPS ---
mkdir -p dist/updater/updater-windows
curl -sfL "$UPDATES_BASE/${APP_SLUG}-windows-x64-${VERSION}-portable.zip" -o "dist/${APP_SLUG}-windows-x64-${VERSION}-portable.zip"
curl -sfL "$UPDATES_BASE/${APP_SLUG}-windows-x64-${VERSION}-setup.exe" -o "dist/${APP_SLUG}-windows-x64-${VERSION}-setup.exe"
curl -sfL "$UPDATES_BASE/$APP_NAME-$VERSION-windows.zip" -o "dist/updater/updater-windows/$APP_NAME-$VERSION-windows.zip"
curl -sfL "$UPDATES_BASE/release-windows.json" -o dist/updater/updater-windows/release-windows.json
ls -lh dist/ dist/updater/updater-windows/
[ -f dist/updater/updater-windows/release-windows.json ] || { echo "release-windows.json nao veio"; exit 1; }

# --- feed (linux + windows): estende o publicado (VPS, fallback GitHub, ou novo) ---
mkdir -p dist/updater/feed
cp dist/updater/linux/release.json dist/updater/feed/release-linux.json
cp dist/updater/updater-windows/release-windows.json dist/updater/feed/release-windows.json
cp dist/updater/linux/*.zip dist/updater/feed/
cp dist/updater/updater-windows/*.zip dist/updater/feed/
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

# --- SHA256 dos arquivos publicados ---
mkdir -p dist/tag
cp dist/linux/*.tar.gz dist/linux/*.AppImage dist/tag/
cp dist/updater/feed/*.zip dist/updater/feed/release-*.json dist/updater/feed/app-archive.json dist/tag/
cd dist/tag
sha256sum ./*.tar.gz ./*.AppImage ./*.zip ./*.json > SHA256SUMS.txt
cat SHA256SUMS.txt
cd ../..

# --- upload p/ updates/<tag>/ + publica updates/latest/ + verifica ---
# sftp -b ABORTA no primeiro erro: mkdir de dir existente mataria os puts.
# mkdirs tolerantes vao em chamadas separadas (|| true); o batch so tem puts.
setup_updates_ssh
sftp_mkdir_tag
printf 'mkdir %s/latest\n' "$UPDATES_ROOT" > "$TMPD/mkdir-latest.batch"
# shellcheck disable=SC2086
sftp $SFTP_OPTS -b "$TMPD/mkdir-latest.batch" "$UPDATES_USER@$UPDATES_HOST" >/dev/null 2>&1 || true
{
  for f in dist/tag/*; do printf 'put %s %s/%s/\n' "$f" "$UPDATES_ROOT" "$TAG"; done
  printf 'put %s %s/%s/\n' "dist/${APP_SLUG}-windows-x64-${VERSION}-portable.zip" "$UPDATES_ROOT" "$TAG"
  printf 'put %s %s/%s/\n' "dist/${APP_SLUG}-windows-x64-${VERSION}-setup.exe" "$UPDATES_ROOT" "$TAG"
} > "$TMPD/upload.batch"
# shellcheck disable=SC2086
sftp $SFTP_OPTS -b "$TMPD/upload.batch" "$UPDATES_USER@$UPDATES_HOST"
# Um `put` por linha: glob com 2 arquivos na mesma linha vira remoto invalido.
{
  for f in dist/tag/"$APP_NAME"-*.zip dist/tag/release-*.json dist/tag/app-archive.json; do
    printf 'put %s %s/latest/\n' "$f" "$UPDATES_ROOT"
  done
} > "$TMPD/latest.batch"
# shellcheck disable=SC2086
sftp $SFTP_OPTS -b "$TMPD/latest.batch" "$UPDATES_USER@$UPDATES_HOST" >/dev/null 2>&1 || \
sftp $SFTP_OPTS -b "$TMPD/latest.batch" "$UPDATES_USER@$UPDATES_HOST"
shred -u "$TMPD/updates_deploy_key"
cp desktop_updater.keys.json dist/desktop_updater.keys.json
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
