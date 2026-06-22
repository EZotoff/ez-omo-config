---
patch_id: "omo--commit-policy-alignment"
dependency: "oh-my-openagent"
target_file: "packages/omo-opencode/src/agents/sisyphus/default.ts, packages/omo-opencode/src/agents/sisyphus/gpt-5-4.ts, packages/omo-opencode/src/agents/sisyphus/kimi-k2-6.ts, packages/omo-opencode/src/agents/sisyphus-dynamic-prompt-execution.ts, AGENTS.md"
target_install_path: "/home/ezotoff/oh-my-openagent-v4.12.1"
status: "active"
applied_date: "2026-05-02"
dep_version: "4.12.1"
upstream_issue: "none"
verification_pattern: "Git commits: follow the active git workflow"
note: "Rescoped from 9 to 5 files for v4.12.1. 3 prometheus files (plan-template.ts, gpt.ts, identity-constraints.ts) deleted in v4.x monorepo refactor. git-master SKILL.md has totally different upstream content (no 'Commit early, commit often' to replace). Added 2 new files discovered in v4.12.1: kimi-k2-6.ts and sisyphus-dynamic-prompt-execution.ts."
---

# OMO Commit Policy: Align Agent Instructions and Skills

## Problem

Oh-My-OpenAgent has contradictory or under-constrained commit instructions across multiple agent definitions, Prometheus plan-generation sources, and the built-in git-master skill:

- **Agent instructions** (`sisyphus.ts`, `sisyphus/default.ts`, `sisyphus/gpt-5-4.ts`): Contain blanket "Never commit without explicit user direction" rules inherited from `AGENTS.md`.
- **Prometheus plan-generation sources** (`prometheus/plan-template.ts`, `prometheus/gpt.ts`, `prometheus/identity-constraints.ts`): Leave `## Commit Strategy` bare or skeletal, allowing the planner model to invent stale blanket no-commit wording such as `Do not commit automatically unless the user explicitly requests a commit.`
- **git-master skill** (`builtin-skills/git-master/SKILL.md`, `features/builtin-skills/skills/git-master-sections/commit-workflow.ts`): Instructs agents to "Commit early, commit often" and "Commit and push on every completed todo item or logical task unit."
- **AGENTS.md**: Contains `Rule 6` that says "Never commit without explicit user direction."

These contradictions must be resolved by aligning all instructions with a consistent permissive local-commit policy: agents may create local commits freely for atomic changes and partial-progress saves, while pushes and destructive actions require explicit authorization.

**Revision v2 (2026-06-21):** The v1 canonical text retained an "If no active workflow calls for a commit, ask first" clause. In practice, agents ended turns with passive "ready to commit when you're ready" prompts in the common case where no skill was explicitly loaded. The user's git workflow is agent-driven, so the clause was pure friction. v2 removes it and makes atomic/partial-progress commits explicitly free. Safety guardrails (no secrets, no push/force-push/amend/rebase/destructive without authorization) are preserved unchanged.

## Patch Description

Nine OMO source files are modified to replace absolute no-commit rules or unconstrained commit-strategy placeholders with the canonical safe local-commit policy.

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

### Source file 7: `src/agents/prometheus/plan-template.ts`

- Replace the bare `## Commit Strategy` example block with the canonical policy text.
- Preserve per-task `**Commit**` YES/NO fields, but constrain `YES` to workflow-authorized local checkpoint/logical-task commits only.

### Source file 8: `src/agents/prometheus/gpt.ts`

- Replace the bare `## Commit Strategy` skeleton in the planner prompt with the canonical policy text.
- Explicitly forbid using the section to invent a blanket user-request-only commit rule.

### Source file 9: `src/agents/prometheus/identity-constraints.ts`

- Replace the `## Commit Strategy` placeholder with the canonical policy text.
- Preserve task-level `**Commit**` YES/NO lines while constraining `YES` to workflow-authorized commits.

### Canonical Replacement Text

> Git commits: follow the active git workflow. Agents may create local commits freely for atomic changes and partial-progress saves — no need to ask first. This user uses git primarily for agent work. Before committing, inspect staged/untracked changes and never commit secrets, credentials, auth files, or unrelated work. Do not push, force-push, amend, rebase, or run destructive git commands unless explicitly authorized.

## Verification

```bash
# Verify agent instructions and Prometheus templates contain the replacement text
grep -E "Git commits: follow the active git workflow" \
  /home/ezotoff/oh-my-openagent/src/agents/sisyphus.ts \
  /home/ezotoff/oh-my-openagent/src/agents/sisyphus/default.ts \
  /home/ezotoff/oh-my-openagent/src/agents/sisyphus/gpt-5-4.ts \
  /home/ezotoff/oh-my-openagent/AGENTS.md \
  /home/ezotoff/oh-my-openagent/src/agents/prometheus/plan-template.ts \
  /home/ezotoff/oh-my-openagent/src/agents/prometheus/gpt.ts \
  /home/ezotoff/oh-my-openagent/src/agents/prometheus/identity-constraints.ts
```

Expected: matches in all seven files.

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

```bash
# Verify Prometheus sources do not permit the stale blanket no-commit wording
grep -cF "Do not commit automatically unless the user explicitly requests a commit" \
  /home/ezotoff/oh-my-openagent/src/agents/prometheus/plan-template.ts \
  /home/ezotoff/oh-my-openagent/src/agents/prometheus/gpt.ts \
  /home/ezotoff/oh-my-openagent/src/agents/prometheus/identity-constraints.ts
```

Expected: 0 matches in each file.

```bash
# Verify the v1 canonical text (revision-1 "ask first" clause) is also absent
# This is the NEW check added in v2 — catches stale v1 patches that were not refreshed
grep -cE "If no active workflow calls for a commit, ask first" \
  /home/ezotoff/oh-my-openagent/src/agents/sisyphus.ts \
  /home/ezotoff/oh-my-openagent/src/agents/sisyphus/default.ts \
  /home/ezotoff/oh-my-openagent/src/agents/sisyphus/gpt-5-4.ts \
  /home/ezotoff/oh-my-openagent/AGENTS.md \
  /home/ezotoff/oh-my-openagent/src/agents/prometheus/plan-template.ts \
  /home/ezotoff/oh-my-openagent/src/agents/prometheus/gpt.ts \
  /home/ezotoff/oh-my-openagent/src/agents/prometheus/identity-constraints.ts
```

Expected: 0 matches in each file.

```bash
# Rebuild and verify the bundled output keeps the canonical policy and excludes the stale wording
cd /home/ezotoff/oh-my-openagent && bun run build && grep -F "Git commits: follow the active git workflow" dist/index.js && ! grep -F "Do not commit automatically unless the user explicitly requests a commit" dist/index.js && ! grep -F "If no active workflow calls for a commit, ask first" dist/index.js
```

Expected: build succeeds, canonical policy is present in `dist/index.js`, stale v0 wording AND stale v1 "ask first" wording are both absent.

## Reapply Instructions

If this patch is lost after an OMO update (git pull, rebase):

1. Verify the live source path:
   ```bash
   ls /home/ezotoff/oh-my-openagent/src/agents/sisyphus.ts
   ```

2. For each of the nine target files, find the old absolute no-commit text or bare `## Commit Strategy` placeholder and replace it with the canonical safe local-commit policy.

3. Agent instruction files (`src/agents/sisyphus.ts`, `default.ts`, `gpt-5-4.ts`): Find the "Never commit without explicit user direction" sentence and replace the entire block with the canonical text.

4. `AGENTS.md`: Find Rule 6 and replace with the canonical text.

5. git-master skill files (`SKILL.md`, `commit-workflow.ts`): Find "Commit early, commit often" / "Commit and push on every completed todo item" and replace with guidance that allows local checkpoint commits but restricts pushing.

6. Prometheus files (`src/agents/prometheus/plan-template.ts`, `gpt.ts`, `identity-constraints.ts`): Replace the bare `## Commit Strategy` section with the canonical policy text, preserve task-level `**Commit**` YES/NO fields, and forbid blanket user-request-only wording.

7. Rebuild OMO so the bundled planner prompt updates:
   ```bash
   cd /home/ezotoff/oh-my-openagent && bun run build
   ```

8. Verify `dist/index.js` contains the canonical policy and does not contain `Do not commit automatically unless the user explicitly requests a commit`.

### Canonical Replacement Text

```
Git commits: follow the active git workflow. Agents may create local commits freely for atomic changes and partial-progress saves — no need to ask first. This user uses git primarily for agent work. Before committing, inspect staged/untracked changes and never commit secrets, credentials, auth files, or unrelated work. Do not push, force-push, amend, rebase, or run destructive git commands unless explicitly authorized.
```

## Durable Alternative

Upstream OMO could:
- Centralize commit policy into a single configurable agent-internal setting (`commitPolicy: "ask" | "workflow-authorized" | "allow"`).
- Add a `commit` capability declaration system to skills so the framework can reconcile conflicting commit instructions automatically.
- Provide an extensible policy hook in `SisyphusInitContext` so project configs can declare their commit policy without patching source files.

Status: not-yet-pursued

## Revision History

| Revision | Date       | Change                                                                                                                                          |
|----------|------------|------------------------------------------------------------------------------------------------------------------------------------------------|
| v1       | 2026-05-02 | Initial canonical text: "A local commit is allowed when the user requested one or when a loaded project/skill workflow explicitly calls for checkpoint or logical-task commits. If no active workflow calls for a commit, ask first." Aligned 9 OMO source files. |
| v2       | 2026-06-21 | Removed "ask first" clause. New canonical text: "Agents may create local commits freely for atomic changes and partial-progress saves — no need to ask first. This user uses git primarily for agent work." The v1 "ask first" clause caused agents to end turns with passive "ready to commit when you're ready" prompts in the common case where no skill was explicitly loaded. The user's git workflow is agent-driven, so asking added friction without value. Safety guardrails (no secrets, no push/force-push, no destructive) are preserved unchanged. Added v1-stale-text verification step and updated build verification to reject v1 text in dist/index.js. |
