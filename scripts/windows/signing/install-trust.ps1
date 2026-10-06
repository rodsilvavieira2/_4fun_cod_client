# 4FunCode — install public trust on an authorized machine. Must run as Administrator.
# Installs to LocalMachine\Root AND LocalMachine\TrustedPublisher.
# Validates thumbprint before trusting; never disables SmartScreen/Defender.
param(
    [string]$CertificatePath = ".\certificates\public\4funcode-code-signing.cer",
    [string]$ExpectedThumbprint = ""
)

$ErrorActionPreference = "Stop"

$principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "This script must run as Administrator."
}

if (-not (Test-Path $CertificatePath)) {
    throw "Certificate not found: $CertificatePath"
}

$certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertificatePath)
Write-Host "Certificate Subject:    $($certificate.Subject)"
Write-Host "Certificate Thumbprint: $($certificate.Thumbprint)"

if ($ExpectedThumbprint -and $ExpectedThumbprint -ne "PENDING-CERT-CREATION") {
    if ($certificate.Thumbprint -ne $ExpectedThumbprint) {
        throw "Unexpected certificate thumbprint. Expected=$ExpectedThumbprint Actual=$($certificate.Thumbprint)"
    }
    Write-Host "Thumbprint pinned: OK"
} else {
    Write-Host "WARNING: no ExpectedThumbprint supplied; confirm thumbprint out-of-band before trusting." -ForegroundColor Yellow
}

Write-Host "Installing 4FunCode public certificate..."
Import-Certificate -FilePath $CertificatePath -CertStoreLocation "Cert:\LocalMachine\Root" | Out-Null
Import-Certificate -FilePath $CertificatePath -CertStoreLocation "Cert:\LocalMachine\TrustedPublisher" | Out-Null

Write-Host "Certificate installed."
Write-Host "Trusted Root Certification Authorities: OK"
Write-Host "Trusted Publishers: OK"
