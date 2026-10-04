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

# --- updater portable policy (ANTES do portable.zip/installer/updater) ---
# Sem desktop_updater_helper_policy.json ao lado do exe, o nativo falha com
# "Windows helper preparation failed: Required install metadata file is unavailable".
# Geracao 100% PowerShell (a VM nao tem `python` no PATH — exit 9009).
$BUNDLE = 'build\windows\x64\runner\Release'
$WIN_PKG_ID = 'fourfun_cod_client'
$WIN_KEY_ID = 'release-de4dba08820a7c59511f86ce'
$WIN_PUBKEY = 'MUceP/D/eQGYTiNhtcu3B6p0czGJW+LVWsHyhUjkJgE='
$WIN_EXE = Join-Path $BUNDLE '_4fun_cod_client.exe'
$WIN_HELPER = Join-Path $BUNDLE 'desktop_updater_install_helper.exe'
if (-not (Test-Path $WIN_EXE)) { Write-Error "exe ausente: $WIN_EXE"; exit 1 }
if (-not (Test-Path $WIN_HELPER)) { Write-Error "helper ausente: $WIN_HELPER (plugin desktop_updater nao bundlou?)"; exit 1 }
$exeSha = (Get-FileHash -Algorithm SHA256 -Path $WIN_EXE).Hash.ToLower()
$helperSha = (Get-FileHash -Algorithm SHA256 -Path $WIN_HELPER).Hash.ToLower()
# JSON canonico: chaves ordenadas, sem espacos, sem newline final (validacao nativa e byte-exata).
$WIN_POLICY_JSON = '{"allowedApplicationSigner":{"kind":"sha256","value":"' + $exeSha + '"},"allowedHelperSigner":{"kind":"sha256","value":"' + $helperSha + '"},"allowedInstallRoots":[],"allowedStrategies":[{"provider":"platformDirectory","strategy":"directoryReplace"},{"provider":"platformFile","strategy":"singleFileReplace"}],"allowedTargetClasses":["sameUserWritable"],"applicationPackageId":"' + $WIN_PKG_ID + '","helperServiceId":"com.example.desktop-updater.helper","minimumHelperProtocolVersion":1,"policyId":"com.example.desktop-updater.portable","policyVersion":1,"releaseRootPublicKeys":[{"algorithm":"ed25519","keyId":"' + $WIN_KEY_ID + '","publicKeyBase64":"' + $WIN_PUBKEY + '"}]}'
$WIN_POLICY = Join-Path $BUNDLE 'desktop_updater_helper_policy.json'
[System.IO.File]::WriteAllText($WIN_POLICY, $WIN_POLICY_JSON, (New-Object System.Text.UTF8Encoding $false))
if (-not (Test-Path $WIN_POLICY)) { Write-Error "policy nao gerada: $WIN_POLICY"; exit 1 }
Get-ChildItem $BUNDLE -Filter 'desktop_updater*' | Out-String | Write-Host

# --- assert DirectML resolveu (o BRIDGE DLL linka ORT estatico + DirectML;
# nao o plugin: o plugin carrega o bridge via import lib e nao referencia
# simbolo DirectML direto, entao o linker descarta o import do plugin por
# /OPT:REF. Desde a0ed009 (bridge via DLL p/ fugir do LNK2038 /MDd) checar o
# plugin sempre falha — o binario certo e fourfun_deepfilter_bridge.dll) ---
& (Join-Path $PSScriptRoot 'verify-windows-webrtc.ps1') -Bundle $BUNDLE
& $dumpbin /DEPENDENTS "$BUNDLE\_4fun_cod_client.exe" | Out-String | Write-Host
$bridgeDll = "$BUNDLE\fourfun_deepfilter_bridge.dll"
if (-not (Test-Path $bridgeDll)) { Write-Error 'fourfun_deepfilter_bridge.dll ausente no bundle'; exit 1 }
$bridgeDeps = & $dumpbin /DEPENDENTS $bridgeDll 2>$null | Out-String
if ($bridgeDeps -notmatch 'DirectML\.dll') { Write-Error 'fourfun_deepfilter_bridge.dll nao referencia DirectML.dll'; exit 1 }
if (-not (Test-Path "$BUNDLE\DirectML.dll")) { Write-Error 'DirectML.dll ausente no bundle'; exit 1 }
Write-Host 'DirectML OK: bridge referencia e DLL esta no bundle'

# --- portable + installer ---
# vc_redist vai no portable.zip e no setup via installer/vendor, NUNCA no
# zip do updater (o updater nao deve versionar o instalador MSVC).
$redistUrl = 'https://aka.ms/vs/17/release/vc_redist.x64.exe'
New-Item -ItemType Directory -Force -Path 'installer\vendor' | Out-Null
Invoke-WebRequest -Uri $redistUrl -OutFile "$BUNDLE\vc_redist.x64.exe"
Copy-Item "$BUNDLE\vc_redist.x64.exe" 'installer\vendor\vc_redist.x64.exe' -Force
$portable = "dist\${APP_SLUG}-windows-x64-${APP_VERSION}-portable.zip"
New-Item -ItemType Directory -Force -Path 'dist' | Out-Null
Compress-Archive -Path "$BUNDLE\*" -DestinationPath $portable -Force
$iscc = "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $iscc)) { $iscc = 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe' }
& $iscc "/DAppVersion=$APP_VERSION" 'installer\windows.iss'
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Get-ChildItem 'dist\windows' | Out-String | Write-Host
# Remove vc_redist do bundle antes do updater package (nao versionar MSVC).
Remove-Item "$BUNDLE\vc_redist.x64.exe" -Force -ErrorAction SilentlyContinue

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
