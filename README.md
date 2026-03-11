# ez-omo-config

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Personal OpenCode configuration with Oh-My-OpenCode presets. 26 curated artifacts including configs, plugins, skills, and scripts for enhanced AI-assisted development.

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

This repository contains 26 artifacts organized into 5 categories:

| # | Category | Artifacts | Description |
|---|----------|-----------|-------------|
| 1-4 | **Configs** | 4 files | Core OpenCode and OMO configuration files |
| 5-10 | **Plugins** | 5 files + library | TypeScript plugins for worktrees, git safety, and review enforcement |
| 11-16 | **Skills** | 6 directories | Specialized agent skills for testing, deployment, and UX |
| 17-25 | **Scripts** | 9 shell scripts | Wisdom propagation system scripts |
| 26 | **Extras** | 1 file | Additional registry configuration |

### Complete Artifact Inventory

| # | Artifact | Path | Purpose |
|---|----------|------|---------|
| 1 | `opencode.json` | `configs/opencode/` | Main OpenCode provider and model configuration |
| 2 | `opencode.jsonc` | `configs/opencode/` | User-specific OpenCode settings |
| 3 | `provider-connect-retry.mjs` | `configs/opencode/` | Auto-retry logic for provider connections |
| 4 | `oh-my-opencode.json` | `configs/oh-my-opencode/` | Agent model assignments and experimental features |
| 5 | `worktree.ts` | `plugins/` | Git worktree management plugin |
| 6 | `worktree/state.ts` | `plugins/worktree/` | Worktree state management |
| 7 | `worktree/terminal.ts` | `plugins/worktree/` | Terminal integration for worktrees |
| 8 | `git-safety.ts` | `plugins/` | Git safety protocol enforcement |
| 9 | `review-enforcer.ts` | `plugins/` | Automated code review triggers |
| 10 | `kdco-primitives/` | `plugins/` | Shared library for plugins |
| 11 | `wisdom/` | `skills/` | Wisdom propagation and knowledge management |
| 12 | `atlas-review-handler/` | `skills/` | Review orchestration skill |
| 13 | `review-protocol/` | `skills/` | Code review protocol implementation |
| 14 | `playwright/` | `skills/` | Browser automation testing |
| 15 | `deployment/` | `skills/` | Infrastructure deployment helpers |
| 16 | `frontend-ui-ux/` | `skills/` | Frontend and UX design assistance |
| 17 | `wisdom-common.sh` | `scripts/wisdom/` | Shared wisdom utilities |
| 18 | `wisdom-search.sh` | `scripts/wisdom/` | Search wisdom database |
| 19 | `wisdom-write.sh` | `scripts/wisdom/` | Write new learnings |
| 20 | `wisdom-sync.sh` | `scripts/wisdom/` | Sync wisdom across notepads |
| 21 | `wisdom-archive.sh` | `scripts/wisdom/` | Archive old wisdom entries |
| 22 | `wisdom-delete.sh` | `scripts/wisdom/` | Delete wisdom entries |
| 23 | `wisdom-edit.sh` | `scripts/wisdom/` | Edit existing wisdom |
| 24 | `wisdom-gc.sh` | `scripts/wisdom/` | Garbage collect wisdom |
| 25 | `wisdom-merge.sh` | `scripts/wisdom/` | Merge wisdom databases |
| 26 | `ocx.jsonc` | `extras/` | Additional registry configuration |

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
./install.sh --plugins    # Install only plugins
./install.sh --skills     # Install only skills
./install.sh --scripts    # Install only wisdom scripts
```

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
| **explore** | `github-copilot/grok-code-fast-1` | default | (none) | Discovery, exploration |
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
