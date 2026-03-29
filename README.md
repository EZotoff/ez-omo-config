# ez-omo-config

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Sponsor](https://img.shields.io/badge/sponsor-%E2%9D%A4-lightgrey)](https://github.com/sponsors/EZotoff)

Personal OpenCode configuration with Oh-My-OpenCode presets. 27 curated artifacts including commands, configs, plugins, skills, and scripts for enhanced AI-assisted development.

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

## What's Included

This repository contains 36 artifacts organized into 8 categories:

| # | Category | Artifacts | Description |
|---|----------|-----------|-------------|
| 1 | **Commands** | 1 file | Slash commands for OpenCode workflows |
| 2-5 | **Configs** | 5 files | Core OpenCode and OMO configuration files |
| 6-11 | **Plugins** | 5 files + library | TypeScript plugins for worktrees, git safety, and review enforcement |
| 12-20 | **Skills** | 9 directories | Specialized agent skills for testing, deployment, UX, and parallel development |
| 21-30 | **Scripts** | 11 shell scripts | Wisdom propagation and worktree lifecycle scripts |
| 31 | **Extras** | 1 file | Additional registry configuration |
| 32-33 | **Docker** | 2 files | Worktree container templates |
| 34-36 | **Docs** | 3 files | Configuration, plugin, and worktree state documentation |

### Complete Artifact Inventory

| # | Artifact | Path | Purpose |
|---|----------|------|---------|
| 1 | `models-preset.md` | `commands/` | Slash command for showing current OMO model assignments |
| 2 | `opencode.json` | `configs/opencode/` | Main OpenCode provider and model configuration |
| 3 | `opencode.jsonc` | `configs/opencode/` | User-specific OpenCode settings |
| 4 | `provider-connect-retry.mjs` | `configs/opencode/` | Auto-retry logic for provider connections |
| 5 | `oh-my-opencode.json` | `configs/oh-my-opencode/` | Agent model assignments and experimental features |
| 6 | `worktree.ts` | `plugins/` | Git worktree management plugin |
| 7 | `worktree/state.ts` | `plugins/worktree/` | Worktree state management |
| 8 | `worktree/terminal.ts` | `plugins/worktree/` | Terminal integration for worktrees |
| 9 | `git-safety.ts` | `plugins/` | Git safety protocol enforcement |
| 10 | `review-enforcer.ts` | `plugins/` | Automated code review triggers |
| 11 | `kdco-primitives/` | `plugins/` | Shared library for plugins |
| 12 | `wisdom/` | `skills/` | Wisdom propagation and knowledge management |
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
| 27 | `ocx.jsonc` | `extras/` | Additional registry configuration |
| 28 | `merge-agent/` | `skills/` | Safe branch merging with guardrails |
| 29 | `parallel-dev/` | `skills/` | Multi-agent orchestration with decision framework |
| 30 | `worktree-coordinator/` | `skills/` | Worktree parallel development guide |
| 31 | `worktree-post-create.sh` | `scripts/worktree/` | State creation, port allocation, Docker start |
| 32 | `worktree-pre-delete.sh` | `scripts/worktree/` | Container stop, port free, state cleanup |
| 33 | `worktree.jsonc` | `configs/opencode/` | Worktree sync config and hook registration |
| 34 | `worktree-compose.template.yml` | `docker/` | Per-worktree container isolation template |
| 35 | `docker/README.md` | `docker/` | Docker worktree setup instructions |
| 36 | `worktree-state-schema.md` | `docs/` | Runtime state file formats and locations |

---

## Architecture Overview

This configuration bridges **OpenCode** (the core CLI) with **Oh-My-OpenCode** (enhancement layer).

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
│   Oh-My-OpenCode Layer        │
│   (oh-my-opencode.json)       │
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
- **Skills**: Specialized agent capabilities for browser testing, deployment, and UI/UX design
- **Scripts**: Shell utilities for the wisdom propagation system (learning management)
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
./install.sh --scripts    # Install only wisdom scripts
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

### 7 Configured Providers

| Provider | Description | Key Models |
|----------|-------------|------------|
| **Google** | Gemini models via Antigravity | Gemini 3 Pro, Gemini 3 Flash |
| **OpenAI** | GPT models via OAuth | GPT 5.4, GPT 5.3 Codex, GPT 5.2 |
| **GitHub Copilot** | Claude and GPT via Copilot | Claude Opus 4.6, Claude Sonnet 4.6, GPT 5.4 |
| **Moonshot** | Kimi models | Kimi K2.5 |
| **Z.AI** | GLM models via Coding Plan | GLM 5 |
| **DeepSeek** | DeepSeek V3.2 | DeepSeek Chat, DeepSeek Reasoner |
| **Inception** | Mercury models | Mercury 2 |

### 12 Agent Model Assignments

| Agent | Primary Model | Variant | Fallback Model | Purpose |
|-------|---------------|---------|----------------|---------|
| **atlas** | `github-copilot/gpt-5.4` | default | `zai-coding-plan/glm-5` | Orchestrator with wisdom injection |
| **prometheus** | `github-copilot/claude-opus-4.6` | default | `zai-coding-plan/glm-5` | Planner, deep reasoning |
| **sisyphus** | `github-copilot/gpt-5.4` | high | `zai-coding-plan/glm-5` | Executor, focused tasks |
| **librarian** | `github-copilot/gemini-3-flash-preview` | high | `google/antigravity-gemini-3-flash` | Search, documentation |
| **explore** | `opencode-go/minimax-m2.7` | default | `github-copilot/grok-code-fast-1` | Discovery, exploration |
| **frontend-ui-ux-engineer** | `github-copilot/gemini-3.1-pro-preview` | default | `zai-coding-plan/glm-5` | Complex frontend work |
| **document-writer** | `moonshot/kimi-k2.5` | default | `zai-coding-plan/glm-5` | Writing, documentation |
| **multimodal-looker** | `moonshot/kimi-k2.5` | default | (none) | Image/PDF analysis |
| **oracle** | `github-copilot/gpt-5.4` | high | `github-copilot/claude-opus-4.6` | Q&A, knowledge queries |
| **metis** | `github-copilot/gpt-5.4` | xhigh | (none) | Deep analysis |
| **momus** | `github-copilot/gpt-5.4` | high | `github-copilot/claude-opus-4.6` | Code review, critique |
| **hephaestus** | `github-copilot/gpt-5.3-codex` | xhigh | (none) | Infrastructure, deployment |

### Key Experimental Features

| Feature | Status | Description |
|---------|--------|-------------|
| **DCP** (Dynamic Context Pruning) | Enabled | Intelligently removes irrelevant tool outputs to save tokens |
| **Aggressive Truncation** | Enabled | Truncates verbose tool outputs aggressively |
| **Runtime Fallback** | Enabled | Automatically switches to fallback models on API errors (404, 429, 500, 502, 503, 504) |
| **Turn Protection** | Enabled | Protects critical tools (task, todowrite, lsp_rename) for 3 turns after use |

---

## Related Projects

- **[OMO Pulse](https://github.com/EZotoff/omo-pulse)** - Dashboard for monitoring Oh-My-OpenCode activity and agent performance

---

## Dependencies

Before using this configuration, ensure you have:

1. **OpenCode CLI** - The core AI coding assistant ([installation guide](https://opencode.ai))
2. **Oh-My-OpenCode** - Enhancement layer for OpenCode

The installer handles placing configuration files in the correct locations. It does not install OpenCode or OMO themselves.

---

## Backup & Rollback

### Automatic Backups

The installer automatically backs up your existing configuration before making changes:

```
~/.ez-omo-backup/
├── 2024-01-15_143022/     # Timestamped backup directory
│   ├── opencode.json
│   ├── oh-my-opencode.json
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
cp ~/.ez-omo-backup/2024-01-15_143022/oh-my-opencode.json ~/.config/opencode/
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

<p align="center">Made with OpenCode + Oh-My-OpenCode</p>
