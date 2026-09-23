---
patch_id: "omo--task-hygiene-close-before-turn-end"
dependency: "oh-my-openagent"
target_file: "packages/omo-opencode/src/agents/sisyphus/glm-5-2.ts"
target_install_path: "/home/ezotoff/oh-my-openagent-v4.19.2"
status: "active"
applied_date: "2026-09-22"
dep_version: "4.19.2"
upstream_issue: "none"
verification_pattern: "stale lie in your own tracking list"
runtime_effective: true
surfaces: "n/a (prompt content, not rendering)"
note: "Source patch, fork commit ff320aa04 on branch feature/wake-journal-outbox (pushed to EZotoff/oh-my-openagent). runtime_effective true since 2026-09-23: both serve surfaces restarted post-rebuild and scratch-instance behavioral probe observed the amended close-before-turn-end behavior. 1-2wk metric re-audit (never-completed rate vs 36% baseline) remains open."
---

# Sisyphus glm-5-2 Task-Hygiene Rule (close tasks before turn end)

## Problem

Session-DB audit of 2026-09-22 (last 21 days, top-level sessions): Sisyphus on glm-5.3-flash creates tracking tasks in 70% of multi-prompt sessions (up from 53% under glm-5.3 full), but 36% of created tasks are never marked completed (glm-5.3 era: 54%, small sample). Spot checks showed most gaps are done-but-unmarked rather than genuinely forgotten — the work happened, the `task_update` bookkeeping did not. Stale open tasks then misdirect later turns in the same session (the agent re-reads a list that claims work is still in progress), producing the operator-observed focus/coordination loss across consecutive prompts.

## Patch Description

One rule appended to the `<tasks>` section of `buildGlm52TasksSection` in the GLM prompt variant (the variant `isGlmModel` selects for every "glm" model, including glm-5.3-flash):

> Before you end any turn, close every ${noun} you created via `${update}` — mark work done the moment it is verified, and explicitly hand off anything intentionally left open. A completed-but-unmarked ${noun} is a stale lie in your own tracking list: it misdirects your next turn and erodes coordination across a multi-prompt session.

Fork commit `ff320aa04`, branch `feature/wake-journal-outbox`, pushed to origin (EZotoff/oh-my-openagent) same day — satisfies the fork-push preservation rule before `status: active`.

## Verification

```bash
# Source: rule present in the tasks section template.
grep -c "stale lie in your own tracking list" /home/ezotoff/oh-my-openagent-v4.19.2/packages/omo-opencode/src/agents/sisyphus/glm-5-2.ts   # 1

# Typecheck of the touched package: clean exit.
# bun x tsgo --noEmit -p packages/omo-opencode/tsconfig.json   (run 2026-09-22, no output)

# Rebuilt bundle (bun run build 2026-09-22) carries the patch:
grep -c "stale lie in your own tracking list" /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js   # 1

# Pushed to fork remote:
git -C /home/ezotoff/oh-my-openagent-v4.19.2 branch -r --contains ff320aa04   # origin/feature/wake-journal-outbox
```

## Runtime Status
runtime_effective: true — verified live 2026-09-23. Both managed serve surfaces restarted 12:13/12:14 CEST after the 11:19 dist rebuild (opencode.service :3021, opencode-interactive.service :3030; fresh process start times via `ps -eo lstart,args`). Behavioral probe from a throwaway scratch instance (`/tmp/opencode/taskhyg.t5l5Nz`, glm-5.3-flash): model created two tasks, executed both, then explicitly emitted `task_update status=completed` for both before ending the turn, narrating "Marking them completed before finishing the turn" — the amended rule's exact shape. Open follow-up (separate from effectiveness): 1-2 week session-DB re-audit to confirm the never-completed rate drops from the 36% baseline before declaring the coordination problem fixed.
