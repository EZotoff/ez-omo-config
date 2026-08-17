---
name: computer-use
description: "OS-level computer use on the local X11 desktop via the cua-driver daemon: screenshots, AT-SPI element trees, background (co-work) mouse/keyboard input, window management, and driving the user's real authenticated browser. Use for native GUI apps without APIs, OS dialogs, and logged-in web accounts; NOT for anonymous web automation (use agent-browser) or anything with a CLI/API (use bash)."
mcp:
  cua:
    command: bash
    args: ['-c', 'exec cua-driver mcp --socket "$HOME/.cache/cua-driver/cua-driver.sock" --no-overlay']
---

# Computer Use (cua-driver)

You control the local Linux X11 desktop through the `skill_mcp` tool with
`mcp_name: "cua"`. One tool per call, e.g.:

```
skill_mcp(mcp_name="cua", tool_name="get_window_state", arguments={"pid": ..., "window_id": ...})
```

Infrastructure facts (already deployed, do not change):
- Daemon: systemd user service `cua-driver.service`, pinned 0.20.0, **overlay
  disabled** (it froze GNOME Shell on this dual-head — never re-enable), telemetry off.
- The daemon is shared and always-on; your calls are cheap and isolated per session label.

## Decision ladder — when to use what

| Task shape | Tool |
|---|---|
| Target app has a CLI, config file, or API | bash — never this skill |
| Web site, no login needed | agent-browser (cheaper, DOM-precise) |
| Web account the user is logged into (email, calendar, portals) | this skill, browser tools |
| Native GUI app (GNOME/Qt/Electron) | this skill, AT-SPI element rung first |
| OS chrome (dialogs, polkit, keyring, settings) | this skill, pixel rung |
| Screenshot interpretation only | `look_at` after `get_desktop_state` |

## Action method (strict order)

1. **Element rung (preferred).** `list_windows` → find target →
   `get_window_state` (returns `elements[]` with `element_token` + the app tree) →
   act by `element_token` (`click`, `set_value`, `type_text`...). No coordinate math
   needed. Re-read the tree after any UI change — tokens go stale.
2. **Pixel rung (fallback).** The screenshot from `get_window_state` is in
   **window-local pixels** — pixel actions take x,y relative to that window's
   screenshot, NOT the desktop. Ground coordinates with `look_at` on the saved
   image when unsure. Click centers of elements; on miss, re-shoot, adjust, retry.
3. **Foreground escalation (last resort).** Background delivery is the default and
   safe for co-work. If a tool returns `background_unavailable` with an escalation
   hint, foreground mode briefly focuses the target — acceptable only for brief
   input, and never while the user is typing in that window.

## Core tool catalog (~20 of 60; full list via `skill_mcp` `list_tools`)

Inspection: `get_screen_size` `get_cursor_position` `get_desktop_state` (full
5120x1600 capture) `list_windows` `get_window_state` (tree + screenshot)
`verify_state` (predicate check — prefer over eyeballing) `health_report`
Input: `click` `double_click` `right_click` `drag` `scroll` `type_text`
`press_key` `hotkey`
Apps: `launch_app` `kill_app` (destructive — confirm with user first)
Clipboard: `clipboard_read` `clipboard_write`
Browser (user's real profile; see below): `browser_prepare` `get_browser_state`
`browser_navigate` `browser_click` `browser_type`

Omitted deliberately: recording/replay, agent-cursor cosmetics, multi-cursor,
sessions beyond a label, deprecated aliases.

## Working rules

- Multi-step work: pass the same short `session` label on every call (e.g.
  `"email-triage"`) — keys lifecycle and cleanup.
- Screenshot-heavy loops: use `include_screenshot: false` on `get_window_state`
  when you only need the tree; cap `max_elements` (≤200) on Electron/large apps.
- Some apps ignore synthetic input (rare; the tool reports it honestly). If an
  action lands as `effect: "unverifiable"`, verify with `verify_state` or a fresh
  screenshot before assuming success.
- Destructive UI (delete dialogs, send buttons, kill_app): confirm with the user
  first, every time, regardless of rung.
- The user works on this desktop concurrently. Background delivery never moves
  their cursor; foreground mode does steal focus briefly — announce it first.
- Browser attach (`browser_prepare`) uses the user's authenticated Chrome —
  treat every page as acting-as-the-user. Announce intent before navigating.

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
- Existing-profile Chrome attach on Linux X11 has a split capability boundary
  in 0.20.0. If Chrome exposes no omnibox AT-SPI tree, the canonical setup route
  refuses; a profile with an already-published `DevToolsActivePort` attaches with
  zero setup side effects. After attach, state reads, semantic snapshots,
  navigation, and session revocation work. `browser_click` refuses
  `route_unavailable` for BOTH `trusted` and `dom_event` routes — treat attached
  Chrome as read/navigate-only until upstream #3239 is resolved.

## Upstream tracking

- trycua/cua#3236 — X11 overlay freezes GNOME Shell (workaround: `--no-overlay`)
- trycua/cua#3237 — screenshot/click coordinate frame mismatch (~47px header)
- trycua/cua#3238 — `launch_app` steals focus on GNOME X11
- trycua/cua#3239 — Linux Chrome attach: empty AT-SPI tree + input routes unavailable
