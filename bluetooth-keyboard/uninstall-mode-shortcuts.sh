#!/bin/sh
set -eu
[ "$(id -u)" -eq 0 ] || { echo "Run as root" >&2; exit 1; }
rm -f /usr/local/bin/duet-bt /usr/local/bin/duet-pogo
echo "Removed mode shortcuts"
