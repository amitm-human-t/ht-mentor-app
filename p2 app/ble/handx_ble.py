# flake8: noqa
"""HandX BLE driver.

The driver now implements a minimal operational connection layer using
`bleak` so the hub can talk to a real HandX dongle.  Notifications from the
device are decoded into a normalized dictionary matching the structure
produced by the legacy ``hxget.py`` helper.  When no device is present or
``bleak`` is unavailable the driver silently falls back to an inert mock so
unit tests and development remain unaffected.
"""

from __future__ import annotations

import asyncio
from threading import Thread
from typing import Any, Dict, List, Tuple
import struct
import time

try:  # ``bleak`` is optional at test time
    from bleak import BleakClient, BleakScanner
except Exception:  # pragma: no cover - best effort import
    BleakClient = BleakScanner = None

FAST_DATA_UUID = "dd90ec52-2001-4357-891a-26d580f709ef"
SLOW_DATA_UUID = "dd90ec52-2002-4357-891a-26d580f709ef"
# Legacy single-packet characteristic for older firmware
LEGACY_DATA_UUID = "dd90ec52-1002-4357-891a-26d580f709ef"

_HANDX_UUIDS = {FAST_DATA_UUID, SLOW_DATA_UUID, LEGACY_DATA_UUID}


def _is_handx_device(dev: Any) -> bool:
    """Return True if *dev* (a BleakDevice) looks like a HandX dongle."""
    name_l = (dev.name or "").lower()
    name_norm = name_l.replace(" ", "")
    meta = getattr(dev, "metadata", {})
    uuids = [u.lower() for u in meta.get("uuids", [])]
    manu = [
        bytes(v).decode(errors="ignore").lower()
        for v in meta.get("manufacturer_data", {}).values()
    ]
    return (
        "handx" in name_norm
        or "hxdongle" in name_norm
        or name_norm.startswith("hx")
        or ("hx" in name_l and "dongle" in name_l)
        or any(u in uuids for u in _HANDX_UUIDS)
        or any("handx" in m or m.startswith("hx") for m in manu)
    )


class HandXBLE:
    """Minimal BLE driver for the HandX device.

    The class exposes ``start``, ``stop`` and ``poll`` methods and decodes raw
    notification packets into a structured dictionary. ``feed_fast_packet`` and
    ``feed_slow_packet`` helpers remain available so tests or other sources can
    inject packets directly.
    """

    def __init__(self, address: str | None = None, verbose: bool = False) -> None:
        self._running = False
        self._last: Dict[str, Any] | None = None
        self._last_fast: Dict[str, Any] | None = None
        self._last_slow: Dict[str, Any] | None = None
        self._legacy = False
        self._addr = address
        self._client: Any = None
        self._loop: asyncio.AbstractEventLoop | None = None
        self._thread: Thread | None = None
        self._verbose = verbose
        self._slow_interval = 0.1
        self._next_slow_read = 0.0
        self._slow_notify = False

    # ------------------------------------------------------------------
    def start(self) -> None:  # pragma: no cover - relies on hardware
        """Start the BLE session and attempt connection in a background thread."""
        if self._verbose:
            print("HandXBLE: starting BLE session")
        if BleakClient is None or self._thread is not None:
            if self._verbose:
                print("HandXBLE: bleak not available or thread already running")
            return
        self._thread = Thread(target=self._run_loop, daemon=True)
        try:
            self._thread.start()
        except Exception:  # pragma: no cover - thread spawn best effort
            self._thread = None
            if self._verbose:
                print("HandXBLE: failed to spawn thread")
            return
        self._running = True

    def stop(self) -> None:  # pragma: no cover - relies on hardware
        """Stop the BLE session and disconnect if needed."""
        if self._verbose:
            print("HandXBLE: stopping BLE session")
        self._running = False
        self._last = None
        if self._loop and self._client:
            fut = asyncio.run_coroutine_threadsafe(
                self._client.disconnect(), self._loop
            )
            try:
                fut.result(timeout=2)
            except Exception:  # pragma: no cover - best effort
                pass
        if self._loop:
            self._loop.call_soon_threadsafe(self._loop.stop)
        if self._thread:
            try:
                if self._thread.is_alive():
                    self._thread.join(timeout=2)
            except RuntimeError:  # thread never started
                pass
        self._client = None
        self._loop = None
        self._thread = None

    # ------------------------------------------------------------------
    def _merge_last(self) -> None:
        merged: Dict[str, Any] = {}
        if self._last_slow:
            merged.update(self._last_slow)
        if self._last_fast:
            merged.update(self._last_fast)
        self._last = merged or None

    def feed_fast_packet(self, data: bytes) -> None:
        """Decode and store a fast notification packet."""
        self._last_fast = self.decode_fast_packet(data)
        self._merge_last()

    def feed_slow_packet(self, data: bytes) -> None:
        """Decode and store a slow diagnostic packet."""
        self._last_slow = self.decode_packet(data)
        self._merge_last()

    def feed_legacy_packet(self, data: bytes) -> None:
        """Decode a legacy combined packet."""
        self._legacy = True
        self._last_slow = self.decode_packet(data)
        self._last_fast = None
        self._merge_last()

    def feed_packet(self, data: bytes) -> None:
        """Alias for ``feed_legacy_packet`` for backward compatibility."""
        self.feed_legacy_packet(data)

    def _fast_notification_handler(self, _sender: int, data: bytes) -> None:
        """Handle incoming fast BLE packets from the device."""
        self.feed_fast_packet(data)

    def _slow_notification_handler(self, _sender: int, data: bytes) -> None:
        """Handle incoming slow BLE packets from the device."""
        self.feed_slow_packet(data)

    def _legacy_notification_handler(self, _sender: int, data: bytes) -> None:
        """Handle legacy single-stream packets."""
        self.feed_legacy_packet(data)

    def read_slow(self) -> None:  # pragma: no cover - hardware access
        """Fetch the latest slow diagnostic packet and merge it."""
        if self._legacy or not self._client or not self._loop:
            return
        fut = asyncio.run_coroutine_threadsafe(
            self._client.read_gatt_char(SLOW_DATA_UUID), self._loop
        )
        try:
            data = fut.result(timeout=2)
        except Exception:
            return
        self.feed_slow_packet(data)

    def _run_loop(self) -> None:
        """Background event loop managing BLE connection."""
        self._loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self._loop)
        try:
            self._loop.run_until_complete(self._connect())
            self._loop.run_forever()
        finally:
            self._loop.close()

    async def _connect(self) -> None:
        """Discover and connect to the HandX dongle if available."""
        if BleakClient is None:
            return
        try:
            addr = self._addr
            if addr is not None:
                if self._verbose:
                    print(f"HandXBLE: attempting stored address {addr}")
                try:
                    self._client = BleakClient(addr)
                    await self._client.connect()
                    if self._client.is_connected:
                        if self._verbose:
                            print(f"HandXBLE: connected to {addr}")
                        try:
                            await self._client.start_notify(
                                FAST_DATA_UUID, self._fast_notification_handler
                            )
                        except Exception:
                            await self._client.start_notify(
                                LEGACY_DATA_UUID, self._legacy_notification_handler
                            )
                            self._legacy = True
                            self._slow_notify = False
                        else:
                            self._legacy = False
                            try:
                                await self._client.start_notify(
                                    SLOW_DATA_UUID, self._slow_notification_handler
                                )
                            except Exception:
                                self._slow_notify = False
                            else:
                                self._slow_notify = True
                        return
                except Exception:  # pragma: no cover - best effort
                    if self._verbose:
                        print(f"HandXBLE: failed to connect to stored address {addr}")
                    self._client = None

            if self._verbose:
                print("HandXBLE: scanning for HandX devices...")
            devices = await BleakScanner.discover(timeout=5.0)
            if not devices:
                if self._verbose:
                    print("HandXBLE: no Bluetooth devices found")
            else:
                if self._verbose:
                    print("HandXBLE: discovered devices:")
                seen: set[str] = set()
                for dev in devices:
                    if dev.address in seen:
                        continue
                    seen.add(dev.address)
                    if self._verbose:
                        print(f"  - {dev.name or 'Unknown'} [{dev.address}]")
                    if _is_handx_device(dev) and addr is None:
                        addr = dev.address
                        if self._verbose:
                            print(
                                f"HandXBLE: found HandX device {dev.name or 'Unknown'} at {dev.address}"
                            )
            if addr is None:
                if self._verbose:
                    print("HandXBLE: no HandX dongle detected")
                return
            if self._verbose:
                print(f"HandXBLE: connecting to {addr}")
            self._client = BleakClient(addr)
            await self._client.connect()
            if self._client.is_connected:
                if self._verbose:
                    print("HandXBLE: connection established")
                try:
                    await self._client.start_notify(
                        FAST_DATA_UUID, self._fast_notification_handler
                    )
                except Exception:
                    await self._client.start_notify(
                        LEGACY_DATA_UUID, self._legacy_notification_handler
                    )
                    self._legacy = True
                    self._slow_notify = False
                else:
                    self._legacy = False
                    try:
                        await self._client.start_notify(
                            SLOW_DATA_UUID, self._slow_notification_handler
                        )
                    except Exception:
                        self._slow_notify = False
                    else:
                        self._slow_notify = True
        except Exception:  # pragma: no cover - connection best effort
            if self._verbose:
                print("HandXBLE: connection attempt failed")
            self._client = None

    # ------------------------------------------------------------------
    @classmethod
    def discover(
        cls, timeout: float = 5.0, verbose: bool = False
    ) -> List[Tuple[str, str]]:
        """Return ``(name, address)`` pairs for available HandX devices."""
        if BleakScanner is None:
            return []
        if verbose:
            print(f"HandXBLE: scanning for devices (timeout={timeout})")
        loop = asyncio.new_event_loop()
        try:
            devices = loop.run_until_complete(BleakScanner.discover(timeout=timeout))
        finally:
            loop.close()
        if not devices and verbose:
            print("HandXBLE: no Bluetooth devices found")
        dedup: Dict[str, str] = {}
        for dev in devices:
            if verbose:
                print(
                    f"HandXBLE: found device {dev.name or 'Unknown'} at {dev.address}"
                )
            if _is_handx_device(dev):
                dedup.setdefault(dev.address, dev.name or "Unknown")
        if not dedup and verbose:
            print("HandXBLE: no HandX devices found")
        return [(name, addr) for addr, name in dedup.items()]

    # ------------------------------------------------------------------
    @staticmethod
    def decode_fast_packet(data: bytes) -> Dict[str, Any]:
        """Decode a fast packet from the HandX dongle.

        Final firmware emits a 20-byte payload containing the sequence number,
        IMU orientation, four joystick channels (``joy_y``, ``joy_x``,
        ``direction``, ``bend``) and two finger-unit channels (``roll`` and
        ``grip``).  Older firmware produced shorter packets that omitted the
        extra channels; those are still parsed with missing fields defaulting
        to zero.  Transitional builds sometimes appended state bytes; when
        present they are parsed but callers should merge slow packets for the
        full device state.
        """
        if len(data) < 8:
            return {}
        seq = struct.unpack("<H", data[0:2])[0]
        roll, pitch, yaw = struct.unpack("<hhh", data[2:8])
        offset = 8
        joy_y = joy_x = direction = bend = 0
        if len(data) >= offset + 8:
            joy_y, joy_x, direction, bend = struct.unpack(
                "<hhhh", data[offset : offset + 8]
            )
            offset += 8
        elif len(data) >= offset + 4:
            joy_y, joy_x = struct.unpack("<hh", data[offset : offset + 4])
            offset += 4
        fu_0 = fu_1 = 0
        if len(data) >= offset + 4:
            fu_0, fu_1 = struct.unpack("<hh", data[offset : offset + 4])
            offset += 4
        result = {
            "seq": seq,
            "orientation": (roll, pitch, yaw),
            "joystick": (joy_x, joy_y),
            "direction": direction,
            "bend": bend,
            "roll": fu_0,
            "grip": fu_1,
        }
        if len(data) >= offset + 4:
            sys_state, lock_state, coupling_state, button_state = struct.unpack(
                "<BBBB", data[offset : offset + 4]
            )
            result["state"] = {
                "sys": sys_state,
                "lock": lock_state,
                "coupling": coupling_state,
            }
            result["buttons"] = {"state": [button_state]}
        return result

    @staticmethod
    def decode_packet(data: bytes) -> Dict[str, Any]:
        """Decode a slow diagnostic packet into a structured dictionary.

        Final firmware ships a 21-byte stream (including header and CRC)
        containing only fields absent from the fast packet.  Older firmware
        emitted a larger payload that mirrored the legacy layout.  Both formats
        are supported here so development tools remain compatible.
        """
        hdr = 3
        if len(data) >= 37:  # legacy extended layout
            seq = struct.unpack("<H", data[hdr : hdr + 2])[0]
            roll, pitch, yaw = struct.unpack("<hhh", data[hdr + 2 : hdr + 8])
            roll_range = struct.unpack("<H", data[hdr + 8 : hdr + 10])[0]
            joy_y, joy_x = struct.unpack("<hh", data[hdr + 10 : hdr + 14])
            direction, bend = struct.unpack("<hh", data[hdr + 14 : hdr + 18])
            fu_0, fu_1 = struct.unpack("<bb", data[hdr + 18 : hdr + 20])
            sys_state = data[hdr + 20]
            lock_state = data[hdr + 21]
            coupling_state = data[hdr + 22]
            invert_mode = data[hdr + 23]
            button_event = list(data[hdr + 24 : hdr + 27])
            button_number_events = list(data[hdr + 27 : hdr + 30])
            button_state = list(data[hdr + 30 : hdr + 33])
            return {
                "seq": seq,
                "orientation": (roll, pitch, yaw),
                "roll_range": roll_range,
                "joystick": (joy_x, joy_y),
                "direction": direction,
                "bend": bend,
                "roll": fu_0,
                "grip": fu_1,
                "state": {
                    "sys": sys_state,
                    "lock": lock_state,
                    "coupling": coupling_state,
                    "invert": invert_mode,
                },
                "buttons": {
                    "event": button_event,
                    "number": button_number_events,
                    # ``times`` kept for backward compatibility with callers
                    # that may still reference the legacy field name.
                    "times": button_number_events,
                    "state": button_state,
                },
            }
        if len(data) < 21:  # header + payload + crc
            return {}
        seq = struct.unpack("<H", data[hdr : hdr + 2])[0]
        roll_range = struct.unpack("<H", data[hdr + 2 : hdr + 4])[0]
        sys_state = data[hdr + 4]
        lock_state = data[hdr + 5]
        coupling_state = data[hdr + 6]
        invert_mode = data[hdr + 7]
        button_event = list(data[hdr + 8 : hdr + 11])
        button_number_events = list(data[hdr + 11 : hdr + 14])
        button_state = list(data[hdr + 14 : hdr + 17])
        return {
            "seq": seq,
            "roll_range": roll_range,
            "state": {
                "sys": sys_state,
                "lock": lock_state,
                "coupling": coupling_state,
                "invert": invert_mode,
            },
            "buttons": {
                "event": button_event,
                "number": button_number_events,
                # ``times`` kept for backward compatibility.
                "times": button_number_events,
                "state": button_state,
            },
        }

    # ------------------------------------------------------------------
    def poll(self) -> Dict[str, Any]:
        """Return the latest decoded packet or empty data when idle."""
        if not self._running:
            return {}
        if (
            self._client
            and not self._legacy
            and not self._slow_notify
            and time.time() >= self._next_slow_read
        ):
            self.read_slow()
            self._next_slow_read = time.time() + self._slow_interval
        if self._last is not None:
            return self._last
        # No data received yet – return zeros so callers can rely on keys.
        return {
            "joystick": (0.0, 0.0),
            "direction": 0.0,
            "bend": 0.0,
            "roll": 0.0,
            "grip": 0.0,
            "orientation": (0.0, 0.0, 0.0),
            "state": {},
            "buttons": {},
        }
