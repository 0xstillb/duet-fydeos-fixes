#!/bin/sh
set -eu
if [ "$(id -u)" -ne 0 ]; then echo "Run as root" >&2; exit 1; fi
if [ "${DUET_ALLOW_INTERNAL_ROOT:-}" != YES ]; then
  root_source=$(findmnt -no SOURCE / 2>/dev/null || echo unknown)
  echo "Refusing to modify root ($root_source). For an intentional fresh FydeOS install only, rerun with DUET_ALLOW_INTERNAL_ROOT=YES." >&2
  exit 1
fi
SRC=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
STATE=/usr/local/duet-bt-debug
stamp=$(date -u +%Y%m%dT%H%M%SZ)
was_ro=0
case "$(findmnt -no OPTIONS / 2>/dev/null || true)" in *ro*) was_ro=1;; esac
restore_mount() { [ "$was_ro" -eq 1 ] && mount -o remount,ro / || true; }
trap restore_mount EXIT INT TERM
[ "$was_ro" -eq 0 ] || mount -o remount,rw /
mkdir -p "$STATE/bridge" "$STATE/descriptors/ble"
[ -f /etc/init/btadapterd.conf ] || { echo "missing /etc/init/btadapterd.conf" >&2; exit 1; }
cp --preserve=mode,ownership,timestamps /etc/init/btadapterd.conf "$STATE/btadapterd.conf.original-$stamp"
printf '%s\n' "$STATE/btadapterd.conf.original-$stamp" > "$STATE/btadapterd.conf.current-backup"
cp --preserve=mode,ownership,timestamps "$SRC/runtime/duet5-hogp-bridge.py" "$STATE/bridge/duet5-hogp-bridge.py"
cp --preserve=mode,ownership,timestamps "$SRC/descriptors/ble/ble-report-bridge.bin" "$STATE/descriptors/ble/ble-report-bridge.bin"
cp --preserve=mode,ownership,timestamps "$SRC/runtime/libduet5-uhid-preload.so" "$STATE/"
cp --preserve=mode,ownership,timestamps "$SRC/runtime/libduet5-gatt-filter.so" "$STATE/"
cp --preserve=mode,ownership,timestamps "$SRC/runtime/btadapterd.conf.duet-runtime-filter" "$STATE/"
cp --preserve=mode,ownership,timestamps "$SRC/run-duet5-bridge.sh" "$STATE/"
chmod 0755 "$STATE/run-duet5-bridge.sh"
cp --preserve=mode,ownership,timestamps /etc/init/btadapterd.conf "$STATE/btadapterd.conf.pre-install-$stamp"
cp --preserve=mode,ownership,timestamps "$SRC/runtime/btadapterd.conf.duet-runtime-filter" /etc/init/btadapterd.conf
if [ -f /etc/init/duet5-hogp-bridge.conf ]; then cp --preserve=mode,ownership,timestamps /etc/init/duet5-hogp-bridge.conf "$STATE/duet5-hogp-bridge.conf.original-$stamp"; fi
cp --preserve=mode,ownership,timestamps "$SRC/runtime/duet5-hogp-bridge.conf" /etc/init/duet5-hogp-bridge.conf
setfacl -m u:chronos:rw /dev/uhid
/sbin/initctl reload-configuration
/sbin/stop btmanagerd || true
sleep 3
/sbin/start btmanagerd
sleep 5
/sbin/start duet5-hogp-bridge || true
echo "Installed runtime bridge. Backup: $(cat "$STATE/btadapterd.conf.current-backup")"
