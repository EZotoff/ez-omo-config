---
patch_id: "omo--auto-slash-command-duplicate-user-args"
dependency: "oh-my-openagent"
target_file: "dist/index.js"
target_install_path: "/home/ezotoff/oh-my-openagent-v4.12.1"
status: "active"
applied_date: "2026-07-06"
dep_version: "4.12.1"
upstream_issue: "none"
verification_pattern: "\\*\\*User Arguments\\*\\*"
---

# OMO auto-slash-command duplicate user arguments

## Problem

The `formatCommandTemplate` function in OMO's auto-slash-command executor inserted the user's slash-command arguments into the rendered prompt **twice**:

1. In the metadata header as `**User Arguments**: ${args}`
2. At the bottom as a `## User Request` section after the command instructions

This affected every skill-based slash command (e.g., `/register-retry-error`, `/deployment`, `/wisdom`) — the user's typed arguments appeared redundantly in the final prompt sent to the LLM.

## Patch Description

Removed the duplicate footer insertion (`## User Request` section) from `formatCommandTemplate` in:
- **Source**: `src/hooks/auto-slash-command/executor.ts` (candidate repo v4.3.1+)
- **Dist**: `dist/index.js` (installed v4.12.1, function at ~line 96498)

The header `**User Arguments**: ${args}` is retained, consistent with `formatLoadedCommand` in `command-output-formatter.ts` which uses `**Arguments**: ${userMessage}` in the header only.

## Verification

Positive check — retained header exists:

```bash
grep -n 'User Arguments' /home/ezotoff/oh-my-openagent-v4.12.1/dist/index.js && echo "APPLIED" || echo "STALE"
```

Negative check — duplicate footer removed (adjacency test):

```bash
# Patched: substitutedContent.trim() is immediately followed by return sections.join
grep -A1 'substitutedContent\.trim' /home/ezotoff/oh-my-openagent-v4.12.1/dist/index.js | grep -q 'return sections\.join' && echo "APPLIED" || echo "STALE"
```

Also confirm `## User Request` is globally absent from the dist:

```bash
test $(grep -c '## User Request' /home/ezotoff/oh-my-openagent-v4.12.1/dist/index.js) -eq 0 && echo "APPLIED" || echo "STALE"
```

Source repo check:

```bash
test $(grep -c '## User Request' /home/ezotoff/oh-my-openagent-candidate/src/hooks/auto-slash-command/executor.ts) -eq 0 && echo "APPLIED" || echo "STALE"
```

## Reapply Instructions

1. Open `dist/index.js` in the installed OMO directory (`/home/ezotoff/oh-my-openagent-v4.12.1/dist/index.js`)
2. Find the function `formatCommandTemplate` (search for `async function formatCommandTemplate`)
3. After the line `sections.push(substitutedContent.trim());`, remove the following block:
   ```javascript
   if (args) {
     sections.push(`\n\n---\n`);
     sections.push(`## User Request\n`);
     sections.push(args);
   }
   ```
4. Run `node --check dist/index.js` to verify syntax
5. Restart OpenCode for the change to take effect

For the source repo (`oh-my-openagent-candidate`), apply the same removal in `src/hooks/auto-slash-command/executor.ts` after line `sections.push(substitutedContent.trim())`.

## Durable Alternative

Evaluated alternatives before direct patching:

1. **Plugin/hook** — Not viable. The `formatCommandTemplate` function runs inside OMO's `auto-slash-command` executor, which itself operates at the `command.execute.before` hook layer. Adding a second hook to strip the duplicate would create fragile hook-to-hook coupling with ordering dependencies.
2. **Configuration** — Not viable. The argument insertion logic is hardcoded in the function body; no config key controls it.
3. **Upstream fix** — VIABLE and preferred. The duplicate insertion is a straightforward bug: the same `args` value is pushed in both the metadata header (`**User Arguments**`) and a footer section (`## User Request`). Removing either one is a one-line fix. Should be reported as a bug to the OMO upstream repository. The `formatLoadedCommand` function in `command-output-formatter.ts` already uses header-only insertion, providing precedent for the correct pattern.
4. **Direct patch** — Applied as interim measure until upstream fix is shipped.

Status: not-yet-pursued (upstream issue not yet filed)
