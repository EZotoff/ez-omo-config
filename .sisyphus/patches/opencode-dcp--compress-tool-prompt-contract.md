---
patch_id: "opencode-dcp--compress-tool-prompt-contract"
dependency: "@tarquinen/opencode-dcp"
target_file: "dist/lib/prompts/system.js"
target_install_path: "/home/ezotoff/.config/opencode/node_modules/@tarquinen/opencode-dcp"
status: "active"
applied_date: "2026-05-17"
dep_version: "3.1.9"
upstream_issue: "none"
verification_pattern: "Do NOT announce that you will compress"
---

# Compress Tool Prompt Contract for DCP

## Problem

The DCP system prompt (`lib/prompts/system.ts`) contained an ambiguous instruction at line 28: `Before compressing, ask: _"Is this section closed enough to become summary-only right now?"_`. This wording caused models to announce their intention to compress in assistant text rather than evaluating internally and making an immediate `compress` tool call. The announcement wasted a turn and often led to the model saying it would compress without actually invoking the tool, which defeated the purpose of autonomous context management.

## Patch Description

Replaced the ambiguous "Before compressing, ask:" instruction with a strict internal-evaluation contract (lines 28-32 in `lib/prompts/system.ts`):

- `Before calling \`compress\`, evaluate internally whether the target range is closed enough to become summary-only.`
- `Do NOT announce that you will compress.`
- `If compression is appropriate, call the \`compress\` tool immediately in the same turn.`
- `If compression is not appropriate, answer normally without mentioning compression.`
- `Saying "I will compress" or similar without a \`compress\` tool call in the same turn is a failure.`

This contract forces the model to evaluate compression eligibility silently and either call `compress` immediately or continue without mentioning it. No other prompt files (nudge files, compress-range, etc.) were changed; the fix is localized to the system prompt only.

**Note on build output**: The source repo uses `tsup` which bundles JS into `dist/index.js`. To produce the individual `dist/lib/prompts/system.js` file that the installed npm package expects, run `npx tsc --noEmit false --emitDeclarationOnly false` after `npm run build`.

## Verification

Check the patched text is present in the reference install:

```bash
grep -n "Do NOT announce that you will compress" /home/ezotoff/.config/opencode/node_modules/@tarquinen/opencode-dcp/dist/lib/prompts/system.js
```

Expected: at least one match on the line containing the contract text.

**Current status**: As of patch registration (2026-05-17), the installed copies (reference, runtime, and package caches) still contain the old prompt text. The patch has been applied to the DCP source repo and built, but has not yet been synced to install targets. Run the reapply instructions below to deploy.

## Reapply Instructions

If the patch is lost after a DCP package update or needs to be deployed from source:

1. Edit source `lib/prompts/system.ts` in the DCP repo (`omo-hub/projects/opencode-dynamic-context-pruning`):
   - Replace line 28 (`Before compressing, ask: _"Is this section closed enough to become summary-only right now?"_`) with the 5-line internal-evaluation contract shown in the Patch Description above.
   - Ensure backticks around `compress` are escaped as `\`compress\`` inside the template literal to avoid TS1005 parse errors.

2. Build from source:
   ```bash
   cd omo-hub/projects/opencode-dynamic-context-pruning
   npm run build
   npx tsc --noEmit false --emitDeclarationOnly false
   ```

3. Copy `dist/lib/prompts/system.js` to the reference install:
   ```bash
   cp dist/lib/prompts/system.js ~/.config/opencode/node_modules/@tarquinen/opencode-dcp/dist/lib/prompts/system.js
   ```

4. Sync all copies via the installer:
   ```bash
   cd ~/ez-omo-config
   ./install.sh --configs
   ```

5. **Restart OpenCode** so the backend reloads the patched prompt module.

6. Verify with the grep command in the Verification section above.

## Durable Alternative

DCP already supports prompt overrides via `experimental.customPrompts: true` and override files under `~/.config/opencode/dcp-prompts/`. If this feature were extended to allow overriding the `system` prompt without editing the npm package, the direct patch would become unnecessary. Alternatively, upstream could adopt the stricter contract as the default system prompt.

Status: not-yet-pursued
