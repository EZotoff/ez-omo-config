# Plan Review Ledger (`.omo/plans/<plan>.reviews.md`)

Spec for the per-plan review ledger produced by the plan-review loop (Momus reviews, atlas/orchestrator calls them). W2 of the workflow-standardization episode ([plan](../.omo/plans/workflow-standardization.md), Architecture §4 Momus bullet + W2 alignment addendum).

## Ownership

- **The REVIEW CALLER (atlas/orchestrator) writes the ledger file.** Momus only emits a ready-to-paste ledger block per review round (via its `prompt_append` contract in `configs/oh-my-openagent/oh-my-openagent.json`).
- The repo **lint (`scripts/execution-record-lint.sh ledger`, QA in `tests/test_execution_record_lint.sh`) enforces this schema and the budget/hard-stop rules mechanically** — not trusted to the prompt.
- One ledger file per plan: `.omo/plans/<plan>.reviews.md`, append-only, one record per review round.

## File format (canonical: fenced JSON)

The canonical ledger record is **one ```json fenced block per review round** (machine-checkable). Markdown prose between blocks is allowed for context and is ignored by the lint. Non-`json` fenced blocks are ignored.

```markdown
# Reviews — <plan-name>

## Round 1 — 2026-09-24 — REJECT

Optional prose context here (ignored by the lint).

```json
{
  "verdict": "REJECT",
  "round": 1,
  "budget": {"standard_used": 1, "standard_max": 4, "extensions_used": 0, "extensions_max": 2},
  "plan_digest": "<sha256 of the plan file at review time>",
  "findings": [
    {
      "locator": "file:line or plan section",
      "severity": "CRITICAL",
      "claim": "what is wrong, one sentence",
      "required_change": "concrete change that resolves the finding",
      "evidence": "command output, path, quote, or reference proving the claim",
      "blocking_rationale": "why this blocks an OKAY verdict"
    }
  ],
  "disposition": "fixed",
  "remaining_risks": []
}
```
```

Findings is an **array** (empty for OKAY rounds; risks-as-findings with `severity: MINOR` and a non-blocking `blocking_rationale` recommended for OKAY-WITH-RISKS).

## Field spec

| Field | Requirement |
|---|---|
| `verdict` | One of `OKAY`, `REJECT`, `ESCALATE`, `OKAY-WITH-RISKS`. |
| `round` | Round number, 1-based. Must be monotonically 1..N in file order (see mechanical rules). |
| `plan_digest` | `sha256sum` of the plan file's bytes as reviewed — binds the verdict to an immutable plan state; delta reviews compare digests. |
| `budget` | Round-budget usage. Rounds 1–4: any object/string form. Rounds ≥5: MUST be an object containing `extended: true` and non-empty `extension_evidence` (string or array). |
| Findings array | Structured REJECT schema below. Required (≥1 CRITICAL/MAJOR) for REJECT; empty for OKAY; risks-as-findings (MINOR, non-blocking) recommended for OKAY-WITH-RISKS. |
| `disposition` | Caller's action for the round (not Momus's). |
| `remaining_risks` | Accepted-but-unresolved risks at this round; must be non-empty for OKAY-WITH-RISKS. |

## Structured REJECT finding schema

Every REJECT finding carries all six fields:

- `locator` — `file:line` or plan `section` identifier
- `severity` — `CRITICAL` | `MAJOR` | `MINOR`
- `claim` — what is wrong, one sentence
- `required_change` — concrete change that resolves the finding
- `evidence` — command output, path, quote, or reference proving the claim
- `blocking_rationale` — why this blocks an OKAY verdict

## Budget and hard stop (4+2)

- Rounds 1–4: standard.
- Rounds 5–6: extension rounds, permitted **only** when new material evidence appeared since the last round (fix commit, changed plan section, new artifact). The evidence must be cited in `budget.extension_evidence` with `budget.extended: true`.
- After round 6 (or when no extension is justified after round 4): the final round's verdict MUST be `ESCALATE` or `OKAY-WITH-RISKS` — never another `REJECT`. An unbounded REJECT loop violates the contract.

### Mechanical rules (enforced by `execution-record-lint.sh ledger`)

1. **Format** — at least one ```json fenced block; each block must be a single JSON object matching the field spec above (all six finding fields present on every finding).
2. **Monotonic rounds** — round numbers must be exactly 1..N in file order: no gaps, no duplicates.
3. **Extension evidence** — any round numbered ≥5 must carry `budget` as an object containing `extended: true` and a non-empty `extension_evidence` (string or array).
4. **Budget exceeded** — any round numbered >6 fails the lint (4+2 budget hard-capped at 6 rounds).
5. **Terminal verdict** — if the last round is numbered 6 and its verdict is `REJECT`, the lint fails; the terminal verdict at budget exhaustion must be `ESCALATE` or `OKAY-WITH-RISKS`.
6. **Fence integrity** — an unterminated (unclosed) ```json fence is a named lint failure.

## Delta review

Re-review entries target only sections changed since the prior round's `plan_digest`, plus a regression scan of prior blocking findings (each prior finding confirmed-fixed or reopened, cited by round number). Unchanged sections are not re-litigated.
