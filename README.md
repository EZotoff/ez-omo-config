# ez-omo-config

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Sponsor](https://img.shields.io/badge/sponsor-%E2%9D%A4-lightgrey)](https://github.com/sponsors/EZotoff)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support-ff5e5b?logo=ko-fi&logoColor=white)](https://ko-fi.com/ezotoff)

> Production-ready OpenCode + Oh-My-OpenAgent configuration. 8 remote AI providers + 1 locally-hosted FLARE model, 13 specialized agents, git safety & worktree plugins, one-command install with automatic backups.

Clone, run `./install.sh`, and get a fully configured AI coding environment in seconds. This repo contains reusable presets, plugins, skills, and scripts organized into a portable configuration you can fork and adapt.

---

## Quick Start

Get up and running in six steps:

```bash
# 1. Install prerequisites
#    OpenCode CLI:  https://opencode.ai
#    bun:           https://bun.sh
#    Docker (optional, for worktree isolation): https://docker.com
#    macOS:         brew install bash bun jq python
#    Windows:       run inside WSL (Ubuntu) — see Platform Support below

# 2. Clone the repository
git clone https://github.com/EZotoff/ez-omo-config.git
cd ez-omo-config

# 3. Run the installer (dry-run first to preview changes)
./install.sh --dry-run

# 4. Install for real
./install.sh

# 5. Set up API keys
cp auth.json.example ~/.local/share/opencode/auth.json
#    Edit the file and replace YOUR_*_API_KEY placeholders.
#    OAuth providers (openai, kimi-for-coding-oauth) auto-populate via:
#      opencode auth login openai
#      opencode auth login kimi-for-coding-oauth

# 6. Verify prerequisites and start
./scripts/check-prerequisites.sh
opencode
```

The installer uses relative paths in `opencode.json` — no manual path
updates are needed on a new machine. Config files are symlinked from
`~/.config/opencode/` into this repo, so editing either path updates the
same file.

---

## What Changes After Installing

After running `./install.sh`, your OpenCode CLI gains:

- **`/models-preset`** — view all 13 agent model assignments, category presets, compaction model, and small model at a glance
- **`/session-id`** — copy the invoking session ID to clipboard; true no-LLM cancellation depends on the active local `opencode--command-hook-cancellation` patch
- **`/session-info`** — copy project path, session title, and invoking session ID to clipboard; true no-LLM cancellation depends on the active local `opencode--command-hook-cancellation` patch
- **Git safety guardrails** — three-layer protection: always-block non-git destructive ops (`rm -rf`, `chmod -R 777`, `dd of=/dev/`), **history-rewrite block** (`git commit --amend`, `git rebase`, `git push --force*`, `git branch -D`, `git stash clear`, `git reflog expire`, `git gc --prune`, and `git reset <ref>` where ref is a strict ancestor of HEAD — catches the post-commit destructive case), and dirty-tree-conditional git ops (`git reset --hard`, `git clean -f`, etc.). Worktree-aware: status checks use the bash command's actual cwd.
- **Worktree-aware development** — parallel worktrees with port allocation and Docker isolation
- **Semantic session-scoped checkpoints** — automatic git checkpoint commits scoped to root session trees, with LLM-powered file selection and temp-index safety
- **Runtime fallback** — automatic model switching across 9 providers when APIs fail or rate-limit
- **Wisdom system** — learning management that captures and reuses development knowledge
- **Review enforcement** — automated code review triggers after completing implementation work, with regression corpus output included in review and plan-completion instructions
- **Clickable file links (TUI)** — every agent formats file references as `[label](file:///abs/path)` markdown links so they are clickable in OSC 8 terminals (Ghostty, Kitty, WezTerm, Alacritty, iTerm2); closes the gap between the built-in prompts' "backtick paths are clickable" claim and the OpenTUI renderer, which only linkifies real markdown links
- **Agent git workflow** — every agent follows the same parallel-agent coordination procedure: commit at logical-unit boundaries with Conventional Commits (no author override — attribution deferred to git_master config); branch as `agent/<name>/<scope>` when concurrent agent work is detected; sync/rebase on stale branches; merge-back-and-delete when the unit is done. Complements the commit-policy patches (permission) and auto-checkpoint plugin (idle safety-net commits)
- **Aspect Dynamics** — deterministic heuristic scoring that detects emotional and behavioral patterns in conversation transcripts and dispatches transcript-visible advisory nudges to guide agent tone and focus
- **Output Shaper** — reduces model output tokens via terseness injection and reasoning-effort dialing on resume turns
- **OpenCode/OMO context management** — OpenCode compaction and OMO preemptive compaction/context-window hooks are enabled; Magic Context is retained only as a disabled config file.
- **Safe update pipeline** — guided OpenCode/OMO update analysis with explicit human approval gate, patch-tracker integration, rollback capability, adaptive regression testing, and evidence-state claim discipline
- **Global deployment-skill mandate** — every session loads `~/.config/opencode/AGENTS.md`, which requires invoking the `/deployment` skill before binding ports or launching dev/test servers. Eliminates cross-project port conflicts
- **Patch-preservation safety infrastructure** — regression corpus, rewritten verifier, inotify watcher, and periodic integrity check protect against patch drift during updates

---

## What's Included

This repository contains a portable OpenCode/OMO configuration bundle organized into 9 categories:

| # | Category | Artifacts | Description |
|---|----------|-----------|-------------|
| 1 | **Commands** | 4 files | Slash commands for OpenCode workflows |
| 2-5 | **Configs** | 29 files | Core OpenCode and OMO configuration files, including the Aspect Dynamics plugin, its support modules, two seed aspect sets, the Output Shaper plugin with its support modules, and the Skill Nudger plugin with its support modules |
| 6-11 | **Plugins** | TypeScript files + kdco-primitives dir | TypeScript plugins for worktrees, git safety, review enforcement, VS Code launcher, session clipboard commands, semantic checkpointing, and TUI clickable-link system-prompt injection |
| 12-22 | **Skills** | Skill directories | Specialized agent skills for retry-error registration, patch tracking, deployment, parallel development, safe update pipelines, and review workflows. (`playwright`, `frontend-ui-ux`, and `github-triage` ship with [OMO upstream](https://github.com/code-yeongyu/oh-my-openagent) and are not vendored here.) |
| 22-31 | **Scripts** | Shell scripts | Wisdom propagation, observability, worktree lifecycle, live deployment verification, patch verification, and runtime watching |
| 31a | **Systemd** | 3 user units | Reactive inotify watcher plus a periodic patch-integrity service and timer |
| 32 | **Tests** | Test scripts | Regression tests for config, plugins, updates, and the 9-pair patch-preservation corpus |
| 33 | **Extras** | 1 file | Additional registry configuration |
| 34-35 | **Docker** | 2 files | Worktree container templates |
| 36-39 | **Docs** | 6 files | Configuration, plugin, skills, worktree state, live deployment verification, compatibility debt, and retired DCP byte-budget reference |

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
| 4 | `provider-connect-retry.mjs` | `configs/opencode/` | Auto-retry logic for provider connections with empty-response detection (finish `other` AND `stop` with zero tokens), escalating nudge prompts, per-message model fallback, and registry-driven error matching |
| 4b | `retry-errors.json` | `configs/` | Retry registry: error patterns, backoff schedules, 5-stage escalating nudge prompts (sisyphus/atlas/default), per-message fallback models, and empty-response detection rules for GLM |
| 5 | `oh-my-openagent.json` | `configs/oh-my-openagent/` | Agent model assignments and experimental features |
| 6 | `worktree.ts` | `plugins/` | Git worktree management plugin |
| 7 | `worktree/state.ts` | `plugins/worktree/` | Worktree state management |
| 8 | `worktree/terminal.ts` | `plugins/worktree/` | Terminal integration for worktrees |
| 9 | `git-safety.ts` | `plugins/` | Git safety protocol enforcement |
| 10 | `review-enforcer.ts` | `plugins/` | Automated code review triggers |
| 11 | `kdco-primitives/` | `plugins/` | Shared library for plugins |
| 11b | `vscode.ts` | `plugins/` | VS Code launcher plugin (intercepts /vscode and sets `output.cancelled = true`; true no-LLM behavior depends on the local OpenCode cancellation patch) |
| 11c | `session-id.ts` | `plugins/` | Session ID clipboard plugin (intercepts /session-id and sets `output.cancelled = true`; true no-LLM behavior depends on the local OpenCode cancellation patch) |
| 11d | `session-info.ts` | `plugins/` | Session info clipboard plugin (intercepts /session-info and sets `output.cancelled = true`; true no-LLM behavior depends on the local OpenCode cancellation patch) |
| 11f | `auto-checkpoint.ts` | `plugins/` | Semantic session-scoped checkpoint plugin |
| 11h | `clickable-links.ts` | `plugins/` | System-prompt injection via `experimental.chat.system.transform` — tells every agent to format file references as `[label](file:///abs/path)` markdown links so they are clickable in the TUI |
| 11i | `agent-git-workflow.ts` | `plugins/` | Force-loads a parallel-agent git coordination procedure into every session via `experimental.chat.system.transform`: commit reflex after logical units, Conventional Commits format without author override (attribution deferred to git_master), branching reflex when concurrent agent work detected, sync/rebase protocol, branch lifecycle. Complements auto-checkpoint (idle safety-net) and commit-policy patches (permission) |
| 12 | `wisdom/` | `skills/` | Wisdom propagation and knowledge management (primary runtime memory skill) |
| 12b | `patch-tracker/` | `skills/` | Patch registry CRUD and post-update verification skill |
| 12c | `register-retry-error/` | `skills/` | Retryable error pattern registration skill |
| 12d | `session-id/` | `skills/` | Session ID clipboard (skill form, mirrors the `/session-id` plugin) |
| 12e | `debate/` | `skills/` | Structured adversarial analysis: quick modes (challenge, panel, pre-mortem, red team) plus a decision-review protocol with binding/advisory judges producing ADOPT/REVISE/REJECT/ESCALATE verdicts |
| 12f | `reader-report/` | `skills/` | Reader-first writing for reports/summaries/briefs: reader contract, no AI-speak, HTML styling guide, lint+independent-review enforcement. Loaded by `/debate` at result-synthesis points |
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
| 30b | `update-to-latest/` | `skills/` | Safe OpenCode/OMO update pipeline with explicit approval gate, patch-tracker integration, rollback capability, and evidence-state reporting |
| 30c | `patch-opencode/` | `skills/` | Minimal-fix procedure for patching the live OpenCode binary from the exact release tag |
| 31 | `worktree-post-create.sh` | `scripts/` | State creation, port allocation, and Docker start. Install: `$HOME/.opencode/scripts/worktree-post-create.sh` |
| 32 | `worktree-pre-delete.sh` | `scripts/` | Container stop, port free, and state cleanup. Install: `$HOME/.opencode/scripts/worktree-pre-delete.sh` |
| 33 | `worktree.jsonc` | `configs/opencode/` | Worktree sync config and hook registration. Install: `$HOME/.opencode/worktree.jsonc` |
| 34 | `worktree-compose.template.yml` | `docker/` | Per-worktree container isolation template |
| 35 | `docker/README.md` | `docker/` | Docker worktree setup instructions |
| 36 | `worktree-state-schema.md` | `docs/` | Runtime state file formats and locations |
| 38 | `aspect-dynamics.mjs` | `configs/opencode/` | Config-layer plugin entry: heuristic scoring and advisory nudge dispatch |
| 39 | `aspect-dynamics/config.mjs` | `configs/opencode/` | Config loader with deferred-field safeguards |
| 40 | `aspect-dynamics/context.mjs` | `configs/opencode/` | Conversation context extraction and recursion guard |
| 41 | `aspect-dynamics/heuristics.mjs` | `configs/opencode/` | Deterministic heuristic scorer for aspect sets |
| 42 | `aspect-dynamics/session-state.mjs` | `configs/opencode/` | Per-session state tracking, deduplication, and circuit breaker |
| 43 | `aspect-dynamics/sets.mjs` | `configs/opencode/` | Aspect set loader and resolver |
| 44 | `aspect-dynamics/nudge.mjs` | `configs/opencode/` | Transcript-visible advisory nudge formatter |
| 45 | `aspect-dynamics/logging.mjs` | `configs/opencode/` | Structured logging utilities |
| 46 | `aspect-dynamics/sets/emotions-v1.json` | `configs/opencode/` | Seed aspect set for emotional tone detection |
| 46a | `output-shaper.mjs` | `configs/opencode/` | Config-layer plugin entry: terseness injection + reasoning-effort dialing for resume turns |
| 46b | `output-shaper/config.mjs` | `configs/opencode/` | Config loader with test override |
| 46c | `output-shaper/logging.mjs` | `configs/opencode/` | File-based structured logging |
| 46d | `output-shaper/model-gating.mjs` | `configs/opencode/` | Per-provider clamp field table and model gating |
| 46e | `output-shaper/resume-detector.mjs` | `configs/opencode/` | Resume-after-tool-result detection |
| 46f | `skill-nudger.mjs` | `configs/opencode/` | Config-layer plugin entry: tool-signal detection and ephemeral skill-suggestion nudge dispatch via `experimental.chat.messages.transform` |
| 46g | `skill-nudger/*.mjs` | `configs/opencode/` | 6 support modules: config, logging, catalog, signals, state, nudge |
| 47a | `tests/skill-nudger/harness.mjs` | `tests/skill-nudger/` | Test harness for skill-nudger unit tests (12 cases incl. guardrails and no-false-positives) |
| 48a | `tests/test_skill_nudger_runtime.sh` | `tests/` | Regression wrapper for skill-nudger runtime verification (auto-discovered by `run_all.sh`) |
| 47 | `tests/aspect-dynamics/harness.mjs` | `tests/aspect-dynamics/` | Test harness for aspect-dynamics unit tests |
| 48 | `tests/test_aspect_dynamics_runtime.sh` | `tests/` | Regression wrapper for aspect-dynamics runtime verification |
| 49 | `scripts/verify-live-deployment.sh` | `scripts/` | Live deployment verifier with evidence-state validation |
| 50 | `tests/test_live_deployment_contract.sh` | `tests/` | Repo-safe contract tests for live deployment verification |
| 50b | `tests/test_review_enforcer_completion_instruction.sh` | `tests/` | Regression test for PLAN_COMPLETION_INSTRUCTION block extraction and content verification |
| 50c | `tests/test_openai_provider.sh` | `tests/` | Regression test for Codex display provider presence in opencode.json (`openai` key) |
| 51 | `docs/live-deployment-verification.md` | `docs/` | Live Deployment Verification Gate documentation |
| 51a | `aspect-dynamics/sets/emotions-v2.json` | `configs/opencode/` | Versioned distress-focused seed aspect set with profanity-aware heuristics |
| 52 | `docs/dcp-byte-budget.md` | `docs/` | RETIRED 2026-06-23: DCP byte-budget gate reference. Magic Context was tried as the replacement and is currently disabled. Historical record only. |
| 53 | `verify-live-patches.sh` | `scripts/` | Rewritten patch verifier with all 7 structural fixes and runtime-resolved target checks |
| 54 | `watch-runtime-patches.sh` | `scripts/` | inotify watcher for runtime binary integrity |
| 55 | `opencode-patch-watcher.service` | `systemd/user/` | systemd user service for write detection |
| 56 | `opencode-patch-integrity-check.service` | `systemd/user/` | Periodic integrity check service |
| 57 | `opencode-patch-integrity-check.timer` | `systemd/user/` | 30-minute periodic timer |
| 58 | `run_regressions.sh` | `tests/` | Regression corpus harness |
| 59 | `regressions/` | `tests/` | 9 paired regression tests, 18 files total |
| 60 | `test_patch_entries.sh` | `tests/` | Schema validation for all active patch-tracker entries (frontmatter completeness: surfaces, runtime_effective, target_file). Catches metadata destruction at commit time |
| 61 | `test_patch_versions.sh` | `tests/` | Drift gate: fails on unresolved VERSION-DRIFT after binary upgrades. Forces patch reconciliation as part of the same commit/PR as the cutover |
| 62 | `flare-serve.service` | `systemd/user/` | FLARE-4B local SGLang server for `small_model` / session-title generation (port 18200; requires `~/src/flare` repo + `~/flare-cache`; GPU required; mem-fraction 0.84 to coexist with desktop + ComfyUI) |
| 63 | `derive-flare-chat-template.py` | `scripts/` | Derives the SGLang chat template for FLARE-4B: forces no-think decoding and merges consecutive leading system messages (OpenCode always sends two system messages; stock template rejects with 400) |

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
- **Skills**: Specialized agent capabilities for browser testing, deployment, UI/UX design, updates, and review workflows
- **Scripts**: Shell utilities for the wisdom propagation system, worktree lifecycle, and live deployment verification
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

### Platform Support

| Platform | Support | Prerequisites | Install |
|----------|---------|---------------|---------|
| **Linux** | Native | — | `./install.sh` |
| **macOS** | Native | `brew install bash bun jq python` (bash 4.3+ required; stock `/bin/bash` is 3.2) | `./install.sh` |
| **Windows** | Via WSL | Run inside WSL (Ubuntu). See [WSL install guide](https://learn.microsoft.com/en-us/windows/wsl/install). Git Bash, Cygwin, and native PowerShell are NOT supported. | inside WSL: `./install.sh` |

---

## Configuration Highlights

### 8 Remote Providers + 1 Local (FLARE)

| Provider | Description | Key Models |
|----------|-------------|------------|
| **Google** | Gemini and Antigravity-hosted models | Gemini 3.6 Flash, Gemini 3.1 Pro Preview, Antigravity Gemini 3.5 Flash, Claude Sonnet/Opus Thinking |
| **Codex** | GPT models via Codex OAuth (`openai` provider key); picker restricted to the configured whitelist | GPT 5.6 Sol, GPT 5.6 Terra, GPT 5.6 Luna |
| **OpenCode Go** | Built-in OpenCode Go provider | Minimax M3, Kimi K2.6, DeepSeek V4 Flash |
| **Kimi For Coding (OAuth)** | Kimi K3 via device-flow OAuth (Allegretto+ tier) | Kimi K3 (`kimi-for-coding` model id; opencode-kimi-full plugin gates all body-shaping hooks on this exact id; supports off/auto/low/medium/high reasoning_effort; context length discovered at runtime via `/coding/v1/models`) |
| **Z.AI Coding Plan** | GLM models via Coding Plan OpenAI-compatible API | GLM 5.3 |
| **DeepSeek** | DeepSeek V4 | DeepSeek V4 Flash, DeepSeek V4 Pro |
| **Inception Labs** | Mercury models | Mercury 2 |
| **Uni.lu LiteLLM** | Local University of Luxembourg LiteLLM proxy on DGX Spark | DeepSeek V4 Flash (vLLM), Kimi K3, GLM 5.2 |
| **FLARE Local** | Self-hosted FLARE-4B diffusion LLM on the local GPU (RTX 4090 Laptop, SGLang `self-spec` AR-Trust mode, systemd unit `flare-serve.service`, port 18200); serves `small_model` and session-title generation; no API key needed (dummy key inline); non-commercial license, personal use | FLARE-4B |

### 13 Agent Model Assignments

| Agent | Primary Model | Variant | Fallback Model | Purpose |
|-------|---------------|---------|----------------|---------|
| **atlas** | `zai-coding-plan/glm-5.3` | default | `openai/gpt-5.6-sol`, `kimi-for-coding-oauth/kimi-for-coding` | Orchestrator with wisdom injection |
| **prometheus** | `kimi-for-coding-oauth/kimi-for-coding` | high | `zai-coding-plan/glm-5.3`, `openai/gpt-5.6-sol` | Planner, deep reasoning, HTML proposal packets before executable plans |
| **sisyphus** | `zai-coding-plan/glm-5.3` | high | `openai/gpt-5.6-sol` | Executor, focused tasks |
| **sisyphus-junior** | `zai-coding-plan/glm-5.3` | default | `openai/gpt-5.6-sol` | Category task executor |
| **librarian** | `opencode-go/minimax-m3` | default | `openai/gpt-5.6-terra`, `zai-coding-plan/glm-5.3` | Search, documentation |
| **explore** | `opencode-go/minimax-m3` | default | `openai/gpt-5.6-luna`, `zai-coding-plan/glm-5.3` | Discovery, exploration |
| **frontend-ui-ux-engineer** | `zai-coding-plan/glm-5.3` | max | `openai/gpt-5.6-sol` | Complex frontend work |
| **document-writer** | `openai/gpt-5.6-sol` | default | `zai-coding-plan/glm-5.3` | Writing, documentation |
| **multimodal-looker** | `openai/gpt-5.6-terra` | default | (none) | Image/PDF analysis |
| **oracle** | `openai/gpt-5.6-sol` | high | `kimi-for-coding-oauth/kimi-for-coding`, `zai-coding-plan/glm-5.3`, `google/gemini-3.1-pro-preview` | Q&A, knowledge queries |
| **metis** | `zai-coding-plan/glm-5.3` | max | `google/gemini-3.1-pro-preview` | Deep analysis |
| **momus** | `openai/gpt-5.6-sol` | xhigh | `google/gemini-3.1-pro-preview` | Code review, critique |
| **hephaestus** | `openai/gpt-5.6-sol` | xhigh | (none) | Infrastructure, deployment |

#### Prometheus planning artifact flow

For complex multi-step work, Prometheus produces an HTML Proposal+Design Packet before generating the executable Markdown plan. The flow is:

```
User request → Prometheus HTML Proposal+Design Packet → pre-plan checkpoint → .omo/plans/*.md → Atlas/Sisyphus execution
```

The HTML packet is for human review and discussion. The Markdown plan remains canonical for execution. Simple or single-step work stays lean and autonomous and does not require reusable HTML template or generator infrastructure.

### Key Experimental Features

| Feature | Status | Description |
|---------|--------|-------------|
| **Magic Context** | Disabled | Plugin removed from `opencode.json#plugin`; `magic-context.jsonc#enabled=false` is retained for rollback/reference only. |
| **OpenCode Compaction** | Enabled | `opencode.json#compaction.auto=true` and `compaction.prune=true`; OpenCode owns built-in context compaction/pruning. |
| **OMO Context Hooks** | Enabled | `preemptive-compaction`, `context-window-monitor`, and `anthropic-context-window-limit-recovery` are no longer listed in `disabled_hooks`; `experimental.preemptive_compaction=true`. |
| **Aggressive Truncation** | Enabled | Truncates verbose tool outputs aggressively |
| **Runtime Fallback** | Enabled | OMO `runtime_fallback.enabled=true` — session.status path dispatches fallback models on API errors (404, 429, 500, 502, 503, 504). Works for both synchronous and background sub-agents. `retries_before_fallback=2` (fork patch `omo--retries-before-fallback`): provider auto-retry signals for attempts 1–2 are left to OpenCode's native same-model retry; the first signal with attempt 3 aborts the retry loop and fails over to the agent's fallback chain. |
| **Turn Protection** | Enabled | Protects critical tools (task, todowrite, lsp_rename) for 3 turns after use |
| **Purge Errors (2-turn)** | Enabled | OMO `dynamic_context_pruning.strategies.purge_errors` is enabled with a 2-turn retention window. |
| **Background Task Circuit Breaker** | Enabled (maxToolCalls=500, consecutiveThreshold=15) | Configured to cancel runaway subagent tasks when a task reaches 500 total tool calls or 15 consecutive identical tool+input signatures. OMO default is 4000/20; lowered thresholds trip earlier |
| **Auto-Update Checker** | Disabled | `oh-my-openagent.json#disabled_hooks: ["auto-update-checker"]` opts out of OMO's startup update-check hook. Updates are managed manually via the `update-to-latest` skill |

### Doom-Loop Mitigations

The configuration includes layered defenses against runaway subagent sessions (forensic root cause: 14 Jun 2025 visual-engineering QA loop burned $43.58 / 14.3M input tokens in 77 minutes; 21 Jun build/test ping-pong burned $12.75 / 50M cache-read tokens in 27 minutes):

| Layer | Setting | Effect |
|-------|---------|--------|
| **Model demotion** | `oh-my-openagent.json#categories.visual-engineering.model` = `google/gemini-3.6-flash` | Per-token cost ~10× lower than Pro Preview; 1M context preserved |
| **Aggressive error purge** | Enabled via OMO dynamic context pruning | Drops failed build/test outputs after 2 turns using OMO's context-pruning strategy. |
| **Tool-call circuit breaker** | `oh-my-openagent.json#background_task.circuitBreaker.{maxToolCalls: 500, consecutiveThreshold: 15}` | Configured to cancel any subagent task that reaches 500 total tool calls or repeats the same tool+input 15× in a row. Catches 14 Jun-class stuck-repeat loops only; alternation patterns (e.g. 21 Jun's `npm run build` ↔ `npm run test`) reset the consecutive counter each call and are NOT cancelled by this setting. |

**Known limitation**: `consecutiveThreshold` only catches *strictly* consecutive identical signatures. Alternating tool patterns (`build → test → build → test`) and same-tool varying-input patterns (screenshot-with-varying-URL) reset the counter each call and defeat the detector. The `maxToolCalls` cap is the only hard backstop for those patterns, and it triggers on total volume rather than loop shape. Shape-based alternation detection is planned as a sliding-window extension to OMO's circuit breaker (where task cancellation actually works), not as an OpenCode plugin.

**Evidence state**: The OMO/config-setting mitigations are `repo_implemented`, `live_file_installed` (via symlink), and `active_config_registered`.

### Removed: Subagent Loop Guard Plugin (2026-07-25)

The `subagent-loop-guard.ts` plugin was removed. Post-incident analysis showed its sliding-window rules (same-tool frequency, same-tool varying-input) matched legitimate tool-dense investigation work far more often than real doom loops, its only enforcement action was mutating bash calls into no-op echoes (agents simply routed around it by switching tools), and it hooked every session including root orchestrators despite being named for subagents. OMO's `consecutiveThreshold` already covers strict-repeat loops with real task cancellation. The one genuine gap it leaves — alternation/varying-input shape detection — is planned as an extension to OMO's own circuit breaker in `manager.ts`, scoped to background subagent tasks, where cancellation authority exists.

### Future Work: Periodic Lead-Agent Inspection

The mitigations above are reactive (detect-and-block). A complementary proactive mechanism would let the lead agent periodically inspect running subagents without breaking their flow. Sketch of options:

| Option | Mechanism | Breaks Flow? | Complexity |
|--------|-----------|--------------|------------|
| **Push (transcript inject)** | Plugin uses `client.session.promptAsync(parentID, status)` every 15 min | Yes — parent processes injection as new user turn | Medium |
| **Pull (sidecar log)** | Plugin writes status snapshots to `~/.sisyphus/agent-watch/<child>.json`; parent reads when curious | No (passive) | Low |
| **Pull (transcript annotation)** | Plugin annotates the parent's next tool call args with a status comment | No (in-band) | Medium |
| **Upstream OMO patch** | Fix `lastMessageAt` assignment in `manager.ts` so the existing babysitter hook fires | No (handled by OMO) | High (requires OMO source patch + maintenance) |

Out of current scope. Will revisit after observing how the circuit breaker performs in real visual-engineering subagent runs.

### Context Management

Magic Context (`@cortexkit/opencode-magic-context@latest`) is disabled. It is no longer registered in `opencode.json#plugin`, and `magic-context.jsonc#enabled` is `false` for rollback/reference only.

OpenCode and OMO now own context management:

- `opencode.json#compaction.auto=true` — OpenCode automatic compaction is enabled.
- `opencode.json#compaction.prune=true` — OpenCode compaction pruning is enabled.
- `oh-my-openagent.json#experimental.preemptive_compaction=false` — OMO preemptive compaction is disabled (was triggering premature compaction on GLM 5.2/GPT 5.5 with 1M context windows).
- `oh-my-openagent.json#disabled_hooks` only disables `auto-update-checker`; context hooks are active.
- `oh-my-openagent.json#experimental.dynamic_context_pruning.enabled=true` — OMO dynamic context pruning is enabled, including 2-turn error purging, write-supersession deduplication, and `background_output` protection from dedup truncation.

Historical context:

- DCP (`@tarquinen/opencode-dcp@3.1.13`) remains retired; `dcp.jsonc` is archived to `dcp.jsonc.retired`.
- The 3 DCP patches remain retired: bounded-range-archive-mode, byte-budget, compress-tool-prompt-contract.

### Patch Documentation

For install locations, failure string meanings, and reapply instructions:
- **Context overflow max-token detection**: `.sisyphus/patches/oh-my-openagent--context-overflow-max-token-error.md` (active on OMO v4.19.2)
- **Clean agent display names**: `.sisyphus/patches/omo--clean-agent-display-names.md` (active on OMO v4.19.2)
- **Commit policy alignment**: `.sisyphus/patches/omo--commit-policy-alignment.md` (active on OMO v4.19.2)
- **OpenCode command hook cancellation**: `.sisyphus/patches/opencode--command-hook-cancellation.md` (active on v1.18.5 binary, `runtime_effective: true` — enables no-LLM cancellation for `/session-id`, `/vscode`, `/session-info` via `output.cancelled = true` in the command hook)
- **OpenCode SSE directory filter removal**: `.sisyphus/patches/opencode--sse-directory-filter-removal.md` (`runtime_effective: false` on v1.18.5 — NOT deprecated. Investigation found workspaceID is never populated (0/2107 sessions); the SSE ternary always falls back to directory check; original worktree-events problem persists. Patch needs reimplementation for the rewritten event.ts. See patch entry's `## Deprecation Investigation` section)
- **OpenCode TUI link-click workaround (wrapped OSC 8)**: `.sisyphus/patches/opencode--link-click-wrapped-osc8.md` (active on v1.18.5 binary, `runtime_effective: true` as of 2026-08-03 — redesigned hook via child `CodeRenderable.onChunks` setter recovered the dead `_linkifyMarkdownChunks` path; works around Alacritty commit 275726f regression where wrapped OSC 8 hyperlinks are only clickable on the first visual line)
- **OpenCode TUI pinned-session reset**: `.sisyphus/patches/opencode--tui-pinned-session-race.md` (UNFIXED upstream bug — `runtime_effective: false`; startup read-overwrite race + multi-process file contention on `~/.local/state/opencode/session.json`; pinned sessions revert to older state when multiple TUI processes run simultaneously)
- **Exclude auto-slash commands**: `.sisyphus/patches/omo--exclude-selected-auto-slash-commands.md` (active on OMO v4.19.2)
- **Auto-slash-command duplicate user args**: `.sisyphus/patches/omo--auto-slash-command-duplicate-user-args.md` (active on OMO v4.19.2)
- **GLM preemptive compaction threshold**: `.sisyphus/patches/omo--glm-preemptive-compaction-threshold.md` (**DEPRECATED 2026-08-05** — GLM 5.1's mid-window context degradation does not occur on GLM 5.2 with 1M context; OMO preemptive compaction is disabled anyway due to premature triggering on large-context models)
- **Parent-wake sync mode for TUI render**: `.sisyphus/patches/omo--parent-wake-sync-mode-for-tui-render.md` (ROLLED BACK — ineffective; root cause is upstream OpenCode TUI SSE bug, not OMO dispatch mode)
- **Parent-wake live-route rollback**: `oh-my-openagent.json#experimental.disable_live_parent_wake_routing=true` keeps parent wakes on the in-process dispatch path because externally routed parent-wake turns can be persisted without live-rendering in the current OpenCode TUI.
- **Boulder worktree authoritative state**: `.sisyphus/patches/omo--boulder-worktree-authoritative-state.md` (superseded by upstream v4.12.1 works-map architecture)
- **Remove activity stagnation bypass**: `.sisyphus/patches/omo--remove-activity-stagnation-bypass.md` (upstreamed in OMO commit df7e1ae1)
- **Sync delegate_task result bloat**: `.sisyphus/patches/omo--sync-delegate-task-result-bloat.md` (active — config-level mitigation via prompt_append on atlas/sisyphus agents; durable fix requires OMO code change in `fetchSyncResult`)
- **Durable OMO log path**: `.sisyphus/patches/omo--durable-log-path.md` (active on OMO v4.19.2; `runtime_effective` pending post-restart observation in task 9 — dist-level patch on the Bun-minified bundle, not a source patch)
- **Fallback toast names originating agent/session**: `.sisyphus/patches/omo--fallback-toast-origin.md` (active on OMO v4.19.2; `runtime_effective: false` until a real fallback toast is observed post-restart — dist-level patch, pattern match necessary but not sufficient)
- **Runtime fallback retries before fallback**: `.sisyphus/patches/omo--retries-before-fallback.md` (active on OMO v4.19.2, `runtime_effective: true` since 2026-08-15 — source patch, fork commit 49f6728; budget guard observed live on real provider retry signals, provider recovered within budget and sessions stayed on GLM; adds `runtime_fallback.retries_before_fallback` config knob, default 0 = legacy fail-on-first-signal)

---

## Related Projects

- **[OMO Pulse](https://github.com/EZotoff/omo-pulse)** - Dashboard for monitoring Oh-My-OpenAgent activity and agent performance

---

## Dependencies

Before using this configuration, install the following prerequisites:

| Dependency | Required? | Install |
|------------|-----------|--------|
| **OpenCode CLI** | Required | [opencode.ai](https://opencode.ai) — `curl -fsSL https://opencode.ai/install \| bash` |
| **bun** | Required | [bun.sh](https://bun.sh) — `curl -fsSL https://bun.sh/install \| bash` |
| **jq** | Required by worktree hooks, wisdom scripts | `brew install jq` (macOS) · `sudo apt-get install -y jq` (Linux) |
| **python3** | Auth.json parsing, portable helper fallbacks | `brew install python` (macOS) · `sudo apt-get install -y python3` (Linux) |
| **bash >= 4.3** | Wisdom scripts use `local -n` namerefs | macOS: `brew install bash` (stock is 3.2) · Linux: preinstalled |
| **Oh-My-OpenAgent** | Local patched fork | Loaded from `file:///home/ezotoff/oh-my-openagent-v4.19.2`. The fork is the canonical runtime source while tracked OMO patches remain active. |
| **Docker** | Optional | [docker.com](https://docker.com) — only needed for worktree container isolation |
| **inotify-tools** | Required for patch watcher | `sudo apt install -y inotify-tools` |
| **API keys** | Required | See `auth.json.example` for the 8 enabled remote providers (the 9th, `flare-local`, needs no key). Run `./scripts/check-prerequisites.sh` to verify. |

The installer handles placing configuration files in the correct locations. It does not install OpenCode CLI, bun, Docker, `inotify-tools`, or the local OMO fork. This machine's `opencode.json` references `~/oh-my-openagent-v4.19.2`; new machines must provide an equivalent patched fork or deliberately change the plugin reference through the update-to-latest workflow.

**Binary patches** (optional): Several features (true no-LLM `/session-id`, `/session-info`, `/vscode` cancellation) require patches to the OpenCode binary or OMO npm cache. These are documented in `.sisyphus/patches/` but NOT auto-applied by `install.sh`. Use the `patch-opencode` skill or follow the patch docs manually.

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
