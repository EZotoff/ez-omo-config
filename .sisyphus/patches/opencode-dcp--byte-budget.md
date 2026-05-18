---
patch_id: "opencode-dcp--byte-budget"
dependency: "@tarquinen/opencode-dcp"
target_file: "dist/lib/messages/byte-budget.js"
target_install_paths:
  - "/home/ezotoff/.config/opencode/node_modules/@tarquinen/opencode-dcp"
  - "/home/ezotoff/.cache/opencode/node_modules/@tarquinen/opencode-dcp"
  - "/home/ezotoff/.cache/opencode/packages/@tarquinen/opencode-dcp@latest/node_modules/@tarquinen/opencode-dcp"
  - "/home/ezotoff/.cache/opencode/packages/@tarquinen/opencode-dcp@3.1.9/node_modules/@tarquinen/opencode-dcp"
  - "/home/ezotoff/snap/alacritty/common/.cache/opencode/node_modules/@tarquinen/opencode-dcp"
  - "/home/ezotoff/snap/alacritty/common/.cache/opencode/packages/@tarquinen/opencode-dcp@latest/node_modules/@tarquinen/opencode-dcp"
  - "/home/ezotoff/snap/alacritty/common/.cache/opencode/packages/@tarquinen/opencode-dcp@3.1.9/node_modules/@tarquinen/opencode-dcp"
  - "/home/ezotoff/.bun/install/cache/@tarquinen/opencode-dcp@3.*@@@*"
status: "active"
applied_date: "2026-05-16"
dep_version: "3.1.9"
upstream_issue: "https://github.com/Opencode-DCP/opencode-dynamic-context-pruning/pull/501"
verification_pattern: "maxPayloadBytes|pruneByByteBudget|measureMessagePayloadBytes|BYTE_BUDGET_DEFAULTS"
---

# Byte-Budget Payload Gate for DCP

## Problem
DCP's existing compression strategies (deduplication, error purging, range compression) do not bound the total raw byte size of the message payload. In long-running sessions, accumulated tool outputs, repeated scaffold instructions, error loops, and todo snapshots can bloat the prompt payload past the 2 MiB protocol limit (2,097,152 bytes). When the payload exceeds this limit, the model provider rejects the request with a 413 Payload Too Large error, causing an unrecoverable session failure.

## Patch Description
This is a local patch that adds a byte-budget enforcement gate at the end of DCP's chat transform pipeline. The gate measures the full UTF-8 byte size of the serialized message list and applies up to five compaction passes when the payload exceeds `maxPayloadBytes`:

1. **compactCompletedToolOutputs** — Replaces stale completed tool outputs with a short marker when their size exceeds the budget, preserving the last two tool results.
2. **collapseRepeatedScaffolds** — Detects identical consecutive slash-command scaffold texts and collapses all but the newest into a short omission marker.
3. **collapseRepeatedErrorLoops** — Detects identical consecutive provider error tool results and collapses all but the newest into an omission marker.
4. **collapseOlderTodoSnapshots** — Detects consecutive `todowrite` snapshots and preserves only the newest, collapsing earlier ones.
5. **removeOldNonProtectedMessages** — As a last resort, removes old non-protected messages (frontier messages and compressed placeholders are protected) from the oldest first until the budget is met.

Key constants (`BYTE_BUDGET_DEFAULTS`):
- `hardLimitBytes`: 2,097,152 (2 MiB protocol limit)
- `reserveBytes`: 262,144 (reserved for injected tool outputs and nudge overhead)
- `safetyMarginBytes`: 32,768 (safe operating envelope)
- `safeClampTargetBytes`: 1,802,240 (effective safe target = hardLimit - reserve - safetyMargin)

Fail-closed: If the protected frontier (newest user + assistant messages that cannot be removed) alone exceeds the budget, the gate does not remove them. Instead, it logs a warning with the diagnostic `"protected frontier exceeds maxPayloadBytes"` and leaves the payload unchanged.

Changes across 6 files:

- **messages/byte-budget.js** (new): Core module with `pruneByByteBudget()`, `measureMessagePayloadBytes()`, and the five compaction passes.
- **messages/byte-budget.d.ts** (new): Type declarations for the byte-budget module.
- **hooks.js** (modified): `createChatMessageTransformHandler()` calls `pruneByByteBudget()` as the final transform step after `stripStaleMetadata()` and before `saveContext`. Also applies an emergency pass before the `allowSubAgents === false` early return.
- **hooks.d.ts** (modified): Type declarations for the modified hooks.
- **config.js** (modified): Added `compress.maxPayloadBytes` to `VALID_CONFIG_KEYS` and type validation.
- **config.d.ts** (modified): Type declaration for `maxPayloadBytes`.

## Install Locations

Same multi-copy layout as the bounded-range patch. See the bounded-range patch doc (same directory) for the full install location table, including OpenCode package-cache copies and existing Bun v3 plugin cache copies.

## Verification

### Quick config check
```bash
grep -n "maxPayloadBytes" configs/opencode/dcp.jsonc
```
Expected: `"maxPayloadBytes": 1802240`

### Marker presence on disk
```bash
grep -cE "maxPayloadBytes|pruneByByteBudget|measureMessagePayloadBytes|BYTE_BUDGET_DEFAULTS" \
  ~/.config/opencode/node_modules/@tarquinen/opencode-dcp/dist/lib/messages/byte-budget.js
```
Expected: ≥1 match (file exists with byte-budget symbols).

### Regression harness
```bash
bash tests/test_dcp_payload_budget.sh --installed
```
Expected: 0 failed. Pass count varies with local XDG and Bun cache contents:
- Marker checks for reference, runtime, OpenCode package-cache, XDG_CACHE_HOME cache (when set and differing from HOME/.cache), and existing Bun v3 cache copies of `messages/byte-budget.js`
- 9 functional cases

### Full stack verification
Run both DCP verification scripts:
```bash
bash tests/test_dcp_bounded_range.sh && bash tests/test_dcp_payload_budget.sh --installed
```

## Reapply Instructions
If the patch is lost after a DCP package update:

1. Build from source: `cd omo-hub/projects/opencode-dynamic-context-pruning && npm run build && npx tsc --noEmit false --emitDeclarationOnly false`
2. Sync dist to reference install: `rsync -a dist/ ~/.config/opencode/node_modules/@tarquinen/opencode-dcp/dist/`
3. Sync all copies: `./install.sh --configs` from this repo (syncs reference, runtime, `@latest` package cache, `@3.1.9` version-pinned package cache, XDG_CACHE_HOME cache copies when set and differing from HOME/.cache, and existing Bun v3 plugin cache copies)
4. Verify: `bash tests/test_dcp_payload_budget.sh --installed`
5. **Restart OpenCode** so the backend reloads the patched modules

## Durable Alternative
Same upstream PR #501 (https://github.com/Opencode-DCP/opencode-dynamic-context-pruning/pull/501) that proposes bounded archive mode also covers payload-budget enforcement as a first-class config option. If merged, both patches could be deprecated and controlled through upstream config keys.
Status: pursued
