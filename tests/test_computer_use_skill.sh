#!/usr/bin/env bash
# Static + optional live contract test for the computer-use skill.
# The safety-critical invariant is that the skill proxies to the shared daemon
# with --no-overlay; bare `cua-driver mcp` creates a second overlay runtime and
# froze GNOME Shell twice on this machine.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$ROOT/skills/computer-use/SKILL.md"
PASS=0
FAIL=0

check() {
    local label="$1"
    shift
    if "$@"; then
        printf 'PASS: %s\n' "$label"
        PASS=$((PASS + 1))
    else
        printf 'FAIL: %s\n' "$label" >&2
        FAIL=$((FAIL + 1))
    fi
}

check "computer-use skill exists" test -f "$SKILL"
check "skill has canonical name" grep -q '^name: computer-use$' "$SKILL"
check "skill embeds a cua MCP" grep -q '^  cua:$' "$SKILL"
check "MCP launcher expands HOME at runtime" grep -Fq 'command: bash' "$SKILL"
check "MCP proxy uses shared daemon socket" grep -Fq 'cua-driver mcp --socket "$HOME/.cache/cua-driver/cua-driver.sock"' "$SKILL"
check "MCP proxy disables overlay defensively" grep -Fq -- '--no-overlay' "$SKILL"
check "skill contains no machine-specific home path" bash -c '! grep -q "/home/ezotoff" "$1"' _ "$SKILL"
check "skill forbids inline MCP screenshots" grep -Fq 'Never return screenshots through `skill_mcp`' "$SKILL"
check "skill requires file-based screenshot transport" grep -Fq 'screenshot_out_file' "$SKILL"

UNIT="$HOME/.config/systemd/user/cua-driver.service"
if [[ -f "$UNIT" ]]; then
    check "systemd daemon pinned to 0.20.0" grep -Fq '/v0.20.0/cua-driver serve' "$UNIT"
    check "systemd daemon disables overlay" grep -Fq 'serve --no-overlay' "$UNIT"
fi

# Live proof is optional so this stays portable in CI/new-machine installs.
if command -v cua-driver >/dev/null 2>&1 && \
   command -v jq >/dev/null 2>&1 && \
   [[ -S "$HOME/.cache/cua-driver/cua-driver.sock" ]]; then
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT

    (
        printf '%s\n' \
            '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"computer-use-test","version":"0.0.0"}}}' \
            '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
            '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
        sleep 2
    ) | timeout 20 bash -c 'exec cua-driver mcp --socket "$HOME/.cache/cua-driver/cua-driver.sock" --no-overlay' \
        >"$TMP/out.json" 2>"$TMP/err.log"

    check "live MCP identifies cua-driver 0.20.0" \
        jq -se 'map(select(.id == 1))[0].result.serverInfo == {name:"cua-driver",version:"0.20.0"}' "$TMP/out.json"
    check "live MCP exposes full tool surface" \
        jq -se 'map(select(.id == 2))[0] | (.result.tools | length) >= 50' "$TMP/out.json"
    check "live MCP proxy never starts an overlay" bash -c '! grep -qi overlay "$1"' _ "$TMP/err.log"
else
    echo "SKIP: live cua-driver handshake (binary, jq, or daemon socket unavailable)"
fi

printf 'computer-use skill: Pass: %d | Fail: %d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
