# Collect-vs-Decide — Design (codified 2026-10-02)

> This document was written *after* the implementation, codifying the behavior
> that `supervisor/src/collect.ts`, `tick.ts` (fork) and `operator-view.ts`
> already implement, so the `design §N` references in code comments resolve to
> something real. The original design doc referenced in early commits never
> existed in the repo (found in the 2026-10-02 schema-ghost postmortem).
> Where code and this doc disagree, the code and its tests win.

## §1 Deterministic forcing function

`detectProxies` (collect.ts) is the cheap, no-LLM trigger that synthesizes a
collect round when the model did not name any `information_needs`:

- `P-empty` — target reply has no assistant text (wedge vs deliberate silence).
- `P-cross` — STEER/ESCALATE cites only target-session evidence while siblings exist.
- `P-ref`  — rationale references context absent from the assembled context.
- `P-contra` — CONTINUE decided against contradiction words in the user turn.

Fired proxy reasons become concrete retrievable needs (`proxyNeeds`, tick.ts)
so the fork can open even when the model emitted `information_needs: []`.
Historical note: until 2026-10-02 the empty-needs early return preceded proxy
detection, making the forcing function unreachable dead code (telemetry
`collect.attempts` stayed 0 since launch).

## §2 Information needs

A need names `question`, `scope` (`sessions|ledger|cards`), `target`, `why`,
`expected_effect` — it must name retrievable evidence, never an operator
preference (POLICY rule 12). Max 3 per decision.

## §3 Executor and bounds

`CollectExecutor.run` resolves needs scope-by-scope under
`DEFAULT_COLLECT_BOUNDS`: per-need lookups, a deadline, a token cap, and a
history turn window. Results are truncated into evidence blocks.

## §4 Stake-scaled eligibility and signal hygiene

`collectEligible` (collect.ts): STEER/ESCALATE collect by default; CONTINUE
requires ambiguous health or a fired proxy; ACCEPT/REFORMULATE require a
proxy; ABSTAIN never collects; budget exhaustion disables the fork for every
action. Signal hygiene in the same spirit: probe/throwaway sessions are
classified before card computation (`isProbeTarget`, operator-view.ts) so a
probe burst neither adds nor displaces operator cards — a bare "OK" on a
one-shot probe is DELIVERED work, not a stall (live false positive 2026-09-22).

## §5 Budgets and caps (runaway guards)

- Collect: per-root daily rounds (15) and tokens (200k), per-session daily
  rounds (2) — `CollectBudget`. Telemetry in `status.json#collect`.
- Operator view: bounded active cards (`MAX_CARDS`), card text
  (`MAX_TEXT_CHARS`), premises (`MAX_PREMISES`/`MAX_PREMISE_CHARS`) — the read
  model stays small and fresh. Trims are sentence-boundary first, ellipsis-marked.

## §6 Confirmation pass

If the fork gathered non-empty evidence, a second LLM pass re-decides with the
evidence appended plus `CONFIRMATION_INSTRUCTION`; the decision may flip
(telemetry `changed`), and `evidence_effect` records
confirmed/disconfirmed/inconclusive.

## Gate

The action-dispatch bijection gate `tests/test_supervisor_dispatch.sh`
(run by `tests/run_all.sh`) enforces that every action in the tick schema has
a dispatch site in service.ts and runs the full unit suite + typecheck.
