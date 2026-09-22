#!/usr/bin/env bash
# Orphan cleanup for maintenance-busy-preflight.sh: kills the sidecar/lock
# holder processes recorded in the pidfile. Must succeed even when the main
# test left nothing behind (run_regressions.sh runs kill files standalone).
set -o errexit
PIDFILE=/tmp/opencode/maintenance-busy-preflight.pids
if [[ -f "$PIDFILE" ]]; then
  while read -r pid; do
    kill "$pid" 2>/dev/null || true
  done < "$PIDFILE"
  rm -f "$PIDFILE"
fi
RUNDIR_FILE=/tmp/opencode/maintenance-busy-preflight.rundir
if [[ -f "$RUNDIR_FILE" ]]; then
  rundir="$(cat "$RUNDIR_FILE")"
  rm -rf "$rundir" "$RUNDIR_FILE"
fi
echo "PASS: no orphaned holders"
