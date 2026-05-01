# Configuration Files

The OhMyOpenCode configuration system provides portable, reusable OpenCode settings through a bundle of JSON, JSONC, and JavaScript configuration files.

## Overview

Configuration files control OpenCode behavior, provider settings, plugin loading, model assignments, and permission restrictions. All configs are copied from the local OpenCode installation with personal paths normalized to `$HOME` notation.

---

## opencode.json

**Purpose**: Main OpenCode configuration file. Controls core agent behavior, providers, plugins, and models.

**What it Configures**:

- **Providers**: 9 provider configurations for different AI services
- **Plugins**: 10 plugin registrations and their settings
- **Model Settings**: Provider model catalogs, default models, limits, and timeouts
- **Runtime Defaults**: Agent behavior, output preferences
- **Feature Flags**: Experimental features and toggles

**Key Sections**:

- `enabled_providers` — Enabled provider IDs
- `plugin` — Loaded plugins and local config-layer modules
- `agent` — Agent-specific runtime settings such as the compaction model
- `provider` — Provider definitions, model catalogs, endpoints, and options
- `compaction` / `experimental` — Compaction behavior and feature flags

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

## dcp.jsonc

**Purpose**: DCP (Dynamic Context Pruning) plugin configuration. Controls how the DCP plugin compresses conversation ranges and manages archived summaries.

**What it Configures**:

- Range compression mode and retention policy
- Token budget caps for archived summaries
- Whether old raw turns stay fully hidden or remain reversible

**Key Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `compress.mode` | string | Always `"range"`. Enables range-based compression where contiguous blocks of old conversation turns are summarized. |
| `compress.retentionMode` | string | `"reversible"` or `"bounded"`. Controls what happens to archived raw turns after compression. |
| `compress.maxArchivedSummaryTokens` | integer | Maximum tokens allowed for all archived summaries combined. Only enforced when `retentionMode` is `"bounded"`. |

**Retention Modes**:

- **`reversible`** (default upstream behavior): Old raw turns are hidden from the default prompt path but kept in session storage. They can be restored later via `decompress` or `recompress` commands.
- **`bounded`** (local patched behavior): Old raw turns are archived out of the default prompt path and a hard token cap is enforced on the total size of all archived summaries. The `maxArchivedSummaryTokens` budget is enforced per-summary via hard text truncation; if a summary exceeds the budget its text is clipped and a tail marker is appended. The `decompress` and `recompress` commands reject bounded archive blocks, so archived content cannot be restored. This keeps long-running sessions from growing without limit.

**Local Patch Note**:

The bounded retention mode is **not upstream standard behavior**. It is backed by a local patch to the installed `@tarquinen/opencode-dcp` package. The patch registry entry lives at `.sisyphus/patches/opencode-dcp--bounded-range-archive-mode.md`. If you update the DCP package, you may need to reapply or verify the patch.

**Install Target**: `$HOME/.config/opencode/dcp.jsonc`

**Status**: Optional

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

- Agent model assignments
- Category model assignments
- Default skill loading
- OMO-specific settings
- Override behaviors for core OpenCode

**Key Features**:

- Custom agent and category model overrides
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

## aspect-dynamics.mjs

**Purpose**: Config-layer JavaScript plugin that performs deterministic heuristic scoring on conversation transcripts and dispatches transcript-visible advisory nudges.

**What it Configures**:

- Aspect set loading and resolution (e.g., `emotions-v1`)
- Heuristic phrase matching against the recent conversation context
- Deterministic scoring (no model-backed inference in MVP)
- Transcript-visible advisory nudge dispatch when a score crosses the configured threshold
- Per-session deduplication, circuit breaker, and recursion guard

**How it Works**:

The plugin registers an `event` handler that watches three event types:

1. **`session.created`** — Initializes per-session state tracking. Child sessions are ignored.

2. **`session.deleted`** — Cleans up session state to prevent memory leaks.

3. **`session.idle`** — The main scoring pipeline runs here:
   - Extracts the recent conversation context (configurable turn window)
   - Checks a recursion guard to prevent nudge loops
   - Prefilters context against active aspect sets using heuristic phrase matching
   - Scores matching aspects deterministically (weighted hit count normalized to 0-1)
   - Dispatches a transcript-visible nudge if the top score exceeds the set's default threshold
   - Deduplicates by assistant message ID so the same message is never nudged twice

**Deferred Fields (Reserved for Future Use)**:

The plugin accepts three deferred fields in config that are deliberately unused in MVP and trigger zero network calls:

- `scoringModel` — Reserved for model-backed aspect scoring
- `polishingModel` — Reserved for nudge text polishing
- `dreamAgent` — Reserved for background session analysis

These fields are logged at startup for visibility but are otherwise inert.

**Key Fields**:

- `enabled` — Master toggle for the plugin
- `activeSets` — Array of aspect set IDs to load (e.g., `["emotions-v1"]`)
- `heuristicPreFilter` — Whether to skip scoring when no heuristic phrases match
- `contextWindowTurns` — Number of recent turns to include in context extraction

**Install Target**: `$HOME/.config/opencode/aspect-dynamics.mjs`

**Status**: Optional

---

## Configuration Summary

| File | What it Controls | Install Target | Status |
|------|------------------|----------------|--------|
| `opencode.json` | Main config: 9 providers, 10 plugins, models, limits, defaults | `$HOME/.config/opencode/opencode.json` | Required |
| `opencode.jsonc` | Bash permission restrictions for destructive commands | `$HOME/.opencode/opencode.jsonc` | Required |
| `dcp.jsonc` | DCP plugin configuration with bounded range archive retention (local patch) | `$HOME/.config/opencode/dcp.jsonc` | Optional |
| `provider-connect-retry.mjs` | Error-triggered retries, empty-response detection, nudge prompts, and fallback handling | `$HOME/.config/opencode/provider-connect-retry.mjs` | Required |
| `retry-errors.json` | Retryable error pattern registry with backoff and fallback rules | `$HOME/.config/opencode/retry-errors.json` | Required |
| `aspect-dynamics.mjs` | Config-layer plugin: deterministic heuristic scoring and transcript-visible advisory nudges | `$HOME/.config/opencode/aspect-dynamics.mjs` | Optional |
| `aspect-dynamics/*.mjs` | 7 support modules (config, context, heuristics, session-state, sets, nudge, logging) | `$HOME/.config/opencode/aspect-dynamics/` | Optional |
| `aspect-dynamics/sets/*.json` | Seed aspect sets (e.g., `emotions-v1`) | `$HOME/.config/opencode/aspect-dynamics/sets/` | Optional |
| `oh-my-openagent.json` | OMO agent/category model overrides and skill loading | `$HOME/.config/opencode/oh-my-openagent.json` | Required |
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
