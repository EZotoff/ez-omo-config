---
patch_id: "omo--clean-agent-display-names"
dependency: "oh-my-openagent"
target_file: "dist/index.js"
target_install_path: "/home/ezotoff/.cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent"
status: "active"
applied_date: "2026-04-18"
dep_version: "current"
upstream_issue: "none"
verification_pattern: 'sisyphus: "Sisyphus",'
---

# Clean Agent Display Names

## Problem
Oh-My-OpenAgent hardcodes agent display names with role suffixes (e.g., "Sisyphus - Ultraworker", "Atlas - Plan Executor"). These suffixes are redundant — the user already knows what each agent does. The TUI shows these names when cycling agents with Tab, making the display unnecessarily verbose.

## Patch Description
Stripped role suffixes from all top-level agent display names in `AGENT_DISPLAY_NAMES`:

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

Also added the old "- Role" format entries to `LEGACY_DISPLAY_NAMES` for backward compatibility.

Applied to:
- `dist/index.js` (main plugin)
- `dist/cli/index.js` (CLI entry)
- All cache copies under `~/.cache/opencode/` and `~/snap/alacritty/common/.cache/opencode/`

## Verification
```bash
grep -n 'sisyphus: "Sisyphus",' /home/ezotoff/.cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent/dist/index.js
```
If output contains `"Sisyphus",` (no suffix) — patch is applied.
If output contains `"Sisyphus - Ultraworker"` or `"Sisyphus (Ultraworker)"` — patch is stale.

## Reapply Instructions
1. Find all oh-my-openagent dist files:
   ```bash
   find ~/.cache/opencode ~/snap/alacritty/common/.cache/opencode -path '*/oh-my-open*/dist/index.js' -o -path '*/oh-my-open*/dist/cli/index.js' 2>/dev/null
   ```
2. For each file, run sed to strip suffixes:
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
3. For `dist/index.js` only: also update `LEGACY_DISPLAY_NAMES` to add old format entries:
   ```bash
   "sisyphus - ultraworker": "sisyphus",
   "hephaestus - deep agent": "hephaestus",
   "prometheus - plan builder": "prometheus",
   "atlas - plan executor": "atlas",
   "metis - plan consultant": "metis",
   "momus - plan critic": "momus",
   "athena - council": "athena",
   "athena-junior - council": "athena-junior"
   ```
4. Restart OpenCode.

## Durable Alternative
Upstream could add a config-based display name override in `oh-my-openagent.json` (e.g., `"display_name"` field per agent). This would eliminate the need for patching.
Status: not-yet-pursued
