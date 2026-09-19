#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/bench-campaign-test-lib.sh"

GROUP="sut-echo"
EVIDENCE_FILE="$EVIDENCE_DIR/task-16-sut-echo.txt"
: >"$EVIDENCE_FILE"
ev "Task 16 SUT-model echo fixture — $(date +%F)"
ev "Decision (f) wire half: sut-phase runners must echo BENCH_SUT_MODEL=<model>;"
ev "missing marker -> sut-model-echo-missing, mismatch -> sut-model-mismatch."
suite_setup
trap suite_cleanup EXIT
make_workspace sut-echo

# --- Scenario 1: echo matches the manifest model -> case completes ----------
RUN=t16echook
write_manifest "$WS/$RUN.json" "$RUN" \
  'printf "BENCH_SUT_MODEL=fixture-model\n"; exit 0' \
  'replay:sut:family-a:fixture-model:case-1'
launch_campaign "$RUN" "$WS/$RUN.json"
assert_eq "matching echo reaches completed" "$(wait_terminal "$WS/state" "$RUN" 120)" "completed"
assert_eq "matching echo exit is zero" "$(ledger_field "$WS/state" "$RUN" 'd["exitCode"]')" "0"
ev "ok: matching echo accepted"

# --- Scenario 2: echo mismatches -> case fails, campaign stops ---------------
RUN=t16echobad
write_manifest "$WS/$RUN.json" "$RUN" \
  'printf "BENCH_SUT_MODEL=other-model\n"; exit 0' \
  'replay:sut:family-a:fixture-model:case-1'
launch_campaign "$RUN" "$WS/$RUN.json"
assert_eq "mismatched echo terminal status" "$(wait_terminal "$WS/state" "$RUN" 120)" "completed"
assert_eq "mismatched echo exit non-zero" "$(ledger_field "$WS/state" "$RUN" 'd["exitCode"]')" "1"
mismatch_log="$(cat "$WS/out"/cases/*echobad*.stderr.log 2>/dev/null || cat "$WS/out"/cases/*.stderr.log)"
assert_match "mismatch named in stderr" "$mismatch_log" "sut-model-mismatch"
assert_match "mismatch names both models" "$mismatch_log" "other-model"
ev "ok: mismatched echo refused by name"

# --- Scenario 3: no marker at all -> fail-closed -----------------------------
RUN=t16echomissing
write_manifest "$WS/$RUN.json" "$RUN" \
  'exit 0' \
  'replay:sut:family-a:fixture-model:case-1'
launch_campaign "$RUN" "$WS/$RUN.json"
assert_eq "missing echo terminal status" "$(wait_terminal "$WS/state" "$RUN" 120)" "completed"
assert_eq "missing echo exit non-zero" "$(ledger_field "$WS/state" "$RUN" 'd["exitCode"]')" "1"
missing_log="$(cat "$WS/out"/cases/*.stderr.log)"
assert_match "missing marker named in stderr" "$missing_log" "sut-model-echo-missing"
ev "ok: missing marker fail-closed"

cleanup_unit t16echook
cleanup_unit t16echobad
cleanup_unit t16echomissing
ev "RESULT: PASS"
echo "PASS: sut-echo"
