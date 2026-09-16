#!/bin/sh
set -eu
[ "$(id -u)" -eq 0 ] || { echo "Run as root" >&2; exit 1; }
install -o root -g root -m 0755 duet-bt /usr/local/bin/duet-bt
install -o root -g root -m 0755 duet-pogo /usr/local/bin/duet-pogo
echo "Installed: sudo duet-bt   and   sudo duet-pogo"
