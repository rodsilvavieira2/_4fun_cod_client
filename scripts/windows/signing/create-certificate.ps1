# 4FunCode — create self-signed Authenticode code-signing certificate.
# Run once on the secure generation machine or secure Windows CI runner.
# Never commits the private key; export PFX separately with a strong password.
param(
    [string]$Subject = "CN=4FunCode",
    [int]$ValidYears = 5
)

$ErrorActionPreference = "Stop"

Write-Host "Creating 4FunCode code-signing certificate..."

$cert = New-SelfSignedCertificate `
    -Type CodeSigningCert `
    -Subject $Subject `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -HashAlgorithm SHA256 `
    -KeyAlgorithm RSA `
    -KeyLength 3072 `
    -NotAfter (Get-Date).AddYears($ValidYears) `
    -KeyExportPolicy Exportable

Write-Host ""
Write-Host "Certificate created successfully."
Write-Host "Subject:     $($cert.Subject)"
Write-Host "Thumbprint:  $($cert.Thumbprint)"
Write-Host "Valid from:  $($cert.NotBefore)"
Write-Host "Valid until: $($cert.NotAfter)"

Write-Host ""
Write-Host "Enhanced Key Usage:"
$cert.EnhancedKeyUsageList | Format-Table | Out-String | Write-Host

if (-not ($cert.EnhancedKeyUsageList | Where-Object { $_.FriendlyName -eq "Code Signing" -or $_.ObjectId -eq "1.3.6.1.5.5.7.3.3" })) {
    throw "Certificate lacks Code Signing EKU (1.3.6.1.5.5.7.3.3). Do not continue."
}

if (-not $cert.HasPrivateKey) {
    throw "Certificate has no private key. Do not continue."
}

Write-Host ""
Write-Host "SAVE THE FOLLOWING THUMBPRINT (update Woodpecker secret code_signing_thumbprint):"
Write-Host $cert.Thumbprint
Write-Host ""
Write-Host "Next: export PFX to C:\CI\secrets\ (icacls-locked) and run export-public-certificate.ps1."
