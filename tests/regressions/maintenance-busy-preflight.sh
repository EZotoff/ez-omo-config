#!/usr/bin/env bash
# Regression: maintenance busy-preflight false positive (fixed 2026-09-22).
#
# The old check_db_busy() treated ANY process holding the DB's -wal/-shm
# sidecars open as "busy" — always true while the always-on `opencode serve`
# instances were running, so the weekly retention archiver never executed
# (rc=10 in every logged run; docs/session-archiving.md). New semantics:
# busy = another opencode_maintenance run holds the maintenance lockfile.
#
# Case 1 (the regression): sidecar files held open by an unrelated process
# must NOT be reported busy. Case 2: a lockfile held by another process MUST
# be reported busy.
set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"
OM="$(cd "$(dirname "$0")/../.." && pwd)/scripts/opencode_maintenance.py"
RUNDIR="$(mktemp -d /tmp/opencode/maint-busy.XXXXXX)"
PIDFILE=/tmp/opencode/maintenance-busy-preflight.pids
echo "$RUNDIR" > /tmp/opencode/maintenance-busy-preflight.rundir
: > "$PIDFILE"
trap 'rm -rf "$RUNDIR"' EXIT

om_probe() {
  python3 -c "
import importlib.util, sys
spec = importlib.util.spec_from_file_location('om', '$OM')
om = importlib.util.module_from_spec(spec); sys.modules['om'] = om
spec.loader.exec_module(om)
om.MAINTENANCE_LOCK_PATH = '$RUNDIR/lock'
print('BUSY' if om.check_db_busy('unused-path') else 'FREE')
"
}

# Case 1: unrelated process holds the DB sidecars open -> FREE (the fix)
touch "$RUNDIR/fake.db-wal" "$RUNDIR/fake.db-shm"
( exec 3>"$RUNDIR/fake.db-wal" 4>"$RUNDIR/fake.db-shm"; sleep 25 ) & SIDE=$!
echo "$SIDE" >> "$PIDFILE"
sleep 0.3
if [ "$(om_probe)" != "FREE" ]; then
  echo "FAIL: sidecar holder still reported busy (old false positive reintroduced)"
  exit 1
fi

# Case 2: another process holds the maintenance lockfile -> BUSY
flock -n "$RUNDIR/lock" -c 'sleep 25' & LOCK=$!
echo "$LOCK" >> "$PIDFILE"
sleep 0.3
if [ "$(om_probe)" != "BUSY" ]; then
  echo "FAIL: external lockfile holder not detected as busy"
  exit 1
fi

kill "$SIDE" "$LOCK" 2>/dev/null || true
rm -f "$PIDFILE" /tmp/opencode/maintenance-busy-preflight.rundir
echo "PASS: maintenance busy-preflight (sidecar-open=FREE, lockfile-held=BUSY)"
