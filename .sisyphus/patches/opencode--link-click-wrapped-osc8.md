---
patch_id: "opencode--link-click-wrapped-osc8"
dependency: "opencode"
target_file: "packages/tui/src/routes/session/index.tsx"
target_install_path: "/home/ezotoff/src/opencode"
status: "active"
applied_date: "2026-07-06"
dep_version: "1.17.9-local"
upstream_issue: "none"
verification_pattern: "__linkLabelPatch"
---

# OpenCode TUI link rendering + click workaround for markdown links

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

Key detail: the markdown renderable exposes `_linkifyMarkdownChunks` (not `_onChunks`).

## Verification

```bash
grep -n "__linkLabelPatch" /home/ezotoff/src/opencode/packages/tui/src/routes/session/index.tsx
grep -n "isUrlOrSyntax" /home/ezotoff/src/opencode/packages/tui/src/routes/session/index.tsx
```

Runtime: with conceal ON, `[label](url)` renders as just `label` (clickable, no URL visible).

## Reapply Instructions

1. In `packages/tui/src/routes/session/index.tsx`, add `import open from "open"`.
2. In `TextPart`, add `const renderer = useRenderer()`.
3. Add `onMouseUp` on `<box>`: linkId resolution + text fallback.
4. Add `ref` on `<markdown>`: patch `el._linkifyMarkdownChunks` to tag labels and filter URLs when concealing.
5. Rebuild, swap binary, restart services.

## Durable Alternative

1. OpenTUI: fix conceal to hide full link syntax, fix detectLinks to tag labels.
2. Alacritty: revert hyperlink_at regression from commit 275726f.
3. Switch terminal (kitty, WezTerm, Ghostty).

Status: blocked-by-upstream
