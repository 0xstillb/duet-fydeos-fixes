# Duet keyboard mode switch (runtime workaround)

This is a best-effort convenience script for the current Live/FydeOS runtime. It restarts only Floss and the Duet bridge before changing physical keyboard mode; it does not erase bonds or change USB power policy.

Because Downloads/MyFiles is normally `noexec`, invoke it through `bash`:

```sh
cd /home/chronos/user/MyFiles/Downloads/duet-fydeos-fixes/bluetooth-keyboard
/usr/bin/sudo bash duet5-mode.sh bt
```

Then turn the detached keyboard on in Bluetooth mode. For the physical pogo keyboard:

```sh
/usr/bin/sudo bash duet5-mode.sh pogo
```

This does not replace the source-level patched `btadapterd`; native Floss reconnect collision can still cause a loop. If that happens, collect `/usr/local/duet-bt-debug/duet5-bridge.log` and use the patched-daemon path.
