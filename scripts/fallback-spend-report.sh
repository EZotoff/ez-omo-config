#!/usr/bin/env bash
# fallback-spend-report.sh — weekly out-of-band fallback spend line.
#
# Reads the live OpenCode session DB read-only and reports assistant traffic
# served on models OUTSIDE the declaring config (agent primary + declared
# fallback_models + small_model) — i.e. the built-in OMO model-core fallback
# chain usage, like the 2026-10-04/05 google/gemini-3.1-pro event (~15M tokens
# found only by forensic attribution).
#
# Advisory output only; never modifies anything. Exit 0 unless invocation is
# broken. Wire into the operator's weekly view (systemd timer / weekly report)
# only after operator approval — deployment is gated, this script is prep.

set -euo pipefail

DAYS="${1:-7}"
DB="${OPENCODE_DB:-$HOME/.local/share/opencode/opencode.db}"
OMO_CONFIG="${OMO_CONFIG:-$HOME/.config/opencode/oh-my-openagent.json}"
OPENCODE_CONFIG="${OPENCODE_CONFIG:-$HOME/.config/opencode/opencode.json}"
RETRY_REGISTRY="${RETRY_REGISTRY:-$HOME/.config/opencode/retry-errors.json}"

export FALLBACK_REPORT_DAYS="$DAYS" \
       FALLBACK_REPORT_DB="$DB" \
       FALLBACK_REPORT_OMO="$OMO_CONFIG" \
       FALLBACK_REPORT_OC="$OPENCODE_CONFIG" \
       FALLBACK_REPORT_RETRY="$RETRY_REGISTRY"

exec python3 - << 'PYEOF'
import json
import os
import sqlite3
import sys
import time

days = float(os.environ["FALLBACK_REPORT_DAYS"])
db_path = os.environ["FALLBACK_REPORT_DB"]


def read_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def ref(model):
    if isinstance(model, dict):
        p, m = model.get("providerID"), model.get("modelID")
        return f"{p}/{m}" if p and m else None
    if isinstance(model, str):
        return model
    return None


omo = read_json(os.environ["FALLBACK_REPORT_OMO"])
oc = read_json(os.environ["FALLBACK_REPORT_OC"])
retry = read_json(os.environ["FALLBACK_REPORT_RETRY"])

declared = {}  # agent/category name -> set of refs
for group in ("agents", "categories"):
    for name, a in (omo.get(group) or {}).items():
        s = declared.setdefault(name.lower(), set())
        if ref(a.get("model")):
            s.add(ref(a["model"]))
        for fb in a.get("fallback_models") or []:
            r = ref(fb)
            if r:
                s.add(r)

small = ref(oc.get("small_model"))
compaction = {ref(m) for m in retry.get("compaction_fallback_models") or [] if ref(m)}

# Global declared pool (v1 semantics): a model is out-of-band only when NO
# operator config declares it anywhere — agent/category primary or fallback,
# small model, compaction chain. Looser than per-agent checking on purpose:
# task(category=...) spawns Sisyphus-Junior on the category's model while the
# message still carries agent="Sisyphus-Junior". A model declared nowhere is
# definitionally built-in-chain usage.
pool = set(compaction)
if small:
    pool.add(small)
for s in declared.values():
    pool |= s

cutoff = (time.time() - days * 86400) * 1000
if not os.path.exists(db_path):
    print(f"fallback-spend-report: DB not found: {db_path}")
    sys.exit(0)

db = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
rows = db.execute(
    "select m.session_id, s.title, s.directory, s.parent_id, m.data "
    "from message m join session s on s.id = m.session_id "
    "where m.time_created > ?",
    (cutoff,),
).fetchall()

per_agent = {}   # (agent, model) -> [msgs, input, cache_read, output, cost]
per_parent = {}  # parent session id -> [tokens, cost, directory, title]
total = [0, 0.0]
for sid, title, directory, parent_id, data in rows:
    try:
        j = json.loads(data)
    except (TypeError, ValueError):
        continue
    if j.get("role") != "assistant":
        continue
    r = ref({"providerID": j.get("providerID"), "modelID": j.get("modelID")})
    agent = j.get("agent") or "?"
    if not r:
        continue
    if r in pool:
        continue
        continue
    t = j.get("tokens") or {}
    c = t.get("cache") or {}
    i = t.get("input") or 0
    o = t.get("output") or 0
    cr = c.get("read") or 0
    cost = j.get("cost") or 0.0
    toks = i + cr + o
    key = (agent, r)
    agg = per_agent.setdefault(key, [0, 0, 0, 0, 0.0])
    agg[0] += 1; agg[1] += i; agg[2] += cr; agg[3] += o; agg[4] += cost
    pt = per_parent.setdefault(sid, [0, 0.0, directory or "?", (title or "?")[:55], parent_id, agent])
    pt[0] += toks; pt[1] += cost
    total[0] += toks; total[1] += cost

print(f"Out-of-band fallback spend, last {days:g} day(s) (declared-set violation only):")
if not per_agent:
    print("  none — all assistant traffic stayed inside declared primary/fallback sets.")
else:
    for (agent, model), (n, i, cr, o, cost) in sorted(per_agent.items(), key=lambda x: -(x[1][1] + x[1][2] + x[1][3])):
        print(f"  {agent:>22} -> {model:<42} msgs={n:<4} in={i:,} cache_read={cr:,} out={o:,} ${cost:.2f}")
    print("  worst sessions:")
    for sid, (toks, cost, directory, title, parent_id, agent) in sorted(per_parent.items(), key=lambda x: -x[1][0])[:8]:
        print(f"    {toks:>12,} ${cost:6.2f} {'SUB' if parent_id else 'TOP'} {directory} :: {title} [{sid}]")
print(f"TOTAL out-of-band: {total[0]:,} tokens, ${total[1]:.2f}")
PYEOF
