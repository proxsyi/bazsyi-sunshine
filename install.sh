#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE="bazsyi-sunshine-prelogin.service"
SERVICE_FILE="/etc/systemd/system/$SERVICE"
STATE_FILE="/etc/bazsyi-sunshine/install-state"
FLATPAK_ID="dev.lizardbyte.app.Sunshine"
FLATPAK_UNIT="app-dev.lizardbyte.app.Sunshine.service"
COPR="lizardbyte/stable"
PACKAGE="Sunshine"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_NAME="${BAZSYI_OUTPUT_NAME:-0}"
REQUESTED_ADAPTER="${BAZSYI_ADAPTER:-}"

say() { printf '\n%s\n' "$*"; }
fail() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: ./install.sh [--output INDEX] [--adapter /dev/dri/renderDXXX]

Installs native Sunshine as a Bazzite KDE pre-login service.
If the native RPM must be layered, reboot and run this command again.

Environment equivalents:
  BAZSYI_OUTPUT_NAME=0
  BAZSYI_ADAPTER=/dev/dri/renderD129
EOF
}

while (($#)); do
  case "$1" in
    --output)
      [[ $# -ge 2 ]] || fail "--output needs a monitor index."
      OUTPUT_NAME="$2"
      shift 2
      ;;
    --adapter)
      [[ $# -ge 2 ]] || fail "--adapter needs a render device."
      REQUESTED_ADAPTER="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
done

[[ $EUID -ne 0 ]] || fail "Run this as your desktop user without sudo. The installer requests sudo only when needed."
TARGET_USER="$USER"

TARGET_UID="$(id -u "$TARGET_USER")"
TARGET_GROUP="$(id -gn "$TARGET_USER")"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
CONFIG_DIR="$TARGET_HOME/.config/bazsyi-sunshine"
CONFIG="$CONFIG_DIR/sunshine.conf"
NATIVE_STATE="$TARGET_HOME/.config/sunshine"
FLATPAK_STATE="$TARGET_HOME/.var/app/$FLATPAK_ID/config/sunshine"
BACKUP_ROOT="$TARGET_HOME/.local/share/bazsyi-sunshine/backups"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$BACKUP_ROOT/$STAMP"

[[ -r /etc/os-release ]] || fail "Cannot read /etc/os-release."
. /etc/os-release
[[ "${ID:-}" == "bazzite" ]] || fail "V1 officially supports Bazzite only."
[[ -f "$ROOT_DIR/systemd/bazsyi-sunshine-prelogin.service.in" ]] || fail "Missing systemd service template."
command -v rpm-ostree >/dev/null || fail "rpm-ostree is required."
command -v dnf5 >/dev/null || fail "dnf5 is required."
systemctl list-unit-files plasmalogin.service --no-legend 2>/dev/null | grep -q '^plasmalogin.service' || fail "V1 requires KDE Plasma Login Manager."

sudo -v

PACKAGE_MARKER="/etc/bazsyi-sunshine/package-added-by-installer"
PACKAGE_PREEXISTING=yes
if [[ -f "$PACKAGE_MARKER" ]]; then
  PACKAGE_PREEXISTING=no
fi
if ! rpm -q "$PACKAGE" >/dev/null 2>&1; then
  PACKAGE_PREEXISTING=no
  say "Native Sunshine is not installed. Enabling LizardByte stable COPR and layering Sunshine."
  sudo install -d -m 0755 /etc/bazsyi-sunshine
  sudo touch "$PACKAGE_MARKER"
  sudo dnf5 -y copr enable "$COPR"
  sudo rpm-ostree install "$PACKAGE"
  say "The native package was added to a pending Bazzite deployment."
  say "Reboot normally, then run ./install.sh again. No login settings were changed."
  exit 10
fi

[[ -x /usr/bin/sunshine ]] || fail "Sunshine is layered but /usr/bin/sunshine is unavailable. Reboot, then rerun the installer."

find_adapter() {
  local status connector card card_device render
  for status in /sys/class/drm/card*-*/status; do
    [[ -r "$status" ]] || continue
    [[ "$(cat "$status")" == "connected" ]] || continue
    connector="$(basename "$(dirname "$status")")"
    card="${connector%%-*}"
    card_device="$(readlink -f "/sys/class/drm/$card/device" 2>/dev/null || true)"
    [[ -n "$card_device" ]] || continue
    for render in /sys/class/drm/renderD*; do
      [[ -e "$render" ]] || continue
      if [[ "$(readlink -f "$render/device" 2>/dev/null || true)" == "$card_device" ]]; then
        printf '%s|%s|%s\n' "/dev/dri/$(basename "$render")" "/dev/dri/$card" "$card"
        return 0
      fi
    done
  done
  return 1
}

if [[ -n "$REQUESTED_ADAPTER" ]]; then
  [[ -e "$REQUESTED_ADAPTER" ]] || fail "Requested adapter does not exist: $REQUESTED_ADAPTER"
  ADAPTER="$REQUESTED_ADAPTER"
  render_name="$(basename "$ADAPTER")"
  render_device="$(readlink -f "/sys/class/drm/$render_name/device" 2>/dev/null || true)"
  CARD_NAME=""
  for card_path in /sys/class/drm/card[0-9]*; do
    [[ -d "$card_path" ]] || continue
    if [[ "$(readlink -f "$card_path/device" 2>/dev/null || true)" == "$render_device" ]]; then
      CARD_NAME="$(basename "$card_path")"
      break
    fi
  done
  [[ -n "$CARD_NAME" ]] || fail "Could not map $ADAPTER to a DRM card."
  CARD_DEVICE="/dev/dri/$CARD_NAME"
else
  detected="$(find_adapter || true)"
  [[ -n "$detected" ]] || fail "Could not find a render device attached to a connected display."
  IFS='|' read -r ADAPTER CARD_DEVICE CARD_NAME <<<"$detected"
fi

say "Detected target"
printf 'User: %s (UID %s)\n' "$TARGET_USER" "$TARGET_UID"
printf 'Adapter: %s\n' "$ADAPTER"
printf 'DRM card: %s\n' "$CARD_DEVICE"
printf 'Monitor index: %s\n' "$OUTPUT_NAME"

PREVIOUS_LINGER="$(loginctl show-user "$TARGET_USER" -p Linger --value 2>/dev/null || printf no)"
FLATPAK_INSTALLED=no
FLATPAK_ENABLED=not-found
FLATPAK_ACTIVE=inactive
if flatpak info "$FLATPAK_ID" >/dev/null 2>&1; then
  FLATPAK_INSTALLED=yes
  FLATPAK_ENABLED="$(systemctl --user is-enabled "$FLATPAK_UNIT" 2>/dev/null || true)"
  FLATPAK_ACTIVE="$(systemctl --user is-active "$FLATPAK_UNIT" 2>/dev/null || true)"
fi

mkdir -p "$BACKUP"
chmod 700 "$BACKUP_ROOT" "$BACKUP"
if [[ -e "$CONFIG_DIR" ]]; then cp -a "$CONFIG_DIR" "$BACKUP/config-before-install"; fi
if [[ -f "$SERVICE_FILE" ]]; then sudo cp -a "$SERVICE_FILE" "$BACKUP/service-before-install"; sudo chown "$TARGET_USER:$TARGET_GROUP" "$BACKUP/service-before-install"; fi
if [[ -d "/etc/systemd/system/$SERVICE.d" ]]; then sudo cp -a "/etc/systemd/system/$SERVICE.d" "$BACKUP/dropins-before-install"; sudo chown -R "$TARGET_USER:$TARGET_GROUP" "$BACKUP/dropins-before-install"; fi
rpm-ostree status >"$BACKUP/rpm-ostree-status.txt" 2>&1 || true

if [[ ! -f "$NATIVE_STATE/sunshine_state.json" && -f "$FLATPAK_STATE/sunshine_state.json" ]]; then
  say "Migrating the existing Flatpak pairing and credentials to native Sunshine."
  install -d -m 700 "$NATIVE_STATE"
  for item in sunshine_state.json credentials apps.json; do
    if [[ -e "$FLATPAK_STATE/$item" ]]; then cp -a "$FLATPAK_STATE/$item" "$NATIVE_STATE/"; fi
  done
fi

install -d -m 700 "$CONFIG_DIR"
SOURCE_CONFIG=""
for candidate in "$ROOT_DIR/prelogin/sunshine.conf" "$CONFIG" "$NATIVE_STATE/sunshine.conf"; do
  if [[ -f "$candidate" ]]; then SOURCE_CONFIG="$candidate"; break; fi
done

TEMP_CONFIG="$(mktemp)"
if [[ -n "$SOURCE_CONFIG" ]]; then
  awk '!/^[[:space:]]*(capture|adapter_name|output_name|system_tray)[[:space:]]*=/' "$SOURCE_CONFIG" >"$TEMP_CONFIG"
fi
cat >>"$TEMP_CONFIG" <<EOF
capture = kms
adapter_name = $ADAPTER
output_name = $OUTPUT_NAME
system_tray = disabled
EOF
install -m 0600 "$TEMP_CONFIG" "$CONFIG"
rm -f "$TEMP_CONFIG"

sudo loginctl enable-linger "$TARGET_USER"
systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service

TEMP_SERVICE="$(mktemp)"
sed \
  -e "s|__USER__|$TARGET_USER|g" \
  -e "s|__GROUP__|$TARGET_GROUP|g" \
  -e "s|__UID__|$TARGET_UID|g" \
  -e "s|__HOME__|$TARGET_HOME|g" \
  -e "s|__CARD_DEVICE__|$CARD_DEVICE|g" \
  -e "s|__CARD_NAME__|$CARD_NAME|g" \
  -e "s|__CONFIG__|$CONFIG|g" \
  "$ROOT_DIR/systemd/bazsyi-sunshine-prelogin.service.in" >"$TEMP_SERVICE"

sudo install -d -m 0755 /etc/bazsyi-sunshine
sudo tee "$STATE_FILE" >/dev/null <<EOF
TARGET_USER=$TARGET_USER
TARGET_UID=$TARGET_UID
TARGET_GROUP=$TARGET_GROUP
TARGET_HOME=$TARGET_HOME
CONFIG=$CONFIG
PREVIOUS_LINGER=$PREVIOUS_LINGER
FLATPAK_INSTALLED=$FLATPAK_INSTALLED
FLATPAK_ENABLED=$FLATPAK_ENABLED
FLATPAK_ACTIVE=$FLATPAK_ACTIVE
PACKAGE_PREEXISTING=$PACKAGE_PREEXISTING
ADAPTER=$ADAPTER
CARD_DEVICE=$CARD_DEVICE
OUTPUT_NAME=$OUTPUT_NAME
EOF
sudo chmod 0644 "$STATE_FILE"

if [[ "$FLATPAK_INSTALLED" == yes ]]; then
  systemctl --user disable --now "$FLATPAK_UNIT" >/dev/null 2>&1 || true
fi
sudo install -o root -g root -m 0644 "$TEMP_SERVICE" "$SERVICE_FILE"
rm -f "$TEMP_SERVICE"
sudo rm -rf "/etc/systemd/system/$SERVICE.d"
sudo systemctl daemon-reload

if ! sudo systemctl enable --now "$SERVICE"; then
  sudo journalctl -u "$SERVICE" --no-pager -n 160 || true
  if [[ "$FLATPAK_INSTALLED" == yes && "$FLATPAK_ACTIVE" == active ]]; then systemctl --user enable --now "$FLATPAK_UNIT" || true; fi
  fail "The native pre-login service failed. The previous files remain in $BACKUP."
fi

sleep 3
sudo systemctl is-active --quiet "$SERVICE" || fail "The service did not remain active. Run sudo journalctl -u $SERVICE --no-pager."

say "Installation complete"
printf 'Service: enabled and active\n'
printf 'Configuration: %s\n' "$CONFIG"
printf 'Backup: %s\n' "$BACKUP"
printf 'Auto-login: unchanged\n'
printf 'Flatpak rollback copy: %s\n' "$FLATPAK_INSTALLED"
say "Run ./verify.sh, then reboot and connect from Moonlight at the login screen."
