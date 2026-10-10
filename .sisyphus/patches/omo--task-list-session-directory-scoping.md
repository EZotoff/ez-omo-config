---
patch_id: "omo--task-list-session-directory-scoping"
dependency: "oh-my-openagent"
target_file: "packages/omo-opencode/src/features/claude-tasks/storage.ts, packages/omo-opencode/src/tools/task/task-create.ts, packages/omo-opencode/src/tools/task/task-list.ts, packages/omo-opencode/src/tools/task/task-get.ts, packages/omo-opencode/src/tools/task/task-update.ts"
target_install_path: "/home/ezotoff/oh-my-openagent-v4.19.2"
status: "active"
applied_date: "2026-10-10"
dep_version: "4.19.2"
upstream_issue: "none"
verification_pattern: "getTaskDir(config, context.directory)"
runtime_effective: false
surfaces: "server-api (task_* tool execution inside opencode serve)"
note: "Source patch, fork commit 2a2fd5fcd, merge b6b94302c on branch fix/custom-patches-v4.19.2 (pushed to EZotoff/oh-my-openagent 2026-10-10 before status active). runtime_effective pending: both serve surfaces must restart to load the rebuilt dist and a live serve-hosted task_create must land in the session's project list, not the HOME list."
---

# Task list scoped to session directory, not server cwd

## Problem

`resolveTaskListId()` fell back to `basename(process.cwd())`. Inside `opencode serve` the plugin process cwd is the server's systemd `WorkingDirectory` (`/home/ezotoff`), so every hosted session in every project resolved the SAME task list (`~/.config/opencode/tasks/ezotoff/`) and contended on a single `.lock` file with a 2×100ms retry budget. Observed 2026-10-10: a veran session's `task_list` returned 773 tasks from ~335 unrelated sessions; 7 of 12 `task_create` calls in one turn failed `task_lock_unavailable` under cross-project lock contention.

## Patch Description

`getTaskDir` / `resolveTaskListId` / `listTaskFiles` accept the session's project directory (`ToolContext.directory` — the SDK type explicitly says "Prefer this over process.cwd()") and use `basename(directory)` when explicit overrides are absent. All four task tools (`create`/`list`/`get`/`update`) pass `context.directory` through. Precedence unchanged: `ULTRAWORK_TASK_LIST_ID` > `CLAUDE_CODE_TASK_LIST_ID` > `sisyphus.tasks.task_list_id` > session directory > `process.cwd()` (legacy CLI-run behavior preserved). Env/config overrides still force a shared list when explicitly set.

Consequence: task lists and locks become per-project-directory again; `opencode run` (own cwd) behavior unchanged.

## Verification

```bash
# Source: new signature + directory fallback present.
grep -n "directory?: string" packages/omo-opencode/src/features/claude-tasks/storage.ts

# Typecheck + tests (2026-10-10): bun run typecheck clean; bun test src/tools/task/ 104 pass, src/features/claude-tasks/ 37 pass.

# Rebuilt bundle carries the patch (dist is gitignored — rebuild required on any re-clone):
grep -c "getTaskDir(config, context.directory)" /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js   # 4

# Pushed to fork remote:
git -C /home/ezotoff/oh-my-openagent-v4.19.2 branch -r --contains 2a2fd5fcd   # origin/fix/custom-patches-v4.19.2
```

## Runtime Verification

1. Restart both serve surfaces (restart-with-continuation.sh --restart for opencode.service :3021 and opencode-interactive.service :3030) to load the rebuilt dist.
2. From a real project directory served by a long-running server (not `opencode run`), create a task via `task_create`; confirm the JSON lands under `~/.config/opencode/tasks/<project-basename>/`, NOT `tasks/ezotoff/`.
3. Confirm `task_list` in that session no longer returns cross-project tasks.
4. Then flip `runtime_effective: true` here.
