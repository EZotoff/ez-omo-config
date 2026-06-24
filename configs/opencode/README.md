# OpenCode Core Configuration

This directory contains the portable OpenCode config bundle copied from the local OpenCode installation.

| File | What it configures | Install target |
|---|---|---|
| `AGENTS.md` | Global user-level agent instructions loaded by OpenCode on top of any project-level `AGENTS.md`. Currently mandates the `/deployment` skill before binding ports or launching dev/test servers. Atomic-install tag: `skills+configs` — installs with `--skills` (alongside the `/deployment` skill) AND with `--configs`. | `$HOME/.config/opencode/AGENTS.md` |
| `opencode.json` | Main OpenCode configuration: enabled providers, plugins, models, limits, OpenCode compaction (`compaction.auto=true`, `compaction.prune=true`), and runtime defaults | `$HOME/.config/opencode/opencode.json` |
| `opencode.jsonc` | Local bash permission restrictions for destructive commands | `$HOME/.opencode/opencode.jsonc` |
| `magic-context.jsonc` | Disabled Magic Context configuration retained for rollback/reference (`enabled=false`; plugin is not registered in `opencode.json`) | `$HOME/.config/opencode/magic-context.jsonc` |
| `dcp.jsonc.retired` | Retired DCP plugin configuration. Magic Context was tried as the replacement on 2026-06-23 and is currently disabled. Kept for historical reference. | Not installed |
| `provider-connect-retry.mjs` | Plugin that retries failed provider connections with bounded backoff, empty-response detection, and registry-driven error matching | `$HOME/.config/opencode/provider-connect-retry.mjs` |
| `retry-errors.json` | Retry registry: error patterns, backoff schedules, nudge prompts, and fallback models consumed by the retry plugin | `$HOME/.config/opencode/retry-errors.json` |
| `aspect-dynamics.mjs` | Config-layer plugin: deterministic heuristic scoring and transcript-visible advisory nudge dispatch | `$HOME/.config/opencode/aspect-dynamics.mjs` |
| `aspect-dynamics/*.mjs` | 7 support modules: config, context, heuristics, session-state, sets, nudge, logging | `$HOME/.config/opencode/aspect-dynamics/` |
| `aspect-dynamics/sets/*.json` | Seed aspect sets (e.g., `emotions-v1`, `emotions-v2`) | `$HOME/.config/opencode/aspect-dynamics/sets/` |
| `worktree.jsonc` | Worktree sync config and hook registration for automated worktree lifecycle management | `$HOME/.opencode/worktree.jsonc` |
| `extras/ocx.jsonc` | OCX registry configuration pointer used by the OCX CLI | `$HOME/.opencode/ocx.jsonc` |

## Registered Local Plugins

| Plugin | What it is configured to do | Install target |
|---|---|---|
| `subagent-loop-guard.ts` | Configured to watch per-session tool-call windows, mutate bash loop calls to a no-op when Rule A or Rule B fires, and log a Rule C warning after the configured total-call threshold. Evidence state: `repo_implemented`, `active_config_registered`; not verified live: `runtime_loaded`, `real_project_behavior_proven`. | `$HOME/.opencode/plugin/subagent-loop-guard.ts` |
| `clickable-links.ts` | Injects a system-prompt instruction on every session via `experimental.chat.system.transform` so file references render as clickable `[label](file:///abs/path)` markdown links in the TUI. Closes the gap between built-in prompts (which claim backtick paths are clickable) and the OpenTUI renderer (which only linkifies real markdown links). Evidence state: `repo_implemented`, `active_config_registered`; not verified live: `runtime_loaded`, `real_project_behavior_proven`. | `$HOME/.opencode/plugin/clickable-links.ts` |

## Worktree Lifecycle Automation

Two hook scripts automate worktree setup and teardown:

- **`scripts/worktree-post-create.sh`** — Runs after a worktree is created. Handles state creation, port allocation from the deployment registry, Docker container start, and manual-by-default Vera state recording. Set `OMO_VERA_RUNTIME_AUTOSTART=1` to allow synchronous Vera index bootstrapping.
- **`scripts/worktree-pre-delete.sh`** — Runs before a worktree is deleted. Handles container stop, port freeing, state cleanup, and Vera watcher cleanup.

These hooks are registered in `worktree.jsonc` and are invoked automatically by the worktree plugin. No manual intervention is needed.

## Vera Runtime Startup Mode

`plugins/vera-runtime.ts` is installed under `$HOME/.opencode/plugin/` and records per-workspace Vera state without blocking OpenCode startup by default. Leave `OMO_VERA_RUNTIME_AUTOSTART` unset/false to keep first-time and large-project launches responsive; set `OMO_VERA_RUNTIME_AUTOSTART=1` only when synchronous watcher bootstrap/recovery is acceptable. Leave `OMO_VERA_RUNTIME_TOOL_UPDATE` unset/false to prevent `tool.execute.before` from running `vera update .`; set it to `1` only when synchronous pre-tool updates are acceptable.

Port allocation now follows a three-tier contract:

1. `~/.sisyphus/ports.json` `ranges` reserves a contiguous range per project.
2. `~/.sisyphus/ports.json` `ports` reserves project-owned service ports inside that range.
3. `~/.local/share/opencode/worktree-state/<project>/ports.json` records dynamic worktree allocations.

When a worktree is created, `worktree-post-create.sh` picks the next free port inside the reserved range, skipping both globally reserved service ports and already-allocated worktree ports.

## Symlinked Config Behavior

Several files in this directory are **symlinked** from `~/.config/opencode/` into this repo. Editing either path edits the same file:

| File | Live Path | Notes |
|------|-----------|-------|
| `AGENTS.md` | `~/.config/opencode/AGENTS.md` | Global user-level agent instructions (deployment-skill mandate) |
| `opencode.json` | `~/.config/opencode/opencode.json` | Main config with plugin array |
| `provider-connect-retry.mjs` | `~/.config/opencode/provider-connect-retry.mjs` | Retry plugin |
| `retry-errors.json` | `~/.config/opencode/retry-errors.json` | Error pattern registry |

**Important**: Plugin files such as `$HOME/.opencode/plugin/*.ts` are **not** symlinked. They are copied by `install.sh` and require a separate install step after editing.

## Portability notes

- Hardcoded personal paths were normalized to `$HOME` notation.
- Configuration values and experimental settings were otherwise preserved as-is.
- The copied files were checked for obvious API keys, tokens, and private key material before adding them to the repo.
