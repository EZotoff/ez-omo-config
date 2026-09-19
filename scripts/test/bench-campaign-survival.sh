#!/usr/bin/env bash
# Group 1 — shell-exit survival: the launcher exits 0 immediately while the
# transient unit keeps running; the campaign completes on its own.
set -euo pipefail
. "$(dirname "$0")/bench-campaign-test-lib.sh"

GROUP="survival"
EVIDENCE_FILE="$EVIDENCE_DIR/task-11-survival.txt"
: >"$EVIDENCE_FILE"
ev "Task 11 survival fixture — $(date +%F)"
ev "Fixture: sleep-based local runner; no network, no LLM calls."
suite_setup
trap suite_cleanup EXIT
make_workspace survival

RUN=t11surv
write_manifest "$WS/$RUN.json" "$RUN" 'sleep 3; printf survivor' \
  'sut:sut:family-a:fixture-model:case-1,case-2'

launch_campaign "$RUN" "$WS/$RUN.json"
ev "launcher exit: 0; run id: $RUN"

U="$(unit_name "$RUN")"
sleep 1
active="$(systemctl --user is-active "$U" 2>/dev/null || true)"
assert_eq "unit active after launcher shell exited" "$active" "active"

mid="$(HOME="$WS/home" BENCH_CAMPAIGN_STATE_DIR="$WS/state" "$LAUNCHER" status "$RUN" | awk -F'\t' 'NR==2{print $3"/"$4"/"$5}')"
ev "status while running: $mid"

terminal="$(wait_terminal "$WS/state" "$RUN" 120)"
assert_eq "final ledger status" "$terminal" "completed"
assert_eq "final completedCases" "$(ledger_field "$WS/state" "$RUN" 'd["completedCases"]')" "2"
assert_eq "final expectedCases" "$(ledger_field "$WS/state" "$RUN" 'd["expectedCases"]')" "2"
assert_eq "final exitCode" "$(ledger_field "$WS/state" "$RUN" 'd["exitCode"]')" "0"

stdout_hits="$(grep -l survivor "$WS/out"/cases/*.stdout.log | wc -l)"
assert_eq "case stdout logs carrying runner output" "$stdout_hits" "2"
log_modes="$(stat -c '%a' "$WS/out"/cases/*.*.log | sort -u | tr '\n' ' ')"
assert_eq "case log modes" "$log_modes" "600 "

final="$(HOME="$WS/home" BENCH_CAMPAIGN_STATE_DIR="$WS/state" "$LAUNCHER" status "$RUN" | awk -F'\t' 'NR==2{print $3"/"$4"/"$5}')"
assert_eq "status line after completion" "$final" "completed/2/2/0"

cleanup_unit "$RUN"
ev "RESULT: PASS"
echo "PASS: survival"
