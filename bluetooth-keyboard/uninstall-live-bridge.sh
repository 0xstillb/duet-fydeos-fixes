#!/bin/sh
set -eu
if [ "$(id -u)" -ne 0 ]; then echo "Run as root" >&2; exit 1; fi
if [ "${DUET_ALLOW_INTERNAL_ROOT:-}" != YES ]; then echo "Set DUET_ALLOW_INTERNAL_ROOT=YES only on the intended FydeOS root" >&2; exit 1; fi
STATE=/usr/local/duet-bt-debug
backup=""
if [ -f "$STATE/btadapterd.conf.current-backup" ]; then
  backup=$(sed -n '1p' "$STATE/btadapterd.conf.current-backup" 2>/dev/null || true)
fi

was_ro=0
case "$(findmnt -no OPTIONS / 2>/dev/null || true)" in *ro*) was_ro=1;; esac
restore_mount() { [ "$was_ro" -eq 1 ] && mount -o remount,ro / || true; }
trap restore_mount EXIT INT TERM
[ "$was_ro" -eq 0 ] || mount -o remount,rw /

/sbin/stop duet5-hogp-bridge 2>/dev/null || true
rm -f /etc/init/duet5-hogp-bridge.conf
rm -f /tmp/duet5-bridge-client-id /tmp/duet5-active-address /tmp/duet5-gatt-filter.log

if [ -n "$backup" ] && [ -f "$backup" ]; then
  cp --preserve=mode,ownership,timestamps "$backup" /etc/init/btadapterd.conf
  echo "Restored $backup"
fi

setfacl -x u:chronos /dev/uhid 2>/dev/null || true
/sbin/initctl reload-configuration
/sbin/stop btmanagerd 2>/dev/null || true
sleep 3
/sbin/start btmanagerd 2>/dev/null || true
echo "Uninstalled live bridge and restored original configuration."
