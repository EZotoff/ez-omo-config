# Plan Review Ledger (`.omo/plans/<plan>.reviews.md`)

Spec for the per-plan review ledger produced by the plan-review loop (Momus reviews, atlas/orchestrator calls them). W2 of the workflow-standardization episode ([plan](../.omo/plans/workflow-standardization.md), Architecture §4 Momus bullet + W2 alignment addendum).

## Ownership

- **The REVIEW CALLER (atlas/orchestrator) writes the ledger file.** Momus only emits a ready-to-paste ledger block per review round (via its `prompt_append` contract in `configs/oh-my-openagent/oh-my-openagent.json`).
- The repo **lint (built in another W2 lane, `tests/test_execution_record_lint.sh`) enforces this schema** — budget counting and stop-verdict presence are checked mechanically, not trusted to the prompt.
- One ledger file per plan: `.omo/plans/<plan>.reviews.md`, append-only, one entry per review round.

## File format

```markdown
# Reviews — <plan-name>

## Round <n> — <date> — <verdict>

- verdict: OKAY | REJECT | ESCALATE | OKAY-WITH-RISKS
- plan_digest: <sha256 of the plan file at review time>
- budget: 4+2: round <n>/6 (<standard|evidence-gated — new evidence: <clause>>)
- disposition: <what the caller did with this round: fixed / accepted-risk / escalated / closed>
- remaining_risks: <comma list or "none">

### Findings
| locator | severity | claim | required_change | evidence | blocking_rationale |
|---|---|---|---|---|---|
| file:line or section | CRITICAL\|MAJOR\|MINOR | ... | ... | ... | ... |

(empty section / "none" for OKAY rounds)
```

## Field spec

| Field | Requirement |
|---|---|
| `verdict` | One of `OKAY`, `REJECT`, `ESCALATE`, `OKAY-WITH-RISKS`. |
| `plan_digest` | `sha256sum` of the plan file's bytes as reviewed — binds the verdict to an immutable plan state; delta reviews compare digests. |
| `budget` | Round number plus budget state, e.g. `4+2: round 3/4 standard`, `4+2: round 5/6 evidence-gated — new evidence: fix commit abc123`. |
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
- Rounds 5–6: extension rounds, permitted **only** when new material evidence appeared since the last round (fix commit, changed plan section, new artifact). The evidence clause must be cited in `budget`.
- After round 6 (or when no extension is justified after round 4): the final round's verdict MUST be `ESCALATE` or `OKAY-WITH-RISKS` — never another `REJECT`. An unbounded REJECT loop violates the contract; the lint fails a ledger whose last round is a REJECT at budget exhaustion.

## Delta review

Re-review entries target only sections changed since the prior round's `plan_digest`, plus a regression scan of prior blocking findings (each prior finding confirmed-fixed or reopened, cited by round number). Unchanged sections are not re-litigated.
