#!/bin/bash
# ─────────────────────────────────────────────────────
# signal-handler.sh
#
# A process that handles signals correctly.
# Represents a well-written Kubernetes application.
# Shows graceful shutdown behaviour.
# ─────────────────────────────────────────────────────

# ── State ────────────────────────────────────────────
KEEP_RUNNING=true
SHUTDOWN_REASON=""
START_TIME=$(date +%s)

# ── Signal handlers ───────────────────────────────────

handle_sigterm() {
    SHUTDOWN_REASON="SIGTERM"
    echo ""
    echo "[$(date +%T)] SIGTERM received — beginning graceful shutdown"
    echo "[$(date +%T)] Finishing current work..."
    sleep 2
    echo "[$(date +%T)] Closing resources..."
    sleep 1
    echo "[$(date +%T)] Graceful shutdown complete (reason: $SHUTDOWN_REASON)"
    KEEP_RUNNING=false
}

handle_sigint() {
    SHUTDOWN_REASON="SIGINT"
    echo ""
    echo "[$(date +%T)] SIGINT received (Ctrl+C) — stopping"
    KEEP_RUNNING=false
}

handle_sighup() {
    echo ""
    echo "[$(date +%T)] SIGHUP received — reloading configuration"
    echo "[$(date +%T)] Configuration reloaded successfully"
}

# ── Register handlers ─────────────────────────────────
trap 'handle_sigterm' SIGTERM
trap 'handle_sigint'  SIGINT
trap 'handle_sighup'  SIGHUP

# ── Main loop ─────────────────────────────────────────
echo "=== Signal Handler Process Started ==="
echo "PID: $$"
echo "User: $(whoami) (UID: $(id -u))"
echo ""
echo "Registered handlers for: SIGTERM, SIGINT, SIGHUP"
echo "Test with:"
echo "  kill $$          → graceful shutdown (SIGTERM)"
echo "  kill -HUP $$     → config reload (SIGHUP)"
echo "  kill -9 $$       → force kill (SIGKILL, uncatchable)"
echo ""

COUNTER=0
while $KEEP_RUNNING; do
    COUNTER=$((COUNTER + 1))
    UPTIME=$(( $(date +%s) - START_TIME ))
    echo "[$(date +%T)] Running — heartbeat #$COUNTER — uptime ${UPTIME}s"
    sleep 5 &
    wait $!
done

RUNTIME=$(( $(date +%s) - START_TIME ))
echo "[$(date +%T)] Process ended after ${RUNTIME}s"
exit 0
