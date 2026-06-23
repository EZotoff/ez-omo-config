# Plugins

This directory packages OpenCode plugins copied from the local plugin registry for reuse in `ez-omo-config`.

## Included plugins

- `worktree.ts` — creates isolated git worktrees for AI sessions and coordinates session state plus terminal spawning.
- `worktree/state.ts` — SQLite-backed persistence for worktree session state and pending operations used by `worktree.ts`.
- `worktree/terminal.ts` — cross-platform terminal spawning and tmux helpers used by `worktree.ts`.
- `git-safety.ts` — blocks destructive shell and git commands and reports working tree safety before risky operations.
- `review-enforcer.ts` — injects review workflow instructions after task completion so plan execution gets reviewed consistently.
- `auto-checkpoint.ts` — semantic session-scoped git checkpointing. Disabled by default for TUI startup safety; set `OPENCODE_AUTO_CHECKPOINT_ENABLE=1` to enable. Uses an ephemeral LLM helper session to select files and compose commit messages from a bounded candidate set, with temp-index safety and skip-on-ambiguity guards.
- `session-id.ts` — copies the invoking session ID to clipboard via `/session-id`, no LLM round-trip.
- `session-info.ts` — copies `Project <path>:<branch>; Session <title>; ID <session-id>` to clipboard via `/session-info` command, no LLM round-trip.
- `vera-runtime.ts` — records per-workspace Vera state without blocking session startup, offers opt-in watcher supervision, and fails open when the `vera` binary is unavailable.
- `subagent-loop-guard.ts` — configured to detect high-frequency same-tool loops and same-tool varying-input loops per session, mutate bash commands to a loop-guard no-op when a configured block rule fires, and log an informational warning past the configured total-call threshold. It is fail-open and stores only the last 50 calls per active session in memory.
- `clickable-links.ts` — injects a system-prompt instruction on every session (root + subagent, all agents, all models) via `experimental.chat.system.transform` telling the model to format file references as `[label](file:///abs/path)` markdown links so they are clickable in the TUI. Closes the gap between the built-in prompts' aspirational "inline-code paths are clickable" claim and the OpenTUI renderer, which only makes real markdown links clickable (OSC 8).
- `kdco-primitives/` — shared helpers used by the plugin bundle, including project ID lookup, shell escaping, tmux detection, temp paths, logging, timeout helpers, and shared types.

## Dependency notes

- `worktree.ts` depends on `./worktree/state` and `./worktree/terminal`, so those files must stay alongside it under `plugins/worktree/`.
- `worktree.ts`, `worktree/state.ts`, and `worktree/terminal.ts` all depend on `plugins/kdco-primitives/`.
- `vera-runtime.ts` is self-contained but coordinates with `scripts/worktree-post-create.sh`, `scripts/worktree-pre-delete.sh`, and `docs/worktree-state-schema.md` through the shared `vera-watchers/` state contract.
- `subagent-loop-guard.ts` is self-contained. Runtime thresholds are read once at plugin init from `OMO_LOOP_GUARD_WINDOW_A`, `OMO_LOOP_GUARD_N_A`, `OMO_LOOP_GUARD_WINDOW_B`, `OMO_LOOP_GUARD_N_B`, `OMO_LOOP_GUARD_INFO_THRESHOLD`, `OMO_LOOP_GUARD_COOLDOWN_MS`, and `OMO_LOOP_GUARD_DISABLE`.
- `kdco-primitives/` should be installed with the rest of the plugin bundle; moving or removing it breaks worktree-related imports.

## Portability

- Files are copied as-is from the source plugin bundle.
- This repo intentionally avoids hardcoded personal paths or embedded secrets in the packaged plugin sources.
