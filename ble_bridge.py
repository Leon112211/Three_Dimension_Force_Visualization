#!/usr/bin/env python3
# =========================================================================
# ble_bridge.py
# BLE -> stdout bridge for TDF_Visual.
#
# Processing cannot speak BLE reliably on Windows, so the sketch launches this
# script (like it already launches convert_data.py) and reads its stdout. The
# bridge connects to the ESP32 "TDF_Sensor" (Nordic UART Service), subscribes
# to the TX notify characteristic, and forwards each received frame verbatim:
#
#   stdout : data frames  ->  "x,y,z\n"   (parsed by SensorReceiver.parseCSVLine)
#   stderr : status/log   ->  human text  (shown on the sketch's BLE screen)
#
# Robustness mirrors PulseSensor_BLE/ble_read.py: match the device by name OR
# service UUID, reconnect with a fixed backoff, and exit cleanly on Ctrl+C /
# when the parent process closes the pipe.
#
# Requires:  pip install bleak
# The UUIDs / device name below MUST match BLE_Arduino/BLE_Arduino.ino.
# =========================================================================

import asyncio
import sys

try:
    from bleak import BleakClient, BleakScanner
except Exception as exc:  # bleak missing or broken install
    sys.stderr.write(
        "FATAL: could not import bleak (%s). Run: pip install bleak\n" % exc)
    sys.stderr.flush()
    sys.exit(2)

# ---- Shared BLE contract (keep in sync with BLE_Arduino.ino) -------------
DEVICE_NAME  = "TDF_Sensor"
SERVICE_UUID = "6e400001-b5a3-f393-e0a9-e50e24dcca9e"  # NUS service
TX_CHAR_UUID = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"  # device -> host (notify)

SCAN_TIMEOUT = 10.0   # seconds per discovery pass
RETRY_DELAY  = 2.0    # backoff before re-scanning / reconnecting


def log(msg):
    """Status line -> stderr (never mixed into the stdout data stream)."""
    sys.stderr.write(msg + "\n")
    sys.stderr.flush()


def _matches_target(device, adv):
    names = {n for n in (device.name, getattr(adv, "local_name", None)) if n}
    if DEVICE_NAME in names:
        return True
    uuids = {str(u).lower() for u in (adv.service_uuids or [])}
    return SERVICE_UUID in uuids


async def _find_device():
    found = await BleakScanner.discover(timeout=SCAN_TIMEOUT, return_adv=True)
    for device, adv in found.values():
        if _matches_target(device, adv):
            return device
    return None


def _on_notify(_characteristic, data):
    # Firmware streams ASCII "x,y,z\n"; forward verbatim. Processing reassembles
    # lines, so partial/coalesced packets are harmless.
    try:
        sys.stdout.write(bytes(data).decode("ascii", "ignore"))
        sys.stdout.flush()
    except (BrokenPipeError, ValueError):
        # Parent (Processing) closed the pipe -> time to stop.
        raise KeyboardInterrupt


async def run():
    # The WHOLE scan+connect body is wrapped: any error (adapter busy, scan
    # failure, connection drop, device powered off) only logs and retries — the
    # bridge must never exit, so the device can be hot-plugged / power-cycled and
    # it reconnects on its own.
    while True:
        try:
            log("Scanning for %s ..." % DEVICE_NAME)
            device = await _find_device()
            if device is None:
                log("Device not found, retrying in %.0fs" % RETRY_DELAY)
                await asyncio.sleep(RETRY_DELAY)
                continue

            log("Connecting to %s [%s]" % (device.name or "(no name)", device.address))
            async with BleakClient(device, timeout=20.0) as client:
                log("Connected")
                await client.start_notify(TX_CHAR_UUID, _on_notify)
                while client.is_connected:
                    await asyncio.sleep(0.5)
            log("Disconnected, retrying in %.0fs" % RETRY_DELAY)
        except KeyboardInterrupt:
            raise
        except Exception as exc:
            log("BLE error: %s: %s" % (type(exc).__name__, exc))
        await asyncio.sleep(RETRY_DELAY)


if __name__ == "__main__":
    try:
        asyncio.run(run())
    except KeyboardInterrupt:
        pass
