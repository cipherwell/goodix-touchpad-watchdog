# goodix-touchpad-watchdog

A user-space watchdog that fixes the **laggy Goodix touchpad on Dell XPS 15
9510 and similar laptops** by rebinding the i2c-hid device when its bus
corrupts.

## The problem

If your laptop has a touchpad that **drifts off or ignores input while making
slow movements**, and dmesg shows errors like:

```
i2c_hid_acpi i2c-DLL0945:00: device returned incorrect report (255 vs 5 expected)
i2c_hid_acpi i2c-DLL0945:00: device returned incorrect report (255 vs 8 expected)
i2c_hid_acpi i2c-DLL0945:00: device returned incorrect report (255 vs 9 expected)
```

…then you have a known issue with the **Goodix DLL0945:00 04F3:311C** touchpad
on the I²C bus. The `0xff` ("no data") sentinel the device returns is
misinterpreted as an error by the in-tree `i2c-hid` driver. After a burst of
these errors, the bus gets into a confused state and the touchpad stops
producing events until the i2c-hid device is reset.

This is **not** a firmware issue. Your touchpad is probably already at the
latest firmware (`0c`). It's a **driver** issue, and the proper upstream
fix hasn't landed yet.

This watchdog detects the burst pattern and rebinds the device automatically
— the touchpad drops for ~50 ms and comes back clean.

## Supported hardware

Confirmed working on:

- **Dell XPS 15 9510** (the original symptom target)
- **Dell Precision 5560** (shares the same chassis & touchpad)
- Any laptop with a **Goodix DLL0945:00 04F3:311C** touchpad on i2c-hid

Should also help on similar touchpads (ELAN 04F3:xxxx) if you adjust the
device name and error string in the script.

## Quick install

```bash
git clone https://github.com/cipherwell/goodix-touchpad-watchdog.git
cd goodix-touchpad-watchdog
sudo ./install.sh
```

That's it. The watchdog starts immediately, runs every 30 seconds, and
re-enables itself on boot. Verify with:

```bash
systemctl status goodix-touchpad-watchdog.timer
journalctl -t goodix-touchpad-watchdog -f
```

## What it installs

| File | Purpose |
| --- | --- |
| `/usr/local/sbin/goodix-touchpad-watchdog` | The watchdog script |
| `/etc/goodix-touchpad-watchdog/goodix-touchpad-watchdog.conf` | Tunables |
| `/etc/systemd/system/goodix-touchpad-watchdog.service` | Oneshot service |
| `/etc/systemd/system/goodix-touchpad-watchdog.timer` | 30s timer (enabled) |
| `/etc/libinput/local-overrides.quirks` | Sensible libinput defaults |

## Tunables

Edit `/etc/goodix-touchpad-watchdog/goodix-touchpad-watchdog.conf`:

| Variable | Default | Meaning |
| --- | --- | --- |
| `WINDOW_SECONDS` | `1800` | Look at the last 30 min of kernel log |
| `THRESHOLD` | `10` | Rebind when any 5-second bucket has this many errors |
| `COOLDOWN_SECONDS` | `300` | Minimum gap between rebinds (5 min) |
| `DEVICE` | `i2c-DLL0945:00` | i2c-hid client name to rebind |
| `DRY_RUN` | `0` | `1` = log but don't rebind (testing) |
| `VERBOSE` | `0` | `1` = log on every check, not just on action |

After editing, the next timer cycle picks up the new values automatically.

## Uninstall

```bash
sudo ./uninstall.sh
```

## How it works

The watchdog runs as a systemd oneshot every 30 seconds. On each run, it:

1. Checks `/etc/goodix-touchpad-watchdog/goodix-touchpad-watchdog.conf` for tunables.
2. Skips if the last rebind was within `COOLDOWN_SECONDS`.
3. Reads `journalctl -k` for the last `WINDOW_SECONDS` and greps for the
   Goodix error pattern.
4. Buckets matching lines by 5-second epoch windows.
5. If any bucket has `>= THRESHOLD` errors, writes the i2c client name to
   `/sys/bus/i2c/drivers/i2c_hid_acpi/unbind`, sleeps 1 second, then writes
   it to `bind` to re-enumerate the device.
6. Records the rebind time in `/run/goodix-touchpad-watchdog.last` for cooldown.

The touchpad drops for ~50-100 ms during the rebind. Then events resume from
a clean state.

## See also

- [`docs/bug-analysis.md`](docs/bug-analysis.md) — what's actually wrong and
  why this approach works
- [`docs/why-not-firmware.md`](docs/why-not-firmware.md) — why the m-bartlett
  `0c.bin` flash is a no-op on most modern hardware
- [libinput issue #618](https://gitlab.freedesktop.org/libinput/libinput/-/issues/618)
- [libinput issue #636](https://gitlab.freedesktop.org/libinput/libinput/-/issues/636)
- [ArchWiki: Dell XPS 15 (9510)](https://wiki.archlinux.org/title/Dell_XPS_15_(9510))
- [Dell community thread on this exact issue](https://www.dell.com/community/en/conversations/xps/xps-15-9510-touchpad-intermittent-touchpad-lag/647f95a5f4ccf8a8de834c71)

## License

MIT — see [LICENSE](LICENSE).
