---
patch_id: "opencode-dcp--bounded-range-archive-mode"
dependency: "@tarquinen/opencode-dcp"
target_file: "dist/lib/compress/range.js"
target_install_paths:
  - "/home/ezotoff/.config/opencode/node_modules/@tarquinen/opencode-dcp"
  - "/home/ezotoff/.cache/opencode/node_modules/@tarquinen/opencode-dcp"
  - "/home/ezotoff/.cache/opencode/packages/@tarquinen/opencode-dcp@latest/node_modules/@tarquinen/opencode-dcp"
status: "active"
applied_date: "2026-04-30"
dep_version: "3.1.9 (reference/package cache), 3.1.7 (runtime cache)"
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
| 4 | `/home/ezotoff/snap/alacritty/common/.cache/opencode/node_modules/@tarquinen/opencode-dcp/` | 3.1.8 | ❌ Inactive snap runtime | Only relevant if OpenCode is launched from the snap-confined environment again |
| 5 | `/home/ezotoff/snap/alacritty/common/.cache/opencode/packages/@tarquinen/opencode-dcp@latest/` | 3.1.9 | ❌ Inactive snap package cache | Only relevant for snap-confined runtime/package flows |

**Durable local baseline in this repo:**

- Location #2 (`~/.config/...`) is the source-of-truth patched donor copy.
- `install.sh --configs` now syncs all 10 patched files from #2 into both native cache copies (#1 runtime + #3 package cache) when those destinations exist.
- If the active backend ever switches to snap-confined runtime, repeat the same sync for snap paths (#4/#5).

## Verification
```bash
# Check the ACTIVE runtime copy (native location):
grep -cE "COMPRESS_RANGE_BOUNDED|archiveRawMessages|maxArchivedSummaryTokens|retentionMode" \
  /home/ezotoff/.cache/opencode/node_modules/@tarquinen/opencode-dcp/dist/lib/config.js \
  /home/ezotoff/.cache/opencode/node_modules/@tarquinen/opencode-dcp/dist/lib/compress/range.js \
  /home/ezotoff/.cache/opencode/node_modules/@tarquinen/opencode-dcp/dist/lib/compress/state.js \
  /home/ezotoff/.cache/opencode/node_modules/@tarquinen/opencode-dcp/dist/lib/compress/range-utils.js
```
Expected: config.js ≥15, range.js ≥4, state.js ≥2, range-utils.js ≥2 matches.

```bash
# Quick: verify all 10 files are identical between reference and both native cache copies:
SRC="/home/ezotoff/.config/opencode/node_modules/@tarquinen/opencode-dcp/dist/lib"
for DEST in \
  "/home/ezotoff/.cache/opencode/node_modules/@tarquinen/opencode-dcp/dist/lib" \
  "/home/ezotoff/.cache/opencode/packages/@tarquinen/opencode-dcp@latest/node_modules/@tarquinen/opencode-dcp/dist/lib"; do
  echo "-- checking $DEST"
  for f in config.js compress/range.js compress/state.js compress/range-utils.js messages/sync.js messages/prune.js commands/decompress.js commands/recompress.js prompts/compress-range.js commands/compression-targets.js; do
    diff -q "$SRC/$f" "$DEST/$f" > /dev/null 2>&1 && echo "OK: $f" || echo "MISMATCH: $f"
  done
done
```

## Reapply Instructions
If the patch is lost after a DCP package update:

1. Apply patches to `~/.config/opencode/node_modules/@tarquinen/opencode-dcp/dist/lib/` (source of truth).
2. Run `./install.sh --configs` from this repo to sync patched files into both native cache destinations (`~/.cache/opencode/node_modules/...` and `~/.cache/opencode/packages/...`).
3. Restart OpenCode so the already-running backend reloads the patched modules.
4. If the active backend later switches to snap-confined OpenCode, manually sync the same 10 files into the snap cache/runtime copies too.

Per-file patch details:

1. **config.js**: Add `"compress.retentionMode"` and `"compress.maxArchivedSummaryTokens"` to `VALID_CONFIG_KEYS`, and add type validation in `validateConfigTypes()`.
2. **compress/state.js**: In `applyCompressionState()`, initialize `archivedBlockIds: []` on new `byMessageId` entries, and preserve it defensively on existing entries. Set `archiveRawMessages: retentionMode === "bounded"` and `retentionMode` on block metadata.
3. **compress/range.js**: Before placeholder expansion, branch on `retentionMode === "bounded"`. In bounded mode, skip expansion and use the `COMPRESS_RANGE_BOUNDED` prompt.
4. **compress/range-utils.js**: Add `normalizeBoundedRangeSummary()` that enforces `maxArchivedSummaryTokens` on the summary text.
5. **prompts/compress-range.js**: Add the `COMPRESS_RANGE_BOUNDED` prompt constant.
6. **messages/sync.js**: In `syncCompressionBlocks()`, recompute `archivedBlockIds` alongside `activeBlockIds`. Use `anchorMessageId` presence (not `compressMessageId`) as the guard for archived block activation.
7. **messages/prune.js**: In `filterCompressedRanges()`, skip raw messages when `archivedBlockIds.length > 0` in addition to the existing `activeBlockIds.length > 0` check.
8. **commands/decompress.js**: Add an early return guard that rejects blocks with `archiveRawMessages === true`.
9. **commands/recompress.js**: Add an early return guard that rejects blocks with `archiveRawMessages === true`.
10. **commands/compression-targets.js**: Filter out blocks where `archiveRawMessages === true` from the list of recompressible targets.

Additionally, the following repo config and documentation files were updated to expose the new settings:
- `configs/opencode/dcp.jsonc` — added `retentionMode` and `maxArchivedSummaryTokens` defaults
- `README.md` — added "Bounded DCP retention" feature description
- `docs/configs.md` — documented the new DCP configuration keys

## Durable Alternative
Upstream PR #501 (https://github.com/Opencode-DCP/opencode-dynamic-context-pruning/pull/501) proposes making bounded archive mode a first-class config option. If merged, this patch could be deprecated and the upstream config keys used directly. Alternatively, DCP could expose a plugin hook for custom compression modes, which would eliminate the need for direct source patches entirely.
Status: pursued
