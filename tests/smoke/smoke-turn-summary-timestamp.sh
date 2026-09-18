#!/usr/bin/env bash
# Smoke: opencode--turn-summary-timestamp (plan: patch-provenance T6).
#
# Spawns the bare TUI in tmux, sends a one-word prompt, and asserts ONLY the
# FORMAT of the rendered turn-summary line (no provider-content assertions):
#   ▣ <agent> · <model> · <N(.N)?s> · <H>:<MM> <AM|PM>
# Model-unreachable / provider error => SKIP (never FAIL).
# Usage: smoke-turn-summary-timestamp.sh [binary] (default: live binary)
# Duplicate PASS for the same sha is refused unless SMOKE_FORCE=1.
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib-smoke.sh"

BIN="${1:-$HOME/.opencode/bin/opencode}"
SMOKE_ID="turn-summary-timestamp"
SESSION="smoke-tts-$$-$(date +%s)"
PROMPT='reply with exactly: hi'

# Verified format: "▣ Sisyphus · GLM 5.3 Flash · 5.1s · 7:19 PM"
SUMMARY_RE='▣.* · [0-9]+(\.[0-9]+)?s · [0-9]{1,2}:[0-9]{2} (AM|PM)'
# Provider-failure indicators (any hit => SKIP, not FAIL)
UNREACHABLE_RE='(quota|rate.?limit|unreachable|connection (refused|error|failed)|ECONNRESET|ECONNREFUSED|network error|API error|authentication|unauthorized|no such model|provider .*failed)'

if ! smoke_require_binary "$BIN"; then
    sha="$(smoke_sha256 "$BIN" 2>/dev/null || echo unknown)"
    smoke_record "$sha" "$SMOKE_ID" "FAIL" "binary missing or not executable: $BIN"
    echo "FAIL: binary missing or not executable: $BIN"
    exit 1
fi

BIN_SHA="$(smoke_sha256 "$BIN")"

if [[ "${SMOKE_FORCE:-0}" != "1" ]] && smoke_already_passing "$BIN_SHA" "$SMOKE_ID"; then
    echo "SKIP-RERUN: $SMOKE_ID already PASS for sha ${BIN_SHA:0:12} (set SMOKE_FORCE=1 to rerun)"
    exit 0
fi

# --- spawn TUI ---------------------------------------------------------------
smoke_spawn_session "$SESSION"
tmux send-keys -t "$SESSION" "$BIN" Enter

composer_ready=0
for _ in $(seq 1 60); do
    if smoke_capture "$SESSION" | grep -q "Ask anything"; then
        composer_ready=1
        break
    fi
    sleep 0.5
done

if [[ $composer_ready -ne 1 ]]; then
    smoke_record "$BIN_SHA" "$SMOKE_ID" "FAIL" "composer ('Ask anything') not visible within 30s"
    echo "FAIL: composer not visible within 30s"
    exit 1
fi

tmux send-keys -t "$SESSION" "$PROMPT" Enter

# --- poll for the summary line (up to 90s) -----------------------------------
matched=""
deadline=$((SECONDS + 90))
while (( SECONDS < deadline )); do
    capture="$(smoke_capture "$SESSION")"
    matched="$(printf '%s\n' "$capture" | grep -E "$SUMMARY_RE" | tail -1 || true)"
    if [[ -n "$matched" ]]; then
        break
    fi
    if printf '%s' "$capture" | grep -Eqi "$UNREACHABLE_RE"; then
        smoke_record "$BIN_SHA" "$SMOKE_ID" "SKIP" \
            "model/provider unreachable while waiting for turn summary (binary ${BIN_SHA:0:12})"
        echo "SKIP: model unreachable / provider error"
        exit 0
    fi
    sleep 2
done

if [[ -n "$matched" ]]; then
    smoke_record "$BIN_SHA" "$SMOKE_ID" "PASS" "summary line matched: $matched"
    echo "PASS: turn-summary timestamp format verified"
    echo "  line: $matched"
    exit 0
fi

smoke_record "$BIN_SHA" "$SMOKE_ID" "FAIL" \
    "no turn-summary line matching '$SUMMARY_RE' within 90s (binary ${BIN_SHA:0:12})"
echo "FAIL: no turn-summary line matching format within 90s"
exit 1
