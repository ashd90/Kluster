#!/bin/bash
# ─────────────────────────────────────────────────────
# memory-hog.sh
#
# A process that gradually allocates memory.
# Used to observe cgroup memory tracking in action.
# Does NOT exceed any limit — just grows slowly
# so we can watch the cgroup memory.current rise.
# ─────────────────────────────────────────────────────

trap 'echo ""; echo "Cleaning up..."; exit 0' SIGTERM SIGINT

echo "=== Memory Hog Process ==="
echo "PID: $$"
echo ""
echo "This process allocates ~1MB every 3 seconds."
echo "Watch cgroup memory.current rise in process-explorer."
echo ""

# We store data in an array to prevent garbage collection
DATA=()
ITERATION=0

while true; do
    ITERATION=$((ITERATION + 1))

    # Allocate approximately 1MB by creating a long string
    # 1024 chars * 1024 = ~1MB of string data
    CHUNK=$(printf 'x%.0s' {1..1024})
    CHUNK=$(printf '%1024s' | tr ' ' 'x')

    # Store it so it isn't freed
    DATA+=("$CHUNK$ITERATION")

    APPROX_MB=$((ITERATION))
    echo "[$(date +%T)] Iteration $ITERATION — approx ${APPROX_MB}KB allocated"

    sleep 3
done
