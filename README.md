# ez-omo-config

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Sponsor](https://img.shields.io/badge/sponsor-%E2%9D%A4-lightgrey)](https://github.com/sponsors/EZotoff)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support-ff5e5b?logo=ko-fi&logoColor=white)](https://ko-fi.com/ezotoff)

> Personal, **locally patched** OpenCode + Oh-My-OpenAgent configuration: 11 enabled providers, 13 specialized agents, git-safety and worktree plugins, one-command install with automatic backups.

This is a working production setup you can fork and adapt — not a turnkey universal distribution. Some capabilities depend on local runtime patches (see [The OMO runtime fork](#the-omo-runtime-fork-primary-machine) and [docs/patches.md](docs/patches.md)). The repo contains reusable presets, plugins, skills, and scripts; the full artifact inventory with install targets lives in [MANIFEST.md](MANIFEST.md) (the single source of truth — this README carries only the category summary).

---

## Quick Start

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

Config files are symlinked from `~/.config/opencode/` into this repo, so editing either path updates the same file. All plugin references in `opencode.json` — including the patched OMO fork — are config-relative, so no manual path updates are needed on a new machine that follows the [fork install](#the-omo-runtime-fork) step.

---

## The OMO runtime fork

`opencode.json` loads Oh-My-OpenAgent from a **published fork** — upstream **v4.19.2** plus tracked patches — via a config-relative reference: `"../../oh-my-openagent-v4.19.2"`, resolving to `$HOME/oh-my-openagent-v4.19.2` on any machine. Fork source: [EZotoff/oh-my-openagent](https://github.com/EZotoff/oh-my-openagent), branch `fix/custom-patches-v4.19.2`, tag `v4.19.2-patches.1`. The fork is the canonical runtime source while tracked patches are active (npm `@latest` resolution previously lost patches silently).

- **Install the fork**: `git clone -b v4.19.2-patches.1 https://github.com/EZotoff/oh-my-openagent.git ~/oh-my-openagent-v4.19.2 && cd ~/oh-my-openagent-v4.19.2 && bun install && bun run build`, then reapply the dist-level patches per their registry entries (source patches are already fork commits).
- **Patch inventory**: 23 active patches — a mix of source patches (carried as fork commits), dist-level patches (applied to the built bundle), and config-layer mitigations. Index: [docs/patches.md](docs/patches.md); authoritative entries with reapply instructions: [`.sisyphus/patches/`](.sisyphus/patches/).
- **On another machine**: upstream npm OMO loads fine, but these advertised behaviors degrade without the fork: fallback retry budget (`retries_before_fallback=2`), `look_at` fallback patience, resume-skip task continuation, background-spawn model default, `/start-work` worktree reclaim, clean agent display names.
- **Updates**: the owner's procedure is the `update-to-latest` skill — a documented operational path, not a turnkey bootstrap.

The OpenCode binary itself is also rebuilt from release tags with tracked patches — see [docs/patches.md](docs/patches.md) and the `patch-opencode` / `update-to-latest` skills.

---

## What You Get

- **`/models-preset`** — all 13 agent model assignments, category presets, compaction fallback chain, small model, at a glance
- **`/session-id` / `/session-info` / `/vscode`** — clipboard/launcher commands intercepted with no LLM turn (no-LLM cancellation depends on the active `opencode--command-hook-cancellation` patch)
- **Git safety guardrails** — always-block non-git destructive ops (`rm -rf`, `chmod -R 777`, `dd of=/dev/`), history-rewrite block (`--amend`, `rebase`, `push --force*`, `branch -D`, ancestor `reset`, …), dirty-tree-conditional git ops; worktree-aware via the command's actual cwd
- **Worktree-aware development** — parallel worktrees with port allocation and optional Docker isolation
- **Semantic checkpoints** — automatic git checkpoint commits scoped to root session trees (LLM file selection, temp-index safety)
- **Runtime fallback** — automatic model switching across providers on API errors/rate limits; retry budget and 300s fallback timeout tuned by fork patches
- **Wisdom system** — capture and reuse development knowledge across sessions
- **Review enforcement** — automated code-review trigger after implementation work, gated to implementation dispatches in the active session lineage
- **Clickable file links (TUI)** — every agent emits `[label](file:///abs/path)` links (works around the OpenTUI markdown-only linkification gap)
- **Agent git workflow** — uniform parallel-agent coordination: Conventional-Commit reflex, branch-on-concurrency, worktree merge-back-and-reclaim
- **Aspect Dynamics** — deterministic heuristic scoring of transcript tone/behavior with advisory nudges
- **Output Shaper** — terseness injection + reasoning-effort dialing on resume turns
- **Skill Nudger** — ephemeral skill suggestions when tool signals match the catalog
- **Safe update pipeline** — guided OpenCode/OMO updates with approval gate, patch preservation, rollback, evidence-state discipline
- **Patch-preservation infrastructure** — regression corpus (24 pairs), patch verifier, inotify watcher, 30-min integrity timer, and OnFailure alerting
- **Deployment mandate** — every session loads the global `AGENTS.md`, requiring the `/deployment` skill before binding ports
- **Project Supervisor P0** *(machine-local)* — read-only shadow observer for top-level sessions, hash-chained local ledger

---

## What's Included

| Category | Count | Contents |
|---|---|---|
| **Commands** | 10 files | Slash-command prompts: model presets, session utilities, handoff emit/resume, four review presets (design-review, option-compare, dual-review, escalate) |
| **Configs** | 43 files | OpenCode + OMO + Supervisor configs; retry registry; Aspect Dynamics, Output Shaper, Skill Nudger modules |
| **Plugins** | 24 files | worktree, git-safety, review-enforcer (+helpers), vscode, session-id/info, auto-checkpoint, clickable-links, agent-git-workflow, kdco-primitives |
| **Skills** | 18 dirs | wisdom, debate, reader-report, patch-tracker, update-to-latest, patch-opencode, merge-agent, parallel-dev, deployment, acceptance-boundary skills, … |
| **Scripts** | 39 files | wisdom suite (21), worktree hooks, live-deployment verifier, patch verifier + watcher, smoke-boot gate, operator tools |
| **Supervisor** | 28 files | Bun + strict-TypeScript read-only observer service, status CLI, tests |
| **Systemd** | 7 units | patch watcher, integrity check service + timer, integrity-failure alert, supervisor, interactive attach daemon, parked FLARE-4B server |
| **Tests** | 107 files | config/plugin/update/computer-use contracts + 24-pair regression corpus (48 files) |
| **Docs** | 10 active | see [Documentation](#documentation); dated material in `docs/history/` |
| **Extras / Docker** | 1 + 2 | ocx registry; worktree compose template + guide |

Counts are tracked files per top-level directory (module directories count as one line in prose, files in tables). Per-artifact paths, install targets, and statuses: [MANIFEST.md](MANIFEST.md).

`playwright`, `frontend-ui-ux`, and `github-triage` skills ship with [OMO upstream](https://github.com/code-yeongyu/oh-my-openagent) and are not vendored here.

### Architecture

```
OpenCode CLI  ──┬── Config layer (opencode.json: providers, models, settings)
                ├── Plugin layer (TypeScript: worktree, git-safety, review, …)
                └── OMO layer (oh-my-openagent.json: agents, categories, hooks)
                        ├── Skills (wisdom, debate, update pipeline, …)
                        └── Scripts (wisdom suite, worktree hooks, verifiers)
```

---

## Installation Options

```bash
./install.sh --dry-run    # preview without changes
./install.sh --symlink    # default: symlink live configs into this repo
./install.sh --copy       # copy files instead of symlinking

# Selective install (combine as needed)
./install.sh --configs --plugins   # e.g. preview configs and plugins only
./install.sh --commands --skills --scripts
```

Commands install to `~/.config/opencode/command/` (e.g. `/models-preset`).

### Platform Support

| Platform | Support | Prerequisites |
|----------|---------|---------------|
| **Linux** | Native | — |
| **macOS** | Native | `brew install bash bun jq python` (bash 4.3+; stock `/bin/bash` is 3.2) |
| **Windows** | Via WSL | Run inside WSL (Ubuntu). Git Bash, Cygwin, native PowerShell NOT supported |

---

## Configuration Highlights

### 11 Enabled Providers

8 public cloud, 1 personal endpoint, 2 machine-local (tagged).

| Provider | Models | Notes |
|----------|--------|-------|
| **google** | Gemini 3.8 Flash, Gemini 3.1 Pro Preview, Antigravity-hosted Gemini/Claude | |
| **openai** (Codex OAuth) | GPT 5.6 Sol / Terra / Luna | OAuth: `opencode auth login openai` |
| **opencode-go** | Minimax M3, Kimi K2.6, DeepSeek V4 Flash, Qwen 3.8 Flash | explicit Qwen entry: 1M ctx / 131k out |
| **kimi-for-coding-oauth** | K2.7 Code (256k), K3 (1M) | device-flow OAuth; details in [docs/configs.md](docs/configs.md) |
| **zai-coding-plan** | GLM 5.3 | Coding Plan API |
| **deepseek** | V4.1 Flash (`deepseek-flash`, native vision), V4 Pro | V4.1 replaces the temporary `deepseek-v4-flash` alias (retiring); Pro kept serving after the planned 14 Sep reroute was cancelled |
| **inception** | Mercury 2 | |
| **ollama-cloud** | DeepSeek V4.1 Flash, V4 Pro (pinned tag), MiniMax M3 | ollama.com OpenAI-compatible API; V4 Flash tag removed 12 Sep 2026 as redundant |
| **uni-lux** *(personal endpoint)* | DeepSeek V4 Flash, Kimi K3, GLM 5.2 | university LiteLLM proxy — bring your own endpoint/key |
| **ollama-local** *(machine-local)* | local models | `127.0.0.1:18210` |
| **qwen-tunnel** *(machine-local)* | Qwen | LAN `10.71.71.3:18061` |

`auth.json.example` carries 9 provider entries (7 API keys + 2 OAuth). Model-limit details, reasoning-effort variants, and per-model caveats: [docs/configs.md](docs/configs.md).

### 13 Agent Model Assignments

| Agent | Primary | Variant | Fallbacks |
|-------|---------|---------|-----------|
| atlas | `zai-coding-plan/glm-5.3` | default | gpt-5.6-sol → ollama dsv4-pro → opencode-go dsv4-pro → k3 |
| prometheus | `kimi-for-coding-oauth/k3` | high | glm-5.3 → gpt-5.6-sol → ollama dsv4-pro → opencode-go dsv4-pro |
| sisyphus | `zai-coding-plan/glm-5.3` | high | gpt-5.6-sol → ollama dsv4-pro → opencode-go dsv4-pro |
| sisyphus-junior | `zai-coding-plan/glm-5.3` | default | gpt-5.6-sol → ollama dsv4-pro → opencode-go dsv4-pro |
| librarian | `zai-coding-plan/glm-5.3-flash` | default | glm-5.3 → ollama m3 → opencode-go m3 → gpt-5.6-terra |
| explore | `opencode-go/minimax-m3` | default | ollama m3 → gpt-5.6-luna |
| frontend-ui-ux-engineer | `zai-coding-plan/glm-5.3` | max | gpt-5.6-sol → ollama dsv4-pro → opencode-go dsv4-pro |
| document-writer | `openai/gpt-5.6-terra` | default | glm-5.3 |
| multimodal-looker | `zai-coding-plan/glm-5.3-flash` | default | gpt-5.6-terra → gemini-3.8-flash |
| oracle | `openai/gpt-5.6-sol` | high | ollama dsv4-pro → opencode-go dsv4-pro → k3 → glm-5.3 → gemini-3.1-pro |
| metis | `zai-coding-plan/glm-5.3` | max | gemini-3.1-pro-preview |
| momus | `openai/gpt-5.6-sol` | xhigh | ollama dsv4-pro → opencode-go dsv4-pro → gemini-3.1-pro |
| hephaestus | `openai/gpt-5.6-sol` | xhigh | ollama dsv4-pro → opencode-go dsv4-pro |

For complex multi-step work, prometheus produces an HTML proposal packet for human review before the canonical Markdown plan in `.omo/plans/`. Simple work stays lean and autonomous.

### Key Features

| Feature | Status | Notes |
|---------|--------|-------|
| OpenCode compaction | Enabled | `compaction.auto=true`, `compaction.prune=true` |
| OMO context hooks | Partially | context-window-monitor + anthropic-limit-recovery active; **preemptive compaction disabled** (premature triggering on 1M-context models) |
| Dynamic context pruning | Enabled | 2-turn error purge, write-supersession dedup, `background_output` protection |
| Aggressive truncation | Enabled | verbose tool outputs truncated |
| Runtime fallback | Enabled | on 404/429/5xx; `retries_before_fallback=2`, `timeout_seconds=300` (fork patch); works for sync and background sub-agents |
| Turn protection | Enabled | task/todowrite/lsp_rename protected 3 turns after use |
| Background-task circuit breaker | Enabled | `maxToolCalls=500`, `consecutiveThreshold=15` (OMO default 4000/20) |
| Auto-update checker | Disabled | updates managed manually via `update-to-latest` |
| Magic Context | Disabled | retained config only, for rollback/reference |

### Runaway-subagent defenses

`visual-engineering` demoted to Gemini Flash intro pricing; 2-turn error purge; circuit breaker 500/15. Known limitation: the consecutive-signature detector misses alternating and varying-input loops — `maxToolCalls` is the only hard backstop for those shapes. Incident forensics and the planned shape-based extension: [docs/history/incidents.md](docs/history/incidents.md).

---

## Dependencies

| Dependency | Required? | Install |
|------------|-----------|---------|
| **OpenCode CLI** | Required | [opencode.ai](https://opencode.ai) — `curl -fsSL https://opencode.ai/install \| bash` |
| **Oh-My-OpenAgent** | Required | npm default; primary machine uses the [local fork](#the-omo-runtime-fork-primary-machine) (upstream v4.19.2 + patches) |
| **bun** | Required | [bun.sh](https://bun.sh) |
| **jq** | Required (worktree hooks, wisdom scripts) | `brew install jq` / `sudo apt-get install -y jq` |
| **python3** | Required (auth parsing, helpers) | `brew install python` / `sudo apt-get install -y python3` |
| **bash >= 4.3** | Required (wisdom namerefs) | macOS: `brew install bash`; Linux: preinstalled |
| **inotify-tools** | Required (patch watcher) | `sudo apt install -y inotify-tools` |
| **Docker** | Optional (worktree isolation) | [docker.com](https://docker.com) |
| **API keys** | Required | `auth.json.example` (9 providers); verify with `./scripts/check-prerequisites.sh` |

The installer places configuration files; it does not install OpenCode CLI, bun, Docker, inotify-tools, or OMO. Binary/bundle patches are documented in [docs/patches.md](docs/patches.md) and are **not** auto-applied by `install.sh`.

---

## Backup & Rollback

Before replacing anything, the installer backs up each existing target into a `$HOME`-relative tree:

```
~/.ez-omo-backup/<timestamp>/
├── .config/opencode/…      # backed-up live configs
├── .opencode/…             # plugins, scripts, worktree config
└── .sisyphus/…             # wisdom scripts, patch verifier
```

Restore everything the installer touched:

```bash
cp -R "$HOME/.ez-omo-backup/<timestamp>"/. "$HOME"/
```

Restore a single file (note the `$HOME`-relative subpath):

```bash
cp ~/.ez-omo-backup/<timestamp>/.config/opencode/opencode.json ~/.config/opencode/
```

**Symlink-mode caveat**: restoring copies files *over* the symlinks this repo installed, replacing them with plain copies. Re-run `./install.sh --symlink` afterwards to re-link, or restore selectively inside the repo instead.

Backups are retained indefinitely — clean old ones periodically (`rm -rf ~/.ez-omo-backup/<old-timestamp>`).

---

## Documentation

| Topic | Location |
|-------|----------|
| Artifact inventory (single source of truth) | [MANIFEST.md](MANIFEST.md) |
| Configuration files | [docs/configs.md](docs/configs.md) |
| Plugin system | [docs/plugins.md](docs/plugins.md) |
| Skill system | [docs/skills.md](docs/skills.md) |
| Wisdom system | [docs/wisdom.md](docs/wisdom.md) |
| Patch index | [docs/patches.md](docs/patches.md) |
| Live deployment verification | [docs/live-deployment-verification.md](docs/live-deployment-verification.md) |
| Observability (non-wisdom) | [docs/non-wisdom-observability.md](docs/non-wisdom-observability.md) |
| Compatibility debt | [docs/COMPATIBILITY-DEBT.md](docs/COMPATIBILITY-DEBT.md) |
| Worktree state schema | [docs/worktree-state-schema.md](docs/worktree-state-schema.md) |
| OMO v4.x config reference (vendored) | [docs/omo-config-reference.md](docs/omo-config-reference.md) |

History (dated snapshots): [incidents & experiments](docs/history/incidents.md) · [DCP byte-budget (retired)](docs/history/dcp-byte-budget.md) · [update migration v1.14.28](docs/history/update-migration-v1.14.28.md) · [patch-management architecture review](docs/history/architecture-review-patch-management-2026-06-28.md)

---

## Related Projects

- **[OMO Pulse](https://github.com/EZotoff/omo-pulse)** — dashboard for monitoring Oh-My-OpenAgent activity and agent performance

---

## License

MIT — see [LICENSE](LICENSE).

## Disclaimer

This is a personal configuration repository; settings reflect specific preferences, providers, and patched runtimes. Fork and adapt. Models are subject to availability and rate limits; experimental features may change behavior between updates; API costs apply; review changes before applying them to your system.

---

<p align="center">Made with OpenCode + Oh-My-OpenAgent</p>
