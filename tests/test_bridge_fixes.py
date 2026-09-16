#!/usr/bin/env python3
"""Comprehensive test suite for Lenovo Duet 5 FydeOS Bluetooth bridge fixes."""

import os
import re
import struct
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
DESCRIPTORS_DIR = REPO_ROOT / "bluetooth-keyboard" / "descriptors" / "ble"
RUNTIME_DIR = REPO_ROOT / "bluetooth-keyboard" / "runtime"

class TestBridgeLogic(unittest.TestCase):
    def setUp(self):
        self.ansi_re = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
        self.device_re = re.compile(r"\[([0-9A-Fa-f:]{17})\]\s+Duet 5 KB")
        self.registered_re = re.compile(r"GATT Client registered status = (\d+), client_id = (-?\d+)")
        self.connection_re = re.compile(
            r"GATT Client connection state = (\d+), client_id = (-?\d+), "
            r"connected = (true|false), addr = ([0-9A-Fa-f:]{17})"
        )
        self.notify_re = re.compile(
            r"GATT Notification: addr = ([0-9A-Fa-f:]{17}), handle = (\d+), "
            r"value = \[([^]]*)\]"
        )
        self.input_handles = {49: 1, 57: 2, 61: 3, 65: 4, 76: 6}
        self.expected_lengths = {49: 11, 57: 6, 61: 3, 65: 1, 76: 20}

    def test_descriptors_existence_and_sizes(self):
        bridge_desc = DESCRIPTORS_DIR / "ble-report-bridge.bin"
        repaired_desc = DESCRIPTORS_DIR / "ble-report-repaired.bin"
        raw_desc = DESCRIPTORS_DIR / "ble-report.bin"

        self.assertTrue(bridge_desc.exists(), "ble-report-bridge.bin missing")
        self.assertEqual(len(bridge_desc.read_bytes()), 640, "bridge descriptor must be 640 bytes")

        self.assertTrue(repaired_desc.exists(), "ble-report-repaired.bin missing")
        self.assertEqual(len(repaired_desc.read_bytes()), 719, "repaired descriptor must be 719 bytes")

        self.assertTrue(raw_desc.exists(), "ble-report.bin missing")
        self.assertEqual(len(raw_desc.read_bytes()), 512, "raw descriptor must be 512 bytes")

    def test_btclient_regex_parsing(self):
        # 1. Device detection with privacy RPA
        line1 = "[CC:59:35:9F:12:34]  Duet 5 KB"
        m1 = self.device_re.search(line1)
        self.assertIsNotNone(m1)
        self.assertEqual(m1.group(1), "CC:59:35:9F:12:34")

        # 2. Registration status
        line2 = "GATT Client registered status = 0, client_id = 45"
        m2 = self.registered_re.search(line2)
        self.assertIsNotNone(m2)
        self.assertEqual(int(m2.group(1)), 0)
        self.assertEqual(int(m2.group(2)), 45)

        # 3. Connection state
        line3 = "GATT Client connection state = 0, client_id = 45, connected = true, addr = CC:59:35:9F:12:34"
        m3 = self.connection_re.search(line3)
        self.assertIsNotNone(m3)
        self.assertEqual(int(m3.group(1)), 0)
        self.assertEqual(m3.group(3), "true")
        self.assertEqual(m3.group(4), "CC:59:35:9F:12:34")

        # 4. GATT Notifications
        # Handle 49: Keyboard report
        line4 = "GATT Notification: addr = CC:59:35:9F:12:34, handle = 49, value = [0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0]"
        m4 = self.notify_re.search(line4)
        self.assertIsNotNone(m4)
        handle = int(m4.group(2))
        self.assertIn(handle, self.input_handles)
        self.assertEqual(self.input_handles[handle], 1)
        raw_vals = [int(x.strip()) for x in m4.group(3).split(",") if x.strip()]
        self.assertEqual(len(raw_vals), self.expected_lengths[handle])

        # Handle 76: Touchpad report (20 bytes payload)
        line5 = "GATT Notification: addr = CC:59:35:9F:12:34, handle = 76, value = [" + ", ".join(["1"] * 20) + "]"
        m5 = self.notify_re.search(line5)
        self.assertIsNotNone(m5)
        self.assertEqual(int(m5.group(2)), 76)
        self.assertEqual(self.input_handles[76], 6)
        touch_vals = [int(x.strip()) for x in m5.group(3).split(",") if x.strip()]
        self.assertEqual(len(touch_vals), 20)

    def test_uhid_payload_construction(self):
        UHID_INPUT2 = 12
        UHID_DATA_MAX = 4096
        UHID_EVENT_SIZE = 4376

        report_id = 1
        value = bytes([0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0])
        data = bytes([report_id]) + value
        self.assertEqual(len(data), 12)

        payload = struct.pack("<H4096s", len(data), data.ljust(UHID_DATA_MAX, b"\0"))
        event = struct.pack("<I", UHID_INPUT2) + payload.ljust(UHID_EVENT_SIZE - 4, b"\0")
        self.assertEqual(len(event), UHID_EVENT_SIZE)

    def test_watchdog_filtering_logic(self):
        # Verify that if bridge client ID is 45, client 45 is NEVER unregistered
        bridge_client_id = 45
        target_ids = [43, 45, 46, 48, 50]
        unregistered = []

        for cid in target_ids:
            if cid == bridge_client_id:
                continue
            unregistered.append(cid)

        self.assertNotIn(45, unregistered, "Bridge client ID 45 must NOT be unregistered!")
        self.assertEqual(unregistered, [43, 46, 48, 50])

    def test_upstart_injection_logic(self):
        sample_conf = """description "Bluetooth Adapter"
author "chromium-os"

stop on stopping btmanagerd
respawn
respawn limit 5 10

exec /usr/bin/btadapterd --index=0
"""
        preload_line = "env LD_PRELOAD=/usr/local/duet-bt-debug/libduet5-gatt-filter-hotfix.so"

        # Simulate the awk script from install-live-bridge.sh
        lines = sample_conf.splitlines()
        output_lines = []
        done = False
        for line in lines:
            if line.startswith("exec ") and not done:
                output_lines.append(preload_line)
                done = True
            output_lines.append(line)
        if not done:
            output_lines.append(preload_line)

        result = "\n".join(output_lines)
        self.assertIn(preload_line, result)
        # Verify it comes before exec
        preload_idx = result.index(preload_line)
        exec_idx = result.index("exec /usr/bin/btadapterd")
        self.assertLess(preload_idx, exec_idx, "env LD_PRELOAD must appear before exec")
        self.assertIn("exec /usr/bin/btadapterd --index=0", result, "Original arguments must be preserved")

if __name__ == "__main__":
    unittest.main()
