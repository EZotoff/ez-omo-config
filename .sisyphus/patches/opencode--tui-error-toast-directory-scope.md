---
patch_id: "opencode--tui-error-toast-directory-scope"
dependency: "opencode"
target_file: "packages/tui/src/app.tsx"
target_install_path: "/home/ezotoff/.opencode/bin/opencode"
source_repo: "/home/ezotoff/src/opencode"
status: "staged"
applied_date: "2026-10-03"
dep_version: "1.18.31-p2"
runtime_effective: false
runtime_effective_note: "Built (14d3a583, source 5dd34e7199) but NOT yet installed — idle gate refused the swap (6 busy sessions incl. an active LLM bench campaign). Flip to true only after observing a foreign-directory probe error produce NO toast in the live TUI."
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
