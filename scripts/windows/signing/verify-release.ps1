# 4FunCode — verify all allowlisted release binaries.
param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseDirectory,

    [string]$ExpectedSubject = "CN=4FunCode",
    [string]$ExpectedThumbprint = "",

    [string[]]$Allowlist = @(
        "_4fun_cod_client.exe",
        "desktop_updater_install_helper.exe",
        "fourfun_deepfilter_bridge.dll"
    )
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ReleaseDirectory)) { throw "Release directory not found: $ReleaseDirectory" }

$checked = 0
foreach ($name in $Allowlist) {
    $full = Join-Path $ReleaseDirectory $name
    if (-not (Test-Path $full)) {
        Write-Host "Allowlist entry absent (skip): $full"
        continue
    }
    & "$PSScriptRoot\verify-signature.ps1" -File $full -ExpectedSubject $ExpectedSubject -ExpectedThumbprint $ExpectedThumbprint
    $checked++
}

if ($checked -eq 0) { throw "No allowlisted binaries found in $ReleaseDirectory" }
Write-Host "Release verification complete: $checked file(s) VALID."

# Audit table (signed vs unsigned vs third-party) for CI logs.
Get-ChildItem $ReleaseDirectory -Recurse -Include *.exe, *.dll -File |
    ForEach-Object {
        $sig = Get-AuthenticodeSignature -LiteralPath $_.FullName
        [PSCustomObject]@{
            File   = $_.FullName
            Status = $sig.Status
            Signer = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { "Unsigned" }
        }
    } |
    Format-Table -AutoSize | Out-String | Write-Host
