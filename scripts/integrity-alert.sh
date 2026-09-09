#!/usr/bin/env bash
# Integrity-failure alerting — invoked by opencode-integrity-alert.service via
# systemd OnFailure= when opencode-patch-integrity-check.service fails.
# Channels: journal line (always, bus-independent), marker file, desktop
# notification (guarded for headless rigs). No console/MOTD spam.
set -euo pipefail

STATE_DIR="$HOME/.local/state/opencode"
MARKER="$STATE_DIR/patch-integrity.alert"
REPO="${EZ_OMO_CONFIG_REPO:-$HOME/ez-omo-config}"
FAILED_UNIT="${1:-unknown}"

mkdir -p "$STATE_DIR"

# Capture the verifier read-only; its non-zero exit IS the triggering
# condition, so tolerate it while collecting the summary.
summary="$(bash "$REPO/scripts/verify-live-patches.sh" 2>&1 || true)"

{
    echo "INTEGRITY-ALERT: patch verification failing"
    echo "timestamp: $(date '+%Y-%m-%dT%H:%M:%S%z')"
    echo "failed unit: $FAILED_UNIT"
    echo "verify-live-patches summary tail:"
    printf '%s\n' "$summary" | tail -5
} > "$MARKER"

if command -v notify-send >/dev/null 2>&1; then
    notify-send -u critical 'OpenCode patch integrity FAILED' \
        'verify-live-patches reported stale/missing — run scripts/verify-live-patches.sh' || true
fi

# Journal line — unmistakable, agent-greppable, independent of any bus.
echo "INTEGRITY-ALERT: patch verification failing (unit: $FAILED_UNIT, marker: $MARKER)"
