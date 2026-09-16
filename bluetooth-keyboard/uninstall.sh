#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi
state_dir=/usr/local/duet-bt-debug
if [ ! -r "$state_dir/current-backup" ]; then
  echo "No recorded btadapterd backup at $state_dir/current-backup" >&2
  exit 1
fi
backup=$(sed -n "1p" "$state_dir/current-backup")
case "$backup" in "$state_dir"/btadapterd.original-*) ;; *) echo "Invalid backup path" >&2; exit 1;; esac
if [ ! -f "$backup" ]; then echo "Backup missing: $backup" >&2; exit 1; fi

root_source=$(findmnt -no SOURCE /)
case "$root_source" in /dev/nvme*|/dev/mmcblk*) echo "Refusing internal-looking root: $root_source" >&2; exit 1;; esac
was_ro=0
case "$(findmnt -no OPTIONS /)" in *ro*) was_ro=1;; esac
restore_mount() { if [ "$was_ro" -eq 1 ]; then mount -o remount,ro /; fi; }
trap restore_mount EXIT INT TERM
if [ "$was_ro" -eq 1 ]; then mount -o remount,rw /; fi

gdbus call --system --dest org.chromium.bluetooth.Manager \
  --object-path /org/chromium/bluetooth/Manager \
  --method org.chromium.bluetooth.Manager.Stop 0
cp --preserve=mode,ownership,timestamps "$backup" /usr/bin/btadapterd
gdbus call --system --dest org.chromium.bluetooth.Manager \
  --object-path /org/chromium/bluetooth/Manager \
  --method org.chromium.bluetooth.Manager.Start 0
sha256sum /usr/bin/btadapterd

echo "Restored $backup"
