# Releases desktop — 4Fun Cod (Linux + Windows)

Releases automáticos via GitHub Actions quando uma tag `vX.Y.Z` é enviada
ao repo **do client** (`_4fun_cod_client`):

```bash
git tag v1.0.0
git push origin v1.0.0
```

Workflow: `.github/workflows/release-desktop.yml`
(`Desktop Release`: Linux ubuntu-22.04 + Windows windows-2025 em paralelo
→ job `release` publica os assets + `SHA256SUMS.txt`).

Artefatos de `v1.0.0`:

```text
4fun-cod-linux-x64-1.0.0.tar.gz
4fun-cod-windows-x64-1.0.0-portable.zip
4fun-cod-windows-x64-1.0.0-setup.exe
SHA256SUMS.txt
```

## Variáveis do pipeline

| Var | Valor | Origem |
|---|---|---|
| `APP_NAME` | `4Fun Cod` | nome exibido |
| `APP_SLUG` | `4fun-cod` | nome dos arquivos |
| `APP_EXE_NAME` | `_4fun_cod_client.exe` | `BINARY_NAME` em `linux/CMakeLists.txt` / `ProductName` em `windows/runner/Runner.rc` |
| `FLUTTER_VERSION` | `3.44.4` | SDK real de dev — atualizar aqui só em commit próprio de upgrade Flutter |

## Instalador Windows

Definido em `installer/windows.iss` (Inno Setup 6). `AppId=com.fourfun.codclient`
é permanente — não alterar após a primeira release pública.

## Checklist pré-tag

```text
[ ] código esperado está na branch principal do CLIENT
[ ] FLUTTER_VERSION do workflow == SDK de dev
[ ] pubspec.lock commitado
[ ] build Linux local funciona (apenas linux/web são suportados)
[ ] ícone Windows ok (windows/runner/resources/app_icon.ico)
[ ] APP_EXE_NAME confere com build/windows/x64/runner/Release/
[ ] versão/tag correta (tags são imutáveis — nunca reutilizar vX.Y.Z)
```

Pós-pipeline: conferir no GitHub `Releases → vX.Y.Z` os 4 arquivos.
Se falhar antes do Release existir: `Re-run failed jobs`, sem recriar tag.
Linux deve ser testado ao menos uma vez num Ubuntu 22.04 limpo
(`ldd ./_4fun_cod_client`, ex. `libgtk-3-0`); `tray_manager`/`window_manager`
podem exigir libs extras além de `libgtk-3-dev`.
