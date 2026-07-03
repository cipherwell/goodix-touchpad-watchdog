#!/usr/bin/env bash
# goodix-touchpad-watchdog installer
#
# Installs the watchdog, the systemd units, the libinput override, and
# starts the timer. Safe to re-run.
#
# Usage:
#   sudo ./install.sh             # install + start
#   sudo ./install.sh --dry-run   # show what would be done

set -euo pipefail

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]] || [[ "${1:-}" == "-n" ]]; then
  DRY_RUN=1
fi

# --- locate ourselves ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SRC_BIN="$SCRIPT_DIR/usr/local/sbin/goodix-touchpad-watchdog"
SRC_CONF_DIR="$SCRIPT_DIR/etc/goodix-touchpad-watchdog"
SRC_SYSTEMD_DIR="$SCRIPT_DIR/etc/systemd/system"
SRC_LIBINPUT="$SCRIPT_DIR/etc/libinput/local-overrides.quirks"

# --- preflight ---
if (( EUID != 0 )); then
  echo "ERROR: must be run as root (try: sudo $0)" >&2
  exit 1
fi

for f in "$SRC_BIN" "$SRC_CONF_DIR/goodix-touchpad-watchdog.conf" \
         "$SRC_SYSTEMD_DIR/goodix-touchpad-watchdog.service" \
         "$SRC_SYSTEMD_DIR/goodix-touchpad-watchdog.timer" \
         "$SRC_LIBINPUT"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: missing source file: $f" >&2
    exit 1
  fi
done

# Detect the touchpad device on this system. The default is
# "i2c-DLL0945:00" (Dell XPS 15 9510). Other laptops with the same chip
# may have a different i2c client name; warn if we don't see it.
DETECTED_DEVICE=""
if [[ -d /sys/bus/i2c/drivers/i2c_hid_acpi ]]; then
  for client in /sys/bus/i2c/drivers/i2c_hid_acpi/i2c-*; do
    [[ -e "$client" ]] || continue
    name=$(basename "$client")
    # Glob-expand the children: matches 0018:04F3:311C.NNNN
    matches=( "$client"/0018:04F3:311C.* )
    if [[ -d "${matches[0]:-}" ]]; then
      DETECTED_DEVICE="$name"
      break
    fi
  done
fi

if [[ -z "$DETECTED_DEVICE" ]]; then
  echo "WARNING: no i2c-hid client found matching 04F3:311C." >&2
  echo "         This watchdog is tuned for the Goodix DLL0945:00 04F3:311C." >&2
  echo "         If your touchpad is different, edit DEVICE in" >&2
  echo "         /etc/goodix-touchpad-watchdog/goodix-touchpad-watchdog.conf after install." >&2
  echo >&2
  read -rp "Continue anyway? [y/N] " ans
  if [[ ! "$ans" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
  fi
else
  echo "Detected touchpad: $DETECTED_DEVICE"
fi

# --- helper ---
run() {
  if (( DRY_RUN )); then
    printf '  [dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

# --- install ---
echo "Installing goodix-touchpad-watchdog..."

run install -d /usr/local/sbin
run install -m 0755 "$SRC_BIN" /usr/local/sbin/goodix-touchpad-watchdog

run install -d /etc/goodix-touchpad-watchdog
run install -m 0644 "$SRC_CONF_DIR/goodix-touchpad-watchdog.conf" \
              /etc/goodix-touchpad-watchdog/goodix-touchpad-watchdog.conf

run install -d /etc/systemd/system
run install -m 0644 "$SRC_SYSTEMD_DIR/goodix-touchpad-watchdog.service" \
              /etc/systemd/system/goodix-touchpad-watchdog.service
run install -m 0644 "$SRC_SYSTEMD_DIR/goodix-touchpad-watchdog.timer" \
              /etc/systemd/system/goodix-touchpad-watchdog.timer

# libinput local overrides: only write if it doesn't exist (don't clobber
# user customizations on re-install).
if [[ ! -f /etc/libinput/local-overrides.quirks ]]; then
  run install -d /etc/libinput
  run install -m 0644 "$SRC_LIBINPUT" /etc/libinput/local-overrides.quirks
else
  echo "  /etc/libinput/local-overrides.quirks already exists, leaving it alone."
  echo "  To install the included override, merge it manually."
fi

# --- start ---
echo "Enabling and starting the timer..."
run systemctl daemon-reload
run systemctl enable goodix-touchpad-watchdog.timer
run systemctl restart goodix-touchpad-watchdog.timer

if (( DRY_RUN )); then
  echo
  echo "Dry run complete. Re-run without --dry-run to actually install."
else
  echo
  echo "Installed. Verify with:"
  echo "  systemctl status goodix-touchpad-watchdog.timer"
  echo "  journalctl -t goodix-touchpad-watchdog -f"
  echo
  echo "Tune via /etc/goodix-touchpad-watchdog/goodix-touchpad-watchdog.conf"
  echo "(the next timer cycle picks up changes automatically)."
fi
