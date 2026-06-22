---
patch_id: "opencode-dcp--bounded-range-archive-mode"
dependency: "@tarquinen/opencode-dcp"
target_file: "dist/index.js"
target_install_paths:
  - "/home/ezotoff/.config/opencode/node_modules/@tarquinen/opencode-dcp"
  - "/home/ezotoff/.cache/opencode/node_modules/@tarquinen/opencode-dcp"
  - "/home/ezotoff/.cache/opencode/packages/@tarquinen/opencode-dcp@latest/node_modules/@tarquinen/opencode-dcp"
  - "/home/ezotoff/.cache/opencode/packages/@tarquinen/opencode-dcp@3.1.13/node_modules/@tarquinen/opencode-dcp"
  - "/home/ezotoff/snap/alacritty/common/.cache/opencode/node_modules/@tarquinen/opencode-dcp"
  - "/home/ezotoff/snap/alacritty/common/.cache/opencode/packages/@tarquinen/opencode-dcp@latest/node_modules/@tarquinen/opencode-dcp"
  - "/home/ezotoff/snap/alacritty/common/.cache/opencode/packages/@tarquinen/opencode-dcp@3.1.13/node_modules/@tarquinen/opencode-dcp"
  - "/home/ezotoff/.bun/install/cache/@tarquinen/opencode-dcp@3.*@@@*"
status: "active"
applied_date: "2026-04-30"
dep_version: "3.1.13"
upstream_issue: "https://github.com/Opencode-DCP/opencode-dynamic-context-pruning/pull/501"
verification_pattern: "COMPRESS_RANGE_BOUNDED|archiveRawMessages|maxArchivedSummaryTokens|retentionMode"
---

# Bounded Range Archive Mode for DCP

## Problem
DCP range compression recursively expands older compressed summaries on each new compression pass. This drives unbounded prompt growth in long-running sessions. Old raw turns remain reversible through `/dcp decompress`, keeping a large message history in the prompt path even when those turns are no longer relevant to current work. Without a cap, archived summaries accumulate indefinitely and eventually push the prompt over the model context window.

## Patch Description
This is a local patch (not upstream standard) that adds a bounded retention mode to DCP range compression. When `retentionMode` is set to `"bounded"`, the compressor archives raw messages covered by the summary instead of keeping them reversible. An archived block suppresses its covered raw messages from the prompt but cannot be decompressed or recompressed. A configurable `maxArchivedSummaryTokens` cap prevents unbounded growth by enforcing per-summary text truncation; each archived summary is hard-clamped to the token budget via `normalizeBoundedRangeSummary()`, which strips placeholders and binary-searches word count, appending a tail marker when truncation occurs.

Changes across 8+ runtime files:

- **config.js**: Added `retentionMode` and `maxArchivedSummaryTokens` config keys to `VALID_CONFIG_KEYS` and `validateConfigTypes()`.
- **compress/state.js**: Added `archiveRawMessages` and `retentionMode` fields to block metadata in `applyCompressionState()`.
- **compress/range.js**: Added bounded mode branch that skips placeholder expansion and uses the `COMPRESS_RANGE_BOUNDED` prompt instead of the standard range prompt.
- **compress/range-utils.js**: Added `normalizeBoundedRangeSummary()` for token budget enforcement on archived summaries.
- **prompts/compress-range.js**: Added `COMPRESS_RANGE_BOUNDED` prompt constant.
- **messages/sync.js**: Added archive-aware state rebuild with `archivedBlockIds` derived field; uses `anchorMessageId` as the origin-presence guard for archived blocks during sync.
- **messages/prune.js**: Updated `filterCompressedRanges()` to skip raw messages when either `activeBlockIds.length > 0` (reversible coverage) OR `archivedBlockIds.length > 0` (archived bounded coverage).
- **commands/decompress.js**: Added guard that rejects bounded archive blocks with a clear error message.
- **commands/recompress.js**: Added guard that rejects bounded archive blocks with a clear error message.
- **commands/compression-targets.js**: Updated target listing to exclude archive blocks from recompressible targets.

## Install Locations

DCP exists in **multiple locations** on this machine. The currently active backend is the native process `/home/ezotoff/.opencode/bin/opencode serve`, which loads plugins from the native cache under `~/.cache/opencode`, not from the snap cache.

| # | Path | Version | Active? | Notes |
|---|------|---------|---------|-------|
| 1 | `/home/ezotoff/.cache/opencode/node_modules/@tarquinen/opencode-dcp/` | 3.1.7 | ✅ **Current runtime** | Loaded by the native OpenCode backend; this is the live patch target |
| 2 | `~/.config/opencode/node_modules/@tarquinen/opencode-dcp/` | 3.1.9 | ⚙️ Reference copy | Manual patched install kept as the source-of-truth donor for runtime syncs |
| 3 | `/home/ezotoff/.cache/opencode/packages/@tarquinen/opencode-dcp@latest/` | 3.1.9 | ✅ Synced cache copy | Package-store source that can be promoted into runtime copies after updates |
| 4 | `/home/ezotoff/.cache/opencode/packages/@tarquinen/opencode-dcp@3.1.9/` | 3.1.9 | ✅ **Version-pinned cache** | Because `opencode.json` pins `@tarquinen/opencode-dcp@3.1.9`, OpenCode loads DCP from this path. Must stay patched to prevent startup warnings. |
| 5 | `/home/ezotoff/.bun/install/cache/@tarquinen/opencode-dcp@3.*@@@*/` | varies | ⚠️ Resolver fallback cache | Bun-compiled OpenCode may consider stale Bun plugin cache copies before OpenCode package cache; existing v3 copies must be patched too. |
| 6 | `/home/ezotoff/snap/alacritty/common/.cache/opencode/node_modules/@tarquinen/opencode-dcp/` | 3.1.8 | ✅ Synced XDG runtime | `install.sh --configs` now syncs here when `XDG_CACHE_HOME` differs from `HOME/.cache` |
| 7 | `/home/ezotoff/snap/alacritty/common/.cache/opencode/packages/@tarquinen/opencode-dcp@latest/` | 3.1.9 | ✅ Synced XDG package cache | `install.sh --configs` now syncs here when `XDG_CACHE_HOME` differs from `HOME/.cache` |
| 8 | `/home/ezotoff/snap/alacritty/common/.cache/opencode/packages/@tarquinen/opencode-dcp@3.1.9/` | 3.1.9 | ✅ Synced XDG version-pinned cache | `install.sh --configs` now syncs here when `XDG_CACHE_HOME` differs from `HOME/.cache` |

**Durable local baseline in this repo:**

- Location #2 (`~/.config/...`) is the source-of-truth patched donor copy.
- `install.sh --configs` now syncs all 15 patched files from #2 into all native cache copies (#1 runtime, #3 `@latest` package cache, #4 `@3.1.9` version-pinned package cache, #6/#7/#8 XDG_CACHE_HOME cache copies when set and differing from HOME/.cache, and #5 existing Bun v3 plugin cache copies) when those destinations exist.

## Canonical Proof Command

Run the canonical proof script from the repo root:

```bash
bash tests/test_dcp_bounded_range.sh
```

Expected: 0 failed. The script exercises marker detection on all known runtime/cache copies (reference, runtime, OpenCode package caches, XDG_CACHE_HOME cache copies when set and differing from HOME/.cache, and any existing Bun v3 DCP cache copies) plus five functional regression cases. Pass count varies with local cache contents. This is the single command to run after any OpenCode or DCP package update to confirm the patch is still intact.

Also run the fresh-start warning probe to ensure a new OpenCode process does not reject the bounded-retention keys:

```bash
bash tests/test_dcp_startup_warning.sh
```

Expected: 0 failed. This test checks version-pinned and Bun cache marker presence, starts a short-lived `opencode serve` probe, and fails if the startup logs contain `Unknown keys: compress.retentionMode`, `compress.maxArchivedSummaryTokens`, `compress.maxPayloadBytes`, or `DCP: config warning`.

## Verification

### How to tell bounded retention is configured

Check `configs/opencode/dcp.jsonc`:

```bash
grep -E 'retentionMode|maxArchivedSummaryTokens' configs/opencode/dcp.jsonc
```

You should see `"retentionMode": "bounded"` and a positive integer for `"maxArchivedSummaryTokens"`.

### How to prove the active runtime copy is patched

Check the **active** runtime copy (native location):

```bash
grep -cE "COMPRESS_RANGE_BOUNDED|archiveRawMessages|maxArchivedSummaryTokens|retentionMode" \
  /home/ezotoff/.cache/opencode/node_modules/@tarquinen/opencode-dcp/dist/lib/config.js \
  /home/ezotoff/.cache/opencode/node_modules/@tarquinen/opencode-dcp/dist/lib/compress/range.js \
  /home/ezotoff/.cache/opencode/node_modules/@tarquinen/opencode-dcp/dist/lib/compress/state.js \
  /home/ezotoff/.cache/opencode/node_modules/@tarquinen/opencode-dcp/dist/lib/compress/range-utils.js
```

Expected: config.js ≥15, range.js ≥4, state.js ≥2, range-utils.js ≥2 matches.

### How to prove bounded archive metadata works at runtime

Run the regression harness:

```bash
bash tests/test_dcp_bounded_range.sh
```

The `bounded-runtime-proof-metadata` harness case asserts bounded archive metadata and limits from runtime state/block objects:

- `retentionMode === "bounded"`
- `archiveRawMessages === true`
- `maxArchivedSummaryTokens` loaded from `configs/opencode/dcp.jsonc`
- `archivedBlockId` is present and integer
- `rawMessageCoverageCount` + `rawMessageCoverage` reflect covered raw IDs
- `archivedMessageCoverageCount` reflects archived coverage in `byMessageId`
- `normalizedSummaryTokenCount <= maxArchivedSummaryTokens`
- `truncationOccurred === true` when summary normalization exceeds budget

```bash
# Proof-string grep for metadata assertions and runtime-proof case wiring:
grep -n "bounded-runtime-proof-metadata\|archiveRawMessages\|maxArchivedSummaryTokens\|retentionMode\|archivedBlockId\|rawMessageCoverageCount\|normalizedSummaryTokenCount\|truncationOccurred" \
  tests/dcp-local-patch/bounded-range.mjs tests/test_dcp_bounded_range.sh
```

```bash
# Quick: verify all patched files are identical between reference and all native cache copies:
SRC="/home/ezotoff/.config/opencode/node_modules/@tarquinen/opencode-dcp/dist/lib"
for DEST in \
  "/home/ezotoff/.cache/opencode/node_modules/@tarquinen/opencode-dcp/dist/lib" \
  "/home/ezotoff/.cache/opencode/packages/@tarquinen/opencode-dcp@latest/node_modules/@tarquinen/opencode-dcp/dist/lib" \
  "/home/ezotoff/.cache/opencode/packages/@tarquinen/opencode-dcp@3.1.9/node_modules/@tarquinen/opencode-dcp/dist/lib" \
  /home/ezotoff/.bun/install/cache/@tarquinen/opencode-dcp@3.*@@@*/dist/lib; do
  [[ -d "$DEST" ]] || continue
  echo "-- checking $DEST"
  for f in config.js config.d.ts compress/range.js compress/state.js compress/range-utils.js messages/sync.js messages/prune.js messages/byte-budget.js messages/byte-budget.d.ts commands/decompress.js commands/recompress.js prompts/compress-range.js commands/compression-targets.js hooks.js hooks.d.ts; do
    diff -q "$SRC/$f" "$DEST/$f" > /dev/null 2>&1 && echo "OK: $f" || echo "MISMATCH: $f"
  done
done
```

### How to prove a fresh OpenCode process does not warn

File-marker checks prove patch presence on disk, but they do not prove a running OpenCode process loaded the patched modules. To verify a fresh startup does not reject `compress.retentionMode`, `compress.maxArchivedSummaryTokens`, or `compress.maxPayloadBytes` as unknown keys, run:

```bash
bash tests/test_dcp_startup_warning.sh
```

Expected: 0 failed. The test probes a short-lived `opencode serve --print-logs --log-level WARN --port 0` startup and fails if stdout/stderr contains `Unknown keys: compress.retentionMode`, `compress.maxArchivedSummaryTokens`, `compress.maxPayloadBytes`, or `DCP: config warning`.

**Stale-process gotcha**: If a running OpenCode server or TUI session emits the DCP unknown-key warning despite all file-marker checks passing, the process was likely started before the most recent patch sync. The patched modules are only loaded at process startup; an already-running process continues using the old modules until restarted. Always restart OpenCode after reapplying or syncing the patch.

### What command to run after OpenCode or DCP updates

After any OpenCode or DCP package update, run both verification scripts:

```bash
bash tests/test_dcp_bounded_range.sh
bash tests/test_dcp_startup_warning.sh
```

If any case fails, the patch may have been overwritten. Reapply per the instructions below, then rerun both proof commands. If `test_dcp_bounded_range.sh` passes but a running OpenCode process still warns, restart that process — the patched modules are only loaded at startup.

### What failure strings mean

| Failure output | Meaning |
|---|---|
| `FAIL: markers-reference-copy` | The reference install at `~/.config/opencode/node_modules/@tarquinen/opencode-dcp/` is missing bounded-retention markers. The source-of-truth copy was likely overwritten. |
| `FAIL: markers-runtime-copy` | The active runtime at `~/.cache/opencode/node_modules/@tarquinen/opencode-dcp/` is unpatched. DCP will ignore `retentionMode` and `maxArchivedSummaryTokens` config keys. |
| `FAIL: markers-package-cache-latest` | The `@latest` package cache at `~/.cache/opencode/packages/@tarquinen/opencode-dcp@latest/` is unpatched. Future `@latest` promotions will revert the patch. |
| `FAIL: markers-package-cache-pinned-3.1.9` | The **version-pinned** package cache at `~/.cache/opencode/packages/@tarquinen/opencode-dcp@3.1.9/` is unpatched. Because `opencode.json` pins `@3.1.9`, this is the path OpenCode actually loads. If unpatched, DCP will ignore `retentionMode` and `maxArchivedSummaryTokens` and emit startup warnings. |
| `FAIL: markers-bun-cache-*` | A Bun install-cache DCP v3 copy is unpatched. Bun plugin resolution can fall back to stale copies, causing real TUI startup warnings even when OpenCode package-cache marker checks pass. |
| `FAIL: markers-xdg-runtime-copy` | The XDG_CACHE_HOME runtime copy is unpatched. OpenCode may load DCP from this path in XDG-compliant or snap-confined environments, ignoring bounded-retention config keys. |
| `FAIL: markers-xdg-package-cache-latest` | The XDG_CACHE_HOME `@latest` package cache is unpatched. Future promotions from this cache will revert the patch. |
| `FAIL: markers-xdg-package-cache-pinned-3.1.9` | The XDG_CACHE_HOME `@3.1.9` version-pinned package cache is unpatched. This is the path OpenCode loads when `XDG_CACHE_HOME` is active and `opencode.json` pins `@3.1.9`. |
| `FAIL: monotonic-summary-bound` | The token budget enforcement function `normalizeBoundedRangeSummary()` is missing or broken. Archived summaries may exceed the token cap. |
| `FAIL: archived-raw-stays-out-of-prompt` | The prune logic is not filtering archived raw messages. Old turns remain in the prompt, defeating the purpose of bounded retention. |
| `FAIL: persisted-frontier-state` | The sync logic is not computing `archivedBlockIds`. Block state may be inconsistent after a restart or reload. |
| `FAIL: decompress-archived-rejected` | The decompress command guard is missing. Users could accidentally decompress an archived block, which is not supported in bounded mode. |
| `FAIL: bounded-runtime-proof-metadata` | The end-to-end runtime metadata proof failed. The config may be missing `retentionMode: "bounded"` or `maxArchivedSummaryTokens`, or the runtime state objects are not receiving the patch fields. |
| `FAIL: startup probe` (`test_dcp_startup_warning.sh`) | The `opencode serve` probe crashed or exited unexpectedly before timeout. This usually indicates a startup failure unrelated to DCP. |
| `FAIL: DCP unknown-key warning detected` (`test_dcp_startup_warning.sh`) | A fresh OpenCode process emitted `Unknown keys: compress.retentionMode`, `compress.maxArchivedSummaryTokens`, or `compress.maxPayloadBytes`. The active runtime/package/cache copy is unpatched, or the running process was started before the latest patch sync. Restart OpenCode after confirming file markers pass. |

## Reapply Instructions
If the patch is lost after a DCP package update:

1. The patched source repo is at `/home/ezotoff/opencode-dynamic-context-pruning-v3.1.13/`. Cherry-pick the patch commits onto a fresh checkout of the target DCP version.
2. Build with tsup: `cd /home/ezotoff/opencode-dynamic-context-pruning-v3.1.13 && npm run build` (produces `dist/index.js` bundled with all patches).
3. Copy the bundle to the reference install: `cp dist/index.js dist/index.js.map ~/.config/opencode/node_modules/@tarquinen/opencode-dcp/dist/`.
4. Run `./install.sh --configs` from this repo to sync `dist/index.js` + `dist/index.js.map` into all native cache destinations.
5. **Restart OpenCode** so the backend reloads the patched bundle.

### Per-file source changes (TypeScript, compiled into bundle by tsup)

1. **lib/config.ts**: Add `"compress.retentionMode"` and `"compress.maxArchivedSummaryTokens"` to `VALID_CONFIG_KEYS`, and add type validation in `validateConfigTypes()`.
2. **lib/compress/state.ts**: In `applyCompressionState()`, initialize `archivedBlockIds: []` on new `byMessageId` entries, and preserve it defensively on existing entries. Set `archiveRawMessages: retentionMode === "bounded"` and `retentionMode` on block metadata.
3. **lib/compress/range.ts**: Before placeholder expansion, branch on `retentionMode === "bounded"`. In bounded mode, skip expansion and use the `COMPRESS_RANGE_BOUNDED` prompt.
4. **lib/compress/range-utils.ts**: Add `normalizeBoundedRangeSummary()` that enforces `maxArchivedSummaryTokens` on the summary text.
5. **lib/prompts/compress-range.ts**: Add the `COMPRESS_RANGE_BOUNDED` prompt constant.
6. **lib/messages/sync.ts**: In `syncCompressionBlocks()`, recompute `archivedBlockIds` alongside `activeBlockIds`. Use `anchorMessageId` presence (not `compressMessageId`) as the guard for archived block activation.
7. **lib/messages/prune.ts**: In `filterCompressedRanges()`, skip raw messages when `archivedBlockIds.length > 0` in addition to the existing `activeBlockIds.length > 0` check.
8. **lib/commands/decompress.ts**: Add an early return guard that rejects blocks with `archiveRawMessages === true`.
9. **lib/commands/recompress.ts**: Add an early return guard that rejects blocks with `archiveRawMessages === true`.
10. **lib/commands/compression-targets.ts**: Filter out blocks where `archiveRawMessages === true` from the list of recompressible targets.

Additionally, the following repo config and documentation files were updated to expose the new settings:
- `configs/opencode/dcp.jsonc` — added `retentionMode` and `maxArchivedSummaryTokens` defaults
- `README.md` — added "Bounded DCP retention" feature description
- `docs/configs.md` — documented the new DCP configuration keys

## Durable Alternative
Upstream PR #501 (https://github.com/Opencode-DCP/opencode-dynamic-context-pruning/pull/501) proposes making bounded archive mode a first-class config option. If merged, this patch could be deprecated and the upstream config keys used directly. Alternatively, DCP could expose a plugin hook for custom compression modes, which would eliminate the need for direct source patches entirely.
Status: pursued

---

# Byte-Budget Gate (opencode-dcp)

**Patch**: byte-budget gate — `pruneByByteBudget()` enforces a payload byte cap on the message list after all other DCP strategies, preventing prompt payload from exceeding the protocol limit.

**Dependency**: `@tarquinen/opencode-dcp`
**Version**: 3.1.9
**Applied**: 2026-05-16 (alongside bounded-range patch)
**Upstream issue**: https://github.com/Opencode-DCP/opencode-dynamic-context-pruning/pull/501 (same upstream effort)

## Files Patched

Six source-dist build artifacts, all under `dist/lib/`:

| File | Purpose |
|------|---------|
| `messages/byte-budget.js` | Core `pruneByByteBudget()` logic with 5 compaction passes (compact tool outputs, collapse scaffolds, collapse error loops, collapse old todo snapshots, remove old non-protected messages) |
| `messages/byte-budget.d.ts` | Type declarations for the byte-budget module |
| `hooks.js` | `createChatMessageTransformHandler()` calls `pruneByByteBudget()` at the true end of chat transforms (after dedup, purge, nudge injection) |
| `hooks.d.ts` | Type declarations for the hooks module |
| `config.js` | `maxPayloadBytes` added to `VALID_CONFIG_KEYS` and `validateConfigTypes()` |
| `config.d.ts` | Type declarations for the config module |

## Installation Mode

**Source port + tsup build + install.sh sync** (v3.1.13+)
1. Cherry-pick patch commits onto target DCP version source: `/home/ezotoff/opencode-dynamic-context-pruning-v3.1.13/`
2. Build: `npm run build` (tsup produces single bundled `dist/index.js`)
3. Copy bundle to reference: `cp dist/index.js dist/index.js.map ~/.config/opencode/node_modules/@tarquinen/opencode-dcp/dist/`
4. Sync all copies: `./install.sh --configs`

## Prerequisites

T1–T5 completed (source import, byte-budget implementation, hook integration, test harness, runtime alignment).

## Verification

Run the payload-budget regression harness:
```bash
bash tests/test_dcp_payload_budget.sh
```

Expected: 12 passed, 0 failed (3 marker checks + 9 functional cases).

Also confirm the config key is present:
```bash
grep -n "maxPayloadBytes" configs/opencode/dcp.jsonc
```

Expected: a positive integer value (currently `1802240`).

## Rollback

1. Restore `dcp.jsonc`: `git checkout -- configs/opencode/dcp.jsonc` (removes `maxPayloadBytes`)
2. Restore patched dist files: `./install.sh --configs` overwrites with previously backed-up unpatched files, or restore from `~/.ez-omo-backup/`
3. Remove byte-budget artifacts from runtime: manually delete `messages/byte-budget.js`, `messages/byte-budget.d.ts` from all three install copies

## Durable Alternative
Same upstream PR #501 tracks both bounded-retention and payload-budget features. If merged, both patches could be deprecated and controlled through upstream config keys.
Status: pursued
