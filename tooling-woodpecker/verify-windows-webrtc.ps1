[CmdletBinding()]
param(
  [string]$Bundle = 'build\windows\x64\runner\Release',
  [ValidateSet('x64', 'arm64')][string]$Architecture = 'x64'
)
$ErrorActionPreference = 'Stop'
$thirdParty = Join-Path $PSScriptRoot '..\packages\flutter_webrtc\third_party'
. (Join-Path $thirdParty 'libwebrtc_manifest.ps1')
$manifest = Get-LibWebRtcManifest -Path (Join-Path $thirdParty 'libwebrtc_version.ini')
$expected = $manifest["windows_dll_sha256_$Architecture"]
if ($expected -notmatch '^[0-9a-f]{64}$') { throw "No published patched DLL for $Architecture" }
$dll = Join-Path $Bundle 'libwebrtc.dll'
$actual = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToLower()
if ($actual -ne $expected) { throw "Windows bundle contains an unexpected libwebrtc.dll: $actual" }
Write-Output "Verified $Architecture libwebrtc $($manifest.windows_artifact_revision): $actual"
