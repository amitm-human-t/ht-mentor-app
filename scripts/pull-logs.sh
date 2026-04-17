#!/usr/bin/env bash
# pull-logs.sh — pull the app's file-based debug log from the iPad sandbox
#
# The app writes to: <AppContainer>/Library/Logs/handx-debug.log
# This script copies it to /tmp/handx-debug.log on your Mac.
#
# Usage:
#   ./scripts/pull-logs.sh          # pull from real iPad
#   ./scripts/pull-logs.sh sim      # pull from simulator
#   ./scripts/pull-logs.sh tail     # pull + print last 100 lines

set -euo pipefail

DEVICE_UDID="00008103-001245923C07001E"
BUNDLE_ID="com.humanx.p2-app"
LOG_FILENAME="handx-debug.log"
LOCAL_PATH="/tmp/handx-debug.log"

MODE="${1:-device}"

case "$MODE" in
    device)
        echo "Pulling $LOG_FILENAME from iPad sandbox..."
        xcrun devicectl device file pull \
            --device "$DEVICE_UDID" \
            --source "Library/Logs/$LOG_FILENAME" \
            --destination "$LOCAL_PATH" \
            --domain-type appDataContainer \
            --domain-identifier "$BUNDLE_ID" \
            2>&1
        echo ""
        echo "Saved to $LOCAL_PATH"
        echo "Lines: $(wc -l < "$LOCAL_PATH")"
        ;;
    sim)
        echo "Finding simulator container for $BUNDLE_ID..."
        CONTAINER=$(xcrun simctl get_app_container booted "$BUNDLE_ID" data 2>/dev/null || echo "")
        if [ -z "$CONTAINER" ]; then
            echo "App not installed on booted simulator."
            exit 1
        fi
        SRC="$CONTAINER/Library/Logs/$LOG_FILENAME"
        if [ ! -f "$SRC" ]; then
            echo "Log file not found at $SRC"
            echo "(App may not have written any file logs yet)"
            exit 1
        fi
        cp "$SRC" "$LOCAL_PATH"
        echo "Saved to $LOCAL_PATH"
        echo "Lines: $(wc -l < "$LOCAL_PATH")"
        ;;
    tail)
        # Pull then print
        bash "$0" device
        echo ""
        echo "━━━ Last 100 lines ━━━"
        tail -100 "$LOCAL_PATH"
        ;;
    *)
        echo "Usage: $0 [device|sim|tail]"
        exit 1
        ;;
esac
