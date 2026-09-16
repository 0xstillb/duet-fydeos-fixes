#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "Run with: /usr/bin/sudo bash $0 bt|pogo" >&2
  exit 1
fi

mode=${1:-}
case "$mode" in
  bt|pogo) ;;
  *) echo "Usage: sudo bash $0 bt|pogo" >&2; exit 2 ;;
esac

INITCTL=/sbin/initctl
log() { echo "[duet5-mode] $*"; }
stop_job() { "$INITCTL" stop "$1" >/dev/null 2>&1 || true; }

log "stopping Duet bridge and Floss manager"
stop_job duet5-hogp-bridge
stop_job btmanagerd
sleep 3

log "starting Floss manager"
"$INITCTL" start btmanagerd >/dev/null 2>&1 || true
sleep 5

if [ "$mode" = bt ]; then
  log "starting Duet Bluetooth bridge"
  "$INITCTL" start duet5-hogp-bridge >/dev/null 2>&1 || true
  sleep 3
  "$INITCTL" status duet5-hogp-bridge || true
  log "Bluetooth mode selected; now turn on the keyboard's Bluetooth mode"
else
  log "Pogo mode selected; bridge remains stopped"
fi

"$INITCTL" status btmanagerd || true
