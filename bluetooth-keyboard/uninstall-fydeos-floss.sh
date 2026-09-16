#!/bin/sh
set -eu
if [ "$(id -u)" -ne 0 ]; then echo "Run as root" >&2; exit 1; fi
if [ "${DUET_ALLOW_INTERNAL_ROOT:-}" != YES ]; then echo "Set DUET_ALLOW_INTERNAL_ROOT=YES only on the intended FydeOS root" >&2; exit 1; fi
state=/usr/local/duet-bt-debug; backup=$(sed -n '1p' "$state/current-btadapterd-backup")
[ -f "$backup" ] || { echo "Missing backup" >&2; exit 1; }
was_ro=0; case "$(findmnt -no OPTIONS / 2>/dev/null || true)" in *ro*) was_ro=1;; esac
restore() { [ "$was_ro" -eq 1 ] && mount -o remount,ro / || true; }; trap restore EXIT INT TERM
[ "$was_ro" -eq 0 ] || mount -o remount,rw /
/sbin/stop btmanagerd || true
cp --preserve=mode,ownership,timestamps "$backup" /usr/bin/btadapterd
/sbin/start btmanagerd
sha256sum /usr/bin/btadapterd
echo "Restored $backup"
