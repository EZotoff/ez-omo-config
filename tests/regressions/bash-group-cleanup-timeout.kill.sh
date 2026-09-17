#!/usr/bin/env bash
# Cleanup for bash-group-cleanup-timeout.sh.
#
# Kills exactly the PIDs the test recorded (contained `sleep` survivors left by
# the RED unpatched binary). Idempotent: safe to run twice; exits 0 when the PID
# list is empty or the processes are already gone. No pkill sweeps — every kill
# is a specific recorded PID, guarded by a cmdline identity check so a reused
# PID is never signalled.
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

STATE_DIR="${TMPDIR:-/tmp}/opencode/regression-bash-lifecycle"
PIDFILE="$STATE_DIR/bash-group-cleanup-timeout.pids"

if [[ ! -f "$PIDFILE" ]]; then
    echo "PASS: no recorded PIDs (nothing to clean)"
    exit 0
fi

killed=0
while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    kill -0 "$pid" 2>/dev/null || continue
    # Identity guard: only signal a process whose cmdline is the expected sleep.
    if [[ -r "/proc/$pid/cmdline" ]] && tr '\0' ' ' < "/proc/$pid/cmdline" | grep -q '^sleep '; then
        kill -TERM "$pid" 2>/dev/null || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.2
        done
        if kill -0 "$pid" 2>/dev/null; then
            kill -KILL "$pid" 2>/dev/null || true
        fi
        killed=$((killed + 1))
    else
        echo "SKIP: PID $pid is not the expected sleep (identity guard)"
    fi
done < "$PIDFILE"

# Clear the list so a second run is a clean no-op (idempotent).
: > "$PIDFILE"
echo "PASS: cleaned $killed recorded PID(s)"
exit 0
