#!/usr/bin/env bash
# Cleanup for test_supervisor_journal_bridge.sh.
#
# The bridge test runs `bun test supervisor/test/journalbridge.test.ts`, which
# creates scratch dirs via mkdtemp (prefix supervisor-bridge-) under the OS
# tmpdir, holding the test cursor/journal-bridge state and scratch ledger.jsonl.
# The suite self-cleans in afterEach, but a mid-run kill can leave them behind.
# This paired cleanup removes exactly that prefix — never other tmpdir content —
# and terminates any journalctl child the bridge's production reader
# (`journalctl -t restart-continuation`) may have spawned, guarded by parent
# identity (a still-running bun journalbridge test process) so production
# journalctl readers are never signalled. No pkill sweeps.
#
# Idempotent: safe to run twice and safe with nothing to clean.
set -euo pipefail

removed=0
for d in "${TMPDIR:-/tmp}"/supervisor-bridge-*; do
    [[ -e "$d" ]] || continue
    rm -rf -- "$d"
    removed=$((removed + 1))
done

killed=0
for proc in /proc/[0-9]*; do
    [[ -r "$proc/cmdline" && -r "$proc/status" ]] || continue   # /proc entries can vanish mid-scan
    cmdline="$(tr '\0' ' ' < "$proc/cmdline" 2>/dev/null || true)"
    case "$cmdline" in
        journalctl*restart-continuation*) ;;
        *) continue ;;
    esac
    ppid="$(awk '/^PPid:/{print $2}' "$proc/status" 2>/dev/null || true)"
    pcmd="$(tr '\0' ' ' < "/proc/${ppid:-0}/cmdline" 2>/dev/null || true)"
    if [[ "$pcmd" == *bun*journalbridge.test* ]]; then
        kill -TERM "${proc#/proc/}" 2>/dev/null || true
        killed=$((killed + 1))
    fi
done

echo "PASS: bridge cleanup removed $removed scratch dir(s), killed $killed journalctl child(ren)"
exit 0
