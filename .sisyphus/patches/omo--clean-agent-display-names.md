---
patch_id: "omo--clean-agent-display-names"
dependency: "oh-my-openagent"
target_file: "dist/index.js, dist/cli/index.js"
target_install_path: "/home/ezotoff/.cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent"
status: "active"
applied_date: "2026-04-18"
dep_version: "current"
upstream_issue: "none"
verification_pattern: 'return getAgentDisplayName\(configKey\);'
---

# Clean Agent Display Names

## Problem
Oh-My-OpenAgent had two display-name issues in its bundled `dist/index.js` and `dist/cli/index.js`:

1. **Verbose role suffixes**: Agent display names included redundant role descriptions (e.g., `"Sisyphus - Ultraworker"`, `"Atlas - Plan Executor"`). The TUI shows these names when cycling agents with Tab, making the display unnecessarily verbose.

2. **Zero-width sort-prefix injection**: `getAgentRuntimeName()` prepended invisible zero-width characters from `AGENT_LIST_SORT_PREFIXES` to agent names. These characters (`\u200B`, `\u200C`, `\u200D`, `\uFEFF`) are invisible in most contexts but cause issues in clipboard copy/paste, terminal selection, and string comparison. The function was structured as:
   ```
   Before: return (AGENT_LIST_SORT_PREFIXES[configKey] || "") + displayName;
   After:  return getAgentDisplayName(configKey);
   ```

## Patch Description
Two aspects were repaired across all active `@latest` bundle copies:

### Aspect 1: Plain display names
Stripped role suffixes from all top-level agent entries in `AGENT_DISPLAY_NAMES`:

| Before | After |
|--------|-------|
| `"Sisyphus - Ultraworker"` | `"Sisyphus"` |
| `"Hephaestus - Deep Agent"` | `"Hephaestus"` |
| `"Prometheus - Plan Builder"` | `"Prometheus"` |
| `"Atlas - Plan Executor"` | `"Atlas"` |
| `"Metis - Plan Consultant"` | `"Metis"` |
| `"Momus - Plan Critic"` | `"Momus"` |
| `"Athena - Council"` | `"Athena"` |
| `"Athena-Junior - Council"` | `"Athena-Junior"` |

### Aspect 2: Sort-prefix neutralization
- `getAgentRuntimeName()` now delegates directly to `getAgentDisplayName()` instead of prepending sort-prefix characters:
  ```
  Before: getAgentRuntimeName(configKey) { return (AGENT_LIST_SORT_PREFIXES[configKey] || "") + getAgentDisplayName(configKey); }
  After:  getAgentRuntimeName(configKey) { return getAgentDisplayName(configKey); }
  ```
- `AGENT_LIST_SORT_PREFIXES` is set to an empty object `{}` in both files, neutralizing any future additions.

### Scope notes
- Old suffixed names (`"sisyphus (ultraworker)"`, etc.) remain in `LEGACY_DISPLAY_NAMES` as backward-compatible alias mappings. This is intentional — these maps translate legacy input names to current config keys and do not appear in the TUI.
- `REVERSE_DISPLAY_NAMES` is auto-generated from `AGENT_DISPLAY_NAMES` and therefore contains only clean plain names.

### Applied to (4 active files)
- `/home/ezotoff/.cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent/dist/index.js`
- `/home/ezotoff/.cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent/dist/cli/index.js`
- `/home/ezotoff/snap/alacritty/common/.cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent/dist/index.js`
- `/home/ezotoff/snap/alacritty/common/.cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent/dist/cli/index.js`

## Verification

This patch has **two verification patterns** — both must pass for the patch to be intact:

### Verification A: Sort-prefix neutralization (authoritative)
```bash
# Check that getAgentRuntimeName() delegates to getAgentDisplayName() without prefix
grep -n 'return getAgentDisplayName(configKey);' \
  /home/ezotoff/.cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent/dist/index.js \
  /home/ezotoff/.cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent/dist/cli/index.js \
  /home/ezotoff/snap/alacritty/common/.cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent/dist/index.js \
  /home/ezotoff/snap/alacritty/common/.cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent/dist/cli/index.js
```
Expected: 4 matches (one per file). If any file lacks this pattern, the sort-prefix fix is stale in that file.

### Verification B: Plain display names
```bash
# Check that AGENT_DISPLAY_NAMES entries are plain (no role suffix)
grep -n 'sisyphus: "Sisyphus"' \
  /home/ezotoff/.cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent/dist/index.js \
  /home/ezotoff/.cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent/dist/cli/index.js \
  /home/ezotoff/snap/alacritty/common/.cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent/dist/index.js \
  /home/ezotoff/snap/alacritty/common/.cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent/dist/cli/index.js
```
Expected: 4 matches. If any file shows `"Sisyphus - Ultraworker"` or `"Sisyphus (Ultraworker)"`, display names are stale in that file.

### Verification C: AGENT_LIST_SORT_PREFIXES is empty
```bash
# Check that AGENT_LIST_SORT_PREFIXES is an empty object
grep -A1 'AGENT_LIST_SORT_PREFIXES = {' \
  /home/ezotoff/.cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent/dist/index.js \
  /home/ezotoff/.cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent/dist/cli/index.js \
  /home/ezotoff/snap/alacritty/common/.cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent/dist/index.js \
  /home/ezotoff/snap/alacritty/common/.cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent/dist/cli/index.js
```
Expected: Each file shows `AGENT_LIST_SORT_PREFIXES = {` followed immediately by `};` on the next line (empty object).

**False-positive warning**: The old single-file check (`grep 'sisyphus: "Sisyphus"' dist/index.js`) would pass even if `dist/cli/index.js` was stale. Always verify all 4 active files.

## Reapply Instructions

If the patch is lost after an OMO update:

1. Find all active oh-my-openagent bundle files:
   ```bash
   find ~/.cache/opencode ~/snap/alacritty/common/.cache/opencode \
     -path '*/oh-my-openagent@latest/node_modules/oh-my-openagent/dist/index.js' -o \
     -path '*/oh-my-openagent@latest/node_modules/oh-my-openagent/dist/cli/index.js' \
     2>/dev/null
   ```

2. For each `dist/index.js` and `dist/cli/index.js`, apply both fixes:

   **Fix A — Neutralize sort-prefix in getAgentRuntimeName():**
   ```bash
   # Replace the prefix-prepending version with a direct delegation
   sed -i 's/return (AGENT_LIST_SORT_PREFIXES\[configKey\] || "") + getAgentDisplayName(configKey);/return getAgentDisplayName(configKey);/' <file>
   ```

   **Fix B — Strip role suffixes from AGENT_DISPLAY_NAMES:**
   ```bash
   sed -i \
     -e 's/"Sisyphus - Ultraworker"/"Sisyphus"/g' \
     -e 's/"Sisyphus (Ultraworker)"/"Sisyphus"/g' \
     -e 's/"Hephaestus - Deep Agent"/"Hephaestus"/g' \
     -e 's/"Hephaestus (Deep Agent)"/"Hephaestus"/g' \
     -e 's/"Prometheus - Plan Builder"/"Prometheus"/g' \
     -e 's/"Prometheus (Plan Builder)"/"Prometheus"/g' \
     -e 's/"Atlas - Plan Executor"/"Atlas"/g' \
     -e 's/"Atlas (Plan Executor)"/"Atlas"/g' \
     -e 's/"Metis - Plan Consultant"/"Metis"/g' \
     -e 's/"Metis (Plan Consultant)"/"Metis"/g' \
     -e 's/"Momus - Plan Critic"/"Momus"/g' \
     -e 's/"Momus (Plan Critic)"/"Momus"/g' \
     -e 's/"Athena - Council"/"Athena"/g' \
     -e 's/"Athena (Council)"/"Athena"/g' \
     -e 's/"Athena-Junior - Council"/"Athena-Junior"/g' \
     -e 's/"Athena-Junior (Council)"/"Athena-Junior"/g' \
     <file>
   ```

   **Fix C — Empty AGENT_LIST_SORT_PREFIXES:**
   ```bash
   # Replace the sort-prefix entries with an empty object
   # Find the AGENT_LIST_SORT_PREFIXES block and empty it
   # The block looks like: AGENT_LIST_SORT_PREFIXES = { "\u200B...": "agent-key", ... };
   sed -i '/AGENT_LIST_SORT_PREFIXES = {/,/};/c\  AGENT_LIST_SORT_PREFIXES = {\n  };' <file>
   ```

3. Restart OpenCode for changes to take effect.

## Durable Alternative
Upstream could:
- Add a config-based display name override in `oh-my-openagent.json` (e.g., `"display_name"` field per agent)
- Remove the sort-prefix mechanism entirely or make it opt-in
- Use plain names as defaults with role descriptions as tooltips/metadata

Status: not-yet-pursued
