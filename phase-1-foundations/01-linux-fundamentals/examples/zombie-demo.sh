#!/bin/bash

# ─────────────────────────────────────────────
# zombie-demo.sh
#
# Deliberately creates a zombie process so
# you can see what one looks like.
#
# A zombie = a finished process whose parent
# hasn't called wait() to collect its exit code.
# ─────────────────────────────────────────────

echo "Parent PID: $$"

# Spawn a child that exits immediately
(exit 0) &
CHILD_PID=$!

echo "Child PID: $CHILD_PID"
echo "Child has exited — but we're NOT calling wait"
echo ""
echo "Check for zombie with:"
echo "  ps aux | grep $CHILD_PID"
echo ""
echo "You should see STAT = 'Z' (zombie)"
echo ""
echo "Press Enter to let parent exit and zombie disappear..."
read

# When the parent exits, systemd (PID 1) adopts the zombie
# and immediately collects it — zombie disappears
