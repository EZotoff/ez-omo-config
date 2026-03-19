# Plugins

This directory packages OpenCode plugins copied from the local plugin registry for reuse in `ez-omo-config`.

## Included plugins

- `worktree.ts` — creates isolated git worktrees for AI sessions and coordinates session state plus terminal spawning.
- `worktree/state.ts` — SQLite-backed persistence for worktree session state and pending operations used by `worktree.ts`.
- `worktree/terminal.ts` — cross-platform terminal spawning and tmux helpers used by `worktree.ts`.
- `git-safety.ts` — blocks destructive shell and git commands and reports working tree safety before risky operations.
- `review-enforcer.ts` — injects review workflow instructions after task completion so plan execution gets reviewed consistently.
- `auto-checkpoint.ts` — automatically creates git checkpoint commits when sessions become idle or tasks complete, with quiescence-based safety guards.
- `kdco-primitives/` — shared helpers used by the plugin bundle, including project ID lookup, shell escaping, tmux detection, temp paths, logging, timeout helpers, and shared types.

## Dependency notes

- `worktree.ts` depends on `./worktree/state` and `./worktree/terminal`, so those files must stay alongside it under `plugins/worktree/`.
- `worktree.ts`, `worktree/state.ts`, and `worktree/terminal.ts` all depend on `plugins/kdco-primitives/`.
- `kdco-primitives/` should be installed with the rest of the plugin bundle; moving or removing it breaks worktree-related imports.

## Portability

- Files are copied as-is from the source plugin bundle.
- This repo intentionally avoids hardcoded personal paths or embedded secrets in the packaged plugin sources.
