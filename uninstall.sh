#!/usr/bin/env bash
# goodix-touchpad-watchdog uninstaller
#
# Stops and disables the timer/service, removes installed files.
# Does NOT touch /etc/libinput/local-overrides.quirks (you may have
# customized it). Use --purge-libinput to remove it too.
#
# Usage:
#   sudo ./uninstall.sh
#   sudo ./uninstall.sh --purge-libinput

set -euo pipefail

PURGE_LIBINPUT=0
if [[ "${1:-}" == "--purge-libinput" ]]; then
  PURGE_LIBINPUT=1
fi

if (( EUID != 0 )); then
  echo "ERROR: must be run as root (try: sudo $0)" >&2
  exit 1
fi

run() { echo "  $*"; "$@"; }

echo "Stopping and disabling the timer..."
run systemctl disable --now goodix-touchpad-watchdog.timer || true
run systemctl stop goodix-touchpad-watchdog.service || true

echo "Removing installed files..."
run rm -f /usr/local/sbin/goodix-touchpad-watchdog
run rm -rf /etc/goodix-touchpad-watchdog
run rm -f /etc/systemd/system/goodix-touchpad-watchdog.service
run rm -f /etc/systemd/system/goodix-touchpad-watchdog.timer
run rm -f /run/goodix-touchpad-watchdog.last

if (( PURGE_LIBINPUT )); then
  echo "Removing libinput override (--purge-libinput)..."
  run rm -f /etc/libinput/local-overrides.quirks
else
  echo
  echo "Note: /etc/libinput/local-overrides.quirks left in place."
  echo "      Re-run with --purge-libinput to remove it too."
fi

run systemctl daemon-reload

echo
echo "Uninstalled. Reboot (or re-login) to fully clear the touchpad state."
