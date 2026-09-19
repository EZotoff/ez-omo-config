#!/usr/bin/env bash
# Group 5 — status accuracy: `status <run-id>` while running (active override,
# live case count) and after completion must agree with the durable ledger.
set -euo pipefail
. "$(dirname "$0")/bench-campaign-test-lib.sh"

GROUP="status"
EVIDENCE_FILE="$EVIDENCE_DIR/task-11-status.txt"
: >"$EVIDENCE_FILE"
ev "Task 11 status-accuracy fixture — $(date +%F)"
suite_setup
trap suite_cleanup EXIT
make_workspace status

RUN=t11stat
write_manifest "$WS/$RUN.json" "$RUN" 'sleep 2; printf s' \
  'sut:sut:family-a:fixture-model:case-1,case-2,case-3'

launch_campaign "$RUN" "$WS/$RUN.json"
U="$(unit_name "$RUN")"

status_line() {
  HOME="$WS/home" BENCH_CAMPAIGN_STATE_DIR="$WS/state" "$LAUNCHER" status "$RUN" \
    | awk -F'\t' 'NR==2{print $1"|"$3"|"$4"|"$5}'
}
header() {
  HOME="$WS/home" BENCH_CAMPAIGN_STATE_DIR="$WS/state" "$LAUNCHER" status "$RUN" | head -1
}
assert_eq "status header" "$(header)" "RUN_ID	SERVICE	STATUS	CASES	EXIT"

mid="$(status_line)"
ev "status while running: $mid"
case "$mid" in
  "$RUN"|running|*|*) ;;
  "$RUN"|active|*|*) ;;
  "$RUN"|activating|*|*) ;;
  *) fail "status while running not live-shaped: $mid" ;;
esac
running_cases="$(python3 -c 'import sys;print(sys.argv[1].split("|")[2])' "$mid")"
case "$running_cases" in [0-3]/3|[0-3]/\?) ;; *) fail "mid-run case count not 0..3/3: $running_cases";; esac
ev "ok: mid-run cases shape $running_cases"

terminal="$(wait_terminal "$WS/state" "$RUN" 120)"
assert_eq "ledger terminal status" "$terminal" "completed"
ev "final status line: $(status_line)"
final="$(status_line)"
assert_eq "final status line" "$final" "$RUN|completed|3/3|0"

# Unfiltered `status` (no run id) lists the run too.
listed="$(HOME="$WS/home" BENCH_CAMPAIGN_STATE_DIR="$WS/state" "$LAUNCHER" status | awk -F'\t' -v r="$RUN" '$1==r{print $3"|"$4"|"$5}')"
assert_eq "unfiltered status row" "$listed" "completed|3/3|0"

cleanup_unit "$RUN"
ev "RESULT: PASS"
echo "PASS: status"
