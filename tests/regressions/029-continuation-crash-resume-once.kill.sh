#!/usr/bin/env bash
# Cleanup for 029-continuation-crash-resume-once.sh.
#
# Kills exactly the scratch opencode serve PID the test recorded. Idempotent;
# every kill is a specific recorded PID guarded by a cmdline identity check.
# Removes the scratch dir (which contains the test-local XDG_STATE_DIR with
# the seeded checkpoint, .consumed marker, and hooks.log).
set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"

STATE_DIR="${TMPDIR:-/tmp}/opencode/regression-continuation"
PIDFILE="$STATE_DIR/029-crash-resume-once.pids"
WORKFILE="$STATE_DIR/029-crash-resume-once.work"

killed=0
if [[ -f "$PIDFILE" ]]; then
    while IFS= read -r pid; do
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        kill -0 "$pid" 2>/dev/null || continue
        if [[ -r "/proc/$pid/cmdline" ]] && tr '\0' ' ' < "/proc/$pid/cmdline" | grep -q 'serve'; then
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

echo "PASS: cleaned $killed recorded scratch serve PID(s) + scratch dir (checkpoint + markers removed)"
exit 0
