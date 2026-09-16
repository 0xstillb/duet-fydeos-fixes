#!/usr/bin/env python3
"""FydeOS Floss GATT -> UHID compatibility bridge for Lenovo Duet 5 KB.

Uses the installed /usr/bin/btclient as the Floss D-Bus client. It does not
use BlueZ, alter bonds, change firmware, or modify the kernel.
"""
import argparse
import glob
import os
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import time
from pathlib import Path

UHID_DESTROY = 1
UHID_CREATE2 = 11
UHID_INPUT2 = 12
UHID_DATA_MAX = 4096
UHID_EVENT_SIZE = 4376
BUS_BLUETOOTH = 0x0005

ROOT = Path(__file__).resolve().parents[1]
DESCRIPTOR = ROOT / "descriptors/ble/ble-report-bridge.bin"
BTCLIENT = "/usr/bin/btclient"
DEVICE_NAME = "Duet 5 KB"

# GATT characteristic value handle -> HID Report ID.
INPUT_HANDLES = {49: 1, 57: 2, 61: 3, 65: 4, 76: 6}
EXPECTED_LENGTHS = {49: 11, 57: 6, 61: 3, 65: 1, 76: 20}

ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
DEVICE_RE = re.compile(r"\[([0-9A-Fa-f:]{17})\]\s+Duet 5 KB")
REGISTERED_RE = re.compile(r"GATT Client registered status = (\d+), client_id = (-?\d+)")
CONNECTION_RE = re.compile(
    r"GATT Client connection state = (\d+), client_id = (-?\d+), "
    r"connected = (true|false), addr = ([0-9A-Fa-f:]{17})"
)
NOTIFY_RE = re.compile(
    r"GATT Notification: addr = ([0-9A-Fa-f:]{17}), handle = (\d+), "
    r"value = \[([^]]*)\]"
)

def uhid_event(event_type, payload=b""):
    if len(payload) > UHID_EVENT_SIZE - 4:
        raise ValueError("UHID payload too large")
    return struct.pack("<I", event_type) + payload.ljust(UHID_EVENT_SIZE - 4, b"\0")

def create_uhid():
    descriptor = DESCRIPTOR.read_bytes()
    if len(descriptor) != 640:
        raise RuntimeError(f"unexpected repaired descriptor length: {len(descriptor)}")
    create = struct.pack(
        "<128s64s64sHHIIII4096s",
        b"Duet 5 KB Bluetooth bridge",
        b"duet-bt-bridge",
        b"privacy-address-redacted",
        len(descriptor),
        BUS_BLUETOOTH,
        0,
        0,
        0x0111,
        0,
        descriptor.ljust(UHID_DATA_MAX, b"\0"),
    )
    fd = os.open("/dev/uhid", os.O_RDWR | os.O_CLOEXEC | os.O_NONBLOCK)
    os.write(fd, uhid_event(UHID_CREATE2, create))
    return fd

def send_input(fd, report_id, value):
    data = bytes([report_id]) + value
    payload = struct.pack("<H4096s", len(data), data.ljust(UHID_DATA_MAX, b"\0"))
    os.write(fd, uhid_event(UHID_INPUT2, payload))

def find_created_hid():
    for path in glob.glob("/sys/bus/hid/devices/*/uevent"):
        try:
            text = Path(path).read_text(errors="replace")
        except OSError:
            continue
        if "Duet 5 KB Bluetooth bridge" in text:
            dev = str(Path(path).parent)
            driver_path = Path(dev) / "driver"
            driver = driver_path.resolve().name if driver_path.exists() else "none"
            return dev, driver
    return None, None

class BtClientPty:
    def __init__(self):
        master, slave = pty.openpty()
        self.master = master
        self.proc = subprocess.Popen(
            [BTCLIENT],
            stdin=slave,
            stdout=slave,
            stderr=slave,
            close_fds=True,
            start_new_session=True,
        )
        os.close(slave)
        os.set_blocking(master, False)
        self.buffer = ""

    def send(self, command):
        os.write(self.master, (command + "\n").encode())

    def lines(self):
        try:
            chunk = os.read(self.master, 65536)
        except BlockingIOError:
            return []
        if not chunk:
            return []
        text = ANSI_RE.sub("", chunk.decode("utf-8", "replace")).replace("\r", "")
        self.buffer += text
        parts = self.buffer.split("\n")
        self.buffer = parts.pop()
        return parts

    def close(self):
        try:
            self.send("quit")
            self.proc.wait(timeout=3)
        except Exception:
            try:
                os.killpg(self.proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        try:
            os.close(self.master)
        except OSError:
            pass

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--address", help="current bonded privacy address; normally auto-detected")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    if os.geteuid() != 0 and not os.access("/dev/uhid", os.R_OK | os.W_OK):
        raise SystemExit("run with sudo or grant temporary rw ACL on /dev/uhid")

    stopping = False
    def stop(_signum, _frame):
        nonlocal stopping
        stopping = True
    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)

    uhid_fd = create_uhid()
    client = BtClientPty()
    address = args.address.upper() if args.address else None
    addresses = [address] if address else []
    address_index = 0
    registered = False
    client_id = None
    connected = False
    notification_setup = False
    mode_set = False
    command_queue = []
    next_command_at = 0.0
    last_connect_try = 0.0
    stats = {handle: 0 for handle in INPUT_HANDLES}
    warned_lengths = set()

    def queue(command):
        command_queue.append(command)

    try:
        print("UHID descriptor submitted (640 bytes); starting Floss GATT client", flush=True)
        time.sleep(2)
        dev, driver = find_created_hid()
        if not dev or driver != "hid-multitouch":
            raise RuntimeError(f"UHID device did not bind to hid-multitouch: device={dev} driver={driver}")
        print("UHID ready: keyboard and touchpad interfaces created", flush=True)

        if address:
            queue("gatt register-client")
        else:
            queue("list bonded")

        while not stopping:
            now = time.monotonic()
            reads = [client.master, uhid_fd]
            ready, _, _ = select.select(reads, [], [], 0.2)

            if client.master in ready:
                for line in client.lines():
                    if args.verbose and "GATT Notification:" not in line:
                        print("btclient:", line, flush=True)

                    match = DEVICE_RE.search(line)
                    if match:
                        candidate = match.group(1).upper()
                        if candidate not in addresses:
                            addresses.append(candidate)
                        if not address:
                            address = candidate
                            print("Found bonded Duet 5 KB (privacy address withheld)", flush=True)
                            queue("gatt register-client")

                    match = REGISTERED_RE.search(line)
                    if match:
                        status, registered_client_id = int(match.group(1)), int(match.group(2))
                        if status != 0:
                            raise RuntimeError(f"GATT client registration failed: {status}")
                        if not registered:
                            registered = True
                            client_id = registered_client_id
                            print(f"Floss GATT client registered: id={client_id}", flush=True)
                            queue("gatt set-connect-transport LE")
                            queue("gatt set-auth-req EncNoMitm")
                            queue("gatt set-direct-connect true")
                            if address:
                                queue(f"gatt client-connect {address}")
                                last_connect_try = time.monotonic()

                    match = CONNECTION_RE.search(line)
                    callback_address = match.group(4).upper() if match else None
                    if match and callback_address in addresses:
                        status = int(match.group(1))
                        callback_connected = match.group(3) == "true" and status == 0
                        if callback_connected:
                            address = callback_address
                            address_index = addresses.index(address)
                            connected = True
                            print("Floss GATT connection active", flush=True)
                            notification_setup = False
                            mode_set = False
                        elif callback_address == address:
                            connected = False
                            address_index = (address_index + 1) % len(addresses)
                            address = addresses[address_index]
                        if not callback_connected and args.verbose:
                            print(f"Floss GATT disconnected: status={status}", flush=True)

                    match = NOTIFY_RE.search(line)
                    if match and address and match.group(1).upper() == address:
                        handle = int(match.group(2))
                        if handle not in INPUT_HANDLES:
                            continue
                        raw = match.group(3).strip()
                        try:
                            value = bytes(int(item.strip()) for item in raw.split(",") if item.strip())
                        except ValueError:
                            print(f"ignored malformed notification on handle {handle}", file=sys.stderr)
                            continue
                        expected = EXPECTED_LENGTHS.get(handle)
                        if expected is not None and len(value) != expected and (handle, len(value)) not in warned_lengths:
                            warned_lengths.add((handle, len(value)))
                            print(
                                f"warning: handle {handle} report length {len(value)}, expected {expected}; forwarding",
                                file=sys.stderr,
                                flush=True,
                            )
                        send_input(uhid_fd, INPUT_HANDLES[handle], value)
                        stats[handle] += 1
                        if stats[handle] == 1:
                            print(
                                f"first live report: HID id={INPUT_HANDLES[handle]} "
                                f"length={len(value)} bytes",
                                flush=True,
                            )

            if uhid_fd in ready:
                try:
                    os.read(uhid_fd, UHID_EVENT_SIZE)
                except BlockingIOError:
                    pass

            if connected and not notification_setup and not command_queue:
                for handle in INPUT_HANDLES:
                    queue(f"gatt register-notification {address} {handle} enable")
                notification_setup = True

            if connected and notification_setup and not command_queue and not mode_set:
                mode_result = subprocess.run(
                    [
                        "gdbus", "call", "--system",
                        "--dest", "org.chromium.bluetooth",
                        "--object-path", "/org/chromium/bluetooth/hci0/gatt",
                        "--method", "org.chromium.bluetooth.BluetoothGatt.WriteCharacteristic",
                        str(client_id), address, "86", "2", "0", "[byte 0x03]",
                    ],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.PIPE,
                    text=True,
                )
                if mode_result.returncode != 0:
                    raise RuntimeError("failed to set Precision Touchpad Input Mode: " + mode_result.stderr.strip())
                mode_set = True
                print("Precision Touchpad Input Mode 3 requested", flush=True)

            if registered and addresses and not connected and not command_queue and now - last_connect_try > 6:
                address_index = (address_index + 1) % len(addresses)
                address = addresses[address_index]
                queue(f"gatt client-connect {address}")
                last_connect_try = now

            if command_queue and now >= next_command_at:
                client.send(command_queue.pop(0))
                next_command_at = now + 0.8

            if client.proc.poll() is not None:
                raise RuntimeError(f"btclient exited: {client.proc.returncode}")

        print("Stopping bridge", flush=True)
    finally:
        if address and registered:
            try:
                client.send(f"gatt client-disconnect {address}")
                time.sleep(0.5)
            except Exception:
                pass
        client.close()
        try:
            os.write(uhid_fd, uhid_event(UHID_DESTROY))
        except OSError:
            pass
        os.close(uhid_fd)
        print("Report counts:", {INPUT_HANDLES[h]: n for h, n in stats.items()}, flush=True)

if __name__ == "__main__":
    main()
