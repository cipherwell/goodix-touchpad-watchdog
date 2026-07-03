# Bug analysis: Goodix DLL0945 i2c-hid lag

## Hardware

- **Touchpad:** Goodix DLL0945:00 (USB vendor 0x04F3, product 0x311C) — an
  I²C-HID device on `i2c_designware.1` (the second Intel LPSS I²C
  controller on the Dell XPS 15 9510).
- **Touchscreen:** ELAN ELAN2D25:00 on `i2c_designware.0` — separate bus,
  separate driver state. Not involved.
- The "04F3" vendor ID is registered to ELAN Microelectronics, but
  "DLL0945" is a Goodix product code. **Vendor ID lies** here. The chip
  firmware is from Goodix.

## Symptom

Cursor drifts off or ignores input while making slow movements on the
touchpad. Bursts of 5-100 errors within 1-2 seconds, then quiet for
minutes. Affects Linux only because the i2c-hid driver is the same
across distros; Windows uses a custom Goodix driver that doesn't have
this bug.

The Dell OEM firmware is the same for both: `0c` (current as of 2022).
Reflashing does not help.

## Root cause

`i2c-hid` polls the device for reports. When the device has no data
ready, it returns `0xff` as a sentinel. The driver logs:

```
i2c_hid_acpi i2c-DLL0945:00: device returned incorrect report (255 vs N expected)
```

…treating the sentinel as a corrupted read. After enough of these in
quick succession, the bus state is wrong and the touchpad stops
producing events until the i2c-hid device is rebound.

The exact cause inside `i2c-hid` is a missing "treat 0xff as 'try again'"
quirk for this device family. There's no in-tree fix as of kernel 6.16 /
2026-Q2.

## Why the firmware-update path is a dead end

The widely-shared **m-bartlett 0c.bin** firmware (gist
`78d0748b279b7c4c2efd9c93c7496405`) is the correct firmware for the
ELAN 04F3:xxxx touchpad on the **Precision 5560** and some **9510**
configurations. The Dell updater at
`dl.dell.com/FOLDER08634339M/3/FWUpdate_v1.0.3.0_DellMUP_Fv0C_Trial_04_ZPE.exe`
brings the same model to firmware `0c`. **If your touchpad is already
at 0c** (which it almost certainly is, given the 9510 shipped with
this fix in late 2022), flashing 0c again is a no-op.

The m-bartlett `install-touchpad-firmware` script also won't work on
most modern setups because it uses `fwupdtool install-blob` with an
i2c-hid device. fwupd's `elantp` plugin can't see devices that
`i2c_hid_acpi` has already claimed via hidraw.

## Why a user-space watchdog is the right fix

A kernel patch would be the proper fix, but it needs:

1. The maintainers to agree on the right semantics for the 0xff
   sentinel (retry vs. reset vs. ignore).
2. A backport to every LTS kernel in active use.
3. Months of review and testing.

The watchdog sidesteps all three by detecting the symptom in the kernel
log and resetting the device from user-space. The touchpad drops for
~50-100 ms during the rebind, then resumes from a clean state. The
`COOLDOWN_SECONDS=300` default prevents rebind-storms.

## Why this approach is robust

- **No kernel patches.** Works on every Linux distro that ships the
  i2c-hid modules (i.e. all of them).
- **No device firmware changes.** No risk of bricking.
- **Reversible.** A single `uninstall.sh` undoes everything except
  the libinput quirk (which is opt-in).
- **Self-healing.** After a reboot the timer comes back up and the
  watchdog resumes automatically.
- **Auditable.** Everything is in `/usr/local/sbin` and
  `/etc/systemd/system` — standard system paths.

## Trade-offs

- A rebind is briefly visible: cursor freezes for ~50-100 ms, then
  resumes. With 5-min cooldown, this is at most once every 5 minutes
  even under sustained errors.
- The watchdog reads `journalctl -k` every 30s, which is fast on SSDs
  but adds ~1-2% to idle CPU on slow disks. Not a concern in practice.
- If your kernel is patched upstream to handle 0xff correctly, the
  watchdog becomes a no-op (no errors → no rebinds). It can be
  uninstalled safely.

## Verification recipe

To confirm the watchdog is doing useful work:

```bash
# Count errors in the last hour
journalctl -k --since "1 hour ago" | grep -c "i2c_hid_acpi i2c-DLL0945:00: device returned incorrect"

# Watch the watchdog in real time
journalctl -t goodix-touchpad-watchdog -f

# Force a check (in DRY_RUN mode to see what would happen)
sudo DRY_RUN=1 VERBOSE=1 /usr/local/sbin/goodix-touchpad-watchdog

# Manually trigger a rebind
sudo bash -c 'echo i2c-DLL0945:00 > /sys/bus/i2c/drivers/i2c_hid_acpi/unbind && \
              sleep 1 && \
              echo i2c-DLL0945:00 > /sys/bus/i2c/drivers/i2c_hid_acpi/bind'
```
