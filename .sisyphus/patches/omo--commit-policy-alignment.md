---
patch_id: "omo--commit-policy-alignment"
dependency: "oh-my-openagent"
target_file: "src/agents/sisyphus.ts"
target_install_path: "/home/ezotoff/oh-my-openagent"
status: "active"
applied_date: "2026-05-02"
dep_version: "current"
upstream_issue: "none"
verification_pattern: "Git commits: follow the active git workflow"
---

# OMO Commit Policy: Align Agent Instructions and Skills

## Problem

Oh-My-OpenAgent has contradictory commit instructions across multiple agent definitions and the built-in git-master skill:

- **Agent instructions** (`sisyphus.ts`, `sisyphus/default.ts`, `sisyphus/gpt-5-4.ts`): Contain blanket "Never commit without explicit user direction" rules inherited from `AGENTS.md`.
- **git-master skill** (`builtin-skills/git-master/SKILL.md`, `features/builtin-skills/skills/git-master-sections/commit-workflow.ts`): Instructs agents to "Commit early, commit often" and "Commit and push on every completed todo item or logical task unit."
- **AGENTS.md**: Contains `Rule 6` that says "Never commit without explicit user direction."

These contradictions must be resolved by aligning all instructions with a consistent safe local-commit policy: workflow-authorized local commits are allowed, but pushes and destructive actions require explicit authorization.

## Patch Description

Six OMO source files are modified to replace absolute no-commit rules with the canonical safe local-commit policy.

### Source file 1: `src/agents/sisyphus.ts`

- Replace the absolute "Never commit without explicit user direction" rule with the canonical safe local-commit policy text.

### Source file 2: `src/agents/sisyphus/default.ts`

- Same replacement as sisyphus.ts.

### Source file 3: `src/agents/sisyphus/gpt-5-4.ts`

- Same replacement as sisyphus.ts.

### Source file 4: `AGENTS.md`

- Replace Rule 6 ("Never commit without explicit user direction") with the canonical safe local-commit policy text.

### Source file 5: `src/features/builtin-skills/git-master/SKILL.md`

- Replace "Commit early, commit often" / "Commit and push on every completed todo item or logical task unit" with alignment text referencing the safe local-commit policy.
- Add note that local checkpoint commits are allowed but pushing requires authorization.

### Source file 6: `src/features/builtin-skills/skills/git-master-sections/commit-workflow.ts`

- Same alignment as SKILL.md: replace aggressive commit advice with policy-aligned guidance.

### Canonical Replacement Text

> Git commits: follow the active git workflow. A local commit is allowed when the user requested one or when a loaded project/skill workflow explicitly calls for checkpoint or logical-task commits. If no active workflow calls for a commit, ask first. Before committing, inspect staged/untracked changes and never commit secrets, credentials, auth files, or unrelated work. Do not push, force-push, amend, rebase, or run destructive git commands unless explicitly authorized.

## Verification

```bash
# Verify agent instructions contain the replacement text
grep -E "Git commits: follow the active git workflow" \
  /home/ezotoff/oh-my-openagent/src/agents/sisyphus.ts \
  /home/ezotoff/oh-my-openagent/src/agents/sisyphus/default.ts \
  /home/ezotoff/oh-my-openagent/src/agents/sisyphus/gpt-5-4.ts \
  /home/ezotoff/oh-my-openagent/AGENTS.md
```

Expected: matches in all four files.

```bash
# Verify git-master skill files reference the policy
grep -E "local commit|checkpoint" \
  /home/ezotoff/oh-my-openagent/src/features/builtin-skills/git-master/SKILL.md \
  /home/ezotoff/oh-my-openagent/src/features/builtin-skills/skills/git-master-sections/commit-workflow.ts
```

Expected: matches in both files showing policy-aligned commit guidance.

```bash
# Verify old no-commit rule is removed from agent instructions
grep -cE "Never commit without explicit user direction" \
  /home/ezotoff/oh-my-openagent/src/agents/sisyphus.ts \
  /home/ezotoff/oh-my-openagent/src/agents/sisyphus/default.ts \
  /home/ezotoff/oh-my-openagent/src/agents/sisyphus/gpt-5-4.ts
```

Expected: 0 matches in each file.

## Reapply Instructions

If this patch is lost after an OMO update (git pull, rebase):

1. Verify the live source path:
   ```bash
   ls /home/ezotoff/oh-my-openagent/src/agents/sisyphus.ts
   ```

2. For each of the six target files, find the old absolute no-commit text and replace it with the canonical safe local-commit policy.

3. Agent instruction files (`src/agents/sisyphus.ts`, `default.ts`, `gpt-5-4.ts`): Find the "Never commit without explicit user direction" sentence and replace the entire block with the canonical text.

4. `AGENTS.md`: Find Rule 6 and replace with the canonical text.

5. git-master skill files (`SKILL.md`, `commit-workflow.ts`): Find "Commit early, commit often" / "Commit and push on every completed todo item" and replace with guidance that allows local checkpoint commits but restricts pushing.

6. No rebuild is needed — these are source files loaded at session start. Restart OpenCode for changes to take effect.

### Canonical Replacement Text

```
Git commits: follow the active git workflow. A local commit is allowed when the user requested one or when a loaded project/skill workflow explicitly calls for checkpoint or logical-task commits. If no active workflow calls for a commit, ask first. Before committing, inspect staged/untracked changes and never commit secrets, credentials, auth files, or unrelated work. Do not push, force-push, amend, rebase, or run destructive git commands unless explicitly authorized.
```

## Durable Alternative

Upstream OMO could:
- Centralize commit policy into a single configurable agent-internal setting (`commitPolicy: "ask" | "workflow-authorized" | "allow"`).
- Add a `commit` capability declaration system to skills so the framework can reconcile conflicting commit instructions automatically.
- Provide an extensible policy hook in `SisyphusInitContext` so project configs can declare their commit policy without patching source files.

Status: not-yet-pursued
