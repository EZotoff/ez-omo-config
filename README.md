# ez-omo-config

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Sponsor](https://img.shields.io/badge/sponsor-%E2%9D%A4-lightgrey)](https://github.com/sponsors/EZotoff)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support-ff5e5b?logo=ko-fi&logoColor=white)](https://ko-fi.com/ezotoff)

> Production-ready OpenCode + Oh-My-OpenAgent configuration. 10 AI providers, 13 specialized agents, semantic code search, git safety & worktree plugins, one-command install with automatic backups.

Clone, run `./install.sh`, and get a fully configured AI coding environment in seconds. This repo contains **66 curated artifacts** — reusable presets, plugins, skills, and scripts — organized into a portable configuration you can fork and adapt.

> **NEW**: [Vera](https://github.com/lemon07r/Vera) semantic code search integration — hybrid BM25+vector retrieval with cross-encoder reranking for 70%+ token reduction during codebase discovery. See [Implementation Plan](docs/vera-implementation-plan.md).

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

- **`/models-preset`** — view all 13 agent model assignments at a glance
- **`/session-id`** — copy the invoking session ID to clipboard (no LLM round-trip)
- **`/session-info`** — copy project path, session title, and invoking session ID to clipboard (no LLM round-trip)
- **Git safety guardrails** — automatic prevention of destructive git operations
- **Worktree-aware development** — parallel worktrees with port allocation and Docker isolation
- **Semantic session-scoped checkpoints** — automatic git checkpoint commits scoped to root session trees, with LLM-powered file selection and temp-index safety
- **Runtime fallback** — automatic model switching across 9 providers when APIs fail or rate-limit
- **Wisdom system** — learning management that captures and reuses development knowledge
- **Review enforcement** — automated code review triggers after completing implementation work
- **Semantic code search** — Vera integration for 70%+ token reduction during codebase discovery (requires separate `vera` install, see [docs/vera-implementation-plan.md](docs/vera-implementation-plan.md))
- **Vera index hygiene** — automatic `.veraignore` management that detects unreadable dirs, heavy generated artifacts, and prevents self-indexing before Vera root-indexes a project
- **Aspect Dynamics** — deterministic heuristic scoring that detects emotional and behavioral patterns in conversation transcripts and dispatches transcript-visible advisory nudges to guide agent tone and focus
- **Bounded DCP retention** — local patch that caps archived summary tokens during DCP range compression, keeping long-running sessions within a fixed token budget
- **DCP byte-budget gate** — local patch that enforces a payload byte cap (1,802,240 bytes safe target) on the message list via `pruneByByteBudget()`, preventing 413 Payload Too Large errors from the model provider
- **Durable DCP patch sync** — installer keeps native runtime, OpenCode package-cache, XDG_CACHE_HOME cache (when set and differing from HOME/.cache), and existing Bun v3 `@tarquinen/opencode-dcp` cache copies aligned with local bounded-retention and byte-budget patch files
- **Safe update pipeline** — guided OpenCode/OMO update analysis with explicit human approval gate, patch-tracker integration, rollback capability, adaptive regression testing, and evidence-state claim discipline

---

## What's Included

This repository contains 66 core artifacts + 1 external integration organized into 9 categories:

| # | Category | Artifacts | Description |
|---|----------|-----------|-------------|
| 1 | **Commands** | 4 files | Slash commands for OpenCode workflows |
| 2-5 | **Configs** | 17 files | Core OpenCode and OMO configuration files, including the Aspect Dynamics plugin, its support modules, and two seed aspect sets |
| 6-11 | **Plugins** | 11 files + kdco-primitives dir | TypeScript plugins for worktrees, git safety, review enforcement, VS Code launcher, session clipboard commands, Vera runtime supervision, and semantic checkpointing |
| 12-22 | **Skills** | 11 directories | Specialized agent skills for testing, deployment, UX, parallel development, Vera hygiene, and safe update pipelines |
| 22-31 | **Scripts** | 24 shell scripts | Wisdom propagation, observability, worktree lifecycle, live deployment verification, and Vera hygiene scripts |
| 32 | **Tests** | 22 test scripts | Regression tests for config, DCP, plugin, and update pipeline verification |
| 33 | **Extras** | 1 file | Additional registry configuration |
| 34-35 | **Docker** | 2 files | Worktree container templates |
| 36-39 | **Docs** | 6 files | Configuration, plugin, skills, worktree state, live deployment verification, compatibility debt, and byte-budget configuration reference |
| 40 | **External** | 1 skill | [Vera](https://github.com/lemon07r/Vera) semantic code search (installed separately) |

### Complete Artifact Inventory

| # | Artifact | Path | Purpose |
|---|----------|------|---------|
| 1 | `models-preset.md` | `commands/` | Slash command for showing current OMO model assignments |
| 1b | `vscode.md` | `commands/` | VS Code launcher command stub (handled by plugin) |
| 1c | `session-id.md` | `commands/` | Session ID clipboard command stub (handled by plugin) |
| 1d | `session-info.md` | `commands/` | Session info clipboard command stub (handled by plugin) |
| 2 | `opencode.json` | `configs/opencode/` | Main OpenCode provider and model configuration |
| 3 | `opencode.jsonc` | `configs/opencode/` | User-specific OpenCode settings |
| 3b | `dcp.jsonc` | `configs/opencode/` | DCP plugin configuration with bounded range archive retention and byte-budget payload cap (local patches) |
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
| 11e | `vera-runtime.ts` | `plugins/` | Vera watcher supervision plugin (automated index lifecycle, fail-open) |
| 11f | `auto-checkpoint.ts` | `plugins/` | Semantic session-scoped checkpoint plugin |
| 12 | `wisdom/` | `skills/` | Wisdom propagation and knowledge management (primary runtime memory skill) |
| 13 | `atlas-review-handler/` | `skills/` | Review orchestration skill |
| 14 | `review-protocol/` | `skills/` | Code review protocol implementation |
| 15 | `playwright/` | `skills/` | Browser automation testing |
| 16 | `deployment/` | `skills/` | Infrastructure deployment helpers |
| 17 | `frontend-ui-ux/` | `skills/` | Frontend and UX design assistance |
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
| 27 | `ocx.jsonc` | `extras/` | Additional registry configuration |
| 28 | `merge-agent/` | `skills/` | Safe branch merging with guardrails |
| 29 | `parallel-dev/` | `skills/` | Multi-agent orchestration with decision framework |
| 30 | `worktree-coordinator/` | `skills/` | Worktree parallel development guide |
| 30a | `vera-hygiene/` | `skills/` | Vera index hygiene skill — `.veraignore` management and pre-indexing cleanup |
| 30b | `update-to-latest/` | `skills/` | Safe OpenCode/OMO update pipeline with explicit approval gate, patch-tracker integration, rollback capability, and evidence-state reporting |
| 31 | `worktree-post-create.sh` | `scripts/worktree/` | State creation, port allocation, Docker start, Vera bootstrap. Install: `$HOME/.opencode/scripts/worktree-post-create.sh` |
| 32 | `worktree-pre-delete.sh` | `scripts/worktree/` | Container stop, port free, state cleanup, Vera watcher cleanup. Install: `$HOME/.opencode/scripts/worktree-pre-delete.sh` |
| 32a | `vera-hygiene.sh` | `scripts/` | Vera hygiene script — detects unreadable dirs, heavy artifacts, and updates `.veraignore`. Install: `$HOME/.sisyphus/scripts/vera-hygiene.sh` |
| 33 | `worktree.jsonc` | `configs/opencode/` | Worktree sync config and hook registration. Install: `$HOME/.opencode/worktree.jsonc` |
| 34 | `worktree-compose.template.yml` | `docker/` | Per-worktree container isolation template |
| 35 | `docker/README.md` | `docker/` | Docker worktree setup instructions |
| 36 | `worktree-state-schema.md` | `docs/` | Runtime state file formats and locations |
| 37 | `vera/` (external) | `~/.config/opencode/skills/vera/` | Semantic code search (install: `vera agent install --client opencode`) |
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
| 51 | `docs/live-deployment-verification.md` | `docs/` | Live Deployment Verification Gate documentation |
| 51a | `aspect-dynamics/sets/emotions-v2.json` | `configs/opencode/` | Versioned distress-focused seed aspect set with profanity-aware heuristics |
| 52 | `docs/dcp-byte-budget.md` | `docs/` | DCP byte-budget gate configuration reference, safety margin derivation, installation, and rollback |

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
| **Google** | Gemini and Antigravity-hosted models | Gemini 3.5 Flash, Gemini 3 Pro, Gemini 3 Flash, Claude Sonnet/Opus Thinking |
| **Codex** | GPT models via Codex OAuth (`openai` provider key) | GPT 5.2, GPT 5.5, GPT 5.4, GPT 5.3 Codex, GPT 5.1 Codex Max |
| **OpenCode Go** | Built-in OpenCode Go provider | Minimax M3, Kimi K2.6, DeepSeek V4 Flash |
| **Moonshot** | Kimi models via OpenAI-compatible API | Kimi K2.5 |
| **Kimi Code** | Kimi coding models via Anthropic-compatible API | Kimi K2.5 (`k2p5`) |
| **Kimi For Coding (OAuth)** | Kimi K2.6 via device-flow OAuth | Kimi K2.6 (`kimi-for-coding`) |
| **Z.AI Coding Plan** | GLM models via Coding Plan OpenAI-compatible API | GLM 5, GLM 5.1 |
| **DeepSeek** | DeepSeek V3.2 | DeepSeek Chat, DeepSeek Reasoner |
| **Inception Labs** | Mercury models | Mercury 2 |

### 13 Agent Model Assignments

| Agent | Primary Model | Variant | Fallback Model | Purpose |
|-------|---------------|---------|----------------|---------|
| **atlas** | `kimi-for-coding-oauth/kimi-for-coding` | default | `openai/gpt-5.4`, `kimi-for-coding-oauth/kimi-for-coding` | Orchestrator with wisdom injection |
| **prometheus** | `openai/gpt-5.5` | high | `zai-coding-plan/glm-5.1` | Planner, deep reasoning, HTML proposal packets before executable plans |
| **sisyphus** | `openai/gpt-5.5` | high | `kimi-for-coding-oauth/kimi-for-coding` | Executor, focused tasks |
| **sisyphus-junior** | `zai-coding-plan/glm-5.1` | default | `openai/gpt-5.4` | Category task executor |
| **librarian** | `opencode-go/minimax-m3` | default | (none) | Search, documentation |
| **explore** | `opencode-go/minimax-m3` | default | `opencode-go/deepseek-v4-flash` | Discovery, exploration |
| **frontend-ui-ux-engineer** | `google/antigravity-gemini-3-pro` | default | `zai-coding-plan/glm-5.1` | Complex frontend work |
| **document-writer** | `kimi-for-coding-oauth/kimi-for-coding` | default | `zai-coding-plan/glm-5.1` | Writing, documentation |
| **multimodal-looker** | `google/gemini-3.5-flash` | default | (none) | Image/PDF analysis |
| **oracle** | `openai/gpt-5.5` | high | `google/antigravity-gemini-3-pro` | Q&A, knowledge queries |
| **metis** | `openai/gpt-5.5` | high | `google/antigravity-gemini-3-pro` | Deep analysis |
| **momus** | `openai/gpt-5.5` | xhigh | `google/antigravity-gemini-3-pro` | Code review, critique |
| **hephaestus** | `openai/gpt-5.3-codex` | xhigh | (none) | Infrastructure, deployment |

#### Prometheus planning artifact flow

For complex multi-step work, Prometheus produces an HTML Proposal+Design Packet before generating the executable Markdown plan. The flow is:

```
User request → Prometheus HTML Proposal+Design Packet → pre-plan checkpoint → .sisyphus/plans/*.md → Atlas/Sisyphus execution
```

The HTML packet is for human review and discussion. The Markdown plan remains canonical for execution. Simple or single-step work stays lean and autonomous and does not require reusable HTML template or generator infrastructure.

### Key Experimental Features

| Feature | Status | Description |
|---------|--------|-------------|
| **DCP** (Dynamic Context Pruning) | Enabled | Intelligently removes irrelevant tool outputs to save tokens |
| **Aggressive Truncation** | Enabled | Truncates verbose tool outputs aggressively |
| **Runtime Fallback** | Enabled | Automatically switches to fallback models on API errors (404, 429, 500, 502, 503, 504) |
| **Turn Protection** | Enabled | Protects critical tools (task, todowrite, lsp_rename) for 3 turns after use |

### DCP Observability

The bounded DCP retention patch is a local modification, not upstream standard behavior. After any OpenCode or DCP package update, verify the patch is still intact:

```bash
bash tests/test_dcp_bounded_range.sh
```

Expected: 0 failed. The proof script checks marker presence across the reference copy, runtime copy, OpenCode package-cache copies, XDG_CACHE_HOME cache copies (when set and differing from HOME/.cache), and existing Bun v3 DCP cache copies; the pass count varies with local cache contents. It also exercises five functional regression cases, including runtime metadata validation of `retentionMode`, `archiveRawMessages`, `maxArchivedSummaryTokens`, `archivedBlockId`, and `truncationOccurred`.

**Fresh-start warning probe**: File-marker checks prove the patch files exist on disk, but they do not prove a running OpenCode process has loaded them. To verify a fresh process does not reject the bounded-retention keys as unknown, also run:

```bash
bash tests/test_dcp_startup_warning.sh
```

Expected: 0 failed. This test starts a short-lived `opencode serve` probe and fails if the startup logs contain `Unknown keys: compress.retentionMode`, `compress.maxArchivedSummaryTokens`, `compress.maxPayloadBytes`, or `DCP: config warning`.

**Stale-process gotcha**: If you see the DCP unknown-key warning in a running OpenCode server or TUI session that was started *before* the latest patch sync, the patched modules may not be loaded in that process. File-marker checks prove patch presence on disk, but long-running processes only load DCP modules at startup. Restart OpenCode to load the patched code.

### DCP Byte-Budget Gate Verification

The byte-budget gate is a local patch that prevents prompt payload from exceeding the 2 MiB protocol limit. After any OpenCode or DCP package update, verify the patch is still intact:

```bash
bash tests/test_dcp_payload_budget.sh --installed
```

Expected: 0 failed. The script checks marker presence across the reference copy, runtime copy, OpenCode package-cache copies, and existing Bun v3 DCP cache copies; the pass count varies with local cache contents. It also exercises 9 functional regression cases covering tool output compaction, repeated scaffold collapse, error loop collapse, todo snapshot preservation, multibyte encoding, threshold behavior, and protected-failover.

Configuration reference, safety margin derivation, and uninstall steps are documented in `docs/dcp-byte-budget.md`.

For full DCP observability — bounded-range and byte-budget together — run both verification scripts:

```bash
bash tests/test_dcp_bounded_range.sh && bash tests/test_dcp_payload_budget.sh --installed && bash tests/test_dcp_startup_warning.sh
```

### Patch Documentation

For install locations, failure string meanings, and reapply instructions:
- **Bounded-range archive mode**: `.sisyphus/patches/opencode-dcp--bounded-range-archive-mode.md`
- **Byte-budget gate**: `.sisyphus/patches/opencode-dcp--byte-budget.md`
- **Compress tool prompt contract**: `.sisyphus/patches/opencode-dcp--compress-tool-prompt-contract.md`
- **Boulder worktree authoritative state**: `.sisyphus/patches/omo--boulder-worktree-authoritative-state.md` (repo_implemented and tests_passed; not verified live)

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
| DCP Byte-Budget Gate | [docs/dcp-byte-budget.md](docs/dcp-byte-budget.md) |

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
