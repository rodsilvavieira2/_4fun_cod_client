# Releases desktop — 4FunCode (Linux + Windows)

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
4fun-cod-linux-x64-1.0.0.AppImage
4fun-cod-windows-x64-1.0.0-portable.zip
4fun-cod-windows-x64-1.0.0-setup.exe
SHA256SUMS.txt
```

## AppImage (Linux)

Montado com `appimagetool` a partir do bundle Flutter
(`packaging/linux/4fun-cod.desktop` + `packaging/linux/4fun-cod.png`).
**Não é totalmente autocontido** (P3 review t_34728661): as `.so` dos
plugins resolvem via `$ORIGIN/lib`, mas libs de sistema (`libgtk-3`,
`libsecret-1`, `libgstreamer-*`, `libayatana-appindicator3`) precisam
existir no host. Pré-requisitos mínimos (Debian/Ubuntu):

```bash
sudo apt install libgtk-3-0 libsecret-1-0 libgstreamer1.0-0 \
  libgstreamer-plugins-base1.0-0 libayatana-appindicator3-1
```

## Telemetria (OTEL) na release

`API_URL`/`OTEL_*` (exceto auth) vão baked via `--dart-define` a partir
das variables do repo. **`OTEL_BASIC_AUTH` nunca vai no binário**
(P2 review t_34728661) — a release lê da env de runtime:

```bash
OTEL_BASIC_AUTH='<base64(email:senha)>' ./4fun-cod-linux-x64-*.AppImage
```

## Windows (VC++ Redistributable)

O `flutter build windows` não embarca o runtime MSVC. Em Windows limpo
o app pode falhar com `VCRUNTIME140.dll was not found`:

- `setup.exe`: instala o `vc_redist.x64.exe` automaticamente se ausente.
- Portable `.zip`: inclui `vc_redist.x64.exe` ao lado do `.exe` — rode-o
  uma vez se o app não abrir.

## Variáveis do pipeline

| Var | Valor | Origem |
|---|---|---|
| `APP_NAME` | `4FunCode` | nome exibido |
| `APP_SLUG` | `4fun-cod` | nome dos arquivos |
| `APP_EXE_NAME` | `_4fun_cod_client.exe` | `BINARY_NAME` em `linux/CMakeLists.txt` / `InternalName`+`OriginalFilename` em `windows/runner/Runner.rc` (`ProductName`/`FileDescription` exibem `4FunCode`) |
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
