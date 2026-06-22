---
patch_id: "opencode-dcp--compress-tool-prompt-contract"
dependency: "@tarquinen/opencode-dcp"
target_file: "dist/index.js"
target_install_path: "/home/ezotoff/.config/opencode/node_modules/@tarquinen/opencode-dcp"
status: "active"
applied_date: "2026-05-17"
dep_version: "3.1.13"
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

**Note on build output (v3.1.13+)**: DCP uses `tsup` which bundles all JS into a single `dist/index.js`. The patched prompt text is compiled into the bundle at build time.

## Verification

Check the patched text is present in the reference install:

```bash
grep -n "Do NOT announce that you will compress" /home/ezotoff/.config/opencode/node_modules/@tarquinen/opencode-dcp/dist/lib/prompts/system.js
```

Expected: at least one match on the line containing the contract text.

**Current status**: As of patch registration (2026-05-17), the installed copies (reference, runtime, and package caches) still contain the old prompt text. The patch has been applied to the DCP source repo and built, but has not yet been synced to install targets. Run the reapply instructions below to deploy.

## Reapply Instructions

If the patch is lost after a DCP package update or needs to be deployed from source:

1. Edit source `lib/prompts/system.ts` in the patched source repo (`/home/ezotoff/opencode-dynamic-context-pruning-v3.1.13`):
   - Replace line 28 (`Before compressing, ask: _"Is this section closed enough to become summary-only right now?"_`) with the 5-line internal-evaluation contract shown in the Patch Description above.
   - Ensure backticks around `compress` are escaped as `\`compress\`` inside the template literal to avoid TS1005 parse errors.

2. Build with tsup:
   ```bash
   cd /home/ezotoff/opencode-dynamic-context-pruning-v3.1.13
   npm run build
   ```

3. Copy `dist/index.js` and `dist/index.js.map` to the reference install:
   ```bash
   cp dist/index.js dist/index.js.map ~/.config/opencode/node_modules/@tarquinen/opencode-dcp/dist/
   ```

4. Sync all copies via the installer:
   ```bash
   cd ~/ez-omo-config
   ./install.sh --configs
   ```

5. **Restart OpenCode** so the backend reloads the patched bundle.

6. Verify with: `grep -c "Do NOT announce that you will compress" ~/.config/opencode/node_modules/@tarquinen/opencode-dcp/dist/index.js`

## Durable Alternative

DCP already supports prompt overrides via `experimental.customPrompts: true` and override files under `~/.config/opencode/dcp-prompts/`. If this feature were extended to allow overriding the `system` prompt without editing the npm package, the direct patch would become unnecessary. Alternatively, upstream could adopt the stricter contract as the default system prompt.

Status: not-yet-pursued
