# Configuration Files

The OhMyOpenCode configuration system provides portable, reusable OpenCode settings through a bundle of JSON, JSONC, and JavaScript configuration files.

## Overview

Configuration files control OpenCode behavior, provider settings, plugin loading, model assignments, and permission restrictions. All configs are copied from the local OpenCode installation with personal paths normalized to `$HOME` notation.

---

## opencode.json

**Purpose**: Main OpenCode configuration file. Controls core agent behavior, providers, plugins, and models.

**What it Configures**:

- **Providers**: 8 provider configurations for different AI services
- **Plugins**: 9 plugin registrations and their settings
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

**Purpose**: First-party JavaScript plugin loaded by `opencode.json` that handles provider connection retries and empty-response recovery.

**What it Configures**:

- Error-triggered retry logic with bounded backoff
- Empty-response detection and nudge-based recovery
- Per-rule retry limits, backoff schedules, and fallback models
- Session-scoped attempt tracking with duplicate suppression

**How it Works**:

The plugin registers an `event` handler that watches three event types:

1. **`session.error`** and **`message.updated` (with error)** — When a provider returns an error, the plugin loads `retry-errors.json` at runtime, matches the error message against compiled regex patterns, and dispatches a retry if a rule matches. It aborts the failed turn, waits for the configured backoff, then re-prompts the session with the last user message (or an agent-specific nudge). Retries are capped by `max_retries` and deduplicated per failed assistant message ID.

2. **`session.idle`** — When a session goes idle, the plugin checks whether the most recent assistant message is empty (no text parts, no tool calls). If the `retry-errors.json` registry contains a rule with `detect_empty_response: true`, the plugin treats the empty response like an error and triggers the same retry / nudge / fallback flow. This catches stalls where the provider returns HTTP 200 with zero content.

**Key Fields**:

- `max_retries` — Hard ceiling on attempts per rule per session
- `backoff_ms` — Array of millisecond delays, indexed by attempt number
- `fallback_model` — `providerID/modelID` string used after retries are exhausted
- `retry_after_tool_execution` — If `false`, skips retry when tool calls were made since the last user message (avoids replaying side effects)
- `nudge_prompts` — Agent-specific escalating prompts; keyed by agent name or `default`
- `detect_empty_response` — Enables idle-time empty-response detection for this rule

**Nudge Prompts**:

When a rule defines `nudge_prompts`, the plugin sends a short agent-specific text prompt instead of replaying the original user message. This breaks the model out of repetitive failure loops. The prompt is chosen by attempt index (capped at the last entry). If no agent-specific key exists, it falls back to `default`.

**Fallback Behavior**:

After exhausting `max_retries`, if `fallback_model` is set, the plugin aborts the session and re-prompts using the fallback provider and model, preserving the original message parts, agent, system prompt, tools, and variant. If no fallback is configured, it logs a warning and stops.

**State Tracking**:

- `attemptsBySession` — Tracks retry count, fingerprint of dispatched parts, original user message ID, and rule ID per session
- `handledErrorsBySession` — Prevents retrying the same failed assistant message or empty response twice
- `inFlightSessions` — Guards against concurrent retries in the same session

**Runtime Loading**:

The plugin reads `~/.config/opencode/retry-errors.json` fresh on every event. Changes to the registry take effect immediately without restarting OpenCode.

**Install Target**: `$HOME/.config/opencode/provider-connect-retry.mjs`

**Status**: Required

---

## retry-errors.json

**Purpose**: Runtime registry of retryable error patterns consumed by `provider-connect-retry.mjs`.

**What it Configures**:

- Regex patterns that identify retryable provider errors
- Backoff schedules and retry limits per error class
- Optional fallback model assignments
- Empty-response detection flags and nudge prompt libraries

**Schema**:

The top-level object contains an `errors` array. Each entry is an object with these fields:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Stable identifier for the rule |
| `pattern` | string | Yes | Regex pattern (case-insensitive match) |
| `match_type` | string | Yes | Always `"regex"` |
| `max_retries` | integer | Yes | Maximum retry attempts |
| `backoff_ms` | integer[] | Yes | Millisecond delays per attempt |
| `retry_after_tool_execution` | boolean | Yes | Whether to retry after tools were invoked |
| `fallback_model` | string | No | `providerID/modelID` to use after exhaustion |
| `detect_empty_response` | boolean | No | Enables idle-time empty-response detection |
| `nudge_prompts` | object | No | Agent-specific prompt arrays (`agentName` or `default`) |
| `description` | string | No | Human-readable explanation |
| `added_by` | string | No | Who created the rule |
| `added_at` | string | No | ISO date of creation |

**Extending the Registry**:

Use the `register-retry-error` skill to add new rules safely. It validates the JSON schema, checks for duplicate IDs, compiles the regex, and appends the entry. Manual edits are also possible because the file is reloaded at runtime, but the skill ensures structural correctness.

**Live Symlink**:

The installed path `~/.config/opencode/retry-errors.json` is a symlink to `configs/retry-errors.json` in this repo. Editing either path edits the same file. OpenCode sees changes immediately.

**Install Target**: `$HOME/.config/opencode/retry-errors.json`

**Status**: Required

---

## oh-my-openagent.json

**Purpose**: OMO (Oh-My-OpenAgent) agent and category overrides.

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

**Install Target**: `$HOME/.config/opencode/oh-my-openagent.json`

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
| `opencode.json` | Main config: 8 providers, 9 plugins, models, limits, defaults | `$HOME/.config/opencode/opencode.json` | Required |
| `opencode.jsonc` | Bash permission restrictions for destructive commands | `$HOME/.opencode/opencode.jsonc` | Required |
| `provider-connect-retry.mjs` | Error-triggered retries, empty-response detection, nudge prompts, and fallback handling | `$HOME/.config/opencode/provider-connect-retry.mjs` | Required |
| `retry-errors.json` | Retryable error pattern registry with backoff and fallback rules | `$HOME/.config/opencode/retry-errors.json` | Required |
| `oh-my-openagent.json` | OMO agent/category overrides and skill loading | `$HOME/.config/opencode/oh-my-openagent.json` | Required |
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
