#!/usr/bin/env bash
# Release Linux — espelho fiel de .github/workflows/release-desktop.yml (job build-linux + parte linux do job release).
# Roda dentro do step `release` de .woodpecker/build-linux.yaml (gate v* no yaml).
# Entradas: CI_COMMIT_TAG=vX.Y.Z, CI_PIPELINE_NUMBER, secrets via env
# (API_URL/LIVEKIT_URL/OTEL_*, GH_TOKEN, UPDATER_BUNDLE_B64/UPDATER_PASSPHRASE).
set -euo pipefail

TAG="$CI_COMMIT_TAG"
VERSION="${TAG#v}"
BUILD_NUMBER="$CI_PIPELINE_NUMBER"
APP_NAME="4FunCode"
APP_SLUG="4fun-cod"
TMPD="$(mktemp -d)"

echo "Release Linux $VERSION (build $BUILD_NUMBER) da tag $TAG"

# --- sysdeps (mesmo step: container novo por step) + gh + rustup ---
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y --no-install-recommends clang cmake git ninja-build pkg-config \
  libgtk-3-dev libsecret-1-dev libstdc++-12-dev libudev-dev libgstreamer1.0-dev \
  libgstreamer-plugins-base1.0-dev libunwind-dev libayatana-appindicator3-dev \
  liblzma-dev software-properties-common lsb-release \
  wget curl xz-utils zip unzip file patchelf zsync desktop-file-utils gh ca-certificates
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
  --artifact-url "https://github.com/rodsilvavieira2/_4fun_cod_client/releases/download/$TAG/$APP_NAME-$VERSION-linux.zip"
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

# --- espera o Windows subir o sentinel no draft ---
echo "aguardando release-windows.json no draft $TAG..."
for i in $(seq 1 90); do
  if gh release view "$TAG" --json assets --jq '.assets[].name' 2>/dev/null | grep -qx 'release-windows.json'; then
    echo "sentinel encontrado apos ~$((i - 1))min"
    break
  fi
  [ "$i" = 90 ] && { echo "timeout esperando o job Windows"; gh release view "$TAG" --json assets --jq '.assets[].name'; exit 1; }
  sleep 60
done

# --- baixa artefatos Windows do draft ---
gh release download "$TAG" -p "${APP_SLUG}-windows-x64-*-portable.zip" -p "${APP_SLUG}-*-setup.exe" -D dist/
gh release download "$TAG" -p "$APP_NAME-*-windows.zip" -p 'release-windows.json' -D dist/updater/updater-windows/
ls -lh dist/ dist/updater/updater-windows/
[ -f dist/updater/updater-windows/release-windows.json ] || { echo "release-windows.json nao veio"; exit 1; }

# --- feed (linux + windows) ---
BASE="https://github.com/rodsilvavieira2/_4fun_cod_client/releases/download/$TAG"
mkdir -p dist/updater/feed
cp dist/updater/updater-linux/release.json dist/updater/feed/release-linux.json
cp dist/updater/updater-windows/release.json dist/updater/feed/release-windows.json
cp dist/updater/updater-linux/*.zip dist/updater/feed/
cp dist/updater/updater-windows/*.zip dist/updater/feed/
if curl -sfL "https://github.com/rodsilvavieira2/_4fun_cod_client/releases/latest/download/app-archive.json" \
    -o dist/updater/feed/app-archive.json; then
  echo "extending published feed"
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
    --release-url "$BASE/release-$platform.json"
done
dart run desktop_updater:release sign --app-archive dist/updater/feed/app-archive.json

# --- SHA256 dos arquivos raiz ---
cd dist
find . -maxdepth 1 -type f -exec sha256sum {} + > SHA256SUMS.txt
cat SHA256SUMS.txt
cd ..

# --- upload restante + publica + verifica ---
gh release upload "$TAG" dist/*.tar.gz dist/*.AppImage dist/updater/feed/*.zip dist/updater/feed/release-*.json dist/SHA256SUMS.txt --clobber
gh release upload "$TAG" dist/updater/feed/app-archive.json --clobber
gh release edit "$TAG" --draft=false
cp desktop_updater.keys.json dist/desktop_updater.keys.json
cd dist
for platform in linux windows; do
  for i in $(seq 1 12); do
    gh release download "$TAG" -p "release-$platform.json" -D "$TMPD/hosted" --clobber && break
    [ "$i" = 12 ] && { echo "verificacao hospedada falhou: release-$platform.json"; exit 1; }
    sleep 10
  done
done
for i in $(seq 1 12); do
  gh release download "$TAG" -p "app-archive.json" -D "$TMPD/hosted" --clobber && break
  [ "$i" = 12 ] && { echo "verificacao hospedada falhou: app-archive.json"; exit 1; }
  sleep 10
done
cd ..
for platform in linux windows; do
  dart run desktop_updater:verify --release "$TMPD/hosted/release-$platform.json"
done
echo "hosted feed OK — release $TAG publicada"
