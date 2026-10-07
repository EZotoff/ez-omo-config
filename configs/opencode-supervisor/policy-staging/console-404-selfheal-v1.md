# Console 404 self-heal v1 — APPLIED (Patches 2-3: a61c653, b733e38; Patch 1: shipped independently in c5b3595) — applied 2026-10-07

Staged: 2026-10-05, post-incident. Authorizing console ruling: "(b) Recommended, operator
green-light required. … once (a) executes, the storm is gone and deferring (b) costs nothing."

## Incident this prevents (2026-10-05, ANIA)

`consoles.json` bound `/home/ezotoff/AI_projects/ANIA` → console session
`ses_f6b1a0e31ffe3RXAmGU0npuL2Z`, which had been deleted from the OpenCode DB (2026-10-02
db-fix/session archive). `pollReplies()` (supervisor/src/console.ts:433) fetched that session
every ~20s poll → 404 → ledger ERROR, forever: **4,721 ERROR records in one day (~170/hour,
one per poll interval)**. The hourly error-storm auto-investigation re-crossed its threshold-10
in the first minute of every hour window and dispatched **10 duplicate
`[Supervisor] error investigation (ANIA)` sessions** (06:15Z–18:22Z), each re-diagnosing the
same signature. Two escalations surfaced via the console channel — i.e. into the dead session —
so the ticket text was never persisted to any live session; it was only visible as
operator-view cards, and the investigators' "shall I apply the fix?" could not be answered
through the channel at all.

Emergency remediation (a) applied 2026-10-05 ~21:14Z: backup `consoles.json.bak-20261005-211426`,
stale entry removed, supervisor restarted, fresh console session `ses_ef2815bd6ffege6BHLZ1twH8ZV`
created, ANIA error rate 0 across the post-restart verification window.

## Patch 1 — 404 → clear/recreate the console binding (console.ts)

`pollReplies()` (and any console-session fetch path) must distinguish 404 "Session not found"
from other failures. On 404 for the bound console session:

1. Drop the binding (and its watermark) for that root in the consoles state file.
2. Append one ledger `ERROR` with `reason: "console session deleted — binding cleared for re-ensure"`
   (single event, not one per poll).
3. Let the existing `ensure()` path recreate a fresh console session on the next loop/restart.

Guard rails: only clear on a definitive 404 (not 5xx/timeouts); clear at most once per binding
(ledger marker or in-memory set) so a pathological server cannot cause clear/create churn.

## Patch 2 — per-session fetch-error backoff (poller/reconcile)

Root-level backoff exists (`rootBackoff` in service.ts); session-level does not — that is why one
dangling sessionID produced an error every poll for ~13h. Add a per-sessionID failure counter in
the reconcile/poll fetch path: after N consecutive failures for one session, skip that session's
fetch for 2^k minutes (cap ~30m, mirroring rootBackoff), emit one `ERROR` on entering backoff and
one on recovery. Stale-session eviction falls out: a session that stays in backoff past
`initial_window_days` relevance simply stops being fetched; the 404 class additionally gets
Patch 1's binding cleanup.

## Patch 3 — cross-hour investigation dedup (investigation.ts)

`errorHour.investigated` resets with the hourly window, so a persistent storm re-fires the
dispatcher every hour (10 duplicates this incident). Add a signature fingerprint (dominant error
string, first 120 chars, normalized sessionIDs out) persisted in the investigation state:
skip dispatch when the same signature was investigated within `dedup_window_h` (default 6h) —
log `TICK_SKIPPED`-style ledger event `investigation deduped: known signature` instead. A new
signature always dispatches immediately.

## Test plan (RED → GREEN, per suite)

- console-channel.test.ts: dead-session 404 → binding cleared exactly once, ledger event emitted,
  fresh session ensured; 5xx → binding retained.
- reconcile/poller test: 3 consecutive per-session failures → backoff entered, fetches skipped,
  single ERROR; recovery clears it.
- investigation.test.ts: same signature inside the dedup window → skipped with ledger event;
  different signature → dispatched.

## Evidence discipline

In-repo supervisor code — no `.sisyphus/patches/` entry, no fork lifecycle. Post-deploy evidence
required before flipping any doc claim beyond `tests_passed`: one injected dead-binding drill
(scratch state file) producing exactly one cleanup ERROR + a recreated binding, plus a live
ledger window with zero repeat 404s. `status.json#errorInvestigations` should advance only on
new signatures.

## Applied (2026-10-07)

- Patch 1 (404 → clear/recreate the console binding): shipped independently in `c5b3595`.
- Patch 2 (per-session fetch-error backoff): `a61c653`.
- Patch 3 (cross-hour investigation dedup): `b733e38`.
- Live receipt: `.omo/evidence/console-404-selfheal/deploy-receipt.json` (written by the deploy step).

Recorded deltas from this proposal:

1. The dedup event is the typed ledger event `INVESTIGATION_DEDUPED` (registered in `LEDGER_TYPES`, `supervisor/src/types.ts`) rather than the proposal's `TICK_SKIPPED`-style reason string.
2. The backoff recovery ERROR from the proposal IS implemented — one `ERROR` on entering backoff and one on recovery (`supervisor/src/reconcile.ts`).
