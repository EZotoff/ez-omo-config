# OpenCode Core Configuration

This directory contains the portable OpenCode config bundle copied from the local OpenCode installation.

| File | What it configures | Install target |
|---|---|---|
| `opencode.json` | Main OpenCode configuration: enabled providers, plugins, models, limits, and runtime defaults | `$HOME/.config/opencode/opencode.json` |
| `opencode.jsonc` | Local bash permission restrictions for destructive commands | `$HOME/.opencode/opencode.jsonc` |
| `dcp.jsonc` | DCP plugin configuration with bounded range archive retention (local patch) | `$HOME/.config/opencode/dcp.jsonc` |
| `provider-connect-retry.mjs` | Plugin that retries failed provider connections with bounded backoff, empty-response detection, and registry-driven error matching | `$HOME/.config/opencode/provider-connect-retry.mjs` |
| `retry-errors.json` | Retry registry: error patterns, backoff schedules, nudge prompts, and fallback models consumed by the retry plugin | `$HOME/.config/opencode/retry-errors.json` |
| `aspect-dynamics.mjs` | Config-layer plugin: deterministic heuristic scoring and transcript-visible advisory nudge dispatch | `$HOME/.config/opencode/aspect-dynamics.mjs` |
| `aspect-dynamics/*.mjs` | 7 support modules: config, context, heuristics, session-state, sets, nudge, logging | `$HOME/.config/opencode/aspect-dynamics/` |
| `aspect-dynamics/sets/*.json` | Seed aspect sets (e.g., `emotions-v1`) | `$HOME/.config/opencode/aspect-dynamics/sets/` |
| `worktree.jsonc` | Worktree sync config and hook registration for automated worktree lifecycle management | `$HOME/.opencode/worktree.jsonc` |
| `extras/ocx.jsonc` | OCX registry configuration pointer used by the OCX CLI | `$HOME/.opencode/ocx.jsonc` |

## Worktree Lifecycle Automation

Two hook scripts automate worktree setup and teardown:

- **`scripts/worktree-post-create.sh`** — Runs after a worktree is created. Handles state creation, port allocation, Docker container start, and Vera index bootstrapping.
- **`scripts/worktree-pre-delete.sh`** — Runs before a worktree is deleted. Handles container stop, port freeing, state cleanup, and Vera watcher cleanup.

These hooks are registered in `worktree.jsonc` and are invoked automatically by the worktree plugin. No manual intervention is needed.

## Symlinked Config Behavior

Several files in this directory are **symlinked** from `~/.config/opencode/` into this repo. Editing either path edits the same file:

| File | Live Path | Notes |
|------|-----------|-------|
| `opencode.json` | `~/.config/opencode/opencode.json` | Main config with plugin array |
| `provider-connect-retry.mjs` | `~/.config/opencode/provider-connect-retry.mjs` | Retry plugin |
| `retry-errors.json` | `~/.config/opencode/retry-errors.json` | Error pattern registry |

**Important**: Plugin files such as `$HOME/.opencode/plugin/*.ts` are **not** symlinked. They are copied by `install.sh` and require a separate install step after editing.

## Portability notes

- Hardcoded personal paths were normalized to `$HOME` notation.
- Configuration values and experimental settings were otherwise preserved as-is.
- The copied files were checked for obvious API keys, tokens, and private key material before adding them to the repo.
