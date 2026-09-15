# FydeOS fixes for Lenovo IdeaPad Duet 5 12IAU7

Tested on FydeOS 23.0-SP1 (`amd64-fydeos_iris`) running from a Live USB on a Lenovo IdeaPad Duet 5 12IAU7 (Intel Core i5-1235U).

## Current status

- Power button: **WORKING** with native ChromeOS/Ash tablet behavior.
- Auto Rotate: **WORKING / DO NOT MODIFY** (existing Python workaround).
- Touchpad re-probe after keyboard detach/reattach: **WORKING / DO NOT MODIFY**.

## Power-button fix

The generic build launched Chrome/Ash with `--aura-legacy-power-button`, causing a short physical Power-button press to open the shutdown/lock menu. `/etc/chrome_dev.conf` now removes that conflicting switch and enables native tablet behavior:

```text
!--aura-legacy-power-button
--force-tablet-power-button
```

After restarting only the UI, the active Chrome command line contained `--force-tablet-power-button` and no longer contained `--aura-legacy-power-button`.

Verified behavior:

- Short press while awake: display off / lock, no shutdown menu.
- Short press again: display wakes normally.
- powerd logs confirm backlight off/on only; no suspend occurred.
- Touchscreen and the existing Auto Rotate daemon remained available.

See [HANDOFF.md](HANDOFF.md) for the investigation evidence, backup location, rollback commands, and persistence notes.

## Safety

This work did not modify internal Windows/NVMe partitions, BIOS/UEFI, the kernel, autorotate files, or the existing touchpad workaround.
