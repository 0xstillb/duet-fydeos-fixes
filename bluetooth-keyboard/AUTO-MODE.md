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
