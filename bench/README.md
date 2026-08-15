# ez-omo-bench

Benchmarking suite for the **installed** OpenCode + Oh-My-OpenAgent (OMO) stack on this machine. Each benchmark targets one **capability** — currently one OMO sub-agent (`oh-my-openagent.json#agents`) or one OMO task category (`oh-my-openagent.json#categories`) — and is authored via the `bench-author` skill (`skills/bench-author/`).

Two rules define the suite:

1. **Real-subject execution.** The sub-agent/category under test is exercised through the locally installed `opencode` (typically `opencode run --agent <name> --model <provider/model> --variant <v> --format json --dir <fixture-workspace>`). Engineered scripts only orchestrate invocation, capture, and aggregation — they never simulate the agent layer.
2. **Evaluation through opencode.** Judging is an opencode run too (a judge prompt with a rubric, executed with a designated strong model). Deterministic checks (tests, diffs) may supplement or, with justification in the benchmark's `DESIGN.md`, own objectively verifiable dimensions; a judge pass always exists.

All run output is machine-readable: every run writes `results/<run>/results.json` conforming to [schemas/results.schema.json](schemas/results.schema.json).

## Directory Layout

```
bench/
├── README.md                  # This file — conventions and suite contract
├── registry.json              # Machine-readable registry of all benchmarks (contract-tested)
├── schemas/
│   └── results.schema.json    # Machine-readable output contract for every run
├── shared-capability-assessment.md   # Written when the 10-benchmark gate fires (not yet)
└── <benchmark-id>/            # One directory per benchmark, e.g. agent-explore/
    ├── RESEARCH.md            # Stage 1 output: role analysis, session mining, external survey
    ├── DESIGN.md              # Stage 2 output: required sections (see bench-author skill)
    ├── PLAN.md                # Stage 3 output: ordered, verifiable development steps
    ├── tasks/
    │   ├── manifest.jsonl     # One JSON object per task:
    │   │                      #   task_id, provenance{kind,ref}, prompt, fixture, rubric_checks[], timeout_s
    │   └── <task-id>/fixture/ # Optional workspace files copied into a temp dir per run
    ├── judge/
    │   ├── PROMPT.md          # Judge prompt with the JSON-verdict-block contract
    │   └── RUBRIC.md          # Per-behavior checks mapped to DESIGN.md behaviors
    ├── run.sh                 # OPTIONAL thin orchestrator (opencode run invocations + capture only)
    └── results/
        └── <run-id>/
            ├── results.json   # Conforms to schemas/results.schema.json (committed)
            └── raw/           # Verbatim opencode run transcripts (committed if reasonable size)
```

## Registry Entry Contract

Every benchmark registers itself in `registry.json` (the `bench-author` skill does this; `tests/test_bench_registry.sh` enforces the shape):

```json
{
  "id": "agent-explore",
  "capability": { "kind": "agent", "name": "explore" },
  "status": "draft | designed | developed | validated | retired",
  "created": "2026-08-15",
  "bench_dir": "bench/agent-explore",
  "task_count": 12,
  "adapted_from": null,
  "config_fingerprint": "sha256:...",
  "design_session": "ses_...",
  "notes": ""
}
```

- `id` MUST be `<kind>-<name>` (kebab-case), unique.
- `config_fingerprint` = `sha256:` over the sorted, concatenated contents of `configs/oh-my-openagent/oh-my-openagent.json` + `configs/opencode/opencode.json` at design time. When either config changes, the registry fingerprint no longer matches the live files and the benchmark is **stale** (see below).
- `adapted_from` names the public benchmark family if tasks were adapted (with the compatibility analysis in `RESEARCH.md`); `null` for fully original corpora.

## Lifecycle and Ownership

| Phase | Owner | Artifact |
|---|---|---|
| Research → Design → Plan → Develop → Validate → Register | `bench-author` skill | `bench/<id>/` + registry entry |
| Campaign runs (provider/model selection, exclusions, repeats) | future `bench-lead` skill | `results/<run>/results.json` |
| Staleness re-validation, result presentation, next-work formulation | future `bench-lead` skill | run reports |

## Suite Contract (for the future bench-lead skill)

Recorded here so the orchestration skill has a documented foundation:

- **Inputs**: one or more model entities (`provider`/`model`/`variant`, the suite's `model_configs` dimension — validated against `configs/opencode/opencode.json#enabled_providers` and model definitions); optionally a list of excluded sub-agents/categories. Benchmarks must therefore accept `--model`/`--variant` overrides of the capability's assigned model.
- **Output**: machine-readable `results.json` per run (schema above), plus registry-tracked run summaries.
- **Execution**: through the locally installed opencode, for both experiments and evaluation (see the two defining rules).

## The Ten-Benchmark Shared-Capability Gate

Today a "capability" is a bundled configuration (prompt + model + tools + category routing) — it measures the installed stack, not the model in isolation. The operator (2026-08-15) wants to eventually assess **shared capabilities that models possess** (cross-role: instruction-following, tool discipline, context recall, planning depth, …) and evaluate them **separately**.

**Gate**: when `benchmarks` in `registry.json` reaches 10 entries, no benchmark #11 may be authored until the feasibility assessment is done — build the behavior matrix across the 10 `DESIGN.md`s, identify behaviors measured by 3+ benchmarks, assess whether shared-axis benchmarks are meaningful given confounds (different prompts/tools per role), write `bench/shared-capability-assessment.md`, set `shared_capability_review.assessed = true`, and present the outcome to the operator. `tests/test_bench_registry.sh` fails the suite while the gate is open.

## Staleness

Benchmarks measure the **installed** stack and record `config_fingerprint` at design time. When `oh-my-openagent.json` or `opencode.json` changes (agent model swaps, prompt_append edits, category re-routing, provider changes):

- Existing results remain valid **historical** evidence for the stack they recorded.
- The benchmark is stale for new runs until re-validated (diff the config sections that matter to the capability; update tasks/rubric if the role changed; refresh the fingerprint) or explicitly retired in the registry.

Authoring (`bench-author`) only records fingerprints; the staleness sweep across all benchmarks belongs to the future `bench-lead` skill.

## Session Data Provenance

The operator (2026-08-15) authorized using opencode session messages from this system **verbatim** in benchmark tasks — no censorship or privacy screening. Tasks derived from sessions cite the source session id in their manifest `provenance.ref`. Most active session stores: `~/omo-hub`, `/AI_projects/ANIA`, `/AI_projects/traveller`, `/AI_projects/kraken`, `/AI_projects/veran`, `~/ez-omo-config` — but any session on the system is fair game.
