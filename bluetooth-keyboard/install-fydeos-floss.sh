#!/bin/sh
set -eu
if [ "$(id -u)" -ne 0 ]; then echo "Run as root" >&2; exit 1; fi
if [ "${DUET_ALLOW_INTERNAL_ROOT:-}" != YES ]; then
  echo "Refusing to replace btadapterd. On the intended fresh FydeOS root only, rerun with DUET_ALLOW_INTERNAL_ROOT=YES." >&2
  exit 1
fi
[ "$#" -eq 1 ] && [ -x "$1" ] || { echo "Usage: DUET_ALLOW_INTERNAL_ROOT=YES sudo $0 /path/to/patched/btadapterd" >&2; exit 1; }
new=$(readlink -f "$1"); state=/usr/local/duet-bt-debug; stamp=$(date -u +%Y%m%dT%H%M%SZ)
was_ro=0; case "$(findmnt -no OPTIONS / 2>/dev/null || true)" in *ro*) was_ro=1;; esac
restore() { [ "$was_ro" -eq 1 ] && mount -o remount,ro / || true; }; trap restore EXIT INT TERM
[ "$was_ro" -eq 0 ] || mount -o remount,rw /
mkdir -p "$state"
backup="$state/btadapterd.original-$stamp"
cp --preserve=mode,ownership,timestamps /usr/bin/btadapterd "$backup"
printf '%s\n' "$backup" > "$state/current-btadapterd-backup"
sha256sum /usr/bin/btadapterd "$new" > "$state/install-btadapterd-$stamp.sha256"
/sbin/stop btmanagerd || true
install -o root -g root -m 0755 "$new" /usr/bin/btadapterd
/sbin/start btmanagerd
sha256sum /usr/bin/btadapterd
