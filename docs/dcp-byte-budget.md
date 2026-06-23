# DCP Byte-Budget Gate — Configuration Reference

> **RETIRED 2026-06-23**: DCP replaced by @cortexkit/opencode-magic-context.
> MC's continuous transform prevents the content accumulation that caused 413 errors.
> This document is retained for historical reference only.

> **Patch status**: Local modification (not upstream standard behavior).  
> **Patch ID**: `opencode-dcp--byte-budget`  
> **Dependency**: `@tarquinen/opencode-dcp@3.1.9`  
> **Verification**: `bash tests/test_dcp_payload_budget.sh --installed`

---

## Overview

The byte-budget gate is a DCP patch that enforces a hard byte cap on the message payload after all other compression strategies (deduplication, error purging, range compression, nudge injection) have run. It prevents the prompt from exceeding the model provider's 2 MiB (2,097,152-byte) protocol limit, which would otherwise cause a 413 Payload Too Large error.

The gate runs as the **final step** in `createChatMessageTransformHandler()`, after `stripStaleMetadata()` and before `saveContext`.

---

## Configuration

Set in `configs/opencode/dcp.jsonc`:

```jsonc
"compress": {
    // Byte-aware pruning cap: 2,097,152-byte hard cap (2 MiB protocol limit),
    // minus 262,144-byte reserve (for injected tool outputs and nudge overhead),
    // minus 32,768-byte safety margin (to stay within safe operating envelope).
    // Effective safe target: 1,802,240 bytes.
    "maxPayloadBytes": 1802240
}
```

### Safety Margin Derivation

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| `hardLimitBytes` | 2,097,152 | 2 MiB protocol limit enforced by model providers (e.g., Anthropic, OpenAI) |
| `reserveBytes` | 262,144 | Headroom for injected tool outputs, compress nudges, and prompt overhead added after the byte-budget gate runs |
| `safetyMarginBytes` | 32,768 | Conservative operating envelope to avoid edge-of-limit behavior |
| `safeClampTargetBytes` | 1,802,240 | Effective clamp target: `hardLimitBytes - reserveBytes - safetyMarginBytes` |

When `maxPayloadBytes > hardLimitBytes`, the gate silently caps it to `safeClampTargetBytes` and logs a warning.

### Relation to Other DCP Settings

| Setting | Relation |
|---------|----------|
| `compress.maxArchivedSummaryTokens` (1,200) | Controls per-summary token budget for bounded-range archive mode. Independent of byte-budget — archived summaries still pass through `measureMessagePayloadBytes`. |
| `compress.retentionMode: "bounded"` | Archive mode that removes raw messages from the prompt path. Works alongside byte-budget to manage both structured archive size and total payload size. |
| `compress.maxContextLimit` / `compress.minContextLimit` | Relative token thresholds for DCP range compression (`55%` / `30%` of the active model context window). Byte-budget operates at the byte level and is orthogonal to token limits. |

---

## How It Works

The gate exports `pruneByByteBudget(state, logger, messages, config)`, which measures `Buffer.byteLength(JSON.stringify(messages), "utf8")` and applies up to five compaction passes when the payload exceeds `maxPayloadBytes`:

### Compaction Passes

1. **`compactCompletedToolOutputs`** — Finds stale completed tool parts with output strings exceeding the budget. Replaces each output with `"Byte budget compacted tool output: {N} characters [Originally: {M} bytes]"`, preserving the last two tool results per call chain.

2. **`collapseRepeatedScaffolds`** — Detects consecutive messages with identical text content that match slash-command scaffold patterns. Collapses all but the newest into `"[Older repeated scaffold omitted ({N} repeats)]"`.

3. **`collapseRepeatedErrorLoops`** — Detects consecutive tool error parts with identical error text. Collapses all but the newest into `"[Repeated error loop omitted ({N} repeats)]"`.

4. **`collapseOlderTodoSnapshots`** — Detects consecutive `todowrite` tool calls with identical output. Preserves only the newest snapshot; older ones become `"[Older todo snapshot omitted ({N} repeats)]"`.

5. **`removeOldNonProtectedMessages`** — Last resort that removes entire non-protected messages from oldest to newest until the payload fits the budget. Protected messages are never removed.

### Protected Messages

The following messages are never removed:
- The **frontier** — the last user message and its assistant response
- Messages containing `[Compressed conversation section]` placeholders
- Messages with `role === "user"` (frontier user is already covered above)

### Fail-Closed Behavior

If the protected frontier alone exceeds `maxPayloadBytes`, the gate does NOT remove messages. Instead it returns:
```json
{
  "changed": false,
  "endingBytes": <same as startingBytes>,
  "startingBytes": <pre-measurement>,
  "failClosedReason": "protected frontier exceeds maxPayloadBytes",
  "diagnostics": "protected frontier exceeds maxPayloadBytes"
}
```
A warning is logged via the DCP logger. The session continues with the oversized payload; the model provider will likely reject it with a 413 error.

### Telemetry

The return object includes:
- `startingBytes` / `endingBytes` — Pre/post payload byte counts
- `changed` — Whether any compaction occurred
- `reductionPasses` — Array of pass names that contributed to reduction
- `affectedMessageRefs` — Array of affected raw message IDs
- `affectedCallIds` — Array of affected tool call IDs
- `failClosedReason` — Non-null only when fail-closed
- `diagnostics` — Human-readable summary

---

## Installation

### Prerequisites

T1–T5 from the byte-aware DCP pruning pipeline completed (source import, byte-budget implementation, hook integration, test harness, runtime alignment).

### Install Steps

The byte-budget patch is distributed across 6 files in `dist/lib/`:
- `messages/byte-budget.js` (new)
- `messages/byte-budget.d.ts` (new)
- `hooks.js` (modified)
- `hooks.d.ts` (modified)
- `config.js` (modified)
- `config.d.ts` (modified)

These files are part of the 15-file `DCP_PATCH_FILES` array in `install.sh`.

To install:

```bash
# 1. Build DCP from source (in the DCP repo)
cd omo-hub/projects/opencode-dynamic-context-pruning
npm run build
npx tsc --noEmit false --emitDeclarationOnly false

# 2. Sync to reference install
rsync -a dist/ ~/.config/opencode/node_modules/@tarquinen/opencode-dcp/dist/

# 3. Sync all known runtime/cache copies (reference, runtime, OpenCode package cache, XDG_CACHE_HOME cache, Bun v3 cache)
cd ~/ez-omo-config
./install.sh --configs
```

### Verify Installation

```bash
# Marker presence check across all known runtime/cache copies
bash tests/test_dcp_payload_budget.sh --installed
```

Expected: 0 failed for the test; pass count varies with local XDG and Bun cache contents. The config should retain `"maxPayloadBytes": 1802240`.

---

## Uninstall / Rollback

### Option 1: Registry-level rollback (config only)

```bash
git checkout -- configs/opencode/dcp.jsonc
./install.sh --configs
```
This removes `maxPayloadBytes` from the config but leaves the patched JS files on disk. The byte-budget module will not be invoked without the config key.

### Option 2: Full rollback (config + dist files)

```bash
# Restore config
git checkout -- configs/opencode/dcp.jsonc

# Restore patched files from backup (if available)
cp -r ~/.ez-omo-backup/<date>/dcp/* ~/.config/opencode/node_modules/@tarquinen/opencode-dcp/dist/lib/
./install.sh --configs

# OR manually remove byte-budget files from all copies
for root in \
  ~/.config/opencode/node_modules/@tarquinen/opencode-dcp \
  ~/.cache/opencode/node_modules/@tarquinen/opencode-dcp \
  ~/.cache/opencode/packages/@tarquinen/opencode-dcp@latest/node_modules/@tarquinen/opencode-dcp \
  ~/.cache/opencode/packages/@tarquinen/opencode-dcp@3.1.9/node_modules/@tarquinen/opencode-dcp \
  ~/.bun/install/cache/@tarquinen/opencode-dcp@3.*@@@*; do
  rm -f "$root/dist/lib/messages/byte-budget.js" "$root/dist/lib/messages/byte-budget.d.ts"
done
```

After rollback, restart OpenCode to ensure the old modules are loaded.

---

## Verification

### Quick marker check

```bash
grep -cE "maxPayloadBytes|pruneByByteBudget" \
  ~/.config/opencode/node_modules/@tarquinen/opencode-dcp/dist/lib/messages/byte-budget.js
```
Expected: `≥1`.

### Full regression suite

```bash
# Bounded-range + byte-budget + startup-warning
bash tests/test_dcp_bounded_range.sh
bash tests/test_dcp_payload_budget.sh --installed
bash tests/test_dcp_startup_warning.sh
```

All three should pass completely.

### Config grep

```bash
grep -n "maxPayloadBytes" configs/opencode/dcp.jsonc
# Output: 68:    "maxPayloadBytes": 1802240
```
