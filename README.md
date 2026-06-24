# ez-omo-config

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Sponsor](https://img.shields.io/badge/sponsor-%E2%9D%A4-lightgrey)](https://github.com/sponsors/EZotoff)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support-ff5e5b?logo=ko-fi&logoColor=white)](https://ko-fi.com/ezotoff)

> Production-ready OpenCode + Oh-My-OpenAgent configuration. 10 AI providers, 13 specialized agents, semantic code search, git safety & worktree plugins, one-command install with automatic backups.

Clone, run `./install.sh`, and get a fully configured AI coding environment in seconds. This repo contains **68 curated artifacts + 1 repo-tracked skill overlay** — reusable presets, plugins, skills, and scripts — organized into a portable configuration you can fork and adapt.

> **RESTORED**: [Vera](https://github.com/lemon07r/Vera) semantic code search integration — now with guarded autostart (ON by default), per-session bounded logging, binary discovery with cache revalidation, and a repo-tracked skill overlay at `skills/vera/`. See [Implementation Plan](docs/vera-implementation-plan.md).

---

## Quick Start

Get up and running in three steps:

```bash
# 1. Clone the repository
git clone https://github.com/EZotoff/ez-omo-config.git
cd ez-omo-config

# 2. Run the installer (dry-run first to preview changes)
./install.sh --dry-run

# 3. Install for real
./install.sh
```

Verify installation by checking the installed configs:
```bash
ls -la ~/.config/opencode/
ls -la ~/.opencode/plugin/
```

---

## What Changes After Installing

After running `./install.sh`, your OpenCode CLI gains:

- **`/models-preset`** — view all 13 agent model assignments, category presets, compaction model, and small model at a glance
- **`/session-id`** — copy the invoking session ID to clipboard (no LLM round-trip)
- **`/session-info`** — copy project path, session title, and invoking session ID to clipboard (no LLM round-trip)
- **Git safety guardrails** — automatic prevention of destructive git operations
- **Worktree-aware development** — parallel worktrees with port allocation and Docker isolation
- **Semantic session-scoped checkpoints** — automatic git checkpoint commits scoped to root session trees, with LLM-powered file selection and temp-index safety
- **Runtime fallback** — automatic model switching across 9 providers when APIs fail or rate-limit
- **Wisdom system** — learning management that captures and reuses development knowledge
- **Review enforcement** — automated code review triggers after completing implementation work
- **Subagent loop guard** — configured to catch same-tool and same-tool-varying-input loop patterns that strict consecutive-signature detection misses
- **Clickable file links (TUI)** — every agent formats file references as `[label](file:///abs/path)` markdown links so they are clickable in OSC 8 terminals (Ghostty, Kitty, WezTerm, Alacritty, iTerm2); closes the gap between the built-in prompts' "backtick paths are clickable" claim and the OpenTUI renderer, which only linkifies real markdown links
- **Semantic code search** — Vera integration for 70%+ token reduction during codebase discovery. Guarded autostart is ON by default (`OMO_VERA_RUNTIME_AUTOSTART=0` to disable). Per-session bounded logging with 7-day retention. Repo-tracked skill overlay at `skills/vera/` installs via `install.sh --skills`. See [docs/vera-implementation-plan.md](docs/vera-implementation-plan.md)
- **Vera index hygiene** — automatic `.veraignore` management that detects unreadable dirs, heavy generated artifacts, and prevents self-indexing before Vera root-indexes a project
- **Aspect Dynamics** — deterministic heuristic scoring that detects emotional and behavioral patterns in conversation transcripts and dispatches transcript-visible advisory nudges to guide agent tone and focus
- **OpenCode/OMO context management** — OpenCode compaction and OMO preemptive compaction/context-window hooks are enabled; Magic Context is retained only as a disabled config file.
- **Safe update pipeline** — guided OpenCode/OMO update analysis with explicit human approval gate, patch-tracker integration, rollback capability, adaptive regression testing, and evidence-state claim discipline
- **Global deployment-skill mandate** — every session loads `~/.config/opencode/AGENTS.md`, which requires invoking the `/deployment` skill before binding ports or launching dev/test servers. Eliminates cross-project port conflicts

---

## What's Included

This repository contains 68 core artifacts + 1 repo-tracked skill overlay + 1 external binary organized into 9 categories:

| # | Category | Artifacts | Description |
|---|----------|-----------|-------------|
| 1 | **Commands** | 4 files | Slash commands for OpenCode workflows |
| 2-5 | **Configs** | 17 files | Core OpenCode and OMO configuration files, including the Aspect Dynamics plugin, its support modules, and two seed aspect sets |
| 6-11 | **Plugins** | 13 files + kdco-primitives dir | TypeScript plugins for worktrees, git safety, review enforcement, VS Code launcher, session clipboard commands, Vera runtime state with guarded autostart and bounded logging, semantic checkpointing, configured subagent loop guarding, and TUI clickable-link system-prompt injection |
| 12-22 | **Skills** | 13 directories | Specialized agent skills for retry-error registration, patch tracking, deployment, parallel development, Vera hygiene, safe update pipelines, and a repo-tracked Vera skill overlay. (`playwright`, `frontend-ui-ux`, and `github-triage` ship with [OMO upstream](https://github.com/code-yeongyu/oh-my-openagent) and are not vendored here.) |
| 22-31 | **Scripts** | 21 shell scripts | Wisdom propagation, observability, worktree lifecycle, live deployment verification, and Vera hygiene scripts |
| 32 | **Tests** | 23 test scripts | Regression tests for config, plugin, and update pipeline verification |
| 33 | **Extras** | 1 file | Additional registry configuration |
| 34-35 | **Docker** | 2 files | Worktree container templates |
| 36-39 | **Docs** | 6 files | Configuration, plugin, skills, worktree state, live deployment verification, compatibility debt, and retired DCP byte-budget reference |
| 40 | **External** | 1 binary | [Vera](https://github.com/lemon07r/Vera) semantic code search binary (installed separately via `vera agent install --client opencode`). The skill overlay is repo-tracked at `skills/vera/`. |

### Complete Artifact Inventory

| # | Artifact | Path | Purpose |
|---|----------|------|---------|
| 1 | `models-preset.md` | `commands/` | Slash command for showing current OMO model assignments plus compaction and small-model settings |
| 1b | `vscode.md` | `commands/` | VS Code launcher command stub (handled by plugin) |
| 1c | `session-id.md` | `commands/` | Session ID clipboard command stub (handled by plugin) |
| 1d | `session-info.md` | `commands/` | Session info clipboard command stub (handled by plugin) |
| 2 | `opencode.json` | `configs/opencode/` | Main OpenCode provider and model configuration |
| 3 | `opencode.jsonc` | `configs/opencode/` | User-specific OpenCode settings |
| 3b | `dcp.jsonc.retired` | `configs/opencode/` | Retired DCP plugin config. Magic Context was tried as the replacement on 2026-06-23 and is currently disabled. Not installed. |
| 4 | `provider-connect-retry.mjs` | `configs/opencode/` | Auto-retry logic for provider connections with empty-response detection and registry-driven error matching |
| 4b | `retry-errors.json` | `configs/` | Retry registry: error patterns, backoff schedules, nudge prompts, and fallback models for the retry plugin |
| 5 | `oh-my-openagent.json` | `configs/oh-my-openagent/` | Agent model assignments and experimental features |
| 6 | `worktree.ts` | `plugins/` | Git worktree management plugin |
| 7 | `worktree/state.ts` | `plugins/worktree/` | Worktree state management |
| 8 | `worktree/terminal.ts` | `plugins/worktree/` | Terminal integration for worktrees |
| 9 | `git-safety.ts` | `plugins/` | Git safety protocol enforcement |
| 10 | `review-enforcer.ts` | `plugins/` | Automated code review triggers |
| 11 | `kdco-primitives/` | `plugins/` | Shared library for plugins |
| 11b | `vscode.ts` | `plugins/` | VS Code launcher plugin (intercepts /vscode, no LLM round-trip) |
| 11c | `session-id.ts` | `plugins/` | Session ID clipboard plugin (intercepts /session-id, no LLM round-trip) |
| 11d | `session-info.ts` | `plugins/` | Session info clipboard plugin (intercepts /session-info, no LLM round-trip) |
| 11e | `vera-runtime.ts` | `plugins/` | Vera runtime state plugin (guarded-autostart index lifecycle ON by default, binary discovery with cache revalidation, per-session bounded logging, fail-open) |
| 11f | `auto-checkpoint.ts` | `plugins/` | Semantic session-scoped checkpoint plugin |
| 11g | `subagent-loop-guard.ts` | `plugins/` | Configured per-session tool-call loop guard for same-tool frequency and same-tool varying-input patterns |
| 11h | `clickable-links.ts` | `plugins/` | System-prompt injection via `experimental.chat.system.transform` — tells every agent to format file references as `[label](file:///abs/path)` markdown links so they are clickable in the TUI |
| 12 | `wisdom/` | `skills/` | Wisdom propagation and knowledge management (primary runtime memory skill) |
| 12b | `patch-tracker/` | `skills/` | Patch registry CRUD and post-update verification skill |
| 12c | `register-retry-error/` | `skills/` | Retryable error pattern registration skill |
| 12d | `session-id/` | `skills/` | Session ID clipboard (skill form, mirrors the `/session-id` plugin) |
| 12e | `debate/` | `skills/` | Structured adversarial debate protocol with configurable judge panels and 6 distinct modes |
| 13 | `atlas-review-handler/` | `skills/` | Review orchestration skill |
| 14 | `review-protocol/` | `skills/` | Code review protocol implementation |
| 16 | `deployment/` | `skills/` | Infrastructure deployment helpers |
| 16b | `AGENTS.md` (global) | `configs/opencode/` | Global user-level agent instructions loaded by OpenCode on top of any project-level `AGENTS.md`. Currently mandates the `/deployment` skill before binding ports or launching dev/test servers. Atomic-install tag: `skills+configs` |
| 18 | `wisdom-common.sh` | `scripts/wisdom/` | Shared wisdom utilities |
| 19 | `wisdom-search.sh` | `scripts/wisdom/` | Search wisdom database |
| 20 | `wisdom-write.sh` | `scripts/wisdom/` | Write new learnings |
| 21 | `wisdom-sync.sh` | `scripts/wisdom/` | Sync wisdom across notepads |
| 22 | `wisdom-archive.sh` | `scripts/wisdom/` | Archive old wisdom entries |
| 23 | `wisdom-delete.sh` | `scripts/wisdom/` | Delete wisdom entries |
| 24 | `wisdom-edit.sh` | `scripts/wisdom/` | Edit existing wisdom |
| 25 | `wisdom-gc.sh` | `scripts/wisdom/` | Garbage collect wisdom |
| 26 | `wisdom-merge.sh` | `scripts/wisdom/` | Merge wisdom databases |
| 26a | `wisdom-observe.sh` | `scripts/wisdom/` | Operator-facing observability CLI for wisdom events |
| 26b | `wisdom-publish.sh` | `scripts/wisdom/` | Publishes a wisdom entry as a derivative artifact |
| 26c | `wisdom-closeout.sh` | `scripts/wisdom/` | Closeout capture handler (provenance=closeout) |
| 26d | `wisdom-nominate.sh` | `scripts/wisdom/` | Passive nomination handler for candidate wisdom |
| 26e | `wisdom-migrate.sh` | `scripts/wisdom/` | Migration backups + idempotent manifest import |
| 26f | `wisdom-restore.sh` | `scripts/wisdom/` | Restores backup tarballs produced by migrate |
| 26g | `manifest-write.sh` | `scripts/wisdom/` | Creates knowledge manifests with YAML frontmatter |
| 26h | `knowledge-constants.sh` | `scripts/wisdom/` | Shared constants sourced by `wisdom-publish.sh`, `manifest-write.sh`, and tests |
| 27 | `ocx.jsonc` | `extras/` | Additional registry configuration |
| 28 | `merge-agent/` | `skills/` | Safe branch merging with guardrails |
| 29 | `parallel-dev/` | `skills/` | Multi-agent orchestration with decision framework |
| 30a | `vera-hygiene/` | `skills/` | Vera index hygiene skill — `.veraignore` management and pre-indexing cleanup |
| 30b | `update-to-latest/` | `skills/` | Safe OpenCode/OMO update pipeline with explicit approval gate, patch-tracker integration, rollback capability, and evidence-state reporting |
| 31 | `worktree-post-create.sh` | `scripts/` | State creation, port allocation, Docker start, and Vera state recording. Guarded autostart is ON by default. Install: `$HOME/.opencode/scripts/worktree-post-create.sh` |
| 32 | `worktree-pre-delete.sh` | `scripts/` | Container stop, port free, state cleanup, and Vera watcher cleanup. Install: `$HOME/.opencode/scripts/worktree-pre-delete.sh` |
| 32a | `vera-hygiene.sh` | `scripts/` | Vera hygiene script — detects unreadable dirs, heavy artifacts, and updates `.veraignore`. Install: `$HOME/.sisyphus/scripts/vera-hygiene.sh` |
| 33 | `worktree.jsonc` | `configs/opencode/` | Worktree sync config and hook registration. Install: `$HOME/.opencode/worktree.jsonc` |
| 34 | `worktree-compose.template.yml` | `docker/` | Per-worktree container isolation template |
| 35 | `docker/README.md` | `docker/` | Docker worktree setup instructions |
| 36 | `worktree-state-schema.md` | `docs/` | Runtime state file formats and locations |
| 37 | `vera/` (repo-tracked overlay) | `skills/vera/` | Semantic code search skill overlay with self-heal protocol (cold-index check, stale-index update, diagnostics before fallback). Installs to `~/.config/opencode/skills/vera/` via `install.sh --skills`. The Vera binary itself is external. |
| 38 | `aspect-dynamics.mjs` | `configs/opencode/` | Config-layer plugin entry: heuristic scoring and advisory nudge dispatch |
| 39 | `aspect-dynamics/config.mjs` | `configs/opencode/` | Config loader with deferred-field safeguards |
| 40 | `aspect-dynamics/context.mjs` | `configs/opencode/` | Conversation context extraction and recursion guard |
| 41 | `aspect-dynamics/heuristics.mjs` | `configs/opencode/` | Deterministic heuristic scorer for aspect sets |
| 42 | `aspect-dynamics/session-state.mjs` | `configs/opencode/` | Per-session state tracking, deduplication, and circuit breaker |
| 43 | `aspect-dynamics/sets.mjs` | `configs/opencode/` | Aspect set loader and resolver |
| 44 | `aspect-dynamics/nudge.mjs` | `configs/opencode/` | Transcript-visible advisory nudge formatter |
| 45 | `aspect-dynamics/logging.mjs` | `configs/opencode/` | Structured logging utilities |
| 46 | `aspect-dynamics/sets/emotions-v1.json` | `configs/opencode/` | Seed aspect set for emotional tone detection |
| 47 | `tests/aspect-dynamics/harness.mjs` | `tests/aspect-dynamics/` | Test harness for aspect-dynamics unit tests |
| 48 | `tests/test_aspect_dynamics_runtime.sh` | `tests/` | Regression wrapper for aspect-dynamics runtime verification |
| 49 | `scripts/verify-live-deployment.sh` | `scripts/` | Live deployment verifier with evidence-state validation |
| 50 | `tests/test_live_deployment_contract.sh` | `tests/` | Repo-safe contract tests for live deployment verification |
| 50a | `tests/test_vera_hygiene.sh` | `tests/` | Vera hygiene verification — idempotency, safety, and blocker detection tests |
| 50b | `tests/test_review_enforcer_completion_instruction.sh` | `tests/` | Regression test for PLAN_COMPLETION_INSTRUCTION block extraction and content verification |
| 50c | `tests/test_openai_provider.sh` | `tests/` | Regression test for Codex display provider presence in opencode.json (`openai` key) |
| 50d | `tests/test_subagent_loop_guard.sh` | `tests/` | Regression test for subagent loop guard detection, cooldown, per-session tracking, ring eviction, disable flag, and fail-open behavior |
| 51 | `docs/live-deployment-verification.md` | `docs/` | Live Deployment Verification Gate documentation |
| 51a | `aspect-dynamics/sets/emotions-v2.json` | `configs/opencode/` | Versioned distress-focused seed aspect set with profanity-aware heuristics |
| 52 | `docs/dcp-byte-budget.md` | `docs/` | RETIRED 2026-06-23: DCP byte-budget gate reference. Magic Context was tried as the replacement and is currently disabled. Historical record only. |

---

## Architecture Overview

This configuration bridges **OpenCode** (the core CLI) with **Oh-My-OpenAgent** (enhancement layer).

```
┌─────────────────────────────────────────────────────────────┐
│                    OpenCode CLI                            │
│         (Core AI coding assistant engine)                  │
└────────────────────┬────────────────────────────────────────┘
                     │
         ┌───────────┴───────────┐
         │                       │
┌────────▼─────────┐    ┌────────▼─────────┐
│  Config Layer    │    │   Plugin Layer   │
│  (opencode.json) │    │  (TypeScript)    │
│  - Providers     │    │  - Worktrees     │
│  - Models        │    │  - Git Safety    │
│  - Settings      │    │  - Reviews       │
└────────┬─────────┘    └────────┬─────────┘
         │                       │
         └───────────┬───────────┘
                     │
         ┌───────────▼───────────┐
│   Oh-My-OpenAgent Layer        │
│   (oh-my-openagent.json)       │
│   - Agent assignments         │
│   - Category overrides        │
│   - Experimental features     │
└───────────┬───────────────────┘
            │
    ┌───────┴───────┐
    │               │
┌───▼────┐   ┌──────▼──────┐
│ Skills │   │   Scripts   │
│ (Dirs) │   │  (Shell)    │
│ - Test │   │ - Wisdom    │
│ - Deploy│  │ - Search    │
│ - UX   │   │ - Sync      │
└────────┘   └─────────────┘
```

### Category Descriptions

- **Commands**: Slash command prompts for repeatable OpenCode workflows
- **Configs**: Provider definitions, model configurations, and retry logic
- **Plugins**: TypeScript extensions that add worktree management, git safety checks, and review enforcement
- **Skills**: Specialized agent capabilities for browser testing, deployment, UI/UX design, and Vera index hygiene
- **Scripts**: Shell utilities for the wisdom propagation system, worktree lifecycle, live deployment verification, and Vera hygiene
- **Extras**: Optional registry and utility configurations

---

## Installation Options

The `install.sh` script supports several modes and flags:

### Preview Mode
```bash
./install.sh --dry-run    # Show what would be installed without making changes
```

### Installation Modes
```bash
./install.sh --symlink    # Create symlinks (default, recommended for development)
./install.sh --copy       # Copy files instead of symlinking
```

### Selective Installation
Install only specific artifact types:
```bash
./install.sh --configs    # Install only config files
./install.sh --commands   # Install only slash commands
./install.sh --plugins    # Install only plugins
./install.sh --skills     # Install only skills
./install.sh --scripts    # Install all scripts (wisdom + worktree hooks)
```

The `commands` category installs slash-command prompts into `~/.config/opencode/command/`, including `/models-preset` at `~/.config/opencode/command/models-preset.md`.

Combine flags as needed:
```bash
./install.sh --dry-run --configs --plugins   # Preview configs and plugins only
```

### Platform Notes

**Windows Users**: This configuration is designed for Linux/macOS. For Windows, use [WSL](https://learn.microsoft.com/en-us/windows/wsl/install):
```bash
# In WSL terminal
git clone https://github.com/EZotoff/ez-omo-config.git
cd ez-omo-config
./install.sh
```

---

## Configuration Highlights

### 9 Enabled Providers

| Provider | Description | Key Models |
|----------|-------------|------------|
| **Google** | Gemini and Antigravity-hosted models | Gemini 3.5 Flash, Gemini 3.1 Pro Preview, Antigravity Gemini 3.5 Flash, Claude Sonnet/Opus Thinking |
| **Codex** | GPT models via Codex OAuth (`openai` provider key) | GPT 5.2, GPT 5.5, GPT 5.4, GPT 5.3 Codex, GPT 5.1 Codex Max |
| **OpenCode Go** | Built-in OpenCode Go provider | Minimax M3, Kimi K2.6, DeepSeek V4 Flash |
| **Moonshot** | Kimi models via OpenAI-compatible API | Kimi K2.5, Kimi K2.6, Kimi K2.7 Code |
| **Kimi Code** | Kimi coding models via Anthropic-compatible API | Kimi K2.5 (`k2p5`) |
| **Kimi For Coding (OAuth)** | Kimi K2.7 Code via device-flow OAuth | Kimi K2.7 Code (`kimi-for-coding` alias auto-routes to K2.7 Code with thinking on, falls back to K2.6 with thinking off) |
| **Z.AI Coding Plan** | GLM models via Coding Plan OpenAI-compatible API | GLM 5, GLM 5.1, GLM 5.2 |
| **DeepSeek** | DeepSeek V3.2 + V4 | DeepSeek Chat, DeepSeek Reasoner, DeepSeek V4 Flash, DeepSeek V4 Pro |
| **Inception Labs** | Mercury models | Mercury 2 |

### 13 Agent Model Assignments

| Agent | Primary Model | Variant | Fallback Model | Purpose |
|-------|---------------|---------|----------------|---------|
| **atlas** | `zai-coding-plan/glm-5.2` | default | `kimi-for-coding-oauth/kimi-for-coding`, `openai/gpt-5.4` | Orchestrator with wisdom injection |
| **prometheus** | `zai-coding-plan/glm-5.2` | high | `openai/gpt-5.5`, `zai-coding-plan/glm-5.2` | Planner, deep reasoning, HTML proposal packets before executable plans |
| **sisyphus** | `zai-coding-plan/glm-5.2` | high | `openai/gpt-5.5`, `kimi-for-coding-oauth/kimi-for-coding` | Executor, focused tasks |
| **sisyphus-junior** | `zai-coding-plan/glm-5.2` | default | `openai/gpt-5.4` | Category task executor |
| **librarian** | `opencode-go/minimax-m3` | default | (none) | Search, documentation |
| **explore** | `opencode-go/minimax-m3` | default | `opencode-go/deepseek-v4-flash` | Discovery, exploration |
| **frontend-ui-ux-engineer** | `google/gemini-3.5-flash` | high | `zai-coding-plan/glm-5.2` | Complex frontend work |
| **document-writer** | `opencode-go/kimi-k2.6` | default | `zai-coding-plan/glm-5.2` | Writing, documentation |
| **multimodal-looker** | `google/gemini-3.5-flash` | default | (none) | Image/PDF analysis |
| **oracle** | `openai/gpt-5.5` | high | `google/gemini-3.1-pro-preview` | Q&A, knowledge queries |
| **metis** | `openai/gpt-5.5` | high | `google/gemini-3.1-pro-preview` | Deep analysis |
| **momus** | `openai/gpt-5.5` | xhigh | `google/gemini-3.1-pro-preview` | Code review, critique |
| **hephaestus** | `openai/gpt-5.4` | xhigh | (none) | Infrastructure, deployment |

#### Prometheus planning artifact flow

For complex multi-step work, Prometheus produces an HTML Proposal+Design Packet before generating the executable Markdown plan. The flow is:

```
User request → Prometheus HTML Proposal+Design Packet → pre-plan checkpoint → .sisyphus/plans/*.md → Atlas/Sisyphus execution
```

The HTML packet is for human review and discussion. The Markdown plan remains canonical for execution. Simple or single-step work stays lean and autonomous and does not require reusable HTML template or generator infrastructure.

### Key Experimental Features

| Feature | Status | Description |
|---------|--------|-------------|
| **Magic Context** | Disabled | Plugin removed from `opencode.json#plugin`; `magic-context.jsonc#enabled=false` is retained for rollback/reference only. |
| **OpenCode Compaction** | Enabled | `opencode.json#compaction.auto=true` and `compaction.prune=true`; OpenCode owns built-in context compaction/pruning. |
| **OMO Context Hooks** | Enabled | `preemptive-compaction`, `context-window-monitor`, and `anthropic-context-window-limit-recovery` are no longer listed in `disabled_hooks`; `experimental.preemptive_compaction=true`. |
| **Aggressive Truncation** | Enabled | Truncates verbose tool outputs aggressively |
| **Runtime Fallback** | Enabled | Automatically switches to fallback models on API errors (404, 429, 500, 502, 503, 504) |
| **Turn Protection** | Enabled | Protects critical tools (task, todowrite, lsp_rename) for 3 turns after use |
| **Purge Errors (2-turn)** | Enabled | OMO `dynamic_context_pruning.strategies.purge_errors` is enabled with a 2-turn retention window. |
| **Background Task Circuit Breaker** | Enabled (maxToolCalls=500, consecutiveThreshold=15) | Configured to cancel runaway subagent tasks when a task reaches 500 total tool calls or 15 consecutive identical tool+input signatures. OMO default is 4000/20; lowered thresholds trip earlier |
| **Auto-Update Checker** | Disabled | `oh-my-openagent.json#disabled_hooks: ["auto-update-checker"]` opts out of OMO's startup update-check hook. Updates are managed manually via the `update-to-latest` skill |

### Doom-Loop Mitigations

The configuration includes layered defenses against runaway subagent sessions (forensic root cause: 14 Jun 2025 visual-engineering QA loop burned $43.58 / 14.3M input tokens in 77 minutes; 21 Jun build/test ping-pong burned $12.75 / 50M cache-read tokens in 27 minutes):

| Layer | Setting | Effect |
|-------|---------|--------|
| **Model demotion** | `oh-my-openagent.json#categories.visual-engineering.model` = `google/gemini-3.5-flash` | Per-token cost ~10× lower than Pro Preview; 1M context preserved |
| **Aggressive error purge** | Enabled via OMO dynamic context pruning | Drops failed build/test outputs after 2 turns using OMO's context-pruning strategy. |
| **Tool-call circuit breaker** | `oh-my-openagent.json#background_task.circuitBreaker.{maxToolCalls: 500, consecutiveThreshold: 15}` | Configured to cancel any subagent task that reaches 500 total tool calls or repeats the same tool+input 15× in a row. Intended to catch 14 Jun-class loops; alternation patterns (e.g. 21 Jun's `npm run build` ↔ `npm run test`) are NOT cancelled by this setting and rely on the subagent loop guard sliding-window detector. |
| **Subagent loop guard plugin** | `opencode.json#plugin: file:///home/ezotoff/.opencode/plugin/subagent-loop-guard.ts` | Configured to watch the last 50 tool calls per session, convert bash calls to `echo "[loop-guard] blocked: ..."` when Rule A or Rule B fires, and log a Rule C informational warning past the configured total-call threshold |

**Known limitation**: `consecutiveThreshold` only catches *strictly* consecutive identical signatures. Alternating tool patterns (`build → test → build → test`) reset the counter each call and defeat the detector. The `maxToolCalls` cap is the only hard backstop for those patterns, and it triggers on total volume rather than loop shape. The `subagent-loop-guard.ts` plugin is configured to add sliding-window detection as a local add-on.

**Evidence state**: The OMO/config-setting mitigations are `repo_implemented`, `live_file_installed` (via symlink), and `active_config_registered`. The `subagent-loop-guard.ts` row is `repo_implemented` and `active_config_registered` only until `install.sh --plugins` is run. **Not verified live: `live_file_installed` for the new plugin, `runtime_loaded`, `real_project_behavior_proven`**.

### Subagent Loop Guard Plugin

The built-in OMO circuit breaker cannot catch alternating patterns or same-tool-varying-input patterns (see Known Limitation above). The `subagent-loop-guard.ts` plugin is configured to add sliding-window detection on top of OMO's consecutive-signature detector.

| Detection Rule | Window | Threshold | Trigger | Configured action |
|----------------|--------|-----------|---------|--------|
| **A — Tool-frequency alternation** | Last 50 calls | Same tool >30 times | Configured to catch 14 Jun-class agent-browser cycles | Mutate bash command to no-op + log warning |
| **B — Same-tool varying-input** | Last 30 calls | Same tool >20 times with all-different signatures | Configured to catch 21 Jun-class build↔test cycles and screenshot-with-varying-URL loops | Mutate bash command to no-op + log warning |
| **C — Informational threshold** | Per session | >300 total calls | Heads-up before OMO's maxToolCalls=500 fires | Log warning only (no blocking) |

**Env vars** (all optional, read at plugin init):
- `OMO_LOOP_GUARD_WINDOW_A` (default 50), `OMO_LOOP_GUARD_N_A` (default 30)
- `OMO_LOOP_GUARD_WINDOW_B` (default 30), `OMO_LOOP_GUARD_N_B` (default 20)
- `OMO_LOOP_GUARD_INFO_THRESHOLD` (default 300)
- `OMO_LOOP_GUARD_COOLDOWN_MS` (default 60000 — per-session per-rule cooldown to avoid transcript spam)
- `OMO_LOOP_GUARD_DISABLE=1` (kill switch — plugin no-ops all hooks)

**Evidence state**: `repo_implemented`, `tests_passed`, and `active_config_registered`. **Not verified live: `live_file_installed`, `runtime_loaded`, `real_project_behavior_proven`** — install via `install.sh` and restart OpenCode to load the plugin.

**What the plugin CANNOT do**:
- Cannot truly cancel a task (no `cancelTask` in plugin SDK). Bash arg-mutation makes individual bash calls into no-ops; other tools (e.g., agent-browser) only get a logged warning.
- Cannot catch single long-running tool calls (count-based detection only sees discrete tool boundaries).
- Cannot enforce aggregate caps across sibling subagents (each session tracked independently).

### Future Work: Periodic Lead-Agent Inspection

The mitigations above are reactive (detect-and-block). A complementary proactive mechanism would let the lead agent periodically inspect running subagents without breaking their flow. Sketch of options:

| Option | Mechanism | Breaks Flow? | Complexity |
|--------|-----------|--------------|------------|
| **Push (transcript inject)** | Plugin uses `client.session.promptAsync(parentID, status)` every 15 min | Yes — parent processes injection as new user turn | Medium |
| **Pull (sidecar log)** | Plugin writes status snapshots to `~/.sisyphus/agent-watch/<child>.json`; parent reads when curious | No (passive) | Low |
| **Pull (transcript annotation)** | Plugin annotates the parent's next tool call args with a status comment | No (in-band) | Medium |
| **Upstream OMO patch** | Fix `lastMessageAt` assignment in `manager.ts` so the existing babysitter hook fires | No (handled by OMO) | High (requires OMO source patch + maintenance) |

Out of current scope. Will revisit after observing how the circuit breaker + loop guard perform in real visual-engineering subagent runs.

### Context Management

Magic Context (`@cortexkit/opencode-magic-context@latest`) is disabled. It is no longer registered in `opencode.json#plugin`, and `magic-context.jsonc#enabled` is `false` for rollback/reference only.

OpenCode and OMO now own context management:

- `opencode.json#compaction.auto=true` — OpenCode automatic compaction is enabled.
- `opencode.json#compaction.prune=true` — OpenCode compaction pruning is enabled.
- `oh-my-openagent.json#experimental.preemptive_compaction=true` — OMO preemptive compaction is enabled.
- `oh-my-openagent.json#disabled_hooks` only disables `auto-update-checker`; context hooks are active.
- `oh-my-openagent.json#experimental.dynamic_context_pruning.enabled=true` — OMO dynamic context pruning is enabled, including 2-turn error purging and write-supersession deduplication.

Historical context:

- DCP (`@tarquinen/opencode-dcp@3.1.13`) remains retired; `dcp.jsonc` is archived to `dcp.jsonc.retired`.
- The 3 DCP patches remain retired: bounded-range-archive-mode, byte-budget, compress-tool-prompt-contract.

### Patch Documentation

For install locations, failure string meanings, and reapply instructions:
- **Context overflow max-token detection**: `.sisyphus/patches/oh-my-openagent--context-overflow-max-token-error.md` (active on OMO v4.12.1)
- **Clean agent display names**: `.sisyphus/patches/omo--clean-agent-display-names.md` (active on OMO v4.12.1)
- **Commit policy alignment**: `.sisyphus/patches/omo--commit-policy-alignment.md` (active on OMO v4.12.1)
- **Exclude auto-slash commands**: `.sisyphus/patches/omo--exclude-selected-auto-slash-commands.md` (active on OMO v4.12.1)
- **GLM preemptive compaction threshold**: `.sisyphus/patches/omo--glm-preemptive-compaction-threshold.md` (active on OMO v4.12.1)
- **Parent-wake sync mode for TUI render**: `.sisyphus/patches/omo--parent-wake-sync-mode-for-tui-render.md` (ROLLED BACK — ineffective; root cause is upstream OpenCode TUI SSE bug, not OMO dispatch mode)
- **Boulder worktree authoritative state**: `.sisyphus/patches/omo--boulder-worktree-authoritative-state.md` (superseded by upstream v4.12.1 works-map architecture)
- **Remove activity stagnation bypass**: `.sisyphus/patches/omo--remove-activity-stagnation-bypass.md` (upstreamed in OMO commit df7e1ae1)

---

## Related Projects

- **[OMO Pulse](https://github.com/EZotoff/omo-pulse)** - Dashboard for monitoring Oh-My-OpenAgent activity and agent performance

---

## Dependencies

Before using this configuration, ensure you have:

1. **OpenCode CLI** - The core AI coding assistant ([installation guide](https://opencode.ai))
2. **Oh-My-OpenAgent** - Enhancement layer for OpenCode

The installer handles placing configuration files in the correct locations. It does not install OpenCode or OMO themselves.

---

## Backup & Rollback

### Automatic Backups

The installer automatically backs up your existing configuration before making changes:

```
~/.ez-omo-backup/
├── 2024-01-15_143022/     # Timestamped backup directory
│   ├── opencode.json
│   ├── oh-my-openagent.json
│   └── plugins/
├── 2024-01-14_090511/
│   └── ...
```

### Manual Restore

To restore a previous configuration:

```bash
# List available backups
ls -la ~/.ez-omo-backup/

# Restore a specific backup
cp -r ~/.ez-omo-backup/2024-01-15_143022/* ~/.config/opencode/

# Or restore just the configs
cp ~/.ez-omo-backup/2024-01-15_143022/opencode.json ~/.config/opencode/
cp ~/.ez-omo-backup/2024-01-15_143022/oh-my-openagent.json ~/.config/opencode/
```

Backups are retained indefinitely. Clean up old backups periodically:
```bash
rm -rf ~/.ez-omo-backup/2024-01-*
```

---

## Detailed Documentation

For in-depth guides on specific components:

| Topic | Location |
|-------|----------|
| Configuration | [docs/configs.md](docs/configs.md) |
| Plugin Development | [docs/plugins.md](docs/plugins.md) |
| Skill Authoring | [docs/skills.md](docs/skills.md) |
| Wisdom System | [docs/wisdom.md](docs/wisdom.md) |
| Vera Integration | [docs/vera-implementation-plan.md](docs/vera-implementation-plan.md) |
| Compatibility Debt | [docs/COMPATIBILITY-DEBT.md](docs/COMPATIBILITY-DEBT.md) |
| Observability Contract | [docs/configs.md](docs/configs.md) |
| Live Deployment Verification | [docs/live-deployment-verification.md](docs/live-deployment-verification.md) |
| DCP Byte-Budget Gate (RETIRED) | [docs/dcp-byte-budget.md](docs/dcp-byte-budget.md) |

---

## License

MIT License - see [LICENSE](LICENSE) for details.

---

## Disclaimer

This is a personal configuration repository. Your mileage may vary. These settings reflect specific preferences and workflows that may not suit everyone. Feel free to fork, modify, and adapt to your own needs.

- Models and providers are subject to availability and rate limits
- Experimental features may change behavior between updates
- Always review changes before applying to your system
- API costs apply based on your provider usage

---

<p align="center">Made with OpenCode + Oh-My-OpenAgent</p>
