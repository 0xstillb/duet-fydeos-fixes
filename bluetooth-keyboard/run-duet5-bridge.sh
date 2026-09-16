#!/bin/sh
set -eu
B=/usr/local/duet-bt-debug
LOG="$B/duet5-bridge.log"
IDS="43 45 46 48 50"
cleanup() { rm -f /tmp/duet5-bridge-client-id; }
trap cleanup EXIT INT TERM
while :; do
  rm -f /tmp/duet5-bridge-client-id
  /usr/bin/python3 -u "$B/bridge/duet5-hogp-bridge.py" >>"$LOG" 2>&1 &
  bridge=$!
  while kill -0 "$bridge" 2>/dev/null; do
    for id in $IDS; do
      gdbus call --system --dest org.chromium.bluetooth \
        --object-path /org/chromium/bluetooth/hci0/gatt \
        --method org.chromium.bluetooth.BluetoothGatt.UnregisterClient "$id" \
        >/dev/null 2>&1 || true
    done
    sleep 0.25
  done
  wait "$bridge" 2>/dev/null || true
  sleep 2
done
