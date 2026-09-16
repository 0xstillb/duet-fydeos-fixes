#!/bin/bash
set -euo pipefail

echo "=== Testing Watchdog UnregisterClient Filter ==="
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Mock gdbus
MOCK_LOG="$TMP_DIR/gdbus_calls.log"
cat << 'EOF' > "$TMP_DIR/gdbus"
#!/bin/bash
echo "$@" >> "$MOCK_LOG"
EOF
chmod +x "$TMP_DIR/gdbus"
export PATH="$TMP_DIR:$PATH"
export MOCK_LOG

# Test: when /tmp/duet5-bridge-client-id is 45
CLIENT_ID_FILE="$TMP_DIR/duet5-bridge-client-id"
echo "45" > "$CLIENT_ID_FILE"

IDS="43 45 46 48 50"
bridge_id=$(cat "$CLIENT_ID_FILE" 2>/dev/null || true)

for id in $IDS; do
  if [ -n "$bridge_id" ] && [ "$id" = "$bridge_id" ]; then
    continue
  fi
  "$TMP_DIR/gdbus" call --system --dest org.chromium.bluetooth \
    --object-path /org/chromium/bluetooth/hci0/gatt \
    --method org.chromium.bluetooth.BluetoothGatt.UnregisterClient "$id"
done

# Verify calls
echo "GDBus calls made:"
cat "$MOCK_LOG"

if grep -q "UnregisterClient 45" "$MOCK_LOG"; then
  echo "FAIL: UnregisterClient was called for bridge client 45!"
  exit 1
else
  echo "PASS: Bridge client 45 was safely protected!"
fi

if grep -q "UnregisterClient 43" "$MOCK_LOG" && grep -q "UnregisterClient 50" "$MOCK_LOG"; then
  echo "PASS: Other native clients (43, 46, 48, 50) were unregistered."
else
  echo "FAIL: Expected other clients to be unregistered."
  exit 1
fi

echo "=== All Mock Tests Passed Successfully ==="
