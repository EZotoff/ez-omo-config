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

echo "PASS: rollout-monitor ladder semantics (advance, extend/vacuous, gates, restart-on-error, stop)"
