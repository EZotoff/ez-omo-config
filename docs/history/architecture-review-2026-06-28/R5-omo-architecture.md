# R5: OMO architecture and upstream OpenCode relationship

## Scope and evidence base

This note summarizes the local OMO checkout at `/home/ezotoff/oh-my-openagent-v4.12.1` and the local patch registry in `/home/ezotoff/ez-omo-config/.sisyphus/patches`. It is descriptive only. It reports how OMO works and which patterns are relevant to local patch management; it does not make an architecture recommendation.

Primary source files inspected:

- `/home/ezotoff/oh-my-openagent-v4.12.1/package.json`
- `/home/ezotoff/oh-my-openagent-v4.12.1/README.md`
- `/home/ezotoff/oh-my-openagent-v4.12.1/ROADMAP.md`
- `/home/ezotoff/oh-my-openagent-v4.12.1/AGENTS.md`
- `/home/ezotoff/oh-my-openagent-v4.12.1/postinstall.mjs`
- `/home/ezotoff/oh-my-openagent-v4.12.1/bin/version-mismatch.js`
- `/home/ezotoff/oh-my-openagent-v4.12.1/script/patch-node-require-shim.ts`
- `/home/ezotoff/oh-my-openagent-v4.12.1/script/publish.ts`
- `/home/ezotoff/oh-my-openagent-v4.12.1/script/sync-lazycodex-marketplace.ts`
- `/home/ezotoff/oh-my-openagent-v4.12.1/packages/omo-opencode/src/testing/create-plugin-module.ts`
- `/home/ezotoff/oh-my-openagent-v4.12.1/packages/omo-opencode/src/plugin-interface.ts`
- `/home/ezotoff/oh-my-openagent-v4.12.1/packages/omo-opencode/src/create-hooks.ts`
- `/home/ezotoff/oh-my-openagent-v4.12.1/packages/omo-opencode/src/create-tools.ts`
- `/home/ezotoff/oh-my-openagent-v4.12.1/packages/omo-opencode/src/create-managers.ts`
- `/home/ezotoff/oh-my-openagent-v4.12.1/packages/omo-opencode/src/plugin-handlers/config-handler.ts`
- `/home/ezotoff/oh-my-openagent-v4.12.1/packages/omo-opencode/src/config/schema/hooks.ts`
- `/home/ezotoff/oh-my-openagent-v4.12.1/packages/skills-loader-core/src/features/opencode-skill-loader/loader.ts`
- `/home/ezotoff/oh-my-openagent-v4.12.1/packages/skills-loader-core/src/features/opencode-skill-loader/loaded-skill-from-path.ts`
- `/home/ezotoff/oh-my-openagent-v4.12.1/packages/skills-loader-core/src/features/opencode-runtime-skills/source-server.ts`
- `/home/ezotoff/ez-omo-config/.sisyphus/patches/*.md`

## 1. Repository organization

OMO v4.12.1 is a Bun/TypeScript monorepo. The root package is published as `oh-my-opencode` / `oh-my-openagent`, version `4.12.1`, and has workspaces for harness adapters, core logic, MCP servers, skills, and platform binary packages.

The root `package.json` declares these workspace packages:

- Core or shared packages: `rules-engine`, `delegate-core`, `mcp-stdio-core`, `mcp-client-core`, `lsp-core`, `utils`, `model-core`, `prompts-core`, `comment-checker-core`, `hashline-core`, `tmux-core`, `team-core`, `openclaw-core`, `boulder-state`, `telemetry-core`, `claude-code-compat-core`, `skills-loader-core`, `agents-md-core`, `shared-skills`.
- Harness adapters: `omo-opencode` and `omo-codex`.
- MCP/runtime packages present in the tree but not all listed in the root workspaces array shown by `package.json`: `lsp-tools-mcp`, `lsp-daemon`, `git-bash-mcp`.
- Platform packages: `oh-my-opencode-darwin-*`, `oh-my-opencode-linux-*`, and `oh-my-opencode-windows-*` packages. These are platform binary packages with matching optional dependency versions `4.12.1`.
- Web package: `packages/web` exists in the checkout and is documented in `AGENTS.md`, though it is not in the root workspaces list shown in `package.json`.

OMO's own `AGENTS.md` describes the current refactor as a multi-harness package-layering refactor. The intended layer split is:

1. Core: pure TypeScript logic with no harness dependencies.
2. MCP: stdio or external process boundary tool servers.
3. Skills: static `SKILL.md` knowledge bundles.
4. Adapters: harness-specific glue. `packages/omo-opencode` is the OpenCode adapter. `packages/omo-codex` is the Codex Light adapter.
5. Platform: compiled binary packages.
6. Web: marketing site.

The repo docs explicitly say adapters depend downward on Core/MCP/Skills, and nothing should depend on adapters. That is the main organizational pattern relevant to patch management: isolate harness-neutral behavior into packages that can be consumed by multiple adapters, and keep direct OpenCode coupling in the OpenCode adapter.

## 2. How OMO hooks into OpenCode

OMO's OpenCode integration is an OpenCode plugin, not a copy of OpenCode itself.

Important facts:

- `packages/omo-opencode/package.json` describes the package as `OpenCode harness adapter (Ultimate edition plugin)`.
- It depends on `@opencode-ai/plugin` and `@opencode-ai/sdk`, both pinned at `1.15.13` in the local checkout.
- `packages/omo-opencode/src/index.ts` exports a `PluginModule` from `@opencode-ai/plugin` and delegates to `createPluginModule()`.
- `createPluginModule()` returns `{ id: "oh-my-openagent", server: serverPlugin }`.
- OpenCode loads this through the `plugin` array in `opencode.json`. The package identity layer recognizes both `oh-my-openagent` and legacy `oh-my-opencode` names.

The plugin boot path is staged:

1. Install an agent-sort shim.
2. Initialize config context.
3. Warn/migrate legacy names and `.sisyphus` state.
4. Detect duplicate OMO plugin entries and external skill-plugin conflicts.
5. Inject server auth into the SDK client.
6. Load OMO JSONC config from user and project layers.
7. Optionally create a runtime skill source server.
8. Initialize i18n, OpenClaw, Team Mode, tmux checks.
9. Create managers.
10. Create tools.
11. Create hooks.
12. Create the OpenCode plugin interface.
13. Return OpenCode hook handlers plus experimental compaction handlers and a `dispose` handler.

The OpenCode plugin interface is concentrated in `packages/omo-opencode/src/plugin-interface.ts`. It exposes these OpenCode plugin surfaces:

- `tool`: OMO native tools.
- `chat.params`: model parameter mutation, agent variant application, and related chat parameter behavior.
- `chat.headers`: header injection.
- `command.execute.before`: slash-command interception and pre-command guards.
- `chat.message`: first-message setup and keyword/mode handling.
- `experimental.chat.messages.transform`: message-list transforms and context injection.
- `experimental.chat.system.transform`: system-message transforms.
- `config`: config mutation pipeline.
- `event`: session lifecycle and runtime events.
- `tool.definition`: per-tool definition transforms.
- `tool.execute.before`: pre-tool guards.
- `tool.execute.after`: post-tool hooks.

`createPluginModule()` also wires two experimental hooks directly:

- `experimental.session.compacting`
- `experimental.compaction.autocontinue`

OMO therefore hooks into OpenCode through first-class plugin lifecycle hooks, config transformation, tool registration, command interception, message transforms, and event handlers. It also uses the OpenCode SDK client exposed to plugins for session operations. Some high-risk behavior comes from plugin-initiated `session.prompt` / `session.promptAsync` calls; OMO treats those as dangerous shared-session writes and routes production use through a prompt-async gate.

## 3. Config injection model

OMO does substantial config injection rather than patching OpenCode config files directly at runtime.

`packages/omo-opencode/src/plugin-handlers/config-handler.ts` is the central `config` hook. Its pipeline is:

1. `applyProviderConfig` caches provider model limits and vision-capable model info.
2. `loadPluginComponents` loads compatible plugin components.
3. `applyHookConfig` injects Claude Code plugin hook configs into OMO's Claude-code-hook compatibility state.
4. `applyAgentConfig` injects built-in and configured agents.
5. `applyToolConfig` injects or gates tools.
6. `applyMcpConfig` injects built-in MCPs, Claude `.mcp.json` MCPs, user MCPs, and plugin-component MCPs.
7. `applyCommandConfig` injects commands.
8. `applyRuntimeSkillSourceConfig` adds runtime skill-source URLs when runtime security skills are served by the plugin.

The plugin config loader supports multiple layers:

- User-level config under OpenCode config dirs, using `oh-my-openagent.json[c]` and legacy `oh-my-opencode.json[c]` names.
- Project-level configs discovered by walking `.opencode/oh-my-openagent.json[c]` from the project directory up to `$HOME`.
- Zod validation with partial loading for invalid sections.
- Legacy key/name migrations.
- Deep merge for agents/categories/Claude Code config, set-union merge for `disabled_*`, and override semantics for most other fields.
- `mcp_env_allowlist` is user-only and is not extended by walked project configs.

This is a major pattern: OMO uses OpenCode's `config` hook as a controlled overlay system. Agent definitions, tools, MCPs, commands, and runtime skill sources can be added without modifying upstream OpenCode source.

## 4. Hook system structure

OMO has its own internal hook composition layer above OpenCode's plugin API.

`createHooks()` composes three families:

- Core hooks: session hooks, tool guard hooks, and transform hooks.
- Continuation hooks: stop-continuation guard, compaction context/todo preservation, todo continuation enforcer, unstable-agent babysitter, background notification, Atlas hook.
- Skill hooks: category-skill reminder and auto-slash-command.

`packages/omo-opencode/src/config/schema/hooks.ts` lists configurable hook names, including:

- Continuation and session behavior: `todo-continuation-enforcer`, `session-notification`, `background-notification`, `ralph-loop`, `start-work`, `atlas`, `stop-continuation-guard`, `compaction-context-injector`, `compaction-todo-preserver`, `preemptive-compaction`, `runtime-fallback`.
- Tool guards and transforms: `comment-checker`, `tool-output-truncator`, `question-label-truncator`, `directory-agents-injector`, `directory-readme-injector`, `rules-injector`, `tool-pair-validator`, `write-existing-file-guard`, `notepad-write-guard`, `bash-file-read-guard`, `hashline-read-enhancer`, `json-error-recovery`, `read-image-resizer`, `todo-description-override`, `webfetch-redirect-guard`, `fsync-skip-warning`, `plan-format-validator`.
- OpenCode/skill compatibility: `claude-code-hooks`, `auto-slash-command`, `category-skill-reminder`, `legacy-plugin-toast`.
- Agent policy hooks: `no-sisyphus-gpt`, `no-hephaestus-non-gpt`, `hephaestus-agents-md-injector`, `sisyphus-junior-notepad`, `task-resume-info`, `tasks-todowrite-disabler`.

Hook creation is gated by `disabled_hooks` and by `experimental.safe_hook_creation`. Hook instances with `dispose()` are disposed during plugin shutdown.

The relevant pattern is that OMO treats hook behavior as a first-party extension surface. A lot of behavior that might otherwise be a fork patch is modeled as a named hook registered into the composition layer, gated by config, and invoked from OpenCode's broad lifecycle hook surfaces.

## 5. Tool, MCP, and manager model

OMO registers tools through `createTools()` and a tool registry. The local docs describe 20 to 39 tools depending on config gates. Always-on tools include LSP, grep/glob, session history tools, background task tools, `call_omo_agent`, `task`, `skill`, and `skill_mcp`. Conditional tools include multimodal `look_at`, `interactive_bash`, task-system CRUD tools, `hashline_edit`, and Team Mode tools.

Managers are created once at plugin startup:

- `TmuxSessionManager`
- `BackgroundManager`
- `SkillMcpManager`
- `ConfigHandler`
- optional `TuiStateMirror`
- optional `MonitorManager`
- model fallback controller accessor

The manager layer is where OMO keeps long-lived runtime state and external process/session coordination out of individual hooks.

MCP has three tiers:

1. Built-in MCPs from `packages/omo-opencode/src/mcp/`.
2. Claude Code compatible `.mcp.json` configs.
3. Skill-embedded MCPs parsed from `SKILL.md` frontmatter or `mcp.json` and managed per session by `SkillMcpManager`.

This gives OMO another non-fork extension path: if a capability can be represented as an MCP server, the OpenCode adapter can inject it at config time and manage it per session without changing OpenCode source.

## 6. `packages/skills-loader-core`

`skills-loader-core` is harness-neutral. Its package description is: `Harness-neutral skill loading, builtin skill, runtime skill, and skill matching primitives for oh-my-opencode.` It exports:

- OpenCode skill loader modules.
- Built-in skills.
- OpenCode runtime skills.
- The `skill` tool primitives.
- Auto-slash-command hook primitives.
- Shared config/path helpers.

Important behavior:

- It discovers skills from OpenCode project skill dirs, OpenCode global skill dirs, shared bundled skills, Claude project/user skills, `.agents` project skills, and `.agents` global skills.
- It deduplicates by name and uses scope priority.
- It creates `shared/<name>` aliases for shared skills.
- It supports config-defined skills, file-system skills, built-in skills, and disabling/enabling skill sets.
- It parses frontmatter and `mcp.json` for skill-embedded MCP configuration.
- It resolves file references relative to the skill directory and wraps skill bodies in a standard `<skill-instruction>` / `<user-request>` template.
- It can serve runtime skills from an ephemeral local HTTP server. `createRuntimeSkillSourceServer()` binds `127.0.0.1` on port `0`, serves `/index.json` and `/<skill>/SKILL.md`, and `applyRuntimeSkillSourceConfig()` injects the source URL into OpenCode `config.skills.urls`.

This is a relevant pattern because declarative skills and skill-embedded MCPs are separated from the OpenCode adapter. The same skill content is reused across OpenCode and Codex editions.

## 7. Claude Code compatibility and plugin loading

OMO includes a Claude Code compatibility layer. The OpenCode adapter has `features/claude-code-plugin-loader`, and the extracted package `claude-code-compat-core` contains loaders for Claude Code plugins, agents, commands, MCP, and shared path/model utilities.

The OpenCode adapter uses this compatibility layer to load:

- Claude Code-style hooks.
- Claude Code-style MCP configs.
- Claude/project/user skills.
- Agent definitions.
- Commands.

`applyHookConfig()` writes loaded Claude plugin hook configs into state consumed by the `claude-code-hooks` hook. A comment in that file notes that the state key must use `process.cwd()` because `loadClaudeHooksConfig` reads by `process.cwd()`, and keying by the plugin host directory silently dropped hooks in worktree/launcher scenarios.

This is another relevant pattern: OMO does not only consume OpenCode's native plugin API; it builds compatibility adapters that map other harness concepts onto OpenCode hook/config surfaces.

## 8. Does OMO maintain a fork of OpenCode?

Based on the inspected v4.12.1 checkout, OMO does not vendor or maintain an OpenCode source fork inside the repository.

Evidence:

- No `.gitmodules` file was found.
- The OMO root `package.json` depends on `@opencode-ai/plugin` and `@opencode-ai/sdk`, not OpenCode source.
- The OpenCode-facing code lives under `packages/omo-opencode`, named and documented as an adapter/plugin.
- The installer and docs say Ultimate edition lands as a plugin registered in `opencode.json` plus OMO config.
- The local postinstall checks that an `opencode` binary exists and is at least `1.4.0`, but it does not install or build OpenCode.
- Doctor checks inspect the OpenCode binary, OpenCode config, loaded plugin version, and plugin registration.

OMO works primarily through plugins, hooks, config injection, tools, MCPs, skill loading, and runtime session calls. It does maintain local source code for its own adapter and core packages, and this local installation is patched by this operator, but that is an OMO source patch stream, not an upstream OpenCode fork embedded in OMO.

## 9. Versioning and upstream OpenCode coupling

OMO is versioned independently as `4.12.1` in the root package and platform binary optional dependencies. It is not locked to a single exact OpenCode binary version in the inspected files.

Observed coupling points:

- `@opencode-ai/plugin` and `@opencode-ai/sdk` are pinned to `1.15.13` in root and `packages/omo-opencode/package.json`.
- `postinstall.mjs` checks `opencode --version` and warns if OpenCode is below `1.4.0`.
- Doctor framework constants also define `MIN_OPENCODE_VERSION = "1.4.0"`.
- Doctor checks warn if the loaded plugin is not registered, is using the legacy package name, is outdated compared to npm, or has a loaded/expected version mismatch.
- Auto-update checker code tracks OMO's own npm package versions, not upstream OpenCode release versions.
- `bin/version-mismatch.js` detects drift between the main npm package version and the installed platform binary package version. The comparison is exact semver, including prerelease identity, so `4.5.1-beta.1` and `4.5.1` are treated as different versions.
- `postinstall.mjs` invalidates OpenCode's cached OMO plugin package directories under `~/.cache/opencode/packages/oh-my-open*` so OpenCode re-resolves the plugin after OMO upgrades.

The practical model is compatibility by plugin API package + runtime doctor checks + minimum OpenCode version warning. It is not an exact OpenCode-version fork model.

## 10. OMO update model

OMO has an internal auto-update checker for OMO's own npm package.

The `auto-update-checker` hook:

- Runs once after top-level `session.created`, skipping CLI run mode and child sessions.
- Shows startup/version toasts.
- Builds connected-provider and model-capability caches.
- Determines current OMO version from local dev, bundled version, cached package version, or pinned plugin entry.
- Finds the OMO plugin entry in `opencode.json` / `opencode.jsonc`.
- Fetches npm dist-tags for the OMO package.
- Determines update channel from exact version, prerelease, or dist-tag.
- Skips install if `autoUpdate` is disabled.
- Skips install for exact semver-pinned plugin entries and only shows an update-available toast.
- Detects OpenCode-managed sandbox installs created by OpenCode's `Npm.add()` and avoids the old flat-cache `bun install` path because OpenCode would continue reading the sandbox copy. In that case it shows update-available and relies on OpenCode's plugin reinstall path.
- Otherwise syncs package-json intent, invalidates the package cache, runs `bun install` in the active workspace, primes cache if needed, and reports success/failure via toasts.

This update model is about keeping the OMO plugin package current and truthful about what is actually loaded. It is not an upstream OpenCode source-update mechanism.

The local config repo disables OMO's `auto-update-checker` hook in `oh-my-openagent.json` and instead manages OpenCode/OMO updates manually with the local `update-to-latest` skill and patch registry.

## 11. Patch-management patterns OMO itself exhibits

OMO's architecture shows several patterns relevant to patch management:

### Adapter boundary

OpenCode-specific code is kept in `packages/omo-opencode`. Shared behavior is being extracted into harness-neutral packages. This lets changes move from source patches toward reusable core logic plus thin adapter glue when the behavior is not truly OpenCode-specific.

### Named hook inventory

Behavior is represented as named hooks with a config disable list. This makes hook-level changes auditable and reversible. The local patch registry can mirror this by asking whether a desired behavior can be modeled as a new named hook instead of a source patch.

### Config overlay instead of source mutation

Agents, commands, MCPs, tools, runtime skill URLs, and provider-derived caches are injected through the OpenCode `config` hook. This is a strong alternative to direct source edits when the desired change is additive or policy-like.

### Runtime managers instead of scattered side effects

Long-lived behavior is pushed into managers such as `BackgroundManager`, `SkillMcpManager`, `TmuxSessionManager`, and `ConfigHandler`. Hooks call into shared managers rather than owning all state. This makes plugin-level patches more maintainable when runtime state is needed.

### Skill/MCP separation

Skill content, MCP server declarations, and runtime skill-source serving are separate from the OpenCode adapter. Behavior that is mostly instructions, tool docs, or external-tool routing can often be represented as a skill or skill-embedded MCP rather than an OpenCode source patch.

### Compatibility adapters

OMO ports Claude Code concepts into OpenCode through compatibility loaders. That demonstrates a pattern of adapting foreign extension concepts at the plugin layer instead of forking the host.

### Truthful update/load detection

Auto-update code distinguishes cached version, bundled version, local-dev version, config-pinned version, and OpenCode-managed sandbox installs. It has explicit logic to avoid claiming an update was applied when OpenCode will keep loading another copy. This is directly relevant to patch management because patch verification must check the artifact actually loaded, not just the file that was edited.

`bin/version-mismatch.js` adds a second truthfulness check at the platform-binary layer. It compares the main package version to the resolved platform package version and tells the operator to install both packages at the same version when they drift. This is the closest OMO-native analog to patch drift detection: the system does not only ask whether a package exists, it checks whether the executable artifact matches the version that should be active.

### Idempotent post-build patching

OMO has one literal patch script, `script/patch-node-require-shim.ts`. It is a post-build mutator for `dist/index.js` that replaces Bun's `import.meta.require` line with a Node/Electron-safe `createRequire` fallback. The script is idempotent: if the target shim is already present it exits successfully without rewriting. This is not an OpenCode source-patch system, but it is a useful pattern for local patch tooling: make text/bundle mutations narrowly targeted, reversible by rebuild, and safe to re-run.

### Release stamping and marketplace sync

OMO's release scripts also track derived artifacts. `script/publish.ts` bumps the root version and platform optional dependency versions in lockstep, while `script/sync-lazycodex-marketplace.ts` stamps release versions into marketplace plugin metadata and hook status messages. This reinforces the same operational pattern as the local patch registry: generated/installable artifacts need their own verification because they can drift from source files.

### Legacy migration with preservation

OMO migrates names and workspace state (`oh-my-opencode` to `oh-my-openagent`, `.sisyphus` to `.omo`) without simply deleting legacy paths. This resembles the local patch registry's rule to deprecate rather than delete obsolete patch entries.

## 12. Local patch registry compared against OMO extension surfaces

This section classifies the active or historically relevant local patches by whether the behavior looks expressible through OMO-style plugin/hook/config/skill mechanisms or whether it requires host/source modification. This is a descriptive fit analysis, not an architecture recommendation.

### Patches that require OpenCode source or upstream OpenCode API changes

#### `opencode--command-hook-cancellation`

This patch adds a `cancelled: boolean` field to OpenCode's `command.execute.before` output contract, changes OpenCode command prompt flow to skip `prompt()` when cancelled, and changes an HTTP handler to return an empty response for cancelled commands.

Why plugin-level is insufficient: existing plugins can set fields on the hook output, but without OpenCode core checking a cancellation field before `prompt()`, the command still reaches the agent. This is an upstream plugin API/command pipeline contract change.

Relevant OMO pattern: OMO uses `command.execute.before` for slash-command interception, but this patch changes what the host does after that hook. OMO-style hooks can consume the new capability once it exists; they cannot create the host-level cancellation semantics by themselves.

#### `opencode--commit-policy-unblock`

This patch modifies OpenCode's compiled base prompt/tool instruction text in OpenCode source and requires rebuilding the OpenCode binary.

Why plugin-level may not be equivalent: OMO can inject additional system transforms or agent instructions, but the patch changes upstream built-in prompt text embedded in the binary. A plugin overlay could add counter-instructions, but it would not remove the contradictory upstream text from all vanilla OpenCode prompt surfaces.

Relevant OMO pattern: OMO uses system/message transforms and agent prompt construction to add policies, but base OpenCode prompt text remains host-owned.

#### `omo--parent-wake-sync-mode-for-tui-render` (rolled back)

This patch attempted to change OMO dispatch mode for parent wake prompts but was rolled back as ineffective. The entry records the root cause as OpenCode TUI/SSE behavior for plugin-initiated turns: persisted messages do not reliably live-render in the TUI.

Why source/upstream is implicated: if the problem is OpenCode TUI SSE rendering for externally initiated prompt turns, changing OMO plugin dispatch mode is not enough. The durable fix belongs in OpenCode's event/TUI refresh path or in a host-exposed refresh mechanism.

Relevant OMO pattern: OMO's update code distinguishes persisted state from visible runtime state; this patch shows why real loaded/visible-surface verification matters.

### Patches that are OMO source patches today but resemble OMO-style hook/config candidates

#### `oh-my-openagent--context-overflow-max-token-error`

This patch changes OMO's token-limit detection logic in two hooks: todo continuation and Anthropic context-window recovery. It adds conservative request-token-overflow phrase detection and removes broad `max_tokens` false positives.

Current form: OMO source patch.

Potential plugin-level fit: It is internal classification logic used by OMO hooks. If OMO exposed configurable retry/error classifiers or hook extension points for token-limit detection, the behavior could become config/plugin-level. In the inspected architecture, those classifiers are not exposed as config; they are source-level hook internals.

Relevant OMO pattern: hook internals with targeted parser functions. The local retry-error registry pattern is similar in spirit, but this specific path sits inside OMO's compiled hook code.

#### `omo--glm-preemptive-compaction-threshold`

This patch changes OMO's preemptive compaction threshold for GLM models from a global threshold to a GLM-specific lower threshold.

Current form: OMO source patch.

Potential config-level fit: This is policy data keyed by model/provider. It resembles something that could be expressed as OMO config if the schema supported per-provider/model compaction thresholds. The patch entry itself names this as a possible durable alternative.

Relevant OMO pattern: OMO already has Zod config schemas and model/provider config handling. The architecture can carry this sort of policy as config, but the inspected schema does not show a current per-model threshold field for this behavior.

#### `omo--exclude-selected-auto-slash-commands`

This patch adds specific commands to `EXCLUDED_COMMANDS` and adds a guard in `command.execute.before` so selected skills remain available to agents but do not appear/execute as user-facing slash commands.

Current form: OMO source patch across `skills-loader-core` and `omo-opencode` auto-slash-command hook code.

Potential config/metadata fit: This is a strong candidate for a first-class OMO skill metadata or config field such as `slashExpose: false`. The patch entry identifies that durable alternative. OMO already parses skill metadata/frontmatter and merges skill definitions, so the architecture has a natural place for this data if upstream exposes it.

Relevant OMO pattern: `skills-loader-core` centralizes skill metadata; `createSkillHooks()` wires auto-slash-command behavior from merged skills. This behavior is aligned with OMO-style skill metadata more than host source patches.

#### `omo--clean-agent-display-names`

This patch changes OMO runtime display-name mapping and normalization to remove role suffixes and zero-width sort prefixes from visible agent labels.

Current form: OMO source or bundle patch, depending on runtime load path.

Potential config-level fit: The patch entry names a display-name override field or default-name change as the durable alternative. OMO already supports agent config overrides and agent-order config, but display-name overrides were not observed as a first-class schema field.

Relevant OMO pattern: OMO uses a narrow `installAgentSortShim()` and display-name mapping to manage UI ordering/labels. A config-level display-name field would fit OMO's config overlay model if exposed.

#### `omo--commit-policy-alignment`

This patch aligns OMO agent instructions and AGENTS.md with the local commit policy.

Current form: OMO source/documentation prompt patch.

Potential plugin/skill/config fit: Agent prompts are created by OMO factories and can accept some config overrides, prompt append files, and skill text. However, this patch replaces contradictory bundled instructions across agent prompt sources. A pure overlay can add local policy, but it may not remove upstream contradictory policy text unless OMO exposes a configurable commit-policy primitive or prompt section override.

Relevant OMO pattern: OMO's own roadmap hierarchy puts skills first for static knowledge and hooks/config for runtime behavior. This patch spans static agent instructions and would fit best as a first-class policy input if OMO exposes one.

### Patches superseded/upstreamed/retired

#### `omo--remove-activity-stagnation-bypass`

Status: upstreamed. The patch removed activity-based progress detection in the todo-continuation enforcer. The local entry says upstream shipped the same fix and v4.12.1 has the desired `"none" | "todo"` progress source.

Pattern: patch registry preserved the rationale and marked the entry upstreamed rather than deleting it.

#### `omo--boulder-worktree-authoritative-state`

Status: superseded. The entry says upstream v4.12.1 fixed the doom-loop through a different works-map architecture and the local resolver-layer patch should not be ported.

Pattern: patch registry records the superseding upstream mechanism and warns to write a new patch against the new architecture if needed.

#### DCP patches

The local manifest records `opencode-dcp--bounded-range-archive-mode`, `opencode-dcp--byte-budget`, and `opencode-dcp--compress-tool-prompt-contract` as retired because DCP/Magic Context is retired or disabled.

Pattern: when a dependency or feature is retired, patch entries remain as historical records with retired status.

## 13. Lessons from OMO architecture for patch tracking vocabulary

The following are vocabulary and classification patterns visible in OMO that can be reused when describing local patch debt:

- **Host API patch**: changes OpenCode plugin API or core control flow. Example: command hook cancellation.
- **Host prompt patch**: changes compiled OpenCode prompt/tool text. Example: OpenCode commit policy.
- **Adapter hook patch**: changes OMO OpenCode-adapter hook behavior. Examples: token overflow parser, preemptive compaction threshold, auto-slash command exclusion.
- **Adapter config candidate**: an adapter hook patch whose behavior is policy data that could fit OMO config if a schema field existed. Examples: GLM threshold, slash exposure, display names.
- **Skill metadata candidate**: behavior that belongs with skill definition/frontmatter. Example: slash exposure controls.
- **Runtime visibility bug**: behavior where state is persisted but not visible in the live UI. Example: parent-wake TUI render issue.
- **Upstreamed/superseded patch**: patch no longer needed because upstream solved the problem, sometimes differently. Examples: activity stagnation bypass, Boulder works-map architecture.
- **Retired dependency patch**: patch no longer active because the patched component is no longer used. Example: DCP patches.

## 14. Boundary observations for a possible OpenCode fork decision

No recommendation is made here. The observed boundary facts are:

- OMO gains large amounts of behavior without forking OpenCode by exploiting plugin lifecycle hooks, config transforms, MCP injection, tools, skills, and session events.
- OMO still hits hard host boundaries where plugin-level code cannot change OpenCode semantics: command pipeline cancellation, base prompt text embedded in the OpenCode binary, and TUI/SSE rendering behavior for plugin-initiated turns.
- OMO's own architecture pushes most reusable behavior into harness-neutral packages and keeps host-specific glue in adapters. This reduces the amount of code that must change when upstream host APIs move.
- OMO's update machinery is careful about the difference between edited files, cached package installs, sandbox package installs, bundled version, local dev version, and the artifact actually loaded by OpenCode.
- The local patch registry already reflects several OMO-like practices: durable alternative status, verification patterns, update reclassification, obsolete/upstreamed preservation, and explicit live-evidence caveats.

## 15. Direct answers to requested questions

1. **Structure:** OMO is a Bun monorepo with many `packages/*` workspaces. It is undergoing a multi-harness refactor into Core, MCP, Skills, Adapters, Platform, and Web layers. `packages/omo-opencode` is the OpenCode adapter; `packages/skills-loader-core` is harness-neutral skill infrastructure.
2. **Hooking into OpenCode:** OMO hooks through the OpenCode plugin API: plugin module, lifecycle hooks, `config` mutation, tool registration, command interception, chat/message/system transforms, event handlers, experimental compaction hooks, MCP injection, and SDK client calls.
3. **Fork or plugins/hooks/config:** The inspected checkout does not include or vendor an OpenCode source fork. It depends on `@opencode-ai/plugin` and `@opencode-ai/sdk` and works as a plugin/adapter. Local operator patches may target OpenCode or OMO source externally, but OMO itself is not an OpenCode fork in this checkout.
4. **Update model:** OMO tracks its own npm package and plugin load state via an auto-update checker, doctor checks, package cache inspection, dist-tags, pinned entry detection, and sandbox detection. It checks a minimum OpenCode version but does not track upstream OpenCode source changes as a fork.
5. **`skills-loader-core` and `omo-opencode`:** `skills-loader-core` handles skill discovery, parsing, dedupe, scope priority, skill config merging, skill MCP config, and runtime skill serving. `omo-opencode` wraps that and the other core packages into an OpenCode plugin adapter with managers, tools, hooks, and config injection.
6. **Version tie:** OMO v4.12.1 pins OpenCode plugin/sdk packages at `1.15.13` and warns below OpenCode `1.4.0`. It is not tied to one exact OpenCode binary version by the inspected metadata.
7. **Patch relevance:** Some local patches map naturally to OMO-style hooks/config/skills if upstream exposes the right surface (`slashExpose`, display-name config, per-model compaction thresholds). Others require OpenCode source/API modification because the plugin layer cannot change host control flow or host-rendering semantics (`command.execute.before` cancellation, embedded base prompt text, TUI/SSE live-rendering behavior).
