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

# Backup original btadapterd.conf
cp --preserve=mode,ownership,timestamps /etc/init/btadapterd.conf "$STATE/btadapterd.conf.original-$stamp"
printf '%s\n' "$STATE/btadapterd.conf.original-$stamp" > "$STATE/btadapterd.conf.current-backup"

# Stage bridge binaries, descriptors, and preload libraries
cp --preserve=mode,ownership,timestamps "$SRC/runtime/duet5-hogp-bridge.py" "$STATE/bridge/duet5-hogp-bridge.py"
chmod 0755 "$STATE/bridge/duet5-hogp-bridge.py"
cp --preserve=mode,ownership,timestamps "$SRC/descriptors/ble/ble-report-bridge.bin" "$STATE/descriptors/ble/ble-report-bridge.bin"
cp --preserve=mode,ownership,timestamps "$SRC/runtime/libduet5-uhid-preload.so" "$STATE/"
cp --preserve=mode,ownership,timestamps "$SRC/runtime/libduet5-gatt-filter-hotfix.so" "$STATE/"
if [ -f "$SRC/runtime/libduet5-gatt-filter.so" ]; then
  cp --preserve=mode,ownership,timestamps "$SRC/runtime/libduet5-gatt-filter.so" "$STATE/"
fi
chmod 0755 "$STATE"/*.so 2>/dev/null || true

cp --preserve=mode,ownership,timestamps "$SRC/run-duet5-bridge.sh" "$STATE/"
chmod 0755 "$STATE/run-duet5-bridge.sh"

# Configure btadapterd with LD_PRELOAD filter to prevent native GATT collision
cp --preserve=mode,ownership,timestamps /etc/init/btadapterd.conf "$STATE/btadapterd.conf.pre-install-$stamp"
if grep -q "libduet5-gatt-filter" /etc/init/btadapterd.conf; then
  sed -e 's|libduet5-gatt-filter\.so|libduet5-gatt-filter-hotfix.so|g' \
    /etc/init/btadapterd.conf > "$STATE/btadapterd.conf.duet-runtime-filter"
else
  awk '
    /^exec / && !done {
      print "env LD_PRELOAD=/usr/local/duet-bt-debug/libduet5-gatt-filter-hotfix.so"
      done=1
    }
    { print }
    END {
      if (!done) print "env LD_PRELOAD=/usr/local/duet-bt-debug/libduet5-gatt-filter-hotfix.so"
    }
  ' /etc/init/btadapterd.conf > "$STATE/btadapterd.conf.duet-runtime-filter"
fi
cp --preserve=mode,ownership,timestamps "$STATE/btadapterd.conf.duet-runtime-filter" /etc/init/btadapterd.conf

# Install Upstart bridge service
if [ -f /etc/init/duet5-hogp-bridge.conf ]; then
  bridge_backup="$STATE/duet5-hogp-bridge.conf.original-$stamp"
  cp --preserve=mode,ownership,timestamps /etc/init/duet5-hogp-bridge.conf "$bridge_backup"
  printf '%s\n' "$bridge_backup" > "$STATE/duet5-hogp-bridge.conf.current-backup"
else
  rm -f "$STATE/duet5-hogp-bridge.conf.current-backup"
fi
cp --preserve=mode,ownership,timestamps "$SRC/runtime/duet5-hogp-bridge.conf" /etc/init/duet5-hogp-bridge.conf

# Grant chronos access to UHID
setfacl -m u:chronos:rw /dev/uhid 2>/dev/null || true

/sbin/initctl reload-configuration
/sbin/stop duet5-hogp-bridge 2>/dev/null || true
/sbin/stop btmanagerd 2>/dev/null || true
sleep 3
/sbin/start btmanagerd
sleep 5
/sbin/start duet5-hogp-bridge 2>/dev/null || true
echo "Installed runtime bridge with RPA filter hotfix. Backup: $(cat "$STATE/btadapterd.conf.current-backup")"
