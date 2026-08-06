# Plugins

This directory packages OpenCode plugins copied from the local plugin registry for reuse in `ez-omo-config`.

## Included plugins

- `worktree.ts` — creates isolated git worktrees for AI sessions and coordinates session state plus terminal spawning. The `worktree_start` tool resolves plans from both `.omo/plans/` (canonical, read by OMO's `/start-work`) and `.sisyphus/plans/` (legacy `/prometheus-plan` default); when a plan is found only at the legacy location, it is auto-copied to `.omo/plans/` before `/start-work` is dispatched, so the pipeline works regardless of which location the planner wrote to.
- `worktree/state.ts` — SQLite-backed persistence for worktree session state and pending operations used by `worktree.ts`.
- `worktree/terminal.ts` — cross-platform terminal spawning and tmux helpers used by `worktree.ts`.
- `git-safety.ts` — blocks destructive shell and git commands and reports working tree safety before risky operations. Three layers: (1) always-block non-git destructive ops (`rm -rf` non-safe targets, `chmod -R 777`, `dd of=/dev/`, etc.); (1.5) **history-rewrite block** — `git commit --amend`, `git rebase`, `git push --force*`, `git branch -D`, `git stash clear`, `git reflog expire`, `git gc --prune`, and `git reset <ref>` where `<ref>` is a strict ancestor of HEAD (always blocked, regardless of dirty state — catches the post-commit destructive case); (2) dirty-tree-conditional git destructive ops (`git reset --hard`, `git clean -f`, `git checkout -- .`, `git restore`, etc.). Status checks resolve the bash command's actual cwd (`workdir` arg → leading `cd <path>` → `ctx.directory`) so worktree work is covered, not just the OpenCode project root.
- `review-enforcer.ts` — injects review workflow instructions after task completion so plan execution gets reviewed consistently.
- `auto-checkpoint.ts` — semantic session-scoped git checkpointing. Disabled by default for TUI startup safety; set `OPENCODE_AUTO_CHECKPOINT_ENABLE=1` to enable.
- `session-id.ts` — copies the invoking session ID to clipboard via `/session-id`, then sets `output.cancelled = true`. True no-LLM behavior depends on the active `opencode--command-hook-cancellation` patch.
- `session-info.ts` — copies project path, git branch, session title, and invoking session ID to clipboard via `/session-info`, then sets `output.cancelled = true`. True no-LLM behavior depends on the active `opencode--command-hook-cancellation` patch.
- `clickable-links.ts` — injects a system-prompt instruction telling models to format file references as `[label](file:///abs/path)` markdown links so they are clickable in the TUI.
- `kdco-primitives/` — shared helpers used by the plugin bundle, including project ID lookup, shell escaping, tmux detection, temp paths, logging, timeout helpers, and shared types.

## Dependency notes

- `worktree.ts` depends on `./worktree/state` and `./worktree/terminal`, so those files must stay alongside it under `plugins/worktree/`.
- `worktree.ts`, `worktree/state.ts`, and `worktree/terminal.ts` all depend on `plugins/kdco-primitives/`.
- `kdco-primitives/` should be installed with the rest of the plugin bundle; moving or removing it breaks worktree-related imports.

## Portability

- Files are copied as-is from the source plugin bundle.
- This repo intentionally avoids hardcoded personal paths or embedded secrets in the packaged plugin sources.
