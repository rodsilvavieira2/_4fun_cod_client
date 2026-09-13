#!/bin/sh
# Instala a permissao opcional para Push to Talk global por evdev no Linux.
# Execute manualmente: sudo ./install-input-access.sh [usuario]
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "Execute como root: sudo $0 [usuario]" >&2
  exit 1
fi

ptt_user=${1:-${SUDO_USER:-}}
if [ -z "$ptt_user" ]; then
  echo "Informe o usuario que recebera acesso ao teclado/mouse." >&2
  exit 1
fi

if ! getent passwd "$ptt_user" >/dev/null; then
  echo "Usuario inexistente: $ptt_user" >&2
  exit 1
fi

if ! getent group fourfun-ptt >/dev/null; then
  groupadd --system fourfun-ptt
fi

install -D -m 0644 "$(dirname "$0")/70-fourfun-cod-ptt-input.rules" \
  /etc/udev/rules.d/70-fourfun-cod-ptt-input.rules
rm -f /etc/udev/rules.d/70-fourfun-cod-ptt-mouse.rules
usermod -a -G fourfun-ptt "$ptt_user"
udevadm control --reload-rules
udevadm trigger --subsystem-match=input

echo "Acesso instalado para $ptt_user. Encerre a sessao e entre novamente antes de testar o PTT global por evdev."
