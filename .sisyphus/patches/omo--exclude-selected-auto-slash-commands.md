---
patch_id: "omo--exclude-selected-auto-slash-commands"
dependency: "oh-my-openagent"
target_file: "src/hooks/auto-slash-command/constants.ts"
target_install_path: "/home/ezotoff/omo-hub/projects/oh-my-openagent"
status: "active"
applied_date: "2026-05-14"
dep_version: "current"
upstream_issue: "none"
verification_pattern: "\"vera\"|\"gad-experiment\""
---

# Exclude Selected Auto-Slash Commands (vera, gad-experiment)

## Problem
The auto-slash-command hook exposed `/vera` and `/gad-experiment` as user-facing slash commands, causing UI clutter and accidental invocation in chat. These commands are niche/power-user skills that should remain programmatically available to agents (via `mergedSkills`) but not appear as user-typable slash completions. Simply disabling the skills via config would break agent access.

## Patch Description
Added `vera` and `gad-experiment` to the existing `EXCLUDED_COMMANDS` set, and added an exclusion guard to the `command.execute.before` handler (which previously bypassed the detector exclusion path).

**Files changed (2):**
- `src/hooks/auto-slash-command/constants.ts` — Added `"vera"` and `"gad-experiment"` to `EXCLUDED_COMMANDS` Set.
- `src/hooks/auto-slash-command/hook.ts` — Imported `EXCLUDED_COMMANDS` from constants; added a `command.execute.before` guard that returns early if `input.command.toLowerCase()` is in the excluded set, before constructing a `parsed` object and calling `executeSlashCommand`.

**Before (hook.ts):**
```ts
const parsed = {
  command: input.command,
  args: input.arguments || "",
  raw: `/${input.command}${input.arguments ? " " + input.arguments : ""}`,
}
```

**After (hook.ts):**
```ts
if (EXCLUDED_COMMANDS.has(input.command.toLowerCase())) {
  log(`[auto-slash-command] Skipping excluded command: /${input.command}`, ...)
  return
}
const parsed = { ... }
```

The `chat.message` path already respected exclusions via `detectSlashCommand` (which calls `isExcludedCommand` in the detector). The `command.execute.before` path was the gap.

## Verification
```bash
# Verify both commands are in EXCLUDED_COMMANDS
grep -E '"(vera|gad-experiment)"' /home/ezotoff/omo-hub/projects/oh-my-openagent/src/hooks/auto-slash-command/constants.ts

# Verify command.execute.before has the exclusion guard
grep -n 'EXCLUDED_COMMANDS.has' /home/ezotoff/omo-hub/projects/oh-my-openagent/src/hooks/auto-slash-command/hook.ts

# Verify EXCLUDED_COMMANDS is imported in hook.ts
grep -n 'EXCLUDED_COMMANDS' /home/ezotoff/omo-hub/projects/oh-my-openagent/src/hooks/auto-slash-command/hook.ts

# Confirm frontend-ui-ux is NOT excluded
grep -c '"frontend-ui-ux"' /home/ezotoff/omo-hub/projects/oh-my-openagent/src/hooks/auto-slash-command/constants.ts | grep -q "^0$" && echo "frontend-ui-ux NOT excluded — PASS"
```

## Reapply Instructions
1. In `src/hooks/auto-slash-command/constants.ts`, add `"vera"` and `"gad-experiment"` to the `EXCLUDED_COMMANDS` Set:
   ```ts
   export const EXCLUDED_COMMANDS = new Set([
     "ralph-loop",
     "cancel-ralph",
     "ulw-loop",
     "vera",
     "gad-experiment",
   ])
   ```
2. In `src/hooks/auto-slash-command/hook.ts`:
   a. Add `EXCLUDED_COMMANDS` to the import from `"./constants"`
   b. In the `command.execute.before` handler, after the dedup check and before the `parsed` construction, add:
   ```ts
   if (EXCLUDED_COMMANDS.has(input.command.toLowerCase())) {
     log(`[auto-slash-command] Skipping excluded command: /${input.command}`, {
       sessionID: input.sessionID,
     })
     return
   }
   ```

## Durable Alternative
An upstream configurable/metadata-driven slash exposure policy in oh-my-openagent — a `slashExpose: boolean` field on skill definitions that controls whether a skill appears as a user-facing slash command. This would replace hardcoded exclusions with per-skill opt-in/opt-out.
Pursued: not-yet-pursued — no upstream support for per-skill slash visibility exists yet.

**Note:** This patch preserves agent access to `vera` by blocking slash exposure only, rather than using `skills.disable` (which would remove `vera` from `mergedSkills` entirely, breaking agents that rely on it).
