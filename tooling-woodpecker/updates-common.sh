#!/usr/bin/env bash
# Config/feed compartilhado dos scripts de release (SPEC spec-private-releases-vps).
# Sourced por release-linux.sh e publish.sh (mesmo repo, qualquer workflow).
# Nao executa nada sozinho: so define variaveis + helpers de sftp.
# Entradas: CI_COMMIT_TAG=vX.Y.Z, CI_PIPELINE_NUMBER.

TAG="$CI_COMMIT_TAG"
VERSION="${TAG#v}"
BUILD_NUMBER="$CI_PIPELINE_NUMBER"
APP_NAME="4FunCode"
APP_SLUG="4fun-cod"
TMPD="$(mktemp -d)"

# --- feed na VPS ---
UPDATES_HOST="179.197.236.24"
UPDATES_USER="updates-deploy"
UPDATES_ROOT="/docker/updates/data"
UPDATES_BASE="https://updates.srv1849611.hstgr.cloud/$TAG"
UPDATES_LATEST="https://updates.srv1849611.hstgr.cloud/latest"
PINNED_HOSTKEY="179.197.236.24 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGD9/TjlwFN/vbVM1IQvCyqXK51vAU5gsov+LI9EiUvt"

# Share host <-> VM (fan-in Opcao A): builds depositam, publish recolhe.
# No agent linux-docker vai montado em /share (volumes: no yaml, repo trusted).
# Na VM Windows e o drive Z:.
SHARE_ROOT="${SHARE_ROOT:-/share}"

setup_updates_ssh() {
  command -v sftp >/dev/null || { echo "sftp nao encontrado (openssh-client?)"; exit 1; }
  [ -n "${UPDATES_DEPLOY_KEY_B64:-}" ] || { echo "UPDATES_DEPLOY_KEY_B64 vazio (secret updates_deploy_key?)"; exit 1; }
  echo "$UPDATES_DEPLOY_KEY_B64" | base64 -d > "$TMPD/updates_deploy_key"
  chmod 600 "$TMPD/updates_deploy_key"
  printf '%s\n' "$PINNED_HOSTKEY" > "$TMPD/updates_known_hosts"
  SFTP_OPTS="-i $TMPD/updates_deploy_key -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$TMPD/updates_known_hosts -o ConnectTimeout=30 -o ServerAliveInterval=15 -o ServerAliveCountMax=4"
  export SFTP_OPTS
}

# mkdir tolerante ("ja existe" nao pode matar o batch): chamada isolada + || true.
sftp_mkdir() {
  # $1 = dir remoto
  printf 'mkdir %s\n' "$1" > "$TMPD/mkdir.batch"
  # shellcheck disable=SC2086
  sftp $SFTP_OPTS -b "$TMPD/mkdir.batch" "$UPDATES_USER@$UPDATES_HOST" >/dev/null 2>&1 || true
}
