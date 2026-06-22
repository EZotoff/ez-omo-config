---
patch_id: "opencode--commit-policy-unblock"
dependency: "opencode"
target_file: "packages/opencode/src/tool/shell/shell.txt, packages/opencode/src/session/prompt/default.txt, packages/opencode/src/session/prompt/trinity.txt"
target_install_path: "/home/ezotoff/src/opencode"
status: "active"
applied_date: "2026-05-02"
dep_version: "1.17.9"
upstream_issue: "none"
verification_pattern: "may create local commits freely"
---

# OpenCode Commit Policy: Unblock Local Atomic and Partial-Progress Commits

## Problem

OpenCode's base system instructions contain a blanket prohibition on git commits:

> "Only create commits when requested by the user. If unclear, ask first."
> "NEVER commit changes unless the user explicitly asks you to. It is VERY IMPORTANT to only commit when explicitly asked..."

However, active project/skill workflows (git-master, auto-checkpoint) explicitly authorize local checkpoint or logical-task commits. These instructions are contradictory: the absolute no-commit rule blocks workflow-authorized commits, forcing agents to refuse legitimate task-required operations.

This patch replaces the blanket prohibition with a permissive local-commit policy that lets agents commit freely for atomic changes and partial-progress saves while preserving safety guardrails (no pushing, force-pushing, amending, rebasing, or destructive actions without explicit authorization).

**Revision v2 (2026-06-21):** The original v1 canonical text said "If no active workflow calls for a commit, ask first." In practice this caused agents to end turns with passive prompts like "ready to commit when you're ready" whenever no skill was explicitly loaded — which was the common case. The user's git workflow is agent-driven, so the "ask first" clause was friction without value. v2 removes the clause and explicitly permits free atomic/partial-progress commits.

## Patch Description

Three OpenCode instruction files are modified to replace absolute no-commit rules with the canonical replacement text.

**v1.17.9 structural change**: `bash.txt` (119-line static file) was REMOVED and replaced by a templated `shell/` subdirectory. The commit-policy text now lives in `shell/shell.txt` line 14 as a single bullet within a `# Git and GitHub` section.

### Source file 1: `packages/opencode/src/tool/shell/shell.txt` (was `bash.txt` pre-v1.17.9)

- Line 14: Replaces `- Only commit, amend, push, or create PRs when explicitly requested.` with the permissive bullet.
- The surrounding bullets (inspect git status, never commit secrets, do not push/force-push/amend unless requested, etc.) are already aligned with the canonical text's safety guardrails — no change needed.

### Source file 2: `packages/opencode/src/session/prompt/trinity.txt`

- Line 78: Replaces the `NEVER commit changes unless the user explicitly asks you to...` paragraph with the canonical text.

### Source file 3: `packages/opencode/src/session/prompt/default.txt`

- Line 76: Same replacement as trinity.txt.

### Canonical Replacement Text

> Git commits: follow the active git workflow. Agents may create local commits freely for atomic changes and partial-progress saves — no need to ask first. This user uses git primarily for agent work. Before committing, inspect staged/untracked changes and never commit secrets, credentials, auth files, or unrelated work. Do not push, force-push, amend, rebase, or run destructive git commands unless explicitly authorized.

## Verification

**Source-level verification** (after editing the 3 files):

```bash
# Verify all three source files contain the replacement text
grep -l "may create local commits freely" \
  /home/ezotoff/src/opencode/packages/opencode/src/tool/shell/shell.txt \
  /home/ezotoff/src/opencode/packages/opencode/src/session/prompt/trinity.txt \
  /home/ezotoff/src/opencode/packages/opencode/src/session/prompt/default.txt
```

Expected: all 3 files listed.

```bash
# Verify the old blanket prohibition is removed
grep -cE "NEVER commit changes unless the user explicitly asks" \
  /home/ezotoff/src/opencode/packages/opencode/src/session/prompt/default.txt \
  /home/ezotoff/src/opencode/packages/opencode/src/session/prompt/trinity.txt
```

Expected: 0 matches in each file.

```bash
# Verify the old softened bullet (v1.17.x) is removed from shell.txt
grep -c "Only commit, amend, push, or create PRs when explicitly requested" \
  /home/ezotoff/src/opencode/packages/opencode/src/tool/shell/shell.txt
```

Expected: 0 matches.

**Binary-level verification** (after rebuild — the prompt text is compiled into the Bun binary at build time, NOT loaded from filesystem at runtime):

```bash
# Verify the canonical text is embedded in the binary
strings ~/.opencode/bin/opencode | grep -c "may create local commits freely"
```
Expected: 3 (one per prompt file).

```bash
# Verify old prohibition is absent from binary
strings ~/.opencode/bin/opencode | grep -c "NEVER commit changes unless the user explicitly asks"
```
Expected: 0.

## Reapply Instructions

If this patch is lost after an OpenCode update (git pull, rebase, `opencode upgrade`, or upstream change):

**IMPORTANT**: The prompt text files (`shell.txt`, `default.txt`, `trinity.txt`) are imported via Bun's `import X from "./file.txt"` syntax, which embeds them at compile time. **A binary rebuild is REQUIRED for the patch to take runtime effect.** Simply editing the source files does NOT affect the running binary — the patch will be inert until a rebuild.

### Step 1: Edit source files

1. `packages/opencode/src/tool/shell/shell.txt` line 14: Replace `- Only commit, amend, push, or create PRs when explicitly requested.` with:
   ```
   - Agents may create local commits freely for atomic changes and partial-progress saves — no need to ask first. This user uses git primarily for agent work.
   ```
   (The surrounding safety bullets — inspect git status, never commit secrets, do not push/force-push/amend — are already present and need no change.)

2. `packages/opencode/src/session/prompt/default.txt` line 76: Replace `NEVER commit changes unless the user explicitly asks you to...` with the canonical text.

3. `packages/opencode/src/session/prompt/trinity.txt` line 78: Same replacement as default.txt.

### Step 2: Rebuild the binary

```bash
cd /home/ezotoff/src/opencode/packages/opencode
bun run script/build.ts --single --skip-embed-web-ui --skip-install
```

The `--single` flag builds only for the current platform (linux-x64). The `--skip-embed-web-ui` flag skips the browser dashboard UI bundling (not needed for TUI-only usage). Output: `dist/opencode-linux-x64/bin/opencode`.

### Step 3: Install the patched binary

```bash
# Backup current binary first
cp ~/.opencode/bin/opencode ~/.opencode/bin/opencode.backup-$(~/.opencode/bin/opencode --version)
# Install patched binary
cp /home/ezotoff/src/opencode/packages/opencode/dist/opencode-linux-x64/bin/opencode ~/.opencode/bin/opencode
```

### Step 4: Verify

Run the binary-level verification commands above. Restart OpenCode for changes to take effect.

### Canonical Replacement Text

```
Git commits: follow the active git workflow. Agents may create local commits freely for atomic changes and partial-progress saves — no need to ask first. This user uses git primarily for agent work. Before committing, inspect staged/untracked changes and never commit secrets, credentials, auth files, or unrelated work. Do not push, force-push, amend, rebase, or run destructive git commands unless explicitly authorized.
```

## Durable Alternative

Upstream OpenCode could:
- Replace the blanket no-commit rule with a configurable commit policy that respects workflow authorizations.
- Expose an agent-internal setting (e.g., `commitPolicy: "ask" | "workflow-authorized" | "allow"`) that project configs can set.
- Add a `commit` capability declaration to skills so the system can reconcile conflicting commit instructions automatically.

Status: not-yet-pursued

## Revision History

| Revision | Date       | Change                                                                                                                                          |
|----------|------------|------------------------------------------------------------------------------------------------------------------------------------------------|
| v1       | 2026-05-02 | Initial canonical text: "A local commit is allowed when the user requested one or when a loaded project/skill workflow explicitly calls for checkpoint or logical-task commits. If no active workflow calls for a commit, ask first." |
| v2       | 2026-06-21 | Removed "ask first" clause. New canonical text: "Agents may create local commits freely for atomic changes and partial-progress saves — no need to ask first. This user uses git primarily for agent work." The v1 "ask first" clause was generating passive "ready to commit when you're ready" turn-endings in the common case where no skill was explicitly loaded. The user's git workflow is agent-driven, so asking added friction without value. Safety guardrails (no secrets, no push/force-push, no destructive) are preserved unchanged. Verification step added to catch stale v1 patches. |
| v3       | 2026-06-22 | Updated for OpenCode v1.17.9. `bash.txt` was REMOVED upstream and replaced by templated `shell/shell.txt` + `shell/prompt.ts`. Patch target moved from `tool/bash.txt` to `tool/shell/shell.txt` line 14 (single bullet within `# Git and GitHub` section). Discovered that prompt text is compiled into the Bun binary at build time via `import X from "./file.txt"` — the previous claim "No rebuild is needed" was FALSE; the patch had been inert since v1. Binary rebuild via `bun run script/build.ts --single --skip-embed-web-ui` is now documented in reapply instructions. Built patched v1.17.9 binary (140 MB) installed to `~/.opencode/bin/opencode`; official unpatched v1.17.9 (167 MB) kept as `opencode.backup-1.17.9-official`. |
