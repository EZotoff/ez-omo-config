# OpenCode Core Configuration

This directory contains the portable OpenCode config bundle copied from the local OpenCode installation.

| File | What it configures | Install target |
|---|---|---|
| `AGENTS.md` | Global user-level agent instructions loaded by OpenCode on top of any project-level `AGENTS.md`. Currently mandates the `/deployment` skill before binding ports or launching dev/test servers, uses vanilla code discovery guidance, and mandates plan-execution records: every executed plan appends `Execution baseline:` to its `## Execution Record` before dispatch and `F#<n>: <verdict>` lines at closeout, with `verify-built` flagging missing records as GAPs. Atomic-install tag: `skills+configs`. | `$HOME/.config/opencode/AGENTS.md` |
| `opencode.json` | Main OpenCode configuration: enabled providers, plugins, models, limits, OpenCode compaction, runtime defaults, and the pinned default agent (`default_agent: Sisyphus`). Local repo plugins and the patched OMO fork all use config-relative paths (no machine-specific paths). | `$HOME/.config/opencode/opencode.json` |
| `opencode.jsonc` | Local bash permission restrictions for destructive commands | `$HOME/.opencode/opencode.jsonc` |
| `magic-context.jsonc` | Disabled Magic Context configuration retained for rollback/reference | `$HOME/.config/opencode/magic-context.jsonc` |
| `dcp.jsonc.retired` | Retired DCP plugin configuration. Kept for historical reference. | Not installed |
| `provider-connect-retry.mjs` | Plugin that retries failed provider connections with bounded backoff, empty-response and near-empty detection (zero-token and child-only sub-threshold stalls), per-server-process startup heartbeat, registry-driven error matching, and compaction-mode failure fallback: retries compaction through the registry's `compaction_fallback_models` chain via `session.summarize` | `$HOME/.config/opencode/provider-connect-retry.mjs` |
| `retry-errors.json` | Retry registry consumed by the retry plugin, including the dedicated `compaction_fallback_models` chain for compaction-mode failures | `$HOME/.config/opencode/retry-errors.json` |
| `agent-default-guard.mjs` | Config-layer plugin: rewrites incoming chat messages that explicitly request the demoted `build` agent to the configured `default_agent` before persistence (neutralizes OC Beacon's hardcoded client-side `build` default; fail-open). | `$HOME/.config/opencode/agent-default-guard.mjs` |
| `live-config-guard.mjs` | Config-layer plugin: blocks write-intent bash/tmux commands and write/edit tool calls against the live OpenCode/OMO config surface (`~/.config/opencode/{opencode,oh-my-openagent}.json[c]`) and the store's `configs/` tree from sessions outside `~/ez-omo-config` (incl. its worktrees). Substring-anchored detection catches empty alt-root expansion (`cat > $A/home/.config/opencode/opencode.json`); reads pass; repo sessions exempt; fail-open on internal errors. 2026-09-10/12 sandbox-leak incidents. | `$HOME/.config/opencode/live-config-guard.mjs` |
| `agent/document-writer.md` | Opencode-native agent file for the custom `document-writer` agent: frontmatter (`description`, `mode: all`, `model`) + body = system prompt. Custom agent prompts MUST live here, not in `oh-my-openagent.json#agents` (builtin-only — see docs/omo-config-reference.md §3.2b). | `$HOME/.config/opencode/agent/document-writer.md` |
| `aspect-dynamics.mjs` | Config-layer plugin: deterministic heuristic scoring and transcript-visible advisory nudge dispatch; file-based logging at `~/.config/opencode/aspect-dynamics.log` (no console output) | `$HOME/.config/opencode/aspect-dynamics.mjs` |
| `aspect-dynamics/*.mjs` | 7 support modules: config, context, heuristics, session-state, sets, nudge, logging | `$HOME/.config/opencode/aspect-dynamics/` |
| `aspect-dynamics/sets/*.json` | Seed aspect sets | `$HOME/.config/opencode/aspect-dynamics/sets/` |
| `output-shaper.mjs` | Config-layer plugin: terseness injection + reasoning-effort dialing for resume turns (writes OpenCode providerOptions keys — `reasoningEffort` for openai-compatible/openai providers, `thinkingConfig.thinkingLevel` for google; per-provider model allowlists supported); file-based logging at `~/.config/opencode/output-shaper.log` | `$HOME/.config/opencode/output-shaper.mjs` |
| `output-shaper/*.mjs` | 4 support modules: config, logging, model-gating (CLAMP_TABLE + per-provider model allowlists), resume-detector | `$HOME/.config/opencode/output-shaper/` |
| `skill-nudger.mjs` | Config-layer plugin: deterministic tool-signal detection (repeated failures, retryable errors, port binding, tool loops) queuing ephemeral skill-suggestion nudges delivered via `experimental.chat.messages.transform` (not persisted to transcript; fires for root and subagent sessions); file-based logging at `~/.config/opencode/skill-nudger.log` (no console output) | `$HOME/.config/opencode/skill-nudger.mjs` |
| `skill-nudger/*.mjs` | 6 support modules: config, logging, catalog, signals, state, nudge | `$HOME/.config/opencode/skill-nudger/` |
| `worktree.jsonc` | Worktree sync config and hook registration for automated worktree lifecycle management | `$HOME/.opencode/worktree.jsonc` |
| `extras/ocx.jsonc` | OCX registry configuration pointer used by the OCX CLI | `$HOME/.opencode/ocx.jsonc` |

## Registered Local Plugins

| Plugin | What it is configured to do | Install target |
|---|---|---|
| `clickable-links.ts` | Injects a system-prompt instruction so file references render as clickable markdown links in the TUI. | `$HOME/.opencode/plugin/clickable-links.ts` |
| `session-info.ts` | Intercepts `/session-info`, copies project/session metadata to clipboard, then sets `output.cancelled = true`. Requires the active `opencode--command-hook-cancellation` patch for true no-LLM behavior. | `$HOME/.opencode/plugin/session-info.ts` |
| `session-id.ts` | Intercepts `/session-id`, copies the invoking session ID to clipboard, then sets `output.cancelled = true`. Requires the active `opencode--command-hook-cancellation` patch. | `$HOME/.opencode/plugin/session-id.ts` |
| `vscode.ts` | Intercepts `/vscode`, launches VS Code in the current directory, then sets `output.cancelled = true`. Requires the active `opencode--command-hook-cancellation` patch. | `$HOME/.opencode/plugin/vscode.ts` |
| `git-safety.ts` | Blocks destructive shell and git commands (`git clean -fd`, `git reset --hard`, `git checkout --`, `git restore`, `git push --force`, `rm -rf` on unrecognized paths, bulk-delete patterns) and reports working-tree state before risky operations. Registered in `opencode.json#plugin` so its `tool.execute.before` hook intercepts bash/terminal/tmux tools. | `$HOME/.opencode/plugin/git-safety.ts` |

## Plugin Array Path Resolution

`opencode.json` declares local plugins using **relative paths**, resolved by OpenCode against the config file's directory (`~/.config/opencode/`):

| Plugin spec | Resolves to |
|-------------|-------------|
| `./provider-connect-retry.mjs` | `~/.config/opencode/provider-connect-retry.mjs` |
| `./aspect-dynamics.mjs` | `~/.config/opencode/aspect-dynamics.mjs` |
| `./output-shaper.mjs` | `~/.config/opencode/output-shaper.mjs` |
| `./skill-nudger.mjs` | `~/.config/opencode/skill-nudger.mjs` |
| `../../.opencode/plugin/clickable-links.ts` | `~/.opencode/plugin/clickable-links.ts` |
| `../../.opencode/plugin/session-info.ts` | `~/.opencode/plugin/session-info.ts` |
| `../../.opencode/plugin/session-id.ts` | `~/.opencode/plugin/session-id.ts` |
| `../../.opencode/plugin/vscode.ts` | `~/.opencode/plugin/vscode.ts` |
| `../../.opencode/plugin/git-safety.ts` | `~/.opencode/plugin/git-safety.ts` |
| `../../oh-my-openagent-v4.19.2` | `~/oh-my-openagent-v4.19.2` (patched OMO fork) |

OMO is loaded as `"../../oh-my-openagent-v4.19.2"` — config-relative, resolving to `$HOME/oh-my-openagent-v4.19.2` on any machine that clones the published fork there (`git clone -b v4.19.2-patches.1 https://github.com/EZotoff/oh-my-openagent.git ~/oh-my-openagent-v4.19.2`). It replaced the mutable `"oh-my-openagent@latest"` npm reference after the 2026-07-13 silent-bump incident; the fork carries the tracked OMO patches and is the canonical runtime source. The dist-level patches live in the locally built `dist/` and must be reapplied per the [patch registry](../../../MANIFEST.md#patch-registry) after cloning/rebuilding. The `browser-lifecycle-plugin` (agent-browser session cleanup) is optional and not included in the default config — add it manually if needed.


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
