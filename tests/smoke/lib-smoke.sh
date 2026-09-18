#!/usr/bin/env bash
# Shared helpers for the per-SHA smoke matrix (plan: patch-provenance T6).
#
# Result store: ~/.local/share/opencode/smoke-results/<binary-sha256>.json
#   JSON array of {smoke_id, result, timestamp, note}
#   result ∈ PASS | FAIL | SKIP
#
# Duplicate-PASS refusal: already-passing smokes are skipped on re-run
# unless SMOKE_FORCE=1.
set -euo pipefail

SMOKE_RESULTS_DIR="${SMOKE_RESULTS_DIR:-$HOME/.local/share/opencode/smoke-results}"

# --- tmux lifecycle ---------------------------------------------------------

SMOKE_SESSIONS=()
smoke_cleanup() {
    local s
    for s in "${SMOKE_SESSIONS[@]:-}"; do
        [[ -n "$s" ]] || continue
        tmux kill-session -t "$s" 2>/dev/null || true
    done
    SMOKE_SESSIONS=()
}
trap smoke_cleanup EXIT

# smoke_spawn_session <name> — detached session, fixed 200x50, tracked for cleanup.
smoke_spawn_session() {
    local name="$1"
    tmux new-session -d -s "$name" -x 200 -y 50
    SMOKE_SESSIONS+=("$name")
}

# smoke_capture <name> — pane text (incl. scrollback) with ANSI/OSC sequences stripped.
smoke_capture() {
    local name="$1"
    tmux capture-pane -p -t "$name" -S -3000 2>/dev/null \
        | perl -pe 's/\e\][^\e\a]*(\a|\e\\\\)//g; s/\e\[[0-9;?]*[A-Za-z]//g;
                  s/\e[()][0-9A-B]//g; s/[\x01-\x08\x0b\x0c\x0e-\x1f\x7f]//g'
}

# --- result store -----------------------------------------------------------

# smoke_sha256 <file>
smoke_sha256() {
    sha256sum "$1" | cut -d' ' -f1
}

# smoke_record <binary-sha> <smoke-id> <PASS|FAIL|SKIP> <note>
smoke_record() {
    local sha="$1" id="$2" result="$3" note="$4"
    local file="$SMOKE_RESULTS_DIR/$sha.json" ts entry
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    mkdir -p "$SMOKE_RESULTS_DIR"
    entry="$(jq -cn --arg i "$id" --arg r "$result" --arg t "$ts" --arg n "$note" \
        '{smoke_id: $i, result: $r, timestamp: $t, note: $n}')"
    if [[ -f "$file" ]]; then
        jq --argjson e "$entry" '. + [$e]' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
    else
        printf '[%s]\n' "$entry" > "$file"
    fi
}

# smoke_already_passing <sha> <smoke-id> — exit 0 if a PASS entry exists.
smoke_already_passing() {
    local sha="$1" id="$2"
    local file="$SMOKE_RESULTS_DIR/$sha.json"
    [[ -f "$file" ]] || return 1
    jq -e --arg i "$id" 'map(select(.smoke_id == $i and .result == "PASS")) | length > 0' \
        "$file" >/dev/null
}

# smoke_require_binary <path> — exit 22 with message if missing/not executable.
smoke_require_binary() {
    local bin="$1"
    if [[ ! -f "$bin" ]]; then
        echo "smoke: binary not found: $bin" >&2
        return 22
    fi
    if [[ ! -x "$bin" ]]; then
        echo "smoke: binary not executable: $bin" >&2
        return 22
    fi
}
