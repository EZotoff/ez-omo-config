---
name: reader-report
description: "Reader-first writing for any deliverable a human reads to understand a result: HTML reports, MD design docs, debate-result summaries, survey dashboards, executive briefs, handoff notes, panel-review syntheses. Writes for a reader who has NOT read the preceding material. NOT for: bug reports, incident reports, status reports, telemetry, logging, code comments, or ordinary chat answers."
---

# Reader-Report — Self-Contained, Reader-First Writing

<role>
You write for a reader who was not present for the work. Every report, summary, and brief you produce must be understandable on its own — without the reader having read the source artifacts, the preceding conversation, the judge outputs, or the prior version of the document.

The recurring failure this skill exists to fix: deliverables that read as if the reader has already read everything else. Symptoms include undefined acronyms and names, process-internal language ("carried over from v3", "inherited from your analysis"), comparative summaries ("X was discarded in favour of Y"), judge/block/score references the reader never saw, and prose that describes *how the work was done* instead of *what the result is*.

Your register is editorial, confident, and direct — not academic, not marketing.
</role>

## When to use this skill

Load this skill whenever the deliverable is something a human reads to understand a result:

- HTML reports, dashboard copy, survey reports
- MD design documents, technical briefs, executive summaries
- Debate / panel-review / decision-review result summaries
- Handoff notes, post-mortems, pre-mortems, red-team reports
- Any artifact where a reader's job is to learn *what was decided / found / recommended*

## When NOT to use this skill

- Bug reports, incident reports, status updates, telemetry, logging
- Code comments, commit messages, PR descriptions (those have their own conventions)
- Ordinary chat answers to a question
- The raw audit record (judge outputs, transcripts, scoring YAML) — those are for traceability, not reading

---

## The reader contract (non-negotiable)

These hold for every reader-facing surface. Violating any of them breaks the contract.

### 1. Lead with the answer
The decision, recommendation, or finding comes first — before any background, methodology, or context. A reader who stops after the first paragraph must have the outcome.

**Bad:** *"Three judges evaluated the proposal across correctness, feasibility, and risk. The analyst scored block b1 at 4/5…"*
**Good:** *"Adopt the proposal. It solves the stated problem, is feasible with current resources, and the main risk (X) has a documented fallback."*

### 2. Supply enough context for the intended audience
Define the audience explicitly and write to them. A CEO/operator audience needs plain-language framing; a technical audience can assume domain fluency. State the assumption: *"Written for a reader who knows the product but not this decision."*

### 3. Remove inaccessible process provenance
Strip every reference to how the work was produced that the reader cannot see: "carried over from v3", "inherited from your analysis", "the critic scored", "as discussed in round 2", "per the judge panel". The reader was not there. **Nobody cares where the result came from — they care what it is.**

This is the single most common regression. Treat any phrase that narrates *the process of producing this text* as a defect.

### 4. Preserve evidence and material uncertainty
Do not delete the evidence to make the prose cleaner. If the recommendation rests on three findings, the findings stay — stated in plain language, not buried in a score table. If there is real uncertainty ("this depends on whether X holds"), say so plainly. Confidence without honesty is a worse failure than hedging.

### 5. Distinguish fact, inference, and recommendation
Mark the epistemic status. *"The churn rate is 34% (measured)"* is a fact. *"This suggests retention is the priority (inference)"* is an inference. *"Prioritise retention work next quarter (recommendation)"* is a recommendation. Do not let an inference read as a measured fact, and do not let a recommendation pretend to be an inference.

### 6. Keep reader-facing surfaces consistent
If a verdict appears in a chat summary and in an artifact file, they must agree — same recommendation, same stated uncertainty, same next action. The chat summary is a *projection* of the canonical artifact, not an independent synthesis. Two surfaces that disagree is a defect.

---

## Editorial preferences

These make the writing better but admit judgment. Do not trade a contract rule for a preference.

- **Strongest point first within each section.** Open with the insight, not a soft lead-in.
- **Plain, direct language.** No AI-speak. If a phrase could only have come from an LLM, rewrite it. See the anti-slop list below.
- **Concise.** Cut repetition between sentences, sections, and cards on the same page. If two paragraphs say the same thing, keep one.
- **Active voice where natural.** Passive is fine when the actor is irrelevant ("the build was deployed"); never use it to dodge accountability ("mistakes were made").
- **Qualitative in summaries, quantitative in details.** A summary states the shape of the conclusion; the supporting numbers live in the chart or detail section. Do not strip numbers that materially justify a conclusion — but do not flood a summary with figures that belong in the data view.

### Anti-slop list (heuristic, not absolute)

These words and patterns are signals of AI-generated prose. Their presence does not automatically condemn a sentence, but each occurrence deserves a second look. The list is not exhaustive — the test is "does this sound like it could only come from an LLM?"

`leverages`, `utilizes`, `facilitates`, `enables seamless`, `harnesses`, `empowers`, `serves as`, `acts as a catalyst`, `best-in-class`, `world-class`, `robust`, `scalable` (without specifics), `cutting-edge`, `innovative` (without specifics), `in today's fast-paced world`, `it is important to recognise that`, `in effect`, `by design`, `delve into`, `navigate the complexities of`, `tapestry`, `realm`, `landscape` (metaphorical), `unlock`, `seamlessly`, `powerful`.

Also avoid: throat-clearing openers ("It is worth noting that…"), hollow transitions ("Furthermore, … Moreover, …"), and summary sentences that restate the preceding paragraph.

---

## Channel profiles

The same contract applies everywhere, but each channel has different constraints.

### Chat summary (the in-conversation result message)

The message the orchestrator sends to the user after work completes. Constraints:

- **Lead with the verdict / recommendation / top finding** in the first sentence.
- **No process language.** No judge role labels, block IDs, scores, round numbers, "what was discarded", "the critic argued". The reader did not see the debate.
- **Define any necessary term inline** on first use, or omit it.
- **One-line pointer** to the full artifact at the end: *"Full record: panel-review.md + judges/."* — for the reader who wants the trace.
- **Length scales to stakes.** A 1:1 challenge gets one or two sentences. A decision review gets a short paragraph plus the verdict line. Never more than the reader can scan in one screen.

### Rendered report (HTML / MD design doc / dashboard copy)

A standalone artifact a human opens to read. Constraints:

- **Front-load an executive summary** — 3–6 sentences, no jargon, before any background. The reader who reads only this must have the outcome.
- **Self-contained: define every domain term, name, and label on first use.** No "see the underlying doc". (In dense domains a glossary section is acceptable; otherwise define inline.)
- **Open each section with its strongest point.**
- **Styling follows the HTML guide below.**
- **Use the rich functionality of the medium** (HTML: nav, callouts, pull-quotes, sticky sidebars) to improve readability and digestibility — not as decoration.

### Decision artifact (debate.yaml, panel-review.md as the canonical record)

The canonical record that the chat summary projects from. These *may* retain process detail (judge labels, scores, critique trace) because their purpose is traceability. But the reader-facing *framing* of these artifacts still follows the contract: the artifact opens with the decision/recommendation in plain language, and the process detail supports it — the process detail does not replace the result statement.

---

## HTML styling guide

For rendered HTML reports. The primary aim is **readability, digestibility, and clarity** — a professional, restrained look follows from getting those right. This guide synthesises the user's proven house style (the reports iterated over many rounds of feedback) with the anti-slop tells from [pbakaus/impeccable](https://github.com/pbakaus/impeccable).

### Primary aims (in priority order)

1. **Readability** — typography hierarchy, comfortable measure, sufficient contrast, legible type size.
2. **Digestibility** — clear structure, scannable headings, progressive disclosure, callouts for key points.
3. **Clarity** — plain-language labels, data-faithful visuals, terms defined inline.
4. **Professional polish** — consistent design system, restrained colour, no SaaS-template tells.

### House style (proven patterns)

These patterns are validated across the user's approved reports. Default to them; diverge only with reason.

- **Warm off-white paper background**, not pure white (`#F5F2EC` / `#FBFAF7` family). Reduces glare; signals "document" not "app".
- **Tinted near-black ink**, not pure `#000` (`#0D0D0D` / `#1C1B19` family). Pure black on warm paper is harsh.
- **One restrained accent colour** for emphasis (amber `#C8901E`, teal `#006A71`). Used sparingly — for focus, links, key callouts. Never as decoration.
- **Three-family type system:** a serif or distinctive sans for display headings, a clean sans for body, a mono for metadata/labels/captions. Pairings that have worked: Gloock + Inter + DM Mono; Crimson Pro + DM Sans + SF Mono. Avoid Inter-as-the-only-font.
- **Comfortable measure:** body prose capped at ~62–68 characters wide. Long line lengths measurably hurt reading.
- **Generous vertical rhythm:** a spacing scale (4/8/12/16/20/24/32/40/48/64/80/96px), sections separated by rule lines or large vertical gaps.
- **Sticky nav / sidebar** for multi-section reports. The reader should always know where they are.
- **Callout boxes** for the doctrinal line, the key insight, the anchor scenario — visually distinct (dark box, tinted background, left border). Use sparingly; a page of callouts is a page of nothing.
- **Pull-quotes** in editorial italic for the one line that captures the thesis.
- **Pagination over single long sheet** for reports longer than ~3 screens — with a fixed nav footer (prev / next / page count).

### Anti-slop tells (from impeccable — avoid these)

- **Overused fonts as the only choice** (Arial, Inter-as-default, system-ui alone). Pair with a distinctive display face.
- **Gray text on coloured backgrounds.** Kills contrast.
- **Pure black/grey palettes.** Always tint.
- **Cards nested in cards**, or everything-wrapped-in-a-card. Use cards only where grouping is meaningful.
- **Bounce / elastic easing.** Feels dated. Motion should be purposeful and subtle.
- **Purple-to-blue gradients, rounded-square icon tiles above every heading, side-tab borders.** The canonical "this was generated by an LLM trained on SaaS templates" tells.
- **Glossy shadows, decorative gradients, feature-card grids.** This is an editorial brief, not a marketing landing page. Register: *boardroom, not SaaS*.

### Brand vs product lane

Match the visual register to the deliverable's purpose:

- **Brand lane** (investor briefs, external-facing exec summaries): more typographic personality, editorial polish, restrained drama.
- **Product lane** (internal design docs, dashboards, tool docs): cleaner, denser, more functional.

State the lane in the report's design-system comment block so later edits stay consistent.

---

## Enforcement: lint, then independent review

A writer checking its own checklist is weak enforcement — models tend to rubber-stamp their own output. Split enforcement into two layers.

### Layer 1 — Deterministic lint (run first)

Grep the draft for patterns that are *always* defects in a reader-facing surface. Each match is a finding to fix or justify:

```
# Process provenance leaks (chat summaries and reader deliverables)
grep -niE 'carried over|transferred from|inherited from|as discussed in round|per the (judge|critic)|the critic (scored|argued)|block b[0-9]'

# Score / ID syntax leaking into prose
grep -nE '\b(block|judge|analyst|stylist|aesthete) [a-z0-9]+[: ]|score[d]? [0-9]/[0-9]|[0-9]/[0-9] (from|out of)'

# AI-speak tells
grep -niE 'leverag|utiliz|facilitat|enables seamless|harness|empower|serves as|cutting-edge|best-in-class|world-class|delve into|navigate the complexit|tapestry|unlock|seamlessly'

# Throat-clearing openers
grep -niE '^(it is (important|worth) (to )?(note|recogni|mention)|in (effect|design|today)|furthermore|moreover),'
```

These are the user's *existing* practice — they already ship grep regression tests on report outputs. Make the lint explicit and run it before declaring done.

### Layer 2 — Independent semantic review (run second)

A separate pass that sees **only the draft and the intended audience** — not the source artifacts, not the process. It answers four questions:

1. Can a reader who did not see the source material identify the conclusion?
2. Are there undefined terms, names, or references a fresh reader cannot resolve?
3. Are there claims presented as fact that are actually inference or recommendation?
4. Are there statements the source data does not support?

Unresolved findings block completion. Cap the revision loop at one or two cycles — if it cannot converge, the problem is the source material, not the prose.

Do not present the writer's self-attested checklist to the user as evidence of quality. The lint output and the independent-review findings are the evidence.

---

## Modes

### Generate mode

Produce a reader-first report from source material (debate artifacts, data, a design decision, a set of findings).

1. Read the source material fully.
2. Identify the audience and the single most important result.
3. Draft the executive summary / opening verdict first — before any other section.
4. Build the body around the result, each section opening with its strongest point.
5. Define every term on first use.
6. Run lint, then independent review. Fix findings.
7. Verify against the reader contract before declaring done.

### Pass mode

Take an existing report draft (or a chat-level summary) and run an editorial pass to bring it into contract compliance.

1. Read the draft identifying contract violations (process provenance, undefined terms, buried lede, unsupported claims, repetition).
2. Rewrite the opening so it leads with the result.
3. Strip process language. Define undefined terms. Cut repetition.
4. Run lint, then independent review. Fix findings.
5. Preserve every fact and every material caveat — a pass that drops substance to improve style has failed.

---

## Jargon-glossary pattern

When a report uses domain-specific terms (product names, role labels, technical concepts), define each on first use. Two acceptable forms:

- **Inline** (preferred for sparse terms): *"Oren (Veran's AI assistant) opens the interview…"*
- **Glossary section** (acceptable in dense domains): a dedicated section near the top or bottom, with each term defined once and used consistently thereafter.

The test: a fresh reader should never encounter a term they cannot resolve from the document alone. If a term appears undefined, that is a lint-level defect.

---

## Quick reference — bad → good

**Buried lede:**
- ✗ *"Three judges reviewed the proposal. After two rounds of critique and revision, the panel converged on…"*
- ✓ *"Adopt. The proposal is feasible and the main risk has a documented fallback."*

**Process provenance leak:**
- ✗ *"The reframe inherits the shepherd metaphor from the analyst's round-2 contribution."*
- ✓ *"The framing that lands: you are herding agents, not micromanaging them."*

**Undefined reference:**
- ✗ *"Section 4 shows how C and F compose."*
- ✓ *"Section 4 shows how the capture workflow (C) and the feedback workflow (F) compose."*

**AI-speak:**
- ✗ *"This leverages a robust, scalable architecture that empowers teams to seamlessly navigate the complexity landscape."*
- ✓ *"The design separates capture from feedback so each can change without breaking the other."*

**Repetition:**
- ✗ Two paragraphs both stating "retention is the priority" with different wording.
- ✓ One paragraph stating it once, with the supporting number.
