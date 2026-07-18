#!/usr/bin/env bash
set -u

SERVICE="bazsyi-sunshine-prelogin.service"
STATE_FILE="/etc/bazsyi-sunshine/install-state"
FAILURES=0

pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; FAILURES=$((FAILURES + 1)); }
info() { printf 'INFO  %s\n' "$*"; }

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  printf 'Usage: ./verify.sh\n'
  exit 0
fi

if [[ -r "$STATE_FILE" ]]; then
  . "$STATE_FILE"
else
  TARGET_USER="${USER}"
  TARGET_UID="$(id -u)"
  TARGET_HOME="$HOME"
  CONFIG="$HOME/.config/bazsyi-sunshine/sunshine.conf"
fi

rpm -q Sunshine >/dev/null 2>&1 && pass "Native Sunshine RPM installed" || fail "Native Sunshine RPM missing"
[[ -x /usr/bin/sunshine ]] && pass "Native Sunshine binary present" || fail "/usr/bin/sunshine missing"
[[ -f "$CONFIG" ]] && pass "Dedicated config present" || fail "Dedicated config missing: $CONFIG"

if [[ -f "$CONFIG" ]]; then
  grep -Eq '^[[:space:]]*capture[[:space:]]*=[[:space:]]*kms[[:space:]]*$' "$CONFIG" && pass "KMS capture configured" || fail "capture = kms missing"
  grep -Eq '^[[:space:]]*system_tray[[:space:]]*=[[:space:]]*disabled[[:space:]]*$' "$CONFIG" && pass "System tray disabled" || fail "system_tray = disabled missing"
  grep -Eq '^[[:space:]]*adapter_name[[:space:]]*=' "$CONFIG" && pass "DRM render adapter configured" || fail "adapter_name missing"
  grep -Eq '^[[:space:]]*output_name[[:space:]]*=' "$CONFIG" && pass "Monitor index configured" || fail "output_name missing"
fi

[[ "$(loginctl show-user "$TARGET_USER" -p Linger --value 2>/dev/null)" == yes ]] && pass "User lingering enabled" || fail "User lingering is not enabled"
systemctl --user is-active --quiet pipewire.service && pass "PipeWire active" || fail "PipeWire inactive"
systemctl --user is-active --quiet pipewire-pulse.service && pass "PipeWire Pulse active" || fail "PipeWire Pulse inactive"
systemctl --user is-active --quiet wireplumber.service && pass "WirePlumber active" || fail "WirePlumber inactive"
pactl list short sinks 2>/dev/null | grep -q sink-sunshine-stereo && pass "Sunshine virtual audio sink ready" || fail "sink-sunshine-stereo missing"

sudo systemctl is-enabled --quiet "$SERVICE" && pass "Pre-login service enabled" || fail "Pre-login service disabled"
sudo systemctl is-active --quiet "$SERVICE" && pass "Pre-login service active" || fail "Pre-login service inactive"

PROCESS_COUNT="$(pgrep -x sunshine 2>/dev/null | wc -l | tr -d ' ')"
[[ "$PROCESS_COUNT" == 1 ]] && pass "Exactly one Sunshine process running" || fail "Expected one Sunshine process, found $PROCESS_COUNT"

if systemctl --user is-active --quiet app-dev.lizardbyte.app.Sunshine.service; then
  fail "Flatpak Sunshine is also active"
else
  pass "Flatpak Sunshine is not active"
fi

if sudo journalctl -b -u "$SERVICE" --no-pager 2>/dev/null | grep -qiE 'Unable to initialize audio capture|Couldn.t connect to pulseaudio|Couldn.t set default-sink \[sink-sunshine-'; then
  fail "Current boot contains a Sunshine audio initialization error"
else
  pass "No current-boot Sunshine audio initialization errors"
fi

info "Service logs: sudo journalctl -b -u $SERVICE --no-pager"
if ((FAILURES)); then
  printf '\nVerification failed: %s issue(s).\n' "$FAILURES"
  exit 1
fi
printf '\nEverything looks ready. Reboot to test the real pre-login path.\n'
