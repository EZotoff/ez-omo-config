---
name: computer-use
description: "OS-level computer use on the local X11 desktop via the cua-driver daemon: screenshots, AT-SPI element trees, background (co-work) mouse/keyboard input, and window management for NATIVE applications only. Use for native GUI apps without APIs, OS dialogs, and desktop automation; NOT for any browser/web task (use agent-browser) or anything with a CLI/API (use bash)."
mcp:
  cua:
    command: bash
    args: ['-c', 'exec cua-driver mcp --socket "$HOME/.cache/cua-driver/cua-driver.sock" --no-overlay']
---

# Computer Use (cua-driver)

You control the local Linux X11 desktop through the `skill_mcp` tool with
`mcp_name: "cua"`. One tool per call. Keep image-producing calls on the CLI
path (explained below); non-image example:

```
skill_mcp(mcp_name="cua", tool_name="get_window_state", arguments={"pid": ..., "window_id": ..., "include_screenshot": false})
```

Infrastructure facts (already deployed, do not change):
- Daemon: systemd user service `cua-driver.service`, pinned 0.20.0, **overlay
  disabled** (it froze GNOME Shell on this dual-head — never re-enable), telemetry off.
- The daemon is shared and always-on; your calls are cheap and isolated per session label.

## Decision ladder — when to use what

| Task shape | Tool |
|---|---|
| Target app has a CLI, config file, or API | bash — never this skill |
| Web — ANY web, logged in or not | agent-browser (persistent named session for logins; one-time manual login) — never this skill |
| Native GUI app (GNOME/Qt/Electron) | this skill, AT-SPI element rung first |
| OS chrome (dialogs, polkit, keyring, settings) | this skill, pixel rung |

## Action method (strict order)

1. **Element rung (preferred).** `list_windows` → find target →
   `get_window_state` (returns `elements[]` with `element_token` + the app tree) →
   act by `element_token` (`click`, `set_value`, `type_text`...). No coordinate math
   needed. Re-read the tree after any UI change — tokens go stale. Cross-check the
   tree against pixels when it looks wrong: Electron apps echo-confirm and
   virtualized lists report bogus geometry (the tree sometimes lies).
   Background `type_text`: AT-SPI EditableText lands in UNFOCUSED GTK4/Qt6
   editables — no focus needed; terminals take a focus-free pty route.
   Non-editable focused widgets (canvas, spreadsheet cell) need the foreground rung.
2. **Pixel rung (fallback).** The screenshot from `get_window_state` is in
   **window-local pixels** — pixel actions take x,y relative to that window's
   screenshot, NOT the desktop. Ground coordinates with `look_at` on the saved
   image when unsure. Click centers of elements; on miss, re-shoot, adjust,
   retry. Apply the ~47px header offset before clicking (see Failure modes).

3. **Foreground escalation (last resort).** Background delivery is the default and
   safe for co-work. If a tool returns `background_unavailable` with an escalation
   hint, foreground mode briefly focuses the target — acceptable only for brief
   input, and never while the user is typing in that window.

## Browser work is OUT OF SCOPE

All browser tasks go to agent-browser (use a persistent named session when the
site needs the user's login — they type credentials once, the session survives
on disk). The cua browser tools (`browser_prepare`, `get_browser_state`,
`browser_navigate`, `browser_click`, `browser_type`) are deliberately unused:
the daemon runs WITHOUT the existing-profile grant, so profile attachment is
refused by design. A browser WINDOW may still be driven as a native window
(pixel rung) for OS-level chrome inside it — file dialogs, permission popups —
but never its page content.

## Core tool catalog (~20 of 60; full list via `skill_mcp` `list_tools`)

Inspection: `get_screen_size` `get_cursor_position` `get_desktop_state` (full
5120x1600 capture) `list_windows` `get_window_state` (tree + screenshot)
`verify_state` (predicate check — prefer over eyeballing) `health_report`
Input: `click` `double_click` `right_click` `drag` `scroll` `type_text`
`press_key` `hotkey`
Apps: `launch_app` `kill_app` (destructive — confirm with user first)
Clipboard: `clipboard_read` `clipboard_write`

Omitted deliberately: all browser tools (agent-browser owns the web),
recording/replay, agent-cursor cosmetics, multi-cursor, sessions beyond a
label, deprecated aliases.

## Working rules

- Multi-step work: pass the same short `session` label on every call (e.g.
  `"email-triage"`) — keys lifecycle and cleanup.
- **Never return screenshots through `skill_mcp`.** OMO JSON-stringifies MCP
  results, turning image blocks into enormous base64 text. For pixels, call the
  CLI through bash with `screenshot_out_file` (e.g. `cua-driver call
  get_desktop_state '{"screenshot_out_file":"/tmp/opencode/cua/shot.png"}'`),
  then use `look_at` on that file. For tree-only work, always pass
  `include_screenshot:false`. Cap `max_elements` (≤200) on Electron/large apps.
- Some apps ignore synthetic input (rare; the tool reports it honestly). If an
  action lands as `effect: "unverifiable"`, verify with `verify_state` or a fresh
  screenshot before assuming success.
- Destructive UI (delete dialogs, send buttons, kill_app): confirm with the user
  first, every time, regardless of rung.
- The user works on this desktop concurrently. Background delivery never moves
  their cursor; foreground mode does steal focus briefly — announce it first.

## Failure modes seen on this machine

- Snap-confined *clients* (anything launched from a snap terminal) lose AT-SPI —
  if you inherit a degraded tree, the daemon is fine; the client label is the issue.
- Wayland tools are inert here (X11 only). `linux_libei` paths never apply.
- GTK4 apps may under-expose AT-SPI: gnome-calculator's tree contained only its
  109 header/unit menus, no keypad buttons. Expect the pixel rung for such apps.
- Pixel-run coordinate frames disagree by the window header (~47px on stock GNOME):
  the `get_window_state` screenshot INCLUDES the header bar, click coordinates DO
  NOT. Ground on the screenshot, then subtract ~47 from y before clicking
  (x is unaffected; calibrated live 2026-08-18 on 0.20.0).
- `launch_app` STEALS FOCUS on this GNOME/X11 box (no startup-notification
  timestamp from the daemon; its `active:false` reply does NOT mean focus was
  preserved). Never launch apps while the user is typing; after launching, offer
  to reactivate their previous window.
- Background pixel clicks report `effect: "unverifiable"` while still landing
  (verified: digits registered with focus and cursor untouched). ALWAYS verify by
  screenshot/readout, never by the effect field.
- `kill_app` refuses processes outside a live cua session
  (`foreign_process_termination_denied`) — close via `wmctrl -ic <window-id>`
  (graceful WM close) instead.
- Browser tools are dead on this host by policy (no `--grant existing-profile`
  on the daemon; `browser_prepare` existing-profile refuses
  `browser_consent_required`). Technical findings preserved in wisdom entry
  `20260818-010629-03d1` and upstream #3239.

## Upstream tracking

- trycua/cua#3236 — X11 overlay freezes GNOME Shell (workaround: `--no-overlay`)
- trycua/cua#3237 — screenshot/click coordinate frame mismatch (~47px header)
- trycua/cua#3238 — `launch_app` steals focus on GNOME X11
- trycua/cua#3239 — Linux Chrome attach: empty AT-SPI tree + input routes unavailable
