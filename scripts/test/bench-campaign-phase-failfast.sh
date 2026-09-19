#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/bench-campaign-test-lib.sh"

GROUP="phase-failfast"
EVIDENCE_FILE="$EVIDENCE_DIR/task-11-phase-failfast.txt"
: >"$EVIDENCE_FILE"
ev "Task 11 phase fail-fast fixture — $(date +%F)"
ev "Fixture: replay exits 9; judge would create a marker if incorrectly launched."
suite_setup
trap suite_cleanup EXIT
make_workspace phase-failfast

RUN=t11phasefail
write_manifest "$WS/$RUN.json" "$RUN" \
  "if [ \"\$BENCH_CAMPAIGN_PHASE\" = replay ]; then exit 9; fi; : > \"$WS/judge-ran\"" \
  'replay:sut:family-a:fixture-model:case-1|judge:judge:family-b:fixture-judge:case-1'

launch_campaign "$RUN" "$WS/$RUN.json"
terminal="$(wait_terminal "$WS/state" "$RUN" 120)"
assert_eq "terminal ledger status" "$terminal" "stopped"
assert_eq "only failed replay case recorded" "$(ledger_field "$WS/state" "$RUN" 'd["completedCases"]')" "1"
assert_eq "declared cases remain visible" "$(ledger_field "$WS/state" "$RUN" 'd["expectedCases"]')" "2"
assert_eq "campaign exit is non-zero" "$(ledger_field "$WS/state" "$RUN" 'd["exitCode"]')" "1"
[[ ! -e "$WS/judge-ran" ]] || fail "judge phase ran after replay failure"
ev "ok: judge marker absent after replay failure"
assert_eq "recorded phase" "$(ledger_field "$WS/state" "$RUN" 'd["results"][0]["phase"]')" "replay"

cleanup_unit "$RUN"
ev "RESULT: PASS"
echo "PASS: phase-failfast"
