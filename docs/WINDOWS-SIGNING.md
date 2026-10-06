# Windows code signing — 4FunCode (self-signed Authenticode)

Fluxo: `flutter build windows` → assinar binários (allowlist) → verificar →
gerar `desktop_updater_helper_policy.json` dos binários **já assinados** →
`ISCC installer/windows.iss` → assinar setup → verificar → Defender → SHA256.

Self-signed **não elimina SmartScreen em distribuição pública**. Vale para
máquinas administradas que confiam no `.cer`. Nunca desabilitar
SmartScreen/Defender/UAC.

## 1. Gerar (uma vez, máquina segura Windows)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\scripts\windows\signing\create-certificate.ps1   # CN=4FunCode, RSA-3072, SHA256, 5 anos
```

Anote o `Thumbprint` impresso. Exija EKU `Code Signing (1.3.6.1.5.5.7.3.3)`.

Exportar PFX (senha forte, interativa):

```powershell
$cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -eq "CN=4FunCode" } |
  Sort-Object NotAfter -Descending | Select-Object -First 1
$pw = Read-Host "PFX password" -AsSecureString
New-Item -ItemType Directory -Force "$env:USERPROFILE\.4funcode-signing" | Out-Null
Export-PfxCertificate -Cert $cert -FilePath "$env:USERPROFILE\.4funcode-signing\4funcode-code-signing.pfx" -Password $pw
# Copiar para C:\CI\secrets\4funcode-code-signing.pfx no runner windows-build + icacls restrito.
```

Exportar público e commitar:

```powershell
.\scripts\windows\signing\export-public-certificate.ps1
# -> certificates/public/4funcode-code-signing.cer
```

Atualizar secret `code_signing_thumbprint` no Woodpecker (repo `_4fun_cod_client`,
events `tag,manual`) com o thumbprint real. `code_signing_password` já existe.

## 2. CI (Woodpecker `windows-build`)

Step `release` em `.woodpecker/build-windows.yaml` recebe:

```yaml
CODE_SIGNING_PFX: C:\CI\secrets\4funcode-code-signing.pfx
CODE_SIGNING_PASSWORD: {from_secret: code_signing_password}
EXPECTED_THUMBPRINT: {from_secret: code_signing_thumbprint}
```

`tooling-woodpecker/release-windows.ps1` assina allowlist
(`_4fun_cod_client.exe`, `desktop_updater_install_helper.exe`,
`fourfun_deepfilter_bridge.dll`), verifica, gera a portable policy dos hashes
assinados, compila Inno, assina o `*-setup.exe`, verifica (PowerShell +
`signtool verify /pa /v`), roda Defender e grava `.sha256`. Falha fechada em
qualquer gate. PFX/senha nunca vão para log, share ou artefato.

## 3. Confiar (máquina autorizada, Admin)

```powershell
.\scripts\windows\signing\install-trust.ps1 `
  -CertificatePath .\certificates\public\4funcode-code-signing.cer `
  -ExpectedThumbprint "<THUMBPRINT>"
```

Instala em `LocalMachine\Root` + `LocalMachine\TrustedPublisher`. Valide:

```powershell
Get-AuthenticodeSignature .\*-setup.exe   # Status: Valid, Subject: CN=4FunCode
signtool verify /pa /v .\*-setup.exe
```

Propriedades do Explorer → Digital Signatures → `4FunCode` → `This digital signature is OK.`

## 4. Rotação / comprometimento

Rotacionar antes de expirar (ex.: cert 5 anos → rotacionar no ano 4).
Transição pode confiar nos dois `.cer` temporariamente; releases novas usam o
novo thumbprint.

Trate como comprometida se: `.pfx` foi para Git/public, senha vazou em log,
CI comprometida, acesso não autorizado. Então: `STOP releases` → novo cert →
novo PFX/CER → atualizar `C:\CI\secrets\` + secrets + clientes → aposentar o antigo.
Self-signed não tem revogação pública; proteção da chave é crítica.
