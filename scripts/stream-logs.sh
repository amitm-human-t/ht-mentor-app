#!/usr/bin/env bash
# stream-logs.sh — stream HandX Training Hub logs
#
# Usage:
#   ./scripts/stream-logs.sh              # auto-detect: real iPad if connected, else simulator
#   ./scripts/stream-logs.sh device       # force real iPad (UDID below)
#   ./scripts/stream-logs.sh sim          # force simulator
#   ./scripts/stream-logs.sh dump         # pull last ~500 lines from device log archive
#
# Claude: run this from the repo root. Logs print to stdout — paste the
# relevant section into the conversation when reporting a bug.

set -euo pipefail

SUBSYSTEM="humanx.p2-app"
DEVICE_UDID="00008103-001245923C07001E"
PREDICATE="subsystem == \"$SUBSYSTEM\""

# ── helpers ──────────────────────────────────────────────────────────────────

log_header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  HandX Training Hub — Log Stream"
    echo "  Subsystem: $SUBSYSTEM"
    echo "  $(date '+%Y-%m-%d %H:%M:%S')"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

is_device_connected() {
    xcrun devicectl list devices 2>/dev/null | grep -q "$DEVICE_UDID"
}

# ── modes ─────────────────────────────────────────────────────────────────────

stream_device() {
    log_header
    echo "[device] Streaming from iPad ($DEVICE_UDID)"
    echo "[device] Ctrl-C to stop"
    echo ""
    xcrun devicectl device syslog stream \
        --device "$DEVICE_UDID" \
        --predicate "$PREDICATE" \
        2>&1
}

stream_simulator() {
    log_header
    echo "[sim] Streaming from booted simulator"
    echo "[sim] Ctrl-C to stop"
    echo ""
    xcrun simctl spawn booted log stream \
        --predicate "$PREDICATE" \
        --style syslog \
        2>&1
}

dump_device() {
    log_header
    echo "[dump] Collecting recent logs from iPad ($DEVICE_UDID)..."
    echo ""
    # Use log collect to pull recent messages
    xcrun devicectl device syslog show \
        --device "$DEVICE_UDID" \
        --predicate "$PREDICATE" \
        --last 30m \
        2>&1 || {
        echo "[dump] 'syslog show' not available on this Xcode version."
        echo "[dump] Falling back to 'log collect'..."
        echo ""
        TMP=$(mktemp -d)
        xcrun devicectl device syslog collect \
            --device "$DEVICE_UDID" \
            --output "$TMP/app.logarchive" 2>&1 || true
        if [ -d "$TMP/app.logarchive" ]; then
            log show "$TMP/app.logarchive" \
                --predicate "$PREDICATE" \
                --last 30m \
                --style compact \
                2>&1 | tail -500
            rm -rf "$TMP"
        else
            echo "[dump] Could not collect device logs. Make sure the iPad is"
            echo "       trusted and Xcode Developer Disk Image is mounted."
        fi
    }
}

# ── dispatch ──────────────────────────────────────────────────────────────────

MODE="${1:-auto}"

case "$MODE" in
    device)
        stream_device
        ;;
    sim)
        stream_simulator
        ;;
    dump)
        dump_device
        ;;
    auto)
        if is_device_connected; then
            stream_device
        else
            echo "[auto] iPad not detected — falling back to simulator stream"
            echo ""
            stream_simulator
        fi
        ;;
    *)
        echo "Usage: $0 [device|sim|dump|auto]"
        exit 1
        ;;
esac
