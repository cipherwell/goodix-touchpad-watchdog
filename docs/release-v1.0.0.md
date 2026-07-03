## goodix-touchpad-watchdog v1.0.0

First public release. Fixes the laggy Goodix DLL0945:00 04F3:311C touchpad
on Dell XPS 15 9510 and similar laptops by rebinding the i2c-hid device
when its bus corrupts.

### Install

```bash
curl -fsSL https://raw.githubusercontent.com/cipherwell/goodix-touchpad-watchdog/v1.0.0/install.sh | sudo bash
```

Or manually:

```bash
git clone https://github.com/cipherwell/goodix-touchpad-watchdog.git
cd goodix-touchpad-watchdog
sudo ./install.sh
```

### What it does

- Detects bursts of `i2c_hid_acpi i2c-DLL0945:00: device returned incorrect`
  errors in the kernel log
- Rebinds the i2c-hid client to clear the stuck bus state
- Runs as a systemd timer (default: every 30 s) with a 5-minute cooldown
- Touchpad drops for ~50 ms during the rebind; events resume clean

### What's in this release

- `usr/local/sbin/goodix-touchpad-watchdog` — the watchdog script
- `etc/systemd/system/goodix-touchpad-watchdog.{service,timer}` — systemd units
- `etc/goodix-touchpad-watchdog/goodix-touchpad-watchdog.conf` — tunables
- `etc/libinput/local-overrides.quirks` — sensible libinput defaults
- `install.sh` / `uninstall.sh` — one-shot installer/uninstaller
- `docs/bug-analysis.md` — root-cause analysis
- `docs/why-not-firmware.md` — why the firmware flash is a no-op
- `.github/workflows/ci.yml` — shellcheck + install/uninstall CI

### Hardware

Confirmed on:
- Dell XPS 15 9510
- Dell Precision 5560
- Any laptop with Goodix DLL0945:00 04F3:311C on i2c-hid

### License

MIT
