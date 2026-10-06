# 4FunCode — sign a single file with Authenticode + RFC3161 timestamp.
# Never prints the PFX password.
param(
    [Parameter(Mandatory = $true)]
    [string]$File,

    [Parameter(Mandatory = $true)]
    [string]$PfxPath,

    [Parameter(Mandatory = $true)]
    [string]$PfxPassword,

    [string]$TimestampUrl = "http://timestamp.digicert.com"
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\Find-SignTool.ps1"

if (-not (Test-Path $File)) { throw "File not found: $File" }
if (-not (Test-Path $PfxPath)) { throw "PFX not found: $PfxPath" }

$signtool = Find-SignTool
Write-Host "Signing: $File"

& $signtool sign /f $PfxPath /p $PfxPassword /fd SHA256 /tr $TimestampUrl /td SHA256 /v $File
if ($LASTEXITCODE -ne 0) { throw "SignTool failed ($LASTEXITCODE): $File" }

Write-Host "Signature created successfully."
