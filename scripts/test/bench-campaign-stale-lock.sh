#!/usr/bin/env bash
# Group 4 — stale-lock recovery (run.lock semantics inside __run):
#   A. held run.lock  -> second __run invocation refuses ("run is already active")
#   B. stale run.lock file with no holder (simulated crashed service) -> __run
#      recovers the flock and drives the campaign to completion
#   C. launch-level duplicate protection: existing run dir -> launch refuses.
set -euo pipefail
. "$(dirname "$0")/bench-campaign-test-lib.sh"

GROUP="stale-lock"
EVIDENCE_FILE="$EVIDENCE_DIR/task-11-stale-lock.txt"
: >"$EVIDENCE_FILE"
ev "Task 11 stale-lock fixture — $(date +%F)"
suite_setup
trap 'flock -u 9 2>/dev/null || true; exec 9>&- 2>/dev/null || true; suite_cleanup' EXIT
make_workspace stalelock

RUN=t11lock
write_manifest "$WS/$RUN.json" "$RUN" 'printf locked-ok' \
  'sut:sut:family-a:fixture-model:case-1'

# Build the run directory exactly as launch would (owned manifest, modes).
mkdir -p "$WS/state/$RUN"
chmod 700 "$WS/state/$RUN"
install -m 600 "$WS/$RUN.json" "$WS/state/$RUN/manifest.json"

# A: this shell itself holds run.lock on fd 9; a concurrent __run must refuse.
# (fd held by the test shell, not a `flock file cmd` child — the child inherits
# the locked fd, so killing the wrapper would NOT release the lock.)
exec 9>"$WS/state/$RUN/run.lock"
flock -n 9 || fail "test could not acquire the lock it holds on purpose"
set +e
HOME="$WS/home" "$LAUNCHER" __run "$RUN" "$WS/state" >"$WS/a.out" 2>"$WS/a.err"
rc_a=$?
set -e
assert_eq "held-lock invocation exit code" "$rc_a" "2"
assert_match "held-lock refusal message" "$(cat "$WS/a.err")" "run is already active"

flock -u 9
exec 9>&-
ev "lock released (flock -u + close); run.lock file remains on disk with no holder (stale)"

# B: stale lock file (kernel flock released with the holder) -> recovery.
HOME="$WS/home" "$LAUNCHER" __run "$RUN" "$WS/state" >/dev/null 2>"$WS/b.err"
assert_eq "stale-lock file still present (recovery keeps evidence)" "$([[ -f "$WS/state/$RUN/run.lock" ]] && echo yes)" "yes"
terminal="$(wait_terminal "$WS/state" "$RUN" 60)"
assert_eq "recovered run ledger status" "$terminal" "completed"
assert_eq "recovered run completedCases" "$(ledger_field "$WS/state" "$RUN" 'd["completedCases"]')" "1"

# C: launch refuses to reuse an existing run directory.
set +e
HOME="$WS/home" BENCH_CAMPAIGN_STATE_DIR="$WS/state" "$LAUNCHER" launch "$WS/$RUN.json" >"$WS/c.out" 2>"$WS/c.err"
rc_c=$?
set -e
assert_eq "duplicate-launch exit code" "$rc_c" "2"
assert_match "duplicate-launch refusal message" "$(cat "$WS/c.err")" "run already exists"

# No bench-campaign-<run> unit was ever started by __run (direct invocation).
leftover="$(systemctl --user list-units 'bench-campaign-*' --all --no-legend | grep -F "$(unit_name "$RUN")" || true)"
assert_eq "no systemd unit created by direct __run" "$leftover" ""
ev "cleanup receipt: lock fd released and closed; no bench-campaign units created; workspace removed by trap"
ev "RESULT: PASS"
echo "PASS: stale-lock"
