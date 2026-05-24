#!/bin/bash
# ─────────────────────────────────────────────────────
# normal-process.sh
#
# A simple long-running process that does periodic work.
# Represents a basic application with no signal handling.
# We will use this as our first inspection target.
# ─────────────────────────────────────────────────────

echo "=== Normal Process Started ==="
echo "PID: $$"
echo "User: $(whoami) (UID: $(id -u))"
echo "Started at: $(date)"
echo ""
echo "This process has NO signal handler."
echo "SIGTERM will kill it immediately."
echo ""

COUNTER=0
while true; do
    COUNTER=$((COUNTER + 1))
    echo "[$(date +%T)] Heartbeat #$COUNTER — PID $$"

    # Create a temp file to show open file descriptors
    TMPFILE=$(mktemp /tmp/process-explorer-test-XXXXXX)
    echo "data" > "$TMPFILE"

    # Sleep and leave the file open conceptually
    # (it gets cleaned up next iteration)
    sleep 5
    rm -f "$TMPFILE"
done
