#!/bin/sh
set -eu
if [ "$(id -u)" -ne 0 ]; then echo "Run as root" >&2; exit 1; fi
if [ "${DUET_ALLOW_INTERNAL_ROOT:-}" != YES ]; then echo "Set DUET_ALLOW_INTERNAL_ROOT=YES only on the intended FydeOS root" >&2; exit 1; fi
STATE=/usr/local/duet-bt-debug
backup=$(sed -n '1p' "$STATE/btadapterd.conf.current-backup")
[ -f "$backup" ] || { echo "missing backup: $backup" >&2; exit 1; }
was_ro=0
case "$(findmnt -no OPTIONS / 2>/dev/null || true)" in *ro*) was_ro=1;; esac
restore_mount() { [ "$was_ro" -eq 1 ] && mount -o remount,ro / || true; }
trap restore_mount EXIT INT TERM
[ "$was_ro" -eq 0 ] || mount -o remount,rw /
/sbin/stop duet5-hogp-bridge || true
rm -f /etc/init/duet5-hogp-bridge.conf
cp --preserve=mode,ownership,timestamps "$backup" /etc/init/btadapterd.conf
setfacl -x u:chronos /dev/uhid || true
/sbin/initctl reload-configuration
/sbin/stop btmanagerd || true
sleep 3
/sbin/start btmanagerd
echo "Restored $backup"
