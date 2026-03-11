# Configuration Files

The OhMyOpenCode configuration system provides portable, reusable OpenCode settings through a bundle of JSON, JSONC, and JavaScript configuration files.

## Overview

Configuration files control OpenCode behavior, provider settings, plugin loading, model assignments, and permission restrictions. All configs are copied from the local OpenCode installation with personal paths normalized to `$HOME` notation.

---

## opencode.json

**Purpose**: Main OpenCode configuration file. Controls core agent behavior, providers, plugins, and models.

**What it Configures**:

- **Providers**: 7 provider configurations for different AI services
- **Plugins**: 8 plugin registrations and their settings
- **Model Settings**: Default models, limits, timeouts
- **Runtime Defaults**: Agent behavior, output preferences
- **Feature Flags**: Experimental features and toggles

**Key Sections**:

- `providers` — API endpoints and authentication
- `plugins` — Loaded plugins and their configurations
- `models` — Model assignments and parameters
- `limits` — Token limits and rate limiting
- `defaults` — Default behaviors and preferences

**Install Target**: `$HOME/.config/opencode/opencode.json`

**Status**: Required

---

## opencode.jsonc

**Purpose**: Local bash permission restrictions for destructive commands.

**What it Configures**:

- Command allowlists and denylists
- Destructive operation confirmations
- Shell command restrictions
- Safety policy enforcement

**Key Features**:

- Prevents accidental data loss
- Requires confirmation for dangerous operations
- Configurable permission levels
- Per-command granularity

**Install Target**: `$HOME/.opencode/opencode.jsonc`

**Status**: Required

---

## provider-connect-retry.mjs

**Purpose**: Plugin that retries failed provider connections with bounded backoff.

**What it Configures**:

- Connection retry logic
- Exponential backoff parameters
- Maximum retry attempts
- Provider failure handling

**Key Features**:

- Automatic retry on transient failures
- Bounded exponential backoff
- Per-provider retry policies
- Failure logging and reporting

**Install Target**: `$HOME/.config/opencode/provider-connect-retry.mjs`

**Status**: Required

---

## oh-my-opencode.json

**Purpose**: OMO (Oh-My-OpenCode) agent and category overrides.

**What it Configures**:

- Agent category assignments
- Default skill loading
- OMO-specific settings
- Override behaviors for core OpenCode

**Key Features**:

- Custom agent categories
- Skill auto-loading per category
- OMO workflow integrations
- Extension point configurations

**Install Target**: `$HOME/.config/opencode/oh-my-opencode.json`

**Status**: Required

---

## extras/ocx.jsonc

**Purpose**: OCX registry configuration pointer used by the OCX CLI.

**What it Configures**:

- OCX registry endpoints
- Package discovery settings
- CLI integration points

**Install Target**: `$HOME/.opencode/ocx.jsonc`

**Status**: Optional

---

## Configuration Summary

| File | What it Controls | Install Target | Status |
|------|------------------|----------------|--------|
| `opencode.json` | Main config: 7 providers, 8 plugins, models, limits, defaults | `$HOME/.config/opencode/opencode.json` | Required |
| `opencode.jsonc` | Bash permission restrictions for destructive commands | `$HOME/.opencode/opencode.jsonc` | Required |
| `provider-connect-retry.mjs` | Provider connection retry handling with backoff | `$HOME/.config/opencode/provider-connect-retry.mjs` | Required |
| `oh-my-opencode.json` | OMO agent/category overrides and skill loading | `$HOME/.config/opencode/oh-my-opencode.json` | Required |
| `extras/ocx.jsonc` | OCX registry configuration pointer | `$HOME/.opencode/ocx.jsonc` | Optional |

---

## Portability Notes

1. **Normalized Paths**: Hardcoded personal paths replaced with `$HOME` notation
2. **No Secrets**: All configs scanned for API keys, tokens, private keys before packaging
3. **Semantic Preservation**: Configuration values and experimental settings preserved as-is
4. **Cross-Platform**: Compatible with Linux and macOS OpenCode installations

---

## Installation

Use the provided `install.sh` script to install configs:

```bash
# Install all configurations
bash install.sh --configs

# Dry run to preview changes
bash install.sh --configs --dry-run

# Copy instead of symlink
bash install.sh --configs --copy
```

Existing configurations are backed up to `~/.ez-omo-backup/<timestamp>/` before replacement.

---

## See Also

- [Plugins Documentation](plugins.md) — Plugin configuration references
- [Skills Documentation](skills.md) — Skill loading configuration
- [MANIFEST.md](../MANIFEST.md) — Complete artifact inventory
- `configs/opencode/README.md` — Quick reference
- `install.sh` — Installation script with backup and idempotency
