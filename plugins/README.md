# Plugins

This directory packages OpenCode plugins copied from the local plugin registry for reuse in `ez-omo-config`.

## Included plugins

- `worktree.ts` — creates isolated git worktrees for AI sessions and coordinates session state plus terminal spawning.
- `worktree/state.ts` — SQLite-backed persistence for worktree session state and pending operations used by `worktree.ts`.
- `worktree/terminal.ts` — cross-platform terminal spawning and tmux helpers used by `worktree.ts`.
- `git-safety.ts` — blocks destructive shell and git commands and reports working tree safety before risky operations.
- `review-enforcer.ts` — injects review workflow instructions after task completion so plan execution gets reviewed consistently.
- `auto-checkpoint.ts` — semantic session-scoped git checkpointing. Disabled by default for TUI startup safety; set `OPENCODE_AUTO_CHECKPOINT_ENABLE=1` to enable.
- `session-id.ts` — copies the invoking session ID to clipboard via `/session-id` without an LLM round-trip.
- `session-info.ts` — copies project path, git branch, session title, and invoking session ID to clipboard via `/session-info` without an LLM round-trip.
- `subagent-loop-guard.ts` — detects high-frequency same-tool loops and same-tool varying-input loops per session, mutates bash commands to a loop-guard no-op when a configured block rule fires, and logs an informational warning past the configured total-call threshold.
- `clickable-links.ts` — injects a system-prompt instruction telling models to format file references as `[label](file:///abs/path)` markdown links so they are clickable in the TUI.
- `kdco-primitives/` — shared helpers used by the plugin bundle, including project ID lookup, shell escaping, tmux detection, temp paths, logging, timeout helpers, and shared types.

## Dependency notes

- `worktree.ts` depends on `./worktree/state` and `./worktree/terminal`, so those files must stay alongside it under `plugins/worktree/`.
- `worktree.ts`, `worktree/state.ts`, and `worktree/terminal.ts` all depend on `plugins/kdco-primitives/`.
- `subagent-loop-guard.ts` is self-contained. Runtime thresholds are read once at plugin init from `OMO_LOOP_GUARD_WINDOW_A`, `OMO_LOOP_GUARD_N_A`, `OMO_LOOP_GUARD_WINDOW_B`, `OMO_LOOP_GUARD_N_B`, `OMO_LOOP_GUARD_INFO_THRESHOLD`, `OMO_LOOP_GUARD_COOLDOWN_MS`, and `OMO_LOOP_GUARD_DISABLE`.
- `kdco-primitives/` should be installed with the rest of the plugin bundle; moving or removing it breaks worktree-related imports.

## Portability

- Files are copied as-is from the source plugin bundle.
- This repo intentionally avoids hardcoded personal paths or embedded secrets in the packaged plugin sources.
