#!/bin/sh
set -eu

[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo bash $0" >&2; exit 1; }

INITCTL=/sbin/initctl
POGO_IF=/sys/bus/usb/devices/1-3:1.1
last=""

set_mode() {
  mode=$1
  [ "$mode" = "$last" ] && return 0
  echo "[duet5-auto] switching to $mode"

  "$INITCTL" stop duet5-hogp-bridge >/dev/null 2>&1 || true
  "$INITCTL" stop btmanagerd >/dev/null 2>&1 || true
  sleep 3
  "$INITCTL" start btmanagerd >/dev/null 2>&1 || true
  sleep 5

  if [ "$mode" = bt ]; then
    "$INITCTL" start duet5-hogp-bridge >/dev/null 2>&1 || true
  else
    # btmanagerd startup may auto-start the bridge job; ensure pogo mode wins.
    "$INITCTL" stop duet5-hogp-bridge >/dev/null 2>&1 || true
  fi
  last=$mode
}

while :; do
  if [ -e "$POGO_IF" ]; then
    set_mode pogo
  else
    set_mode bt
  fi
  sleep 2
done
