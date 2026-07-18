#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE="bazsyi-sunshine-prelogin.service"
SERVICE_FILE="/etc/systemd/system/$SERVICE"
STATE_FILE="/etc/bazsyi-sunshine/install-state"
FLATPAK_ID="dev.lizardbyte.app.Sunshine"
FLATPAK_UNIT="app-dev.lizardbyte.app.Sunshine.service"
REMOVE_PACKAGE=no

usage() {
  cat <<EOF
Usage: ./uninstall.sh [--remove-package]

Default:
  Remove the pre-login service and dedicated config
  Restore Flatpak Sunshine when installed
  Restore the previous linger state
  Keep the native RPM and native Sunshine identity

--remove-package also prepares removal of the layered Sunshine RPM and COPR.
A reboot may be required.
EOF
}

case "${1:-}" in
  "") ;;
  --remove-package) REMOVE_PACKAGE=yes ;;
  -h|--help) usage; exit 0 ;;
  *) printf 'Unknown option: %s\n' "$1" >&2; usage; exit 2 ;;
esac

if [[ -r "$STATE_FILE" ]]; then
  . "$STATE_FILE"
else
  TARGET_USER="$USER"
  TARGET_HOME="$HOME"
  CONFIG="$HOME/.config/bazsyi-sunshine/sunshine.conf"
  PREVIOUS_LINGER=no
  FLATPAK_INSTALLED=no
  PACKAGE_PREEXISTING=yes
fi

[[ "$TARGET_USER" == "$USER" ]] || { printf 'Run this as %s.\n' "$TARGET_USER" >&2; exit 1; }
sudo -v

sudo systemctl disable --now "$SERVICE" >/dev/null 2>&1 || true
sudo rm -f "$SERVICE_FILE"
sudo rm -rf "/etc/systemd/system/$SERVICE.d"
sudo systemctl daemon-reload
sudo systemctl reset-failed "$SERVICE" >/dev/null 2>&1 || true
rm -f "$CONFIG"
rmdir "$(dirname "$CONFIG")" 2>/dev/null || true

if [[ "${PREVIOUS_LINGER:-no}" == no ]]; then
  sudo loginctl disable-linger "$TARGET_USER"
fi

if flatpak info "$FLATPAK_ID" >/dev/null 2>&1; then
  systemctl --user enable --now "$FLATPAK_UNIT"
  printf 'Restored Flatpak Sunshine.\n'
fi

if [[ "$REMOVE_PACKAGE" == yes ]]; then
  if [[ "${PACKAGE_PREEXISTING:-yes}" == yes ]]; then
    printf 'Native Sunshine existed before this installer, so it was not removed.\n'
  else
    sudo rpm-ostree uninstall Sunshine || true
    sudo dnf5 -y copr disable lizardbyte/stable || true
    sudo rm -f /etc/bazsyi-sunshine/package-added-by-installer
    printf 'Native package removal prepared. Reboot if rpm-ostree created a pending deployment.\n'
  fi
fi

sudo rm -f "$STATE_FILE"
sudo rmdir /etc/bazsyi-sunshine 2>/dev/null || true

printf 'Bazsyi Sunshine pre-login integration removed.\n'
printf 'Native identity in %s/.config/sunshine was preserved.\n' "$TARGET_HOME"
