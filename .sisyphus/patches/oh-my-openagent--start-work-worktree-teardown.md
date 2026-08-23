---
patch_id: "oh-my-openagent--start-work-worktree-teardown"
dependency: "oh-my-openagent"
target_file: "dist/skills/start-work/SKILL.md"
target_install_path: "/home/ezotoff/oh-my-openagent-v4.19.2/dist/skills/start-work/SKILL.md"
status: "active"
applied_date: "2026-08-23"
dep_version: "4.19.2"
runtime_effective: true
upstream_issue: "none"
verification_pattern: "A worktree left behind is a leak"
surfaces: []
---

# start-work: direct-mode worktree teardown step

## Problem

`/start-work` Completion step 2 covered worktree teardown only for `--make-pr` mode ("remove the worktree only after successful merge or explicit handoff"). Direct-mode executions (the default for `plan/*` worktree runs via `worktree_start`) had no teardown instruction at all. Combined with the old `agent-git-workflow.ts` Branch lifecycle block (which prescribed `git checkout master && git branch -D`, impossible/unsafe for worktree branches), this produced a 14/14 worktree+branch leak rate: allocation was automated, reclamation was never specified.

## Patch Description

Adds a new Completion step 3 (renumbering the old 3-4 to 4-5): for direct (non-PR) worktree executions, reclaim before finishing — merge `--no-ff`, remove worktree, `git branch -d` (never `-D`) or `worktree_delete` with target; dirty worktrees must be diffed and ported or explicitly declared discarded; teardown recorded as a cleanup receipt in the ORCHESTRATION COMPLETE block.

Companion fixes (this repo, not OMO): `plugins/agent-git-workflow.ts` worktree-aware Branch lifecycle block, `plugins/worktree.ts` `worktree_delete` target parameter + merged-only branch deletion.

## Verification

Plain-text skill file (not minified) — pattern-presence IS content-presence here:

```bash
grep -c "A worktree left behind is a leak" /home/ezotoff/oh-my-openagent-v4.19.2/dist/skills/start-work/SKILL.md
# 1 = applied, 0/missing = lost to an OMO update re-extract
```

## Runtime Verification

- Load the skill in a fresh session (`skill` tool, name `start-work`) and confirm the Completion section includes the reclaim step for direct-mode worktrees.
- Regression signal: a completed direct-mode plan whose ORCHESTRATION COMPLETE block lacks a worktree teardown receipt.
