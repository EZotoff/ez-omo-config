#!/usr/bin/env bash
# Group 2 — canary-secret absence: fake credentials planted in the two named
# credential sources must never reach manifests, case logs, the journal,
# systemctl show output, or any process arguments. Runner prints nothing from
# the environment, so any canary hit is a launcher leak by construction.
set -euo pipefail
. "$(dirname "$0")/bench-campaign-test-lib.sh"

GROUP="canary"
EVIDENCE_FILE="$EVIDENCE_DIR/task-11-canary.txt"
: >"$EVIDENCE_FILE"
ev "Task 11 canary-secret fixture — $(date +%F)"
ev "Fake credentials only (T11CANARYAUTH / T11CANARYREPO); runner prints nothing from env."
suite_setup
trap suite_cleanup EXIT
make_workspace canary

RUN=t11canary
printf '{"access_token":"T11CANARYAUTH","refresh_token":"T11CANARYAUTH"}\n' \
  >"$WS/home/.local/share/opencode/auth.json"
printf 'T11_REPO_SECRET=T11CANARYREPO\nOTHER=dummy\n' >>"$WS/repo/apps/web/.env.local"

# judge phase pulls opencode-auth; sut pulls repo-env-local.
M_OUT="$WS/$RUN.json" M_RUN="$RUN" M_REPO="$WS/repo" M_OUTDIR="$WS/out" python3 - <<'PY'
import json, os
phases = [
    {"id": "sut", "kind": "sut", "processGroup": "grp-sut", "endpointFamily": "family-a",
     "model": "fixture-model", "armIds": ["arm-1"], "credentialSources": ["repo-env-local"],
     "expectedCases": ["case-1", "case-2"],
     "runnerCommand": ["/bin/sh", "-c", "sleep 4; printf case-done"]},
    {"id": "judge", "kind": "judge", "processGroup": "grp-judge", "endpointFamily": "family-b",
     "model": "fixture-model", "armIds": ["arm-1"], "credentialSources": ["opencode-auth"],
     "expectedCases": ["case-1"],
     "runnerCommand": ["/bin/sh", "-c", "sleep 4; printf judged-done"]},
]
manifest = {"schemaVersion": 1, "runId": os.environ["M_RUN"],
            "repositoryRoot": os.environ["M_REPO"], "outputDirectory": os.environ["M_OUTDIR"],
            "monitoringOwner": {"name": "t11-fixture", "sessionId": "t11-fixture-session"},
            "quota": {"budgetCases": 20, "headroomPercent": 20},
            "diskThresholdGb": 50, "persistEnvironment": [],
            "arms": [{"id": "arm-1", "sutModel": "fixture-model"}], "phases": phases}
with open(os.environ["M_OUT"], "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2); handle.write("\n")
PY

launch_campaign "$RUN" "$WS/$RUN.json"
U="$(unit_name "$RUN")"
sleep 1
[[ "$(systemctl --user is-active "$U" 2>/dev/null || true)" == active ]] || fail "unit not active during run"

for canary in T11CANARYAUTH T11CANARYREPO; do
  assert_no_match "owned manifest copy" "$(cat "$WS/state/$RUN/manifest.json")" "$canary"
  assert_no_match "resolved manifest" "$(cat "$WS/state/$RUN/resolved-manifest.json")" "$canary"
  assert_no_match "journal" "$(journalctl --user -u "$U" --no-pager 2>/dev/null || true)" "$canary"
  assert_no_match "systemctl show" "$(systemctl --user show "$U" 2>/dev/null || true)" "$canary"
  assert_no_match "live process args" "$(ps -eo args= 2>/dev/null || true)" "$canary"
done

terminal="$(wait_terminal "$WS/state" "$RUN" 180)"
assert_eq "final ledger status" "$terminal" "completed"
for canary in T11CANARYAUTH T11CANARYREPO; do
  logs="$(grep -r "$canary" "$WS/out" 2>/dev/null || true)"
  assert_eq "canary in case logs after completion" "$logs" ""
done
ev "canaries absent from: owned manifest, resolved manifest, case logs, journal, systemctl show, process args"

cleanup_unit "$RUN"
ev "RESULT: PASS"
echo "PASS: canary"
