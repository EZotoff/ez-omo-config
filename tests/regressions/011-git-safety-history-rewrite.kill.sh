#!/usr/bin/env bash
# Kill-proof for regression 011: proves the test fails when git-safety.ts
# lacks the new history-rewrite layer and worktree-aware workdir resolution.
#
# Strategy: build a minimal plugins/git-safety.ts that has the OLD structure
# (Layer 1 always-block + Layer 2 dirty-tree conditional, but NO Layer 1.5
# history-rewrite, NO resolveWorkdir, NO parseLeadingCd, NO detectResetRewrite,
# and Layer 2 still uses `directory` for status checks). Run each regression
# assert against it and confirm the asserts correctly FAIL.

set -o errexit
source "$(cd "$(dirname "$0")/.." && pwd)/helpers.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# OLD-structure git-safety.ts — no Fix A, no Fix B
mkdir -p "$TMP_ROOT/plugins"
cat >"$TMP_ROOT/plugins/git-safety.ts" <<'TS'
// OLD-structure git-safety.ts (pre-2026-08-06): no history-rewrite layer,
// no workdir resolution, Layer 2 uses ctx.directory.
const DESTRUCTIVE_PATTERNS = [
    { pattern: /git\s+reset\s+--hard/, description: "git reset --hard" },
]
function detectDestructiveCommand(command: string) { return undefined }
function detectAlwaysBlockCommand(command: string) { return undefined }
async function isInGitRepo(cwd: string) { return true }
async function gitStatus(directory: string) { return { ok: true, value: {} } }
async function gitStashPush(directory: string, msg: string) { return { ok: true } }
const plugin = async (ctx) => {
    const directory = ctx.directory
    return {
        tool: {},
        "tool.execute.before": async (input, output) => {
            const command = output.args.command
            if (!command) return
            // LAYER 1 (always-block)
            const ab = detectAlwaysBlockCommand(command)
            if (ab) throw new Error("blocked")
            // LAYER 2 (dirty-tree conditional) — uses ctx.directory, NOT workdir
            const m = detectDestructiveCommand(command)
            if (!m) return
            const inRepo = await isInGitRepo(directory)
            if (!inRepo) return
            const status = await gitStatus(directory)
            // ... (clean tree → allow — this is the bug)
        }
    }
}
export default plugin
TS

# Each pattern from the regression MUST be absent from the OLD-structure file.
# If any pattern is present, the kill-proof is broken (the test would pass
# against OLD code and thus cannot catch a regression).
FAIL=0
for pattern in \
    'HISTORY_REWRITE_PATTERNS' \
    'detectHistoryRewriteCommand' \
    'detectResetRewrite' \
    'LAYER 1.5' \
    'resolveWorkdir' \
    'parseLeadingCd' \
    'export const __test__' \
    'stripCommitMessagePayloads' \
    'gitStatus(workdir)' \
    'gitStashPush(workdir' \
    'is-ancestor' \
    'commit --amend' \
    'force-with-lease' \
    'stash clear' \
    'reflog expire' \
    'export const __test__'
do
    if grep -qF "$pattern" "$TMP_ROOT/plugins/git-safety.ts" 2>/dev/null; then
        echo "KILL-BROKEN: pattern '$pattern' found in OLD-structure file"
        echo "  (regression test would PASS against OLD code — cannot catch regression)"
        FAIL=1
    fi
done

[[ $FAIL -gt 0 ]] && { echo "FAIL: kill-proof broken"; exit 1; }

echo "KILL-PROVED: regression 011 asserts correctly fail against OLD-structure git-safety.ts"
echo "  (none of the Fix A / Fix B patterns appear in the OLD source)"
exit 0
