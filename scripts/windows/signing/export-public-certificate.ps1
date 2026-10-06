# 4FunCode — export public .cer from the CurrentUser\My code-signing cert.
# The .cer is safe to commit under certificates/public/.
param(
    [string]$OutputPath = ".\certificates\public\4funcode-code-signing.cer",
    [string]$Subject = "CN=4FunCode"
)

$ErrorActionPreference = "Stop"

$cert = Get-ChildItem Cert:\CurrentUser\My |
    Where-Object { $_.Subject -eq $Subject } |
    Sort-Object NotAfter -Descending |
    Select-Object -First 1

if (-not $cert) {
    throw "4FunCode certificate not found (Subject=$Subject)."
}

$directory = Split-Path $OutputPath
if ($directory) {
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
}

Export-Certificate -Cert $cert -FilePath $OutputPath -Type CERT | Out-Null

Write-Host "Public certificate exported:"
Write-Host $OutputPath
Write-Host "Thumbprint: $($cert.Thumbprint)"
Write-Host "Commit this .cer; never commit the .pfx."
