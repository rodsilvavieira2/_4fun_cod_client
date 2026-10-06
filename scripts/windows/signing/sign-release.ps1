# 4FunCode — sign release binaries. Allowlist-first; recursive is opt-in.
# Preserves valid third-party signatures. Timestamp is mandatory (fail-closed).
param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseDirectory,

    [Parameter(Mandatory = $true)]
    [string]$PfxPath,

    [Parameter(Mandatory = $true)]
    [string]$PfxPassword,

    [string]$TimestampUrl = "http://timestamp.digicert.com",

    # Explicit 4FunCode-owned binaries relative to $ReleaseDirectory.
    [string[]]$Allowlist = @(
        "_4fun_cod_client.exe",
        "desktop_updater_install_helper.exe",
        "fourfun_deepfilter_bridge.dll"
    ),

    # Only when explicitly enabled: sign every unsigned .exe/.dll (still preserves third-party).
    [switch]$IncludeAllUnsigned
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ReleaseDirectory)) { throw "Release directory not found: $ReleaseDirectory" }
if (-not (Test-Path $PfxPath)) { throw "PFX not found: $PfxPath" }

function Invoke-SignOne([string]$FullPath) {
    $existing = Get-AuthenticodeSignature -LiteralPath $FullPath
    if ($existing.Status -eq "Valid" -and $existing.SignerCertificate -and $existing.SignerCertificate.Subject -notmatch "4FunCode") {
        Write-Host "Preserving third-party signature: $FullPath ($($existing.SignerCertificate.Subject))"
        return
    }
    Write-Host "Signing: $FullPath"
    & "$PSScriptRoot\sign-file.ps1" -File $FullPath -PfxPath $PfxPath -PfxPassword $PfxPassword -TimestampUrl $TimestampUrl
}

$targets = @()
foreach ($name in $Allowlist) {
    $full = Join-Path $ReleaseDirectory $name
    if (Test-Path $full) { $targets += $full }
    else { Write-Host "Allowlist entry absent (skip): $full" }
}

if ($IncludeAllUnsigned) {
    $all = Get-ChildItem $ReleaseDirectory -Recurse -File | Where-Object { $_.Extension -in @(".exe", ".dll") }
    foreach ($f in $all) {
        if ($targets -notcontains $f.FullName) { $targets += $f.FullName }
    }
    Write-Host "IncludeAllUnsigned: $($targets.Count) candidate(s). Review DLL list before production use." -ForegroundColor Yellow
}

if ($targets.Count -eq 0) { throw "No signable binaries found in $ReleaseDirectory" }

foreach ($t in $targets) { Invoke-SignOne $t }
Write-Host "Release signing complete: $($targets.Count) file(s) processed."
