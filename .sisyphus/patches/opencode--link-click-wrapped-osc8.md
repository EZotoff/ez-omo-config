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
# regression (dead parent _linkifyMarkdownChunks hook) was recovered by the
# child-onChunks redesign (commit b5d4fe483), verified 2026-08-03 (see below).
dep_version: "1.18.5"
runtime_effective: true
runtime_effective_note: "Redesign verified EFFECTIVE on the real v1.18.5 interactive TUI surface 2026-08-03 (T3): conceal-ON renders link labels with no parenthesised (file:///...) URL, conceal-OFF shows the URL, no-link prompt unaffected, regression corpus 11/11. Live binary sha256 03edb5158179d6ad593d21321249316f191060b98e907c0c62a59064190cb4c2. Hook is the child CodeRenderable.onChunks setter (instance createMarkdownCodeRenderable wrap + walkChildren), NOT the parent _linkifyMarkdownChunks (dead in OpenTUI >= 0.4.x). Evidence: .sisyphus/evidence/task-3-tui-link-conceal-on.txt."
upstream_issue: "none"
verification_pattern: "__linkLabelPatch"
surfaces:
  - tui-interactive
---

# OpenCode TUI link rendering + click workaround for markdown links

## Current Runtime Status (2026-08-03)

**VERIFIED EFFECTIVE on v1.18.5 as of 2026-08-03.** The redesigned hook —
child `CodeRenderable.onChunks` via an instance-level
`createMarkdownCodeRenderable` wrap plus a `walkChildren` pass — is reached
on the active SolidJS render path: `[label](file:///long/path)` renders as
just the label (conceal ON) with no parenthesised URL, and the URL appears
when conceal is toggled OFF.

Timeline:
- **2026-07-06**: Patch authored and verified effective on v1.17.9-local binary (Claude Code session `ses_0cb68340affe8wmwHElU79k0N3`).
- **2026-07-26**: `/update-to-latest` (session `ses_05fb42625ffeeATeeEO5BQskpY`) upgraded the live binary to v1.18.5.
- **2026-07-27**: Patch reapplied verbatim to v1.18.5 source as commit `ff9df0b84` ("patch: opencode--link-click-wrapped-osc8 v1.18.5"). The reapply touched `TextPart` in `packages/tui/src/routes/session/index.tsx` unchanged.
- **2026-07-27 (later)**: **REGRESSION** — the monkey-patched `_linkifyMarkdownChunks` method on the `<markdown>` renderable was no longer invoked on v1.18.5's SolidJS render path. OpenTUI 0.4.5 captures `onChunks` in `CodeRenderable` construction; the parent override is dead. The patch string `__linkLabelPatch` remained in the binary (Bun preserves property keys), so pattern-grep reported a false-positive APPLIED while the feature was broken.
- **2026-08-03**: **RECOVERY** — the hook moved to the child `CodeRenderable.onChunks` setter (instance factory wrap + `walkChildren`), commit `b5d4fe483` on `fix/link-click-v1.18.5-solidjs`. Real TUI captures confirm conceal works; evidence `.sisyphus/evidence/task-3-tui-link-conceal-on.txt`.

Redesign verified 2026-08-03 via commit b5d4fe483 on fix/link-click-v1.18.5-solidjs; evidence .sisyphus/evidence/task-3-tui-link-conceal-on.txt.

**Why the verifier reported VERSION-DRIFT until this update**:
`verify-live-patches.sh` greps the binary for `verification_pattern:
"__linkLabelPatch"` and compares `dep_version` to the runtime version. With
`dep_version: 1.17.9-local` and the live runtime at 1.18.5 it reported
VERSION-DRIFT even though the redesign was effective. Bun minification
preserves JS property keys, so the pattern alone is a necessary-but-not-
sufficient check. This entry now records the verified state.

## Problem

Three bugs combine to make markdown file links render poorly and wrap-break:

1. **OpenTUI conceal gap**: Conceal hides `[`/`]` brackets but NOT the URL text. `[label](file:///long/path)` renders as `label (file:///long/path)` — the long URL wraps across terminal lines.
2. **OpenTUI detectLinks gap**: After tree-sitter, only `markup.link.url` chunks get `.link`, not `markup.link.label` chunks. Labels lose linkId and are not clickable.
3. **Alacritty hyperlink_at regression** (commit 275726f): Wrapped OSC 8 URLs only resolve on the first visual line — clicking the second line opens a truncated path.

## Patch Description

**Why the hook moved (OpenTUI 0.4.5)**: in OpenTUI >= 0.4.x, `CodeRenderable`
captures its `onChunks` callback at construction time inside
`createMarkdownCodeRenderable`. Overriding the parent MarkdownRenderable's
`_linkifyMarkdownChunks` after the fact is dead — children already captured
their chunk handlers, and the parent method is never invoked on the active
SolidJS render path. The patch therefore hooks the CHILD. Two mechanisms,
BOTH required:

1. **(a) Instance factory wrap** — the ref sets an own-property shadow
   `el.createMarkdownCodeRenderable` on the MarkdownRenderable instance (NOT a
   prototype override), wrapping `args[3]` (the `onChunks` callback). Every
   child CodeRenderable created — now and during streaming — receives the
   patched callback at construction.
2. **(b) `walkChildren`** — recursively walks already-existing children
   (created in the constructor before the ref fired) and patches their
   `onChunks` via the public SETTER (which updates `_onChunks` and flips
   `_highlightsDirty`).

The patched `onChunks` (in the child) does the work the old parent hook did:

1. **Conceal URL filtering**: When conceal is ON, filters out `](url)` syntax and URL chunks so only the label renders — no wrapping.
2. **Label tagging**: Tags label chunks with `.link = { url }` so labels carry linkId and are clickable via OSC 8.

Also adds an `onMouseUp` fallback on the container `<box>` for regular clicks (linkId resolution + text-based `[label](url)` matching).

Key detail: the hook point is the child `CodeRenderable.onChunks` setter, NOT
the parent `_linkifyMarkdownChunks` (dead in OpenTUI >= 0.4.x). The
`__linkLabelPatch` marker survives in the wrapped `onChunks` closure as the
minification-survivor build marker.

## Runtime Verification

The TUI exercise below is the CANONICAL verification. Pattern-grep alone
cannot confirm effectiveness: Bun preserves JS property keys under
minification, so `__linkLabelPatch` survives in the binary even when the
surrounding code is unreachable — exactly what happened on 2026-07-27 (see
Current Runtime Status). Run the TUI steps after every build, rebuild, or
version bump.

```bash
# 1. Start the interactive TUI (NOT `opencode run` — the regression is on the
#    SolidJS interactive surface, which is a DIFFERENT renderer from run/).
opencode

# 2. In the TUI, send any prompt that causes the assistant to emit a
#    [label](file:///abs/path) markdown link. (Most agent prompts do this
#    because the clickable-links system-prompt injection is active.)
#
#    In tmux, toggle conceal by sending `C-x h` in ONE send-keys invocation;
#    splitting it into `C-x` then `h` leaves a literal `h` in the prompt.

# 3. EXPECTED when patch is effective + conceal ON:
#    - Only the link label is visible (e.g. "configs/opencode/opencode.json")
#    - NO parenthesised file:// URL rendered next to the label
#    - Label is clickable (OSC 8 underline / highlight on hover)

# 4. Toggle conceal OFF: the file:// URL appears next to the label.

# 5. REGRESSION SIGNAL (what this patch fixes):
#    - Label is followed by "(file:///abs/path)" in parens
#    - The URL wraps across terminal lines on narrow terminals
#    - If you see the regression signal, the patch is RUNTIME-INEFFECTIVE even
#      if `grep __linkLabelPatch` returns 1: set runtime_effective: false in
#      this entry and file a follow-up to redesign the hook point.
```

Pattern-grep check (build-completeness only, NOT sufficient):

```bash
# Build-completeness check only:
grep -c "__linkLabelPatch" /home/ezotoff/.opencode/bin/opencode
grep -c "isUrlOrSyntax" /home/ezotoff/src/opencode/packages/tui/src/routes/session/index.tsx
```

## Reapply Instructions

1. **Wrap the MarkdownRenderable instance's `createMarkdownCodeRenderable`
   method (instance own-property shadow, NOT prototype override)** so that
   every child CodeRenderable created — now and during streaming — receives a
   patched `onChunks` at construction time. THEN walk existing children
   (created before the ref fired) and patch their `onChunks` via the setter.
   The parent's `_linkifyMarkdownChunks` is NOT the hook point in OpenTUI >= 0.4.x:
   children capture onChunks at construction, so a parent-level override is
   dead code on the active render path.
2. In `packages/tui/src/routes/session/index.tsx`, add `import open from "open"`.
3. In `TextPart` (or its successor component), add `const renderer = useRenderer()`.
4. Add `onMouseUp` on `<box>`: linkId resolution + text fallback.
5. Add `ref` on `<markdown>`: attach the instance factory wrap (step 1a) and
   run `walkChildren` (step 1b) to patch existing + future child `onChunks`
   callbacks for label tagging and URL filtering when concealing.
6. Rebuild, swap binary, restart services.
7. **Run the Runtime Verification steps above BEFORE claiming the patch is
   effective.** Set `runtime_effective: true` only after observing the
   expected TUI behaviour on the real interactive surface.

## Durable Alternative

1. OpenTUI: fix conceal to hide full link syntax, fix detectLinks to tag labels.
2. Alacritty: revert hyperlink_at regression from commit 275726f.
3. Switch terminal (kitty, WezTerm, Ghostty).

Status: blocked-by-upstream
