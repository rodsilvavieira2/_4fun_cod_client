# 4FunCode — Microsoft Defender security gate (fail-closed).
# Updates signatures, runs a CustomScan, fails on any threat detection.
param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Path)) { throw "Path not found: $Path" }

Write-Host "Updating Defender signatures..."
Update-MpSignature

Write-Host "Scanning: $Path"
Start-MpScan -ScanType CustomScan -ScanPath $Path

$threats = Get-MpThreatDetection
if ($threats) {
    Write-Host "Defender reported threat detections." -ForegroundColor Red
    $threats | Format-List | Out-String | Write-Host
    throw "Security validation failed: Defender found threats in $Path"
}

Write-Host "Defender scan completed: CLEAN."
