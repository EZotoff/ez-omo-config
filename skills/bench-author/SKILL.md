---
name: bench-author
description: "Multi-stage research, design, planning, and development of a single ez-omo-bench benchmark for one capability — an Oh-My-OpenAgent sub-agent or task category. Exercises the real subject through the locally installed opencode for both experiments and evaluation; results are machine-readable. Use when asked to author, create, or build a benchmark for a specific sub-agent or category, to resume an in-progress benchmark, or when bench/registry.json names a benchmark as needing authoring."
---

# ez-omo-bench — Benchmark Authoring for One Capability

<role>
You are a benchmark engineer authoring ONE benchmark for ONE capability of the installed OpenCode + Oh-My-OpenAgent (OMO) stack. You drive the stages Research → Design → Plan → Develop → Validate → Register. You do NOT run full benchmark campaigns, present results to the operator, or re-validate stale benchmarks after config changes — those belong to the future `bench-lead` skill. Your deliverables: a validated benchmark directory under `bench/` and an updated `bench/registry.json`.
</role>

Conventions, directory contract, and the registry shape live in `bench/README.md` — read it before Stage 0. The machine-readable output contract is `bench/schemas/results.schema.json`.

## Hard Constraints (violating any invalidates the benchmark)

1. **Real-subject execution.** The sub-agent/category under test MUST run through the locally installed `opencode`. Canonical invocation:
   ```bash
   opencode run --agent <agent> --model <provider/model> --variant <v> \
     --format json --dir <fixture-workspace> \
     --title "ez-omo-bench/<benchmark-id>/<task-id>" "<task prompt>"
   ```
   Engineered scripts (`run.sh`) may orchestrate invocation, capture `--format json` streams, and aggregate machine-readable output — they MUST NOT simulate, stub, or short-circuit the agent layer. No direct provider-API calls with a copied prompt stack; no expected-output-only harness that never runs the subject.
2. **Evaluation through opencode.** The judge is an opencode run too: a judge prompt (from `judge/PROMPT.md`) plus rubric, executed with a designated strong model via `opencode run --model ... --variant ...` with the subject transcript attached (`--file`). The verdict of record defaults to the opencode judge. Deterministic checks (test suites, diffs, file existence) may own objectively verifiable dimensions ONLY with justification in `DESIGN.md` — and a judge pass must still exist for qualitative dimensions. The judge model MUST NOT be a model-under-test in the same run.
3. **Machine-readable output.** Every run emits `results/<run-id>/results.json` conforming to `bench/schemas/results.schema.json`, with raw transcripts preserved under `results/<run-id>/raw/`.
4. **Session-data authorization.** The operator (2026-08-15) authorized reading ANY opencode session on this system and reusing session messages VERBATIM in benchmark tasks, prompts, and rubrics — no censorship, no privacy screening. Most active stores: `~/omo-hub`, `/AI_projects/ANIA`, `/AI_projects/traveller`, `/AI_projects/kraken`, `/AI_projects/veran`, `~/ez-omo-config`; any others are equally authorized. Cite source session ids in task provenance.
5. **Registry is mandatory.** Stage 0 creates a `draft` entry; Stage 6 finalizes it. `tests/test_bench_registry.sh` enforces the shape and the Ten-Benchmark Gate.
6. **One capability per benchmark.** id = `<kind>-<name>` (`agent-<name>` / `category-<name>`).
7. **Fingerprint at design time.** Record `config_fingerprint` = `sha256:` over the sorted, concatenated contents of `configs/oh-my-openagent/oh-my-openagent.json` + `configs/opencode/opencode.json`. Staleness handling belongs to bench-lead; you only record.
8. **Model parameterization.** The benchmark MUST work with `--model`/`--variant` overrides of the capability's assigned model, so the suite can later compare provider/model/variant entities (the suite's `model_configs` input dimension).

## Target Enumeration and Execution Contract

### Enumerating capabilities (source of truth = installed config)

- **Agents**: keys of `oh-my-openagent.json#agents` (the repo store path and `~/.config/opencode/oh-my-openagent.json` are the same file). Cross-check OMO built-in agents defined in the local fork (`~/oh-my-openagent-v4.19.2/src/agents/`) that are not overridden in config — they are benchmarkable too; note their provenance.
- **Categories**: keys of `oh-my-openagent.json#categories`.
- Per capability, capture the effective config: `model`, `variant`, `fallback_models`, `skills`, `prompt_append`, and (agents) any OMO base-prompt file.

### Running an agent target

Use the canonical invocation above. Rules:

- **Default model** = the capability's assigned model at design time; record it. Overrides via `--model`/`--variant` are first-class (Constraint 8).
- **Fixtures**: copy `tasks/<task-id>/fixture/` into a fresh temp workspace per run (`mktemp -d`). NEVER run tasks inside the config repo or any real project.
- **Ports**: `opencode run` picks a random port by default — keep that; never pin ports (global `/deployment` mandate).
- **Capture**: the `--format json` stream goes verbatim to `results/<run-id>/raw/<task-id>-r<repeat>.jsonl`; extract session id and final assistant message from it.
- **Timeouts**: per-task `timeout_s` from the manifest; record `status: "timeout"` on expiry, do not retry silently.

### Running a category target

Categories are OMO `task()` routing tiers — there is no `--agent <category>`. Reproduce the effective stack faithfully and document it:

1. Determine the base agent OMO dispatches for the category (default: `sisyphus-junior`; VERIFY in the local fork source and cite file:line).
2. Apply `categories.<name>.model` and `.variant` via `--model`/`--variant`.
3. Apply `categories.<name>.prompt_append` to the task prompt exactly as OMO's task composition does (verify the composition rule in fork source; cite it).
4. Record the whole stack in `composed_from` on the target in every results file.
5. Optionally, a supplementary **parent-dispatch mode**: a lead session calls `task(category=...)` for real. This measures parent+category jointly — label those runs distinctly; never mix them into the isolated series.

### Cost and safety guardrails

- Pilots (Stage 5) run at most 2–3 tasks, sequentially.
- The global OMO circuit breaker (500 tool calls / 15 identical repeats) is the hard ceiling — size tasks to finish far under it.
- Every session gets the `--title "ez-omo-bench/..."` prefix for auditability.

## Stage 0 — Intake

1. Input: capability `kind` + `name`. Confirm it exists in the installed config (or fork agent inventory). If `bench/registry.json` already has a non-retired benchmark for it — stop and report the duplicate.
2. Capture the effective config snapshot for the capability (see above) and compute `config_fingerprint` (Constraint 7).
3. Create `bench/<id>/` skeleton and a registry entry with `status: "draft"`, `task_count: 0`, `config_fingerprint`, `design_session: <current session id>`.

## Stage 1 — Research (three lanes, run in parallel)

Write `bench/<id>/RESEARCH.md` with one section per lane. The agents doing Research and Design ARE authorized to read any opencode session on this system (Constraint 4) — invoke that authorization explicitly when delegating.

### 1.1 Role & prompt-stack analysis (what the capability IS)

Map the effective prompt stack bottom-up:

| Layer | Source |
|---|---|
| OMO base agent prompt | `~/oh-my-openagent-v4.19.2/src/agents/<name>.ts` (or fork dist) |
| Config overrides | `oh-my-openagent.json` `agents.<name>` / `categories.<name>` (model, variant, `prompt_append`, skills) |
| Global instructions | `~/.config/opencode/AGENTS.md` |
| Project instructions | `AGENTS.md` of the fixture workspace (design decides: usually none, to isolate) |
| Tools | tool list the agent type carries (from fork source / runtime agent registry) |
| Invocation contract | how a lead calls it: delegation table, `task(category=...)` routing, category descriptions |

Deliverable: **5–10 testable behavior claims** ("explore returns file paths and grep patterns, not prose", "oracle cites code it has read"), each traced to prompt/config evidence with file paths. These claims become rubric checks.

### 1.2 Session mining (how the capability is ACTUALLY used)

Find real usages with the session tools (`session_list` with `project_path`, `session_search`, `session_read`, `session_info`; or the shared `coding-agent-sessions` skill for cross-platform stores):

1. List sessions per authorized project (Constraint 4 lists the most active ones).
2. Search for the agent name / category word / typical delegation phrasing.
3. Read the matching sessions; extract per usage: the delegation prompt (verbatim task arguments), context provided, output shape, how the lead consumed the result, and failures.
4. Session messages may be embedded verbatim in tasks — no screening; cite session ids.

Deliverable: a usage table (session id → delegation prompt → outcome quality signal). If fewer than 3 real usages exist, say so explicitly and mark the corpus as constructed-dominant.

### 1.3 External benchmark survey (delegate to `librarian`)

How are similar agent types benchmarked? Survey families matching the role: coding (SWE-bench, terminal-bench), research/web (GAIA, BrowseComp), tool-use (τ-bench, AgentBench), planning, writing, multimodal, retrieval. For each: what it measures, task/eval format, and an **adaptability verdict**: adaptable ONLY IF its tasks can be replayed as prompt + fixture through a real `opencode run` of the subject in THIS environment, with LOCAL judging. Most public benchmarks fail this (external grading services, API-direct harnesses, browser-only environments) — documenting rejections is a required, respectable outcome. Adapted tasks must still cite their source benchmark and the adaptation deltas.

## Stage 2 — Design

Write `bench/<id>/DESIGN.md`. Required sections:

1. **Capability definition** — measured behaviors (from 1.1) and explicit out-of-scope statement. For categories: the full effective-stack composition with fork-source citations.
2. **Task corpus** — 10–30 tasks recommended (pilots may start with fewer). Per task: provenance (`mined-session` + session id | `adapted-public` + source | `constructed`), difficulty tier, fixture needs. Mined-session prompts are embedded verbatim where possible.
3. **Execution design** — invocation contract (model default + parameterization), fixture strategy, `timeout_s`, repeats, cost estimate for a full run.
4. **Evaluation design** — judge model (default: oracle-grade, e.g. `openai/gpt-5.6-sol` with high variant; never a model-under-test), rubric mapped 1:1 to behavior claims, judge output format (JSON verdict block: verdict ∈ pass|partial|fail, score 0–1, rubric_hits[], rationale), verdict-of-record policy (Constraint 2), and judge-gaming mitigations (rubric hidden from subject, no score leakage in task prompts, transcript not task text alone).
5. **Validity threats** — contamination (public benchmark tasks may be in training data; mined local sessions won't be), model nondeterminism (repeats), judge bias (fixed strong judge; spot-check with a second judge model), fixture leakage. Mitigation per threat.
6. **Acceptance criteria** — the benchmark itself is done when: schema-valid pilot results exist, judge verdicts parse, raw transcripts recorded, registry updated.

Present a DESIGN.md summary to the operator before Stage 4 when a full run would cost nontrivially or the design deviates from these defaults.

## Stage 3 — Plan

Write `bench/<id>/PLAN.md`: ordered, individually verifiable steps (fixtures → manifest → orchestrator → judge → pilot → registry), each with its verification command. This benchmark scope is single-worker sized — no `.omo/plans` ceremony needed unless the operator asks.

## Stage 4 — Develop

Implement the directory contract from `bench/README.md`:

- `tasks/manifest.jsonl` — one JSON object per task: `task_id`, `provenance{kind, ref}`, `prompt`, `fixture` (path or null), `rubric_checks[]` (ids into `judge/RUBRIC.md`), `timeout_s`.
- `tasks/<task-id>/fixture/` — workspace files (fixture workspaces must not be real projects; no secrets regardless of session authorization — session MESSAGES are authorized, credential FILES are not).
- `judge/PROMPT.md` + `judge/RUBRIC.md`.
- `run.sh` (optional) — bash, `set -euo pipefail`, orchestration only (opencode invocations, capture, aggregation via jq/python3). No subject simulation.

## Stage 5 — Validate (pilot)

1. Run 2–3 tasks end-to-end through opencode — subject run AND judge run — at the default model.
2. Verify: `results.json` parses AND conforms to the schema (structural check at minimum; `python3 -m jsonschema` if available); verdicts parse; raw transcripts exist; session ids recorded.
3. Fix and repeat until green. Record the pilot summary (tasks run, verdicts, deviations) in the registry entry notes.

## Stage 6 — Register & Report

1. Finalize the registry entry: `status: "validated"`, `task_count`, `adapted_from`, pilot notes.
2. Commit atomically (Conventional Commits).
3. Report to the operator using evidence-state language from `AGENTS.md`: the benchmark is `repo_implemented` + `tests_passed` (contract test) + pilot-evidenced (runtime run through live opencode observed); full-campaign claims belong to bench-lead.
4. **Gate check**: if `benchmarks` in the registry now has ≥ 10 entries and `shared_capability_review.assessed` is false — the Ten-Benchmark Gate below fires before any further authoring.

## The Ten-Benchmark Shared-Capability Gate

Today's capability = bundled configuration (prompt + model + tools + routing): benchmarks measure the installed stack, not the model in isolation. The operator (2026-08-15) wants, later, to assess **shared capabilities that models possess** (instruction-following, tool-use discipline, context recall, planning depth, output-format discipline, …) and evaluate them **separately** as cross-cutting benchmarks.

At ≥ 10 registered benchmarks (and before authoring #11 — `tests/test_bench_registry.sh` blocks this):

1. Build the behavior matrix: behaviors (from all 10 `DESIGN.md`s) × benchmarks.
2. Identify behaviors measured by 3+ benchmarks → candidate shared axes.
3. Assess feasibility: can a shared-axis benchmark run multiple agent stacks on one task battery meaningfully, given confounds (different tools/prompts per role)? Where is the model signal separable from the prompt-stack signal (e.g. via `--model` overrides within one benchmark)?
4. Write `bench/shared-capability-assessment.md`; set `shared_capability_review.assessed = true` and `assessment_ref` in the registry; present the outcome to the operator.

## Quick Reference

```text
Stage 0 Intake      → capability from installed config; registry draft; fingerprint
Stage 1 Research    → 1.1 prompt-stack + behavior claims (parallel)
                    → 1.2 session mining, verbatim reuse authorized (parallel)
                    → 1.3 external survey via librarian (parallel)
Stage 2 Design      → DESIGN.md (6 required sections)
Stage 3 Plan        → PLAN.md (verifiable steps)
Stage 4 Develop     → manifest.jsonl, fixtures, judge/, optional run.sh
Stage 5 Validate    → 2–3-task pilot through opencode; schema-valid results
Stage 6 Register    → registry finalized; commit; evidence-state report; gate check
```
