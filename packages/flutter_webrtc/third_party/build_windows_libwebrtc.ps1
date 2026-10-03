# Builds the pinned M150 Windows DLL with the 4fun render-stream ducking patch.
# Run in Windows PowerShell from a host with VS 2022 C++ and Windows SDK 26100.
[CmdletBinding()]
param(
  [string]$BuildRoot = 'C:\work\4fun_webrtc_ducking',
  [ValidateSet('x64', 'arm64')][string]$Architecture = 'x64',
  [ValidateRange(1, 64)][int]$Jobs = 2,
  [switch]$SkipSync
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'libwebrtc_manifest.ps1')
$manifest = Get-LibWebRtcManifest
$webrtcRevision = $manifest.webrtc_revision
$wrapperRevision = $manifest.wrapper_revision
$binaryVersion = $manifest.binary_version
$patchPath = Join-Path $PSScriptRoot ('patches\' + $manifest.windows_ducking_patch)
$sourceRoot = Join-Path $BuildRoot 'src'
$depotRoot = Join-Path $BuildRoot 'depot_tools'
$wrapperRoot = Join-Path $sourceRoot 'libwebrtc'
$outputRoot = Join-Path $sourceRoot ('out-4fun-' + $Architecture)

function Invoke-Checked {
  param([string]$Program, [string[]]$Arguments)
  & $Program @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "$Program failed with exit code $LASTEXITCODE"
  }
}

function Apply-Patch {
  param([string]$Path)
  $previousErrorAction = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $null = & git -C $sourceRoot apply --reverse --check --ignore-space-change $Path 2>&1
    $alreadyApplied = $LASTEXITCODE -eq 0
  } finally {
    $ErrorActionPreference = $previousErrorAction
  }
  if ($alreadyApplied) { return }
  Invoke-Checked 'git' @('-C', $sourceRoot, 'apply', '--check', '--ignore-space-change', $Path)
  Invoke-Checked 'git' @('-C', $sourceRoot, 'apply', '--ignore-space-change', $Path)
}

if (!(Test-Path $patchPath)) { throw "Missing patch: $patchPath" }
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vsPath = & $vswhere -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1
if (!$vsPath) { throw 'Visual Studio 2022 C++ build tools are required.' }
$sdkHeader = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Include\10.0.26100.0\um\audioclient.h'
if (!(Test-Path $sdkHeader)) { throw 'Windows SDK 10.0.26100.0 is required.' }
$sdkDebugger = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Debuggers\x64\dbghelp.dll'
if (!(Test-Path $sdkDebugger)) {
  throw 'Install the SDK Debugging Tools for Windows feature before building libwebrtc.'
}

New-Item -ItemType Directory -Path $BuildRoot -Force | Out-Null
# Keep Chromium's Git recommendations scoped to this build process.
$gitConfig = Join-Path $BuildRoot 'build.gitconfig'
if (!(Test-Path $gitConfig)) {
  [IO.File]::WriteAllText($gitConfig, @"
[core]
    autocrlf = false
    filemode = false
    fscache = true
    preloadindex = true
    longpaths = true
[depot-tools]
    allowGlobalGitConfig = false
"@, [Text.Encoding]::ASCII)
}
$env:GIT_CONFIG_GLOBAL = $gitConfig
$env:DEPOT_TOOLS_WIN_TOOLCHAIN = '0'
$env:DEPOT_TOOLS_UPDATE = '0'
$env:GYP_MSVS_VERSION = '2022'
$env:GYP_MSVS_OVERRIDE_PATH = $vsPath
$env:vs2022_install = $vsPath
$env:WINDOWSSDKDIR = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10'
$env:Path = "$depotRoot;" + $env:Path

if (!(Test-Path "$depotRoot\.git")) {
  Invoke-Checked 'git' @('clone', '--depth', '1', 'https://chromium.googlesource.com/chromium/tools/depot_tools.git', $depotRoot)
}
if (!(Test-Path "$depotRoot\git.bat")) {
  # The first bootstrap generates git.bat, which gclient invokes on Windows.
  Invoke-Checked "$depotRoot\bootstrap\win_tools.bat" @()
}
if (!(Test-Path "$sourceRoot\.git")) {
  Invoke-Checked 'git' @('clone', '--depth', '1', '--branch', 'm150_release', 'https://github.com/webrtc-sdk/webrtc.git', $sourceRoot)
  Invoke-Checked 'git' @('-C', $sourceRoot, 'fetch', '--depth', '1', 'origin', $webrtcRevision)
  Invoke-Checked 'git' @('-C', $sourceRoot, 'checkout', '--detach', $webrtcRevision)
  Invoke-Checked 'git' @('-C', $sourceRoot, 'config', 'core.longpaths', 'true')
}
$actualRevision = (& git -C $sourceRoot rev-parse HEAD).Trim()
if ($actualRevision -ne $webrtcRevision) {
  throw "Unexpected WebRTC revision $actualRevision. Use a separate BuildRoot."
}

Push-Location $BuildRoot
try {
  if (!$SkipSync) {
    $gclient = @"
solutions = [{"name": "src", "url": "https://github.com/webrtc-sdk/webrtc.git@$webrtcRevision", "deps_file": "DEPS", "managed": False, "custom_deps": {}}]
target_os = ["win"]
"@
    [IO.File]::WriteAllText((Join-Path $BuildRoot '.gclient'), $gclient, [Text.Encoding]::ASCII)
    Invoke-Checked "$depotRoot\gclient.bat" @('sync', '--no-history', "--jobs=$Jobs")
  }

  if (!(Test-Path "$wrapperRoot\.git")) {
    Invoke-Checked 'git' @('clone', '--depth', '1', '--branch', $binaryVersion, 'https://github.com/webrtc-sdk/libwebrtc.git', $wrapperRoot)
  }
  $actualWrapper = (& git -C $wrapperRoot rev-parse HEAD).Trim()
  if ($actualWrapper -ne $wrapperRevision) { throw "Unexpected wrapper revision $actualWrapper" }

  Apply-Patch "$wrapperRoot\patches\custom_audio_source_m150.patch"
  Apply-Patch "$wrapperRoot\patches\add_libwebrtc_build_target.patch"
  Apply-Patch "$wrapperRoot\patches\allow_176k4_192k_shared_mode_formats.patch"
  Apply-Patch $patchPath

  # Chromium's hook filters for Change-Id, which is absent in the pinned
  # fork commit. Regenerate LASTCHANGE from that commit instead of epoch zero,
  # which produces a negative PE timestamp in compute_build_timestamp.py.
  $lastchangeFile = Join-Path $sourceRoot 'build\util\LASTCHANGE'
  Invoke-Checked "$depotRoot\python3.bat" @(
    "$sourceRoot\build\util\lastchange.py", '--source-dir', $sourceRoot,
    '--filter', '.', '--revision-id-only', '--output', $lastchangeFile
  )
  $sourceTimestamp = [long](Get-Content ($lastchangeFile + '.committime') -Raw).Trim()
  if ($sourceTimestamp -le 0 -or
      (Get-Content $lastchangeFile) -notcontains "LASTCHANGE=$webrtcRevision") {
    throw 'LASTCHANGE must identify the pinned WebRTC commit with a positive timestamp.'
  }

  # The wrapper declares test targets unconditionally; match its Windows build
  # flags so GN can resolve them. Ninja below only builds the library target.
  $gnArgs = 'is_debug=false is_clang=true target_os="win" target_cpu="' + $Architecture + '" use_custom_libcxx=false rtc_libvpx_build_vp9=true enable_libaom=true rtc_include_tests=true rtc_build_examples=false rtc_build_tools=false is_component_build=false rtc_enable_protobuf=false rtc_use_h264=true ffmpeg_branding="Chrome" rtc_use_h265=true symbol_level=0 enable_iterator_debugging=false'
  New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
  # A file avoids PowerShell 5 / cmd.exe stripping GN string quotes.
  [IO.File]::WriteAllText((Join-Path $outputRoot 'args.gn'), $gnArgs, [Text.Encoding]::ASCII)
  Invoke-Checked "$depotRoot\gn.bat" @('gen', $outputRoot, "--root=$sourceRoot")
  Invoke-Checked 'ninja.exe' @('-C', $outputRoot, "-j$Jobs", 'libwebrtc')

  $artifactRoot = Join-Path $BuildRoot ('artifact-' + $Architecture)
  $artifactLib = Join-Path $artifactRoot 'lib'
  New-Item -ItemType Directory -Path $artifactLib -Force | Out-Null
  Copy-Item "$outputRoot\libwebrtc.dll", "$outputRoot\libwebrtc.dll.lib" $artifactLib -Force
  $metadata = [ordered]@{
    binary_version = $binaryVersion
    webrtc_revision = $webrtcRevision
    wrapper_revision = $wrapperRevision
    source_commit_timestamp = $sourceTimestamp
    patch_sha256 = (Get-FileHash $patchPath -Algorithm SHA256).Hash.ToLower()
    dll_sha256 = (Get-FileHash "$artifactLib\libwebrtc.dll" -Algorithm SHA256).Hash.ToLower()
    architecture = $Architecture
  }
  $metadata | ConvertTo-Json | Set-Content (Join-Path $artifactRoot 'fourfun-ducking-build.json') -Encoding ASCII
  $archive = Join-Path $PSScriptRoot ('downloads\libwebrtc-win-' + $Architecture + '-release-fourfun-ducking.zip')
  New-Item -ItemType Directory -Path (Split-Path $archive) -Force | Out-Null
  $temporaryArchive = $archive + '.new.zip'
  Compress-Archive -Path "$artifactRoot\*" -DestinationPath $temporaryArchive -Force
  Move-Item $temporaryArchive $archive -Force
  Write-Output "Patched Windows archive: $archive"
  Write-Output ('Archive SHA256 for the new manifest revision: ' + (Get-FileHash $archive -Algorithm SHA256).Hash.ToLower())
} finally {
  Pop-Location
}
