---
patch_id: "opencode--turn-summary-timestamp"
dependency: "opencode"
target_file: "packages/opencode/src/cli/cmd/run/turn-summary.ts, packages/opencode/src/cli/cmd/run/types.ts, packages/opencode/src/cli/cmd/run/scrollback.surface.ts, packages/opencode/src/cli/cmd/run/scrollback.writer.tsx, packages/opencode/src/cli/cmd/run/runtime.queue.ts, packages/opencode/src/cli/cmd/run/footer.ts, packages/tui/src/routes/session/index.tsx"
target_install_path: "/home/ezotoff/src/opencode"
status: "active"
applied_date: "2026-07-19"
dep_version: "1.18.5"
upstream_issue: "https://github.com/anomalyco/opencode/pull/37929"
verification_pattern: "todayTimeOrDateTime"
surfaces: "cli-run, tui-interactive"
runtime_effective: true
runtime_effective_note: "Verified effective on v1.18.5 binary (2026-08-06): 'todayTimeOrDateTime' present (3 matches in binary). Source patch applied in turn-summary.ts:47, runtime.queue.ts:238. Rendering path intact on both surfaces: scrollback.writer.tsx:345 (cli-run: input.time rendering) and session/index.tsx:1430 (tui-interactive: Locale.todayTimeOrDateTime call). Unlike the link-click monkey-patch (bgj3 failure mode), this is compiled-in source code on the active render path — pattern-presence is sufficient."
---

# OpenCode TUI turn-summary timestamp (local customization: shortDateTime 24h+date format)

## Regression History

- **2026-09-18 11:32 CEST** — Patch silently lost AGAIN, same failure mode as 2026-07-22. A bash-lifecycle session rebuilt the binary from branch `fix/bash-lifecycle-group-cleanup`, which did NOT carry this patch (nor 5 other TUI patches). Detected by the operator after timestamps vanished from the interactive TUI. Restored 2026-09-18 19:17 by creating branch `fix/all-patches-v1.18.5` (cherry-picks 23020f01c + 0ba2467295 + 5 TUI patch commits), rebuilding, and runtime-verifying `▣ … · 5.1s · 7:19 PM` on the TUI surface. Pushed to fork `EZotoff/opencode`.
- **2026-09-18 (audit finding)** — The TUI surface is implemented by a SEPARATE commit `0ba2467295` ("fix(tui): add turn-completion timestamp to interactive TUI") that earlier reapply instructions did not include; the `verification_pattern` (todayTimeOrDateTime) also matches upstream code, so the verifier reported APPLIED while the patch was absent.
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

This patch has TWO surface commits: `23020f01c` (cli-run, 6 files under `packages/opencode/src/cli/cmd/run/`) and `0ba2467295` (tui-interactive, `packages/tui/src/routes/session/index.tsx`, 3 insertions). BOTH are required; the TUI commit was historically missed (2026-09-18 audit). To reapply after an OpenCode update:

1. Identify the new live version: `~/.opencode/bin/opencode --version`.
2. In `$HOME/src/opencode`, branch from `fix/all-patches-v1.18.5` (the aggregate branch carrying ALL tracked binary patches, pushed to fork `EZotoff/opencode`). For a new upstream version: cherry-pick ALL patch commits from `fix/all-patches-v1.18.5` onto a fresh branch off the release tag. Ancestry is the completeness check, not pattern greps.
3. Apply both commits (cherry-pick `23020f01c` and `0ba2467295`, resolve context drift). The cli-run change is mechanical: add `time?: string` to four type signatures, append ` · ${time}` to the summary text, populate `time` from `Locale.todayTimeOrDateTime(<ms>)` in both `runtime.queue.ts` (live turns) and `turn-summary.ts` (`messageTurnSummaryCommit` for replay).
4. Port the three test files (or re-run them as-is if the upstream code hasn't diverged).
5. Build: `cd packages/opencode && OPENCODE_VERSION=<X.Y.Z> bun run script/build.ts --single --skip-install --skip-embed-web-ui`.
6. Verify built binary `--version` matches live. The `todayTimeOrDateTime` grep is NOT sufficient (matches upstream code — this let the 2026-09-18 loss pass verification). The ONLY sufficient check: render a turn in the interactive TUI and confirm the summary line ends with ` · <time>`.
7. Stop services: `systemctl --user stop omo-tg.service opencode.service`.
8. Swap binary. If interactive TUI clients hold the file busy, use the Linux `mv` + `cp` pattern: `mv ~/.opencode/bin/opencode ~/.opencode/bin/opencode.old-<v>-pre-turn-summary-timestamp && cp dist/opencode-linux-x64/bin/opencode ~/.opencode/bin/opencode && chmod +x ~/.opencode/bin/opencode`. Running TUI clients keep the old inode; new invocations get the new binary.
9. Restart services: `systemctl --user start opencode.service omo-tg.service`.
10. Confirm fresh start time: `ps -eo lstart,args | grep 'opencode serve' | grep -v grep`.

## Durable Alternative

1. **Upstream PR (PREFERRED) — SUBMITTED 2026-07-20** — Opened [anomalyco/opencode#37929](https://github.com/anomalyco/opencode/pull/37929) (first attempt #37905 was auto-closed by the same compliance bot that killed the original #32771, for missing 4 of 6 required template sections). The upstream PR uses `Locale.time()` (locale-aware, time-only) — the user-facing default that respects every user's system settings. When merged and released, the upstream code path will produce locale-formatted times; this local patch will continue to override that with `Locale.shortDateTime()` (24-hour, date-inclusive) as a personal format customization.
2. Plugin/hook — Not viable: the turn summary is rendered deep inside the TUI scrollback writer; no plugin or system-prompt transform can inject text into that line.
3. Config option — Not viable: no config knob exists for the turn-summary format, and adding one is more invasive than the patch itself.

Status: pursued (upstream PR #37929 opened 2026-07-20, all compliance checks green, awaiting maintainer review as of 2026-07-23).
