# Why flashing 0c.bin is a dead end

A widely-shared solution on the Dell XPS 15 9510 / Precision 5560
touchpad-lag problem is the gist at
<https://gist.github.com/m-bartlett/78d0748b279b7c4c2efd9c93c7496405>.
It distributes `0b.bin` and `0c.bin` firmware blobs plus an
`install-touchpad-firmware` script that uses `fwupdtool install-blob`.

This document explains why that path **does not help most people** in
2026, and why we still need this watchdog.

## What the m-bartlett gist actually does

The `install-touchpad-firmware` script:

1. Runs `fwupdtool get-devices` to find a Touchpad device ID.
2. Runs `fwupdtool install-blob <firmware> <device-id>` to flash it.

For this to work, **two things must be true**:

1. fwupd must see the touchpad in `get-devices`.
2. fwupd's `elantp` plugin must match the device.

On a typical 2026 Linux install with the i2c-hid driver enabled,
**neither is true**.

## Why fwupd can't see the touchpad

`fwupd` enumerates devices via subsystem matches. For ELAN i2c-hid
touchpads, the `elantp` plugin is supposed to match on
`HIDRAW\VEN_04F3&DEV_xxxx` and offer the device for firmware update.

But on the XPS 15 9510 (and most laptops shipping in 2022+), the
`i2c_hid_acpi` kernel module binds the i2c-hid device and exposes it
as `/dev/hidrawN` *before* `fwupd` runs its enumeration. The `elantp`
plugin sees the device, attempts to claim it for firmware mode
(claiming the hidraw fd), and **fails** because `i2c_hid_acpi` already
holds it. The device is then silently dropped from `get-devices`.

You can confirm this with:

```bash
$ sudo fwupdtool get-devices | grep -iE "touch|hidraw"
(no output)
```

The result: `get-devices` lists every other firmwareable device on the
system (SSD, fingerprint reader, UEFI, etc.) but **not the touchpad**.

## Why the firmware is probably already 0c

The Dell XPS 15 9510 was released in 2020 with the original touchpad
firmware `0a`. Dell shipped a fix firmware `0c` in **late 2022** as part
of the OEM update package
`FWUpdate_v1.0.3.0_DellMUP_Fv0C_Trial_04_ZPE.exe`. Most 9510s sold
after 2022 Q4 — and most users who have run a Windows update at any
point since — already have `0c` installed.

You can verify with `fwupd` (when it can see the device) or with the
HID feature report query described in `bug-analysis.md`.

## Why the m-bartlett install script is hard to get working

If you want to flash anyway (e.g. to downgrade then re-upgrade, or to
get from `0a` → `0c` on a never-updated machine), you need to:

1. **Unbind the i2c-hid driver** so the hidraw device is free for
   fwupd: `echo i2c-DLL0945:00 | sudo tee /sys/bus/i2c/drivers/i2c_hid_acpi/unbind`
2. Run `fwupdtool get-devices` — the touchpad should now appear.
3. Run the m-bartlett script.
4. Rebind: `echo i2c-DLL0945:00 | sudo tee /sys/bus/i2c/drivers/i2c_hid_acpi/bind`

This works but is fiddly, requires a working fwupd, requires the
correct firmware file, and is **no-op** for users already on `0c`.

## The watchdog is the right fix because

1. **The firmware isn't the problem.** It's a driver issue with how
   `i2c-hid` handles the 0xff sentinel.
2. **Flashing is invasive.** The watchdog is reversible and stays out
   of the firmware-update path entirely.
3. **The lag recurs even with correct firmware.** The 0xff issue is
   independent of which firmware version is running. The watchdog
   handles both `0c` and older firmwares.

If you have an XPS 15 9510 with touchpad lag, the watchdog fixes it
regardless of your current firmware version.
