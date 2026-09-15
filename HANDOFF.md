# Lenovo IdeaPad Duet 5 12IAU7 — FydeOS Fixes

Test system: FydeOS 23.0-SP1 (`amd64-fydeos_iris`), Chrome 150.0.7871.208, Live USB.

## Working Fixes — Do Not Modify

- **Auto Rotate = WORKING / DO NOT MODIFY.** The existing Python workaround at `/usr/local/duet-autorotate/duet-autorotate daemon` remained running after the UI restart and power-button test. No autorotate file or logic was changed during this work.
- **Touchpad re-probe workaround = WORKING / DO NOT MODIFY.** Existing recovery command after keyboard detach/reattach:

  ```sh
  sudo sh -c 'printf "%s\n" "1-3:1.1" > /sys/bus/usb/drivers_probe'
  ```

  No touchpad workaround file or logic was changed during this work.

## Power Button

### Original symptom

A short press of the physical Power button opened the shutdown/sign-out/lock power menu instead of turning the display off and locking the device.

### Root cause

The generic FydeOS build enables the `legacy_power_button` build setting:

- `/etc/ui_use_flags.txt` contains `legacy_power_button`.
- `/usr/share/power_manager/legacy_power_button` contains `1`.
- Session manager consequently launched Chrome/Ash with `--aura-legacy-power-button`.

The physical ACPI Power Button reports distinct down and up events, but `--aura-legacy-power-button` tells Ash to use the legacy ACPI interpretation where release timing is not meaningful. That made a short press take the legacy power-menu path. The installed Chrome binary contains native support for `--force-tablet-power-button`; it contains no `--force-clamshell-power-button` switch.

ChromiumOS reference: <https://chromium.googlesource.com/chromiumos/platform2/+/HEAD/power_manager/docs/power_buttons.md>

### Native fix

Changed `/etc/chrome_dev.conf` by adding only these directives:

```text
!--aura-legacy-power-button
--force-tablet-power-button
```

The first directive removes the conflicting build-injected legacy Ash switch. This removal is required because Ash selects the legacy handler before evaluating tablet behavior. The second directive forces tablet-like Power-button behavior even when the detachable keyboard is attached.

`/usr/share/power_manager/legacy_power_button` was intentionally left unchanged. In powerd that preference selects which duplicate input interface is ignored; Ash controls the user-visible short/long-press behavior.

After `restart ui`, the active browser command line contained `--force-tablet-power-button` and did not contain `--aura-legacy-power-button`.

### Verification

Physical test confirmed:

- Short press while awake -> display off / lock; no shutdown menu.
- Short press again -> display wakes normally; no reboot.
- Touchscreen device remained present at `/dev/input/event4`, bound to `hid-multitouch`.
- Auto Rotate daemon remained running.

This was display-off/lock, not system suspend:

- Before and after the test, `/sys/power/suspend_stats/success` was `0` and `fail` was `0`.
- Uptime remained continuous.
- powerd logged `Received request to start forcing backlights off` and brightness `0%` on the first press.
- powerd logged `Received request to stop forcing backlights off` and restored brightness on the second press.
- No suspend/resume entry occurred during the button test.

The current `[s2idle] deep` selection is separate from this Power-button fix and was not changed here.

Long-press was physically tested and does not open the menu on this device. The Intel HID input path reports an immediate synthetic release, so Ash cannot measure the physical hold duration; see "Long-press limitation" below.

### Files changed and backup

System configuration changed:

- `/etc/chrome_dev.conf`

Backup created before editing:

- `/etc/chrome_dev.conf.power-button.bak-20260915T1605Z`
- Original SHA-256: `896d997f033a48ca065d009782b6a03c41a4a58e133f7246e32e815ad5a83602`

Documentation created because the requested `duet-fydeos-fixes/HANDOFF.md` was not present in the accessible Live USB/user paths:

- `/home/chronos/user/MyFiles/Downloads/duet-fydeos-fixes/HANDOFF.md`

The Live USB root filesystem was temporarily remounted read-write for the backed-up edit and then restored to read-only. No internal Windows/NVMe partition, BIOS/UEFI, kernel, autorotate file, or touchpad workaround was modified.

### Rollback

The exact backup restore sequence is:

```sh
sudo mount -o remount,rw /
sudo cp --preserve=mode,ownership,timestamps \
  /etc/chrome_dev.conf.power-button.bak-20260915T1605Z \
  /etc/chrome_dev.conf
sudo chmod 0644 /etc/chrome_dev.conf
sudo mount -o remount,ro /
sudo restart ui
```

This restores the entire pre-test file. If unrelated lines are added to `chrome_dev.conf` later, remove only the following two exact lines instead of restoring the old backup:

```text
!--aura-legacy-power-button
--force-tablet-power-button
```

Then restart only the UI.

### Persistence

The fix is stored in `/etc/chrome_dev.conf` on the Live USB root filesystem and survives UI restarts. A full reboot with these newly added lines has not yet been physically tested, so reboot persistence is expected but not yet marked verified.

## Suspend / Resume

### S2Idle Power-button wake test

On 2026-09-15, a controlled native suspend was requested through `/usr/bin/powerd_dbus_suspend` while `/sys/power/mem_sleep` showed `[s2idle] deep`.

Pre-test state:

- Successful suspend count: `0`
- Failed suspend count: `0`
- ACPI `PNP0C0C` wake setting: `enabled`
- Touchscreen: HIMX1234 at `/dev/input/event4`, bound to `hid-multitouch`
- Auto Rotate daemon: running

Result:

- powerd configured suspend mode to `s2idle` and completed the suspend request successfully.
- The system remained suspended for approximately 32 seconds, so this is a short suspend test rather than a completed one-minute test.
- The user physically woke the device with a short press of the side Power button.
- Successful suspend count increased from `0` to `1`; failed count remained `0`.
- Display resumed and the user physically confirmed that touchscreen input still worked.
- Auto Rotate daemon remained running after resume.
- No reboot or crash occurred.

Wake-source evidence:

- `/sys/power/pm_wakeup_irq` reported IRQ `9`.
- `/sys/devices/platform/INTC1070:00` event count increased from `0` to `1`.
- The ACPI `PNP0C0C` Power-button event counter remained `0`.
- This indicates that the physical side Power button wakes this device through the Intel HID (`INTC1070`) path rather than the generic ACPI Power Button path.

Resume warnings:

- The kernel logged `i915`/DSI display warnings including `DSI link not ready` and pipe-mode mismatch messages after resume.
- Despite these warnings, the display returned and the test remained usable.

Status: **SHORT S2IDLE TEST PASSED (32 seconds)**. A full one-minute and longer-duration test remain pending.

### Long-press limitation

A physical approximately two-second Power-button hold was captured simultaneously from the two native Power-capable input devices:

- `/dev/input/event2` (`Power Button`, ACPI `PNP0C0C`) reported no event.
- `/dev/input/event15` (`Intel HID 5 button array`, `INTC1070`) reported `KEY_POWER=1` followed by `KEY_POWER=0` only 27 microseconds later.
- powerd consequently logged Power-button down/up only about 3.5 milliseconds apart and requested that the backlights be forced off.
- The suspend-success counter did not change, confirming that this was screen-off rather than suspend.

The firmware/Intel HID path therefore exposes the side button as an instantaneous pulse and does not expose the physical hold duration to userspace. Ash cannot distinguish a two-second hold from a tap.

Native behavior tradeoff on this build:

- With `--aura-legacy-power-button`: every pulse takes the legacy menu/lock path, including short presses.
- With `!--aura-legacy-power-button` plus `--force-tablet-power-button`: every pulse is treated as a short tablet press, providing the desired screen off/on behavior but no timed long-press menu.

There is no additional supported `--force-clamshell-power-button` switch in the installed Chrome binary, and combining the legacy and tablet switches does not help because Ash dispatches to the legacy handler first.

Decision: keep the tablet short-press fix because it provides the requested everyday tablet behavior. Use the on-screen system menu for normal shutdown. A firmware-level very-long hold may still force power off, but it is an emergency action that risks data loss and was not tested. Implementing a different long-press gesture would require a non-native workaround and cannot recover hold duration that the kernel input interface never reports.
