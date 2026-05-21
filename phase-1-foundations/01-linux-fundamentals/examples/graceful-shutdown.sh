#!/bin/bash

# ─────────────────────────────────────────────
# graceful-shutdown.sh
#
# Simulates a well-behaved application that
# handles SIGTERM properly — exactly what a
# Kubernetes pod should do.
# ─────────────────────────────────────────────

# This variable tracks whether we should keep running.
# We start as "true" (keep running).
KEEP_RUNNING=true

# ── Signal handler function ──────────────────
# This function runs when the process receives SIGTERM.
# Think of it as: "what should I do when Kubernetes
# asks me to shut down?"
handle_sigterm() {
    echo ""
    echo "[$(date +%T)] SIGTERM received — starting graceful shutdown..."
    echo "[$(date +%T)] Step 1: Stopped accepting new requests"
    sleep 1   # Simulate: finish current in-flight requests
    echo "[$(date +%T)] Step 2: Finished processing in-flight requests"
    sleep 1   # Simulate: close database connections
    echo "[$(date +%T)] Step 3: Closed database connections"
    sleep 1   # Simulate: flush any pending writes
    echo "[$(date +%T)] Step 4: Flushed pending writes to disk"
    echo "[$(date +%T)] Shutdown complete. Exiting cleanly with code 0."
    KEEP_RUNNING=false
}

# ── Register the signal handler ──────────────
# This line tells bash: "when you receive SIGTERM,
# run the handle_sigterm function instead of dying"
trap 'handle_sigterm' SIGTERM

# ── Also handle Ctrl+C (SIGINT) cleanly ──────
trap 'echo ""; echo "SIGINT received. Exiting."; exit 0' SIGINT

# ── Main application loop ────────────────────
echo "[$(date +%T)] Application started. PID is $$"
echo "[$(date +%T)] Send SIGTERM with: kill $$"
echo "[$(date +%T)] Or press Ctrl+C to stop."
echo ""

# This loop simulates an application doing work.
# In a real app, this would be: while serving HTTP requests
while $KEEP_RUNNING; do
    echo "[$(date +%T)] Working... (heartbeat)"
    # sleep in the background and wait for it.
    # This trick allows signal delivery even during sleep.
    sleep 5 &
    wait $!
done

# If we reach here, KEEP_RUNNING was set to false by handle_sigterm
echo "[$(date +%T)] Process exited."
exit 0
