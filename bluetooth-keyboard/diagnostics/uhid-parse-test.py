#!/usr/bin/env python3
# Create a temporary UHID device from the repaired descriptor, then destroy it.
import glob
import os
import struct
import time
from pathlib import Path

UHID_CREATE2 = 11
UHID_DESTROY = 1
UHID_DATA_MAX = 4096
EVENT_SIZE = 4376
DESCRIPTOR = Path(__file__).resolve().parents[1] / "descriptors/ble/ble-report-repaired.bin"

def event(event_type, payload=b""):
    if len(payload) > EVENT_SIZE - 4:
        raise ValueError("UHID payload too large")
    return struct.pack("<I", event_type) + payload.ljust(EVENT_SIZE - 4, b"\0")

report = DESCRIPTOR.read_bytes()
if len(report) != 719:
    raise SystemExit(f"unexpected descriptor size: {len(report)}")
create = struct.pack(
    "<128s64s64sHHIIII4096s",
    b"Duet 5 KB repaired parser probe",
    b"duet-bt-debug",
    b"no-device-address",
    len(report),
    0x0005,
    0,
    0,
    0x0111,
    0,
    report.ljust(UHID_DATA_MAX, b"\0"),
)
if len(create) != EVENT_SIZE - 4:
    raise SystemExit(f"unexpected UHID_CREATE2 layout: {len(create)}")

fd = os.open("/dev/uhid", os.O_RDWR | os.O_CLOEXEC | os.O_NONBLOCK)
try:
    written = os.write(fd, event(UHID_CREATE2, create))
    print(f"UHID_CREATE2 bytes written: {written}")
    time.sleep(3)
    found = []
    for path in glob.glob("/sys/bus/hid/devices/*/uevent"):
        value = Path(path).read_text(errors="replace")
        if "Duet 5 KB repaired parser probe" in value:
            found.append(str(Path(path).parent))
    print("created HID devices:", found)
    if not found:
        raise SystemExit(2)
    for dev in found:
        rd = Path(dev) / "report_descriptor"
        driver_path = Path(dev) / "driver"
        driver = driver_path.resolve().name if driver_path.exists() else "none"
        print(f"{dev}: driver={driver} report_descriptor={len(rd.read_bytes())} bytes")
    time.sleep(2)
finally:
    try:
        os.write(fd, event(UHID_DESTROY))
    finally:
        os.close(fd)
