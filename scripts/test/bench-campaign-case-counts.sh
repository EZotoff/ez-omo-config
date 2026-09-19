#!/usr/bin/env bash
# Group 6 — exact final case counts: 3 phases (2+2+1 = 5 cases), one phase's
# runner fails (exit 7). Final ledger must show exactly 5/5 completed with
# exit 1, and per-case results/logs must match the manifest expectation.
set -euo pipefail
. "$(dirname "$0")/bench-campaign-test-lib.sh"

GROUP="case-counts"
EVIDENCE_FILE="$EVIDENCE_DIR/task-11-case-counts.txt"
: >"$EVIDENCE_FILE"
ev "Task 11 case-count fixture — $(date +%F)"
ev "Manifest expectation: 5 cases across 3 phases; fail-phase runner exits 7."
suite_setup
trap suite_cleanup EXIT
make_workspace counts

RUN=t11counts
M_OUT="$WS/$RUN.json" M_RUN="$RUN" M_REPO="$WS/repo" M_OUTDIR="$WS/out" python3 - <<'PY'
import json, os
def phase(pid, kind, cases, shell):
    return {"id": pid, "kind": kind, "processGroup": f"grp-{pid}",
            "endpointFamily": "family-a", "model": "fixture-model",
            "armIds": ["arm-1"], "credentialSources": ["repo-env-local"],
            "expectedCases": cases, "runnerCommand": ["/bin/sh", "-c", shell]}
manifest = {"schemaVersion": 1, "runId": os.environ["M_RUN"],
            "repositoryRoot": os.environ["M_REPO"], "outputDirectory": os.environ["M_OUTDIR"],
            "monitoringOwner": {"name": "t11-fixture", "sessionId": "t11-fixture-session"},
            "quota": {"budgetCases": 7, "headroomPercent": 20},
            "diskThresholdGb": 50, "persistEnvironment": [],
            "arms": [{"id": "arm-1", "sutModel": "fixture-model"}],
            "phases": [
                phase("sut1", "sut", ["a-1", "a-2"], "printf ok"),
                phase("sut2", "sut", ["b-1", "b-2"], "printf ok"),
                phase("judge", "judge", ["j-1"], "exit 7"),
            ]}
with open(os.environ["M_OUT"], "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2); handle.write("\n")
PY

launch_campaign "$RUN" "$WS/$RUN.json"
terminal="$(wait_terminal "$WS/state" "$RUN" 120)"
assert_eq "terminal status (all cases ran despite failures)" "$terminal" "completed"
assert_eq "ledger completedCases" "$(ledger_field "$WS/state" "$RUN" 'd["completedCases"]')" "5"
assert_eq "ledger expectedCases" "$(ledger_field "$WS/state" "$RUN" 'd["expectedCases"]')" "5"
assert_eq "ledger exitCode (one failing phase)" "$(ledger_field "$WS/state" "$RUN" 'd["exitCode"]')" "1"

jsonl_lines="$(wc -l <"$WS/state/$RUN/case-results.jsonl")"
assert_eq "case-results.jsonl record count" "$jsonl_lines" "5"
fail_rows="$(grep -c '"exitCode": 7' "$WS/state/$RUN/case-results.jsonl" || true)"
assert_eq "records with exit 7" "$fail_rows" "1"
per_phase="$(python3 -c 'import json,collections,sys; c=collections.Counter(json.loads(l)["phase"] for l in open(sys.argv[1])); print(dict(sorted(c.items())))' "$WS/state/$RUN/case-results.jsonl")"
assert_eq "per-phase record counts" "$per_phase" "{'judge': 1, 'sut1': 2, 'sut2': 2}"

log_count="$(ls "$WS/out/cases" | wc -l)"
assert_eq "per-case log files (stdout+stderr x 5)" "$log_count" "10"
stems="$(ls "$WS/out/cases" | sed 's/\.\(stdout\|stderr\)\.log$//' | sort -u | wc -l)"
assert_eq "distinct case stems" "$stems" "5"
seq_check="$(ls "$WS/out/cases" | grep -cE '^00[1-5]-' || true)"
assert_eq "sequential case numbering 001-005" "$seq_check" "10"

cleanup_unit "$RUN"
ev "RESULT: PASS"
echo "PASS: case-counts"
