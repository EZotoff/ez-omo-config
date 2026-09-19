#!/usr/bin/env bash
# Group 7 — schema-rejection matrix: malformed JSON, incomplete manifest,
# mixed endpoint families in one process group, quota violation, bad runId
# pattern, unsupported credential source, SUT model substitution mismatch,
# additional property. Every case must exit 2 with a specific message.
set -euo pipefail
. "$(dirname "$0")/bench-campaign-test-lib.sh"

GROUP="schema-rejection"
EVIDENCE_FILE="$EVIDENCE_DIR/task-11-schema-rejection.txt"
: >"$EVIDENCE_FILE"
ev "Task 11 schema-rejection matrix — $(date +%F)"
suite_setup
trap suite_cleanup EXIT
make_workspace schema

reject_check() { # name path message-fragment
  local name="$1" path="$2" fragment="$3" rc out
  set +e
  "$LAUNCHER" --validate-manifest "$path" >"$WS/$name.out" 2>"$WS/$name.err"
  rc=$?
  set -e
  assert_eq "$name exit code" "$rc" "2"
  assert_match "$name message" "$(cat "$WS/$name.err")" "$fragment"
}

# malformed JSON
printf '{"runId": oops\n' >"$WS/malformed.json"
reject_check malformed "$WS/malformed.json" "invalid JSON"

# valid base manifest (same shape as the mixed-family shipped fixture)
BASE="$WS/base.json"
M_OUT="$BASE" M_RUN="t11schema" M_REPO="$WS/repo" M_OUTDIR="$WS/out" python3 - <<'PY'
import json, os
manifest = {"schemaVersion": 1, "runId": "t11schema",
            "repositoryRoot": os.environ["M_REPO"], "outputDirectory": os.environ["M_OUTDIR"],
            "monitoringOwner": {"name": "t11", "sessionId": "t11"},
            "quota": {"budgetCases": 20, "headroomPercent": 20},
            "diskThresholdGb": 50, "persistEnvironment": [],
            "arms": [{"id": "arm-1", "sutModel": "fixture-model"}],
            "phases": [{"id": "sut", "kind": "sut", "processGroup": "grp-sut",
                        "endpointFamily": "family-a", "model": "fixture-model",
                        "armIds": ["arm-1"], "credentialSources": ["repo-env-local"],
                        "expectedCases": ["case-1"],
                        "runnerCommand": ["/bin/true"]}]}
with open(os.environ["M_OUT"], "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2); handle.write("\n")
PY

mutate() { # out-path python-statement
  M_BASE="$BASE" M_DST="$1" M_STMT="$2" python3 - <<'PY'
import json, os
with open(os.environ["M_BASE"], encoding="utf-8") as h: m = json.load(h)
exec(os.environ["M_STMT"])
with open(os.environ["M_DST"], "w", encoding="utf-8") as h:
    json.dump(m, h, indent=2); h.write("\n")
PY
}

# incomplete: missing required property
mutate "$WS/incomplete.json" 'del m["diskThresholdGb"]'
reject_check incomplete "$WS/incomplete.json" "missing required property diskThresholdGb"

# mixed endpoint families in one process group (shipped fixture + generated)
reject_check mixed-family-shipped \
  /home/ezotoff/ez-omo-config/scripts/bench-campaign-fixtures/mixed-family-single-process.json \
  "mixes endpoint families"
mutate "$WS/mixed.json" 'm["phases"].append({"id":"j","kind":"judge","processGroup":"grp-sut","endpointFamily":"family-b","model":"fixture-model","armIds":["arm-1"],"credentialSources":["repo-env-local"],"expectedCases":["c"],"runnerCommand":["/bin/true"]})'
reject_check mixed-family-generated "$WS/mixed.json" "mixes endpoint families"

# quota violation: 2 cases, budget 2 with 20% headroom admits 1
mutate "$WS/quota.json" 'm["quota"]["budgetCases"] = 2; m["phases"][0]["expectedCases"] = ["case-1","case-2"]'
reject_check quota "$WS/quota.json" "quota violation"

# bad runId pattern
mutate "$WS/runid.json" 'm["runId"] = "Bad_Run"'
reject_check runid-pattern "$WS/runid.json" "schema violation"

# unsupported credential source
mutate "$WS/creds.json" 'm["phases"][0]["credentialSources"] = ["web-search"]'
reject_check credential-source "$WS/creds.json" "schema violation"

# SUT substitution mismatch: phase model != arm sutModel
mutate "$WS/sut.json" 'm["phases"][0]["model"] = "other-model"'
reject_check sut-substitution "$WS/sut.json" "SUT substitution is invalid"

# additional property
mutate "$WS/extra.json" 'm["surprise"] = True'
reject_check additional-property "$WS/extra.json" "additional property"

# control: the unmutated base validates (exit 0) so rejections are meaningful
"$LAUNCHER" --validate-manifest "$BASE" >/dev/null 2>&1 || fail "base manifest stopped validating"
ev "ok: base manifest still validates (control)"
ev "RESULT: PASS"
echo "PASS: schema-rejection"
