"""HandX driver protocol and factory.

All concrete driver implementations (BLE, mock, future serial/USB) must
satisfy the :class:`HandXDriver` structural protocol.  Use
:func:`create_driver` to obtain the right driver for a given address rather
than instantiating :class:`~app.devices.handx_ble.HandXBLE` directly.

Input dictionary contract
-------------------------
``poll()`` returns a dict whose keys tasks and the provider can rely on:

.. code-block:: python

    {
        # Normalised joystick axes in [-1, 1].
        "joystick": (float, float),       # (x, y)

        # Auxiliary motion channels, also normalised.
        "direction": float,
        "bend": float,
        "roll": float,
        "grip": float,

        # IMU orientation in raw ADC ticks (roll, pitch, yaw).
        "orientation": (int, int, int),

        # Alias for orientation — always present when orientation is.
        "rpy": (int, int, int),

        # Slow-telemetry state flags (may be absent on fast-only firmware).
        "state": {
            "sys": int,
            "lock": int,     # 1 = locked, 2 = unlocked
            "coupling": int,
            "invert": int,
        },

        # Button edge/count data (may be absent).
        "buttons": {
            "event":  list[int],   # edge code per button
            "number": list[int],   # cumulative press count
            "state":  list[int],   # current button state
        },

        # Populated by HandXProvider after poll() — do not set in drivers.
        "lock_process": {
            "locking":               bool,
            "unlocking":             bool,
            "locked":                bool | None,
            "predicted_locked":      bool | None,
            "predicted_lock_state":  str | None,
            ...
        },
    }
"""

from __future__ import annotations

import json
import logging
import os
import subprocess
import sys
from pathlib import Path
from threading import Thread
from typing import Any, Dict, Protocol, runtime_checkable

logger = logging.getLogger("p1.devices.handx")

# Address prefix used to identify the built-in mock driver.
MOCK_ADDRESS_PREFIX = "AA:BB:CC"


@runtime_checkable
class HandXDriver(Protocol):
    """Structural protocol every HandX driver must satisfy.

    Implementations are free to connect over BLE, a serial port, a subprocess
    pipe, or any other transport as long as they expose these three methods.
    """

    def start(self) -> None:
        """Begin the driver session (connect, open port, spawn process…)."""
        ...

    def stop(self) -> None:
        """End the session and release all resources."""
        ...

    def poll(self) -> Dict[str, Any]:
        """Return the latest input snapshot.

        Must return an empty dict ``{}`` when no data is available yet.
        """
        ...


class MockHandXDriver:
    """Driver that reads from the bundled ``tools/mock_handx.py`` subprocess.

    The subprocess emits one JSON object per line on stdout; ``poll()``
    returns the most-recently parsed object.
    """

    def __init__(self) -> None:
        self._proc: subprocess.Popen[str] | None = None
        self._reader: Thread | None = None
        self._sample: Dict[str, Any] = {}

    def start(self) -> None:
        if self._proc is not None:
            return
        exe = Path(__file__).resolve().parents[2] / "tools" / "mock_handx.py"
        cmd = [sys.executable, "-u", str(exe)]
        gui = not (sys.platform.startswith("linux") and not os.environ.get("DISPLAY"))
        cmd.append("--stream" if gui else "--headless")
        self._proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, text=True, bufsize=1)

        proc = self._proc

        def _reader() -> None:
            assert proc.stdout is not None
            for line in proc.stdout:
                line = line.strip()
                if not line:
                    continue
                try:
                    self._sample = json.loads(line)
                except json.JSONDecodeError:
                    continue

        self._reader = Thread(target=_reader, daemon=True)
        self._reader.start()

    def stop(self) -> None:
        if self._proc:
            try:
                self._proc.terminate()
            except Exception:
                pass
            self._proc = None
        if self._reader and self._reader.is_alive():
            self._reader.join(timeout=1.0)
        self._reader = None
        self._sample = {}

    def poll(self) -> Dict[str, Any]:
        return dict(self._sample)


def create_driver(addr: str) -> HandXDriver:
    """Return the appropriate driver for *addr*.

    Addresses starting with :data:`MOCK_ADDRESS_PREFIX` always use the mock
    subprocess driver.  All other addresses are handed to the BLE driver.
    """
    if addr.startswith(MOCK_ADDRESS_PREFIX):
        return MockHandXDriver()
    from .handx_ble import HandXBLE
    return HandXBLE(addr)


__all__ = [
    "HandXDriver",
    "MockHandXDriver",
    "MOCK_ADDRESS_PREFIX",
    "create_driver",
]
