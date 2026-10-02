#!/usr/bin/env bash
# Gate action: unlock steering writes on veran + kraken (meta-run gate).
# Preconditions are enforced by rollout-monitor (after_round, min_activations,
# max_new_errors) — this script only performs the flip, validate, restart, record.
set -euo pipefail

CONFIG="$HOME/ez-omo-config/configs/opencode-supervisor/supervisor.json"
MARKER="$HOME/.local/state/opencode-rollout/supervisor-steering.gate-fired"

# Idempotence guard beyond the monitor's gates_done (belt and suspenders)
[ -f "$MARKER" ] && { echo "gate already fired"; exit 0; }

python3 - "$CONFIG" <<'PYEOF'
import json, sys
path = sys.argv[1]
cfg = json.load(open(path))
flipped = []
for root in cfg["roots"]:
    if root["path"] in ("/home/ezotoff/AI_projects/veran", "/home/ezotoff/AI_projects/kraken"):
        if root.get("continue_writes", {}).get("enabled") is not True:
            root["continue_writes"] = {"enabled": True, "daily_cap": 5, "kick_start_only": True}
            root["steer_writes"] = {"enabled": True, "daily_cap": 3}
            root["reformulate_writes"] = {"enabled": True, "daily_cap": 3}
            flipped.append(root["path"])
json.dump(cfg, open(path, "w"), indent=2)
json.load(open(path))  # validate
print("flipped:", flipped or "none (already enabled)")
PYEOF

mkdir -p "$(dirname "$MARKER")"
date -Is > "$MARKER"

git -C "$HOME/ez-omo-config" add configs/opencode-supervisor/supervisor.json
git -C "$HOME/ez-omo-config" commit -q -m "gate(supervisor): unlock steering on veran+kraken (rollout gate after round 4, >=3 activations, 0 errors)" || echo "commit skipped (nothing to commit)"

systemctl --user restart opencode-supervisor.service
sleep 3
systemctl --user is-active opencode-supervisor.service
echo "gate complete: steering enabled on veran + kraken"
