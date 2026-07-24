---
patch_id: "opencode--turn-summary-timestamp"
dependency: "opencode"
target_file: "opencode"
target_install_path: "/home/ezotoff/src/opencode"
status: "active"
applied_date: "2026-07-19"
dep_version: "1.17.9-local"
upstream_issue: "https://github.com/anomalyco/opencode/pull/37929"
verification_pattern: "todayTimeOrDateTime"
---

# OpenCode TUI turn-summary timestamp (local customization: shortDateTime 24h+date format)

## Regression History

- **2026-07-22 22:41 CEST** — Patch silently lost. Another agent (opencode log `run=73012e84`) ran `OPENCODE_VERSION=1.17.9 bun run script/build.ts --single --skip-install --skip-embed-web-ui` from a non-patched branch (likely `feat/turn-summary-completion-time` or `origin/dev`), then swapped the resulting unpatched binary into `~/.opencode/bin/opencode`. Detected by user after system reboot when timestamps disappeared from TUI.
- **2026-07-23 09:31 CEST** — Restored from backup `opencode.backup-1.17.9-turn-summary-v3-20260720-094806`.

**Systemic risk**: any agent that rebuilds opencode from a branch lacking the local patches will silently overwrite the live binary. Mitigation: when rebuilding, ALWAYS branch from `fix/turn-summary-timestamp-v1.17.9` (or its successor carrying the same patches). Detection: `python3 -c "d=open('/home/ezotoff/.opencode/bin/opencode','rb').read(); print('time? count:', d.count(b'time?'))"` should print 35, not 34.

## Problem

The TUI turn-summary line (rendered after each assistant turn completes) shows `▣ {agent} · {model} · {duration}` with no wall-clock time. Reviewing long sessions, especially across multiple days, gives no clue when each turn ran. Issue [sst/opencode#35348](https://github.com/sst/opencode/issues/35348) requests start/completion timestamps; PR [sst/opencode#32771](https://github.com/sst/opencode/pull/32771) implemented this exact feature but was auto-closed by the `needs:compliance` bot within 2 hours (template-formatter issue, not rejected on merits).

## Patch Description

Ports the turn-summary timestamp subset of PR #32771, with one deviation: uses `Locale.todayTimeOrDateTime()` instead of upstream's `Locale.time()` so that turns from prior days (typically only visible in session replay) render with the date as well as the time. Turns from today still render time-only ("3:41 PM"); older turns render "3:41 PM · 7/19/2026".

Six source files touched (13 insertions, 4 deletions):

1. `packages/opencode/src/cli/cmd/run/turn-summary.ts` — `turnSummaryCommit` accepts optional `time?: string`; appends ` · ${time}` to the summary text; `summary` object carries `time`; `messageTurnSummaryCommit` passes `time: Locale.todayTimeOrDateTime(completed)`.
2. `packages/opencode/src/cli/cmd/run/scrollback.writer.tsx` — `turnSummaryWriter` accepts `time?: string` and renders `{input.time ? ` · ${input.time}` : ""}` after duration.
3. `packages/opencode/src/cli/cmd/run/scrollback.surface.ts` — `writeTurnSummary` accepts `time?: string` and passes through.
4. `packages/opencode/src/cli/cmd/run/types.ts` — `TurnSummary` gains `time?: string`; the `turn.duration` `FooterEvent` variant gains `time: string`.
5. `packages/opencode/src/cli/cmd/run/runtime.queue.ts` — captures `end = Date.now()`; emits `time: Locale.todayTimeOrDateTime(end)` in the `turn.duration` event.
6. `packages/opencode/src/cli/cmd/run/footer.ts` — forwards `next.time` into `writeTurnSummary`.

Deliberately NOT ported from PR #32771 (out of scope for the timestamp feature):
- The `environmentStatus` (host+directory) block in `footer.view.tsx`. Different feature; user did not request.
- The web-TUI route change in `packages/tui/src/routes/session/index.tsx`.
- The `footer.view.test.tsx` env-status test changes.

Tests ported:
- New `packages/opencode/test/cli/run/turn-summary.test.ts` (single unit test on `turnSummaryCommit`).
- New case "turn summary appends completion time after duration" in `scrollback.surface.test.ts`.
- Updated three turn-summary assertions in `session-replay.test.ts` to expect ` · ${Locale.todayTimeOrDateTime(3000)}` suffix; added `import * as Locale from "@/util/locale"`.

## Verification

Binary proof (built into `~/.opencode/bin/opencode`):

```bash
~/.opencode/bin/opencode --version
# Expected: 1.17.9

grep -c 'todayTimeOrDateTime' ~/.opencode/bin/opencode
# Expected: 3 (function name embedded in minified bundle)
```

Source proof (in `/home/ezotoff/src/opencode` on branch `fix/turn-summary-timestamp-v1.17.9`):

```bash
grep -nE 'todayTimeOrDateTime\(completed\)' /home/ezotoff/src/opencode/packages/opencode/src/cli/cmd/run/turn-summary.ts
grep -nE 'time:\s*next\.time' /home/ezotoff/src/opencode/packages/opencode/src/cli/cmd/run/footer.ts
grep -nE 'time:\s*Locale\.todayTimeOrDateTime\(end\)' /home/ezotoff/src/opencode/packages/opencode/src/cli/cmd/run/runtime.queue.ts
```

Test verification:

```bash
cd /home/ezotoff/src/opencode/packages/opencode
bun test test/cli/run/turn-summary.test.ts test/cli/run/scrollback.surface.test.ts test/cli/run/session-replay.test.ts --timeout 60000
# Expected: 31 pass, 0 fail
```

## Reapply Instructions

This patch is layered on top of branch `fix/sse-directory-filter-v1.17.9` (which itself contains two prior tracked patches: SSE directory filter removal + link-click OSC 8 workaround). To reapply after an OpenCode update:

1. Identify the new live version: `~/.opencode/bin/opencode --version`.
2. In `$HOME/src/opencode`, checkout the release tag matching that version: `git checkout v<X.Y.Z> -b fix/turn-summary-timestamp-v<X.Y.Z>`. If prior patches (SSE dir filter, link click) still apply, branch from the branch that carries them instead, so the rebuild carries all tracked patches.
3. Re-apply the six-file diff shown in `git log fix/turn-summary-timestamp-v1.17.9 ^v1.17.9 -- packages/opencode/src/cli/cmd/run/`. The change is mechanical: add `time?: string` to four type signatures, append ` · ${time}` to the summary text, populate `time` from `Locale.todayTimeOrDateTime(<ms>)` in both `runtime.queue.ts` (live turns) and `turn-summary.ts` (`messageTurnSummaryCommit` for replay).
4. Port the three test files (or re-run them as-is if the upstream code hasn't diverged).
5. Build: `cd packages/opencode && OPENCODE_VERSION=<X.Y.Z> bun run script/build.ts --single --skip-install --skip-embed-web-ui`.
6. Verify built binary `--version` matches live, and `grep -c todayTimeOrDateTime dist/opencode-linux-x64/bin/opencode` returns ≥3.
7. Stop services: `systemctl --user stop omo-tg.service opencode.service`.
8. Swap binary. If interactive TUI clients hold the file busy, use the Linux `mv` + `cp` pattern: `mv ~/.opencode/bin/opencode ~/.opencode/bin/opencode.old-<v>-pre-turn-summary-timestamp && cp dist/opencode-linux-x64/bin/opencode ~/.opencode/bin/opencode && chmod +x ~/.opencode/bin/opencode`. Running TUI clients keep the old inode; new invocations get the new binary.
9. Restart services: `systemctl --user start opencode.service omo-tg.service`.
10. Confirm fresh start time: `ps -eo lstart,args | grep 'opencode serve' | grep -v grep`.

## Durable Alternative

1. **Upstream PR (PREFERRED) — SUBMITTED 2026-07-20** — Opened [anomalyco/opencode#37929](https://github.com/anomalyco/opencode/pull/37929) (first attempt #37905 was auto-closed by the same compliance bot that killed the original #32771, for missing 4 of 6 required template sections). The upstream PR uses `Locale.time()` (locale-aware, time-only) — the user-facing default that respects every user's system settings. When merged and released, the upstream code path will produce locale-formatted times; this local patch will continue to override that with `Locale.shortDateTime()` (24-hour, date-inclusive) as a personal format customization.
2. Plugin/hook — Not viable: the turn summary is rendered deep inside the TUI scrollback writer; no plugin or system-prompt transform can inject text into that line.
3. Config option — Not viable: no config knob exists for the turn-summary format, and adding one is more invasive than the patch itself.

Status: pursued (upstream PR #37929 opened 2026-07-20, all compliance checks green, awaiting maintainer review as of 2026-07-23).
