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

A previous debug preload was cleaned up before the current runtime test. The current runtime test intentionally has the init bind mount and `/dev/uhid` chronos ACL active; use the rollback commands in the final runtime section to restore the original file hash `7bf7cea084ba5f0d4db67c1828211c67363c3cf7aa0260a5ef70d4f5b2d16e6a`.

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

Physical approximately two-second Power-button holds were captured across all three native Power-capable host input devices:

- `/dev/input/event2` (`Power Button`, ACPI `PNP0C0C`) reported no event.
- `/dev/input/event14` (`Intel HID events`, `INTC1070`) advertises `KEY_POWER` support but reported no event.
- `/dev/input/event15` (`Intel HID 5 button array`, `INTC1070`) reported `KEY_POWER=1` followed by `KEY_POWER=0` only 27 microseconds later.
- powerd consequently logged Power-button down/up only about 3.5 milliseconds apart and requested that the backlights be forced off.
- The suspend-success counter did not change, confirming that this was screen-off rather than suspend.

The only active side-button path is therefore `event15`; the firmware/Intel HID path exposes it as an instantaneous pulse and does not expose the physical hold duration to userspace. Ash cannot distinguish a two-second hold from a tap.

Native behavior tradeoff on this build:

- With `--aura-legacy-power-button`: every pulse takes the legacy menu/lock path, including short presses.
- With `!--aura-legacy-power-button` plus `--force-tablet-power-button`: every pulse is treated as a short tablet press, providing the desired screen off/on behavior but no timed long-press menu.

There is no additional supported `--force-clamshell-power-button` switch in the installed Chrome binary, and combining the legacy and tablet switches does not help because Ash dispatches to the legacy handler first.

Decision: keep the tablet short-press fix because it provides the requested everyday tablet behavior. Use the on-screen system menu for normal shutdown. A firmware-level very-long hold may still force power off, but it is an emergency action that risks data loss and was not tested. Implementing a different long-press gesture would require a non-native workaround and cannot recover hold duration that the kernel input interface never reports.


## Bluetooth Keyboard

Status: **DIAGNOSED / NOT FIXED. Auto Rotate = WORKING / DO NOT MODIFY.**

Hardware/controller:

- Lenovo keyboard advertised name: `Duet 5 KB`.
- Bluetooth address is privacy-random and changed on successive pairings; observed addresses were redacted in logs (`…:B5:00`, `…:B6:00`, `…:B7:00`, `…:B8:00`). Do not treat the address as a permanent identifier.
- Internal controller: Intel AX211 Bluetooth half of the Alder Lake-P CNVi platform; USB VID/PID `8087:0033` (Intel).
- Exact USB path: `/sys/bus/usb/devices/1-10` (`pci-0000:00:14.0-usb-0:10`). Interfaces `1-10:1.0` and `1-10:1.1` use `btusb`.
- Kernel driver/modules: `btusb`, `btintel`, `bluetooth` (also `btrtl`, `btbcm`, `btmtk` loaded).
- Original power state: `power/control=auto`, `runtime_status=suspended`, `autosuspend_delay_ms=2000`, `wakeup=disabled`. A temporary test set only this controller to `on`; the loop remained unchanged. The current Live USB session may still show `on`; restore with `sudo sh -c 'echo auto > /sys/bus/usb/devices/1-10/power/control'`.
- Readable service logs contain no Intel Bluetooth firmware-load error or loaded firmware revision. Installed Intel firmware includes compressed `ibt-0040-0041.*` and related files, but firmware must not be replaced blindly. Capture privileged `dmesg` on a future run if the exact loaded revision is required.

Keyboard protocol and evidence:

- Floss reports BLE device type, appearance `0x03C1` (keyboard), and UUIDs HID Service `0x1812` plus Battery Service `0x180F`.
- This is BLE HID/HOGP (`BT_TRANSPORT_LE`), not Classic HIDP. `/dev/uhid` exists (`bluetooth:bluetooth`, builtin kernel UHID support), so this is not a missing UHID module or basic permission failure.
- Pairing and encryption sometimes complete, but GATT discovery repeatedly fails. Logs show `hid_available=false`, `hogp_available=false`, `GATT_CONN_TIMEOUT`, GATT discovery status `133`, and `HCI_ERR_CONNECTION_TOUT` (`0x08`).
- On clean-pair attempts Floss also reports `Encryption failure 6`, `HCI_ERR_KEY_MISSING`, `Bond loss detected ... key_missing`, and `HCI_ERR_AUTH_FAILURE`; deleting only the two stale Lenovo bonds and pairing again did not fix it.
- When LE HID briefly opens, Floss logs `uhid_ready_disconn_timeout`; the kernel simultaneously logs `hid-multitouch ... item fetching failed at offset 511/512` and probe error `-22`. No Lenovo keyboard or touchpad `/dev/input/event*` node is created. The repeated report-descriptor failure is the direct reason the UHID handoff never becomes usable.

Classification: **D (BLE HID/HOGP), F (bond/encryption state), G (GATT/supervision timeout), H/I (UHID/input and keyboard report compatibility)**. Category A/B (USB autosuspend/runtime-PM) was tested and disproven; the controller remains active during failures and disabling autosuspend did not change behavior. No Intel firmware error was observed, so category C is unproven and should not be assumed.

Runtime actions tested:

- Temporary device-specific autosuspend disable on `/sys/bus/usb/devices/1-10` — **no improvement**; no global autosuspend change was made.
- Floss adapter-only Stop/Start for hci0 — reversible, did not improve the loop; Wi-Fi and other USB devices were untouched.
- Removed only Lenovo keyboard bond records (the exact observed privacy addresses), then re-paired; the same GATT/HOGP/UHID failures recurred. No other Bluetooth pairing data was wiped.

Persistent fix: **none proven; no persistent Bluetooth file or udev rule was added.** Do not claim success. The keyboard never met the 10-minute, typing, reconnect, or touchpad criteria. Pogo/physical keyboard operation remained outside this Bluetooth failure and was not modified. Wi-Fi was not intentionally changed. Auto Rotate files under `duet-fydeos-fixes/autorotate/` were not touched.

Rollback/runtime recovery:

```sh
# Restore the only temporary power-policy test
sudo sh -c 'echo auto > /sys/bus/usb/devices/1-10/power/control'

# If the adapter is left in a bad runtime state, restart only Floss hci0
gdbus call --system --dest org.chromium.bluetooth.Manager \
  --object-path /org/chromium/bluetooth/Manager \
  --method org.chromium.bluetooth.Manager.Stop 0
gdbus call --system --dest org.chromium.bluetooth.Manager \
  --object-path /org/chromium/bluetooth/Manager \
  --method org.chromium.bluetooth.Manager.Start 0
```

Files changed:

- Documentation only: this `HANDOFF.md` section.
- Backup before this edit: `HANDOFF.md.bluetooth-bak-20260915T1255Z` (SHA-256 `e02a414a6a33e5034292fc6aea638a0c77255661fce63a7f255e5f105f3327ff`).
- No autorotate, kernel, BIOS/UEFI, internal Windows/NVMe partition, or persistent Bluetooth configuration was changed.

Live USB notes:

- Runtime D-Bus state, Floss bonds, and `/sys` power policy are not reliable across reboot. The observed keyboard addresses are privacy-random and may change again.
- The current build uses Floss (`btmanagerd`/`btadapterd`), not a conventional BlueZ `bluetoothd`; `bluetoothctl`/`btmgmt` may block while Floss owns hci0. Use the Floss D-Bus API and `/var/log/bluetooth.log` for diagnostics.
- To reproduce: start logs, put the folio switch in the Bluetooth icon position for three seconds, pair `Duet 5 KB`, and capture `hid-multitouch`, `uhid_ready_disconn_timeout`, GATT, encryption, and HCI reason lines. Do not print Bluetooth key files.

Fresh FydeOS install instructions:

- Do not apply a global Bluetooth autosuspend disable or replace firmware based on this diagnosis.
- First verify whether a newer FydeOS/Floss/kernel build fixes the malformed Lenovo HOGP report handling. If testing a new image, collect the same controller path/VID/PID and logs before any pairing cleanup.
- Preserve the working Auto Rotate workaround exactly as documented above; do not modify `duet-fydeos-fixes/autorotate/`.


## Bluetooth Keyboard Final

Status: **OUTCOME B — exact Floss/HOGP failure path isolated and a minimal source patch produced.** The installed daemon was not replaced and end-to-end keyboard/touchpad success is not claimed. Auto Rotate, the pogo touchpad re-probe workaround, and `/etc/chrome_dev.conf` were not changed.

### Exact root cause

`Duet 5 KB` is BLE HOGP. Using Floss’s supported GATT client, HID Report Map handle 39 returned status 0 and exactly 512 bytes. The map SHA-256 is `262ed064b3a701846b7fd6eb4a7c7ce82ff2809cb1f1be71b42a07e1b30efd0b`. Its final bytes are `05 0d 09`: offset 509 is a complete Digitizers Usage Page item and offset 511 is a `Usage` short-item header requiring one data byte that GATT did not return. The kernel’s `item fetching failed at offset 511/512` is therefore the deterministic parser result, not an inferred timeout symptom.

The live sequence was repeatedly observed and captured:

```text
HOGP Report Map read succeeds with 512 bytes
-> bta_hh_le_save_report_map passes those 512 bytes unchanged
-> bta_hh_co_send_hid_info creates UHID with VID/PID 0000:0000
-> hid-multitouch stops at incomplete item offset 511/512 and returns -EINVAL
-> no usable input devices/UHID-ready event
-> Floss uhid_ready_disconn_timeout after 10 seconds
-> HID reconnect loop
```

This is a device/host interoperability defect at the GATT/HOGP boundary. GATT attribute values cannot exceed 512 bytes, but the keyboard’s report definition does. The exact inaccessible original BLE suffix cannot be read through conforming GATT and must not be confused with USB bytes.

### Pogo proof and descriptor comparison

The attached cover enumerated at USB path `1-3`, USB VID/PID `17ef:613a`, manufacturer/product `DOKING / Duet 5 USB Composite Device`.

- Interface `1-3:1.0`, HID `0003:17EF:613A.00B4`, driver `hid-generic`, event13, is the keyboard. Descriptor: 65 bytes; SHA-256 `5d2632c6a469ba4e8c722cfb8750332619605acd433cd38d88329dc5ddad7dae`.
- Interface `1-3:1.1`, HID `0003:17EF:613A.00B5`, driver `hid-multitouch`, is the composite controls/mouse/touchpad interface. Touchpad is specifically event27, proven by `INPUT_PROP_POINTER|BUTTONPAD`, multitouch absolute capabilities, and touch/tool/button keys. Descriptor: 913 bytes; SHA-256 `062662146e21d55159fc06f07eaa9735289dde6542ada3a5943312c11ffe89cb`.

BLE is not a literal prefix of either USB map because Bluetooth merges and changes the two USB interface descriptors. BLE/composite matching prefix is 3 bytes; first difference is zero-based offset 3 (`06` vs `80`). BLE/keyboard matching prefix is 6 bytes; first difference is offset 6 (`85` vs `05`). The strict “first 512 bytes equal pogo” sub-hypothesis is disproven, while the truncation chain itself is proven by the direct GATT bytes and parser boundary.

Structurally, both transports describe a five-contact touchpad. BLE Report ID 6 has three complete Finger collections before truncation, begins the fourth at offsets 509–511, and its live GATT value is exactly 24 bytes. Five BLE contact blocks account for 20 bytes; the scan-time/contact-count/button tail accounts for 4 bytes.

### Installed Floss implementation

- Package: `net-wireless/floss-0.0.2-r8327` from repository `chromiumos`.
- Exact AOSP Bluetooth commit: `85ccfbdb4f09b90bc1d7171ac77c979e9b299e2e`.
- Exact affected source: `system/bta/hh/bta_hh_le.cc`.
- Installed `/usr/bin/btadapterd`: 12,469,120 bytes; SHA-256 `f558b5cf7f5dccbdb5292155ed829e1f9058e4b2dc993bfc5ea1d8af71455ca8`.
- Installed `/usr/bin/btmanagerd`: SHA-256 `2cc592a553e114c53a395e3d21375fe060c5312dec1d371b51b1a45ce17035f0`.

This build has `[INTEROP_HOGP_LONG_REPORT]`, but `bta_hh_le_save_report_map()` implements it with a hard-coded 101-byte Brydge suffix and selects it only through `interop_match_vendor_product_ids`. The sole database entry is Brydge `03f6:a001`. Lenovo’s Device Information/PnP data is absent and Floss reports HID VID/PID `0000:0000`; a name entry cannot match that API, while a `0000:0000` entry would affect unrelated devices. The Brydge bytes are not Lenovo bytes. Therefore no safe config-only fix exists in this build.

### Patch

Portable patch:

`bluetooth-keyboard/patch/0001-FLOSS-HOGP-repair-Lenovo-Duet-5-KB-report-map.patch`

Patch SHA-256: `173d07075e93d720567ce831152ea44a5e9acfb1cf3a1c0b4cb61c3d9a0f6207`.

The patch matches the complete received map by exact SHA-256 rather than name/address/VID/PID. It then appends only `lenovo-verified-residual.bin`, leaving Brydge and every unrelated descriptor on the original code path. The daemon already links `libcrypto.so.3`, and both the `libbt-bta` and `bluetooth_hh_test` build targets declare `libcrypto`.

Residual:

- Length: 207 bytes.
- SHA-256: `86f46977e5b1ca3a91bafc952290c5b7f334f973e044a8e1b177c17cd97312df`.
- Construction: finish contact four from an observed BLE contact template, add identical contact five, append the scan-time/contact-count/button tail verified in the working pogo map, close the Application collection.

Repaired map:

- Length: 719 bytes.
- SHA-256: `6d8472b344592896718356859ad9896eed46fa0e7738e93616a026bdfc23085f`.
- Static validation: all HID items complete, collection depth zero, Report ID 6 exactly 192 bits/24 bytes.

This is a minimal functionally equivalent reconstruction. It is not a claim that the original firmware’s inaccessible post-512 bytes are byte-identical. Kernel UHID parser validation and physical input validation remain pending a temporary `/dev/uhid` ACL or a rebuilt daemon.


### Native Floss reconnect collision (patch 0002)

After descriptor repair testing, the installed native path still opened concurrent HoGP clients 43/45/46/48 and the generic Battery Service client. Logs showed successful connection followed by GATT_CONN_TIMEOUT status 8 and immediate reconnect. DisconnectAllEnabledProfiles stopped the loop only temporarily; BAS restarted when the bridge connected. This explains why the bridge worked during the first timing window and later stopped working after Floss restarted.

bluetooth-keyboard/patch/0002-FLOSS-Duet5-suppress-native-reconnect.patch is the smallest source-level companion: in system/bta/hh/bta_hh_le.cc it hashes the verified 512-byte Lenovo map and skips only that device native HoGP background reconnect; in floss/rust/linux/stack/src/lib.rs it skips BAS only when the cached bonded name is exactly Duet 5 KB. The patch applies to AOSP Bluetooth commit 85ccfbdb4f09b90bc1d7171ac77c979e9b299e2e; SHA-256 a95bec26ea05e07015296a8442b150be0e40a2043ae3b191acbfd558254d5a2d.

The live image has no compiler or headers, so neither patch was built into /usr/bin/btadapterd; this is an exact source fix and not a claim of deployed success. Build both patches together in the FydeOS SDK, replace only btadapterd, and run the full reconnect test before keeping it.

### Boot Protocol result

Protocol Mode characteristic handle 37 exists and reads `1` (Report Protocol). Boot Keyboard Input handle 41 reads a valid 8-byte value and Boot Mouse Input handle 46 reads a valid 4-byte value. However, the installed Floss HID D-Bus/CLI surface has no supported Set Protocol method. A generic GATT write would leave the HID profile’s notification registration/state machine inconsistent, so no unsupported write was forced. Boot Protocol is not the selected fix.

### Files created

All artifacts are under `bluetooth-keyboard/`:

- `README.md`
- `descriptor-comparison.txt`
- `install.sh`, `uninstall.sh`
- `descriptors/pogo/keyboard-report.bin` plus hex dump
- `descriptors/pogo/composite-touchpad-report.bin` plus hex dump
- `descriptors/ble/ble-report.bin` plus hex dump
- `descriptors/ble/lenovo-verified-residual.bin` plus hex dump
- `descriptors/ble/ble-report-repaired.bin` plus hex dump
- `patch/0001-FLOSS-HOGP-repair-Lenovo-Duet-5-KB-report-map.patch`
- exact upstream and patched source copies
- redacted GATT metadata/transcript and current Floss/kernel logs

No pairing key or authentication secret is stored. Raw feature-report data was deliberately discarded; the summary retains only report IDs/types and payload lengths. The remote privacy-random address was redacted from the Report Map transcript.

Backup before this HANDOFF update:

`HANDOFF.md.bluetooth-keyboard-bak-20260915T133432Z`, SHA-256 `be063935b6c3fd143cdb30a6f69649b5616e09a48f06390ac79b17de15b49b5e`.

### Build and deploy

The Live USB image has no compiler or development headers. In the FydeOS 23.0-SP1/ChromiumOS SDK at the exact commits above, apply the patch and rebuild only `net-wireless/floss-0.0.2-r8327` for `amd64-fydeos_iris`; the affected runtime artifact is `/usr/bin/btadapterd`, not the kernel. The package wrapper is normally:

```sh
emerge-amd64-fydeos_iris =net-wireless/floss-0.0.2-r8327
```

Run/build the existing host test target `bluetooth_hh_test`. The resulting daemon is normally staged at `/build/amd64-fydeos_iris/usr/bin/btadapterd`.

The Downloads/MyFiles mount is `noexec`; first copy the deployment scripts to the executable Live USB root (after reviewing them), then restore the root read-only:

```sh
sudo mount -o remount,rw /
sudo mkdir -p /usr/local/duet-bt-debug
sudo cp /home/chronos/user/MyFiles/Downloads/duet-fydeos-fixes/bluetooth-keyboard/install.sh /usr/local/duet-bt-debug/
sudo cp /home/chronos/user/MyFiles/Downloads/duet-fydeos-fixes/bluetooth-keyboard/uninstall.sh /usr/local/duet-bt-debug/
sudo chmod 0755 /usr/local/duet-bt-debug/install.sh /usr/local/duet-bt-debug/uninstall.sh
sudo mount -o remount,ro /
sudo /usr/local/duet-bt-debug/install.sh /path/to/patched/btadapterd
```

`install.sh` refuses NVMe/MMC-looking root devices, backs up the original daemon with permissions/ownership/timestamps and both hashes, stops/starts only Floss hci0, changes only `/usr/bin/btadapterd`, and restores the previous read-only root state.

### Rollback

A previous debug preload was cleaned up before the current runtime test. The current runtime test intentionally has the init bind mount and `/dev/uhid` chronos ACL active; use the rollback commands in the final runtime section to restore the original file hash `7bf7cea084ba5f0d4db67c1828211c67363c3cf7aa0260a5ef70d4f5b2d16e6a`.

```sh
sudo /usr/local/duet-bt-debug/uninstall.sh
```

This restores the recorded original `btadapterd` backup and restarts only Floss hci0. No interop file needs restoring because none was changed. Bluetooth controller power policy is currently and must remain:

```text
/sys/bus/usb/devices/1-10/power/control = auto
```

### Test status and required post-build test

Completed:

- direct 512-byte BLE Report Map capture and SHA-256
- exact offset-511 incomplete-item proof
- working pogo interface identification and descriptor capture
- direct Report Reference, Protocol Mode, boot report, and 24-byte touch-report reads
- source-version identification and config-only-quirk rejection
- repaired descriptor structural/size validation
- patch and guarded deployment/rollback packaging
- Wi-Fi not modified; Bluetooth controller power policy `auto`; auto-rotate daemon still running

Not completed and not claimed:

- source-patched `btadapterd` build/deployment
- three physical power-cycle reconnects
- final pogo/Wi-Fi/auto-rotate regression after a persistent fresh-install deployment

The runtime bridge typing/touchpad test and 10-minute stability test are completed as recorded in the final runtime section below.

After deployment, perform all success criteria from the task: confirm UHID readiness and input nodes, absence of `511/512`, `-22`, reconnect loop, and Floss crashes; type and test pointer/click/gestures; hold 10 minutes; repeat off/on reconnect three times; reattach pogo and verify keyboard/touchpad; verify Wi-Fi and auto-rotate.

### Running-kernel UHID validation result

On 2026-09-15, `diagnostics/uhid-parse-test.py` submitted the repaired 719-byte map to `/dev/uhid`. The running kernel created HID device `0005:0000:0000.013C`, bound `hid-multitouch`, and created four logical input devices: Keyboard, Consumer Control, System Control, and Touchpad. The repaired probe produced neither `item fetching failed at offset 511/512` nor probe error `-22`. The probe was destroyed after the test, and the temporary `chronos` ACL on `/dev/uhid` was removed. The exact log excerpt is stored in `bluetooth-keyboard/logs/uhid-repaired-parser-test.log`.

This proves the reconstructed descriptor fixes the kernel parser/UHID creation failure. It does not yet prove that real Bluetooth input reports or reconnect stability work; those require building and deploying the patched `btadapterd`.

### Fresh FydeOS installation

Do not reuse a binary built for a different FydeOS/Floss revision. On a fresh install, first compare the installed Report Map hash and source revision. If still `262ed0…fd0b` on Floss commit `85ccfb…`, build/apply this patch for that board and deploy with the backed-up script above. If either hash/revision differs, port the exact SHA-guarded repair to that source and revalidate before installation. Never add `0000:0000` globally, reuse the Brydge suffix, disable global USB autosuspend, replace Intel firmware, wipe all bonds, or patch the kernel HID parser.


## Bluetooth Keyboard Final — runtime result and fresh-install package

The original failure is now fixed in the running Live USB session by a reversible bridge fallback. The BLE Report Map remains a 512-byte truncated value whose final `09` starts an incomplete HID Usage item; that is why native unpatched Floss fails at offset 511/512. The bridge submits the verified 640-byte descriptor and forwards the live HOGP reports through UHID. Native Floss clients are prevented from competing during the bridge session by the runtime cleanup watchdog.

Verified on 2026-09-16:

- event13 `Duet 5 KB Bluetooth bridge Keyboard` received input; the user typed `DUET LIVE 123`.
- event24 `Duet 5 KB Bluetooth bridge Touchpad` received live input; event22/event23 controls also exist.
- Payload-free monitor counts: 1,656 bytes keyboard and 203,952 bytes touchpad.
- Ten-minute monitor completed with bridge alive and no new `GATT_CONN_TIMEOUT`, `item fetching failed at offset 511/512`, `probe error -22`, or `uhid_ready_disconn_timeout`.
- Current live runtime uses `/usr/local/duet-bt-debug/libduet5-uhid-preload.so`, `/usr/local/duet-bt-debug/libduet5-gatt-filter.so`, and the modified bridge script. The init bind mount is active and the `/dev/uhid` chronos ACL is present.
- This session has not yet exercised three physical off/on cycles or a fresh bond after reboot; do not represent those as completed.

### Which fix to use on a fresh FydeOS installation

Preferred: build and deploy `btadapterd` with patches 0001 and 0002 for the exact FydeOS 23.0-SP1 Floss revision. This is the durable fix. Fresh pairing should not reproduce the report-map defect because matching is by the complete 512-byte SHA-256, not by the privacy-random address; patch 0002 also removes the Duet-specific native HOGP/BAS client collision. If the installed Floss commit or Report Map hash differs, stop and port/revalidate the patch.

Fallback: run `install-live-bridge.sh` after a fresh boot. It installs the tested runtime bridge, the upstart job, the guarded init configuration, and the respawn/watchdog wrapper. It requires `DUET_ALLOW_INTERNAL_ROOT=YES` as an explicit operator confirmation because it writes the intended FydeOS root. It backs up `/etc/init/btadapterd.conf`, never wipes bonds, keeps USB Bluetooth power `auto`, and does not touch kernel, firmware, Wi-Fi, pogo fixes, or auto-rotate.

Commands, after copying this directory to the fresh FydeOS user storage and checking the root device:

```sh
cd /home/chronos/user/MyFiles/Downloads/duet-fydeos-fixes/bluetooth-keyboard
sudo env DUET_ALLOW_INTERNAL_ROOT=YES bash install-live-bridge.sh
```

For the source-patched daemon:

```sh
sudo env DUET_ALLOW_INTERNAL_ROOT=YES bash install-fydeos-floss.sh /path/to/patched/btadapterd
```

Rollback commands:

```sh
sudo env DUET_ALLOW_INTERNAL_ROOT=YES bash uninstall-live-bridge.sh
sudo env DUET_ALLOW_INTERNAL_ROOT=YES bash uninstall-fydeos-floss.sh
```

The installers require explicit confirmation and make timestamped backups. They are not run on this session's internal Windows/NVMe storage. The current Live USB runtime remains active until the user stops the bridge and restores the original init configuration.

### Auto-mode detach/reattach retest (2026-09-16)

The physical detach path was tested with `duet5-auto-mode.sh`. With the pogo keyboard attached, `/sys/bus/usb/devices/1-3:1.1` was present; after detaching it disappeared and the monitor correctly printed `switching to bt`. The bridge and Floss services restarted.

This did **not** pass the Bluetooth reconnect criterion: the bridge entered the same reconnect loop and its log recorded `btclient exited: -6` (Floss callback/GATT collision). The runtime GATT filter produced no block log, so this experiment is recorded as a partial convenience workaround, not a successful permanent fix. Reattaching the pogo keyboard remains supported, but stable Bluetooth off/on reconnect still requires the source-patched `btadapterd` (`0001` + `0002`).

