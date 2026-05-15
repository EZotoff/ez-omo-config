# Configuration Files

The OhMyOpenCode configuration system provides portable, reusable OpenCode settings through a bundle of JSON, JSONC, and JavaScript configuration files.

## Overview

Configuration files control OpenCode behavior, provider settings, plugin loading, model assignments, and permission restrictions. All configs are copied from the local OpenCode installation with personal paths normalized to `$HOME` notation.

---

## opencode.json

**Purpose**: Main OpenCode configuration file. Controls core agent behavior, providers, plugins, and models.

**What it Configures**:

- **Providers**: 10 provider configurations for different AI services
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

The bounded retention mode is **not upstream standard behavior**. It is backed by a local patch to the installed `@tarquinen/opencode-dcp` package. The patch registry entry lives at `.sisyphus/patches/opencode-dcp--bounded-range-archive-mode.md`.

`install.sh --configs` includes a DCP patch sync step: it copies the 10 patched DCP files from the reference install at `~/.config/opencode/node_modules/@tarquinen/opencode-dcp/dist/lib` into both native cache copies when present:

- `~/.cache/opencode/node_modules/@tarquinen/opencode-dcp/dist/lib`
- `~/.cache/opencode/packages/@tarquinen/opencode-dcp@latest/node_modules/@tarquinen/opencode-dcp/dist/lib`

This prevents package-cache refreshes from reintroducing unknown-key warnings for `compress.retentionMode` and `compress.maxArchivedSummaryTokens`.

**Observability**:

After any OpenCode or DCP update, verify the patch is still intact by running the canonical proof command from the repo root:

```bash
bash tests/test_dcp_bounded_range.sh
```

Expected: 8 passed, 0 failed. The script checks marker presence across all three install copies (reference, runtime, and package cache) and exercises five functional regression cases, including the `bounded-runtime-proof-metadata` case that asserts runtime block metadata (`retentionMode`, `archiveRawMessages`, `maxArchivedSummaryTokens`, `archivedBlockId`, `rawMessageCoverageCount`, `normalizedSummaryTokenCount`, `truncationOccurred`) against the live DCP state.

**Fresh-start warning probe**: File-marker checks prove patch presence on disk, but a long-running OpenCode process started before the patch sync may still emit unknown-key warnings because it loaded unpatched modules at startup. To verify a fresh process does not reject the bounded-retention keys, also run:

```bash
bash tests/test_dcp_startup_warning.sh
```

Expected: 2 passed, 0 failed. This test probes a short-lived `opencode serve` startup and fails if the logs contain `Unknown keys: compress.retentionMode, compress.maxArchivedSummaryTokens` or `DCP: config warning`.

**Stale-process gotcha**: If a running OpenCode server or TUI session emits the DCP unknown-key warning despite `test_dcp_bounded_range.sh` passing, the process was likely started before the most recent patch sync. The file markers prove the patch exists on disk, but the running process loaded the old modules at startup. Restart OpenCode to load the patched modules.

For detailed install locations, verification commands, failure string meanings, and reapply instructions, see the patch registry entry at `.sisyphus/patches/opencode-dcp--bounded-range-archive-mode.md`.

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

### Prometheus HTML Proposal+Design Packet Contract

The `prometheus` agent is configured via `prompt_append` to produce a human-facing proposal artifact before emitting the executable Markdown plan. This is a **prompt contract**, not runtime infrastructure.

**HTML Packet** (default): For Standard or Architecture planning work, Prometheus creates a human-facing proposal/checkpoint artifact at `.sisyphus/drafts/<topic-slug>-proposal.html`. The packet includes an objective, user-visible outcome, non-goals, chosen implementation slice, design assumptions, risks, and a checkpoint question.

**Markdown Fallback / Source**: When HTML cannot be produced, the same-content fallback is used as a Markdown-formatted proposal.

**Markdown Plan** (canonical): `.sisyphus/plans/*.md` remains the canonical execution source for Atlas/Sisyphus. The HTML packet is a checkpoint that happens before Prometheus writes the executable plan.

**Checkpoint**: If proceeding by default because no blocking decision exists, Prometheus records the assumption in the plan. If a user decision materially changes scope or acceptance criteria, Prometheus asks before continuing.

**Goal Coverage Map**: The packet includes a Goal Coverage Map showing how the proposed implementation slice advances the high-level goal using these labels:

- `FULL` — the slice completely covers the goal
- `PARTIAL` — the slice covers part of the goal, with the remainder deferred or handled separately
- `DEFERRED` — the goal is intentionally postponed to a later phase
- `DELTA` — the goal represents a change from a prior state; the slice addresses the delta

**Scope (v1)**: This is a prompt contract only. There is no template or generator infrastructure in v1. The artifact format and path conventions are enforced via the agent's configured prompt instructions.

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

- Aspect set loading and resolution (e.g., `emotions-v1`, `emotions-v2`)
- Heuristic phrase matching against the recent conversation context
- Deterministic scoring (no model-backed inference in MVP)
- Transcript-visible advisory nudge dispatch when a score crosses the configured threshold
- Per-session deduplication, circuit breaker, and recursion guard
- Optional non-Wisdom proof-event sink for local observability and verification

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

These fields are inert by default. They are logged only when `logLevel` is set to `info`, so normal startup stays quiet.

**Key Fields**:

- `enabled` — Master toggle for the plugin
- `activeSets` — Ordered array of aspect set IDs to load (e.g., `["emotions-v1"]`, `["emotions-v2"]`, or both). This field resolves and loads the specified aspect sets at runtime; unknown IDs fail closed and put the plugin in no-op mode.
- `logLevel` — Plugin terminal logging threshold. Defaults to `warn`; set `info` to show startup/info diagnostics, or `silent` to suppress all plugin terminal logging.
- `heuristicPreFilter` — Whether to skip scoring when no heuristic phrases match
- `contextWindowTurns` — Number of recent turns to include in context extraction
- `proofEnabled` — Optional toggle for JSONL proof-event emission (enabled by default when unset)
- `proofPath` — Optional override for the JSONL proof-event sink path (defaults under `~/.local/share/opencode/aspect-dynamics/`)

**Install Target**: `$HOME/.config/opencode/aspect-dynamics.mjs`

**Status**: Optional

---

## Symlinked Configs vs Installed Plugin Targets

Not all files in this repository share the same deployment model. The symlinked config behavior applies **only** to the listed config files. Installed plugin targets are separate deployable artifacts.

### Symlinked Config Files

These files are symlinked from `~/.config/opencode/` into this repo. Editing either path edits the same file. There is one file, not two.

| File | Live Path | Store Path |
|------|-----------|------------|
| `opencode.json` | `~/.config/opencode/opencode.json` | `configs/opencode/opencode.json` |
| `oh-my-openagent.json` | `~/.config/opencode/oh-my-openagent.json` | `configs/oh-my-openagent/oh-my-openagent.json` |
| `provider-connect-retry.mjs` | `~/.config/opencode/provider-connect-retry.mjs` | `configs/opencode/provider-connect-retry.mjs` |
| `retry-errors.json` | `~/.config/opencode/retry-errors.json` | `configs/retry-errors.json` |

### Installed Plugin Targets

Plugin files such as `$HOME/.opencode/plugin/*.ts` are copied or symlinked by `install.sh` and must be treated as distinct deployment targets. They do **not** share the "one file, not two" symlink property. After editing a plugin in the repo, run `install.sh --plugins` to push changes to the live target.

**Why the distinction matters**: Agents must know whether a change to a repo file is automatically visible to OpenCode (symlinked configs) or requires an install step (plugins). Claim language for plugins must reflect the actual install state, not just the repo state.

---

## Configuration Summary

| File | What it Controls | Install Target | Status |
|------|------------------|----------------|--------|
| `opencode.json` | Main config: 10 providers, 10 plugins, models, limits, defaults | `$HOME/.config/opencode/opencode.json` | Required |
| `opencode.jsonc` | Bash permission restrictions for destructive commands | `$HOME/.opencode/opencode.jsonc` | Required |
| `dcp.jsonc` | DCP plugin configuration with bounded range archive retention (local patch) | `$HOME/.config/opencode/dcp.jsonc` | Optional |
| `provider-connect-retry.mjs` | Error-triggered retries, empty-response detection, nudge prompts, and fallback handling | `$HOME/.config/opencode/provider-connect-retry.mjs` | Required |
| `retry-errors.json` | Retryable error pattern registry with backoff and fallback rules | `$HOME/.config/opencode/retry-errors.json` | Required |
| `aspect-dynamics.mjs` | Config-layer plugin: deterministic heuristic scoring and transcript-visible advisory nudges | `$HOME/.config/opencode/aspect-dynamics.mjs` | Optional |
| `aspect-dynamics/*.mjs` | 7 support modules (config, context, heuristics, session-state, sets, nudge, logging) | `$HOME/.config/opencode/aspect-dynamics/` | Optional |
| `aspect-dynamics/sets/*.json` | Seed aspect sets (e.g., `emotions-v1`, `emotions-v2`) | `$HOME/.config/opencode/aspect-dynamics/sets/` | Optional |
| `oh-my-openagent.json` | OMO agent/category model overrides, skill loading, and Prometheus HTML proposal planning contract | `$HOME/.config/opencode/oh-my-openagent.json` | Required |
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

## Non-Wisdom Observability Contract

This section defines the shared sanitized observability contract for config-layer systems in this repository. The contract applies to **Aspect Dynamics** and **DCP** (Dynamic Context Pruning). These systems emit events for debugging and health monitoring while never leaking sensitive conversation content.

### Event Shape

Every observability event produced by a config-layer system must include these fields where applicable:

| Field | Type | Description |
|-------|------|-------------|
| `ts` | string | ISO 8601 timestamp of the event |
| `system` | string | System identifier. Values: `aspect-dynamics`, `dcp` |
| `event` | string | Event type string (e.g., `session.scored`, `compress.range_archived`) |
| `status` | string | Event outcome: `success`, `failure`, `idle`, `skipped` |
| `session_id` | string | Correlation ID for the OpenCode session |
| `duration_ms` | integer | Elapsed time for the operation, in milliseconds |
| `reason` | string | Human-readable explanation when status is not `success` |
| `counts` | object | Numeric aggregates (e.g., `{"aspectsScored": 7, "nudgesDispatched": 1}`) |
| `error` | object | Sanitized error information. Contains only `class` and `message`. Never a stack trace |
| `version` | string | System version or commit hash |
| `config_hash` | string | Fingerprint of the active configuration (e.g., hash of `aspect-dynamics.mjs` or `dcp.jsonc`) |

### Redaction Rules

The following values must **never** appear in any observability event:

- Raw transcript content
- Prompts sent to models
- Model responses or completions
- API keys, tokens, or credentials
- Authentication paths or secret file locations
- Full message bodies from OpenCode sessions
- Request bodies, response bodies, or headers from provider calls

**Allowed substitutions**:

| Instead of | Log this |
|---|---|
| Full message text | Message ID, role, and token count |
| Prompt content | Prompt hash or `prompt_sha256` |
| Model response | Response length in tokens and finish reason |
| API key | Provider ID only (e.g., `github-copilot`, `moonshot`) |
| File path with secrets | File name only, or a redaction marker `<redacted>` |

### Retention Rules

All durable JSONL and proof artifacts must be bounded:

- **Default maximum**: 1000 events per JSONL file
- **Bound by count**: Truncate to the most recent 1000 lines when the limit is exceeded
- **Bound by age**: Events older than 30 days may be removed during cleanup
- **Explicit cleanup**: Systems must provide a manual cleanup command or flag
- **Deterministic truncation**: Prefer line-count truncation over time-based rotation for predictability

### Examples

**Aspect Dynamics — session scored event:**

```json
{
  "ts": "2026-05-01T14:32:01.123Z",
  "system": "aspect-dynamics",
  "event": "session.scored",
  "status": "success",
  "session_id": "ses_abc123",
  "duration_ms": 12,
  "counts": {
    "aspectsScored": 7,
    "nudgesDispatched": 1,
    "contextWindowTurns": 10
  },
  "version": "1.2.0",
  "config_hash": "a3f1b2c4"
}
```

**Aspect Dynamics — scoring failure event:**

```json
{
  "ts": "2026-05-01T14:32:05.456Z",
  "system": "aspect-dynamics",
  "event": "session.scored",
  "status": "failure",
  "session_id": "ses_abc123",
  "duration_ms": 45,
  "reason": "Aspect set emotions-v1 failed to load",
  "error": {
    "class": "FileNotFoundError",
    "message": "Set file not found at configured path"
  },
  "version": "1.2.0",
  "config_hash": "a3f1b2c4"
}
```

**DCP — range compression archived event:**

```json
{
  "ts": "2026-05-01T14:35:22.789Z",
  "system": "dcp",
  "event": "compress.range_archived",
  "status": "success",
  "session_id": "ses_def456",
  "duration_ms": 234,
  "counts": {
    "turnsArchived": 15,
    "tokensBefore": 4200,
    "tokensAfter": 1800,
    "summariesCreated": 1
  },
  "version": "1.0.0",
  "config_hash": "dcp-bounded-v1"
}
```

---

## See Also

- [Plugins Documentation](plugins.md) — Plugin configuration references
- [Skills Documentation](skills.md) — Skill loading configuration
- [MANIFEST.md](../MANIFEST.md) — Complete artifact inventory
- `configs/opencode/README.md` — Quick reference
- `install.sh` — Installation script with backup and idempotency
