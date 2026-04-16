"""HandX provider that wraps the BLE driver with a mock fallback.

The provider exposes scanning and connection helpers so the UI can bind to
either a real HandX dongle or a headless mock HandX tool.  Raw samples are
emitted via ``inputsSampled`` and the latest reading can be retrieved with
``poll`` so tasks may consume HandX data on their worker thread.  Joystick
axes are normalized to ``[-1, 1]`` so UI overlays can rely on consistent
coordinates regardless of whether a real or mock device is supplying data.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from datetime import datetime
from threading import Lock, Thread
from typing import Any, Dict, List

from PyQt6.QtCore import QObject, QTimer, pyqtSignal

from .handx_driver import MOCK_ADDRESS_PREFIX, HandXDriver, create_driver
from .handx_ble import HandXBLE

logger = logging.getLogger("p1.devices.handx")
logger.setLevel(logging.INFO)


@dataclass
class DeviceDTO:
    name: str
    addr: str
    rssi: int
    last_seen: str


class HandXProvider(QObject):
    """Manage HandX scanning, connection and input sampling."""

    devicesChanged = pyqtSignal(list)
    stateChanged = pyqtSignal(str)
    logLine = pyqtSignal(str)
    inputsSampled = pyqtSignal(dict)

    def __init__(self, parent=None) -> None:
        super().__init__(parent)
        self._devices: List[DeviceDTO] = []
        self._input_thread: Thread | None = None
        self._polling = False
        self._driver: HandXDriver | None = None
        self._verbose = False
        self._state = "disconnected"
        self._connect_addr: str | None = None
        self._last: Dict[str, Any] = {}
        self._lock = Lock()
        self._scan_thread: Thread | None = None
        self._prev_button_counts: list[int] | None = None
        self._last_lock_process_ts: float | None = None
        self._predicted_locked_bool: bool | None = None
        self._predicted_lock_state: str | None = None
        self._locking_event_count: int = 0
        self._unlocking_event_count: int = 0

    @property
    def state(self) -> str:
        """Current connection state (`disconnected`, `connecting`, `connected`)."""

        return self._state

    @property
    def address(self) -> str | None:
        """BLE address of the connected device, if any."""

        return self._connect_addr if self._state == "connected" else None

    # scanning -----------------------------------------------------------
    def start_scan(self, filter_nearby: bool = False) -> None:
        if (
            self._scan_thread
            and getattr(self._scan_thread, "is_alive", lambda: False)()
        ):
            return
        logger.info("HandXScanStarted{filter=%s}", filter_nearby)
        self.logLine.emit(f"Scan started (nearby={filter_nearby})")

        def _scan() -> None:
            try:
                now = datetime.now().strftime("%H:%M:%S")
                raw = HandXBLE.discover(timeout=0.5, verbose=self._verbose)
                handx = raw if raw else [("Mock HandX", f"{MOCK_ADDRESS_PREFIX}:00")]
                self._devices = [DeviceDTO(name, addr, 0, now) for name, addr in handx]
                self.devicesChanged.emit([d.__dict__ for d in self._devices])
                logger.info("HandXScanStopped{count=%d}", len(self._devices))
            finally:
                self._scan_thread = None

        self._scan_thread = Thread(target=_scan, daemon=True)
        self._scan_thread.start()

    def stop_scan(self) -> None:
        self.logLine.emit("Scan stopped")
        if (
            self._scan_thread
            and getattr(self._scan_thread, "is_alive", lambda: False)()
        ):
            self._scan_thread.join(timeout=0.1)
        self._scan_thread = None

    # connection ---------------------------------------------------------
    def connect(self, addr: str) -> None:
        if self._state != "disconnected":
            return
        self._state = "connecting"
        self.stateChanged.emit("connecting")
        self.logLine.emit(f"Connecting to {addr}")
        self._connect_addr = addr
        # Defer to the next event-loop tick so the UI can update first.
        QTimer.singleShot(0, lambda: self._do_connect(addr))

    def _do_connect(self, addr: str) -> None:
        try:
            self._driver = create_driver(addr)
            if self._verbose and hasattr(self._driver, "_verbose"):
                self._driver._verbose = True  # type: ignore[attr-defined]
            self._driver.start()
            self._state = "connected"
            self.stateChanged.emit("connected")
            self.logLine.emit("Connected")
            logger.info("HandXConnected{addr=%s}", addr)
            self._start_polling()
        except Exception as exc:  # pragma: no cover - best effort logging
            logger.error("HandXConnectFailed{addr=%s, err=%s}", addr, exc)
            self.logLine.emit("Connect failed")
            self._state = "disconnected"
            self.stateChanged.emit("disconnected")

    def disconnect(self) -> None:
        if self._state == "disconnected":
            return
        self._stop_polling()
        if self._driver:
            try:
                self._driver.stop()
            except Exception:  # pragma: no cover
                pass
            self._driver = None
        self._state = "disconnected"
        self.stateChanged.emit("disconnected")
        logger.info("HandXDisconnected{reason=user}")
        self.logLine.emit("Disconnected")
        self._connect_addr = None

    def reset(self) -> None:
        """Forget discovered devices and disconnect."""
        self.disconnect()
        self._devices = []
        self.devicesChanged.emit([])

    # verbose toggle ----------------------------------------------------
    def set_verbose(self, on: bool) -> None:
        self._verbose = on
        logger.setLevel(logging.DEBUG if on else logging.INFO)
        if self._driver is not None and hasattr(self._driver, "_verbose"):
            self._driver._verbose = on  # type: ignore[attr-defined]
        logger.info("HandXVerboseToggled{on=%s}", on)
        self.logLine.emit(f"Verbose={'on' if on else 'off'}")

    # input generation --------------------------------------------------
    def _start_polling(self) -> None:
        if self._polling:
            return
        self._polling = True
        self._prev_button_counts = None
        self._last_lock_process_ts = None
        self._predicted_locked_bool = None
        self._predicted_lock_state = None
        self._locking_event_count = 0
        self._unlocking_event_count = 0
        if self._input_thread is None or not self._input_thread.is_alive():
            self._input_thread = Thread(target=self._poll_loop, daemon=True)
            self._input_thread.start()

    def _stop_polling(self) -> None:
        self._polling = False
        if self._input_thread:
            try:
                if self._input_thread.is_alive():
                    self._input_thread.join(timeout=1.0)
            except RuntimeError:  # thread never started
                pass
            self._input_thread = None

    def _poll_loop(self) -> None:
        interval = 0.02  # 50 Hz target
        while self._polling:
            start = time.perf_counter()
            self._on_input_tick()
            # Compensate for work time so the effective poll rate stays ~50 Hz
            elapsed = time.perf_counter() - start
            sleep = interval - elapsed
            if sleep > 0:
                time.sleep(sleep)

    def _on_input_tick(self) -> None:
        if self._driver is not None:
            data = self._driver.poll()
            # Older BLE packets expose orientation but not the ``rpy`` alias
            # used by the UI.  Add the alias so widgets can rely on it without
            # checking for multiple keys.
            if "orientation" in data and "rpy" not in data:
                data["rpy"] = data["orientation"]
            if not data:
                self.logLine.emit("No data received from HandX")
            # Mark whether real sensor values have arrived.  An empty dict means
            # the driver is connected but has not yet forwarded a packet.
            is_synthetic = not bool(data)
        else:
            data = {}
            is_synthetic = True  # no driver → all-zero placeholder
        # Stamp before _detect_lock_unlock_process_start so consumers can
        # distinguish a real reading from a synthetic placeholder in one check.
        data["is_synthetic"] = is_synthetic
        self._detect_lock_unlock_process_start(data)
        joy = data.get("joystick")
        if joy is not None:
            jx, jy = joy
            if max(abs(jx), abs(jy)) > 1.5:
                jx = (jx - 2048) / 2047
                jy = (jy - 2048) / 2047
            data["joystick"] = (
                max(-1.0, min(1.0, float(jx))),
                max(-1.0, min(1.0, float(jy))),
            )
        with self._lock:
            self._last = data
        self.inputsSampled.emit(data)
        if self._verbose:
            logger.debug("HandXSample %s", data)

    def poll(self) -> Dict[str, Any]:
        with self._lock:
            return dict(self._last)

    # ------------------------------------------------------------------
    def _detect_lock_unlock_process_start(self, data: Dict[str, Any]) -> None:
        """Print when the HandX lock/unlock sequences begin based on button events.

        Lock pre-detection fires only when the current slow-packet lock state
        reports that the tool is unlocked (value ``2``). Unlock pre-detection
        requires the slow state to report locked (value ``1``) unless it occurs
        within 1.5 seconds of the lock trigger so transitions don't get lost
        while the slow telemetry catches up.  Each poll copies the inferred
        lock information onto the ``lock_process`` dictionary inside the data
        payload so tasks can react without reading the raw slow state.  The
        section now includes ``predicted_locked`` and ``predicted_lock_state``
        so downstream consumers can rely on the inferred outcome and the
        current transition (locking vs unlocking) even before the slow
        telemetry flips.  Transition markers remain until the slow state
        confirms the final locked/unlocked value so consumers do not miss the
        in-progress phase while waiting for the HandX to update its lock
        telemetry.
        """

        lock_process = data.setdefault("lock_process", {})
        lock_state_value: int | None = None
        state = data.get("state")
        if isinstance(state, dict):
            raw_lock_state = state.get("lock")
            try:
                lock_state_value = int(raw_lock_state)
            except (TypeError, ValueError):
                lock_state_value = None
        slow_locked: bool | None = None
        if lock_state_value == 1:
            slow_locked = True
        elif lock_state_value == 2:
            slow_locked = False

        def _store_lock_section(locking: bool = False, unlocking: bool = False) -> None:
            lock_process["locking"] = locking
            lock_process["unlocking"] = unlocking
            lock_process["locked"] = slow_locked
            lock_process["predicted_locked"] = self._predicted_locked_bool
            lock_process["predicted_lock_state"] = self._predicted_lock_state
            lock_process["state_value"] = lock_state_value
            lock_process["last_lock_ts"] = self._last_lock_process_ts
            lock_process["locking_count"] = self._locking_event_count
            lock_process["unlocking_count"] = self._unlocking_event_count

        buttons = data.get("buttons")
        counts = events = None
        if isinstance(buttons, dict):
            counts = buttons.get("number")
            events = buttons.get("event")
        if not isinstance(counts, (list, tuple)) or not isinstance(events, (list, tuple)):
            _store_lock_section()
            return
        if len(counts) < 3 or len(events) < 3:
            _store_lock_section()
            return
        try:
            normalized_counts = [int(c) for c in counts]
            normalized_events = [int(e) for e in events]
        except (TypeError, ValueError):
            _store_lock_section()
            return
        is_locked = lock_state_value == 1
        is_unlocked = lock_state_value == 2
        within_lock_grace = False
        if self._last_lock_process_ts is not None:
            within_lock_grace = (time.monotonic() - self._last_lock_process_ts) < 1.5
        allow_lock_trigger = is_unlocked
        if not allow_lock_trigger and lock_state_value not in (1, 2):
            allow_lock_trigger = self._predicted_locked_bool is False
        allow_unlock_trigger = is_locked or within_lock_grace
        if not allow_unlock_trigger and lock_state_value not in (1, 2):
            allow_unlock_trigger = self._predicted_locked_bool is True
        current_count = normalized_counts[2]
        event_code = normalized_events[2]
        if self._prev_button_counts is None or len(self._prev_button_counts) < 3:
            self._prev_button_counts = normalized_counts
            _store_lock_section()
            return
        previous_count = self._prev_button_counts[2]
        locking_triggered = False
        unlocking_triggered = False
        if current_count != previous_count:
            if event_code == 3 and allow_lock_trigger:
                self._last_lock_process_ts = time.monotonic()
                self._predicted_locked_bool = True
                self._predicted_lock_state = "locking"
                self._locking_event_count += 1
                logger.info("HandXLockProcessStarted")
                locking_triggered = True
            elif event_code == 5 and allow_unlock_trigger:
                self._predicted_locked_bool = False
                self._predicted_lock_state = "unlocking"
                self._unlocking_event_count += 1
                logger.info("HandXUnlockProcessStarted")
                unlocking_triggered = True
        self._prev_button_counts = normalized_counts

        if slow_locked is not None:
            if self._predicted_lock_state == "locking":
                if slow_locked:
                    self._predicted_locked_bool = True
                    self._predicted_lock_state = "locked"
            elif self._predicted_lock_state == "unlocking":
                if not slow_locked:
                    self._predicted_locked_bool = False
                    self._predicted_lock_state = "unlocked"
            else:
                self._predicted_locked_bool = slow_locked
                self._predicted_lock_state = "locked" if slow_locked else "unlocked"

        _store_lock_section(locking_triggered, unlocking_triggered)


handx_provider = HandXProvider()
