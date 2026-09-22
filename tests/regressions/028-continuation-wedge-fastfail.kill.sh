#!/usr/bin/env bash
# Cleanup for 028-continuation-wedge-fastfail.sh.
#
# Kills exactly the scratch opencode serve PID the test recorded. Idempotent:
# safe to run twice; exits 0 when nothing is left. No pkill sweeps — every
# kill is a specific recorded PID, guarded by a cmdline identity check so a
# reused PID is never signalled. Removes the scratch dir and test state.
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

STATE_DIR="${TMPDIR:-/tmp}/opencode/regression-continuation"
PIDFILE="$STATE_DIR/028-wedge-fastfail.pids"
WORKFILE="$STATE_DIR/028-wedge-fastfail.work"

killed=0
if [[ -f "$PIDFILE" ]]; then
    while IFS= read -r pid; do
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        kill -0 "$pid" 2>/dev/null || continue
        # Identity guard: only signal a process whose cmdline is the scratch serve.
        if [[ -r "/proc/$pid/cmdline" ]] && tr '\0' ' ' < "/proc/$pid/cmdline" | grep -q 'serve'; then
            kill -CONT "$pid" 2>/dev/null || true   # un-wedge first so TERM is deliverable
            kill -TERM "$pid" 2>/dev/null || true
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                kill -0 "$pid" 2>/dev/null || break
                sleep 0.2
            done
            kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null || true
            killed=$((killed + 1))
        else
            echo "SKIP: PID $pid is not the expected scratch serve (identity guard)"
        fi
    done < "$PIDFILE"
    : > "$PIDFILE"
fi

if [[ -f "$WORKFILE" ]]; then
    while IFS= read -r work; do
        [[ -d "$work" ]] && rm -rf "$work"
    done < "$WORKFILE"
    : > "$WORKFILE"
fi

echo "PASS: cleaned $killed recorded scratch serve PID(s) + scratch dir"
exit 0
