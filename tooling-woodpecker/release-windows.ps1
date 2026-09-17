# Release Windows - build + sobe artefatos p/ o feed na VPS (SPEC spec-private-releases-vps).
# Roda no step `release` de .woodpecker/build-windows.yaml (gate v* abaixo).
# O job Linux aguarda o sentinel `.windows-done` e publica o feed (latest/).
# Premissa: steps environment/dependencies/bridge/build ja rodaram neste pipeline
# (mesma VM, mesmo workspace) - cargo aqui e incremental, sem limpar o cache ORT.
$ErrorActionPreference = 'Stop'

$TAG = $env:CI_COMMIT_TAG
if (-not $TAG -or -not $TAG.StartsWith('v')) { Write-Host 'skip: nao e tag v*'; exit 78 }
$APP_VERSION = $TAG.TrimStart('v')
$BN = $env:CI_PIPELINE_NUMBER
$APP_NAME = '4FunCode'
$APP_SLUG = '4fun-cod'

# --- feed na VPS ---
$UPDATES_HOST = '179.197.236.24'
$UPDATES_USER = 'updates-deploy'
$UPDATES_ROOT = '/docker/updates/data'
$UPDATES_BASE = "https://updates.srv1849611.hstgr.cloud/$TAG"
$PINNED_HOSTKEY = '179.197.236.24 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGD9/TjlwFN/vbVM1IQvCyqXK51vAU5gsov+LI9EiUvt'

Write-Host "Release Windows $APP_VERSION (build $BN) da tag $TAG"

# --- version stamp (exe == feed) ---
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

# --- build versionado ---
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

# --- updater: chave + package + sign ---
# O store DPAPI (%LOCALAPPDATA%\desktop_updater\release-keys) persiste entre
# pipelines na mesma VM, e o protect usa entropia aleatoria: re-importar a
# MESMA chave sobre o arquivo existente sempre falha com "A different
# private key already exists". Limpa o profile antes (dir so guarda essas
# chaves) e mantem o retry da GHA contra flake do DPAPI.
$keysProfile = (Get-Content desktop_updater.keys.json | ConvertFrom-Json).profileId
$storeFile = Join-Path $env:LOCALAPPDATA "desktop_updater\release-keys\$keysProfile.json"
Remove-Item $storeFile -Force -ErrorAction SilentlyContinue
Remove-Item "$storeFile.lock" -Force -ErrorAction SilentlyContinue
[System.IO.File]::WriteAllBytes("$env:TEMP\release-key.dukey", [System.Convert]::FromBase64String($env:UPDATER_BUNDLE_B64))
$env:UPDATER_PASSPHRASE = $env:UPDATER_PASSPHRASE
$attempt = 0
while ($true) {
  $attempt++
  dart run desktop_updater:release keys import --input "$env:TEMP\release-key.dukey" --passphrase-env UPDATER_PASSPHRASE
  if ($LASTEXITCODE -eq 0) { break }
  if ($attempt -ge 5) { Write-Error "keys import failed after $attempt attempts"; exit 1 }
  Start-Sleep -Seconds (15 * $attempt)
}
Remove-Item "$env:TEMP\release-key.dukey" -Force -ErrorAction SilentlyContinue
dart run desktop_updater:package --input $BUNDLE --output 'dist\updater\windows' `
  --package-id 'fourfun_cod_client' --app-name $APP_NAME --version $APP_VERSION --build-number $BN `
  --platform windows --channel stable `
  --artifact-url "$UPDATES_BASE/$APP_NAME-$APP_VERSION-windows.zip"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
dart run desktop_updater:release sign --release 'dist\updater\windows\release.json'
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# --- upload p/ updates/<tag>/ na VPS + sentinel .windows-done por ultimo ---
if (-not (Get-Command sftp -ErrorAction SilentlyContinue)) { Write-Error 'sftp nao encontrado (OpenSSH Client?)'; exit 1 }
if (-not $env:UPDATES_DEPLOY_KEY_B64) { Write-Error 'UPDATES_DEPLOY_KEY_B64 vazio (secret updates_deploy_key?)'; exit 1 }
$sshDir = Join-Path $env:TEMP 'updates-ssh'
New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
$keyFile = Join-Path $sshDir 'updates_deploy_key'
[System.IO.File]::WriteAllBytes($keyFile, [System.Convert]::FromBase64String($env:UPDATES_DEPLOY_KEY_B64))
$khFile = Join-Path $sshDir 'known_hosts'
Set-Content -Encoding Ascii -Path $khFile -Value $PINNED_HOSTKEY
$sshTarget = "${UPDATES_USER}@${UPDATES_HOST}"
$sshOpts = @('-i', $keyFile, '-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes', '-o', 'StrictHostKeyChecking=yes', "-o", "UserKnownHostsFile=$khFile", '-o', 'ConnectTimeout=30', '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=4')
$tagDir = "$UPDATES_ROOT/$TAG"
$mkdirBatch = Join-Path $sshDir 'mkdir.batch'
Set-Content -Encoding Ascii -Path $mkdirBatch -Value "mkdir $tagDir"
& sftp @sshOpts -b $mkdirBatch $sshTarget | Out-String | Write-Host
$upBatch = Join-Path $sshDir 'upload.batch'
$lines = @()
$lines += "put $portable $tagDir/"
Get-ChildItem 'dist\windows\*.exe' | ForEach-Object { $lines += "put $($_.FullName) $tagDir/" }
Get-ChildItem 'dist\updater\windows\*.zip' | ForEach-Object { $lines += "put $($_.FullName) $tagDir/" }
Copy-Item 'dist\updater\windows\release.json' 'dist\updater\windows\release-windows.json' -Force
$lines += "put dist\updater\windows\release-windows.json $tagDir/"
$sentinel = Join-Path $sshDir '.windows-done'
Set-Content -Encoding Ascii -Path $sentinel -Value ''
$lines += "put $sentinel $tagDir/.windows-done"
Set-Content -Encoding Ascii -Path $upBatch -Value ($lines -join "`n")
& sftp @sshOpts -b $upBatch $sshTarget | Out-String | Write-Host
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Remove-Item -Recurse -Force $sshDir
Write-Host "artefatos Windows em $UPDATES_BASE - sentinel publicado"
