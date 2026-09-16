#!/bin/sh
set -eu
B=/usr/local/duet-bt-debug
LOG="$B/duet5-bridge.log"
IDS="43 45 46 48 50"
CLIENT_ID_FILE=/tmp/duet5-bridge-client-id

cleanup() {
  rm -f "$CLIENT_ID_FILE" /tmp/duet5-active-address
}
trap cleanup EXIT INT TERM

while :; do
  rm -f "$CLIENT_ID_FILE" /tmp/duet5-active-address
  /usr/bin/python3 -u "$B/bridge/duet5-hogp-bridge.py" >>"$LOG" 2>&1 &
  bridge=$!
  while kill -0 "$bridge" 2>/dev/null; do
    bridge_id=""
    if [ -f "$CLIENT_ID_FILE" ]; then
      bridge_id=$(cat "$CLIENT_ID_FILE" 2>/dev/null || true)
    fi

    # Wait for the bridge to publish a complete numeric client ID.  The bridge
    # writes this file atomically; without this guard the watchdog can race
    # registration and unregister the bridge's own Floss client.
    case "$bridge_id" in
      ''|*[!0-9]*)
        sleep 0.5
        continue
        ;;
    esac

    for id in $IDS; do
      # Do not unregister the bridge client ID; doing so causes btclient assertion failure (SIGABRT/-6)
      if [ -n "$bridge_id" ] && [ "$id" = "$bridge_id" ]; then
        continue
      fi
      gdbus call --system --dest org.chromium.bluetooth \
        --object-path /org/chromium/bluetooth/hci0/gatt \
        --method org.chromium.bluetooth.BluetoothGatt.UnregisterClient "$id" \
        >/dev/null 2>&1 || true
    done
    sleep 0.5
  done
  wait "$bridge" 2>/dev/null || true
  sleep 2
done
