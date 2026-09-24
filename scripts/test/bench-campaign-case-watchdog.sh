#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/bench-campaign-test-lib.sh"

GROUP="case-watchdog"
EVIDENCE_FILE="$EVIDENCE_DIR/task-17-case-watchdog.txt"
: >"$EVIDENCE_FILE"
ev "Task 17 per-case watchdog — $(date +%F)"
ev "A wedged case (BENCH_CASE_TIMEOUT_SEC) must be killed and fail the campaign,"
ev "never hold it forever (observed: silent SSE stall, 33+ min, zero bytes)."
suite_setup
trap suite_cleanup EXIT
make_workspace case-watchdog

# Budget tiny + a runner that sleeps far beyond the watchdog limit.
RUN=t17watchdog
write_manifest "$WS/$RUN.json" "$RUN" 'printf "BENCH_SUT_MODEL=fixture-model\\n"; sleep 999' 'replay:sut:family-a:fixture-model:case-1'
# Tighten the watchdog via the env the launcher reads.
BENCH_CAMPAIGN_STATE_DIR="$WS/state" BENCH_CASE_TIMEOUT_SEC=5 HOME=/home/ezotoff \
  /home/ezotoff/ez-omo-config/scripts/bench-campaign launch "$WS/$RUN.json" >"$WS/launch.log" 2>&1 || true
ev "launch.log: $(tail -2 "$WS/launch.log" 2>/dev/null | tr '\n' ' ')"
assert_eq "watchdog case terminal status" "$(wait_terminal "$WS/state" "$RUN" 120)" "completed"
assert_eq "campaign overall exit non-zero" "$(ledger_field "$WS/state" "$RUN" 'd["exitCode"]')" "1"
assert_eq "killed case records timeout 124" "$(ledger_field "$WS/state" "$RUN" 'd["results"][0]["exitCode"]')" "124"
timeout_log="$(cat "$WS/out"/cases/*.stderr.log)"
ev "stderr tail: $(echo "$timeout_log" | tail -1)"
cleanup_unit t17watchdog
ev "RESULT: PASS"
echo "PASS: case-watchdog"
