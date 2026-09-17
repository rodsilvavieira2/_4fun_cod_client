#!/usr/bin/env bash
# Release Linux — build UNICO versionado + deposita no share (fan-in Opcao A).
# Roda no step `release` de .woodpecker/build-linux.yaml (gate v* no yaml).
# Nao compila duas vezes: o step `ci` do yaml so builda em tags nao-v*.
# Nao sobe nada p/ a VPS: o workflow `publish` (depends_on) recolhe do share,
# assina, monta o feed e faz o upload unico pelo link rapido do host.
# Entradas: CI_COMMIT_TAG=vX.Y.Z, CI_PIPELINE_NUMBER, secrets via env
# (API_URL/LIVEKIT_URL/OTEL_*). Share montado em /share (volumes:, repo trusted).
set -euo pipefail

# shellcheck source=updates-common.sh
source "$(dirname "$0")/updates-common.sh"

echo "Release Linux $VERSION (build $BUILD_NUMBER) da tag $TAG"

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

# --- version stamp ANTES do build unico (exe == feed) ---
sed -i -E "s/^version: .*/version: $VERSION+$BUILD_NUMBER/" pubspec.yaml
grep '^version:' pubspec.yaml

# --- build unico versionado ---
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

# --- updater package (SEM sign: publish assina tudo de uma vez no host) ---
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

# --- deposita no share p/ o publish recolher (unico escritor daqui p/ frente) ---
OUT="$SHARE_ROOT/$TAG/linux"
mkdir -p "$OUT"
cp dist/linux/*.tar.gz dist/linux/*.AppImage "$OUT/"
cp dist/updater/linux/*.zip dist/updater/linux/release.json "$OUT/"
ls -lh "$OUT"
echo "artefatos Linux em $OUT - publish assume daqui"
