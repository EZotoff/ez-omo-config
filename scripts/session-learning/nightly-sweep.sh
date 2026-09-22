#!/usr/bin/env bash
set -euo pipefail

# nightly-sweep.sh — nightly session-learning closeout sweep (thin wrapper).
#
# Orchestration lives in extract-digest.py (subcommand: sweep). This wrapper
# owns the single-instance lock and state-dir scaffolding so the systemd
# oneshot and manual runs serialize cleanly.
#
# Usage: nightly-sweep.sh [--dry-run] [--limit N] [--stale-hours H] ...
# (flags pass through to `extract-digest.py sweep`)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${SESSION_LEARNING_STATE_DIR:-$HOME/.sisyphus/session-learning}"

mkdir -p "$STATE_DIR"

# Single instance (systemd oneshot is already serialized; this guards manual runs)
exec 9>"$STATE_DIR/sweep.lock"
flock -n 9 || {
    echo "nightly-sweep: another sweep is running; exiting" >&2
    exit 0
}

exec python3 "$SCRIPT_DIR/extract-digest.py" sweep --state-dir "$STATE_DIR" "$@"
