# Oh My OpenAgent (OMO) v4.x — Exhaustive Configuration Reference

> **Source-of-truth verification**: every entry below is cross-referenced against the actual `v4.12.1` source at `/home/ezotoff/oh-my-openagent-v4.12.1/packages/omo-opencode/src/config/schema/*.ts` (permalink SHAs pinned to v4.12.1 tag `d0dc6f6`) and the `dev` branch documentation on GitHub.
> **Repo**: `code-yeongyu/oh-my-openagent` — **default branch**: `dev` (not `main`)
> **Versions present**: v4.12.1 (local), v4.2.3 (last tagged in CHANGELOG), `Unreleased` (4.3.0) — docs on `dev` are ahead of tagged releases.

---

## 0. Top-level inventory (counts)

| Artifact | Count | Source |
| --- | --- | --- |
| Built-in **agents** | 11 | [docs/reference/features.md](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/features.md) |
| Built-in **categories** | 8 | [categories.ts#L30-L39](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/categories.ts#L30-L39) |
| Built-in **hooks** (base) | 54 | [hooks.ts#L3-L62](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/hooks.ts#L3-L62) |
| Built-in **hooks** (with team_mode) | 61 | [features.md#L135](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/features.md#L135) |
| Built-in **commands** | 8 | [commands.ts#L3-L12](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/commands.ts#L3-L12) |
| Built-in **skills** | 13 | [agent-names.ts#L17-L31](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/agent-names.ts#L17-L31) |
| Built-in **MCPs** | 5 (`websearch`, `context7`, `grep_app`, `lsp`, `ast_grep`) | [CHANGELOG.md#L103](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/CHANGELOG.md#L103) |
| Tool directories | 16 | [features.md#L613](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/features.md#L613) |
| Tools registered (range) | 20–39 | [features.md#L613](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/features.md#L613) |
| Config schema files | 30 | `/packages/omo-opencode/src/config/schema/*.ts` |
| Documentation files | 20 | `docs/` tree |
| Example configs | 3 | `docs/examples/{default,coding-focused,planning-focused}.jsonc` |

---

## 1. Configuration file locations & format

**Source**: [docs/reference/configuration.md#L42-L69](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/configuration.md#L42-L69)

| Platform | Path |
| --- | --- |
| Project (any depth) | `.opencode/oh-my-openagent.json[c]` (or legacy `oh-my-opencode.json[c]`) — walked from CWD up to `$HOME`; closest wins |
| User — macOS/Linux | `~/.config/opencode/oh-my-openagent.json[c]`, `~/.config/opencode/oh-my-opencode.json[c]` |
| User — Windows | `%APPDATA%\opencode\oh-my-openagent.json[c]`, `%APPDATA%\opencode\oh-my-opencode.json[c]` |

- **Format**: JSONC — `// line`, `/* block */`, trailing commas allowed.
- **Schema URL** (autocomplete): `https://raw.githubusercontent.com/code-yeongyu/oh-my-openagent/dev/assets/oh-my-opencode.schema.json`
- **Rename-compat note**: Config detection checks `oh-my-opencode` *before* `oh-my-openagent`, so if both basenames exist in the same directory, `oh-my-opencode.*` currently wins.
- **`mcp_env_allowlist` is user-only** — walked configs cannot extend it.

---

## 2. Top-level config keys (the root `OhMyOpenCodeConfig` schema)

**Source**: [oh-my-opencode-config.ts#L33-L104](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/oh-my-opencode-config.ts#L33-L104)

| Key | Type | Default | Description | Doc / Source |
| --- | --- | --- | --- | --- |
| `$schema` | `string` | — | JSON-Schema URL for IDE autocomplete | [config.md#L63-L67](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/configuration.md#L63-L67) |
| `new_task_system_enabled` | `boolean` | `false` | Enable new task system (root-level flag) | [schema#L36](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/oh-my-opencode-config.ts#L36) |
| `default_run_agent` | `string` | — | Default agent name for `oh-my-opencode run` (env: `OPENCODE_DEFAULT_AGENT`) | [schema#L37-L38](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/oh-my-opencode-config.ts#L37-L38) |
| `agent_order` | `string[]` (max 64, each max 128 chars) | — | Preferred display order for known agents. Invalid names ignored with toast warning. | [schema#L39-L40](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/oh-my-opencode-config.ts#L39-L40), [config.md#L164-L170](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/configuration.md#L164-L170) |
| `agent_definitions` | `string[]` | — | Paths to external agent definition files (`.md` or `.json`) | [agent-definitions.ts](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/agent-definitions.ts) |
| `disabled_mcps` | `string[]` | — | Names of built-in MCPs to disable | [config.md#L624-L650](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/configuration.md#L624-L650) |
| `disabled_agents` | `string[]` | — | Names of agents to disable entirely | [config.md#L162](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/configuration.md#L162) |
| `disabled_skills` | `string[]` | — | Built-in skills to disable | [config.md#L491-L493](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/configuration.md#L491-L493) |
| `disabled_hooks` | `string[]` | — | Hook names to disable (see §6) | [config.md#L529-L546](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/configuration.md#L529-L546) |
| `disabled_commands` | `string[]` (BuiltinCommandName) | — | Slash commands to disable | [config.md#L547-L556](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/configuration.md#L547-L556) |
| `disabled_tools` | `string[]` | — | Disable specific tool names (e.g. `["todowrite","todoread"]`) | [schema#L48-L49](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/oh-my-opencode-config.ts#L48-L49) |
| `disabled_providers` | `string[]` | — | Provider prefixes excluded from every fallback chain (matches first segment of `provider/model`) | [schema#L50-L57](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/oh-my-opencode-config.ts#L50-L57), [CHANGELOG#L14](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/CHANGELOG.md#L14) |
| `mcp_env_allowlist` | `string[]` | — | Allowlist of env var names for MCP. **User-only**, walked configs cannot extend it. | [schema#L58](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/oh-my-opencode-config.ts#L58), [config.md#L56](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/configuration.md#L56) |
| `hashline_edit` | `boolean` | `false` | Enable hashline-anchored edit tool + `hashline-read-enhancer` hook | [config.md#L944-L952](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/configuration.md#L944-L952), [schema#L60](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/oh-my-opencode-config.ts#L60) |
| `model_fallback` | `boolean` | `false` | Enable model fallback on API errors (legacy flag; prefer `runtime_fallback`) | [schema#L62](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/oh-my-opencode-config.ts#L62) |
| `agents` | `object` (`AgentOverrides`) | — | Per-agent overrides (see §3) | [agent-overrides.ts#L60-L77](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/agent-overrides.ts#L60-L77) |
| `categories` | `record<string, CategoryConfig>` | — | Per-category overrides (see §4) | [categories.ts#L41](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/categories.ts#L41) |
| `claude_code` | `ClaudeCodeConfig` | — | Claude Code compatibility toggles (see §5) | [claude-code.ts](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/claude-code.ts) |
| `sisyphus_agent` | `SisyphusAgentConfig` | — | Sisyphus orchestrator toggles (see §7) | [sisyphus-agent.ts](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/sisyphus-agent.ts) |
| `comment_checker` | `CommentCheckerConfig` | — | Comment-checker customization | [comment-checker.ts](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/comment-checker.ts) |
| `experimental` | `ExperimentalConfig` | — | Experimental feature flags (see §8) | [experimental.ts](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/experimental.ts) |
| `auto_update` | `boolean` | — | Auto-update plugin | [schema#L69](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/oh-my-opencode-config.ts#L69) |
| `skills` | `SkillsConfig` (array OR object) | — | Skill config — sources, enable, disable, per-skill entries | [skills.ts](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/skills.ts) |
| `ralph_loop` | `RalphLoopConfig` | — | Ralph Loop (see §9) | [ralph-loop.ts](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/ralph-loop.ts) |
| `runtime_fallback` | `boolean \| RuntimeFallbackConfig` | `false` | Reactive model fallback on runtime failures (see §10) | [runtime-fallback.ts](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/runtime-fallback.ts) |
| `background_task` | `BackgroundTaskConfig` | — | Background-task concurrency / timeout controls (see §11) | [background-task.ts](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/background-task.ts) |
| `notification` | `NotificationConfig` | — | Session notification controls | [notification.ts](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/notification.ts) |
| `model_capabilities` | `ModelCapabilitiesConfig` | — | models.dev snapshot refresh controls (see §12) | [model-capabilities.ts](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/model-capabilities.ts) |
| `openclaw` | `OpenClawConfig` | — | Bidirectional integrations (Discord/Telegram/HTTP/shell + reply listener) | [openclaw.ts](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/openclaw.ts) |
| `i18n` | `I18nConfig` | — | Plugin locale override (e.g. `"en"`, `"zh"`) — falls back to `LANG` env | [i18n.ts](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/i18n.ts) |
| `monitor` | `MonitorConfig` | — | Live command monitor (see §13) | [monitor.ts](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/monitor.ts) |
| `codegraph` | `CodegraphConfig` | — | Codegraph indexing controls (see §14) | [codegraph.ts](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/codegraph.ts) |
| `team_mode` | `TeamModeConfig` | — | Team Mode (off by default) (see §15) | [team-mode.ts](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/team-mode.ts) (re-exported from `@oh-my-opencode/team-core/config`) |
| `keyword_detector` | `KeywordDetectorConfig` | — | IntentGate keyword expansion control (see §16) | [keyword-detector.ts](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/keyword-detector.ts) |
| `babysitting` | `BabysittingConfig` | — | Unstable-agent babysitter timeout (see §17) | [babysitting.ts](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/babysitting.ts) |
| `git_master` | `GitMasterConfig` | `{commit_footer:true, include_co_authored_by:true, git_env_prefix:"GIT_MASTER=1"}` | Git commit behavior (see §18) | [git-master.ts](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/git-master.ts) |
| `browser_automation_engine` | `BrowserAutomationConfig` | `{provider:"playwright"}` | Browser automation provider | [browser-automation.ts](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/browser-automation.ts) |
| `websearch` | `WebsearchConfig` | — | Websearch provider | [websearch.ts](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/websearch.ts) |
| `tmux` | `TmuxConfig` | `{enabled:false, layout:"main-vertical", main_pane_size:60, main_pane_min_width:120, agent_pane_min_width:40, isolation:"inline"}` | Tmux pane spawning for subagents (see §19) | [tmux.ts](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/tmux.ts) |
| `tui` | `TuiConfig` | `{sidebar:{enabled:true}}` | TUI sidebar toggle | [tui.ts](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/tui.ts) |
| `sisyphus` | `SisyphusConfig` | — | Sisyphus task-storage options (see §20) | [sisyphus.ts](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/sisyphus.ts) |
| `start_work` | `StartWorkConfig` | `{auto_commit:true}` | `/start-work` behavior | [start-work.ts](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/start-work.ts) |
| `default_mode` | `DefaultModeConfig` | `{ultrawork:false, ralph_loop:false}` | Auto-activation of modes (see §21) | [default-mode.ts](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/default-mode.ts) |
| `_migrations` | `string[]` | — | Migration history (prevents re-applying migrations) | [schema#L103](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/oh-my-opencode-config.ts#L103) |

---

## 3. `agents.<name>` — per-agent overrides

**Source**: [agent-overrides.ts#L5-L77](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/agent-overrides.ts#L5-L77)

### 3.1 Built-in agent names (`BuiltinAgentNameSchema`)

**Source**: [agent-names.ts#L3-L15](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/agent-names.ts#L3-L15)

`sisyphus`, `hephaestus`, `prometheus`, `oracle`, `librarian`, `explore`, `multimodal-looker`, `metis`, `momus`, `atlas`, `sisyphus-junior`

### 3.2 Overridable agent names (`OverridableAgentNameSchema`)

`build`, `plan`, `sisyphus`, `hephaestus`, `sisyphus-junior`, `OpenCode-Builder`, `prometheus`, `metis`, `momus`, `oracle`, `librarian`, `explore`, `multimodal-looker`, `atlas` + `.catchall()` for custom agents.

### 3.2b ⚠️ LOCAL WARNING — custom agent names: `prompt`/`prompt_append`/`mode` are dead fields (verified 2026-09-06, OMO v4.19.2)

> The `agents:` map is **builtin-agent overrides only** for prompt-shaping fields. `pluginConfig.agents` is consumed for `prompt`/`prompt_append` merging exclusively in the builtin factory path (`agent-config-handler.ts` → `createBuiltinAgents` → `builtin-agents/agent-overrides.ts` `mergeAgentConfig`). For any non-builtin name (e.g. `document-writer`, `frontend-ui-ux-engineer`), `prompt`, `prompt_append`, and `mode` are **silently dropped** — no merge path exists, no warning is emitted.
>
> Fields that DO work at runtime for custom names (consumed by name-keyed lookups elsewhere: model resolution, variant, runtime-fallback chains, ultrawork override): `model`, `variant`, `fallback_models` — which is exactly what makes the trap confusing: routing works, the prompt doesn't. (`description` is likewise redundant for custom names — the agent .md frontmatter owns it.)
>
> **Custom agent system prompts go in opencode-native agent files**: `configs/opencode/agent/<name>.md` — frontmatter (`description`, `mode`, `model`) + body = system prompt. OMO loads them via `loadAgentSources` (`agent-source-loader.ts`); `install.sh` symlinks them into `~/.config/opencode/agent/`. Working example: [`configs/opencode/agent/document-writer.md`](../configs/opencode/agent/document-writer.md). Never put a custom agent's prompt in `agents.<name>.prompt`. Since 2026-09-12 document-writer is the single routed door for documentation/prose work — the `writing` category is deprecated-unrouted (see §4.5).


### 3.3 Agent override fields

| Field | Type | Description |
| --- | --- | --- |
| `model` | `string` | **Deprecated** — use `category` instead. Model ID `provider/model`. |
| `fallback_models` | `string \| string[] \| object[] \| mixed[]` | Fallback chain. Supports mixed strings + per-fallback objects (see [fallback-models.ts#L24-L29](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/fallback-models.ts#L24-L29)). |
| `variant` | `string` | Model variant. Normalized to supported values: `max`/`high`/`medium`/`low`/`xhigh`. |
| `category` | `string` | Inherit model and other settings from this `categories.<name>`. |
| `skills` | `string[]` | Skill names injected into this agent's prompt. |
| `temperature` | `number (0..2)` | Sampling temperature. |
| `top_p` | `number (0..1)` | Nucleus sampling. |
| `prompt` | `string` | Replace system prompt. Supports `file://` URIs. For Prometheus, **appended**, not replaced. |
| `prompt_append` | `string` | Append to system prompt. Supports `file://` URIs (absolute, `./rel`, `~/home`). |
| `tools` | `Record<string, boolean>` | Per-tool enable/disable. |
| `disable` | `boolean` | Disable this agent. |
| `description` | `string` | UI/description string. |
| `mode` | `"subagent" \| "primary" \| "all"` | Agent mode. |
| `color` | `string` (`/^#[0-9A-Fa-f]{6}$/`) | UI color. |
| `displayName` | `string` | Localized display name in TUI agent selector (i18n). |
| `permission` | `AgentPermission` | Per-tool permissions (see §3.4). |
| `maxTokens` | `number` | Max response tokens. |
| `thinking` | `{ type: "enabled"\|"disabled", budgetTokens?: number }` | Anthropic extended thinking. |
| `reasoningEffort` | `"none"\|"minimal"\|"low"\|"medium"\|"high"\|"xhigh"\|"max"` | OpenAI reasoning effort. |
| `textVerbosity` | `"low"\|"medium"\|"high"` | Text verbosity. |
| `providerOptions` | `Record<string, unknown>` | Provider-specific options (passed to OpenCode SDK). |
| `ultrawork` | `{ model?, variant? }` | Per-message ultrawork override model/variant. |
| `compaction` | `{ model?, variant? }` | Compaction-specific override. |
| `allow_non_gpt_model` | `boolean` (hephaestus only) | Allow non-GPT models for Hephaestus (Hephaestus has `AgentOverrideConfigSchema.extend({...})`). |

### 3.4 `permission` sub-fields

**Source**: [internal/permission.ts#L11-L18](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/internal/permission.ts#L11-L18)

| Field | Type | Values |
| --- | --- | --- |
| `edit` | `PermissionValue` | `ask` / `allow` / `deny` |
| `bash` | `PermissionValue \| Record<command, PermissionValue>` | e.g. `{ "git": "allow", "rm": "deny" }` |
| `webfetch` | `PermissionValue` | `ask` / `allow` / `deny` |
| `task` | `PermissionValue` | `ask` / `allow` / `deny` |
| `doom_loop` | `PermissionValue` | `ask` / `allow` / `deny` |
| `external_directory` | `PermissionValue` | `ask` / `allow` / `deny` |
| `<catchall>` | `PermissionValue` | Any other tool name → `ask`/`allow`/`deny` |

### 3.5 Default agent models & provider chains

**Source**: [configuration.md#L368-L381](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/configuration.md#L368-L381) and [features.md](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/features.md)

| Agent | Default Model | Primary fallback chain |
| --- | --- | --- |
| Sisyphus | `claude-opus-4-7` (max) | `anthropic\|github-copilot\|opencode/claude-opus-4-7 (max)` → `opencode-go/kimi-k2.6` → `kimi-for-coding/k2p5` → `opencode\|moonshotai\|moonshotai-cn\|firmware\|ollama-cloud\|aihubmix/kimi-k2.5` → `openai\|github-copilot\|opencode/gpt-5.5 (medium)` → `zai-coding-plan\|opencode/glm-5` → `opencode/big-pickle` |
| Hephaestus | `gpt-5.5` (medium) | `gpt-5.5 (medium)` |
| Oracle | `gpt-5.5` (high) | `openai\|github-copilot\|opencode/gpt-5.5 (high)` → `google\|github-copilot\|opencode/gemini-3.1-pro (high)` → `anthropic\|github-copilot\|opencode/claude-opus-4-7 (max)` → `opencode-go/glm-5.1` |
| Librarian | `gpt-5.4-mini-fast` | `openai/gpt-5.4-mini-fast` → `opencode-go/qwen3.5-plus` → `vercel/minimax-m2.7-highspeed` → `opencode-go\|vercel/minimax-m3` → `opencode-go\|vercel/minimax-m2.7` → `anthropic\|vercel/claude-haiku-4-5` → `openai\|vercel/gpt-5.4-nano` |
| Explore | `gpt-5.4-mini-fast` | same as Librarian |
| Multimodal-Looker | `gpt-5.5` | `openai\|opencode/gpt-5.5 (medium)` → `opencode-go/kimi-k2.6` → `zai-coding-plan/glm-4.6v` → `openai\|github-copilot\|opencode/gpt-5-nano` |
| Prometheus | `claude-opus-4-7` (max) | `anthropic\|github-copilot\|opencode/claude-opus-4-7 (max)` → `openai\|github-copilot\|opencode/gpt-5.5 (high)` → `opencode-go/glm-5.1` → `google\|github-copilot\|opencode/gemini-3.1-pro` |
| Metis | `claude-sonnet-4-6` | `anthropic\|github-copilot\|opencode/claude-sonnet-4-6` → `anthropic\|github-copilot\|opencode/claude-opus-4-7 (max)` → `openai\|github-copilot\|opencode/gpt-5.5 (high)` → `opencode-go/glm-5.1` → `kimi-for-coding/k2p5` |
| Momus | `gpt-5.5` (xhigh) | `openai\|github-copilot\|opencode/gpt-5.5 (xhigh)` → `anthropic\|github-copilot\|opencode/claude-opus-4-7 (max)` → `google\|github-copilot\|opencode/gemini-3.1-pro (high)` → `opencode-go/glm-5.1` |
| Atlas | `claude-sonnet-4-6` | `anthropic\|github-copilot\|opencode/claude-sonnet-4-6` → `opencode-go/kimi-k2.6` → `openai\|github-copilot\|opencode/gpt-5.5 (medium)` → `opencode-go/minimax-m3` → `opencode-go/minimax-m2.7` |
| Sisyphus-Junior | (category-dependent) | `anthropic\|github-copilot\|opencode/claude-sonnet-4-6` → `opencode-go/kimi-k2.6` → `openai\|github-copilot\|opencode/gpt-5.5 (medium)` → `opencode-go/minimax-m3` → `opencode-go/minimax-m2.7` → `opencode/big-pickle` |

### 3.6 Agent tool restrictions (per docs)

**Source**: [features.md#L46-L53](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/features.md#L46-L53)

| Agent | Restricted/blocked |
| --- | --- |
| oracle | Read-only: blocked: `write`, `edit`, `task`, `call_omo_agent` |
| librarian | blocked: `write`, `edit`, `task`, `call_omo_agent` |
| explore | blocked: `write`, `edit`, `task`, `call_omo_agent` |
| multimodal-looker | allowlist: `read` only |
| atlas | blocked: `task`, `call_omo_agent` |
| momus | blocked: `write`, `edit`, `task` |

---

## 4. `categories.<name>` — per-category overrides

**Source**: [categories.ts#L4-L28](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/categories.ts#L4-L28)

### 4.1 Built-in category names (`BuiltinCategoryNameSchema`)

**Source**: [categories.ts#L30-L39](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/categories.ts#L30-L39)

`visual-engineering`, `ultrabrain`, `deep`, `artistry`, `quick`, `unspecified-low`, `unspecified-high`, `writing`

(Orchestration doc additionally mentions `quick-rust`, `quick-zig`, `git` as user-facing examples — [orchestration.md#L323](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/guide/orchestration.md#L323).)

### 4.2 Category fields

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `description` | `string` | — | Human-readable description shown in `task()` tool prompt. |
| `model` | `string` | — | Model override. |
| `fallback_models` | `string \| array` | — | Same shape as agent fallback. |
| `variant` | `string` | — | Model variant. |
| `temperature` | `number (0..2)` | — | Sampling temperature. |
| `top_p` | `number (0..1)` | — | Top-p. |
| `maxTokens` | `number` | — | Max response tokens. |
| `thinking` | `{type, budgetTokens?}` | — | Anthropic extended thinking. |
| `reasoningEffort` | `enum` | — | OpenAI reasoning effort. |
| `textVerbosity` | `enum` | — | Text verbosity. |
| `tools` | `Record<string, boolean>` | — | Tool enable/disable. |
| `prompt_append` | `string` | — | Append to category prompt (supports `file://`). |
| `max_prompt_tokens` | `number (positive int)` | — | Max prompt tokens for delegated tasks. |
| `is_unstable_agent` | `boolean` | `false` | Force background mode + monitoring. Auto-enabled for Gemini models. |
| `disable` | `boolean` | `false` | Exclude this category from task delegation. |

### 4.3 Default category models

**Source**: [features.md#L153-L164](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/features.md#L153-L164), [configuration.md#L300-L310](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/configuration.md#L300-L310)

| Category | Default Model |
| --- | --- |
| `visual-engineering` | `google/gemini-3.1-pro` (high) |
| `ultrabrain` | `openai/gpt-5.5` (xhigh) |
| `deep` | `openai/gpt-5.5` (medium) |
| `artistry` | `google/gemini-3.1-pro` (high) |
| `quick` | `openai/gpt-5.4-mini` |
| `unspecified-low` | `anthropic/claude-sonnet-4-6` |
| `unspecified-high` | `anthropic/claude-opus-4-7` (max) |
| `writing` | `kimi-for-coding/k2p5` |

### 4.4 Model resolution order

**Source**: [configuration.md#L336-L345](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/configuration.md#L336-L345)

1. UI-selected model (primary agents)
2. User override (config) — used exactly as-is
3. Category default
4. User `fallback_models`
5. Provider fallback chain (built-in)
6. System default (OpenCode)

### 4.5 ⚠️ LOCAL WARNING — `categories.writing` is deprecated-unrouted (2026-09-12)

> Documentation/prose/technical-writing delegation routes to the `document-writer` SUBAGENT (`task(subagent_type="document-writer")`; agent file [`configs/opencode/agent/document-writer.md`](../configs/opencode/agent/document-writer.md)), not to the `writing` category. The category is a **dormant rollback snapshot**: defined (builtin in OMO `kimi-categories.ts` + this repo's model pin `openai/gpt-5.6-terra`) but unrouted — its `description` override carries this deprecation notice into every orchestrator prompt's category list.
>
> **NEVER delete the `categories.writing` entry.** It exists to override the builtin's model (`kimi-for-coding/kimi-k3`). Deleting it resurrects the builtin and silently routes any surviving writing-category delegation to kimi-k3 (same trap class as wisdom `20260831-231121-vvdb`). To roll back the deprecation instead, see patch `omo--writing-routing-to-document-writer` in [patches.md](patches.md).
>
> The sisyphus GPT-family routing row was repointed by fork patch `omo--writing-routing-to-document-writer`; the live GLM-family prompt has no hardcoded row and is governed by this description override (dynamic category row via `builtin-agents.ts` `AvailableCategory.description`).

---

## 5. `claude_code` — Claude Code compatibility toggles

**Source**: [claude-code.ts#L3-L17](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/claude-code.ts#L3-L17), [features.md#L1138-L1174](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/features.md#L1138-L1174)

| Field | Type | Default | Effect when `false` |
| --- | --- | --- | --- |
| `mcp` | `boolean` | `true` | Don't load `.mcp.json` files (built-in MCPs unaffected) |
| `commands` | `boolean` | `true` | Don't load Claude Code commands |
| `skills` | `boolean` | `true` | Don't load Claude Code skills |
| `agents` | `boolean` | `true` | Don't load Claude Code agents (built-in unaffected) |
| `hooks` | `boolean` | `true` | Don't run `settings.json` hooks |
| `plugins` | `boolean` | `true` | Don't load Claude Code marketplace plugins |
| `plugins_override` | `Record<string, boolean>` | — | Per-plugin enable/disable, e.g. `{"claude-mem@thedotmack": false}` |
| `anthropic_provider` | `string` (no `/`) | `"anthropic"` | Override provider used for `opus/sonnet/haiku` model aliases (for proxied Anthropic access, e.g. `"kiro"`, `"my-gateway"`) |

---
  
## 6. `disabled_hooks` — every built-in hook name (54 base, 61 with team_mode)

**Source**: [hooks.ts#L3-L62](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/hooks.ts#L3-L62)

Every entry below appears in `HookNameSchema` and may be added to `disabled_hooks`. Categorized by event per [features.md#L825-L917](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/features.md#L825-L917):

| # | Hook Name | Event(s) | Purpose |
| --- | --- | --- | --- |
| 1 | `todo-continuation-enforcer` | Event | Yanks idle agents back to work (enforces todo completion) |
| 2 | `session-notification` | Event | OS notifications when agents go idle (macOS/Linux/Windows) |
| 3 | `comment-checker` | PostToolUse | Blocks AI-slop comment patterns (bypass: `// @allow` or `// comment-checker-disable-file`) |
| 4 | `tool-output-truncator` | PostToolUse | Truncates Grep/Glob/LSP/ast-grep outputs dynamically |
| 5 | `question-label-truncator` | PreToolUse | Truncates long Question tool labels |
| 6 | `directory-agents-injector` | PreToolUse+PostToolUse | Auto-injects `AGENTS.md` (auto-disabled on OpenCode 1.1.37+) |
| 7 | `directory-readme-injector` | PreToolUse+PostToolUse | Auto-injects `README.md` |
| 8 | `empty-task-response-detector` | PostToolUse | Detects empty delegated-task responses |
| 9 | `think-mode` | Params | Auto-detects "think deeply" / "ultrathink" → adjusts settings |
| 10 | `model-fallback` | Event+Message | Manages model fallback chain |
| 11 | `anthropic-context-window-limit-recovery` | Event | Handles Claude context window overflow gracefully |
| 12 | `preemptive-compaction` | Event | Proactive compaction before token limit hit |
| 13 | `rules-injector` | PreToolUse+PostToolUse | Injects `.claude/rules/` and `.omo/rules/**` content |
| 14 | `background-notification` | Event | Notifies on background agent completion |
| 15 | `auto-update-checker` | Event | Checks for new versions on session creation |
| 16 | `codegraph-bootstrap` | Event | Codegraph provisioning |
| 17 | `ast-grep-sg-provision` | Event | Provision `ast-grep` tool |
| 18 | `startup-toast` | Event | Version + Sisyphus status toast (sub-feature of `auto-update-checker`) |
| 19 | `keyword-detector` | Message+Transform | IntentGate — activates `ultrawork`/`ulw`/`search`/`analyze`/`team`/`hyperplan`/`hyperplan-ultrawork` |
| 20 | `agent-usage-reminder` | PostToolUse+Event | Reminds about specialized agents |
| 21 | `non-interactive-env` | PreToolUse | Non-interactive environment handling |
| 22 | `interactive-bash-session` | PostToolUse+Event | Manages tmux sessions for interactive CLI |
| 23 | `tool-pair-validator` | (Transform?) | Validates tool-call pairs |
| 24 | `monitor-status-injector` | (PostToolUse?) | Injects monitor status updates |
| 25 | `ralph-loop` | Event+Message | Manages self-referential loop continuation |
| 26 | `category-skill-reminder` | Event+PostToolUse | Reminds about category skills for delegation |
| 27 | `compaction-context-injector` | Event | Preserves critical context during compaction |
| 28 | `compaction-todo-preserver` | Event | Preserves todo state during compaction |
| 29 | `claude-code-hooks` | (All) | Executes hooks from `settings.json` |
| 30 | `auto-slash-command` | Message | Auto-executes slash commands from prompts |
| 31 | `edit-error-recovery` | PostToolUse+Event | Recovers from edit-tool failures |
| 32 | `json-error-recovery` | PostToolUse | Recovers from JSON parse errors in tool outputs |
| 33 | `delegate-task-retry` | PostToolUse+Event | Retries failed task delegations |
| 34 | `prometheus-md-only` | PreToolUse | Prometheus writes limited to `.omo/*.md` |
| 35 | `sisyphus-junior-notepad` | PreToolUse | Notepad state for Sisyphus-Junior |
| 36 | `team-tool-gating` | (PreToolUse) | Gating for `team_*` tools |
| 37 | `no-sisyphus-gpt` | Message | Blocks incompatible GPT for Sisyphus (**do not disable**) |
| 38 | `no-hephaestus-non-gpt` | Message | Blocks non-GPT for Hephaestus |
| 39 | `hephaestus-agents-md-injector` | (Event) | Injects `AGENTS.md` for Hephaestus |
| 40 | `start-work` | Message | `/start-work` command execution |
| 41 | `atlas` | (Multiple) | Main Atlas orchestration |
| 42 | `unstable-agent-babysitter` | Event | Handles unstable agent recovery |
| 43 | `task-resume-info` | PostToolUse | Provides task resume info for continuity |
| 44 | `stop-continuation-guard` | Event+Message | Guards stop-continuation |
| 45 | `tasks-todowrite-disabler` | PreToolUse | Disables TodoWrite when task system is active |
| 46 | `runtime-fallback` | Event+Message | Reactive model switching on API errors |
| 47 | `write-existing-file-guard` | PreToolUse | Blocks writes over unread existing files |
| 48 | `notepad-write-guard` | (PreToolUse) | Prevents accidental overwrites in `.omo/notepads` |
| 49 | `bash-file-read-guard` | (PreToolUse) | Guards reading bash as a file |
| 50 | `hashline-read-enhancer` | PostToolUse | Adds `LINE#ID` markers to Read output |
| 51 | `read-image-resizer` | (PostToolUse) | Resizes images for `read` tool |
| 52 | `todo-description-override` | (tool.definition) | Overrides TodoWrite description |
| 53 | `webfetch-redirect-guard` | (PreToolUse) | Guards webfetch redirects |
| 54 | `fsync-skip-warning` | (Event) | Warns when fsync is skipped |
| 55 | `plan-format-validator` | (PreToolUse) | Warns on malformed `.omo/plans/*.md` task labels |
| 56 | `legacy-plugin-toast` | (Event) | Warns on legacy `oh-my-opencode` plugin entry |
| 57 | `thinking-block-validator` | Transform | Prevents API errors from invalid thinking blocks |

> **With `team_mode.enabled`**: +1 Tool Guard + 2 Transform hooks + 4 direct team session event handlers in `packages/omo-opencode/src/plugin/event.ts` = **61 total**. (Source: [features.md#L135](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/features.md#L135))

### 6.1 Hook count breakdown by tier

**Source**: [features.md#L804-L812](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/features.md#L804-L812)

- Session: 24
- Tool Guard: 16
- Transform: 5
- Continuation: 7
- Skill: 2
- **Total base**: 54

### 6.2 Hook event types

**Source**: [features.md#L814-L824](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/features.md#L814-L824)

`PreToolUse`, `PostToolUse`, `Message`, `Event`, `Transform`, `Params`

---

## 7. `sisyphus_agent` — Sisyphus orchestrator toggles

**Source**: [sisyphus-agent.ts#L3-L9](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/sisyphus-agent.ts#L3-L9), [configuration.md#L428-L450](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/configuration.md#L428-L450)

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `disabled` | `boolean` | `false` | Disable all Sisyphus orchestration; restore original `build`/`plan` |
| `default_builder_enabled` | `boolean` | `false` | Enable `OpenCode-Builder` agent (off by default) |
| `planner_enabled` | `boolean` | `true` | Enable Prometheus (Planner) |
| `replace_plan` | `boolean` | `true` | Demote default `plan` agent to subagent mode |
| `tdd` | `boolean` | `true` | TDD-style enforcement (only in schema; not in config.md docs) |

---

## 8. `experimental` — experimental flags

**Source**: [experimental.ts#L4-L26](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/experimental.ts#L4-L26), [configuration.md#L954-L998](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/configuration.md#L954-L998)

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `aggressive_truncation` | `boolean` | `false` | Aggressively truncate when token limit exceeded |
| `preemptive_compaction` | `boolean` | — | Proactive compaction flag (already also a hook) |
| `truncate_all_tool_outputs` | `boolean` | `false` | Truncate all tool outputs (not just whitelisted) |
| `dynamic_context_pruning` | `object` | — | See §8.1 |
| `task_system` | `boolean` | `false` | Enable Sisyphus task system (intercept TodoWrite/TodoRead) |
| `plugin_load_timeout_ms` | `number (≥1000)` | `10000` | Timeout for `loadAllPluginComponents` during config handler init |
| `safe_hook_creation` | `boolean` | `true` (at call site) | Wrap hook creation in try/catch |
| `disable_omo_env` | `boolean` | `false` | Disable auto-injected `<omo-env>` block (date/time/locale) |
| `hashline_edit` | `boolean` | — | Hashline edit tool (also root-level) |
| `model_fallback_title` | `boolean` | `false` | Append fallback model info to session title |
| `max_tools` | `number (≥1)` | — | Max tools to register (e.g. OpenAI 128-tool cap). Accounts for ~20 OpenCode built-in. |
| `disable_live_parent_wake_routing` | `boolean` | `true` in this repo | Roll back parent-targeted internal prompts to the in-process dispatch path. Enabled here because OpenCode TUI can persist but not live-render externally routed parent-wake turns. |

### 8.1 `dynamic_context_pruning`

**Source**: [dynamic-context-pruning.ts#L3-L49](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/dynamic-context-pruning.ts#L3-L49)

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `enabled` | `boolean` | `false` | Master switch |
| `notification` | `"off"\|"minimal"\|"detailed"` | `"detailed"` | Pruning notification level |
| `turn_protection.enabled` | `boolean` | `true` | Prevent pruning recent tool outputs |
| `turn_protection.turns` | `number (1..10)` | `3` | Recent turns protected |
| `protected_tools` | `string[]` | `["task","todowrite","todoread","lsp_rename","session_read","session_write","session_search"]` | Never-prune list |
| `strategies.deduplication.enabled` | `boolean` | `true` | Remove duplicate tool calls |
| `strategies.supersede_writes.enabled` | `boolean` | `true` | Prune write inputs when file later read |
| `strategies.supersede_writes.aggressive` | `boolean` | `false` | Prune any write if ANY subsequent read exists |
| `strategies.purge_errors.enabled` | `boolean` | `true` | Prune errored tool inputs |
| `strategies.purge_errors.turns` | `number (1..20)` | `5` | Turns before pruning errored tool inputs |

---

## 9. `ralph_loop` — Ralph Loop

**Source**: [ralph-loop.ts#L3-L9](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/ralph-loop.ts#L3-L9), [features.md#L532-L554](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/features.md#L532-L554)

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `enabled` | `boolean` | `false` | Enable Ralph Loop |
| `default_max_iterations` | `number (1..1000)` | `100` | Default iteration cap |
| `state_dir` | `string` | `.opencode/` | Custom state directory (relative to project root) |
| `default_strategy` | `"reset"\|"continue"` | `"continue"` | Default strategy on restart |

**Invocation**: `/ralph-loop "Build a REST API" --max-iterations=50`; `/ulw-loop` runs Ralph with ultrawork mode.

---

## 10. `runtime_fallback` — reactive model fallback

**Source**: [runtime-fallback.ts#L3-L16](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/runtime-fallback.ts#L3-L16), [configuration.md#L655-L908](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/configuration.md#L655-L908)

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `enabled` | `boolean` | `false` | Enable runtime fallback |
| `retry_on_errors` | `number[]` | `[429,500,502,503,504]` | HTTP codes that trigger fallback (also classified provider key errors) |
| `max_fallback_attempts` | `number (1..20)` | `3` | Max fallback attempts per session |
| `cooldown_seconds` | `number (≥0)` | `60` | Seconds before retrying a failed model |
| `timeout_seconds` | `number (≥0)` | `30` | Session-level timeout to force next fallback. **`0` disables** timeout-based escalation and `message.updated` retry-signal detection (structured `session.status` retry events still trigger) |
| `notify_on_fallback` | `boolean` | `true` | Toast notification on model switch |

**Accepts**: bare `boolean` OR full object (e.g. `"runtime_fallback": true`).

---

## 11. `background_task` — concurrency & timeout controls

**Source**: [background-task.ts#L3-L29](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/background-task.ts#L3-L29), [configuration.md#L404-L426](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/configuration.md#L404-L426)

| Field | Type | Default | Min | Description |
| --- | --- | --- | --- | --- |
| `defaultConcurrency` | `number (≥1)` | — | — | Max concurrent tasks (all providers) |
| `providerConcurrency` | `Record<provider, number (≥0)>` | — | — | Per-provider limits (key = provider name) |
| `modelConcurrency` | `Record<provider/model, number (≥0)>` | — | — | Per-model limits (overrides provider) |
| `maxDepth` | `number (≥1)` | — | — | Max delegation depth |
| `staleTimeoutMs` | `number (ms)` | `180000` | `60000` | Interrupt tasks with no activity for this duration |
| `messageStalenessTimeoutMs` | `number (ms)` | `1800000` | `60000` | Timeout for tasks that never received progress update |
| `taskTtlMs` | `number (ms)` | `1800000` | `300000` | Absolute TTL for non-terminal tasks |
| `sessionGoneTimeoutMs` | `number (ms)` | `60000` | `10000` | Timeout when session completely disappeared from status registry |
| `taskCleanupDelayMs` | `number (ms)` | `600000` | `60000` | Delay before removing completed/cancelled/errored tasks from memory |
| `syncPollTimeoutMs` | `number (ms)` | — | `60000` | — |
| `maxToolCalls` | `number (int, ≥10)` | `200` | `10` | Max tool calls per subagent before circuit breaker |
| `circuitBreaker.enabled` | `boolean` | — | — | Master switch |
| `circuitBreaker.maxToolCalls` | `number (int, ≥10)` | — | — | Circuit breaker cap |
| `circuitBreaker.consecutiveThreshold` | `number (int, ≥5)` | — | — | Consecutive failures before trigger |

**Priority**: `modelConcurrency` > `providerConcurrency` > `defaultConcurrency`

---

## 12. `model_capabilities` — models.dev snapshot cache

**Source**: [model-capabilities.ts#L3-L8](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/model-capabilities.ts#L3-L8), [configuration.md#L916-L943](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/configuration.md#L916-L943)

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `enabled` | `boolean` | enabled unless explicitly `false` | Master switch |
| `auto_refresh_on_start` | `boolean` | refresh on startup unless explicitly `false` | Refresh on startup |
| `refresh_timeout_ms` | `number (int, >0)` | `5000` | Refresh attempt timeout |
| `source_url` | `string (URL)` | `https://models.dev/api.json` | Override source URL |

Manual refresh: `bunx oh-my-openagent refresh-model-capabilities`.

---

## 13. `monitor` — long-running process monitor (live mode)

**Source**: [monitor.ts#L3-L15](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/monitor.ts#L3-L15), [docs/reference/monitor.md](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/monitor.md)

| Field | Type | Default | Bounds | Description |
| --- | --- | --- | --- | --- |
| `enabled` | `boolean` | `false` | — | Registers the 4 Monitor tools (`monitor_start`, `monitor_stop`, `monitor_list`, `monitor_output`) |
| `live_mode_enabled` | `boolean` | `false` | — | Allows `monitor_start` to request `mode: "live_safe"` |
| `allowed_commands` | `string[]` | `[]` (deny all fallback) | — | Program-name allowlist (used only when Bash-equivalent permission unavailable) |
| `max_monitors_per_session` | `number (int)` | `3` | `1..16` | Max active monitors per parent session |
| `max_runtime_ms` | `number (int)` | `1800000` (30 min) | `≥1000` | Runtime cap per monitor |
| `batch_max_lines` | `number (int)` | `50` | `≥1` | Max lines per injected batch |
| `batch_max_bytes` | `number (int)` | `16384` | `≥1024` | Max bytes per injected batch |
| `flush_interval_ms` | `number (int)` | `1000` | `≥250` | Batch flush interval |
| `ring_max_lines` | `number (int)` | `1000` | `≥1` | Retained output lines per monitor |
| `line_max_bytes` | `number (int)` | `8192` | `≥256` | Max bytes per single output line |
| `pattern_max_length` | `number (int)` | `512` | `≥1` | Max length of `match_pattern` |

**Tools exposed when enabled**: `monitor_start`, `monitor_stop`, `monitor_list`, `monitor_output`.

**Security model** (per [monitor.md#L125-L138](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/monitor.md#L125-L138)): `enabled: true` only registers tools. Command execution gated by (1) OpenCode's Bash permission API when available, (2) `allowed_commands` otherwise. Fails closed.

**MVP limitations**: no stdin, no PTY, no interactive, no persistence, primary-session only, no cross-session ownership, no auto-restart, no file-watch, no CI parser, no dev-server health dashboard.

---

## 14. `codegraph` — codegraph indexing

**Source**: [codegraph.ts#L3-L9](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/codegraph.ts#L3-L9)

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `auto_provision` | `boolean` | `true` | Auto-provision codegraph index |
| `enabled` | `boolean` | `true` | Enable codegraph integration |
| `install_dir` | `string` | — | Custom install directory |
| `telemetry` | `boolean` | — | Telemetry opt-in/out |
| `watch_debounce_ms` | `number (non-negative)` | — | File-watch debounce delay |

---

## 15. `team_mode` — parallel multi-agent teams (THE big v4.0 feature)

**Source**:
- Source: [team-mode.ts](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/team-mode.ts) (re-exports from `team-core`)
- Actual schema: [packages/team-core/src/config.ts#L3-L15](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/team-core/src/config.ts#L3-L15)
- Doc: [docs/guide/team-mode.md](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/guide/team-mode.md)

**OFF by default.** Enable via:

```jsonc
{
  "team_mode": {
    "enabled": true,
    "max_parallel_members": 4,
    "max_members": 8,
    "tmux_visualization": false
  }
}
```

### 15.1 Schema (11 fields)

| Field | Type | Default | Bounds | Description |
| --- | --- | --- | --- | --- |
| `enabled` | `boolean` | `false` | — | Master switch |
| `tmux_visualization` | `boolean` | `false` | — | Per-member tmux pane attached to each member's session via `opencode attach` |
| `max_parallel_members` | `int` | `4` | `1..8` | Members in flight |
| `max_members` | `int` | `8` | `1..8` | Team size cap |
| `max_messages_per_run` | `int` | `10000` | `≥1` | Per-run message cap |
| `max_wall_clock_minutes` | `int` | `120` | `≥1` | Wall-clock cap |
| `max_member_turns` | `int` | `500` | `≥1` | Per-member turn cap |
| `base_dir` | `string` | `~/.omo` | — | Base dir for team state |
| `message_payload_max_bytes` | `int` | `32768` | `≥1024` | Max message body size |
| `recipient_unread_max_bytes` | `int` | `262144` | `≥1024` | Max recipient unread buffer |
| `mailbox_poll_interval_ms` | `int` | `3000` | `≥500` | Mailbox poll interval |

### 15.2 The 12 `team_*` tools

**Source**: [team-mode.md#L91-L103](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/guide/team-mode.md#L91-L103)

`team_create`, `team_delete`, `team_shutdown_request`, `team_approve_shutdown`, `team_reject_shutdown`, `team_send_message`, `team_task_create`, `team_task_list`, `team_task_update`, `team_task_get`, `team_status`, `team_list`

### 15.3 Team spec file (separate from plugin config)

**Source**: [team-mode.md#L52-L68](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/guide/team-mode.md#L52-L68)

Stored at `~/.omo/teams/{name}/config.json` (user) or `<project>/.omo/teams/{name}/config.json` (project). Project wins on collision.

```json
{
  "name": "ccapi-explorers",
  "description": "Explore the ccapi project structure.",
  "lead": { "kind": "subagent_type", "subagent_type": "sisyphus" },
  "members": [
    { "kind": "category", "name": "scout-1", "category": "deep", "prompt": "..." },
    { "kind": "category", "name": "scout-2", "category": "quick", "prompt": "..." }
  ]
}
```

### 15.4 Member kinds

- `kind: "subagent_type"` — direct agent (`sisyphus`, `atlas`, `sisyphus-junior`, `hephaestus`). `prompt` optional.
- `kind: "category"` — routed through `sisyphus-junior` with category model. `prompt` **REQUIRED**.

### 15.5 Team member eligibility

- **Eligible**: `sisyphus`, `atlas`, `sisyphus-junior`
- **Conditional**: `hephaestus` (needs teammate permission `teammate: "allow"`; otherwise use `subagent_type: "sisyphus"`)
- **Hard-reject**: `oracle`, `librarian`, `explore`, `multimodal-looker`, `metis`, `momus`, `prometheus` — fail `TeamSpec` parsing (cannot write mailbox state)

### 15.6 Skills riding on top of Team Mode

- **`hyperplan`** — 5 hostile critics tear plans apart
- **`security-research`** — 3 vulnerability hunters + 2 PoC engineers audit in parallel

### 15.7 Storage layout

**Source**: [team-mode.md#L135-L147](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/guide/team-mode.md#L135-L147)

```
~/.omo/
├── teams/{name}/config.json
├── .highwatermark
└── runtime/{teamRunId}/
    ├── state.json
    ├── inboxes/{member}/{uuid}.json
    ├── inboxes/{member}/.delivering-{uuid}.json  (transient, 10min TTL)
    ├── inboxes/{member}/processed/
    └── tasks/{id}.json
```

---

## 16. `keyword_detector` — IntentGate keyword control

**Source**: [keyword-detector.ts#L3-L9](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/keyword-detector.ts#L3-L9), [CHANGELOG#L19](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/CHANGELOG.md#L19)

| Field | Type | Description |
| --- | --- | --- |
| `enabled_expansions` | `KeywordType[]` | Allowlist of which keyword expansions fire |
| `disabled_keywords` | `KeywordType[]` | Blocklist of keywords to skip |

**Allowed `KeywordType` values**:
- `"ultrawork"` — activates ultrawork mode
- `"team"` — activates team mode
- `"hyperplan"` — activates hyperplan
- `"hyperplan-ultrawork"` — combined hyperplan + ultrawork

---

## 17. `babysitting` — unstable-agent watchdog

**Source**: [babysitting.ts#L3-L5](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/babysitting.ts#L3-L5)

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `timeout_ms` | `number` | `120000` (2 min) | Timeout for unstable-agent babysitter hook |

---

## 18. `git_master` — git commit behavior

**Source**: [git-master.ts#L5-L12](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/git-master.ts#L5-L12)

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `commit_footer` | `boolean \| string` | `true` | Add "Ultraworked with Sisyphus" footer (`true`/`false`/custom string) |
| `include_co_authored_by` | `boolean` | `true` | Add "Co-authored-by: Sisyphus" trailer |
| `git_env_prefix` | `string` | `"GIT_MASTER=1"` | Env var prefix on all git commands. Set `""` to disable. |

---

## 19. `tmux` — interactive tmux panes

**Source**: [tmux.ts#L9-L16](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/tmux.ts#L9-L16), [configuration.md#L570-L593](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/configuration.md#L570-L593)

| Field | Type | Default | Bounds | Description |
| --- | --- | --- | --- | --- |
| `enabled` | `boolean` | `false` | — | Enable tmux pane spawning |
| `layout` | `enum` | `"main-vertical"` | `main-vertical`/`main-horizontal`/`tiled`/`even-horizontal`/`even-vertical` | Pane layout |
| `main_pane_size` | `number` | `60` | `20..80` | Main pane % |
| `main_pane_min_width` | `number` | `120` | `≥40` | Min main pane columns |
| `agent_pane_min_width` | `number` | `40` | `≥20` | Min agent pane columns |
| `isolation` | `enum` | `"inline"` | (see `TMUX_ISOLATION_VALUES`) | Isolation mode |

Requires running inside tmux with `opencode --port <port>`. Works in cmux via `cmux omo`.

---

## 20. `sisyphus` — task storage

**Source**: [sisyphus.ts#L3-L13](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/sisyphus.ts#L3-L13), [configuration.md#L452-L481](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/docs/reference/configuration.md#L452-L481)

```json
{
  "sisyphus": {
    "tasks": {
      "storage_path": ".omo/tasks",
      "task_list_id": "...",
      "claude_code_compat": false
    }
  }
}
```

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `tasks.storage_path` | `string` | — | Absolute or relative storage path override. When set, bypasses global config dir. |
| `tasks.task_list_id` | `string` | — | Force task list ID (alt to env `ULTRAWORK_TASK_LIST_ID`) |
| `tasks.claude_code_compat` | `boolean` | `false` | Enable Claude Code path compatibility mode |

---

## 21. `default_mode` — auto-activation

**Source**: [default-mode.ts#L3-L16](https://github.com/code-yeongyu/oh-my-openagent/blob/v4.12.1/packages/omo-opencode/src/config/schema/default-mode.ts#L3-L16), [CHANGELOG#L12](https://github.com/code-yeongyu/oh-my-openagent/blob/dev/CHANGELOG.md#L12)

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `ultrawork` | `boolean` | `false` | Auto-inject ultrawork mode prompt on main session start (without typing `ultrawork`/`ulw`). The system prompt is injected once per session. |
| `ralph_loop` | `boolean` | `false` | Auto-start Ralph Loop on main session start. When `ultrawork` also enabled, loop starts in ultrawork mode. |

---
