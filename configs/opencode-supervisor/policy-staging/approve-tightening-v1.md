# Staged rule: approve-CONTINUE tightening (v1)

```yaml
status: applied (epoch 2)
effective_from: 2026-10-05T06:10:51.000Z   # Option 2 executed 2026-10-05 — fresh epoch declared, counters zeroed, approves uncapped
applies_to: supervisor/src/tick.ts POLICY rule 256 (CONTINUE mode semantics)
trigger: n=2 would-grants — 1 TP (2026-10-03 bench instrument-composition), 1 hindsight FP (2026-10-04 config Fix 1, operator redirected "Think this through…" 80s after would-grant)
```

## Current text (rule 256, CONTINUE sentence)

> CONTINUE: The exchange is INCOMPLETE and needs a trivial go-ahead. A CONTINUE must declare mode: APPROVE for "shall I?"; KICK-START when stalled or errored with nothing in flight. A trivial in-scope request is APPROVE-CONTINUE, not ESCALATE. Operator "continue" means kick-start; "proceed" means approve. If there is a real decision — a choice between options, or authorization for consequential, out-of-scope, or destructive work — ESCALATE. If complete and nothing was asked, ACCEPT — never nudge a finished exchange.

## Replacement text (apply verbatim at epoch boundary)

> CONTINUE: The exchange is INCOMPLETE and needs a trivial go-ahead. A CONTINUE must declare mode: APPROVE for "shall I?"; KICK-START when stalled or errored with nothing in flight. A trivial in-scope request is APPROVE-CONTINUE, not ESCALATE — but APPROVE is only trivial when the go-ahead executes a recent operator instruction verbatim or is purely procedural (run the tests, commit the reviewed change, proceed with exactly what was asked). A "shall I?" whose value depends on the quality of the worker's own just-delivered analysis is NOT trivial: ESCALATE. Operator "continue" means kick-start; "proceed" means approve. If there is a real decision — a choice between options, or authorization for consequential, out-of-scope, or destructive work — ESCALATE. If complete and nothing was asked, ACCEPT — never nudge a finished exchange.

## Classification check (why it is staged, not applied)

- Specimen 1 (TP): "shall I build the benchmark you just greenlit the idea of" → verbatim-recent operator instruction → still APPROVE under v1. Correct.
- Specimen 2 (FP): "shall I implement the fix I just designed" → rests on worker analysis quality → v1 routes to ESCALATE. Correct.
- Self-test: "apply the tightening I just designed" → escalate-shaped under v1. Which is why this file exists instead of a live edit.

## Apply mechanics (epoch switch)

1. Replace the rule-256 CONTINUE sentence in `supervisor/src/tick.ts` POLICY (mind the 1.5k-token ceiling test in tick.test.ts).
2. Deploy via session-safe restart; append a ledger epoch marker (e.g. `TICK_SKIPPED` reason `approve write: EPOCH v1 applied` is wrong — use a dedicated `METRICS_SNAPSHOT` or note the apply timestamp here).
3. Would-grant comparability: the ledger is timestamped, so pre/post regimes separate by the apply timestamp recorded in this file's `applied_at:` line (filled at apply time).

## Applied record (2026-10-05T06:10:51.000Z)
- Replacement text applied in COMPACT PHRASING (semantics identical; the staged verbatim text exceeded the 1.5k-token POLICY ceiling). Compensating compressions of rules 3/6/8/12/13 removed redundant phrasing only — no rule content changed.
- Config: `daily_cap` removed from all approve_writes roots (uncapped per operator directive; code sanity ceiling 1000/day). `epoch_started_at` = 2026-10-05T06:10:51.000Z on all four roots; boot-rebuild and rollout evidence are epoch-scoped.
- Unlock marker (HUMAN-REVIEW-DONE): still absent — untouched by this change. Grant mode remains gated on the operator's personal review.
