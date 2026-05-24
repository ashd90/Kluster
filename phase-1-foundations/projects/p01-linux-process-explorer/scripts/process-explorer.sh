#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# process-explorer.sh
#
# Inspects any running process and shows:
#   - Identity (PID, PPID, user, command)
#   - Namespace isolation status
#   - cgroup resource limits and usage
#   - Open file descriptors
#   - Network connections
#   - Signal handlers
#
# Usage: sudo ./process-explorer.sh <PID>
#        sudo ./process-explorer.sh <PID> --watch
#
# The --watch flag refreshes every 3 seconds (like kubectl top)
# ═══════════════════════════════════════════════════════════════

# ── Strict mode ───────────────────────────────────────────────
# -e  exit immediately if any command fails
# -u  treat unset variables as errors
# -o pipefail  pipeline fails if ANY command in it fails
set -euo pipefail

# ── Colour codes for output ───────────────────────────────────
# These are ANSI escape codes — the terminal interprets them
# as colour instructions rather than printing the characters
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'    # Resets all formatting back to normal

# ── Helper functions ──────────────────────────────────────────

# Prints a section header
section() {
    echo ""
    echo -e "${BOLD}${BLUE}══ $1 ══${RESET}"
}

# Prints a key-value pair
field() {
    printf "  ${CYAN}%-28s${RESET} %s\n" "$1" "$2"
}

# Prints a warning line
warn() {
    echo -e "  ${YELLOW}⚠  $1${RESET}"
}

# Prints a good/safe indicator
good() {
    echo -e "  ${GREEN}✓  $1${RESET}"
}

# Prints a bad/danger indicator
danger() {
    echo -e "  ${RED}✗  $1${RESET}"
}

# ── Argument validation ───────────────────────────────────────
# $# = number of arguments passed to the script
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <PID> [--watch]"
    echo ""
    echo "Examples:"
    echo "  sudo $0 1234"
    echo "  sudo $0 1234 --watch"
    echo "  sudo $0 \$(pgrep nginx | head -1)"
    exit 1
fi

TARGET_PID=$1
WATCH_MODE=false

# Check if --watch flag was passed
# ${2:-} means: use $2 if set, otherwise empty string
# This prevents -u (unset variable) from firing
if [[ "${2:-}" == "--watch" ]]; then
    WATCH_MODE=true
fi

# ── Validate the PID exists ───────────────────────────────────
# /proc/<pid> only exists while the process is running
if [[ ! -d "/proc/$TARGET_PID" ]]; then
    echo -e "${RED}Error: PID $TARGET_PID does not exist${RESET}"
    exit 1
fi

# ── Main inspection function ──────────────────────────────────
# We wrap everything in a function so --watch can call it
# repeatedly in a loop
inspect_process() {

    local PID=$1

    # Re-check the process still exists
    # 'local' makes variables scoped to this function only
    if [[ ! -d "/proc/$PID" ]]; then
        echo -e "${RED}Process $PID no longer exists${RESET}"
        return 1
    fi

    # ── Clear screen in watch mode ────────────────────────────
    if $WATCH_MODE; then
        clear
    fi

    echo -e "${BOLD}Process Explorer — PID $PID — $(date '+%Y-%m-%d %H:%M:%S')${RESET}"

    # ════════════════════════════════════════════════════════
    # SECTION 1 — PROCESS IDENTITY
    # ════════════════════════════════════════════════════════
    section "Process Identity"

    # /proc/<pid>/status contains a wealth of process info
    # grep -E matches lines with any of the listed field names
    # We read it once into a variable to avoid multiple reads
    STATUS=$(cat /proc/$PID/status 2>/dev/null || echo "")

    # Extract fields using grep and awk
    # awk '{print $2}' takes the second whitespace-separated field
    PROC_NAME=$(echo "$STATUS"   | grep "^Name:"  | awk '{print $2}')
    PROC_STATE=$(echo "$STATUS"  | grep "^State:" | awk '{print $2, $3}')
    PROC_PPID=$(echo "$STATUS"   | grep "^PPid:"  | awk '{print $2}')
    PROC_UID=$(echo "$STATUS"    | grep "^Uid:"   | awk '{print $2}')
    PROC_GID=$(echo "$STATUS"    | grep "^Gid:"   | awk '{print $2}')
    PROC_THREADS=$(echo "$STATUS"| grep "^Threads:" | awk '{print $2}')
    PROC_VMRSS=$(echo "$STATUS"  | grep "^VmRSS:" | awk '{print $2, $3}')
    PROC_VMPEAK=$(echo "$STATUS" | grep "^VmPeak:"| awk '{print $2, $3}')

    # Get the full command line
    # /proc/<pid>/cmdline stores args separated by null bytes (\0)
    # tr '\0' ' ' replaces null bytes with spaces for readability
    CMDLINE=$(cat /proc/$PID/cmdline 2>/dev/null | tr '\0' ' ' | sed 's/ $//')

    # Look up the username from UID
    # getent passwd queries the system user database
    USERNAME=$(getent passwd "$PROC_UID" 2>/dev/null | cut -d: -f1 || echo "UID:$PROC_UID")

    field "PID:"           "$PID"
    field "Name:"          "$PROC_NAME"
    field "State:"         "$PROC_STATE"
    field "Parent PID:"    "$PROC_PPID ($(cat /proc/$PROC_PPID/comm 2>/dev/null || echo 'unknown'))"
    field "User:"          "$USERNAME (UID: $PROC_UID, GID: $PROC_GID)"
    field "Threads:"       "$PROC_THREADS"
    field "RAM (current):" "$PROC_VMRSS"
    field "RAM (peak):"    "$PROC_VMPEAK"
    field "Command:"       "${CMDLINE:0:60}..."

    # Security check — warn if process runs as root
    if [[ "$PROC_UID" == "0" ]]; then
        danger "Running as root (UID 0) — potential security risk"
    else
        good "Running as non-root (UID $PROC_UID)"
    fi

    # ════════════════════════════════════════════════════════
    # SECTION 2 — NAMESPACE ISOLATION
    # ════════════════════════════════════════════════════════
    section "Namespace Isolation"

    echo "  Comparing process namespaces against host (PID 1):"
    echo ""

    # We compare each namespace against PID 1 (systemd/init)
    # If they match → process shares the host namespace (not isolated)
    # If they differ → process has its own namespace (isolated)
    for NS_TYPE in cgroup ipc mnt net pid uts user; do

        # readlink reads the symlink target
        # The target looks like: net:[4026531840]
        # The number is the namespace inode
        HOST_NS=$(readlink /proc/1/ns/$NS_TYPE 2>/dev/null || echo "unknown")
        PROC_NS=$(readlink /proc/$PID/ns/$NS_TYPE 2>/dev/null || echo "unknown")

        if [[ "$HOST_NS" == "$PROC_NS" ]]; then
            warn "$NS_TYPE namespace: SHARED with host ($PROC_NS)"
        else
            good "$NS_TYPE namespace: ISOLATED ($PROC_NS)"
        fi
    done

    # Determine if this looks like a container
    NET_NS_HOST=$(readlink /proc/1/ns/net 2>/dev/null)
    NET_NS_PROC=$(readlink /proc/$PID/ns/net 2>/dev/null)

    echo ""
    if [[ "$NET_NS_HOST" != "$NET_NS_PROC" ]]; then
        good "Assessment: This process appears to be CONTAINERISED"
    else
        field "Assessment:" "This process is a HOST process (not containerised)"
    fi

    # ════════════════════════════════════════════════════════
    # SECTION 3 — CGROUP RESOURCE LIMITS
    # ════════════════════════════════════════════════════════
    section "cgroup Resource Limits & Usage"

    # Get the cgroup path for this process
    # Format: 0::/path/to/cgroup
    # cut -d: -f3 takes the third colon-separated field
    CGROUP_REL=$(cat /proc/$PID/cgroup 2>/dev/null | grep "^0::" | cut -d: -f3)

    if [[ -z "$CGROUP_REL" ]]; then
        warn "Could not determine cgroup path"
    else
        CGROUP_PATH="/sys/fs/cgroup${CGROUP_REL}"
        field "cgroup path:" "$CGROUP_REL"
        echo ""

        # ── Memory ───────────────────────────────────────────
        echo "  Memory:"

        # memory.max — the hard limit
        # 'max' means unlimited (no cgroup limit set)
        MEM_MAX=$(cat "${CGROUP_PATH}/memory.max" 2>/dev/null || echo "unavailable")
        MEM_CURRENT=$(cat "${CGROUP_PATH}/memory.current" 2>/dev/null || echo "unavailable")

        if [[ "$MEM_MAX" == "max" ]]; then
            field "  Limit:"   "unlimited (no cgroup limit)"
        else
            # Convert bytes to MB for readability
            MEM_MAX_MB=$(( MEM_MAX / 1024 / 1024 ))
            field "  Limit:"   "${MEM_MAX} bytes (${MEM_MAX_MB} MB)"
        fi

        if [[ "$MEM_CURRENT" != "unavailable" ]]; then
            MEM_CURRENT_MB=$(( MEM_CURRENT / 1024 / 1024 ))
            field "  Current:"  "${MEM_CURRENT} bytes (${MEM_CURRENT_MB} MB)"

            # Warn if using more than 80% of limit
            if [[ "$MEM_MAX" != "max" && "$MEM_MAX" != "unavailable" ]]; then
                MEM_PCT=$(( MEM_CURRENT * 100 / MEM_MAX ))
                field "  Usage:"   "${MEM_PCT}%"
                if [[ $MEM_PCT -gt 80 ]]; then
                    danger "Memory usage above 80% — OOMKill risk"
                fi
            fi
        fi

        # ── CPU ───────────────────────────────────────────────
        echo ""
        echo "  CPU:"

        # cpu.max format: "quota period" or "max period"
        # quota/period = fraction of one CPU
        # e.g. "50000 100000" = 50% of one CPU
        CPU_MAX=$(cat "${CGROUP_PATH}/cpu.max" 2>/dev/null || echo "unavailable")

        if [[ "$CPU_MAX" == "max"* ]] || [[ "$CPU_MAX" == "unavailable" ]]; then
            field "  Limit:"   "unlimited (no cgroup limit)"
        else
            CPU_QUOTA=$(echo $CPU_MAX | awk '{print $1}')
            CPU_PERIOD=$(echo $CPU_MAX | awk '{print $2}')
            CPU_CORES=$(echo "scale=2; $CPU_QUOTA / $CPU_PERIOD" | bc 2>/dev/null || echo "?")
            field "  Limit:"   "$CPU_MAX (${CPU_CORES} cores)"
        fi

        # cpu.stat — throttling statistics
        CPU_STAT=$(cat "${CGROUP_PATH}/cpu.stat" 2>/dev/null || echo "")
        THROTTLED=$(echo "$CPU_STAT" | grep "throttled_usec" | awk '{print $2}')
        if [[ -n "$THROTTLED" && "$THROTTLED" != "0" ]]; then
            THROTTLED_MS=$(( THROTTLED / 1000 ))
            field "  Throttled:" "${THROTTLED_MS}ms total"
            if [[ $THROTTLED_MS -gt 1000 ]]; then
                warn "Significant CPU throttling detected — consider raising limit"
            fi
        else
            good "No CPU throttling detected"
        fi

        # ── PIDs ──────────────────────────────────────────────
        echo ""
        echo "  PIDs:"
        PID_MAX=$(cat "${CGROUP_PATH}/pids.max" 2>/dev/null || echo "unavailable")
        PID_CURRENT=$(cat "${CGROUP_PATH}/pids.current" 2>/dev/null || echo "unavailable")
        field "  Limit:"   "$PID_MAX"
        field "  Current:" "$PID_CURRENT"
    fi

    # ════════════════════════════════════════════════════════
    # SECTION 4 — OPEN FILE DESCRIPTORS
    # ════════════════════════════════════════════════════════
    section "Open File Descriptors"

    FD_DIR="/proc/$PID/fd"

    if [[ -r "$FD_DIR" ]]; then
        # Count total open FDs
        FD_COUNT=$(ls "$FD_DIR" 2>/dev/null | wc -l)
        field "Total open FDs:" "$FD_COUNT"
        echo ""

        # Show the first 10 FDs with their targets
        echo "  FD  Type        Target"
        echo "  ──  ──────────  ──────────────────────────────────"

        for FD in $(ls "$FD_DIR" 2>/dev/null | head -10); do
            TARGET=$(readlink "$FD_DIR/$FD" 2>/dev/null || echo "unknown")

            # Classify the FD type based on its target
            if [[ "$TARGET" == "socket:"* ]]; then
                FD_TYPE="socket"
            elif [[ "$TARGET" == "pipe:"* ]]; then
                FD_TYPE="pipe"
            elif [[ "$TARGET" == "/dev/"* ]]; then
                FD_TYPE="device"
            elif [[ "$TARGET" == "anon_inode:"* ]]; then
                FD_TYPE="anon"
            else
                FD_TYPE="file"
            fi

            printf "  %-3s %-11s %s\n" "$FD" "$FD_TYPE" "${TARGET:0:50}"
        done

        if [[ $FD_COUNT -gt 10 ]]; then
            echo "  ... and $((FD_COUNT - 10)) more"
        fi
    else
        warn "Cannot read FD directory (try running with sudo)"
    fi

    # ════════════════════════════════════════════════════════
    # SECTION 5 — NETWORK CONNECTIONS
    # ════════════════════════════════════════════════════════
    section "Network Connections"

    # Enter the process's network namespace and run ss
    # This shows connections as the PROCESS sees them
    # not filtered by grep but truly from inside its namespace
    if command -v nsenter &>/dev/null; then
        echo "  (Connections visible from inside process's network namespace)"
        echo ""
        sudo nsenter -t "$PID" --net -- \
            ss -tnp 2>/dev/null | head -15 || \
            warn "Could not enter network namespace"
    else
        warn "nsenter not available — showing host-level connections"
        ss -tnp 2>/dev/null | grep "$PID" | head -10
    fi

    # ════════════════════════════════════════════════════════
    # SECTION 6 — SIGNAL HANDLING
    # ════════════════════════════════════════════════════════
    section "Signal Handling"

    # /proc/<pid>/status contains SigCgt — caught signals bitmask
    # Each bit represents a signal number
    # If the bit is 1, the process has a handler for that signal
    SIGCGT=$(echo "$STATUS" | grep "^SigCgt:" | awk '{print $2}')
    SIGIGN=$(echo "$STATUS" | grep "^SigIgn:" | awk '{print $2}')

    field "Caught signals (hex):"  "$SIGCGT"
    field "Ignored signals (hex):" "$SIGIGN"
    echo ""

    # Convert hex bitmask to check specific signals
    # We use bash arithmetic with base-16 conversion
    if [[ -n "$SIGCGT" ]]; then
        SIGCGT_DEC=$(( 16#$SIGCGT ))

        # Check SIGTERM (bit 14, signal 15)
        # (( value & (1 << (sig-1)) )) — bitwise AND
        SIGTERM_CAUGHT=$(( (SIGCGT_DEC >> 14) & 1 ))
        SIGINT_CAUGHT=$(( (SIGCGT_DEC >> 1) & 1 ))
        SIGHUP_CAUGHT=$(( (SIGCGT_DEC >> 0) & 1 ))

        if [[ $SIGTERM_CAUGHT -eq 1 ]]; then
            good "SIGTERM (15): HANDLED — graceful shutdown possible"
        else
            danger "SIGTERM (15): NOT handled — will die immediately on kubectl delete"
        fi

        if [[ $SIGINT_CAUGHT -eq 1 ]]; then
            good "SIGINT (2):   HANDLED"
        else
            warn "SIGINT (2):   NOT handled (Ctrl+C causes immediate exit)"
        fi

        if [[ $SIGHUP_CAUGHT -eq 1 ]]; then
            good "SIGHUP (1):   HANDLED — config reload supported"
        else
            field "SIGHUP (1):" "  not handled (no config reload)"
        fi
    fi

    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
}

# ── Entry point ───────────────────────────────────────────────
if $WATCH_MODE; then
    echo "Watch mode — refreshing every 3 seconds. Ctrl+C to stop."
    # Trap Ctrl+C so we exit cleanly from watch mode
    trap 'echo ""; echo "Watch mode stopped."; exit 0' SIGINT

    while true; do
        inspect_process "$TARGET_PID" || break
        sleep 3
    done
else
    inspect_process "$TARGET_PID"
fi
