# Release Windows - build UNICO versionado + deposita no share (fan-in Opcao A).
# Roda no step `release` de .woodpecker/build-windows.yaml (gate v* abaixo).
# Nao compila duas vezes: o step `build` do yaml so builda em tags nao-v*.
# Nao assina nem sobe nada: sem DPAPI na VM, sem sftp pelo NAT.
# O workflow `publish` (depends_on) recolhe do share, assina, monta o feed
# e faz o upload unico pelo link rapido do host.
# Destino: Z:\<tag>\windows\ (= <repo>/infra/windows/<tag>/windows no host).
$ErrorActionPreference = 'Stop'

$TAG = $env:CI_COMMIT_TAG
if (-not $TAG -or -not $TAG.StartsWith('v')) { Write-Host 'skip: nao e tag v*'; exit 78 }
$APP_VERSION = $TAG.TrimStart('v')
$BN = $env:CI_PIPELINE_NUMBER
$APP_NAME = '4FunCode'
$APP_SLUG = '4fun-cod'
$UPDATES_BASE = "https://updates.srv1849611.hstgr.cloud/$TAG"

Write-Host "Release Windows $APP_VERSION (build $BN) da tag $TAG"

# --- version stamp ANTES do build unico (exe == feed) ---
(Get-Content pubspec.yaml) -replace '^version: .*', "version: $APP_VERSION+$BN" | Set-Content pubspec.yaml
Select-String '^version:' pubspec.yaml

# --- bridge incremental (garante target/release/DirectML.dll; cache ORT intacto) ---
$env:ORT_CACHE_DIR = Join-Path $env:USERPROFILE '.cache\ort-cache'
$env:RUSTUP_TOOLCHAIN = 'stable'
$env:PATH = "$env:USERPROFILE\.rustup\toolchains\stable-x86_64-pc-windows-msvc\bin;$env:USERPROFILE\.cargo\bin;$env:PATH"
cargo build --release --manifest-path native/deepfilter_bridge/Cargo.toml
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$dfbinDll = Get-ChildItem (Join-Path $env:ORT_CACHE_DIR 'dfbin') -Recurse -Filter DirectML.dll |
  Where-Object { $_.Length -gt 0 } | Select-Object -First 1 -ExpandProperty FullName
if (-not $dfbinDll) { Write-Error 'DirectML.dll nao baixado'; exit 1 }

# --- build unico versionado ---
$bridge = Join-Path (Get-Location) 'native\deepfilter_bridge'
$stage = Join-Path $bridge 'target\stage-windows'
$vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
$roots = @()
if (Test-Path $vswhere) { $roots += & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath }
$dumpbin = $null
foreach ($r in ($roots | Where-Object { $_ } | Sort-Object -Unique)) {
  $cand = Get-ChildItem "$r\VC\Tools\MSVC" -Filter dumpbin.exe -Recurse -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName
  if ($cand) { $dumpbin = $cand; break }
}
if (-not $dumpbin) { Write-Error 'dumpbin nao encontrado'; exit 1 }
$libexe = Join-Path (Split-Path $dumpbin) 'lib.exe'
$cmake = $null
try { $cmake = (Get-Command cmake -ErrorAction Stop).Source } catch { $cmake = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' }
$cargs = @("-DBRIDGE_DIR=$bridge", "-DSTAGE_DIR=$stage", "-DSTAGE_DLL=$stage\DirectML.dll", "-DSTAGE_LIB=$stage\DirectML.lib", "-DDUMPBIN_EXE=$dumpbin", "-DLIB_EXE=$libexe", "-DFOURFUN_DFBIN_DLL=$dfbinDll")
& $cmake @cargs -P packages/flutter_webrtc/windows/stage_ort_windows.cmake
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
flutter build windows --release --build-name $APP_VERSION --build-number $BN `
  --dart-define=API_URL=$env:API_URL --dart-define=LIVEKIT_URL=$env:LIVEKIT_URL `
  --dart-define=OTEL_ENABLED=$env:OTEL_ENABLED --dart-define=OTEL_VIA_API=$env:OTEL_VIA_API `
  --dart-define=OTEL_ENDPOINT=$env:OTEL_ENDPOINT --dart-define=OTEL_ORG=$env:OTEL_ORG
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# --- assert dumpbin resolveu (mesma checagem da GHA) ---
$BUNDLE = 'build\windows\x64\runner\Release'
& $dumpbin /DEPENDENTS "$BUNDLE\_4fun_cod_client.exe" | Out-String | Write-Host
$dllDeps = & $dumpbin /DEPENDENTS "$BUNDLE\flutter_webrtc_plugin.dll" 2>$null | Out-String
if ($dllDeps -notmatch 'DirectML\.dll') { Write-Error 'flutter_webrtc_plugin.dll nao referencia DirectML.dll'; exit 1 }

# --- portable + installer ---
$redistUrl = 'https://aka.ms/vs/17/release/vc_redist.x64.exe'
Invoke-WebRequest -Uri $redistUrl -OutFile "$BUNDLE\vc_redist.x64.exe"
$portable = "dist\${APP_SLUG}-windows-x64-${APP_VERSION}-portable.zip"
New-Item -ItemType Directory -Force -Path 'dist' | Out-Null
Compress-Archive -Path "$BUNDLE\*" -DestinationPath $portable -Force
$iscc = "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $iscc)) { $iscc = 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe' }
& $iscc "/DAppVersion=$APP_VERSION" 'installer\windows.iss'
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Get-ChildItem 'dist\windows' | Out-String | Write-Host

# --- updater package (SEM sign: publish assina tudo de uma vez no host) ---
dart run desktop_updater:package --input $BUNDLE --output 'dist\updater\windows' `
  --package-id 'fourfun_cod_client' --app-name $APP_NAME --version $APP_VERSION --build-number $BN `
  --platform windows --channel stable `
  --artifact-url "$UPDATES_BASE/$APP_NAME-$APP_VERSION-windows.zip"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# --- deposita no share p/ o publish recolher (copia local, segundos) ---
$share = "Z:\$TAG\windows"
New-Item -ItemType Directory -Force -Path $share | Out-Null
Copy-Item $portable "$share\" -Force
Get-ChildItem 'dist\windows\*.exe' | Copy-Item -Destination $share -Force
Get-ChildItem 'dist\updater\windows\*.zip' | Copy-Item -Destination $share -Force
Copy-Item 'dist\updater\windows\release.json' "$share\release.json" -Force
Get-ChildItem $share | Out-String | Write-Host
Write-Host "artefatos Windows em $share - publish assume daqui"
