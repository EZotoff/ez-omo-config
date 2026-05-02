---
patch_id: "opencode--commit-policy-unblock"
dependency: "opencode"
target_file: "packages/opencode/src/tool/bash.txt"
target_install_path: "/home/ezotoff/src/opencode"
status: "active"
applied_date: "2026-05-02"
dep_version: "current"
upstream_issue: "none"
verification_pattern: "Git commits: follow the active git workflow"
---

# OpenCode Commit Policy: Unblock Workflow-Authorized Local Commits

## Problem

OpenCode's base system instructions contain a blanket prohibition on git commits:

> "Only create commits when requested by the user. If unclear, ask first."
> "NEVER commit changes unless the user explicitly asks you to. It is VERY IMPORTANT to only commit when explicitly asked..."

However, active project/skill workflows (git-master, auto-checkpoint) explicitly authorize local checkpoint or logical-task commits. These instructions are contradictory: the absolute no-commit rule blocks workflow-authorized commits, forcing agents to refuse legitimate task-required operations.

This patch replaces the blanket prohibition with a nuanced safe local-commit policy that allows workflow-authorized commits while preserving safety guardrails (no pushing, force-pushing, amending, rebasing, or destructive actions without explicit authorization).

## Patch Description

Three OpenCode instruction files are modified to replace absolute no-commit rules with the canonical replacement text.

### Source file 1: `packages/opencode/src/tool/bash.txt`

- Removes the blanket "Only create commits when requested by the user" block and its detailed elaboration ("NEVER commit changes unless the user explicitly asks you to...").
- Replaces with the safe local-commit policy that allows workflow-authorized commits.

### Source file 2: `packages/opencode/src/session/prompt/trinity.txt`

- Same replacement: removes the absolute no-commit rule, inserts the safe local-commit policy.

### Source file 3: `packages/opencode/src/session/prompt/default.txt`

- Same replacement: removes the absolute no-commit rule, inserts the safe local-commit policy.

### Canonical Replacement Text

> Git commits: follow the active git workflow. A local commit is allowed when the user requested one or when a loaded project/skill workflow explicitly calls for checkpoint or logical-task commits. If no active workflow calls for a commit, ask first. Before committing, inspect staged/untracked changes and never commit secrets, credentials, auth files, or unrelated work. Do not push, force-push, amend, rebase, or run destructive git commands unless explicitly authorized.

## Verification

```bash
# Verify all three source files contain the replacement text
grep -E "Git commits: follow the active git workflow" \
  /home/ezotoff/src/opencode/packages/opencode/src/tool/bash.txt \
  /home/ezotoff/src/opencode/packages/opencode/src/session/prompt/trinity.txt \
  /home/ezotoff/src/opencode/packages/opencode/src/session/prompt/default.txt
```

Expected: matches in all three files, each showing the safe local-commit policy text.

```bash
# Verify the old blanket prohibition is removed from all three files
grep -cE "NEVER commit changes unless the user explicitly asks" \
  /home/ezotoff/src/opencode/packages/opencode/src/tool/bash.txt \
  /home/ezotoff/src/opencode/packages/opencode/src/session/prompt/trinity.txt \
  /home/ezotoff/src/opencode/packages/opencode/src/session/prompt/default.txt
```

Expected: 0 matches in each file.

## Reapply Instructions

If this patch is lost after an OpenCode update (git pull, rebase, or upstream change):

1. Verify the live source path:
   ```bash
   ls /home/ezotoff/src/opencode/packages/opencode/src/tool/bash.txt
   ```

2. For each of the three target files, find the old blanket no-commit text and replace it with the canonical safe local-commit policy.

3. In `packages/opencode/src/tool/bash.txt`, look for the "Only create commits when requested by the user" paragraph and the detailed "NEVER commit changes" elaboration. Replace the entire block with the canonical text.

4. In `packages/opencode/src/session/prompt/trinity.txt`, find the same patterns and replace.

5. In `packages/opencode/src/session/prompt/default.txt`, find the same patterns and replace.

6. No rebuild is needed — these are runtime text files loaded on session start. Restart OpenCode for changes to take effect.

### Canonical Replacement Text

```
Git commits: follow the active git workflow. A local commit is allowed when the user requested one or when a loaded project/skill workflow explicitly calls for checkpoint or logical-task commits. If no active workflow calls for a commit, ask first. Before committing, inspect staged/untracked changes and never commit secrets, credentials, auth files, or unrelated work. Do not push, force-push, amend, rebase, or run destructive git commands unless explicitly authorized.
```

## Durable Alternative

Upstream OpenCode could:
- Replace the blanket no-commit rule with a configurable commit policy that respects workflow authorizations.
- Expose an agent-internal setting (e.g., `commitPolicy: "ask" | "workflow-authorized" | "allow"`) that project configs can set.
- Add a `commit` capability declaration to skills so the system can reconcile conflicting commit instructions automatically.

Status: not-yet-pursued
