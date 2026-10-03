---
patch_id: "opencode--tui-error-toast-directory-scope"
dependency: "opencode"
target_file: "packages/tui/src/app.tsx"
target_install_path: "/home/ezotoff/.opencode/bin/opencode"
source_repo: "/home/ezotoff/src/opencode"
status: "active"
applied_date: "2026-10-03"
dep_version: "1.18.31-p3"
runtime_effective: false
runtime_effective_note: "LIVE since the 1.18.31-p3 cutover (2026-10-03 14:46): p3 was built from the 5dd34e7199 lineage that contains the tui-toast commits — identical source to staged receipt 14d3a583, so the separate staged swap is MOOT. Source gate verified in tree (sync-guard.ts, 6/6 unit tests green); verification_pattern does not survive minification (function name). runtime_effective flips true on live observation: foreign-directory probe error produces NO toast in the TUI."
upstream_issue: "none"
verification_pattern: "shouldApplySessionEvent"
verification_strength: "weak"
required_evidence: "provenance"
surfaces: ["tui-interactive"]
---

# OpenCode TUI session.error toast directory scope

## Problem

Every `session.error` event was auto-toasted by the TUI as long as its `workspace`
metadata matched `project.workspace.current()`. But the workspace guard leaks:
the default TUI has `workspace.current === undefined`, and events from
`projectID=global` scratch sessions (e.g. `/tmp/opencode/*` probe sessions, whose
git-root resolution fails and which report no workspace) carry
`workspace: undefined` too. `undefined !== undefined` is false, so the guard
passed and foreign probe errors — rate-limit retries, FK constraint failures from
the attach-fanin regression test's session deletes — toasted in the operator's
TUI. Frequency spiked ~10× from 2026-10-01 with the attach fan-in verification
probes and bench campaigns (35 `prompt_async failed` on Oct 1 vs a 1–15/day
baseline).

## Patch Description

In `packages/tui/src/app.tsx`, the `session.error` handler now destructures
`directory` from the event metadata and additionally applies the existing
`shouldApplySessionEvent(sync.data, sessionID, directory, sdk.directory, kv)`
guard (from `opencode--event-scope-attach-congestion` S2, sync-guard.ts) before
showing the toast. Semantics: own-directory errors toast; errors for sessions
already present in the store (legitimately observed/pinned foreign sessions) keep
toasting; unknown foreign sessions are silent. The workspace guard is kept as a
first filter.

Implementation commit: `5dd34e7199` ("fix(tui): scope session.error toasts to
the TUI directory/session scope") on `fix/v1.18.31-question-stall-watchdog`,
pushed to `EZotoff/opencode`.

## Verification

Pattern (necessary, NOT sufficient — `shouldApplySessionEvent` is a module-local
minified-away symbol; the pattern only proves the sync-guard module is bundled,
which is true of pre-patch binaries too):

```bash
grep -a -c 'shouldApplySessionEvent\|session_directory_filter_enabled' /home/ezotoff/.opencode/bin/opencode
```

Authoritative evidence for this patch is provenance: build receipt
`97f4ee2e38b144ef93760988bce7ab1b098ca42c15c54309872109de2b170f38` binds binary
sha256 → source head `5dd34e7199` via the lockfile ancestry chain
(`build-and-install-opencode.sh build`).

## Runtime Verification

Required before flipping `runtime_effective: true`:

1. Install the receipted binary (idle gate must pass or the operator explicitly
   authorizes a busy-session restart).
2. Create a scratch session in a foreign directory (e.g.
   `mktemp -d /tmp/opencode/toastcheck.XXXX`), fire a `prompt_async` that errors
   (e.g. against a rate-limited provider), and observe the live TUI: no toast
   may appear for the foreign session.
3. Fire an error in the TUI's OWN directory (e.g. invalid model in the current
   project) and confirm the toast still appears (regression guard).
3. Fire an error in the TUI's OWN directory (e.g. invalid model in the current
   project) and confirm the toast still appears (regression guard).

## Install Deferral (2026-10-03 operator decision)

Option B: the staged swap (receipt `97f4ee2e`, already in
`~/src/opencode/packages/opencode/dist/`) is DEFERRED to the next idle window,
shared with the Q3 install gate. The integrity-check RED (provenance
ancestry-fail on commit `5dd34e7199` vs live binary receipt source_head
`977b8a4d97`) is acknowledged fail-visible noise — all 38 patches remain
grep-APPLIED. Idle-window sequence: (1) continuation-hook fixes verified via
dry-run snapshot, (2) staged swap via continuation-safe procedure,
(3) verify-live-patches GREEN + fresh hooks.log start. Standing exception:
only an explicit operator "install it now" authorizes an immediate busy-session
restart; repeated RED alerts do NOT constitute implicit urgency. If alert noise
becomes a problem before the window opens, snooze the provenance alert instead
of rushing the swap.

Continuation-hook fix note: the resume retry loop's `retry_secs` NameError
(crash on first retryable prompt_async failure, observed in hooks.log
2026-10-03 09:20:39) was fixed 2026-10-03 — `RESUME_RETRY_SECONDS` env
(default 60s), bash -n + py compile + dry-run snapshot verified.
