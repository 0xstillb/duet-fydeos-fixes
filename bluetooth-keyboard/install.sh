#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo $0 /path/to/patched/btadapterd" >&2
  exit 1
fi
if [ "$#" -ne 1 ] || [ ! -f "$1" ] || [ ! -x "$1" ]; then
  echo "Usage: sudo $0 /path/to/patched/btadapterd" >&2
  exit 1
fi

new_binary=$(readlink -f "$1")
root_source=$(findmnt -no SOURCE /)
case "$root_source" in
  /dev/nvme*|/dev/mmcblk*)
    echo "Refusing to modify internal-looking root device: $root_source" >&2
    exit 1
    ;;
esac

state_dir=/usr/local/duet-bt-debug
stamp=$(date -u +%Y%m%dT%H%M%SZ)
backup="$state_dir/btadapterd.original-$stamp"
was_ro=0
case "$(findmnt -no OPTIONS /)" in *ro*) was_ro=1;; esac
restore_mount() { if [ "$was_ro" -eq 1 ]; then mount -o remount,ro /; fi; }
trap restore_mount EXIT INT TERM
if [ "$was_ro" -eq 1 ]; then mount -o remount,rw /; fi
mkdir -p "$state_dir"
cp --preserve=mode,ownership,timestamps /usr/bin/btadapterd "$backup"
{
  echo "root_source=$root_source"
  echo "backup=$backup"
  sha256sum /usr/bin/btadapterd "$new_binary"
  stat -c "%A %U:%G %a %s %n" /usr/bin/btadapterd "$new_binary"
} > "$state_dir/install-$stamp.txt"
printf "%s\n" "$backup" > "$state_dir/current-backup"

gdbus call --system --dest org.chromium.bluetooth.Manager \
  --object-path /org/chromium/bluetooth/Manager \
  --method org.chromium.bluetooth.Manager.Stop 0
install -o root -g root -m 0755 "$new_binary" /usr/bin/btadapterd
gdbus call --system --dest org.chromium.bluetooth.Manager \
  --object-path /org/chromium/bluetooth/Manager \
  --method org.chromium.bluetooth.Manager.Start 0
sha256sum /usr/bin/btadapterd

echo "Installed on Live USB root $root_source. Backup: $backup"
