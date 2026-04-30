---
patch_id: "omo--clean-agent-display-names"
dependency: "oh-my-openagent"
target_file: "src/shared/agent-display-names.ts, src/features/claude-code-session-state/state.ts, src/cli/run/event-handlers.ts"
target_install_path: "/home/ezotoff/omo-hub/projects/oh-my-openagent"
status: "active"
applied_date: "2026-04-30"
dep_version: "current"
upstream_issue: "none"
verification_pattern: 'normalizeAgentForPrompt|getAgentDisplayName\(configKey\)'
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
grep -E 'normalizeAgentForPrompt|getAgentDisplayName\(configKey\)' \
  /home/ezotoff/omo-hub/projects/oh-my-openagent/src/shared/agent-display-names.ts \
  /home/ezotoff/omo-hub/projects/oh-my-openagent/src/features/claude-code-session-state/state.ts \
  /home/ezotoff/omo-hub/projects/oh-my-openagent/src/cli/run/event-handlers.ts
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
   If it points to `file:///home/ezotoff/omo-hub/projects/oh-my-openagent`, edit the source files there directly.

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
   cd /home/ezotoff/omo-hub/projects/oh-my-openagent
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
