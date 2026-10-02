#!/usr/bin/env bash
# rollout-monitor.py ladder semantics — fast-forwarded intervals, fake probes.
set -euo pipefail

DIR="$(mktemp -d /tmp/opencode/rollout-test.XXXXXX)"
trap 'rm -rf "$DIR"' EXIT
CONFIG="$DIR/feature.rollout.json"
PYTHON="${PYTHON:-python3}"
MONITOR="$HOME/ez-omo-config/scripts/rollout-monitor.py"
GAP=1.1   # ladder gap is 1s; --once respects the schedule, so wait it out

touch "$DIR/alive" "$DIR/errors"
EVIDENCE="$DIR/evidence-count"
GATELOG="$DIR/gate-log"
echo 0 > "$EVIDENCE"

cat > "$CONFIG" <<EOF
{
  "feature": "test-feature",
  "ladder": [1, 1, 1, 1],
  "plateau_gap_s": 1,
  "max_ladder_resets": 2,
  "checks": [ {"name": "alive", "cmd": ["test", "-f", "$DIR/alive"] } ],
  "error_tail": {"cmd": ["cat", "$DIR/errors"], "pattern": "ERROR"},
  "evidence": {"cmd": ["cat", "$EVIDENCE"], "min_per_round": [0, 1, 1, 3], "max_extends": 1},
  "gates": [ {"name": "unlock-b", "after_round": 2, "requires": {"min_activations": 3},
              "action": ["sh", "-c", "echo unlock-b >> $GATELOG"] } ],
  "state_path": "$DIR/state.json",
  "log_path": "$DIR/rounds.jsonl"
}
EOF

run_round() { "$PYTHON" "$MONITOR" --config "$CONFIG" --once >/dev/null || true; sleep "$GAP"; }
last_status() { tail -1 "$DIR/rounds.jsonl" | "$PYTHON" -c "import json,sys; print(json.loads(sys.stdin.read())['status'])"; }

# --- Round 0: plain pass (no quota) -> advances to round 1
run_round
grep -q '"round_index": 1' "$DIR/state.json" || { echo "FAIL: round 0 did not advance"; exit 1; }

# --- Round 1: quota 1 with evidence 0 -> extended, then vacuous (max_extends=1) -> advance
run_round
[ "$(last_status)" = "extended" ] || { echo "FAIL: expected extended, got $(last_status)"; exit 1; }
run_round
[ "$(last_status)" = "vacuous" ] || { echo "FAIL: expected vacuous, got $(last_status)"; exit 1; }
grep -q '"round_index": 2' "$DIR/state.json" || { echo "FAIL: vacuous did not advance"; exit 1; }

# --- Evidence 3 -> quota passes; round 2+ evaluates the gate (after_round 2)
echo 3 > "$EVIDENCE"
run_round
grep -q "unlock-b" "$GATELOG" || { echo "FAIL: gate did not fire at round 2 with 3 activations"; exit 1; }
run_round
[ "$(wc -l < "$GATELOG")" -eq 1 ] || { echo "FAIL: gate fired twice (not idempotent)"; exit 1; }

# --- Hard failure: liveness gone -> fail + ladder reset
rm "$DIR/alive"
run_round
grep -q '"round_index": 0' "$DIR/state.json" || { echo "FAIL: failure did not reset ladder"; exit 1; }
grep -q '"ladder_resets": 1' "$DIR/state.json" || { echo "FAIL: reset not counted"; exit 1; }

# --- New error-class lines also fail the round
touch "$DIR/alive"
echo "ERROR: boom" >> "$DIR/errors"
run_round
[ "$(last_status)" = "fail" ] || { echo "FAIL: error tail did not fail round (got $(last_status))"; exit 1; }
: > "$DIR/errors"

# --- Max resets exceeded -> completed/stop signal preserved in state
rm "$DIR/alive"
run_round   # reset 2
run_round   # reset 3 > cap 2 -> stop
grep -q '"completed": true' "$DIR/state.json" || { echo "FAIL: max-resets stop missing"; exit 1; }

# --- Review round fixes (2026-10-02 /review-work): regression coverage ---
DIR2="$(mktemp -d /tmp/opencode/rollout-test.XXXXXX)"
CFG2="$DIR2/cfg.json"
cat > "$CFG2" <<EOF
{
  "feature": "t2",
  "ladder": [1, 1],
  "plateau_gap_s": 1,
  "max_ladder_resets": 5,
  "cmd_timeout_s": 1,
  "checks": [ {"name": "hang", "cmd": ["sleep", "5"] } ],
  "evidence": {"cmd": ["cat", "$DIR2/ev"], "min_per_round": [2, 2], "max_extends": 0},
  "gates": [ {"name": "g-vacuous", "after_round": 0, "requires": {"min_activations": 0},
              "action": ["sh", "-c", "echo fired >> $DIR2/gatelog"] } ],
  "operator_review_rounds": [1],
  "state_path": "$DIR2/state.json",
  "log_path": "$DIR2/rounds.jsonl"
}
EOF
echo 0 > "$DIR2/ev"; : > "$DIR2/gatelog"

# (a) hung check (timeout=1s vs sleep 5) -> recorded FAIL round, monitor exits 1, no crash
RC=0; "$PYTHON" "$MONITOR" --config "$CFG2" --once >/dev/null 2>&1 || RC=$?
[ "$RC" -eq 1 ] || { echo "FAIL: hung check should produce rc 1 (got $RC)"; exit 1; }
tail -1 "$DIR2/rounds.jsonl" | "$PYTHON" -c "import json,sys; d=json.loads(sys.stdin.read()); assert d['status']=='fail' and 'timeout' in d['note'], d" || { echo "FAIL: timeout not recorded as failed round"; exit 1; }

# (b) gate must NOT fire on a vacuous round (quota unmet, evidence 0)
"$PYTHON" "$MONITOR" --config "$CFG2" --once >/dev/null 2>&1 || true; sleep "$GAP"
# round now runs with check passing (swap hang for true), evidence 0 -> vacuous; gate blocked
"$PYTHON" - "$CFG2" <<'PY'
import json,sys
c=json.load(open(sys.argv[1])); c["checks"]=[{"name":"ok","cmd":["true"]}]
json.dump(c,open(sys.argv[1],'w'))
PY
"$PYTHON" "$MONITOR" --config "$CFG2" --once >/dev/null 2>&1 || true; sleep "$GAP"
[ ! -s "$DIR2/gatelog" ] || { echo "FAIL: gate fired on vacuous round"; exit 1; }
tail -1 "$DIR2/rounds.jsonl" | "$PYTHON" -c "import json,sys; d=json.loads(sys.stdin.read()); assert d['status']=='vacuous', d" || { echo "FAIL: expected vacuous"; exit 1; }

# (c) evidence supplied -> pass round 1 fires operator-review marker, then gate fires on PASS round
echo 2 > "$DIR2/ev"
"$PYTHON" "$MONITOR" --config "$CFG2" --once >/dev/null 2>&1; sleep "$GAP"
tail -1 "$DIR2/rounds.jsonl" | "$PYTHON" -c "import json,sys; d=json.loads(sys.stdin.read()); assert d['status']=='pass' and d.get('operator_review') is True, d" || { echo "FAIL: operator_review marker missing"; exit 1; }
grep -q "fired" "$DIR2/gatelog" || { echo "FAIL: gate did not fire on genuine pass"; exit 1; }

# (d) missing binary -> failed round, no crash
"$PYTHON" - "$CFG2" <<'PY'
import json,sys
c=json.load(open(sys.argv[1])); c["checks"]=[{"name":"missing","cmd":["definitely-not-a-binary-x"]}]
json.dump(c,open(sys.argv[1],'w'))
PY
RC=0; "$PYTHON" "$MONITOR" --config "$CFG2" --once >/dev/null 2>&1 || RC=$?
[ "$RC" -eq 1 ] || { echo "FAIL: missing binary should rc 1 (got $RC)"; exit 1; }

# (e) error watermark regression (sliding window) resets silently, no ghost re-count
DIR3="$(mktemp -d /tmp/opencode/rollout-test.XXXXXX)"
printf 'ERROR a\nERROR b\n' > "$DIR3/errs"
cat > "$DIR3/cfg.json" <<EOF
{"feature":"t3","ladder":[1],"plateau_gap_s":1,"max_ladder_resets":9,
 "checks":[{"name":"ok","cmd":["true"]}],
 "error_tail":{"cmd":["cat","$DIR3/errs"],"pattern":"ERROR"},
 "state_path":"$DIR3/state.json","log_path":"$DIR3/rounds.jsonl"}
EOF
"$PYTHON" "$MONITOR" --config "$DIR3/cfg.json" --once >/dev/null 2>&1 || true; sleep "$GAP"  # fail: 2 new
printf 'ERROR a\n' > "$DIR3/errs"  # window slid: 1 match < seen 2 -> reset, 0 new
"$PYTHON" "$MONITOR" --config "$DIR3/cfg.json" --once >/dev/null 2>&1 || { echo "FAIL: watermark regression treated as new errors"; exit 1; }

echo "PASS: rollout-monitor ladder semantics (advance, extend/vacuous, gates, restart-on-error, stop)"
