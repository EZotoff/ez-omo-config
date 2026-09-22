#!/usr/bin/env bash
set -euo pipefail

# test_session_learning.sh — tests for the nightly session-learning sweep.
#
# Covers:
#   1. Eligibility selection (trivial exclusion, thresholds, staleness, watermark)
#   2. Fork dedup
#   3. Digest extraction from a fixture DB (fields, units, errors)
#   4. Digest-recall validation on the 3 audited real sessions (binding gate)
#   5. Candidate ranking (duplicate drop, per-session cap, global cap)
#   6. wisdom-closeout.sh --no-supersede (hermetic temp-HOME wisdom store)
#   7. Dry-run sweep orchestration on a fixture DB
#
# Read-only with respect to the real wisdom store and real session DB.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EXTRACT="$REPO_ROOT/scripts/session-learning/extract-digest.py"
CLOSEOUT="$REPO_ROOT/scripts/wisdom/wisdom-closeout.sh"

TMP="$(mktemp -d /tmp/opencode/session-learning-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { PASS=$((PASS + 1)); echo "ok: $1"; }

assert_contains() { # haystack_file needle label
    if grep -qi "$2" "$1"; then ok "$3"; else fail "$3 (missing: $2)"; fi
}

NOW_MS="$(python3 -c 'import time; print(int(time.time() * 1000))')"
OLD_MS="$(python3 -c "import time; print(int(time.time() * 1000) - 2 * 86400 * 1000)")"

# ---------------------------------------------------------------- fixture DB

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
seq = [0]

def add_session(sid, msgs, directory="/proj", title="t", created=None, updated=None, tools=None):
    created = created if created is not None else now_ms - 86400_000
    updated = updated if updated is not None else now_ms - 2 * 86400_000
    db.execute(
        "INSERT INTO session VALUES (?,?,?,?,?,?,?,?,?)",
        (sid, None, directory, title, str(created), str(updated), None, "Sisyphus", "{}"),
    )
    for i in range(msgs):
        seq[0] += 1
        mid = f"m_{sid}_{i}"
        role = "user" if i % 2 == 0 else "assistant"
        db.execute(
            "INSERT INTO message VALUES (?,?,?,?)",
            (mid, sid, str(created + i * 1000), json.dumps({"role": role})),
        )
        db.execute(
            "INSERT INTO part VALUES (?,?,?,?,?)",
            (f"p_{mid}", sid, mid, str(created + i * 1000),
             json.dumps({"type": "text", "text": f"turn {i} filler"})),
        )
        if tools and i in tools:
            state = tools[i]
            db.execute(
                "INSERT INTO part VALUES (?,?,?,?,?)",
                (f"t_{mid}", sid, mid, str(created + i * 1000),
                 json.dumps({"type": "tool", "tool": "bash", "state": state})),
            )

add_session("s_trivial", 10)
add_session("s_big", 45)
add_session("s_dur", 25, created=now_ms - 9 * 3600_000, updated=now_ms - 7 * 3600_000)
sig_tools = {}
for j in range(16):
    sig_tools[j * 2] = {
        "input": {"command": f"make check {j}"},
        "metadata": {"output": f"error: module{j} failed", "exit": 1},
    }
add_session("s_sig", 20, tools=sig_tools)
fork_base = (now_ms // 3_600_000) * 3_600_000 - 3_600_000  # fully inside the previous hour bucket
add_session("s_fork_a", 60, created=fork_base + 1_000, updated=now_ms - 2 * 86400_000)
add_session("s_fork_b", 50, created=fork_base + 50_000, updated=now_ms - 2 * 86400_000)
add_session("s_processed", 50)
add_session("s_active", 50, created=now_ms - 3600_000, updated=now_ms - 60_000)

# A digest fixture with known payload
digest_tools = {
    0: {
        "input": {"command": "systemd-run --unit=bench-campaign ./run.sh"},
        "metadata": {"output": "ok", "exit": 0},
    },
    2: {
        "input": {"command": "btop --utf-force"},
        "metadata": {"output": "error: NVML glibc dlopen failed (musl build)", "exit": 1},
    },
}
add_session(
    "s_digest", 6, created=now_ms - 7200_000, updated=now_ms - 2 * 86400_000,
    tools=digest_tools,
)
db.execute(
    "UPDATE part SET data=? WHERE id='p_m_s_digest_1'",
    (json.dumps({"type": "text", "text": "the musl btop binary cannot load NVML"}),),
)
db.commit()
PYEOF

LEDGER="$TMP/ledger.jsonl"
cat > "$LEDGER" <<EOF
{"session_id": "s_processed", "last_time_updated": $NOW_MS, "status": "analyzed", "candidate_ids": [], "attempts": 1}
EOF

# ---------------------------------------------------------------- 1+2: select

SELECT_OUT="$TMP/select.jsonl"
python3 "$EXTRACT" select --db "$FIXTURE_DB" --ledger "$LEDGER" --stale-hours 6 --limit 10 > "$SELECT_OUT"

grep -q '"s_trivial"' "$SELECT_OUT" && fail "trivial session must be excluded"
ok "trivial exclusion"
for sid in s_big s_dur s_sig; do
    grep -q "\"$sid\"" "$SELECT_OUT" || fail "expected $sid selected"
done
ok "threshold qualifications (messages / duration / signals)"
grep -q '"s_active"' "$SELECT_OUT" && fail "active session must be excluded by staleness"
ok "staleness gate"
grep -q '"s_processed"' "$SELECT_OUT" && fail "watermarked session must be skipped"
ok "watermark skip"
grep -q '"s_fork_a".*"covered_by": null' "$SELECT_OUT" || grep -q '"session_id": "s_fork_a", .*"covered_by": null' "$SELECT_OUT" || true
python3 - "$SELECT_OUT" <<'PYEOF'
import json, sys
rows = {json.loads(l)["session_id"]: json.loads(l) for l in open(sys.argv[1]) if l.strip()}
assert "s_fork_a" in rows and "s_fork_b" in rows, rows.keys()
assert rows["s_fork_a"]["covered_by"] is None, rows["s_fork_a"]
assert rows["s_fork_b"]["covered_by"] == "s_fork_a", rows["s_fork_b"]
print("ok: fork dedup (canonical kept, fork covered)")
PYEOF

# ---------------------------------------------------------------- 3: digest

DIGEST_OUT="$TMP/digest.json"
python3 "$EXTRACT" digest --db "$FIXTURE_DB" --session s_digest --out "$DIGEST_OUT"
python3 - "$DIGEST_OUT" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["launched_units"] == ["bench-campaign"], d["launched_units"]
assert d["error_tool_calls"] >= 1
assert any("NVML" in e["output"] for e in d["tool_errors"])
assert any("musl btop" in f["text"] for f in d["assistant_finals"])
print("ok: digest extraction (units, errors, user text)")
PYEOF

# ---------------------------------------------------------------- 4: recall

RECALL_IDS=(
    "ses_f424ea75affeSBlCIHN92vhrlv:btop nvml musl alacritty"
    "ses_f4c0bcb2bffezZ3HykoshHQv5t:llama-swap litellm llama-server vram"
    "ses_f497db5c7ffeSx2N7nGOixtQtY:oren deepseek-flash kimi ollama benchmark"
)
for entry in "${RECALL_IDS[@]}"; do
    sid="${entry%%:*}"
    keywords="${entry#*:}"
    out="$TMP/recall_$sid.json"
    if ! python3 "$EXTRACT" digest --session "$sid" --out "$out" 2>/dev/null; then
        fail "recall: digest failed for $sid (real DB unreadable?)"
    fi
    hits=0
    for kw in $keywords; do
        grep -qi "$kw" "$out" && hits=$((hits + 1))
    done
    if [ "$hits" -ge 2 ]; then
        ok "digest recall $sid ($hits keywords)"
    else
        fail "digest recall $sid: only $hits keyword hits (digest too lossy)"
    fi
done

# ---------------------------------------------------------------- 5: rank

CANDS="$TMP/cands.jsonl"
cat > "$CANDS" <<'EOF'
{"session_id": "A", "candidates": [{"route": "wisdom", "type": "gotcha", "claim": "A1 high evidence", "evidence": "quote", "confidence": "high", "relationship": "new"}, {"route": "wisdom", "type": "fact", "claim": "A2 high no evidence", "evidence": "", "confidence": "high", "relationship": "new"}, {"route": "wisdom", "type": "fact", "claim": "A3 medium", "evidence": "q", "confidence": "medium", "relationship": "new"}, {"route": "wisdom", "type": "fact", "claim": "A4 dup", "evidence": "q", "confidence": "high", "relationship": "duplicate"}, {"route": "none", "type": "fact", "claim": "A5 none", "evidence": "", "confidence": "high", "relationship": "new"}]}
{"session_id": "B", "candidates": [{"route": "proposal", "proposal_kind": "policy", "type": "decision", "claim": "B1 policy proposal", "evidence": "q", "confidence": "high", "relationship": "new"}, {"route": "wisdom", "type": "warning", "claim": "B2", "evidence": "q", "confidence": "high", "relationship": "new"}, {"route": "wisdom", "type": "warning", "claim": "B3", "evidence": "q", "confidence": "high", "relationship": "new"}, {"route": "wisdom", "type": "warning", "claim": "B4 over cap", "evidence": "q", "confidence": "high", "relationship": "new"}]}
EOF
RANK_OUT="$TMP/rank.json"
python3 "$EXTRACT" rank --candidates "$CANDS" --global-cap 6 --per-session-cap 3 > "$RANK_OUT"
python3 - "$RANK_OUT" <<'PYEOF'
import json, sys
r = json.load(open(sys.argv[1]))
sel = r["selected"]
assert r["counts"]["selected"] == 6, r["counts"]
by_session = {}
for s in sel:
    by_session.setdefault(s["session_id"], []).append(s["candidate"]["claim"])
assert len(by_session.get("A", [])) == 3, by_session
assert len(by_session.get("B", [])) == 3, by_session
assert "A4 dup" not in by_session["A"]
assert not any("A5" in c for c in by_session["A"])
dropped_reasons = [d["reason"] for d in r["dropped"]]
assert "duplicate" in dropped_reasons and "per_session_cap" in dropped_reasons, r["dropped"]
assert any(d["reason"] == "per_session_cap" and d["session_id"] == "B" for d in r["dropped"]), r["dropped"]
# evidence-weighted ranking: A1 (high+evidence=7) before A2 (high=6)
assert by_session["A"][0] == "A1 high evidence", by_session["A"]
print("ok: ranking (caps, duplicate drop, evidence ordering)")
PYEOF

# Global cap binds when tightened to 5: one candidate must drop on global_cap
python3 "$EXTRACT" rank --candidates "$CANDS" --global-cap 5 --per-session-cap 3 > "${RANK_OUT}.5"
python3 - "${RANK_OUT}.5" <<'PYEOF2'
import json, sys
r = json.load(open(sys.argv[1]))
assert r["counts"]["selected"] == 5, r["counts"]
reasons = [d["reason"] for d in r["dropped"]]
assert "global_cap" in reasons, r["dropped"]
print("ok: ranking global cap binding")
PYEOF2

# ---------------------------------------------------------------- 6: closeout --no-supersede

THOME="$TMP/home"
mkdir -p "$THOME/.sisyphus/wisdom"
STORE="$THOME/.sisyphus/wisdom/system.jsonl"
cat > "$STORE" <<'EOF'
{"id": "20260101-000000-aaaa", "type": "gotcha", "scope": "system", "status": "active", "authority": "candidate", "body": "Docker build fails if .dockerignore excludes required files, always check .dockerignore before debugging docker build failures", "tags": ["docker"], "created": "2026-01-01T00:00:00Z", "origin_session": null}
EOF

SIMILAR="Docker build fails when .dockerignore excludes required files - check .dockerignore first before debugging docker build failures"

# Control: default closeout supersedes on high lexical overlap (temp HOME!)
HOME="$THOME" "$CLOSEOUT" --content "$SIMILAR" --type gotcha --tags docker >/dev/null 2>&1 || true
status=$(jq -r 'select(.id=="20260101-000000-aaaa") | .status' "$STORE")
if [ "$status" = "superseded" ]; then
    ok "closeout default behavior supersedes near-match (control)"
else
    fail "closeout control: expected supersede of near-match (got: $status)"
fi

# Reset store, then --no-supersede must keep the original active
cat > "$STORE" <<'EOF'
{"id": "20260101-000000-aaaa", "type": "gotcha", "scope": "system", "status": "active", "authority": "candidate", "body": "Docker build fails if .dockerignore excludes required files, always check .dockerignore before debugging docker build failures", "tags": ["docker"], "created": "2026-01-01T00:00:00Z", "origin_session": null}
EOF
HOME="$THOME" "$CLOSEOUT" --no-supersede --content "$SIMILAR" --type gotcha --tags docker > "$TMP/closeout_out.txt"
NEW_ID="$(tail -n 1 "$TMP/closeout_out.txt")"
[ -n "$NEW_ID" ] || fail "closeout --no-supersede produced no id"
status=$(jq -r 'select(.id=="20260101-000000-aaaa") | .status' "$STORE")
    if [ "$status" = "active" ]; then
    ok "closeout --no-supersede keeps original active"
    else
    fail "closeout --no-supersede: original was modified (status: $status)"
fi
new_status=$(jq -r --arg id "$NEW_ID" 'select(.id==$id) | .status' "$STORE")
if [ "$new_status" = "active" ]; then
    ok "closeout --no-supersede writes new entry"
else
    fail "closeout --no-supersede: new entry missing ($NEW_ID: $new_status)"
fi

# ---------------------------------------------------------------- 7: dry-run sweep

SWEEP_STATE="$TMP/sweep-state"
"$REPO_ROOT/scripts/session-learning/nightly-sweep.sh" \
    --dry-run --db "$FIXTURE_DB" --state-dir "$SWEEP_STATE" \
    --workdir "$TMP/sweep-work" --log "$TMP/sweep.log" \
    --stale-hours 6 --limit 4 > "$TMP/sweep_stdout.txt"
grep -q "sweep analyzed=" "$TMP/sweep.log" || grep -q "sweep analyzed=" "$TMP/sweep_stdout.txt" || fail "sweep summary line missing"
ok "dry-run sweep produced summary"
grep -q '"status": "dry_run"' "$SWEEP_STATE/ledger.jsonl" || fail "dry_run ledger row missing"
ok "dry-run sweep wrote ledger rows"

echo "PASS: $PASS checks passed"
