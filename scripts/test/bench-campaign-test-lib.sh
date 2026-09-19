# bench-campaign-test-lib.sh — shared helpers for the bench-campaign fixture
# suite (task 11). Sourced by each group script, never executed directly.
#
# Hermetic contract: every group runs against its own isolated HOME, state
# dir, repository root, and output dir under a mktemp workspace. Fake runners
# only (printf/sleep/true/exit) — no network, no LLM, no real credentials.
# bench-campaign-* units created here are stopped, reset-failed, and verified
# absent before the group exits; the workspace is removed on exit.

LAUNCHER="${BENCH_CAMPAIGN_LAUNCHER:-/home/ezotoff/ez-omo-config/scripts/bench-campaign}"
EVIDENCE_DIR="${BENCH_CAMPAIGN_EVIDENCE_DIR:-/home/ezotoff/AI_projects/veran/.sisyphus/evidence}"
WORK_ROOT=""
WS=""
GROUP=""

suite_setup() {
  WORK_ROOT="$(mktemp -d /tmp/bench-campaign-t11-XXXXXX)"
  chmod 700 "$WORK_ROOT"
}

ev() { printf '%s\n' "$*" >>"$EVIDENCE_FILE"; }

fail() {
  ev "RESULT: FAIL — $*"
  echo "FAIL: ${GROUP:-?} — $*" >&2
  exit 1
}

assert_eq() { # label got want
  [[ "$2" == "$3" ]] || fail "$1: got '$2' want '$3'"
  ev "ok: $1 = '$2'"
}

assert_match() { # label haystack needle
  [[ "$2" == *"$3"* ]] || fail "$1: no match for '$3' in: ${2:0:400}"
  ev "ok: $1 matched '$3'"
}

assert_no_match() { # label haystack needle
  [[ "$2" != *"$3"* ]] || fail "$1: forbidden match for '$3' in: ${2:0:400}"
  ev "ok: $1 absent: '$3'"
}

# make_workspace <name>: sets WS with isolated home/state/repo/out.
# The fake repo carries an empty apps/web/.env.local so the repo-env-local
# credential source is satisfiable without any real secret.
make_workspace() {
  WS="$WORK_ROOT/$1"
  mkdir -p "$WS/home/.local/share/opencode" "$WS/state" "$WS/out/cases" "$WS/repo/apps/web"
  : >"$WS/repo/apps/web/.env.local"
  chmod 700 "$WS/home" "$WS/state" "$WS/out"
}

# write_manifest <path> <runId> <runner-shell-string> <phase:case,case|...>
# Phases share process group per-phase uniqueness not required here; every
# phase gets its own processGroup so endpoint-family mixing is never tripped.
# Phase spec item: id:kind:family:model:case1,case2  (credentialSources: repo-env-local)
write_manifest() {
  local path="$1" run_id="$2" runner="$3" phases="$4"
  M_OUT="$path" M_RUN="$run_id" M_RUNNER="$runner" M_PHASES="$phases" \
  M_REPO="$WS/repo" M_OUTDIR="$WS/out" python3 - <<'PY'
import json, os
phases = []
for item in os.environ["M_PHASES"].split("|"):
    pid, kind, family, model, cases = item.split(":")
    phases.append({
        "id": pid, "kind": kind, "processGroup": f"grp-{pid}",
        "endpointFamily": family, "model": model, "armIds": ["arm-1"],
        "credentialSources": ["repo-env-local"],
        "expectedCases": cases.split(","),
        "runnerCommand": ["/bin/sh", "-c", os.environ["M_RUNNER"]],
    })
manifest = {
    "schemaVersion": 1, "runId": os.environ["M_RUN"],
    "repositoryRoot": os.environ["M_REPO"],
    "outputDirectory": os.environ["M_OUTDIR"],
    "monitoringOwner": {"name": "t11-fixture", "sessionId": "t11-fixture-session"},
    "quota": {"budgetCases": 20, "headroomPercent": 20},
    "diskThresholdGb": 50, "persistEnvironment": [],
    "arms": [{"id": "arm-1", "sutModel": "fixture-model"}],
    "phases": phases,
}
with open(os.environ["M_OUT"], "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2)
    handle.write("\n")
PY
}

# SUT phases must have model == arm sutModel; default spec uses fixture-model.
launch_campaign() { # run_id manifest
  HOME="$WS/home" BENCH_CAMPAIGN_STATE_DIR="$WS/state" "$LAUNCHER" launch "$2" \
    || fail "launcher exited non-zero for $1"
}

unit_name() { printf 'bench-campaign-%s.service' "$1"; }

# cleanup_unit <run-id> — stop, reset-failed, verify absence; receipt to evidence.
cleanup_unit() {
  local u receipt
  u="$(unit_name "$1")"
  systemctl --user stop "$u" >/dev/null 2>&1 || true
  systemctl --user reset-failed "$u" >/dev/null 2>&1 || true
  receipt="$(systemctl --user list-units 'bench-campaign-*' --all --no-legend | grep -F "$u" || true)"
  [[ -z "$receipt" ]] || fail "cleanup: unit $u still listed after stop+reset-failed"
  ev "cleanup receipt: $u stopped, reset-failed, verified absent from list-units"
}

ledger_field() { # state-dir run-id python-expr-over-d
  python3 -c 'import json,os,sys; d=json.load(open(os.path.join(sys.argv[1],sys.argv[2],"ledger.json"))); print(eval(sys.argv[3]))' \
    "$1" "$2" "$3"
}

wait_terminal() { # state-dir run-id timeout-seconds -> prints terminal status
  local deadline=$((SECONDS + ${3:-120})) status=""
  while (( SECONDS < deadline )); do
    if [[ -s "$1/$2/ledger.json" ]]; then
      status="$(ledger_field "$1" "$2" 'd["status"]')"
      [[ "$status" == completed || "$status" == stopped ]] && { printf '%s' "$status"; return 0; }
    fi
    sleep 1
  done
  fail "campaign $2 did not reach a terminal ledger status within ${3:-120}s (last: '$status')"
}

suite_cleanup() {
  if [[ -n "$WORK_ROOT" && -e "$WORK_ROOT" ]]; then
    rm -rf "$WORK_ROOT"
    [[ ! -e "$WORK_ROOT" ]] || { echo "WARN: workspace $WORK_ROOT not removed" >&2; return; }
    ev "cleanup receipt: workspace $WORK_ROOT removed and absence verified"
  fi
}
