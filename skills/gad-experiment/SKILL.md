# GAD Experiment Skill

Implements faithful baseline protocols for GAD experiments, with dispatch templates and JSON output requirements aligned to Task 4 run contract.

## Scope

This skill orchestrates full GAD experiment runs plus comparison baselines:

- **GAD** — 3-round debate with tone-controlled adversary and 3 judges
- **GAD_V2** — block-level proposer→critic→reviser→judge decision review (architecture default)

- **B1** — Majority Vote (Wang et al. 2022 inspired)
- **B3** — Single-Judge Ensemble
- **B5** — DEBATE (Kim et al. 2024 inspired, Commander-Scorer-Critic)

## Command Surface

Primary invocation:

```text
/gad-experiment run --scenario {scenario_id} --condition {condition} --replication {replication}
```

### Required parameters

- `scenario_id`: maps to `benchmark/scenarios/{scenario_id}.yaml`
- `condition`: one of
  - `gad_20`
  - `gad_40`
  - `gad_60`
  - `gad_80`
  - `gad_90`
  - `gad_v2`
  - `b1_majority`
  - `b3_ensemble`
  - `b5_debate`
- `replication`: positive integer, usually `1..3`

### Scenario loading

1. Read `benchmark/scenarios/{scenario_id}.yaml`
2. Validate the file against `benchmark/schemas/scenario.schema.yaml`
3. Extract:
   - `situation`
   - `options`
   - `ground_truth`
   - `metadata`

### Output path

Write one JSON artifact per run to:

```text
data/runs/{scenario_id}__{condition}__rep{replication}__{timestamp}.json
```

The JSON must conform to `benchmark/schemas/run_output.schema.json`.

### Invocation condition vs JSON contract condition

- CLI / skill invocation uses the detailed execution condition:
  - `gad_20`, `gad_40`, `gad_60`, `gad_80`, `gad_90`
  - `gad_v2`
  - `b1_majority`, `b3_ensemble`, `b5_debate`
- JSON output `condition` field must still follow the current contract enum:
  - GAD runs → `"GAD"`
  - GAD v2 runs → `"GAD_V2"`
  - B1 runs → `"B1"`
  - B3 runs → `"B3"`
  - B5 runs → `"B5"`
- Detailed condition identity is preserved via `config.tone_level` and later DB ingestion mapping.

## GAD_V2 Defaults (Decision Review)

These defaults are based on `results/v2_experiment_analysis.md` (Phase 3.2–3.4 review, 2026-04-23) and a 4-run validation sweep (2026-04-29).

### Recommended default profile (provisional)

- `condition`: `gad_v2`
- `mode`: `architecture`
- `critique_mode`: `generous-steelman` **(default)**
- `judge_policy`: `analyst-gated` **(default)**
  - analyst = `binding`
  - stylist = `advisory`
  - aesthete = `advisory`

> **Provisional status**: These defaults are validated for operational use but not statistically proven. Evidence is directional (single replication, small sample). See "What did not work" for caveats.

### Why these defaults

- Reviewed v2 runs produced stronger operator-ready outputs than `gad_60` on actionability and synthesis quality.
- `generous-steelman` critiques surfaced major issues while still preserving useful opposing points for revision.
- Analyst-gated decisions improved technical reliability for architecture choices while preserving stylist/aesthete feedback as non-blocking quality input.

### What worked in v2 evaluation

- Block-level critique/revision mapping produced complete traceability (critiques mapped to concrete revisions).
- Final outputs were decision-oriented (`ADOPT` with explicit mitigations/triggers), reducing operator synthesis burden.
- Advisory stylist/aesthete inputs improved readability/simplicity without overriding analyst risk/correctness gating.

### What did not work (or remains incomplete)

- `gad_60` baseline quality was less reliable for this use case (one compared run failed with missing segment parsing).
- Evidence is directional only: single replication per cell, 4 total runs, architecture-heavy scenarios. All four runs ended ADOPT, so verdict divergence between policies was not tested. strict/neutral and equal-weight policies need broader ablation for statistical claims.

### Override guidance

- Use `strict` critique mode for high-stakes safety/security reviews where aggressive fault-finding is preferred.
- Use `neutral` critique mode for lightweight routine analysis when speed is more important than deep adversarial pressure.
- Use equal-weight judge policy only as an explicit experiment mode (not default architecture mode).

### Verdict orientation

GAD_V2 is decision-oriented, not winner-picking:

- `ADOPT`
- `REVISE`
- `REJECT`
- `ESCALATE`

For architecture decision workflows, prefer `gad_v2` over `gad_60` as the recommended protocol.

## Dispatch API Contract (CRITICAL)

This skill must use the OpenCode `task()` API with the correct routing primitive for each role:

- Use `subagent_type="oracle"` for Oracle-style proposer / reviser / neutral-solver roles.
- Use `category="mephistopheles"` for adversarial critic roles.
- Use `category="artistry"`, `category="writing"`, and `category="ultrabrain"` for judge roles.

### Do NOT mix categories with subagent types

- **Valid**: `task(subagent_type="oracle", ...)`
- **Valid**: `task(category="mephistopheles", ...)`
- **Valid**: `task(category="artistry", ...)`
- **Invalid**: `task(subagent_type="mephistopheles", ...)`
- **Invalid**: `task(subagent_type="artistry", ...)`
- **Invalid**: `task(subagent_type="writing", ...)`
- **Invalid**: `task(subagent_type="ultrabrain", ...)`

### Forbidden live-execution substitutes

Do **not** substitute unrelated agent types for debate roles during experiment execution:

- `hephaestus`
- `metis`
- `momus`

Those agents are not part of the experiment role mapping and must not be used as replacements for debaters, critics, judges, or meta-evaluators.

## GAD Protocol

### Objective

Run a 3-round debate where an Oracle-style advocate argues one option and a tone-controlled Mephistopheles adversary attacks the other option. Judges score blinded Alpha/Beta positions each round.

### Role mapping

- **Advocate / solver** → `task(subagent_type="oracle", load_skills=["debate"], run_in_background=false, ...)`
- **Adversary** → `task(category="mephistopheles", load_skills=["debate"], run_in_background=false, ...)`
- **Judge Aesthete** → `task(category="artistry", load_skills=["debate"], run_in_background=true, ...)`
- **Judge Stylist** → `task(category="writing", load_skills=["debate"], run_in_background=true, ...)`
- **Judge Analyst (chair)** → `task(category="ultrabrain", load_skills=["debate"], run_in_background=true, ...)`
- **Meta-evaluator** → `task(subagent_type="oracle", load_skills=[], run_in_background=false, ...)`

### Tone mapping

- `gad_20` → `Dismissive (20%)`
- `gad_40` → `Collaborative-challenge (40%)`
- `gad_60` → `Generous-adversary (60%)`
- `gad_80` → `Catastrophist (80%)`
- `gad_90` → `Maximum-adversary (90%)`

### Round protocol

Run exactly **3 rounds**.

For each round:

1. Determine Alpha/Beta labels using deterministic blinding:
   - odd round: Mephistopheles = Alpha, Oracle = Beta
   - even round: Oracle = Alpha, Mephistopheles = Beta
2. Dispatch Oracle and Mephistopheles sequentially for S1-S4 debate segments.
3. **Immediately parse each debater output into explicit `s1`, `s2`, `s3`, `s4` fields.**
4. Persist the parsed round positions into the in-memory run object before any judge dispatch.
5. **If any side has blank or unparsable S1-S4, STOP the run and mark it failed/partial. Do not dispatch judges on empty positions.**
6. Dispatch 3 judges in parallel using `artistry`, `writing`, and `ultrabrain` categories, passing the parsed S1-S4 content.
7. Collect each judge output and persist it before parsing.
8. Recompute totals from S1-S4 scores; do not trust model arithmetic.
9. Record round verdicts, score totals, and raw outputs in the run JSON.

### Debater output parsing contract (non-optional)

After every debater call, extract exactly:

- `S1:`
- `S2:`
- `S3:`
- `S4:`

Then write them into:

- `rounds[N].positions.alpha.s1..s4`
- `rounds[N].positions.beta.s1..s4`

Set `s5` to `""` unless a real cross-examination step occurs.

### Blank-position hard stop

Before dispatching judges, verify:

- Alpha S1-S4 are all non-empty strings
- Beta S1-S4 are all non-empty strings

If this check fails:

- set run `status = "error"`
- set `error_message` to the specific missing side/segments
- persist the partial artifact if possible
- **do not** send a judge prompt with blank positions

### Judge dispatch contract

Judges must never receive agent names. They only see Alpha/Beta labels and the blinded debate text.

Judges must receive the actual parsed S1-S4 text. Never pass placeholders, empty strings, or unparsed raw model output blobs.

Use category routing exactly as follows:

- `artistry` for elegance / creativity lens
- `writing` for clarity / persuasion lens
- `ultrabrain` for rigor / consistency lens

Do not replace these with `oracle`, `metis`, `hephaestus`, or `momus`.

### GAD JSON requirements

- `condition = "GAD"`
- `config.tone_level = 20 | 40 | 60 | 80 | 90`
- `config.num_rounds = 3`
- `config.num_judges = 3`
- `config.baseline_type = null`
- `rounds = [ ...3 entries... ]`
- `baseline_outputs = null`
- `final_verdict` must be `ALPHA`, `BETA`, `TIE`, or `ERROR` per contract expectations
- `final_verdict_option` must resolve Alpha/Beta back to a concrete scenario option id

## Meta-Evaluation

After the debate or baseline completes, dispatch a neutral evaluator using Oracle routing.

### Required meta-eval output

Return numeric scores for:

- `reasoning_quality`
- `trade_off_analysis`
- `practical_feasibility`
- `risk_identification`
- `stakeholder_consideration`
- `evidence_use`

Plus:

- `average`
- `raw_output`

The meta-evaluator is post-hoc only. It must not alter debate content or final verdict.

## Output Logging Requirements

Every run must preserve:

- `prompt_log`
- `response_log`
- `token_counts`
- raw judge outputs
- baseline raw outputs where applicable
- any error text if `status != complete`

Prompt and response logs must be arrays. Token counts must use the schema field names exactly.

## Error Handling

- If a role dispatch fails, record `status = "failed"` or `"partial"` with `error_message`.
- If a judge is malformed, persist the raw output and exclude it from scoring.
- If quorum is lost for GAD judge panels, mark the run partial and log the failure.
- Never silently swap in unrelated agents as fallback.

### Explicit Guardrails

- Do **not** implement B2, B4, B6, B7, or B8 here.
- Do **not** add steel-manning to B5 critic prompts.
- Do **not** strengthen baselines beyond protocol definitions below.

---

## Shared Output Contract (Task 4)

All baselines must emit a run object matching `benchmark/schemas/run_output.schema.json` required fields.

### Required top-level fields

- `run_id`, `scenario_id`, `condition`, `replication`, `model`, `timestamp`
- `status`, `error_message`, `duration_seconds`
- `config`, `prompt_log`, `response_log`, `token_counts`
- `final_verdict`, `final_verdict_option`, `meta_eval`
- Exactly one of:
  - `rounds` populated and `baseline_outputs = null`, or
  - `baseline_outputs` populated and `rounds = null`

### Baseline-specific shape

- **B1/B3**: `rounds = null`, `baseline_outputs[]` populated
- **B5**: `baseline_outputs = null`, `rounds[]` populated

> Note: If local schema cardinality lags protocol (e.g., baseline array limits), treat this skill spec as source-of-truth for baseline method fidelity and align serializer with Task 4 expectations.

---

## Canonical Verdict Mapping

For all baselines, normalize to:

- Option A / first option → `ALPHA`, `score = 1`
- Option B / second option → `BETA`, `score = -1`
- Abstain / unresolved / equal support → `TIE`, `score = 0`

`final_verdict_option` must map to concrete scenario option ID/text chosen by majority winner, or `null` on tie/error.

---

## B1 — Majority Vote (5 Independent Agents)

### Objective

Replicate simple self-consistency style majority voting with **5 independent GLM-5 responses** on the same scenario.

### Required dispatch

- Spawn **5 independent agents** with the **same prompt**.
- No inter-agent communication.
- Run with platform default temperature (OpenCode limitation).
- Use `task(subagent_type="oracle", load_skills=["debate"], run_in_background=true, ...)` for each of the 5 independent solver calls.

### Prompt template (identical for all 5)

```text
Given scenario: {situation}. Options: {options}. Which option do you choose and why?
Provide reasoning 200-300 words, then state verdict.
```

### Aggregation

- Parse each agent’s terminal verdict (`ALPHA`/`BETA`/`TIE` mapping).
- Final verdict = simple majority across 5 votes.
- Majority threshold: **≥3 of 5** for ALPHA or BETA.
- If no option reaches 3 (e.g., split with ties), output `TIE`.

### JSON requirements for B1

- `condition = "B1"`
- `config.baseline_type = "scorer-only"`
- `config.num_rounds = 1`
- `config.num_judges = 1`
- `rounds = null`
- `baseline_outputs = [ ...5 entries... ]`
  - each entry includes:
    - `agent_index` (0-4)
    - `output_text`
    - `verdict`
    - `score`
    - `raw_output`

### Required deviation note

Document in prompt log or run notes:

- Wang et al. (2022) baseline references temperature ~0.7.
- OpenCode runtime has no explicit temperature control in this path; run uses default temperature.

---

## B3 — Single-Judge Ensemble (3 Independent Judges)

### Objective

Simulate a compact evaluator ensemble where three judge personas independently score the same scenario and each emits a verdict.

### Required dispatch

Spawn **3 independent judge agents** (parallel allowed) with scenario-only context:

- Judge Aesthete via `task(category="artistry", load_skills=["debate"], run_in_background=true, ...)`
- Judge Stylist via `task(category="writing", load_skills=["debate"], run_in_background=true, ...)`
- Judge Analyst via `task(category="ultrabrain", load_skills=["debate"], run_in_background=true, ...)`

Judges evaluate scenario/options directly; they **do not** review debate transcripts.

### Prompt templates (persona-specific)

Common core:

```text
You are an independent evaluator.
Given scenario: {situation}
Options: {options}

Evaluate from the assigned lens and choose one option.
Return:
1) 150-250 word reasoning
2) VERDICT: {ALPHA|BETA|TIE}
```

Lens suffixes:

- Aesthete: prioritize elegance, creativity, conceptual harmony.
- Stylist: prioritize clarity, communication quality, persuasiveness.
- Analyst: prioritize logical rigor, consistency, evidence fit.

### Aggregation

- Final verdict = majority across 3 judge verdicts.
- Majority threshold: **≥2 of 3** for ALPHA or BETA.
- If all split or tie-blocked, output `TIE`.

### JSON requirements for B3

- `condition = "B3"`
- `config.baseline_type = "scorer-only"`
- `config.num_rounds = 1`
- `config.num_judges = 1`
- `rounds = null`
- `baseline_outputs = [ ...3 entries... ]`
  - each entry includes:
    - `agent_index` (0-2)
    - `output_text`
    - `verdict`
    - `score`
    - `raw_output`

---

## B5 — DEBATE (Commander-Scorer-Critic, 3 Rounds)

### Objective

Implement Kim et al. (2024)-style Commander-Scorer-Critic loop with a strictly negative critic.

### Role mapping

- **Commander** → `task(subagent_type="oracle", load_skills=["debate"], run_in_background=false, ...)`
- **Critic** → `task(category="mephistopheles", load_skills=["debate"], run_in_background=false, ...)` (strictly negative tone)
- **Scorer** → `task(category="ultrabrain", load_skills=["debate"], run_in_background=false, ...)`

### Core loop (exact)

Run **3 rounds** of:

1. Commander proposes verdict + rationale
2. Critic attacks weaknesses only
3. Commander revises (or defends) after critique
4. Scorer returns round verdict

### Strict critic rule (non-negotiable)

Critic prompt must include and enforce:

```text
Only point out weaknesses. Do not point out strengths.
```

No steel-manning, no balancing praise, no “what works” section.

### Dispatch templates

#### Commander initial

```text
ROLE: Commander
Given scenario: {situation}
Options: {options}

Choose the better option and justify in 180-260 words.
End with: VERDICT: {ALPHA|BETA|TIE}
```

#### Critic attack

```text
ROLE: Critic
TONE: Strictly-negative
Only point out weaknesses. Do not point out strengths.

Target commander argument:
{commander_output}

Produce a focused critique (120-220 words) identifying flaws, blind spots, unsupported claims, and failure modes.
End with: CRITIQUE_SUMMARY: {one-sentence core failure}
```

#### Commander revision

```text
ROLE: Commander
You must respond to the critic's weaknesses.

Previous argument:
{commander_output}

Critique:
{critic_output}

Revise your position in 180-260 words.
End with: VERDICT: {ALPHA|BETA|TIE}
```

#### Scorer (1 per round)

```text
ROLE: Scorer
Given scenario: {situation}
Options: {options}

Commander revised output:
{commander_revised_output}

Score this round and choose verdict.
Return:
- ALPHA_SCORE: {1-5}
- BETA_SCORE: {1-5}
- VERDICT: {ALPHA|BETA|TIE}
- RATIONALE: {80-150 words}
```

### Aggregation

- Use scorer verdict each round to fill `rounds[].judge_scores` (one judge object).
- Final verdict = majority across the 3 round verdicts.
- Tie on rounds → `TIE`.

### JSON requirements for B5

- `condition = "B5"`
- `config.baseline_type = "commander-scorer-critic"`
- `config.num_judges = 1`
- `baseline_outputs = null`
- `rounds = [ ...3 entries... ]`
  - each round must include:
    - `round_number` (1..3)
    - `alpha_agent`, `beta_agent`
    - `option_mapping`
    - `positions.alpha.s1..s5`, `positions.beta.s1..s5` (empty string allowed where not used)
    - `judge_scores` with exactly one scorer record and `raw_output`

---

## Required Deviation Log (Method Fidelity)

Every B1/B3/B5 run must include explicit notes in run metadata or transcript for deviations from source papers:

1. **Temperature control limitation** (B1): default runtime temp used instead of explicitly setting 0.7.
2. **Platform role mapping** (B5): Commander/Scorer/Critic mapped to available OpenCode agent categories.
3. **Schema adaptation details**: any pragmatic field mapping needed to satisfy Task 4 JSON contract.

If additional deviations are introduced, they must be documented before run completion.

---

## Minimal Execution Checklist

- [ ] Correct invocation condition selected (`gad_20`, `gad_40`, `gad_60`, `gad_80`, `gad_90`, `gad_v2`, `b1_majority`, `b3_ensemble`, or `b5_debate`)
- [ ] JSON contract `condition` field emitted as one of (`GAD`, `GAD_V2`, `B1`, `B3`, `B5`)
- [ ] Dispatch count matches protocol (GAD=3 rounds + 3 judges/round, B1=5, B3=3, B5=3 rounds)
- [ ] Critic prompt in B5 is strictly negative
- [ ] Majority-rule aggregation applied with correct threshold
- [ ] Output object matches Task 4 run contract
- [ ] Deviations from paper logged explicitly
