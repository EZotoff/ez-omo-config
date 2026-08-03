---
patch_id: "opencode--link-click-wrapped-osc8"
dependency: "opencode"
# Source file the patch modifies (for reapply / human readers). NOTE: the
# verify-live-patches.sh verifier ignores target_file/target_install_path for
# opencode binary patches and resolves directly to ~/.opencode/bin/opencode.
target_file: "packages/tui/src/routes/session/index.tsx"
target_install_path: "/home/ezotoff/.opencode/bin/opencode"
source_repo: "/home/ezotoff/src/opencode"
status: "active"
applied_date: "2026-07-06"
# dep_version records the LAST VERSION WHERE RUNTIME EFFECTIVENESS WAS VERIFIED.
# Do NOT bump this just because the patch string is present in a newer binary —
# that is a pattern-presence claim, not an effectiveness claim. The v1.18.5
# binary contains the patch string but the feature regressed (see below).
dep_version: "1.17.9-local"
runtime_effective: false
runtime_effective_note: "Patch reapplied to v1.18.5 source (commit ff9df0b84) and built into the v1.18.5 binary, but the `_linkifyMarkdownChunks` monkey-patch hook is no longer reached at runtime in v1.18.5's SolidJS renderer. The patch string `__linkLabelPatch` is present in the binary (Bun preserves property keys under minification) so pattern-grep reports a false positive. Feature must be re-observed on the real TUI surface before this flag can return to true."
upstream_issue: "none"
verification_pattern: "__linkLabelPatch"
surfaces:
  - tui-interactive
---

# OpenCode TUI link rendering + click workaround for markdown links

## Current Runtime Status (2026-08-02)

**RUNTIME-INEFFECTIVE on the live v1.18.5 binary.** The `opencode run`/TUI
feature is currently regressed: `[label](file:///long/path)` renders as
`label (file:///long/path)` again, exactly as described in the Problem section.

Timeline:
- **2026-07-06**: Patch authored and verified effective on v1.17.9-local binary (Claude Code session `ses_0cb68340affe8wmwHElU79k0N3`).
- **2026-07-26**: `/update-to-latest` (session `ses_05fb42625ffeeATeeEO5BQskpY`) upgraded the live binary to v1.18.5.
- **2026-07-27**: Patch reapplied verbatim to v1.18.5 source as commit `ff9df0b84` ("patch: opencode--link-click-wrapped-osc8 v1.18.5"). The reapply touched `TextPart` in `packages/tui/src/routes/session/index.tsx` unchanged.
- **2026-07-27 (later)**: Sibling patch `opencode--turn-summary-timestamp` required an explicit rendering-path migration (commit `0ba246729`, message: "v1.18.5 rendering path changed from run/ scrollback to SolidJS"). **No equivalent migration was done for this patch** — the link-click hook was assumed still-reachable, but the SolidJS renderer change in v1.18.5 means the monkey-patched `_linkifyMarkdownChunks` method on the `<markdown>` renderable is no longer invoked on the active code path.

**Why the verifier did not catch this**: `verify-live-patches.sh` greps the
binary for `verification_pattern: "__linkLabelPatch"`. Bun minification
preserves JavaScript property keys (only local variable names are renamed),
so the pattern is present in the binary even though the surrounding code is
unreachable. The verifier also reports VERSION-DRIFT (dep_version 1.17.9-local
vs runtime 1.18.5), but that is a soft warning, not a hard gate.

**Required follow-up (out of scope of the systemic-prevention change that
updated this entry)**: redesign the patch against v1.18.5's active SolidJS
render path. The hook point is no longer `_linkifyMarkdownChunks` on the
`<markdown>` ref inside `TextPart`; identify the new chunk-pipeline entry
point in the v1.18.5 renderer before re-attempting.

## Problem

Three bugs combine to make markdown file links render poorly and wrap-break:

1. **OpenTUI conceal gap**: Conceal hides `[`/`]` brackets but NOT the URL text. `[label](file:///long/path)` renders as `label (file:///long/path)` — the long URL wraps across terminal lines.
2. **OpenTUI detectLinks gap**: After tree-sitter, only `markup.link.url` chunks get `.link`, not `markup.link.label` chunks. Labels lose linkId and are not clickable.
3. **Alacritty hyperlink_at regression** (commit 275726f): Wrapped OSC 8 URLs only resolve on the first visual line — clicking the second line opens a truncated path.

## Patch Description

Overrides `_linkifyMarkdownChunks` via a `ref` on the `<markdown>` element:

1. **Conceal URL filtering**: When conceal is ON, filters out `](url)` syntax and URL chunks so only the label renders — no wrapping.
2. **Label tagging**: Tags label chunks with `.link = { url }` so labels carry linkId and are clickable via OSC 8.

Also adds an `onMouseUp` fallback on the container `<box>` for regular clicks (linkId resolution + text-based `[label](url)` matching).

Key detail: the markdown renderable exposes `_linkifyMarkdownChunks` (not `_onChunks`) — **on v1.17.9-local**. This hook point is NOT reached on v1.18.5; see Current Runtime Status above.

## Verification

### Pattern verification (necessary, NOT sufficient)

Pattern-grep confirms the patch string is embedded in the binary, but CANNOT
confirm runtime effectiveness. Bun preserves JS property keys under
minification, so `__linkLabelPatch` survives even when the surrounding code
is unreachable. Use this only as a build-completeness check.

```bash
# Build-completeness check only:
grep -c "__linkLabelPatch" /home/ezotoff/.opencode/bin/opencode
grep -c "isUrlOrSyntax" /home/ezotoff/src/opencode/packages/tui/src/routes/session/index.tsx
```

### Runtime verification (REQUIRED — the only sufficient check)

The feature must be exercised on the real TUI surface after every build,
rebuild, or version bump. Pattern-presence is a false-positive trap.

```bash
# 1. Start the interactive TUI (NOT `opencode run` — the regression is on the
#    SolidJS interactive surface, which is a DIFFERENT renderer from run/).
opencode

# 2. In the TUI, send any prompt that causes the assistant to emit a
#    [label](file:///abs/path) markdown link. (Most agent prompts do this
#    because the clickable-links system-prompt injection is active.)

# 3. EXPECTED when patch is effective + conceal ON:
#    - Only the link label is visible (e.g. "configs/opencode/opencode.json")
#    - NO parenthesised file:// URL rendered next to the label
#    - Label is clickable (OSC 8 underline / highlight on hover)
#
# 4. REGRESSION SIGNAL (what this patch fixes):
#    - Label is followed by "(file:///abs/path)" in parens
#    - The URL wraps across terminal lines on narrow terminals
#
# 5. If you see the regression signal, the patch is RUNTIME-INEFFECTIVE even
#    if `grep __linkLabelPatch` returns 1. Update runtime_effective: false in
#    this entry and file a follow-up to redesign the hook point.
```

## Reapply Instructions

1. **Identify the ACTIVE rendering hook point in the TARGET version first.**
   Do NOT blindly re-edit `TextPart._linkifyMarkdownChunks` — verify the
   method is still invoked on the active SolidJS render path in that version.
   On v1.18.5 it is NOT; a new hook point must be found.
2. In `packages/tui/src/routes/session/index.tsx`, add `import open from "open"`.
3. In `TextPart` (or its successor component), add `const renderer = useRenderer()`.
4. Add `onMouseUp` on `<box>`: linkId resolution + text fallback.
5. Add `ref` on `<markdown>`: patch the renderable's chunk hook to tag labels
   and filter URLs when concealing.
6. Rebuild, swap binary, restart services.
7. **Run the Runtime Verification steps above BEFORE claiming the patch is
   effective.** Set `runtime_effective: true` only after observing the
   expected TUI behaviour with your own eyes.

## Durable Alternative

1. OpenTUI: fix conceal to hide full link syntax, fix detectLinks to tag labels.
2. Alacritty: revert hyperlink_at regression from commit 275726f.
3. Switch terminal (kitty, WezTerm, Ghostty).

Status: blocked-by-upstream
