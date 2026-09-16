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

Leave that terminal/process running. Stop it with `Ctrl-C`.

### Loop Fix & RPA Filter Hotfix Update

The reconnect loop previously observed during detach/reattach was caused by two issues:
1. `run-duet5-bridge.sh` blindly called `UnregisterClient` on client IDs 43, 45, 46, 48, 50 without checking if `btclient` (the bridge itself) was assigned one of those IDs by Floss, causing an assertion failure and `SIGABRT` (`btclient exited: -6`).
2. `install-live-bridge.sh` failed to configure `LD_PRELOAD` in `/etc/init/btadapterd.conf` because the template file was missing, and it did not install `libduet5-gatt-filter-hotfix.so` to handle RPA (Resolvable Private Address).

With the updated runtime fix:
- `libduet5-gatt-filter-hotfix.so` is preloaded via `/etc/init/btadapterd.conf` to block competing native Floss clients from opening connections to the Duet 5 KB.
- `run-duet5-bridge.sh` checks `/tmp/duet5-bridge-client-id` and explicitly skips unregistering the bridge's own client ID.
- The active Bluetooth address is recorded in `/tmp/duet5-active-address`.
