#!/usr/bin/env bash
# Rollout gate action: supervisor approve-writes, observe -> grant flip.
# Per the 2026-10-03 console ruling, this UNLOCK REQUIRES HUMAN REVIEW of the
# would-grant ledger: the monitor's gate calls this script, and it refuses to
# flip until the operator's review marker exists. Never runs unattended-unsafe.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT/configs/opencode-supervisor/supervisor.json"
MARKER="$HOME/.local/state/opencode-rollout/supervisor-approve-writes.HUMAN-REVIEW-DONE"

if [ ! -f "$MARKER" ]; then
  echo "UNLOCK BLOCKED: human review marker missing ($MARKER)."
  echo "Review would-grants: jq 'select(.type==\"TICK_SKIPPED\" and (.payload.reason|startswith(\"approve write: WOULD-GRANT\")))' ~/.local/state/opencode-supervisor/ledger.jsonl"
  echo "Then: touch $MARKER"
  exit 1
fi

python3 - "$CONFIG" <<'PY'
import json, sys
p = sys.argv[1]
c = json.load(open(p))
n = 0
for r in c["roots"]:
    aw = r.get("approve_writes")
    if aw and aw.get("enabled") and aw.get("mode") == "observe":
        aw["mode"] = "grant"
        n += 1
json.dump(c, open(p, "w"), indent=2)
json.load(open(p))
print(f"approve_writes flipped observe->grant on {n} roots")
PY
"$ROOT/scripts/restart-with-continuation.sh" --restart --service opencode-supervisor.service --url http://127.0.0.1:3021 >> ~/.local/share/opencode/restart-continuations/restart.log 2>&1
echo "UNLOCKED: approve writes now grant on enabled roots (FYI toast + ledger INTERVENTION_SENT mode=approve)."
