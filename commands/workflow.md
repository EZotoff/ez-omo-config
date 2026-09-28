---
description: "Run the full codified workflow — Design → Debate → Plan → Review → Implementation → Review → Closeout — for a task, without re-describing the stages"
---

# /workflow — the standardized end-to-end loop

Argument: the task description (what to build/fix/investigate). Optional flag `--lite` for bounded work (≤2 files or ≤30 min, single lane).

You (the orchestrator) run the following stages IN ORDER. Each stage has a gate; do not proceed past a failed gate. One episode manifest owns the whole run: create it at stage 3 (or earlier via `scripts/episode-receipt.sh append .omo/episodes/<slug> --checkpoint`).

## Stage 1 — Design
Gather context (explore/codegraph), identify constraints and the one-sentence destination. Output: a short design note (problem, approach, options considered, risks) kept in the working trail — it feeds the plan doc's background section.

## Stage 2 — Debate
Load the `debate` skill and run an adversarial pass on the design (challenge mode for small designs, panel for architecture-sized ones). The debate's verdict and strongest objections must be reflected in the plan. Gate: the debate must have produced a verdict; unresolved blockers become plan risks or kill the task early.

## Stage 3 — Plan
Write `.omo/plans/<slug>.md`: background (incl. design note + debate outcome), `## TODOs` as numbered checkboxes (`1.`, `2.`, …), `## Final Verification Wave` as `F1.`, `F2.`, … reviewer boxes. Plan must pass `bash scripts/execution-record-lint.sh plan <file>` would-be checks (structure, no F-boxes checked yet).

## Stage 4 — Review (pre-implementation)
Dispatch Momus on the plan. Momus operates under the 4+2 round budget with structured REJECT findings; the orchestrator records each round in `.omo/plans/<slug>.reviews.md` (one fenced ```json block per round: verdict, round, budget, plan_digest, findings, disposition, remaining_risks). Gate: verdict OKAY or OKAY-WITH-RISKS (or ESCALATE → stop, report to the operator). Ledger must pass `bash scripts/execution-record-lint.sh ledger <reviews.md>`.

## Stage 5 — Implementation
Execute the TODOs via delegated lanes (never implement yourself if you are the orchestrator). During execution:
- Stamp checkpoints: `scripts/episode-receipt.sh append .omo/episodes/<slug> --checkpoint --intent … --claims … --evidence-refs … --resume-pointer …` at meaningful boundaries.
- Cite immutable evidence (commit SHAs, frozen files) — never living documents.
- Mark each TODO `- [x]` only after orchestrator-verified evidence (tests run, files inspected).

## Stage 6 — Review (post-implementation)
Run the F-wave: independent reviewers covering (a) requirements alignment, (b) code quality, (c) hands-on QA. Record verdicts as `F#n: APPROVE|REJECT — evidence` lines in the plan's `## Execution Record` (create it with `Execution baseline: <full HEAD SHA>` before the first dispatch). REJECT → one consolidated fix lane → one delta re-review (max 2 full cycles). Gate: all F-boxes approved AND `bash scripts/execution-record-lint.sh plan <file>` exits 0.

## Stage 7 — Closeout
Load the `closeout` skill and produce the terminal summary from receipts only; append the closeout receipt; report `closeout.status`.

## --lite variant
For bounded work, skip stages 1–4 (a workorder replaces the plan): create `.omo/workorders/<slug>-<date>.md` per `docs/workorders.md` (must pass `scripts/workorder-lint.sh`), run one lane, teardown receipt, post-hoc checklist. Escalate to the full loop on scope drift / budget 2x / blocking dependency.

## Reporting to the operator
At the end, report: what ran, gate verdicts per stage, artifacts (plan, reviews ledger, evidence, closeout), and the honest status. Never claim runtime/live behavior that wasn't observed.
