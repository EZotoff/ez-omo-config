#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT/configs/opencode-supervisor/supervisor.json"
UNIT="$ROOT/systemd/user/opencode-supervisor.service"

python3 -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$CONFIG"
test -f "$UNIT"
grep -Fq 'configs|configs/opencode-supervisor/supervisor.json|$HOME/.config/opencode-supervisor/supervisor.json' "$ROOT/install.sh"
grep -Fq 'scripts|systemd/user/opencode-supervisor.service|$HOME/.config/systemd/user/opencode-supervisor.service' "$ROOT/install.sh"
grep -Fq 'NoNewPrivileges=true' "$UNIT"
grep -Fq 'ExecStart=%h/.bun/bin/bun run %h/ez-omo-config/supervisor/src/main.ts' "$UNIT"
printf 'supervisor static contract: PASS\n'
