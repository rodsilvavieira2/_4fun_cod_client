# 4FunCode — verify a single Authenticode signature (PowerShell + SignTool).
# Enforces Status=Valid, Subject=CN=4FunCode, and optional thumbprint pinning.
param(
    [Parameter(Mandatory = $true)]
    [string]$File,

    [string]$ExpectedSubject = "CN=4FunCode",
    [string]$ExpectedThumbprint = ""
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\Find-SignTool.ps1"

if (-not (Test-Path $File)) { throw "File not found: $File" }

$signature = Get-AuthenticodeSignature -LiteralPath $File

Write-Host ""
Write-Host "File: $File"
Write-Host "Status: $($signature.Status)"
if ($signature.SignerCertificate) {
    Write-Host "Signer: $($signature.SignerCertificate.Subject)"
    Write-Host "Thumbprint: $($signature.SignerCertificate.Thumbprint)"
}

if ($signature.Status -ne "Valid") { throw "Invalid Authenticode signature: $File (Status=$($signature.Status))" }
if ($signature.SignerCertificate.Subject -ne $ExpectedSubject) {
    throw "Unexpected signer: $($signature.SignerCertificate.Subject) (expected $ExpectedSubject)"
}
if ($ExpectedThumbprint -and $ExpectedThumbprint -ne "PENDING-CERT-CREATION") {
    if ($signature.SignerCertificate.Thumbprint -ne $ExpectedThumbprint) {
        throw "Unexpected signing certificate thumbprint: $($signature.SignerCertificate.Thumbprint)"
    }
    Write-Host "Thumbprint pinned: OK"
}

$signtool = Find-SignTool
& $signtool verify /pa /v $File
if ($LASTEXITCODE -ne 0) { throw "SignTool verify failed ($LASTEXITCODE): $File" }

Write-Host "Signature VALID: $File"
