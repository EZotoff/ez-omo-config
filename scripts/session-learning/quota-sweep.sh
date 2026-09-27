#!/usr/bin/env bash
set -euo pipefail

# quota-sweep.sh — opportunistic parallel backlog drain inside the Z.AI
# pre-reset quota window (default: 30-120 min before the 5h rolling reset).
#
# Thin wrapper: shares the nightly sweep's flock (mutual exclusion), then
# defers to `extract-digest.py quota-sweep`, which itself exits immediately
# unless the quota probe says the window is open.
#
# Flags pass through to `extract-digest.py quota-sweep`
# (--concurrency, --max-batch, --global-cap, --usage-ceiling, --dry-run, ...).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${SESSION_LEARNING_STATE_DIR:-$HOME/.sisyphus/session-learning}"

mkdir -p "$STATE_DIR"

exec 9>"$STATE_DIR/sweep.lock"
flock -n 9 || {
    echo "quota-sweep: another sweep holds the lock; exiting" >&2
    exit 0
}

exec python3 "$SCRIPT_DIR/extract-digest.py" quota-sweep --state-dir "$STATE_DIR" "$@"
