#!/usr/bin/env bash
set -euo pipefail

source tests/helpers.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_FAILED=0
TESTS_PASSED=0

pass() {
    echo "PASS: $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
    echo "FAIL: $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

if command -v vera >/dev/null 2>&1; then
    pass "Vera binary is available on PATH"
else
    fail "Vera binary is not available on PATH"
fi

if [[ -d "$HOME/.config/opencode/skills/vera" ]]; then
    pass "External vera skill exists at ~/.config/opencode/skills/vera/"
else
    fail "External vera skill missing at ~/.config/opencode/skills/vera/"
fi

if [[ -f "$REPO_ROOT/plugins/vera-runtime.ts" ]]; then
    pass "plugins/vera-runtime.ts exists in repo"
else
    fail "plugins/vera-runtime.ts missing in repo"
fi

if grep -q 'configs/opencode/worktree.jsonc' "$REPO_ROOT/install.sh"; then
    pass "install.sh contains worktree.jsonc entry"
else
    fail "install.sh missing worktree.jsonc entry"
fi

if grep -q 'plugins/vera-runtime.ts' "$REPO_ROOT/install.sh"; then
    pass "install.sh contains vera-runtime.ts entry"
else
    fail "install.sh missing vera-runtime.ts entry"
fi

if grep -q 'scripts/worktree-post-create.sh' "$REPO_ROOT/install.sh"; then
    pass "install.sh contains worktree-post-create.sh entry"
else
    fail "install.sh missing worktree-post-create.sh entry"
fi

if grep -q 'scripts/worktree-pre-delete.sh' "$REPO_ROOT/install.sh"; then
    pass "install.sh contains worktree-pre-delete.sh entry"
else
    fail "install.sh missing worktree-pre-delete.sh entry"
fi

WORKTREE_HOOK_TEMP="$(mktemp -d)"
trap 'rm -rf "$WORKTREE_HOOK_TEMP"' EXIT
FAKE_BIN="$WORKTREE_HOOK_TEMP/bin"
FAKE_HOME="$WORKTREE_HOOK_TEMP/home"
FAKE_REPO="$WORKTREE_HOOK_TEMP/repo"
VERA_CALLS="$WORKTREE_HOOK_TEMP/vera-calls.log"
mkdir -p "$FAKE_BIN" "$FAKE_HOME" "$FAKE_REPO"
cat > "$FAKE_BIN/vera" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$VERA_CALLS"
exit 0
EOF
chmod +x "$FAKE_BIN/vera"
git -C "$FAKE_REPO" init -q

(
    cd "$FAKE_REPO"
    HOME="$FAKE_HOME" PATH="$FAKE_BIN:$PATH" VERA_CALLS="$VERA_CALLS" bash "$REPO_ROOT/scripts/worktree-post-create.sh" >/dev/null
)
if [[ -s "$VERA_CALLS" ]]; then
    fail "worktree-post-create.sh invoked vera when OMO_VERA_RUNTIME_AUTOSTART was unset"
else
    pass "worktree-post-create.sh skips vera when OMO_VERA_RUNTIME_AUTOSTART is unset"
fi
if grep -R '"automationMode": "manual"' "$FAKE_HOME/.local/share/opencode/worktree-state" >/dev/null && grep -R '"status": "stopped"' "$FAKE_HOME/.local/share/opencode/worktree-state" >/dev/null; then
    pass "worktree-post-create.sh records manual stopped Vera state by default"
else
    fail "worktree-post-create.sh did not record manual stopped Vera state by default"
fi

rm -f "$VERA_CALLS"
rm -rf "$FAKE_HOME/.local/share/opencode/worktree-state"
(
    cd "$FAKE_REPO"
    HOME="$FAKE_HOME" PATH="$FAKE_BIN:$PATH" VERA_CALLS="$VERA_CALLS" OMO_VERA_RUNTIME_AUTOSTART=1 bash "$REPO_ROOT/scripts/worktree-post-create.sh" >/dev/null
)
if grep -Fxq 'index .' "$VERA_CALLS" 2>/dev/null; then
    pass "worktree-post-create.sh runs vera index when OMO_VERA_RUNTIME_AUTOSTART=1"
else
    fail "worktree-post-create.sh did not run vera index when OMO_VERA_RUNTIME_AUTOSTART=1"
fi
if grep -R '"automationMode": "autostart"' "$FAKE_HOME/.local/share/opencode/worktree-state" >/dev/null && grep -R '"status": "indexed"' "$FAKE_HOME/.local/share/opencode/worktree-state" >/dev/null; then
    pass "worktree-post-create.sh records autostart indexed Vera state when enabled"
else
    fail "worktree-post-create.sh did not record autostart indexed Vera state when enabled"
fi

run_pre_delete_case() {
    local mode="$1"
    local repo="$WORKTREE_HOOK_TEMP/pre-delete-$mode"
    local home="$WORKTREE_HOOK_TEMP/home-pre-delete-$mode"
    local project_id
    local real_path
    local workspace_key
    local watcher_dir
    local watcher_state
    local pid

    mkdir -p "$repo" "$home"
    git -C "$repo" init -q
    project_id="$(basename "$repo")"
    real_path="$(realpath "$repo")"
    workspace_key="$(basename "$real_path")-$(printf '%s' "$real_path" | sha1sum | cut -c1-8)"
    watcher_dir="$home/.local/share/opencode/worktree-state/$project_id/vera-watchers"
    watcher_state="$watcher_dir/$workspace_key.json"
    mkdir -p "$watcher_dir"

    bash -c "exec -a 'vera watch $real_path' sleep 900" >/dev/null 2>&1 &
    pid=$!
    STARTED_PIDS+=("$pid")

    cat > "$watcher_state" <<EOF
{
  "status": "running",
  "pid": $pid,
  "workspaceKey": "$workspace_key",
  "workspacePath": "$real_path",
  "automationMode": "$mode"
}
EOF

    (
        cd "$repo"
        HOME="$home" bash "$REPO_ROOT/scripts/worktree-pre-delete.sh" >/dev/null
    )

    if [[ -e "$watcher_state" ]]; then
        fail "worktree-pre-delete.sh removes $mode watcher state"
    else
        pass "worktree-pre-delete.sh removes $mode watcher state"
    fi

    if [[ "$mode" == "autostart" ]]; then
        if kill -0 "$pid" >/dev/null 2>&1; then
            fail "worktree-pre-delete.sh stops owned autostart Vera watcher"
        else
            pass "worktree-pre-delete.sh stops owned autostart Vera watcher"
        fi
    else
        if kill -0 "$pid" >/dev/null 2>&1; then
            pass "worktree-pre-delete.sh leaves manual Vera watcher process untouched"
            kill "$pid" >/dev/null 2>&1 || true
        else
            fail "worktree-pre-delete.sh should not stop manual Vera watcher process"
        fi
    fi
}

run_pre_delete_case "autostart"
run_pre_delete_case "manual"

if grep -q '\.vera/' "$REPO_ROOT/.gitignore"; then
    pass ".gitignore contains .vera/"
else
    fail ".gitignore missing .vera/"
fi

vera_agents=$(python3 -c "
import json
with open('$REPO_ROOT/configs/oh-my-openagent/oh-my-openagent.json') as f:
    data = json.load(f)
agents_with_vera = []
for agent, cfg in data.get('agents', {}).items():
    skills = cfg.get('skills', [])
    if 'vera' in skills:
        agents_with_vera.append(agent)
expected = ['sisyphus', 'librarian', 'explore', 'prometheus']
if sorted(agents_with_vera) == sorted(expected):
    print('OK')
else:
    print('MISMATCH: got ' + str(sorted(agents_with_vera)))
" 2>/dev/null)

if [[ "$vera_agents" == "OK" ]]; then
    pass "oh-my-openagent.json has vera in skills for exactly sisyphus, librarian, explore, prometheus"
else
    fail "oh-my-openagent.json vera skill assignment mismatch: $vera_agents"
fi

if grep -q 'vera-watchers/' "$REPO_ROOT/docs/worktree-state-schema.md"; then
    pass "docs/worktree-state-schema.md contains vera-watchers/ section"
else
    fail "docs/worktree-state-schema.md missing vera-watchers/ section"
fi

if grep -q 'pgrep -f \"vera watch\"' "$REPO_ROOT/AGENTS.md"; then
    fail "AGENTS.md still contains pgrep -f \"vera watch\""
else
    pass "AGENTS.md does not contain pgrep -f \"vera watch\""
fi

if grep -qi 'TODO' "$REPO_ROOT/plugins/vera-runtime.ts"; then
    fail "plugins/vera-runtime.ts contains TODO comments"
else
    pass "plugins/vera-runtime.ts has no TODO comments"
fi

if grep -q 'event: async' "$REPO_ROOT/plugins/vera-runtime.ts"; then
    pass "vera-runtime.ts uses event: async hook"
else
    fail "vera-runtime.ts missing event: async hook"
fi

if grep -q 'event.properties.info.id' "$REPO_ROOT/plugins/vera-runtime.ts"; then
    pass "vera-runtime.ts handles properties.info.id"
else
    fail "vera-runtime.ts missing properties.info.id handling"
fi

for log_pattern in \
    "event hook invoked" \
    "session.created handled" \
    "vera index . starting" \
    "vera watch . starting" \
    "watcher started pid="; do
    if grep -qF "$log_pattern" "$REPO_ROOT/plugins/vera-runtime.ts"; then
        pass "vera-runtime.ts contains log substring: $log_pattern"
    else
        fail "vera-runtime.ts missing log substring: $log_pattern"
    fi
done

echo ""
echo "Vera operational integration: $TESTS_PASSED passed, $TESTS_FAILED failed"

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi

exit 0
