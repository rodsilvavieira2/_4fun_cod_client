# SPEC — Releases privadas: feed de update na VPS (aposentar GitHub Releases)

- **Status:** spec (não implementado)
- **Data:** 2026-09-17
- **Escopo:** `_4fun_cod_client` (pipeline Woodpecker + `lib/core/updates/update_config.dart`) e VPS `personal-vps`
- **Fora de escopo:** mudar o pacote `desktop_updater`, download autenticado, `_4fun_cod_server`

## 1. Contexto

Hoje os artefatos de release (portable, setup, tar.gz, AppImage, zips do updater, `release-*.json`,
`app-archive.json`, `SHA256SUMS.txt`) são publicados como assets de GitHub Releases públicas, e o app
instalado lê o feed em `updateBaseUrl` (`lib/core/updates/update_config.dart`):

```dart
const String updateBaseUrl =
    'https://github.com/rodsilvavieira2/_4fun_cod_client/releases/latest/download';
```

O `desktop_updater` busca `<base>/app-archive.json` via GET simples e verifica assinatura ed25519 offline.
Objetivo: hospedar o feed na VPS, privatizar os repos e aposentar o GitHub Releases, **sem auth no
download** (URLs não-listadas + assinatura; decisão registrada — sem fork do pacote).

## 2. Requisitos

1. O app instalado deve descobrir updates numa URL sob nosso domínio, via HTTPS com GET simples.
2. O conjunto de artefatos por release deve ser o mesmo de hoje (10 arquivos + sources dispensados).
3. `updateBaseUrl` continua sendo constante de compilação (sem mudança de arquitetura no client).
4. Clientes já instalados (feed GitHub) devem migrar sozinhos, sem ação manual.
5. Repos podem ser privatizados sem quebrar clone CI (`WOODPECKER_*`) nem `gh`/PAT nos scripts.
6. Rollback: GitHub Releases segue como destino até a Fase 4 dar verde.

## 3. Desenho

### 3.1 Host estático na VPS

- Novo host no Traefik existente: `updates.srv1849611.hstgr.cloud` → container Caddy/nginx servindo um volume.
- Layout no volume:
  - `updates/<tag>/` — os 10 arquivos da release (imutável após publicar);
  - `updates/latest/` — espelho dos arquivos do feed (`app-archive.json`, `release-*.json`, zips),
    preservando o padrão `<base>/...` que o client espera de `updateBaseUrl`.

### 3.2 Client (1 commit)

- `update_config.dart`: `updateBaseUrl` →
  `https://updates.srv1849611.hstgr.cloud/latest`
- **Release de transição (última no GitHub):** publica pelo fluxo atual com a nova base já embutida.
  A partir dela, os instalados passam a olhar a VPS.

### 3.3 Pipeline Woodpecker (troca de destino, mesma lógica)

Nos scripts `tooling-woodpecker/release-linux.sh` e `release-windows.ps1`:

| Hoje (GitHub) | Novo (VPS) |
|---|---|
| `BASE=https://github.com/.../releases/download/$TAG` | `BASE=https://updates.srv1849611.hstgr.cloud/<tag>` |
| `artifact-url` / `release-url` com `$BASE` | mesmos flags, nova base |
| `gh release create --draft` + `upload` | `scp` para `updates/<tag>/` (secret SSH novo, chave restrita ao volume) |
| Sentinel `release-windows.json` no draft (destrava o Linux) | sentinel como arquivo `updates/<tag>/.windows-done` (poll via `ssh`/`curl`) |
| `gh release edit --draft=false` (publish) | `scp` do feed para `updates/latest/` |
| Verificação hospedada via `gh release download` | `curl` contra `updates.*` + `desktop_updater:verify` local |

Feed, assinatura, SHA256 e gates `v*` (exit 78 nas `ci-*`): inalterados.

### 3.4 Privatizar + aposentar

1. Validar de ponta a ponta com tag `v9.9.9-priv1` (app instalado atualizando da VPS).
2. Tornar os repos privados (OAuth cobre o clone; conferir scope do PAT).
3. Deletar drafts/releases de teste; GitHub vira só código.

## 4. Critérios de aceite

- [ ] `GET https://updates.srv1849611.hstgr.cloud/latest/app-archive.json` retorna feed assinado válido.
- [ ] App instalado na versão de transição detecta e aplica update vindo da VPS (Windows + Linux).
- [ ] `desktop_updater:verify` passa nos `release-*.json` servidos pela VPS.
- [ ] Repos privados com CI verde (clone + release).
- [ ] Nenhum asset novo publicado no GitHub após a release de transição.

## 5. Riscos e notas

- **Transição exige a release-ponte no GitHub:** sem ela, instalados antigos nunca saem do feed GitHub
  (URL é constante compilada, não vem da API).
- DNS/TLS do novo host dependem do Traefik da VPS (mesmo padrão de `api.*`/`o2.*`).
- Pré-requisito sugerido: concluir a validação da `v0.0.0-ci99` no fluxo GitHub antes de pivotar
  (ou abortá-la explicitamente e pivotar direto).
- Segredo novo necessário: chave SSH restrita ao volume `updates/` (secret `updates_deploy_key`, evento `tag`).
