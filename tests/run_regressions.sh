#!/usr/bin/env bash
set -o errexit
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGRESSIONS_DIR="$SCRIPT_DIR/regressions"
TOTAL_PASS=0; TOTAL_FAIL=0; KILL_PASS=0; KILL_FAIL=0
for test_file in "$REGRESSIONS_DIR"/*.sh; do
    [[ -f "$test_file" ]] || continue
    [[ "$test_file" == *.kill.sh ]] && continue
    if bash "$test_file" >/dev/null 2>&1; then TOTAL_PASS=$((TOTAL_PASS+1)); else TOTAL_FAIL=$((TOTAL_FAIL+1)); fi
done
for kill_file in "$REGRESSIONS_DIR"/*.kill.sh; do
    [[ -f "$kill_file" ]] || continue
    if bash "$kill_file" >/dev/null 2>&1; then KILL_PASS=$((KILL_PASS+1)); else KILL_FAIL=$((KILL_FAIL+1)); fi
done
echo "Tests: $TOTAL_PASS passed | $TOTAL_FAIL failed"
echo "Kill-tests: $KILL_PASS proved | $KILL_FAIL broken"
[[ $KILL_FAIL -gt 0 ]] && { echo "FAILURE: kill-tests broken"; exit 1; }
[[ $TOTAL_FAIL -gt 0 ]] && { echo "EXPECTED RED: script not rewritten yet"; exit 1; }
exit 0
