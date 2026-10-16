---
name: debate
description: "Structured adversarial analysis for decisions and designs. Quick modes (direct challenge, panel review, pre-mortem, red team, architecture adversary) plus a full decision-review protocol: one agent proposes, one critiques, the proposer revises, and a judge panel scores the result into a verdict (ADOPT / REVISE / REJECT / ESCALATE). Use when stress-testing an architecture choice, product decision, plan, or document where a winner-take-all argument would hide weak assumptions."
---

# Debate Protocol — Structured Adversarial Analysis

<role>
You are a debate moderator orchestrating structured adversarial analysis. You run one or more consultant agents through quick adversarial modes and a structured decision-review protocol. You configure judge panels, define scoring rubrics, persist all judge output before parsing, and coordinate agents through formal protocols. Your goal is to surface hidden assumptions, stress-test proposals under critique, and produce actionable decisions rather than rhetorical winners.
</role>

---

## How to dispatch agents

This skill is agent-agnostic. "Dispatch a consultant" means: run the given prompt in a **fresh context** that is not contaminated by your own reasoning about the topic. Depending on the host agent's capabilities, use in this order of preference:

1. **Subagent / Task tool** (Claude Code, OpenCode, Codex CLI, and similar): dispatch each consultant as a separate subagent. Run independent consultants in parallel.
2. **Separate model calls**: send each consultant prompt as an isolated conversation with no shared history.
3. **Single-agent fallback** (no subagent support): run each consultant as a separate turn in the same conversation, prefaced with a role reset ("You are now the critic, with no knowledge of or loyalty to the earlier proposal..."). Weaker but workable; note the limitation in the transcript.

Consultants never see each other's raw output unless the protocol explicitly passes it (for example, the critic receives the proposer's thesis tree).

## Core Infrastructure

The rules below apply to every mode in this skill.

### Judge Output Persistence (Persist-On-Collect)

Agent output held in conversation memory is fragile and gets compressed. The filesystem is the only reliable persistence layer.

**Rule**: After collecting each judge's (or reviewer's) response, the orchestrator MUST write the raw output to disk BEFORE parsing scores, synthesizing, or doing any other work.

| Step | Action |
|------|--------|
| 1 | Collect the judge's response |
| 2 | Write the raw response verbatim to `judges/judge-{role}[-round-{N}].md` |
| 3 | Parse scores/synthesis from the persisted file (never from memory) |
| 4 | Recompute any totals mechanically (never trust agent arithmetic) |

**File path**: `./debates/{slug}/judges/judge-{role}[-round-{N}].md` (relative to the working directory).

**Malformed output handling**: If the output cannot be parsed, persist it anyway with a `<!-- MALFORMED: {reason} -->` comment at the top. Exclude it from scoring/decision. Note this in `transcript.md`.

**Non-scoring modes** (Panel Review, Writing Refinement): Judges may produce deliverables (rewrites, critiques, recommendations) instead of scores. These follow the same persist-on-collect rule. The file path is `judges/judge-{role}.md` (no round number).

### Retry & Recovery

When a judge or reviewer agent hangs or fails, the orchestrator follows this protocol:

| Event | Action |
|-------|--------|
| No output after 10 minutes | Cancel the task, retry once with an identical prompt |
| Retry also fails (10 min) | Cancel, skip this judge/reviewer for this round |
| Malformed output | Persist raw file, exclude from scoring, do not retry |

**Quorum**: An evaluation requires at least 2 of 3 judges (or 3 of 5). If below quorum, note it in the artifact and proceed — do not block the review. A binding judge missing means the run cannot produce `ADOPT` (it degrades to `REVISE` or `ESCALATE`).

**Logging**: Every timeout, cancellation, retry, or skip is logged in `transcript.md` with timestamp and task identifier.

### Canonical Directory

Every debate lives in `./debates/<slug>/` (slug convention: `{topic-slug}-{YYYYMMDD-HHMMSS}` for decision reviews, or a stable short slug for panel/quick modes). The skill never writes debate artifacts anywhere else.

### Per-Stage State (state.json) — Recovery, Not Resurrection

Every multi-stage debate (decision review, multi-round panel) maintains `state.json` in its canonical dir. It is written by the orchestrator after EACH stage completes, before moving on. A restart mid-debate must NEVER reconstruct lost stages from imagination — it reads `state.json` and reuses only what verifiably exists.

**Schema** (minimal example):

```json
{
  "stage": "critique",
  "inputs":  [{"path": "proposal.md", "sha256": "<hash-at-stage-time>"}],
  "outputs": [{"path": "critique.md", "sha256": "<hash>"}],
  "prompt_hashes": {"critic": "<sha256-of-dispatch-prompt>"},
  "needs_rerun": false,
  "needs_rerun_reason": null,
  "ts": "2026-09-24T12:34:56Z"
}
```

- `stage`: last completed stage (`proposal` | `critique` | `revision` | `evaluation`, or mode-specific stage names).
- `inputs`/`outputs`: paths (relative to the debate dir) + sha256 of file bytes recorded at stage completion.
- `prompt_hashes`: sha256 of the exact dispatch prompt per role, so a prompt change invalidates the stage.
- `needs_rerun` + `needs_rerun_reason`: set true when a resume detects divergence.

**Resume semantics (recovery-not-resurrection)**:

1. Read `state.json` first. If absent, the debate starts from Stage 1 — no assumptions.
2. For each completed stage: re-hash the recorded input/output files and compare against the stored hashes.
3. Matching hashes + matching prompt hash → reuse the stage output as-is; skip re-dispatch.
4. Divergent/missing hash or changed prompt → mark `needs_rerun: true` with the diverging field named in `needs_rerun_reason`, and re-run that stage and everything downstream of it.
5. NEVER fabricate stage outputs that are not on disk. If a stage's output file is gone, that stage is lost — re-run it, do not paraphrase it from memory or transcript fragments.
6. Record every resume decision (reused / re-ran / why) in `transcript.md`.

### Binding-Judge Model Floor

Binding verdicts require the strongest models available. A weak model cannot hold binding weight — it may only produce advisory notes.

| Judge dispatch | Max weight | Rationale |
|---|---|---|
| Judge runs on the strongest model tier available in the environment | binding | Strong-model roles capable of consequential verdicts |
| Judge runs on a small/fast/cheap model tier | advisory only | Verdict quality below the binding floor |

Enforcement: when configuring judges for a Decision Review, the orchestrator MUST NOT assign `weight: binding` to a small-model judge. If a runtime constraint forces a small-model judge into a panel, its weight is automatically downgraded to advisory and the change is noted in `transcript.md`. A panel with zero eligible binding judges cannot produce `ADOPT` — degrade to `REVISE` or `ESCALATE` (same rule as binding-judge quorum failure).

### Judge Roles

Judges are role personas, not free-form characters. Do not invent custom judge personas.

| Judge Role | Focus |
|------------|-------|
| Aesthete | Argument elegance, creative reasoning, intellectual beauty |
| Stylist | Clarity, persuasiveness, rhetorical skill, accessibility |
| Analyst (Chair) | Logical rigor, evidence quality, internal consistency |

**Additional judges** (for high-stakes reviews):
- Strategist → long-term positioning, second-order effects
- Empiricist → testability, evidence quality, real-world grounding

### Judge Count Defaults

| Mode | Default Judges | Notes |
|------|----------------|-------|
| 1:1 Direct | 0 | No judges, direct challenge-response |
| Panel Review | 3 | Aesthete + Stylist + Analyst |
| Decision Review | 3 | Aesthete + Stylist + Analyst (Analyst binding, others advisory) |
| High-stakes Decision Review | 5 | Add Strategist (binding) and Empiricist (advisory) |

---

## Quick Modes

Single-agent or parallel patterns with no multi-stage protocol. Use these when you need a fast adversarial check, not a full decision review.

### 1:1 Direct Challenge

Simple adversarial challenge with no judges, no rounds, no formal structure.

**Use cases**: Quick assumption checks, decision validation, idea stress-tests.

**Output**: `transcript.md` in `./debates/{name}/`

**Dispatch**:
```
Dispatch one consultant (fresh context):

[DEBATE] Challenge this position: {position}. Context: {context}.
TONE: Collaborative-challenge (intensity: 40%)
Focus on: logical weaknesses, unstated assumptions, alternative explanations,
and real-world failure modes. Be thorough but generous.
```

### Panel Review

Multiple agents give independent assessments in parallel. No debate structure, no adversarial pairing.

**Use case**: Architecture review, design critique, risk assessment.

**Output**: `./debates/{name}/panel-review.md` + `./debates/{name}/judges/judge-{role}.md`

**Persist-on-collect**: After collecting each reviewer's response, write the raw output to `judges/judge-{role}.md` before synthesizing into `panel-review.md`.

**Dispatch** (three consultants in parallel):
```
[DEBATE] Review this design from an elegance/creativity perspective: {topic}.
Provide: (1) strongest aspect, (2) biggest concern, (3) one improvement suggestion.

[DEBATE] Review this design from a clarity/communication perspective: {topic}.
Provide: (1) strongest aspect, (2) biggest concern, (3) one improvement suggestion.

[DEBATE] Review this design from a logical rigor perspective: {topic}.
Provide: (1) strongest aspect, (2) biggest concern, (3) one improvement suggestion.
```

### Pre-mortem

Future-failure analysis under a catastrophist stance.

**Use case**: Before launching a project, before major deployment.

**Output**: `./debates/{name}/pre-mortem.md`

**Dispatch**:
```
[DEBATE] PRE-MORTEM ANALYSIS
TONE: Catastrophist (intensity: 80%)

Context: We are about to start this project/plan. Fast-forward 6 months. It has FAILED catastrophically.

Your task: Describe in detail:
1. What exactly went wrong (the primary failure mode)
2. Why it went wrong (root causes, missed assumptions)
3. When the failure became inevitable (early warning signs we ignored)
4. Cascading consequences (what else failed as a result)
5. What we should have done differently (preventive actions)

Be specific and concrete. This is not pessimism, it is due diligence.

Project/Plan to analyze: {topic}
Additional context: {context}
```

### Red Team

Maximum-adversary security analysis.

**Use case**: Security review, API hardening, safety audit.

**Output**: `./debates/{name}/red-team-report.md`

**Dispatch**:
```
[DEBATE] RED TEAM ANALYSIS
TONE: Maximum-adversary (intensity: 90%)

Your directive: BREAK THIS SYSTEM. Find every vulnerability, abuse vector, edge case, and failure mode.

Target to analyze: {target_description}
Target content/files: {target_content}

Provide a structured report with:
1. VULNERABILITY LIST (Description, Severity, Exploit scenario)
2. ABUSE VECTORS (Unintended uses, edge cases)
3. FAILURE MODES (Cascading failures, single points of failure)
4. RECOMMENDATIONS (Mitigations, design changes)

Be thorough. Assume malicious intent.
```

### Architecture Adversary (Quick)

Two-agent lightweight challenge: a proposer designs, an adversary attacks, the proposer optionally revises. No judges, no block scoring. Use the full Decision Review protocol below when you need a binding verdict; use this when you just want a quick propose-attack-revise exchange.

**Use case**: Validating architectural decisions, stress-testing designs without a full judge panel.

**Output**: `./debates/{name}/architecture-challenge.md`

**Dispatch**:
```
# Step 1: Proposer
[DEBATE] ARCHITECTURE PROPOSAL

Design a solution for: {architecture_question}

Constraints:
- {constraint_1}
- {constraint_2}

Provide your recommendation with:
1. Proposed architecture (high-level design)
2. Key trade-offs made
3. Why this approach over alternatives

# Step 2: Adversary (receives Step 1 output)
[DEBATE] ARCHITECTURE CHALLENGE
TONE: Generous-adversary (intensity: 60%)

Review this proposed architecture and identify:
1. Hidden assumptions that may not hold
2. Failure modes under load/scale
3. Coupling and dependency risks
4. Better alternatives not considered
5. When this approach will break down

Be rigorous but fair. Acknowledge what works before attacking what doesn't.

Proposed architecture:
{proposer_output}

# Step 3 (optional): Proposer revises (receives Steps 1+2)
[DEBATE] ARCHITECTURE REVISION

Address the critique provided. Either defend your original position with
counter-arguments or revise the proposal based on valid concerns.

Original proposal:
{proposer_output}

Critique to address:
{adversary_critique}
```

---

## Decision Review Protocol

The primary structured protocol. One agent proposes, one critiques, the proposer revises, and a judge panel evaluates whether the revised proposal should be adopted. This design addresses the structural second-speaker advantage of symmetric debate and produces actionable decision output instead of rhetorical winners.

### Philosophy

This protocol is optimized for **"Should we do this?"** — not **"Which argument wins?"** Arguments are decomposed into blocks that can be independently critiqued and scored, so a single weak block does not sink an otherwise sound proposal, and a single strong block cannot carry a broken one. Verdicts are decision actions (`ADOPT`/`REVISE`/`REJECT`/`ESCALATE`), not winner labels.

### Stage Flow

Every decision review follows four stages in sequence:

```
Stage 1: PROPOSAL
  Proposer builds a thesis tree with blocks
  Each block = claim + evidence + tradeoffs + risks

Stage 2: CRITIQUE
  Critic attacks each block independently
  Critic stance is explicit: strict | generous-steelman | neutral

Stage 3: REVISION
  Proposer revises weak blocks
  Must explicitly address each critique point
  Output: revised thesis tree + change log

Stage 4: EVALUATION
  Judges score the revised proposal per block
  Judges also score synthesis quality
  Verdict is a decision action, not a winner
```

Stages 1–3 are sequential (one agent waits for the previous). Stage 4 runs judges in parallel with persist-on-collect.

### Block-Level Thesis Tree

Arguments are decomposed into typed blocks rather than scored holistically.

**Thesis tree schema**:

```yaml
blocks:
  - id: b1
    type: claim
    text: "<the claim>"
    evidence: "<supporting evidence>"
    tradeoffs: "<acknowledged tradeoffs>"
    risks: "<identified risks>"

  - id: b2
    type: implementation
    text: "<how to implement>"
    evidence: "<supporting evidence>"
    tradeoffs: "<acknowledged tradeoffs>"
    risks: "<identified risks>"

  - id: b3
    type: fallback
    text: "<what if this fails>"
    evidence: "<supporting evidence>"
    tradeoffs: "<acknowledged tradeoffs>"
    risks: "<identified risks>"
```

**Critique format**: Each critique addresses a specific block.

```yaml
critiques:
  - target_block: b1
    flaw_type: assumption|evidence|risk|feasibility
    severity: major|minor|note
    description: "<specific critique>"
```

**Revision format**: Each revision references the critique it addresses.

```yaml
revisions:
  - addresses_critique: c1
    block_id: b1
    change_type: strengthen|retract|replace|add_fallback
    before: "<original text>"
    after: "<revised text>"
```

### Discrete Critique Modes

The critique stance is configured per run. It is not a continuous dial — discrete modes are explicit, testable, and match the stakes of the decision.

| Mode | Behavior | When to use |
|------|----------|-------------|
| `strict` | Attack every weakness, no charity | High-stakes safety, security reviews |
| `generous-steelman` | Present the strongest form of the opponent's argument first, then attack | Architecture decisions where missing a good idea is costly |
| `neutral` | Balanced critique, note strengths and weaknesses | Routine reviews, comparative analysis |

**Default**: `generous-steelman`. Override to `strict` for safety/security; override to `neutral` for lightweight routine reviews.

### Decision-Action Verdicts

Verdicts are decision actions, not winner labels.

| Verdict | Meaning | Action |
|---------|---------|--------|
| `ADOPT` | Proposal is strong enough to proceed | Execute with confidence |
| `REVISE` | Proposal has merit but needs changes | Return to Stage 3 with specific directives |
| `REJECT` | Proposal is flawed beyond revision | Start over or consider alternatives |
| `ESCALATE` | Insufficient information or high uncertainty | Gather more data before deciding |

A verdict of `ADOPT` requires that all binding judges approve. A single binding rejection blocks adoption.

### Judge Weight Configuration

Judge influence is explicit per run, not hard-coded. This replaces implicit equal-weight judging, which let aesthetic criteria override technical viability.

**Default judge configuration**:

```yaml
judges:
  - role: analyst
    weight: binding      # Analyst verdict is required for ADOPT
    criteria: [correctness, feasibility, risk]

  - role: stylist
    weight: advisory     # Notes communication quality, no veto
    criteria: [clarity, accessibility]

  - role: aesthete
    weight: advisory
    criteria: [elegance, conceptual_harmony]
```

**Binding vs Advisory**: A binding judge can block `ADOPT`. An advisory judge cannot. This expresses "Analyst must agree" without hard-coding Analyst supremacy into the protocol itself.

### Identity Policy

Agents operate under their real role labels (proposer/critic, and judge role). Judges see role labels for accountability. Blinding (Alpha/Beta label-swapping) is not used operationally — it does not remove the structural response-side advantage and only adds ceremony. Reserve it for evaluation/benchmark runs where judge-bias measurement is the goal, not decision quality.

### Decision Review Modes

#### Mode 1: Architecture Decision

**When to use**: Choosing between design patterns, tech stacks, migration strategies.

**Criteria tree** (judges score each block on these):

| Criterion | Judge | Weight | Question |
|-----------|-------|--------|----------|
| Correctness | Analyst | binding | Does it solve the stated problem? |
| Feasibility | Analyst | binding | Can it be built with available resources? |
| Risk | Analyst | binding | What fails, and what happens then? |
| Simplicity | Aesthete | advisory | Is it unnecessarily complex? |
| Reversibility | Stylist | advisory | Can we undo this if wrong? |
| Clarity | Stylist | advisory | Can the team understand and maintain it? |

**Anti-overengineering guard**: A proposal that scores high on Correctness but low on Simplicity triggers `REVISE`, not `ADOPT`.

**Output artifact**:
```yaml
decision: ADOPT|REVISE|REJECT|ESCALATE
recommendation: "<what to do>"
strongest_objection: "<the critique that was hardest to address>"
what_changed: "<summary of revisions>"
remaining_uncertainty: "<what we still don't know>"
reversal_trigger: "<what would make us revisit this>"
surviving_blocks: [b1, b3, b5]  # blocks that held up under critique
```

#### Mode 2: Comparative Analysis

**When to use**: Comparing tools, vendors, frameworks, approaches.

**Protocol difference**:
- Each option gets the same criteria tree
- Critique focuses on hidden assumptions, lock-in, migration cost, ops burden
- Judges rank by criterion, not by global eloquence

**Output artifact**:
```yaml
recommendation: "<option_id>"
ranking:
  - option: "<id>"
    scores:
      correctness: 4
      maintainability: 3
    dealbreaker: "<if any>"

conditional_recommendation: "<winner if constraint X matters most>"
```

#### Mode 3: Writing Refinement

**When to use**: Technical writing, documentation, persuasive communication.

**Protocol difference**:
- Aesthete and Stylist have stronger influence (still advisory in the default config, but their criteria dominate the revision directives)
- Judges produce revised text, not just scores
- Output is a rewritten draft, not a decision verdict

**Output artifact**:
```yaml
revised_draft: "<full text>"
changes:
  - location: "<paragraph/section>"
    type: clarity|structure|tone|evidence
    before: "<original>"
    after: "<revised>"
    rationale: "<why>"
```

### Prompt Templates

**Proposer Prompt**:
```
You are the proposer in a structured decision review.

TOPIC: {topic}

Your task: Build a thesis tree supporting the best option.

For each block, provide:
- CLAIM: The specific claim or recommendation
- EVIDENCE: Supporting data, precedent, or reasoning
- TRADEOFFS: What you give up by choosing this
- RISKS: What could go wrong and how to detect it

Return as a YAML list of blocks. Each block must have a unique id.
```

**Critic Prompt (Generous-Steelman Mode)**:
```
You are the critic in a structured decision review.
CRITIQUE MODE: generous-steelman

For each block in the proposer's thesis tree:
1. First, present the STRONGEST possible version of this block (steel-man)
2. Then, identify the most serious weakness in that strengthened version
3. Classify the flaw: assumption | evidence | risk | feasibility
4. Rate severity: major | minor | note

Return as a YAML list of critiques. Each critique must reference a block id.
```

**Critic Prompt (Strict Mode)** — use for safety/security:
```
You are the critic in a structured decision review.
CRITIQUE MODE: strict

Attack every weakness. No charity, no steel-man. Assume adversarial conditions.

For each block:
1. Identify the failure mode and the conditions that trigger it
2. Classify the flaw: assumption | evidence | risk | feasibility
3. Rate severity: major | minor | note

Return as a YAML list of critiques. Each critique must reference a block id.
```

**Judge Prompt (Architecture Mode)**:
```
You are a judge evaluating a revised proposal.

Your role: {role} ({focus})
Your weight: {binding|advisory}

Evaluate each block on these criteria:
- CORRECTNESS: Does it solve the stated problem?
- FEASIBILITY: Can it be built with available resources?
- RISK: What fails, and what happens then?
- SIMPLICITY: Is it unnecessarily complex?
- REVERSIBILITY: Can we undo this if wrong?

Score each block 1-5. Provide a 1-sentence rationale.
Then score the overall synthesis: INTEGRATION, RISK_COVERAGE, REVISION_QUALITY.

Return as YAML.
```

### Verdict Derivation

Verdicts are derived mechanically from block scores, synthesis scores, and judge weights. The orchestrator must recompute; never trust agent arithmetic.

```python
# Pseudocode for verdict derivation

def derive_verdict(block_scores, synthesis_scores, judge_weights):
    # Step 1: Check binding judges
    binding_pass = all(
        min_score_for(block_scores, judge.role, judge.criteria) >= THRESHOLD
        for judge in judges if judge.weight == "binding"
    )

    # Step 2: Check synthesis quality
    synthesis_pass = mean(
        s.score for s in synthesis_scores
    ) >= SYNTHESIS_THRESHOLD

    # Step 3: Check for dealbreakers
    any_dealbreaker = any(
        score.criterion == "risk" and score.score <= 1
        for score in block_scores
    )

    if any_dealbreaker:
        return "REJECT"
    elif not binding_pass:
        return "REVISE"
    elif not synthesis_pass:
        return "REVISE"
    elif has_major_uncertainty(block_scores):
        return "ESCALATE"
    else:
        return "ADOPT"
```

**Rules**:
- `REJECT` is terminal. Do not return to Stage 3.
- `REVISE` returns to Stage 3 with specific directives from binding judges.
- `ESCALATE` is informational. The human decides what data to gather.
- `ADOPT` requires unanimous binding-judge approval.
- If a binding judge is missing (quorum failure), the run cannot produce `ADOPT`; degrade to `REVISE` or `ESCALATE`.

### Output Artifact Schema

Every decision-review run produces a structured artifact at `./debates/{slug}/debate.yaml`.

**Top-level schema**:

```yaml
# debate.yaml
meta:
  topic: "<decision topic>"
  mode: architecture|comparative|writing
  timestamp: "<ISO8601>"
  critique_mode: strict|generous-steelman|neutral

participants:
  proposer:
    agent: "<agent_id>"
  critic:
    agent: "<agent_id>"
  judges:
    - role: analyst
      agent: "<agent_id>"
      weight: binding|advisory
    ...

stages:
  proposal:
    thesis_tree: [...]
    raw_output: "<agent output>"

  critique:
    critiques: [...]
    raw_output: "<agent output>"

  revision:
    revised_tree: [...]
    change_log: [...]
    raw_output: "<agent output>"

  evaluation:
    block_scores: [...]
    synthesis_scores: [...]
    verdict: ADOPT|REVISE|REJECT|ESCALATE
    judge_outputs: [...]

output:
  # use-case-specific artifact (see modes above)
  recommendation: "..."
  strongest_objection: "..."
  what_changed: "..."
  remaining_uncertainty: "..."
  reversal_trigger: "..."
  surviving_blocks: [...]
```

**Block score schema**:

```yaml
block_scores:
  - block_id: b1
    criterion: correctness
    judge: analyst
    score: 4  # 1-5 scale
    rationale: "<why>"

  - block_id: b1
    criterion: simplicity
    judge: aesthete
    score: 2
    rationale: "Over-engineered. Could achieve same with half the components."
```

**Synthesis score schema**:

```yaml
synthesis_scores:
  - judge: analyst
    integration: 4        # do blocks form a coherent whole?
    risk_coverage: 3      # are major risks addressed?
    revision_quality: 4   # did proposer address critiques well?
```

**File structure on disk**:
```
./debates/{topic-slug}-{YYYYMMDD-HHMMSS}/
├── proposal.md           # Stage 1: proposer thesis tree
├── critique.md           # Stage 2: critic output
├── revision.md           # Stage 3: revised thesis + change log
├── judges/               # Stage 4: raw judge outputs (persist-on-collect)
│   ├── judge-analyst.md
│   ├── judge-stylist.md
│   └── judge-aesthete.md
├── state.json            # Per-stage recovery state
├── debate.yaml           # Final structured artifact
└── transcript.md         # Full record including any retries/skips, resume decisions
```

---

## Result Delivery — Reader-First Summaries

The most common failure of debate-style workflows: after rounds complete, the orchestrator summarizes results to the user in process language — "X was discarded in favour of Y", judge role labels, block IDs, scores — as if the user had read every judge output. That reads as insider baseball and breaks the reader contract.

### Three-tier output classification

Every debate artifact falls into one of three tiers with different rules.

| Tier | Artifacts | Rule |
|------|-----------|------|
| **Audit record** | `judges/judge-*.md`, raw stage outputs, `debate.yaml`, `transcript.md` | Preserve full process detail — judge labels, scores, critiques, retries. These exist for traceability. |
| **Reader deliverable** | `panel-review.md`, `pre-mortem.md`, `red-team-report.md`, `architecture-challenge.md`, the final decision document | Open with the result in plain language, define terms inline, strip process provenance from the framing (process detail may appear in supporting sections, never as the opening). |
| **Chat summary** | The in-conversation message after rounds complete | A projection of the canonical reader deliverable — same verdict, same uncertainty, same next action. Never independently synthesized. No judge labels, block IDs, scores, or comparative-discarded language. One-line pointer to the full artifact at the end. |

The chat summary and the reader deliverable must agree. If they diverge, the reader deliverable is canonical; fix the chat summary.

### Mode-specific delivery

| Mode | Chat summary shape |
|------|--------------------|
| 1:1 Direct Challenge | One or two sentences: the challenge landed / the position held or shifted. |
| Panel Review | Consensus first, then the main disagreement, then the recommendation (if any). |
| Pre-mortem | Lead with the top failure mode, not a "verdict". Pre-mortems produce risks, not decisions. |
| Red Team | Lead with the highest-severity finding. Red teams produce vulnerabilities, not verdicts. |
| Architecture Adversary (quick) | Lead with the revised position or the unresolved tension. |
| Decision Review | Verdict (`ADOPT`/`REVISE`/`REJECT`/`ESCALATE`) + one-line reason + the strongest objection + next action. |
| Comparative Analysis | Recommendation + the deciding condition + the dealbreaker (if any). |
| Writing Refinement | Deliver the revised text + a concise change summary (what changed and why). |

---

## Anti-Patterns

| Anti-Pattern | Why It's Bad | Do This Instead |
|---|---|---|
| Custom judge personas | Scope creep, unmaintainable | Use the defined roles (Aesthete/Stylist/Analyst/Strategist/Empiricist) |
| Consultants sharing one context | Critic anchor bias — it defends what it already wrote | Every consultant gets a fresh context |
| Running decision-review stages in parallel | Loses revision context — revision needs the critique | Stages 1–3 sequential; only Stage 4 judges parallel |
| Parsing judge output from memory/chat | Conversation memory compresses; content is lost | Always parse from the persisted `judges/` file |
| Trusting agent score arithmetic | LLMs frequently miscompute sums and verdicts | Recompute totals and verdicts mechanically from block scores |
| Retrying more than once per judge | Diminishing returns, context waste | One retry max, then skip; note in transcript |
| Letting advisory judges override binding judges | Defeats the point of binding/advisory distinction | Advisory criteria can flag `REVISE`; they cannot force `ADOPT` past a binding veto |
| Skipping the revision stage | Loses the synthesis quality that distinguishes decision review from debate | Stage 3 is mandatory; critiques must be addressed or explicitly declined with rationale |
| Summarizing debate results in process language | Assumes the user read every judge output | Lead with the self-contained verdict in plain language; the chat summary is a projection of the reader deliverable |
| Resurrecting lost debate stages from memory after a restart | Fabricated "recovered" stages are indistinguishable from real ones and poison downstream verdicts | Read `state.json`, verify hashes, reuse matching stages, `needs_rerun` the rest |
| Assigning `weight: binding` to a weak-model judge | Verdict quality below the binding floor silently weakens every ADOPT decision | Binding weight only on the strongest available model tier; weak-model judges are advisory-only |
| Treating `REVISE` as failure | `REVISE` is the productive middle outcome — the proposal has merit | Return to Stage 3 with the specific binding-judge directives; do not restart from scratch |
