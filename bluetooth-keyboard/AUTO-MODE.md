# Automatic pogo/Bluetooth mode switching

`duet5-auto-mode.sh` watches the known physical pogo touchpad interface
`/sys/bus/usb/devices/1-3:1.1`.

- interface present: stop the Bluetooth bridge and use pogo mode
- interface absent: restart Floss and start the Bluetooth bridge

Run it from a terminal (Downloads is normally `noexec`):

```sh
cd /home/chronos/user/MyFiles/Downloads/duet-fydeos-fixes/bluetooth-keyboard
/usr/bin/sudo bash duet5-auto-mode.sh
```

Leave that terminal/process running. Stop it with `Ctrl-C`. This is a
convenience workaround only; it does not replace the patched `btadapterd`
needed to eliminate the native Floss HoGP/BAS reconnect collision.

### Auto-mode detach/reattach retest (2026-09-16)

The physical detach path was tested with `duet5-auto-mode.sh`. With the pogo keyboard attached, `/sys/bus/usb/devices/1-3:1.1` was present; after detaching it disappeared and the monitor correctly printed `switching to bt`. The bridge and Floss services restarted.

This did **not** pass the Bluetooth reconnect criterion: the bridge entered the same reconnect loop and its log recorded `btclient exited: -6` (Floss callback/GATT collision). The runtime GATT filter produced no block log, so this experiment is recorded as a partial convenience workaround, not a successful permanent fix. Reattaching the pogo keyboard remains supported, but stable Bluetooth off/on reconnect still requires the source-patched `btadapterd` (`0001` + `0002`).

