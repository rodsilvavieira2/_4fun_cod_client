# Shared by the native builder and the Windows release gate.
function Get-LibWebRtcManifest {
  param([string]$Path = (Join-Path $PSScriptRoot 'libwebrtc_version.ini'))
  $values = @{}
  foreach ($line in Get-Content -LiteralPath $Path -ErrorAction Stop) {
    $entry = $line.Trim()
    if (!$entry -or $entry -match '^[#;\[]') { continue }
    if ($entry -notmatch '^([^=]+)=(.*)$') { throw "Invalid libwebrtc manifest line: $entry" }
    $key = $Matches[1].Trim()
    $value = $Matches[2].Trim()
    if ($values.ContainsKey($key)) { throw "Duplicate libwebrtc manifest key: $key" }
    $values[$key] = $value
  }
  foreach ($key in @('binary_version', 'webrtc_revision', 'wrapper_revision', 'windows_ducking_patch', 'windows_artifact_revision', 'windows_download_url')) {
    if (!$values[$key]) { throw "Missing libwebrtc manifest key: $key" }
  }
  foreach ($key in @('webrtc_revision', 'wrapper_revision')) {
    if ($values[$key] -notmatch '^[0-9a-f]{40}$') { throw "Invalid revision: $key" }
  }
  return $values
}
