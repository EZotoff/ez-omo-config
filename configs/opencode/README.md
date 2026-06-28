# OpenCode Core Configuration

This directory contains the portable OpenCode config bundle copied from the local OpenCode installation.

| File | What it configures | Install target |
|---|---|---|
| `AGENTS.md` | Global user-level agent instructions loaded by OpenCode on top of any project-level `AGENTS.md`. Currently mandates the `/deployment` skill before binding ports or launching dev/test servers and uses vanilla code discovery guidance. Atomic-install tag: `skills+configs`. | `$HOME/.config/opencode/AGENTS.md` |
| `opencode.json` | Main OpenCode configuration: enabled providers, plugins, models, limits, OpenCode compaction, and runtime defaults | `$HOME/.config/opencode/opencode.json` |
| `opencode.jsonc` | Local bash permission restrictions for destructive commands | `$HOME/.opencode/opencode.jsonc` |
| `magic-context.jsonc` | Disabled Magic Context configuration retained for rollback/reference | `$HOME/.config/opencode/magic-context.jsonc` |
| `dcp.jsonc.retired` | Retired DCP plugin configuration. Kept for historical reference. | Not installed |
| `provider-connect-retry.mjs` | Plugin that retries failed provider connections with bounded backoff, empty-response detection, and registry-driven error matching | `$HOME/.config/opencode/provider-connect-retry.mjs` |
| `retry-errors.json` | Retry registry consumed by the retry plugin | `$HOME/.config/opencode/retry-errors.json` |
| `aspect-dynamics.mjs` | Config-layer plugin: deterministic heuristic scoring and transcript-visible advisory nudge dispatch | `$HOME/.config/opencode/aspect-dynamics.mjs` |
| `aspect-dynamics/*.mjs` | 7 support modules: config, context, heuristics, session-state, sets, nudge, logging | `$HOME/.config/opencode/aspect-dynamics/` |
| `aspect-dynamics/sets/*.json` | Seed aspect sets | `$HOME/.config/opencode/aspect-dynamics/sets/` |
| `worktree.jsonc` | Worktree sync config and hook registration for automated worktree lifecycle management | `$HOME/.opencode/worktree.jsonc` |
| `extras/ocx.jsonc` | OCX registry configuration pointer used by the OCX CLI | `$HOME/.opencode/ocx.jsonc` |

## Registered Local Plugins

| Plugin | What it is configured to do | Install target |
|---|---|---|
| `subagent-loop-guard.ts` | Watches per-session tool-call windows, mutates bash loop calls to a no-op when configured rules fire, and logs threshold warnings. | `$HOME/.opencode/plugin/subagent-loop-guard.ts` |
| `clickable-links.ts` | Injects a system-prompt instruction so file references render as clickable markdown links in the TUI. | `$HOME/.opencode/plugin/clickable-links.ts` |
| `session-info.ts` | Intercepts `/session-info`, copies project/session metadata to clipboard, then sets `output.cancelled = true`. Requires the active `opencode--command-hook-cancellation` patch for true no-LLM behavior. | `$HOME/.opencode/plugin/session-info.ts` |
| `session-id.ts` | Intercepts `/session-id`, copies the invoking session ID to clipboard, then sets `output.cancelled = true`. Requires the active `opencode--command-hook-cancellation` patch. | `$HOME/.opencode/plugin/session-id.ts` |
| `vscode.ts` | Intercepts `/vscode`, launches VS Code in the current directory, then sets `output.cancelled = true`. Requires the active `opencode--command-hook-cancellation` patch. | `$HOME/.opencode/plugin/vscode.ts` |

## Worktree Lifecycle Automation

Two hook scripts automate worktree setup and teardown:

- **`scripts/worktree-post-create.sh`** — Runs after a worktree is created. Handles state creation, port allocation from the deployment registry, and Docker container start.
- **`scripts/worktree-pre-delete.sh`** — Runs before a worktree is deleted. Handles container stop, port freeing, and state cleanup.

Port allocation follows a three-tier contract: global project ranges, global project-owned service ports, and worktree-local dynamic allocations.

## Symlinked Config Behavior

Several files in this directory are symlinked from `~/.config/opencode/` into this repo. Editing either path edits the same file.

| File | Live Path | Notes |
|------|-----------|-------|
| `AGENTS.md` | `~/.config/opencode/AGENTS.md` | Global user-level agent instructions |
| `opencode.json` | `~/.config/opencode/opencode.json` | Main config with plugin array |
| `provider-connect-retry.mjs` | `~/.config/opencode/provider-connect-retry.mjs` | Retry plugin |
| `retry-errors.json` | `~/.config/opencode/retry-errors.json` | Error pattern registry |

Plugin files such as `$HOME/.opencode/plugin/*.ts` are not symlinked by this config table. They are installed by `install.sh` and require a separate install step after editing.
