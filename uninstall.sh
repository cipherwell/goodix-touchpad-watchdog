#!/usr/bin/env bash
# goodix-touchpad-watchdog uninstaller
#
# Stops and disables the timer/service, removes installed files.
# Does NOT touch /etc/libinput/local-overrides.quirks (you may have
# customized it). Use --purge-libinput to remove it too.
#
# Usage:
#   sudo ./uninstall.sh
#   sudo ./uninstall.sh --dry-run
#   sudo ./uninstall.sh --purge-libinput
#   sudo ./uninstall.sh --dry-run --purge-libinput

set -euo pipefail

DRY_RUN=0
PURGE_LIBINPUT=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    --purge-libinput) PURGE_LIBINPUT=1 ;;
    *) echo "ERROR: unknown argument: $arg" >&2; exit 2 ;;
  esac
done

if (( EUID != 0 )); then
  echo "ERROR: must be run as root (try: sudo $0)" >&2
  exit 1
fi

run() {
  if (( DRY_RUN )); then
    echo "  [dry-run] $*"
  else
    echo "  $*"
    "$@"
  fi
}

# Same semantics as install.sh's systemctl_run: don't fail if systemd
# isn't actually running in this environment.
systemctl_run() {
  if (( DRY_RUN )); then
    echo "  [dry-run] systemctl $*"
    return 0
  fi
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "  WARNING: systemctl not found, skipping: $*"
    return 0
  fi
  if ! systemctl "$@" 2>/tmp/uninstall-sh-systemctl-err.$$; then
    err=$(cat /tmp/uninstall-sh-systemctl-err.$$ 2>/dev/null)
    rm -f /tmp/uninstall-sh-systemctl-err.$$
    if [[ "$err" == *"Failed to connect to bus"* ]] \
       || [[ "$err" == *"System has not been booted with systemd"* ]] \
       || [[ "$err" == *"Connection refused"* ]]; then
      echo "  WARNING: systemd is not running here, skipping: systemctl $*"
      return 0
    fi
    echo "  ERROR: systemctl $* failed: $err" >&2
    return 1
  fi
  rm -f /tmp/uninstall-sh-systemctl-err.$$
}

echo "Stopping and disabling the timer..."
systemctl_run disable --now goodix-touchpad-watchdog.timer || true
systemctl_run stop goodix-touchpad-watchdog.service || true

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

systemctl_run daemon-reload

echo
echo "Uninstalled. Reboot (or re-login) to fully clear the touchpad state."
