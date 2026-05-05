---
name: debate
description: "Structured adversarial debate protocol with configurable judge panels, scoring rubrics, and 6 distinct modes for rigorous technical analysis. Orchestrates multi-agent debates with formal rules, evidence tracking, and consensus building."
---

# Debate Protocol — Structured Adversarial Analysis

<role>
You are a debate moderator orchestrating structured adversarial analysis. You configure judge panels, define scoring rubrics, manage debate segments, enforce blinding rules, and coordinate multiple agents through formal debate protocols. Your goal is to surface hidden assumptions, test argument robustness, and build consensus through rigorous adversarial examination.
</role>

---

## Core Debate Protocol

### Segment Structure (S1-S5)

| Segment | Name | Words | Purpose |
|---------|------|-------|---------|
| S1 | Core Thesis | ~150 | State position clearly and compellingly |
| S2 | Evidence & Reasoning | ~200 | Support with evidence, data, analogies |
| S3 | Steel-Man & Counter | ~150 | Anti-conformity: CoT to identify flaws first, then steel-man, then counter. Only revise own position if factual error found — never because opponent "sounds convincing" |
| S4 | Implications | ~100 | What follows if your position is correct |
| S5 | Cross-Examination | ~150 | Optional rebuttal triggered by judge flag |

**S5 Trigger**: A judge may flag an unresolved critical point in their verdict. If flagged, both debaters receive a cross-examination prompt to address that specific point.

### Deterministic Label Blinding

Judges never see agent names. Positions are labeled Alpha and Beta only.

**Assignment Rule**: `if round_number % 2 == 1: Mephistopheles = Alpha, Advocate = Beta else: Mephistopheles = Beta, Advocate = Alpha`

The orchestrator tracks the mapping privately for verdict attribution. Judges receive only Alpha/Beta labels.

### Scoring System

Each judge scores each position 1-10 per segment (S1-S4).

| Element | Requirement |
|---------|-------------|
| Score range | 1-10 per segment per position |
| Decisive factor | 1-sentence justification per score |
| Per-round verdict | Judge declares winner: Alpha or Beta |
| Aggregate scoring | Total judge votes across all rounds |
| Tiebreaker | Chair judge (Analyst/ultrabrain) breaks ties |

### Judge Output Persistence (Persist-On-Collect)

Judge outputs are ephemeral — `background_output` is fire-once and compression destroys verbatim content. The filesystem is the only reliable persistence layer.

**Rule**: After collecting each judge's `background_output`, the orchestrator MUST write the raw output to disk BEFORE parsing scores or doing any other work.

| Step | Action |
|------|--------|
| 1 | Collect `background_output(task_id="...")` |
| 2 | Write raw output verbatim to `judges/judge-{role}-round-{N}.md` |
| 3 | Parse scores from the persisted file (never from memory) |
| 4 | Recompute TOTAL from S1-S4 scores (never trust agent arithmetic) |

**File path**: `.sisyphus/debates/{slug}/judges/judge-{role}-round-{N}.md`

**Malformed output handling**: If the output cannot be parsed (missing headers, unparseable scores), persist it anyway with a `<!-- MALFORMED: {reason} -->` comment at the top. Exclude from scoring. Note in `transcript.md`.

**Non-scoring modes** (Panel Review, deliverable-focused debates): Judges may produce deliverables (rewrites, critiques, recommendations) instead of scores. These follow the same persist-on-collect rule. The file path is `judges/judge-{role}.md` (no round number).

### Retry & Recovery

When a judge agent hangs or fails, the orchestrator follows this simple protocol:

| Event | Action |
|-------|--------|
| No output after 10 minutes | `background_cancel(taskId="...")`, retry once with identical prompt |
| Retry also fails (10 min) | Cancel, skip this judge for this round |
| Malformed output | Persist raw file, exclude from scoring, do not retry |

**Quorum**: A round requires at least 2 of 3 judges (or 3 of 5). If below quorum, note in transcript and proceed — do not block the debate.

**Reduced-panel tie-break**: If the Chair judge (Analyst) is missing and remaining judges split, the position with the highest aggregate segment score across those judges wins the round.

**Logging**: Every timeout, cancellation, retry, or skip is logged in `transcript.md` with timestamp and task_id.

### Judge Roles and Category Mapping

Judges map to existing OMO categories. Do not create custom judge personas.

| Judge Role | Category | Focus |
|------------|----------|-------|
| Aesthete | `artistry` | Argument elegance, creative reasoning, intellectual beauty |
| Stylist | `writing` | Clarity, persuasiveness, rhetorical skill, accessibility |
| Analyst (Chair) | `ultrabrain` | Logical rigor, evidence quality, internal consistency |

**Chair Judge**: The Analyst judge serves as chair and breaks ties. In 3-judge panels, the Analyst's vote prevails in tied rounds.

**Additional Judges** (for high-stakes debates):
- Strategist → `deep`
- Empiricist → `unspecified-high`

### Judge Count Defaults

| Mode | Default Judges | Notes |
|------|----------------|-------|
| 1:1 Direct | 0 | No judges, direct challenge-response |
| Standard | 3 | Aesthete + Stylist + Analyst |
| High-stakes | 5 | Add Strategist and Empiricist |

### Adversarial Intensity (Mode-Dependent)

Each mode specifies a default adversarial intensity for Mephistopheles prompts. Include `TONE: {label} (intensity: {N}%)` in every Mephistopheles dispatch.

| Mode | Intensity | Tone Label |
|------|-----------|------------|
| 1:1 Direct | 40% | Collaborative-challenge |
| Formal Debate | 60% | Generous-adversary |
| Pre-mortem | 80% | Catastrophist |
| Red Team | 90% | Maximum-adversary |
| Panel Review | N/A | Not adversarial |
| Architecture Adversary | 60% | Generous-adversary |

---

## Mode 1: 1:1 Direct Challenge

Simple adversarial challenge with no judges, no rounds, and no formal structure.

**Use cases**: Quick assumption checks, decision validation, idea stress-tests.

**Output**: `transcript.md` in `.sisyphus/debates/{name}/`

**Invocation**:
```
task(category="mephistopheles", load_skills=[],
  prompt="Challenge this position: {position}. Context: {context}.
  TONE: Collaborative-challenge (intensity: 40%)
  Focus on: logical weaknesses, unstated assumptions, alternative explanations,
  and real-world failure modes. Be thorough but generous.",
  run_in_background=false)
```

---

## Mode 2: Formal Debate

Full protocol with briefing, multiple rounds, judging, and verdict.

**Structure**: 
1. **Briefing Phase**: Generate briefing document
2. **Round Phase** (default 3 rounds): For each round:
   - Determine label assignment using blinding rule
   - Dispatch initiative side (S1-S4)
   - Dispatch response side (S1-S4)
   - Dispatch judges in parallel with blinded positions
   - Collect each judge's output → **persist to `judges/judge-{role}-round-{N}.md` immediately** → then parse scores
   - If any judge flags S5: dispatch S5 cross-examination to both debaters before next round
   - Write `round-{N}.md` with positions + parsed scores
3. **Verdict Phase**: Aggregate all judge votes
4. **Output Phase**: Write verdict.md, transcript.md

**Output File Structure**:
```
.sisyphus/debates/{topic-slug}-{YYYYMMDD-HHMMSS}/
├── briefing.md          # Shared research document
├── round-1.md           # Round 1: Alpha/Beta positions + judge scores
├── round-2.md           # Round 2: positions + scores
├── round-3.md           # Round 3: positions + scores
├── judges/              # Raw judge outputs (persist-on-collect)
│   ├── judge-aesthete-round-1.md
│   ├── judge-stylist-round-1.md
│   ├── judge-analyst-round-1.md
│   ├── judge-aesthete-round-2.md
│   └── ...              # One file per judge per round
├── verdict.md           # Final aggregate scores, winner, decisive factors
└── transcript.md        # Full unblinded record (agent names revealed)
```

**Use cases**: High-stakes architectural decisions, technology adoption debates.

---

## Mode 3: Panel Review

Multiple agents give independent assessments in parallel. No debate structure.

**Use case**: Architecture review, design critique, risk assessment.

**Output**: `.sisyphus/debates/{name}/panel-review.md` + `.sisyphus/debates/{name}/judges/judge-{role}.md`

**Persist-on-collect**: After collecting each reviewer's `background_output`, write the raw output to `judges/judge-{role}.md` before synthesizing into `panel-review.md`.

**Invocation**:
```
task(category="artistry", prompt="Review this design from an elegance/creativity perspective: {topic}. Provide: (1) strongest aspect, (2) biggest concern, (3) one improvement suggestion.", run_in_background=true)
task(category="writing", prompt="Review this design from a clarity/communication perspective: {topic}. Provide: (1) strongest aspect, (2) biggest concern, (3) one improvement suggestion.", run_in_background=true)
task(category="ultrabrain", prompt="Review this design from a logical rigor perspective: {topic}. Provide: (1) strongest aspect, (2) biggest concern, (3) one improvement suggestion.", run_in_background=true)
```

---

## Mode 4: Pre-mortem

Mephistopheles-only future-failure analysis.

**Use case**: Before launching a project, before major deployment.

**Output**: `.sisyphus/debates/{name}/pre-mortem.md`

**Invocation**:
```
task(category="mephistopheles", load_skills=[],
  prompt="PRE-MORTEM ANALYSIS
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
Additional context: {context}",
  run_in_background=false)
```

---

## Mode 5: Red Team

Mephistopheles-only security analysis.

**Use case**: Security review, API hardening, safety audit.

**Output**: `.sisyphus/debates/{name}/red-team-report.md`

**Invocation**:
```
task(category="mephistopheles", load_skills=[],
  prompt="RED TEAM ANALYSIS
TONE: Maximum-adversary (intensity: 90%)

Your directive: BREAK THIS SYSTEM. Find every vulnerability, abuse vector, edge case, and failure mode.

Target to analyze: {target_description}
Target content/files: {target_content}

Provide a structured report with:
1. VULNERABILITY LIST (Description, Severity, Exploit scenario)
2. ABUSE VECTORS (Unintended uses, edge cases)
3. FAILURE MODES (Cascading failures, single points of failure)
4. RECOMMENDATIONS (Mitigations, design changes)

Be thorough. Assume malicious intent.",
  run_in_background=false)
```

---

## Mode 6: Architecture Adversary

Two-agent mode: Oracle proposes, Mephistopheles attacks.

**Use case**: Validating architectural decisions, stress-testing designs.

**Output**: `.sisyphus/debates/{name}/architecture-challenge.md`

**Invocation**:
```
# Step 1: Oracle proposes
task(subagent_type="oracle", load_skills=[],
  prompt="ARCHITECTURE PROPOSAL

Design a solution for: {architecture_question}

Constraints:
- {constraint_1}
- {constraint_2}

Provide your recommendation with:
1. Proposed architecture (high-level design)
2. Key trade-offs made
3. Why this approach over alternatives",
  run_in_background=false)

# Step 2: Mephistopheles attacks
task(category="mephistopheles", load_skills=[],
  prompt="ARCHITECTURE CHALLENGE
TONE: Generous-adversary (intensity: 60%)

Review this proposed architecture and identify:
1. Hidden assumptions that may not hold
2. Failure modes under load/scale
3. Coupling and dependency risks
4. Better alternatives not considered
5. When this approach will break down

Be rigorous but fair. Acknowledge what works before attacking what doesn't.

Proposed architecture:
{oracle_proposal}",
  run_in_background=false)

# Step 3 (optional): Oracle revises
task(subagent_type="oracle", load_skills=[],
  prompt="ARCHITECTURE REVISION

Address the critique provided. Either defend your original position with counter-arguments or revise the proposal based on valid concerns.

Original proposal:
{oracle_proposal}

Critique to address:
{mephistopheles_critique}",
  run_in_background=false)
```

---

## Dispatch Templates

### Template Patterns

**Debater Template (Initiative)**:
```typescript
task(
  category="mephistopheles",  // or subagent_type="oracle" for Advocate
  load_skills=[],
  prompt=`DEBATE: Round {N}, Position: {Alpha|Beta}, Initiative: YES
TONE: Generous-adversary (intensity: 60%)
RESOLUTION: {debate_topic}
YOUR POSITION: {position_statement}
OPPONENT: Position will respond

STRUCTURE (follow exactly):
S1 Core Thesis (~150 words): State position clearly
S2 Evidence (~200 words): Support with evidence, data, examples
S3 Steel-Man & Counter (~150 words): Use Chain-of-Thought: (1) identify specific flaws in opponent's reasoning, (2) then present strongest version of their argument, (3) then counter. Only revise your own position if a factual error is found — not because opponent sounds convincing
S4 Implications (~100 words): What follows if correct

OUTPUT FORMAT:
S1: [thesis]
S2: [evidence]
S3: [steel-man opponent, then counter]
S4: [implications]`,
  run_in_background=false
)
```

**Debater Template (Response)**:
```typescript
task(
  category="mephistopheles",  // or subagent_type="oracle" for Advocate
  load_skills=[],
  prompt=`DEBATE: Round {N}, Position: {Alpha|Beta}, Initiative: NO
TONE: Generous-adversary (intensity: 60%)
RESOLUTION: {debate_topic}
YOUR POSITION: {position_statement}
OPPONENT'S ARGUMENT: {opponent_s1_s2_s3_s4}

STRUCTURE (follow exactly):
S1 Core Thesis (~150 words): Restate position, acknowledge clash
S2 Evidence (~200 words): Present counter-evidence, point out flaws
S3 Steel-Man & Counter (~150 words): Use Chain-of-Thought: (1) identify specific flaws in opponent's argument, (2) then strengthen their best point, (3) show why yours wins. Only revise your position if a factual error is found — not because opponent sounds convincing
S4 Implications (~100 words): Reiterate what hangs on decision

OUTPUT FORMAT:
S1: [thesis]
S2: [evidence and counter-evidence]
S3: [steel-man opponent, then counter]
S4: [implications]`,
  run_in_background=false
)
```

**Judge Template (Blinded)**:
```typescript
task(
  category="{judge_category}",  // artistry, writing, ultrabrain, deep, unspecified-high
  load_skills=[],
  prompt=`JUDGE: Round {N}
RESOLUTION: {debate_topic}

POSITION ALPHA: S1: {alpha_s1} S2: {alpha_s2} S3: {alpha_s3} S4: {alpha_s4}
POSITION BETA: S1: {beta_s1} S2: {beta_s2} S3: {beta_s3} S4: {beta_s4}

YOUR JOB: Score each segment 1-10 for both positions. Provide 1-sentence justification.

SCORING RUBRIC:
- 1-3: Poor (unsubstantiated, unclear, or fallacious)
- 4-6: Adequate (meets minimum, but not compelling)
- 7-8: Good (well-reasoned, clear, supported)
- 9-10: Excellent (exceptional clarity, evidence, persuasion)

OUTPUT FORMAT (follow this structure exactly — orchestrator parses by ### headers):

### ALPHA
- S1: {1-10} — {justification}
- S2: {1-10} — {justification}
- S3: {1-10} — {justification}
- S4: {1-10} — {justification}
- **TOTAL: {sum}**

### BETA
- S1: {1-10} — {justification}
- S2: {1-10} — {justification}
- S3: {1-10} — {justification}
- S4: {1-10} — {justification}
- **TOTAL: {sum}**

### VERDICT
- **Winner**: {Alpha|Beta}
- **Rationale**: {1-2 sentences}
- **Flag S5**: {YES|NO}
- **S5 Prompt**: {If YES, the specific unresolved point to examine}

### DELIVERABLE
{Optional — only when the debate involves non-scoring deliverables like rewrites or recommendations. Place the full deliverable content here.}`,
  run_in_background=true
)
```

**S5 Cross-Examination Template**:
```typescript
task(
  category="mephistopheles",  // or subagent_type="oracle" for Advocate
  load_skills=[],
  prompt=`DEBATE: Round {N} - S5 CROSS-EXAMINATION
TONE: Generous-adversary (intensity: 60%)
RESOLUTION: {debate_topic}
YOUR POSITION: {Alpha|Beta}
JUDGE'S FLAG: {s5_flag_text}

YOUR JOB: Address the specific concern raised in ~150 words.
1. Acknowledge the specific concern
2. Provide additional evidence, clarification, or rebuttal
3. Show why this point does (or does not) undermine your position

OUTPUT FORMAT:
S5_RESPONSE: [your cross-examination response, ~150 words]`,
  run_in_background=false
)
```

### Verdict Aggregation

**Tally Process**:
1. For each round: Collect judge verdicts (Alpha|Beta), count votes, tie broken by Chair judge
2. Final aggregation: Tally round winners across all rounds, majority wins
3. If tied on rounds: Sum all segment scores across all judges and rounds

**Unblinding**: After final verdict, reveal mapping: Alpha = {Mephistopheles|Advocate}, Beta = {Advocate|Mephistopheles}. Judges never learn which agent was which during scoring.

**Reporting Format**:
```
DEBATE RESULTS: {debate_topic}
Round 1: {Alpha|Beta} (Judge: {category}, Score: {total})
Round 2: {Alpha|Beta} (Judge: {category}, Score: {total})
Round 3: {Alpha|Beta} (Judge: {category}, Score: {total})
FINAL VERDICT: {Alpha|Beta} wins the debate
UNBLINDED: Alpha = {agent_name}, Beta = {agent_name}
KEY STRENGTHS (Winner): - {point 1} - {point 2}
KEY WEAKNESSES (Loser): - {point 1} - {point 2}
DISSENTING OPINIONS: {If any judge disagreed with majority}
```

### Absolute Rules for Dispatch

| Rule | Severity | Rationale |
|------|----------|-----------|
| Judges must never see agent names | CRITICAL | Blinding prevents bias |
| One judge = one background task | CRITICAL | Parallel execution required |
| Persist judge output to file before parsing | CRITICAL | `background_output` is fire-once; compression destroys raw content |
| Parse scores from persisted file, not memory | HIGH | Single source of truth prevents drift |
| Recompute TOTAL from S1-S4 scores mechanically | HIGH | Never trust agent arithmetic |
| Debaters use `run_in_background=false` | HIGH | Sequential within round |
| Judges use `run_in_background=true` | HIGH | Parallel across judges |
| Include full S1-S4 in judge prompts | HIGH | Complete context needed |
| Never batch multiple rounds | CRITICAL | One round at a time |

---

## Quick Start

**1:1 Direct Challenge**: Load skill, dispatch Mephistopheles directly
```
task(category="mephistopheles", prompt="Challenge this position: {position}. TONE: Collaborative-challenge (intensity: 40%). Focus on: logical weaknesses, unstated assumptions, alternative explanations, real-world failure modes.")
```
Output: `transcript.md`

**Formal Debate**: Load skill, configure rounds/judges/topic, orchestrate full protocol
```
/debate formal "Microservices are better than monolith for e-commerce" with judges=3 rounds=3
```
Output: `briefing.md`, `round-{N}.md`, `judges/judge-{role}-round-{N}.md`, `verdict.md`, `transcript.md`

**Panel Review**: Load skill, dispatch N reviewers in parallel, synthesize
```
task(category="artistry", prompt="Review: {topic}", run_in_background=true)
task(category="writing", prompt="Review: {topic}", run_in_background=true)
task(category="ultrabrain", prompt="Review: {topic}", run_in_background=true)
```
Output: `panel-review.md`, `judges/judge-{role}.md`

**Pre-mortem**: Load skill, dispatch Mephistopheles with pre-mortem prompt
```
task(category="mephistopheles", prompt="PRE-MORTEM: TONE: Catastrophist (intensity: 80%). This project will FAIL. Describe exactly how, why, and when. Project: {topic}")
```
Output: `pre-mortem.md`

**Red Team**: Load skill, dispatch Mephistopheles with red team prompt + target
```
task(category="mephistopheles", prompt="RED TEAM: TONE: Maximum-adversary (intensity: 90%). Break this system. Find vulnerabilities, abuse vectors, edge cases. Target: {target}")
```
Output: `red-team-report.md`

**Architecture Adversary**: Load skill, dispatch Oracle then Mephistopheles
```
task(subagent_type="oracle", prompt="Propose architecture for: {question}")
task(category="mephistopheles", prompt="Challenge this architecture: TONE: Generous-adversary (intensity: 60%). {oracle_proposal}")
```
Output: `architecture-challenge.md`

---

## Anti-Patterns

| Anti-Pattern | Why It's Bad | Do This Instead |
|---|---|---|
| Revealing agent names to judges | Breaks blinding, introduces bias | Use Alpha/Beta labels only |
| Random label shuffling | Non-reproducible, hard to verify | Deterministic: odd=Meph/Alpha |
| Custom judge personas | Scope creep, unmaintainable | Map to existing categories |
| Running all rounds in parallel | Loses debate progression context | Sequential rounds, parallel judges |
| Skipping S3 (Steel-Man) | Weakest arguments, no generosity | S3 is mandatory |
| Parsing scores from memory/chat | `background_output` is fire-once; compression destroys content | Always parse from persisted `judges/` file |
| Trusting agent TOTAL arithmetic | LLMs frequently miscompute sums | Recompute TOTAL mechanically from S1-S4 |
| Retrying more than once per judge | Diminishing returns, context waste | One retry max, then skip |
| Ad-hoc hang recovery | Burns context on improvised retry logic | Follow retry protocol: 10 min → cancel → retry once → skip |

---

## v2 Protocol — Structured Decision Review

The v2 protocol replaces symmetric winner-picking debate with an asymmetric decision-review process. One agent proposes, one critiques, the proposer revises, and judges evaluate whether the revised proposal should be adopted. This design addresses the structural second-speaker advantage of v1 and produces actionable decision output instead of rhetorical winners.

### Philosophy

**v1 optimized for**: "Which argument wins?"  
**v2 optimized for**: "Should we do this?"

The continuous tone parameter (20-90%) from v1 is dropped. In its place, v2 uses discrete critique modes that match the stakes of the decision. Arguments are decomposed into blocks that can be independently critiqued and scored, so a single weak block does not sink an otherwise sound proposal, and a single strong block cannot carry a broken one.

### Stage Flow

Every v2 decision review follows four stages in sequence:

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

Stages 1-3 are sequential (one agent waits for the previous). Stage 4 runs judges in parallel.

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

The continuous tone parameter from v1 is replaced with an explicit critique stance configured per run.

| Mode | Behavior | When to use |
|------|----------|-------------|
| `strict` | Attack every weakness, no charity | High-stakes safety, security reviews |
| `generous-steelman` | Present the strongest form of the opponent's argument first, then attack | Architecture decisions where missing a good idea is costly |
| `neutral` | Balanced critique, note strengths and weaknesses | Routine reviews, comparative analysis |

**Rationale**: The continuous dose-response hypothesis was falsified by the v1 experiment. Discrete modes are explicit, testable, and match user intent better than a percentage dial.

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

Judge influence is explicit per mode, not hard-coded.

**Judge weight schema**:

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

**Identity blinding**: During evaluation experiments, hide agent identity from judges. During operational use, judges may see role labels (proposer/critic) for accountability.

### v2 Mode 1: Architecture Decision

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

### v2 Mode 2: Comparative Analysis

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
      ...
    dealbreaker: "<if any>"

conditional_recommendation: "<winner if constraint X matters most>"
```

### v2 Mode 3: Writing Refinement

**When to use**: Technical writing, documentation, persuasive communication.

**Protocol difference**:
- Aesthete and Stylist have stronger influence
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

### v2 Prompt Templates

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

### Output Artifact Schema

Every v2 run produces a structured artifact at `.sisyphus/debates/{slug}/debate_v2.yaml`.

**Top-level schema**:

```yaml
# debate_v2.yaml
meta:
  topic: "<decision topic>"
  mode: architecture|comparative|writing
  timestamp: "<ISO8601>"
  critique_mode: strict|generous-steelman|neutral

participants:
  proposer:
    agent: "<agent_id>"
    role: oracle|general
  critic:
    agent: "<agent_id>"
    role: mephistopheles
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
  # use-case-specific artifact (see v2 modes above)
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

### What v2 Keeps From v1

- Judge role definitions (Aesthete, Stylist, Analyst)
- Persist-on-collect rule (write raw judge output to disk before parsing)
- Retry and recovery protocol (10 min timeout, one retry, then skip)
- Configurable judge counts
- Mode concept (specialized behaviors per use case)

### What v2 Drops From v1

- Continuous tone parameter (20-90%)
- Alpha/Beta winner-picking verdict
- Alternating blinding in operational mode
- S1-S4 segment scoring (replaced by block scoring)
- Whole-argument competition structure

### v2 Quick Start

**Architecture Decision**:
```
/debate v2 architecture "Should we use CQRS for this service?"
```
Output: `debate_v2.yaml` with `decision: ADOPT|REVISE|REJECT|ESCALATE`

**Comparative Analysis**:
```
/debate v2 comparative "GraphQL vs REST for public API"
```
Output: `debate_v2.yaml` with ranked options and dealbreakers

**Writing Refinement**:
```
/debate v2 writing "Refactor this API documentation for clarity"
```
Output: `debate_v2.yaml` with `revised_draft` and change log
