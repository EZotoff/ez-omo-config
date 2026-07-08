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

# OpenCode TUI link-click workaround for wrapped OSC 8 hyperlinks

## Problem
File links (`[label](file:///abs/path)`) in assistant markdown messages render via OpenTUI's native `.link` chunk mechanism, which emits OSC 8 terminal hyperlinks. Two bugs combine to make wrapped links only clickable on their first visual line:

1. **OpenTUI detectLinks gap**: After tree-sitter highlighting replaces initial streaming chunks, `detectLinks` only re-tags `markup.link.url` chunks (the concealed URL) with `.link`, not `markup.link.label` chunks (the visible label). Label cells lose their linkId, so OSC 8 is no longer emitted for them. Ctrl+Click on the visible label text stops working entirely after tree-sitter completes.

2. **Alacritty hyperlink_at regression**: Even when label cells retain linkId (during the streaming window before tree-sitter), Alacritty's `hyperlink_at` (`alacritty/src/display/hint.rs:425`) only returns contiguous cells within a single row — a regression from commit `275726f` (March 2024). Ctrl+Click on the second+ visual line of a wrapped OSC 8 region opens nothing. Not fixed in any Alacritty version through 0.18.0-dev. Other terminals (kitty, WezTerm, Ghostty, iTerm2) handle multi-line OSC 8 correctly.

## Patch Description
Two mechanisms in `packages/tui/src/routes/session/index.tsx`, both in the `TextPart` component:

**Primary — `_onChunks` override (fixes Ctrl+Click on wrapped lines):**
A `ref` callback on the `<markdown>` element patches `_onChunks` to also tag `markup.link.label` chunks with their corresponding URL after `detectLinks` runs. This preserves linkId on all label cells so OSC 8 covers every visual line, making terminal-level hyperlink click resolution work regardless of wrapping. Guard: `el.__linkLabelPatch` prevents double-patching.

**Secondary — `onMouseUp` handler (fallback for regular clicks):**
An `onMouseUp` handler on the `<box>` container reads the cell linkId from `renderer.currentRenderBuffer.buffers.attributes` at the click position. If linkId > 0, resolves the URL via `(renderer as any).lib.linkGetUrl(lid)`. If linkId is absent, falls back to parsing `[label](url)` patterns from the markdown content and matching the clicked line text against known labels. Skips when text selection is active.

84 insertions, 1 deletion. Purely additive — no behavior change for non-link cells.

## Verification
```bash
# Primary fix: _onChunks patch marker
grep -n "__linkLabelPatch" \
  /home/ezotoff/src/opencode/packages/tui/src/routes/session/index.tsx

# Secondary fix: onMouseUp handler present
grep -n "buffers\.attributes\[idx\] >>> 8" \
  /home/ezotoff/src/opencode/packages/tui/src/routes/session/index.tsx

# Import
grep -n 'import open from "open"' \
  /home/ezotoff/src/opencode/packages/tui/src/routes/session/index.tsx
```

Binary verification:
```bash
grep -a -o '__linkLabelPatch' ~/.opencode/bin/opencode | wc -l  # expect 2
grep -a -o 'linkGetUrl' ~/.opencode/bin/opencode | wc -l        # expect 8 (stock: 7)
```

Runtime verification (after TUI restart):
- Ctrl+Click the SECOND visual line of a wrapped file link in a freshly-printed assistant message
- The file should open in the default application
- On the stock binary, only the first line would be clickable

## Reapply Instructions
1. Open `/home/ezotoff/src/opencode/packages/tui/src/routes/session/index.tsx`.
2. Add `import open from "open"` after `import { openEditor } from "../../editor"`.
3. In `function TextPart(...)`, add `const renderer = useRenderer()` after `const { theme, syntax } = useTheme()`.
4. Add `onMouseUp` handler to the `<box>` that wraps `<markdown>`:
   - Skip if `renderer.getSelection()?.getSelectedText()` is truthy
   - Read cell linkId: `(buf.buffers.attributes[e.y * buf.width + e.x] >>> 8) & 0xffffff`
   - If linkId > 0, call `(renderer as any).lib?.linkGetUrl?.(lid)` and `open(url)`
   - Fallback: parse `[label](url)` from content, match clicked line text against labels
5. Add `ref` callback to `<markdown>` that patches `el._onChunks` to tag label chunks:
   - Guard with `el.__linkLabelPatch`
   - Save `const orig = el._onChunks`
   - Replace with wrapper that calls `orig`, then parses `[label](url)` patterns from `context.content`
   - For each pattern, find chunks overlapping the label text range and set `chunk.link = { url }` if not already set
6. Rebuild: `cd /home/ezotoff/src/opencode/packages/opencode && OPENCODE_VERSION="$(/home/ezotoff/.opencode/bin/opencode --version)" PATH=/home/ezotoff/.bun/bin:$PATH /home/ezotoff/.bun/bin/bun run script/build.ts --single --skip-install --skip-embed-web-ui`.
7. Back up `~/.opencode/bin/opencode`, then `rm` + `cp` to swap (avoids ETXTBSY).
8. Restart `omo-tg.service` and `opencode.service`. The running TUI session must also be restarted.

## Durable Alternative
1. **Alacritty upstream fix**: Revert the `hyperlink_at` regression from commit `275726f` so click resolution walks adjacent rows. Fixes the bug for ALL OSC 8 hyperlinks. No tracking issue on alacritty/alacritty as of 2026-07-08.
2. **OpenTUI upstream fix**: Patch `detectLinks` to also tag `markup.link.label` chunks, not just `markup.link.url`. This would eliminate the need for the `_onChunks` override.
3. **Switch terminal**: kitty, WezTerm, Ghostty, iTerm2 handle multi-line OSC 8 clicks correctly.
4. **Upstream opencode PR**: Submit both the `_onChunks` label-tagging patch and the onMouseUp fallback to opencode/OpenTUI as resilience improvements.

Status: blocked-by-upstream (Alacritty regression + OpenTUI detectLinks gap; no upstream fix available for either)
