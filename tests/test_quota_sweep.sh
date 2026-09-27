#!/usr/bin/env bash
set -euo pipefail

# test_quota_sweep.sh — tests for the quota-opportunistic sweep.
#
# Covers (with an injectable fake quota probe + fake analyst):
#   1. Out-of-window reset (>120 min)  -> no-op, ledger untouched
#   2. Window about to close (<30 min) -> no-op
#   3. Usage at/above ceiling          -> no-op
#   4. Probe failure                   -> no-op (fail-safe)
#   5. In-window                       -> parallel batch runs, wave sizing,
#      ledger rows written under concurrency, candidates ranked + written
#      through wisdom-closeout --no-supersede (temp-HOME hermetic store)
#
# The real quotas.sh is never called; the real DB is only read.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EXTRACT="$REPO_ROOT/scripts/session-learning/extract-digest.py"

TMP="$(mktemp -d /tmp/opencode/quota-sweep-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok: $1"; }

NOW_MS="$(python3 -c 'import time; print(int(time.time() * 1000))')"

# ---------------------------------------------------------------- fixtures

FIXTURE_DB="$TMP/fixture.db"
python3 - "$FIXTURE_DB" "$NOW_MS" <<'PYEOF'
import json
import sqlite3
import sys

db_path, now_ms = sys.argv[1], int(sys.argv[2])
db = sqlite3.connect(db_path)
db.executescript(
    """
    CREATE TABLE session (
        id TEXT PRIMARY KEY, parent_id TEXT, directory TEXT, title TEXT,
        time_created TEXT, time_updated TEXT, time_archived TEXT,
        agent TEXT, model TEXT
    );
    CREATE TABLE message (
        id TEXT PRIMARY KEY, session_id TEXT, time_created TEXT, data TEXT
    );
    CREATE TABLE part (
        id TEXT PRIMARY KEY, session_id TEXT, message_id TEXT,
        time_created TEXT, data TEXT
    );
    """
)
for n in range(4):
    sid = f"qs_{n}"
    created = now_ms - 7200_000
    updated = now_ms - 2 * 86400_000
    db.execute(
        "INSERT INTO session VALUES (?,?,?,?,?,?,?,?,?)",
        (sid, None, "/proj", f"quota fixture {n}", str(created), str(updated), None, "Sisyphus", "{}"),
    )
    for i in range(45):  # qualify via messages>=40
        mid = f"m_{sid}_{i}"
        db.execute(
            "INSERT INTO message VALUES (?,?,?,?)",
            (mid, sid, str(created + i * 1000), json.dumps({"role": "user" if i % 2 == 0 else "assistant"})),
        )
        db.execute(
            "INSERT INTO part VALUES (?,?,?,?,?)",
            (f"p_{mid}", sid, mid, str(created + i * 1000),
             json.dumps({"type": "text", "text": f"turn {i}"})),
        )
db.commit()
PYEOF

# Fake analyst: emits a valid single-candidate JSON response.
FAKE_ANALYST="$TMP/fake-analyst.sh"
cat > "$FAKE_ANALYST" <<EOF
#!/usr/bin/env bash
sleep 0.3
cat <<'JSON'
{"session_id": "x", "obligations": [], "candidates": [{"route": "wisdom", "type": "fact", "scope": "system", "claim": "Fixture learning from $RANDOM", "evidence": "digest quote", "confidence": "high", "relationship": "new", "existing_match": null}]}
JSON
EOF
chmod +x "$FAKE_ANALYST"

# Fake quota probe: writes state from env, emits quotas.sh --json shape.
FAKE_PROBE="$TMP/fake-probe.sh"
cat > "$FAKE_PROBE" <<'EOF'
#!/usr/bin/env bash
python3 - <<PYEOF
import json, time
used = int("${QUSED:-16}")
reset_min = float("${QRESET_MIN:-60}")
print(json.dumps({"providers": [{"providerId": "zai-coding-plan", "windows": [
    {"id": "5h", "usedPercent": used, "resetsAtMs": int((time.time() + reset_min * 60) * 1000)}
]}]}))
PYEOF
EOF
chmod +x "$FAKE_PROBE"

run_sweep() { # extra flags...
    local ledger="$TMP/ledger-$RANDOM.jsonl"
    : > "$ledger"
    python3 "$EXTRACT" quota-sweep \
        --db "$FIXTURE_DB" --ledger "$ledger" \
        --state-dir "$TMP/state-$RANDOM" --workdir "$TMP/work" \
        --log "$TMP/quota.log" --probe-cmd "$FAKE_PROBE" \
        --analyst-cmd "$FAKE_ANALYST" --concurrency 4 --max-batch 10 \
        --window-min-min 30 --window-min-max 120 --usage-ceiling 90 \
        --global-cap 12 --per-session-cap 2 "$@"
}

# Hermetic wisdom store for write tests
export QTHOME="$TMP/home"
mkdir -p "$QTHOME"

# ---------------------------------------------------------------- 1-4: no-op windows

QRESET_MIN=200 run_sweep > "$TMP/out1.txt"
grep -q "no window" "$TMP/out1.txt" || fail "reset 200min should be a no-op"
ok "out-of-window (>120min) no-op"

QRESET_MIN=15 run_sweep > "$TMP/out2.txt"
grep -q "no window" "$TMP/out2.txt" || fail "reset 15min should be a no-op"
ok "closing window (<30min) no-op"

QRESET_MIN=60 QUSED=95 run_sweep > "$TMP/out3.txt"
grep -q "no window" "$TMP/out3.txt" || fail "usage 95% should be a no-op"
ok "usage ceiling no-op"

FAKE_PROBE_BROKEN="$TMP/broken-probe.sh"
printf '#!/usr/bin/env bash\necho "not json"\n' > "$FAKE_PROBE_BROKEN"; chmod +x "$FAKE_PROBE_BROKEN"
python3 "$EXTRACT" quota-sweep --db "$FIXTURE_DB" --state-dir "$TMP/s-broken" --workdir "$TMP/w-broken" \
    --log "$TMP/q-broken.log" --probe-cmd "$FAKE_PROBE_BROKEN" > "$TMP/out4.txt"
grep -q "no window" "$TMP/out4.txt" || fail "broken probe should be a no-op"
ok "probe failure fail-safe"

# ---------------------------------------------------------------- 5: in-window run

HOME="$QTHOME" QRESET_MIN=90 QUSED=40 run_sweep > "$TMP/out5.txt"
grep -q "window active" "$TMP/out5.txt" || { cat "$TMP/out5.txt"; fail "in-window run did not activate"; }
grep -q "quota-sweep: done\|quota-sweep launched=" "$TMP/out5.txt" || fail "run did not complete"
grep -q "launched=4" "$TMP/out5.txt" || { cat "$TMP/out5.txt"; fail "expected 4 sessions launched"; }
ok "in-window batch ran (4 sessions, concurrency 4)"

# Ledger: all 4 analyzed, JSONL intact under concurrency
LEDGER="$(ls -t "$TMP"/ledger-*.jsonl | head -1)"
N_ANALYZED=$(jq -r 'select(.status=="analyzed") | .session_id' "$LEDGER" | wc -l)
[ "$N_ANALYZED" -eq 4 ] || fail "expected 4 analyzed ledger rows, got $N_ANALYZED"
python3 - "$LEDGER" <<'PYEOF'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
ids = [r["session_id"] for r in rows]
assert len(ids) == len(set(ids)), f"duplicate ledger rows: {ids}"
for r in rows:
    assert r["status"] == "analyzed", r
    assert r["digest_sha256"], r
print("ok: ledger consistent under concurrency (4 unique analyzed rows)")
PYEOF

# Wisdom writes happened in the hermetic store (with HOME override the closeout
# script derives $QTHOME/.sisyphus/wisdom) — rerun with store inspection
STORE="$QTHOME/.sisyphus/wisdom/system.jsonl"
if [ -f "$STORE" ]; then
    N=$(jq -r 'select(.provenance=="closeout") | select(.source=="closeout:quota-sweep") | .id' "$STORE" | wc -l)
    [ "$N" -ge 1 ] || fail "expected quota-sweep wisdom entries in hermetic store"
    ok "quota-sweep wrote $N entries via wisdom-closeout (no-supersede)"
else
    fail "hermetic wisdom store missing"
fi

# ---------------------------------------------------------------- regression: analyst-cmd default

# 2026-09-27 incident: the --analyst-cmd default was \"opencode\" (missing the
# `run` subcommand), so every analyst invocation printed the root help and
# exited 1 — 35 silent analyst_failed rows before diagnosis. Guard the default.
grep -q 'analyst-cmd\", default=\"opencode run\"' "$EXTRACT" \
    || fail "analyst-cmd default lost the 'run' subcommand (2026-09-27 regression)"
ok "analyst-cmd default is 'opencode run' (regression guard)"
echo "PASS: quota-sweep tests"
