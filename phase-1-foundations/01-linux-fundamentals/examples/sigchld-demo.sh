#!/bin/bash

# ─────────────────────────────────────────────
# sigchld-demo.sh
#
# Demonstrates SIGCHLD — the signal a parent
# receives when a child process finishes.
#
# This is crucial for containers: if PID 1
# doesn't handle SIGCHLD, finished child
# processes become zombies.
# ─────────────────────────────────────────────

# Handler: runs every time a child process finishes
handle_sigchld() {
    # wait with -n means: collect ONE finished child
    # This prevents zombie processes
    wait -n 2>/dev/null
    echo "[$(date +%T)] Child process finished — collected by parent"
}

# Register the SIGCHLD handler
trap 'handle_sigchld' SIGCHLD

echo "[$(date +%T)] Parent process started. PID: $$"
echo ""

# Spawn 3 child processes with different lifetimes
echo "[$(date +%T)] Spawning 3 child processes..."

sleep 2 &
echo "[$(date +%T)] Child 1 spawned (PID $!) — will finish in 2s"

sleep 4 &
echo "[$(date +%T)] Child 2 spawned (PID $!) — will finish in 4s"

sleep 6 &
echo "[$(date +%T)] Child 3 spawned (PID $!) — will finish in 6s"

echo ""
echo "[$(date +%T)] Parent is waiting..."
echo ""

# Wait for all background jobs to finish
wait
echo ""
echo "[$(date +%T)] All children done. Parent exiting."
