---
patch_id: "omo--clean-agent-display-names"
dependency: "oh-my-openagent"
target_file: "packages/omo-opencode/src/shared/agent-display-names.ts, packages/omo-opencode/src/features/claude-code-session-state/state.ts, packages/omo-opencode/src/cli/run/event-message-handlers.ts"
target_install_path: "/home/ezotoff/oh-my-openagent-v4.12.1"
status: "active"
applied_date: "2026-04-30"
dep_version: "4.12.1"
upstream_issue: "none"
verification_pattern: "sisyphus: \"Sisyphus\""
post_update_status: "reapply_required"
note: "v4.12.1 ships source-only (no dist/ for omo-opencode). Patch now targets source files + bun build. event-handlers.ts refactored to 4-line barrel; handleMessageUpdated moved to event-message-handlers.ts (new file). Previous post_update_status 'unaffected' was FALSE — v4.12.1 source still has all 8 verbose display names."
---

# Clean Agent Display Names

## Problem

Oh-My-OpenAgent displayed verbose agent names with role suffixes (e.g., `"Sisyphus - Ultraworker"`) and injected invisible zero-width sort-prefix characters into runtime labels. Early attempts to fix this by patching cache bundle copies at `~/.cache/opencode/packages/oh-my-openagent@latest/...` produced false positives. The patches appeared intact in the cached bundles, but the live TUI still showed suffixed names because OpenCode loads the plugin from `file:///home/ezotoff/omo-hub/projects/oh-my-openagent`, not from the cache.

## Patch Description

The decisive fix was applied at the source level in `/home/ezotoff/omo-hub/projects/oh-my-openagent`. Three files were changed:

### Source file 1: src/shared/agent-display-names.ts

- Plain runtime-facing display names in `AGENT_DISPLAY_NAMES` (e.g., `"Sisyphus"`, `"Atlas"`, `"Hephaestus"`).
- `getAgentRuntimeName()` and `getAgentListDisplayName()` now return plain `getAgentDisplayName(configKey)` without zero-width prefix injection.
- `LEGACY_DISPLAY_NAMES` expanded to include both dashed and parenthesized historical forms for backward compatibility.
- New `normalizeAgentForPrompt()` function canonicalizes any known legacy label to its plain display name.

### Source file 2: src/features/claude-code-session-state/state.ts

- `normalizeStoredAgentName()` now calls `normalizeAgentForPrompt()` to canonicalize legacy labels, not just strip invisible characters.
- Session agent storage resolves legacy names like `"Sisyphus - Ultraworker"` to `"Sisyphus"`.

### Source file 3: src/cli/run/event-handlers.ts

- `handleMessageUpdated()` normalizes incoming `props.info.agent` through `normalizeAgentForPrompt()` before assigning `state.currentAgent` and rendering headers.

### Backward compatibility notes

- `LEGACY_DISPLAY_NAMES` preserves mappings for dashed/parenthesized legacy labels (e.g., `"sisyphus - ultraworker"`, `"atlas (plan executor)"`).
- `REVERSE_DISPLAY_NAMES` auto-generates from clean `AGENT_DISPLAY_NAMES`.
- Zero-width character stripping remains in `stripAgentListSortPrefix()` for defense in depth.

## Verification

This patch is verified at the source level. The cache bundles are secondary artifacts produced by `bun run build`.

```bash
# Verify all three source files contain the fix patterns
OMO_SOURCE_DIR="${OMO_SOURCE_DIR:-/home/ezotoff/oh-my-openagent}"
grep -E 'normalizeAgentForPrompt|getAgentDisplayName\(configKey\)' \
  "$OMO_SOURCE_DIR/src/shared/agent-display-names.ts" \
  "$OMO_SOURCE_DIR/src/features/claude-code-session-state/state.ts" \
  "$OMO_SOURCE_DIR/src/cli/run/event-handlers.ts"
```

Expected: matches in all three files. `agent-display-names.ts` shows `return getAgentDisplayName(configKey)`; `state.ts` shows `normalizeAgentForPrompt`; `event-handlers.ts` shows `normalizeAgentForPrompt`.

### Runtime QA evidence

After rebuilding (`bun run build`) and restarting `opencode serve`, a fresh TUI session showed plain labels:
- `Sisyphus · ...` on initial load
- `Atlas · ...` after cycling agents with Tab

This confirms the live runtime loads from the local source, not stale cache bundles.

## Reapply Instructions

If the patch is lost after a source update or dependency refresh:

1. Verify the live load path in OpenCode config:
   ```bash
   grep 'oh-my-openagent' ~/.config/opencode/opencode.json
   ```
   If it points to `file:///home/ezotoff/oh-my-openagent`, edit the source files there directly.

2. In `src/shared/agent-display-names.ts`:
   - Ensure `AGENT_DISPLAY_NAMES` contains plain names only.
   - Ensure `getAgentRuntimeName()` returns `getAgentDisplayName(configKey)` without prefix.
   - Ensure `normalizeAgentForPrompt()` canonicalizes known legacy labels.

3. In `src/features/claude-code-session-state/state.ts`:
   - Ensure `normalizeStoredAgentName()` calls `normalizeAgentForPrompt()`.

4. In `src/cli/run/event-handlers.ts`:
   - Ensure `handleMessageUpdated()` sanitizes `props.info.agent` via `normalizeAgentForPrompt()`.

5. Rebuild the project:
   ```bash
    cd "${OMO_SOURCE_DIR:-/home/ezotoff/oh-my-openagent}"
   bun run build
   ```

6. Restart OpenCode for changes to take effect.

### Historical note on cache-bundle patching

Earlier iterations (2026-04-18) patched only bundle copies under `~/.cache/opencode/packages/oh-my-openagent@latest/...` and `~/snap/alacritty/common/.cache/...`. This was insufficient because the plugin `file://` URL in `opencode.json` bypassed the cache. Those bundle edits are now considered stale. Do not reapply them.

## Durable Alternative

Upstream could:
- Add a config-based display name override in `oh-my-openagent.json` (e.g., `"display_name"` field per agent).
- Remove the sort-prefix mechanism entirely or make it opt-in.
- Use plain names as defaults with role descriptions as tooltips or metadata.

Status: not-yet-pursued

## Task 11 Triage (2026-05-23)

- Classification: `unaffected`
- Guard result: `allowed` (`source_plane`).
- Verification marker is present in all target source files.
- Reapply instructions remain valid for OMO v4.3.1 baseline.

## Runtime Cache Reapply (2026-05-23)

After refreshing the active XDG OpenCode package cache to `oh-my-openagent@4.4.0`, OMO again exposed the primary agent as `"Sisyphus - ultraworker"`. The active runtime path is no longer the local source checkout; it is:

```text
/home/ezotoff/snap/alacritty/common/.cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent
```

The local reapply changed only the bundled display-name map in:

```text
dist/index.js
dist/cli/index.js
```

Before:

```js
sisyphus: "Sisyphus - ultraworker"
```

After:

```js
sisyphus: "Sisyphus"
```

Verification:

```bash
grep -E 'sisyphus: "Sisyphus"'   /home/ezotoff/snap/alacritty/common/.cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent/dist/index.js   /home/ezotoff/snap/alacritty/common/.cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent/dist/cli/index.js
opencode debug agent Sisyphus
```

Expected: both bundles contain `sisyphus: "Sisyphus"`, and `opencode debug agent Sisyphus` resolves the primary agent with model `openai/gpt-5.5`.

