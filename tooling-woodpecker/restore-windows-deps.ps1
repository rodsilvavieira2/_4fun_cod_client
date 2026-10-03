# A clean Windows checkout can report a stale package_graph after updating the
# pinned LiveKit fork in pubspec.lock. One second pass completes that refresh.
$ErrorActionPreference = 'Stop'
$previousPreference = $ErrorActionPreference
try {
  $ErrorActionPreference = 'Continue'
  $firstOutput = & flutter pub get 2>&1
  $firstExit = $LASTEXITCODE
} finally {
  $ErrorActionPreference = $previousPreference
}
$firstText = $firstOutput | Out-String
Write-Host $firstText
if ($firstExit -eq 0) { return }
if ($firstText -notmatch 'Failed to parse .*package_graph\.json') {
  throw "flutter pub get failed with exit code $firstExit"
}
Write-Host 'Refreshing the Windows package graph after dependency resolution...'
& flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get retry failed with exit code $LASTEXITCODE" }
