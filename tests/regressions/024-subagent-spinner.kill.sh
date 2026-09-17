#!/usr/bin/env bash
# Kill-proof for 024-subagent-spinner.sh: strip the child-status aggregation
# from a copy of dialog-session-list.tsx and prove the test detects it.
set -o errexit
tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
SRC="$HOME/src/opencode/packages/tui/src/component/dialog-session-list.tsx"
[[ -f "$SRC" ]] || { echo "SKIP: source not present"; exit 0; }
# Reintroduce the bug shape: parent rows key only on their own status;
# child busy/retry is invisible to the spinner decision.
sed -e 's/opencode--tui-subagent-spinner/subagent-spinner-removed/' \
    -e 's/const workingChildParents = new Set<string>()/const workingChildParents = new Set<string>(); void workingChildParents/' \
    -e 's/sync\.data\.session_status?\.\[child\.id\]/({ type: "idle" } as never)/' \
    -e 's/workingChildParents\.add(child\.parentID)/workingChildParents.add("__never")/' \
    -e 's/workingChildParents\.has(x\.id)/false/' \
    -e 's/for (const child of \[...sessions(), ...sync.data.session\])/for (const child of sessions())/' \
    -e 's/seenChildren\.has(child\.id)/seenChildren.has("__never")/' \
    -e 's/if (child\.parentID === undefined || seenChildren/if (true || seenChildren/' \
    "$SRC" > "$tmpdir/dialog-session-list.tsx"
TEST="$(cd "$(dirname "$0")" && pwd)/024-subagent-spinner.sh"
if SUBAGENT_SPINNER_SRC="$tmpdir/dialog-session-list.tsx" bash "$TEST" >/dev/null 2>&1; then
    echo "FAIL: test passed against aggregation-stripped source — sentinel broken"
    exit 1
fi
echo "PROVED: subagent-spinner test detects reintroduced bug"
exit 0
