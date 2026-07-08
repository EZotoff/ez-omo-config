---
patch_id: "opencode--link-click-wrapped-osc8"
dependency: "opencode"
target_file: "packages/tui/src/routes/session/index.tsx"
target_install_path: "/home/ezotoff/src/opencode"
status: "active"
applied_date: "2026-07-06"
dep_version: "1.17.9-local"
upstream_issue: "none"
verification_pattern: "buffers\\.attributes\\[idx\\] >>> 8"
---

# OpenCode TUI link-click workaround for wrapped OSC 8 hyperlinks

## Problem
File links (`[label](file:///abs/path)`) in assistant markdown messages render via OpenTUI's native `.link` chunk mechanism, which emits OSC 8 terminal hyperlinks. When a link's label is long enough to wrap across visual lines, **only the first visual line is clickable** in Alacritty 0.17.0.

Root cause: Alacritty's `hyperlink_at` function (`alacritty/src/display/hint.rs:425`) only returns contiguous cells within a single row — a regression from commit `275726f` (March 2024, "Fix hint Select action for hyperlink escape"). The OSC 8 spec defines hover-underlining by `id`, and OpenTUI 0.3.4 correctly emits matching `id` parameters on all wrapped cells (verified via cell-attribute inspection: all cells carry linkId `0x1003f`). Hover-highlight works across the wrap; click does not. Not fixed in any Alacritty version through 0.18.0-dev.

This affects all opencode TUI users on Alacritty. Other terminals (kitty, WezTerm, Ghostty, iTerm2, VTE) handle multi-line OSC 8 clicks correctly.

## Patch Description
Added a TS-level `onMouseUp` handler to the `TextPart` component's `<box>` container in `packages/tui/src/routes/session/index.tsx`. This handler bypasses the terminal's OSC 8 click resolution entirely:

1. On click in the assistant markdown area, reads the cell's linkId from `renderer.currentRenderBuffer.buffers.attributes` at the click position `(e.y * buf.width + e.x)`.
2. Extracts linkId via bitshift: `(attributes[idx] >>> 8) & 0xFFFFFF`.
3. If linkId > 0, resolves the URL via `(renderer as any).lib.linkGetUrl(lid)`.
4. Opens the URL via the `open` npm package.

The handler skips when there is an active text selection (`renderer.getSelection()?.getSelectedText()`) to avoid interfering with click-drag text selection. `onMouseUp` fires on ALL visual lines (proven by test-renderer mock-mouse verification), unlike Alacritty's per-row OSC 8 click resolution.

27 insertions, 1 deletion. Purely additive — no behavior change for non-link clicks (linkId is 0 for non-link cells).

## Verification
```bash
# Source: verify the workaround code is present
grep -n "buffers\.attributes\[idx\] >>> 8" \
  /home/ezotoff/src/opencode/packages/tui/src/routes/session/index.tsx

# Source: verify the open import was added
grep -n 'import open from "open"' \
  /home/ezotoff/src/opencode/packages/tui/src/routes/session/index.tsx
```

Binary verification:
```bash
# The patched binary has one more linkGetUrl reference than stock (7 → 8)
grep -a -o 'linkGetUrl' ~/.opencode/bin/opencode | wc -l   # expect 8
# The patched binary references buffers.attributes (stock has fewer)
grep -a -o 'buffers.attributes' ~/.opencode/bin/opencode | wc -l  # expect 3
```

Runtime verification (after TUI restart):
- Click the SECOND visual line of a wrapped file link in an assistant message
- The file should open in the default application (xdg-open)
- On the stock binary, only the first line would open the link

## Reapply Instructions
1. Open `/home/ezotoff/src/opencode/packages/tui/src/routes/session/index.tsx`.
2. Add `import open from "open"` after the `import { openEditor } from "../../editor"` line (around line 46).
3. In `function TextPart(...)`, add `const renderer = useRenderer()` after `const { theme, syntax } = useTheme()`.
4. Expand the `<box>` element to include an `onMouseUp` handler that:
   - Checks `renderer.getSelection()?.getSelectedText()` and returns early if truthy
   - Reads `renderer.currentRenderBuffer.buffers.attributes[e.y * buf.width + e.x]`
   - Extracts linkId: `(attrs >>> 8) & 0xffffff`
   - If linkId > 0, calls `(renderer as any).lib?.linkGetUrl?.(lid)` and `open(url)` if the URL is non-empty
   - Wraps the body in `try { ... } catch {}`
5. Rebuild: `cd /home/ezotoff/src/opencode/packages/opencode && OPENCODE_VERSION="$(/home/ezotoff/.opencode/bin/opencode --version)" PATH=/home/ezotoff/.bun/bin:$PATH /home/ezotoff/.bun/bin/bun run script/build.ts --single --skip-install --skip-embed-web-ui`.
6. Back up `~/.opencode/bin/opencode`, then `rm` the old binary and `cp` the new one (rm+cp avoids ETXTBSY when the running TUI holds the old inode).
7. Restart `omo-tg.service` and `opencode.service`. The user's running TUI session must also be restarted to pick up the new binary.

## Durable Alternative
1. **Alacritty upstream fix**: Revert the `hyperlink_at` regression from commit `275726f78499698f82eafff761fb497b29ddc2b8` so click resolution walks adjacent rows (like the pre-2024 implementation in commit `694a52b`). This would fix the bug for ALL OSC 8 hyperlinks, not just opencode's. No tracking issue exists on alacritty/alacritty as of 2026-07-06.
2. **Switch terminal**: kitty, WezTerm, Ghostty, iTerm2 all handle multi-line OSC 8 clicks correctly. Using any of these eliminates the need for this workaround.
3. **Upstream opencode fix**: Submit the TS-level onMouseUp handler to opencode as a general resilience improvement (works regardless of terminal OSC 8 support). This would make the local patch unnecessary.

Status: blocked-by-upstream (Alacritty regression; no upstream fix available)
