#!/usr/bin/env bash
# Cleanup for 034-continuation-resume-sigpipe.sh: removes the scratch dir the
# test created (stub harness — no background processes are spawned, so only the
# recorded rundir + any recorded PIDs need cleanup).
# Idempotent; must exit 0 standalone even when the main test left nothing behind.
set -o errexit
RUNDIR_FILE=/tmp/opencode/034-continuation-resume-sigpipe.rundir
PIDFILE=/tmp/opencode/034-continuation-resume-sigpipe.pids

if [[ -f "$PIDFILE" ]]; then
  while read -r pid; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    kill "$pid" 2>/dev/null || true
  done < "$PIDFILE"
  rm -f "$PIDFILE"
fi

if [[ -f "$RUNDIR_FILE" ]]; then
  rundir="$(cat "$RUNDIR_FILE")"
  case "$rundir" in
    */.cache/cont-sigpipe.*) rm -rf "$rundir" ;;
    *) echo "SKIP: refusing to remove unexpected path: $rundir" ;;
  esac
  rm -f "$RUNDIR_FILE"
fi

echo "PASS: no orphaned scratch (034)"
exit 0
