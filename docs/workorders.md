# Workorders — the `--lite` lane (`.omo/workorders/`)

Spec for the lightweight execution lane. W3 of the workflow-standardization episode ([plan](../.omo/plans/workflow-standardization.md) §4 start-work bullet, TODOs 11 + 14). Validated mechanically by `scripts/workorder-lint.sh` (QA in `tests/test_workorder_lint.sh`).

## When to use the lite lane

The lite lane is for **bounded, single-lane work that does not deserve a plan**. Use it when ALL of these hold:

- Scope is **≤2 files or ≤30 minutes** (whichever bound you state in `budget:`).
- **Single lane** — no parallel sub-agents, no worktree, no cross-repo coordination.
- **No plan required** — the work fits the episode's active plan but is not itself a plan-level deliverable.

Anything larger, multi-lane, or plan-shaped goes to the full lane (episode manifest + phases) instead.

## Workorder file format

One file per workorder: `.omo/workorders/<slug>-<date>.md` (e.g. `.omo/workorders/retry-log-rotate-2026-09-24.md`). `.omo/` is gitignored — examples live inline here, never as committed files.

```markdown
# Workorder: <slug>

intent: one sentence — what this workorder achieves and why
budget: 30m            # or: 2 files — the bound you commit to
status: open           # open | done

## Scope

- path/to/file1        # every file the workorder may touch
- path/to/file2

## Teardown checklist

- [ ] artifacts cleaned / temp files removed
- [ ] no stray ports, processes, or background jobs
- [ ] docs updated where the change is user-visible

## Escalation

<!-- optional; delete if none. If present, name the trigger: -->
none                    # scope-drift | budget-2x | blocking-dependency | none

## Teardown receipt

<!-- REQUIRED before status: done. Exactly one of: -->
closeout.status: complete
<!-- or: episode-receipt: .omo/episodes/<slug>/manifest.yaml seq <n> -->
```

## Required fields (lint-enforced)

| Field | Requirement |
|---|---|
| `intent:` | Non-empty one-liner in the preamble (before the first `## ` heading). |
| `budget:` | Non-empty bound in the preamble: `30m` (≤30m) or `2 files` (≤2). Larger budgets fail the lite-bound lint. |
| `status:` | `open` or `done`, in the preamble. |
| `lane:` | Optional. `lane: full` opts out of the lite-bound check (budget ≤30m / scope ≤2 files) — for workorders that knowingly left the lite lane. |
| `## Scope` | ≥1 listed file path, ≤2 unless `lane: full` (lite-bound enforced). Scope is a closed list — files outside it are drift. |
| `## Teardown checklist` | Present, ≥1 checklist item. |
| `## Teardown receipt` | REQUIRED on completed workorders only (see below). |
| `## Escalation` | Optional; if present and not `none`, it must NAME a trigger. |

## Teardown receipt (required at completion)

A workorder is **completed** when `status: done` (or any checklist item is checked). Every completed workorder MUST carry a teardown receipt — one of:

1. **`closeout.status: complete|degraded|failed`** line in the `## Teardown receipt` section, or
2. **an episode-receipt appended on a workorder episode**: `episode-receipt: <episode-dir> seq <n>` referencing an `episode-receipt.sh append` receipt in that episode's manifest.

No receipt = the workorder is not done. The lint refuses it.

## Post-hoc checklist (drift review)

On completion, before writing the receipt, answer the checklist:

- **Did scope hold?** Every touched file must be in the Scope list.
- **Did budget hold?** Elapsed effort vs the stated bound.
- **Any drift → mandatory follow-up**: append a `follow_ups:` entry to the episode manifest (Supervisor consumes it). Drift is never silently absorbed into "done".

Mechanically: every checklist item must be checked (`- [x]`) on a completed workorder; an unchecked item fails the lint.

## Auto-escalation triggers

Any of these escalates the workorder out of the lite lane to a full lane/episode — write the trigger into `## Escalation`, set `status: open`, and open an episode:

- **scope-drift** — work needs a 3rd file (when budget was file-bounded) or scope grew beyond the closed list.
- **budget-2x** — elapsed effort exceeded 2× the stated budget.
- **blocking-dependency** — the workorder is blocked on another lane, session, or external event.

## §Scribe — index, never authority

Scribe summaries (session summaries produced by scribes/assistants) are an **INDEX, never an authority**:

- A scribe's session summary may **locate** work (which session, which files, roughly when) but never **substitutes** for receipts or evidence.
- Decisions derive from **manifests + receipts only**. A summary claiming "done" without a receipt is not done; a summary claiming a decision without a manifest entry is not a decision.
- Closeout and review consume manifests, receipts, and the workorder's teardown receipt — never scribe prose.

## Lint

```bash
scripts/workorder-lint.sh <file>      # validate one workorder (flags only)
scripts/workorder-lint.sh --template  # print a skeleton workorder
```

Header fields (`intent:`, `budget:`, `status:`, `lane:`) must appear in the preamble — before the first `## ` heading; the lint ignores them below it. The lint also enforces the lite bounds mechanically: budget parses as `Nm` with N≤30 (or `N files` with N≤2) and `## Scope` lists ≤2 files, else it flags "exceeds lite bounds — escalate to full episode"; `lane: full` opts out.

Exit 0 = pass, 1 = violations, 2 = usage error. The `--template` skeleton passes its own lint.
