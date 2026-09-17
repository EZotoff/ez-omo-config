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

### 6. Name the empty states
Silence is ambiguous: the reader cannot tell *nothing found* from *never checked* from *deliberately omitted*. Name each one. State "no findings" as a finding that includes what was searched: *"No defects were found in the payment module (all 14 checks passed)."* If a section is not applicable, say why in one line. If material was redacted or could not be collected, name it. "We couldn't look" and "we looked and found nothing" are different statements — never blur them. An empty state is a line, not a section: name only the absences a reader would expect to find — never manufacture N/A entries to satisfy this rule.

### 7. End with the reader's action
Every report terminates in what the reader should now do — or an explicit *"no action required"*. A report that trails off after the findings leaves the reader to derive the action themselves. The action is a sentence, not a section.

### 8. Keep reader-facing surfaces consistent
If a verdict appears in a chat summary, in an artifact file, and in its PDF export, they must agree — same recommendation, same stated uncertainty, same next action. The chat summary is a *projection* of the canonical artifact, not an independent synthesis. Two surfaces that disagree is a defect.

---

## Editorial preferences

These make the writing better but admit judgment. Do not trade a contract rule for a preference.

- **Strongest point first within each section.** Open with the insight, not a soft lead-in.
- **Plain, direct language.** No AI-speak. If a phrase could only have come from an LLM, rewrite it. See the anti-slop list below.
- **Concise — subtraction first.** Cut repetition between sentences, sections, and cards on the same page. If two paragraphs say the same thing, keep one. Every section is as short as the material allows: detail unnecessary to understand, trust, or act on the result moves down the disclosure ladder (rendered reports) or out. If a section can be a table or three bullets, it is not four paragraphs.
- **Same noun for the same concept.** Once a report names a concept, every reference uses that exact name. Do not vary words for literary effect.
- **Active voice where natural.** Passive is fine when the actor is irrelevant ("the build was deployed"); never use it to dodge accountability ("mistakes were made").
- **Qualitative in summaries, quantitative in details.** A summary states the shape of the conclusion; the supporting numbers live in the chart or detail section. Do not strip numbers that materially justify a conclusion — but do not flood a summary with figures that belong in the data view.

### Anti-slop list (heuristic, not absolute)

These words and patterns are signals of AI-generated prose. Their presence does not automatically condemn a sentence, but each occurrence deserves a second look.

**Mechanically linted** (single tokens and fixed phrases the grep below catches): `leverages`, `utilizes`, `facilitates`, `enables seamless`, `harnesses`, `empowers`, `serves as`, `best-in-class`, `world-class`, `cutting-edge`, `delve into`, `navigate the complexities of`, `tapestry`, `unlock`, `seamlessly`, `robust`, `scalable`, `innovative`, `powerful`, `realm`, `landscape` (metaphorical).

**Judgment-only** (the lint cannot decide these): `acts as a catalyst`, `in today's fast-paced world`, `it is important to recognise that`, `in effect`, `by design` — and every token above in its "without specifics" sense: `robust` is fine when a specific follows it.

Also avoid: throat-clearing openers ("It is worth noting that…"), hollow transitions ("Furthermore, … Moreover, …"), and summary sentences that restate the preceding paragraph.

The list is not exhaustive — the test is *"does this sound like it could only come from an LLM?"*

---

## Channel profiles

The same contract applies everywhere, but each channel has different constraints.

### Chat summary (the in-conversation result message)

The message the orchestrator sends to the user after work completes. Constraints:

- **Lead with the verdict / recommendation / top finding** in the first sentence.
- **No process language.** No judge role labels, block IDs, scores, round numbers, "what was discarded", "the critic argued". The reader did not see the debate.
- **Define any necessary term inline** on first use, or omit it.
- **One-line pointer** to the full artifact at the end: *"Full record: panel-review.md + judges/."* — for the reader who wants the trace.
- **End with the next action** (or "no action required") next to the pointer.
- **Length scales to stakes.** A 1:1 challenge gets one or two sentences. A decision review gets a short paragraph plus the verdict line. Never more than the reader can scan in one screen.

### Rendered report (HTML / MD design doc / dashboard copy)

A standalone artifact a human opens to read. Constraints:

- **Open with the executive core** — verdict/top finding, a one-sentence plain-language distillation, and the next action as the opening lead, followed by the 3–6 sentence executive summary, no jargon, before any background. The reader who reads only the opening region must have the outcome (see *The opening region and disclosure ladder* in the craft section).
- **Self-contained: define every domain term, name, and label on first use.** No "see the underlying doc". (In dense domains a glossary section is acceptable; otherwise define inline.)
- **Open each section with its strongest point.**
- **Styling and dynamism follow the rendered-report craft section below** — the floor there is the minimum; the full section makes the report better.
- **Use the rich functionality of the medium** (HTML: nav, callouts, pull-quotes, sticky sidebars, expandable evidence) to improve readability and digestibility — not as decoration.

### Decision artifact (debate.yaml, panel-review.md as the canonical record)

The canonical record that the chat summary projects from. These *may* retain process detail (judge labels, scores, critique trace) because their purpose is traceability. But the reader-facing *framing* of these artifacts still follows the contract: the artifact opens with the decision/recommendation in plain language, and the process detail supports it — the process detail does not replace the result statement.

---

## Rendered-report craft

For rendered HTML reports and dashboard copy. The primary aim is **readability, digestibility, and clarity** — a professional, restrained look follows from getting those right. The house style is a proven brief, iterated over many approved reports: default to it, diverge only with reason. Synthesised with the anti-slop doctrine from [pbakaus/impeccable](https://github.com/pbakaus/impeccable).

### Styling floor (the load-bearing minimum)

These lines alone produce a correct, plain report. The rest of this section expands them — enrichment, never a precondition. An agent that applies only the floor ships something plain, never something wrong.

- **Warm near-black paper** (`#1B1814` / `#211E18`), **tinted near-white ink** (`#EDE9DF` / `#E2DDD0`). Never pure black or pure white — that is the dated "app terminal" look.
- **One restrained accent — pick one of amber `#D9A441` or teal `#4DAFB6` per report** — for focus, links, key callouts. Rarity is what makes it work: more than a handful of accent uses per screen and there is no hierarchy. Never carry meaning by colour alone — a tinted finding is also labelled.
- **Three-family type:** a serif or distinctive sans for display, a clean sans for body, a mono for metadata and labels. Body prose measure ~62–68 characters (prose only — width follows the viewport doctrine below).
- **Contrast floor:** body text ≥4.5:1; large text, controls, icons, and focus indicators ≥3:1. Secondary text is tinted from the ink hue, never neutral grey. On dark paper, compensate on three axes: slightly more line-height, a touch more letter-spacing, one weight step up where text reads thin.
- **Keyboard and data surfaces:** DOM order equals visual order (keyboard and screen-reader parity); style `:focus-visible` states; use `tabular-nums` on numeric tables.
- **PDF is a third surface.** Nobody prints paper; everyone exports PDF — and the PDF renderer runs the print stylesheet. The light-register values (`#C8901E` / `#006A71`) are the designed PDF palette — a register of its own, not an inversion. Source-level check: the stylesheet exists, nav and interactive chrome are stripped, `<details>` render open, sections/callouts/charts carry `break-inside: avoid`, and page breaks fall at section boundaries.

### House patterns (proven)

These patterns are validated across the user's approved reports. Default to them; diverge only with reason.

- **Warm near-black paper background**, not pure black (`#1B1814` / `#211E18` family). A tinted dark holds the "document" register; pure `#000` reads as "app terminal".
- **Tinted near-white ink**, not pure `#FFF` (`#EDE9DF` / `#E2DDD0` family). Pure white on warm dark is glaring.
- **One restrained accent colour** (pick one: amber `#D9A441` or teal `#4DAFB6`), lifted from its light-theme value (`#C8901E` / `#006A71`) to hold contrast on dark — the dark palette is designed, not inverted. Used sparingly — for focus, links, key callouts. Never as decoration.
- **Three-family type system:** a serif or distinctive sans for display headings, a clean sans for body, a mono for metadata/labels/captions. Pairings that have worked: Gloock + Inter + DM Mono; Crimson Pro + DM Sans + SF Mono. Avoid Inter-as-the-only-font. Four roles, purpose-named: display / body / meta / data.
- **Prose measure:** continuous reading text capped at ~62–68 characters wide — the skill's only hard width pin. It scopes to prose, never to tables, charts, or the page shell; long line lengths measurably hurt reading, and stretched prose is the widescreen failure mode.
- **Generous vertical rhythm:** a spacing scale (4/8/12/16/20/24/32/40/48/64/80/96px); more space above a heading than below it; tight groups, generous separation. Prefer `gap` over child margins for sibling rhythm.
- **Sticky nav / sidebar** for multi-section reports. The reader should always know where they are.
- **Callout boxes** for the doctrinal line, the key insight, the anchor scenario — visually distinct (a panel lifted or recessed relative to the paper, with a tinted left border in the accent colour). Use sparingly; a page of callouts is a page of nothing. *Decision procedure:* before adding a callout, ask whether spacing plus heading structure achieves the grouping — a container is the answer only when proximity is not.
- **Pull-quotes** in editorial italic for the one line that captures the thesis.
- **Pagination over single long sheet** for reports longer than ~3 screens — with a fixed nav footer (prev / next / page count). The opening region opens page 1; it never gets a page of its own.

### Viewport doctrine: desktop-first, content-chosen width

Desktop is the primary reading surface; mobile (~700px and below) is the collapse case. Width is not a preference — each section's width is chosen by the content itself.

**Lane table** (container widths are defaults, not pins; the 62–68ch prose measure is the only hard width pin):

| Lane | Content | Default container |
|---|---|---|
| Prose | Continuous reading text, executive core | measure column (62–68ch) with active margins — composed per the prose-composition rule |
| Evidence | Tables, charts, code, finding+evidence pairs | up to ~1280px |
| Wide | Dashboards, comparison matrices, timelines, wide data tables | up to ~1600px |

**Decision rule — narrowest sufficient lane, content-typed by default.** Assign each section its lane by content type (table/chart/code → Evidence; matrix/dashboard/timeline → Wide; everything else → Prose). Depart from the typed default only when the content is legible in a narrower lane without truncation, compressed type, or avoidable horizontal scrolling — or needs a wider one for the same reason — and record the lane with a one-line reason in the design-system comment block next to the lane. Two hard rules: prose never stretches to match the page shell, and the widest section does not force narrower sections wide — the page shell is exactly as wide as the widest lane the report actually contains.

**Prose composition on widescreen.** The Prose lane pins the *text block* at 62–68ch — that is reading physiology, not a page shape. What widescreen changes is what the margins do. An empty margin is a defect: a lone 64ch column floating in a 1600px viewport is not minimalism, it is an uncomposed page. Choose the composition by what the content carries:

- **Marginalia** — main column at measure; the outer margin (~240–320px) carries sidenotes, pull-quotes, footnote pointers, and small figures next to the passage they annotate. Default for argumentative prose (decision docs, post-mortems, essays) that has asides, references, or numbers worth keeping in view. Margin notes fold inline below their anchor on narrow viewports.
- **Companion rail** — a persistent adjacent column with orientation furniture: answer-card recap, key numbers, section nav, severity or epistemic-status legend. Default when the reader must hold context while reading long sections (decision reviews, findings reports). Folds above the body or into the header on narrow viewports.
- **Modulated flow** — prose at measure punctuated by full-container bands: pull-quotes, charts, tables, code. The width rhythm is the composition; the page shell is sized by the widest band. Default for mixed prose+evidence reports.
- **Wide reading** — measure extended toward the 75ch ceiling with a one-step type-size increase, centred with proportioned margins. Only for dense linear prose (specifications, legal, reference) where lateral eye travel is the cost and margins would otherwise sit empty. If no composition earns the margins, shrink the shell to the composed width instead.

Rejected: CSS multi-column prose. Vertical scrolling breaks column reading order on screen; columns are a paper device. They may return only in paginated print stylesheets, never in the scrolled layout.

**Mobile collapse (≤~700px):** single column; sidebar → compact header → drawer; wide tables become cards or scroll horizontally with intent; touch targets ≥44px; no hover-only functionality.

**QA order for rendered reports:** primary desktop width → widest realistic content → 200% zoom → 360px/320px reflow → PDF export. Desktop-first changes design order, not the acceptance floor. Render-dependent steps run when a render/QA pipeline is available (the conditional QA tier caveat applies); the order never changes. Source-checkable without a pipeline: the lane-and-reason entry in the design-system comment.

### The opening region and disclosure ladder

**The executive core.** The report opens with one component — the executive core: the verdict/decision/top finding, a one-sentence plain-language distillation (a "one-line version" that only makes sense because the report beneath backs it), and the next action (or "no action required"). At the report's declared desktop QA viewport and 100% zoom, all three appear within the initial viewport below persistent navigation, without scrolling or reduced body-text size; at every other size they are the first content in DOM order. The executive core is the opening lead of the executive summary — one component, not a synopsis in front of a synopsis. The closing action section may repeat the action only when enriched with owner, timing, or dependencies. When the material carries real uncertainty, state plainly in the opening region what is settled and what remains fog.

**The ladder:**

1. **Executive core + executive summary** — the opening region described above; 3–6 sentences, no jargon.
2. **Body sections** — strongest point first, prose at measure, each section in its lane.
3. **Layer 3, supplementary receipts** — raw data, methodology, full transcripts, per-item audit detail — in `<details>`, an appendix, or later pages. Hide only what is supplementary: evidence necessary to trust the verdict stays visible, and collapsing must never remove the document's evidentiary chain. Mark Layer-3 material as such; the PDF export shows everything.

### Anti-slop visual tells (avoid these)

- **Overused fonts as the only choice** (Arial, Inter-as-default, system-ui alone). Pair with a distinctive display face.
- **Gray text on coloured backgrounds.** Kills contrast.
- **Low-contrast grey text on tinted ground** — in either theme; dark backgrounds are not a licence for murky mid-greys.
- **Pure black backgrounds / pure white ink.** Always tint.
- **Bounce / elastic easing.** Dated — and it signals undecided motion.
- **Purple-to-blue gradients, rounded-square icon tiles above every heading, side-tab borders.** The canonical "generated by an LLM trained on SaaS templates" tells.
- **Glossy shadows, decorative gradients, feature-card grids.** Editorial brief, not marketing landing page. Register: *boardroom, not SaaS*.
- **One identical entrance animation on every section.** The scroll-stagger tell.

### Brand vs product lane

- **Brand lane** (investor briefs, external-facing exec summaries): more typographic personality, editorial polish, restrained drama.
- **Product lane** (internal design docs, dashboards, tool docs): cleaner, denser, more functional.

State the lane in the report's design-system comment block so later edits stay consistent.

### Emphasis dial (one rule, two directions)

- **Flat → bolder:** in the report's own vocabulary — full-strength display type, the pull-quote, the callout — scope sovereign (bold a section, not the document), no new primitives. One decisive verdict stated without hedge, then quiet support.
- **Noisy → quieter:** when competing bolds, contrast extremes, or container surplus pile up — weights 700→500, motion distances 10–20px not 40px, collapse competing containers, let neutrals do more work.
- **Both directions are tested the same way:** hierarchy and point of view survive the change. Severity inflation is flatness — if every finding is critical, none is.
- Hierarchy comes from weight, size, and space — not more colour.
- The emphasis dial and the earned dynamic moment (below) are mutually exclusive on the same element: dial the element up, or give it the moment — never both.

### Motion and dynamism

Reports are Read mode: motion serves feedback, state, and continuity. Three categories, one budget:

**1. Wayfinding and continuity furniture (always allowed, never counted).** Scrollspy nav highlighting and a reading-progress indicator — they serve the house "reader always knows where they are" rule continuously. Pagination transitions — 300–500ms, exit faster than entrance. Mechanical, quiet, no per-report design cost. Not counted against the moment budget.

2. **Reader-controlled affordances (always allowed, never counted).** Expandable evidence trails (`<details>`): the executive summary stays lean; the receipts are one click down — rendered open in the PDF export by default. Epistemic-status filter/highlight on findings (fact / inference / recommendation) — the report-native use of interactivity. Rules: default state shows all content (nothing load-bearing hidden behind a toggle the reader must find; material marked as Layer-3 supplementary receipts under the disclosure ladder is the sole exception), the PDF export shows everything, reduced-motion safe, keyboard reachable.

**3. The one earned dynamic moment (budget: exactly one).** One authored emphasis beat **derived from this report's thesis** — the key chart settling into place on arrival, the adopted recommendation's callout receiving the emphasis. Test: *specific enough that a neighbouring product could not use it unchanged.* Generic whimsy is worse than neutral clarity. **Default-visible:** the fully-rendered document is the state of record; animation may enhance what is already visible, never gate it — reports get PDF'd, archived, emailed; a scroll-reveal without JS is a blank export. Never delays or blocks reading; skippable; tolerates re-reading; the report stays fast and obvious without it. `prefers-reduced-motion` means fewer and gentler effects, not none (nav highlighting stays; spatial movement goes). Data updates animate state (bars settle), never construct from zero, and never sit between the reader and the data.

**Timing footnote:** feedback 100–150ms; routine state 150–300ms; layout/pagination 300–500ms; the one authored entrance up to 500–800ms. Arrivals ease `cubic-bezier(0.16, 1, 0.3, 1)`. Never bounce or elastic.

**Refusals (named):** sound, haptics, shader/spectacle register, tooltips, guided tours, progress-tracking storage. No visual or interactive ambition compensates for a buried verdict — contract compliance precedes any enhancement.

**Dashboards are the one data-fluid surface.** Virtualised/deferred rendering for large result sets, animated transitions between data states (filtering included), lazy initialisation near the viewport, pause when hidden. Nowhere else.

### PDF and delivery

The floor's PDF rules (stylesheet exists, chrome stripped, `<details>` open, section-boundary breaks) are source-checkable and always apply. Beyond them:

- Page numbers and an export date in the PDF footer — page counters work only inside `@page` margin boxes; `counter(page)` in ordinary content renders `0`. Charts PDF-friendly (no hover-dependent labelling).
- **Mobile:** sticky sidebar collapses (sidebar → compact header → drawer); wide tables become cards or scroll horizontally with intent; touch targets ≥44px; no hover-only functionality (`hover: none`); content-driven breakpoints.
- **Check flipped colour pairs after the palette flip:** ink-on-accent text in the PDF register (e.g. labels inside accent bars) must clear the same contrast floor as the screen version — the flip is where 4.5:1 quietly becomes 2.8:1.
- **Conditional QA tier** (when a render/QA pipeline is available — not a per-report requirement): screenshot at 360px width and at the widest realistic copy; PDF-preview pass; CJK fallback-face measure check and emoji line-height survival when source material contains them; smooth-on-mid-range-hardware check. Don't trust imagination over a render — but don't block shipping on an unavailable pipeline either.

### Robustness

Three rules, always:

1. **Reserve space for every visual** — `width`/`height` attributes or `aspect-ratio`. Unreserved charts and images reflow text while the reader scrolls and destroy reading position mid-argument.
2. **Wrap extreme values** — `overflow-wrap: anywhere` on data cells, `min-width: 0` on flex/grid children, truncation with intent. Every data slot must survive its longest realistic value (100+ character names, millions-scale numbers).
3. **A broken chart degrades to its data table** — never a blank region; one failed visual must not take its section with it.

Payload: self-contained reports (embedded fonts, images) stay in the low single-digit MB — they get emailed, archived, and opened on phones. With webfonts: subset them; `font-display: swap` with metric-compatible fallbacks. Offline / no-webfont reports: name the pairing as stack heads over locally available faces (serif display / sans body / mono meta) and check fallback glyph coverage in the export.

### Genre guidance (findings-reports, audits, surveys)

Applies to findings-report and survey genres; not needed for briefs and notes.

- **Positive findings are required.** A report listing only problems makes every problem look systemic; "what's working" is the calibration baseline for everything else. Skipping positives is a NEVER. Stated briefly — calibration, not padding.
- **Findings template:** location (section + paragraph, never "somewhere in the middle") · category · impact — *why it matters*, mandatory · recommendation · severity P0–P3 (aligned with review severity). Too many P3s is noise; if everything is critical, nothing is.
- **Patterns vs one-offs:** separate recurring findings ("the term is used inconsistently in 12 places") from one-off defects — the patterns section is where the reader learns the cause class.
- **Synthetic/illustrative material** is a marked epistemic category alongside fact/inference/recommendation. Fine to include — labelled wherever a reader could mistake it for real data ("illustrative example, not measured").
- **Conventions legend:** at most three explained conventions (severity levels, epistemic tags, symbols) in a small legend near the top. Needing more than three is a signal the report is over-engineered, not that the reader is under-prepared.
- **Revisions:** v2 of any report opens with a what-changed line so returning readers route to the delta.
- **Series:** recurring report families keep identical structure — learned structure is navigation; novelty lives in content, never in scaffolding. A stable scored dimension gives readers trajectory, not just state.

---

## Enforcement: lint, then independent review

A writer checking its own checklist is weak enforcement — models tend to rubber-stamp their own output. Split enforcement into two layers.

### Layer 1 — Deterministic lint (run first)

Grep the draft for patterns that are *always* defects in a reader-facing surface. Each match is a finding to fix or justify — "justified" means you can say why in one line, not that you ignore the match. Quoted source material and genre-required terms (a changes report may legitimately name its review panel) are the standard exemptions — state the exemption rather than contorting the prose:

```
# Process provenance leaks (chat summaries and reader deliverables)
grep -niE 'carried over|transferred from|inherited from|as discussed in round|per the (judge|critic)|the critic (scored|argued)|block b[0-9]'

# Score / ID syntax leaking into prose
grep -nE '\b(block|judge|analyst|stylist|aesthete) [a-z0-9]+[: ]|score[d]? [0-9]/[0-9]|[0-9]/[0-9] (from|out of)'

# AI-speak tells — single tokens and fixed phrases from the anti-slop list
grep -niE 'leverag|utiliz|facilitat|enables seamless|harness|empower|serves as|cutting-edge|best-in-class|world-class|delve into|navigate the complexit|tapestry|unlock|seamlessly|\b(robust|scalable|innovative|powerful|realm)s?\b|landscap'

# Throat-clearing and hollow transitions — anywhere in the paragraph
grep -niE '\b(it is (important|worth) (to )?(note|recogni|mention)|worth noting|furthermore|moreover)\b'

# Line-opening filler
grep -niE '^(in (effect|design|today)|needless to say)[a-z]*,?'
```

Run the lint before declaring done — but do not show its output to the Layer-2 reviewer before their pass (below).

### Layer 2 — Independent semantic review (run second)

A separate pass that sees **only the draft and the intended audience** — not the source artifacts, not the process, and not the lint findings until after the review is written (lint output anchors judgment; cold reads find more).

Instantiate one concrete reader — name the role ("a maintainer joining next month") — and read the draft as that person.

**Always asked (every surface):**

1. Can a reader who did not see the source material identify the conclusion?
2. Are there undefined terms, names, or references a fresh reader cannot resolve?
3. Are there claims presented as fact that are actually inference or recommendation?
4. Are there statements the source data does not support?
5. Do all surfaces agree — chat summary, artifact, and (for rendered reports) the PDF export?

**Rendered reports also ask:**

6. *Skeleton and squint:* strip the prose — do headings, emphasis, and callout placement alone carry the arc? Blur the render — are the primary element, secondary element, and major groups still identifiable in order?
7. *Removal test:* would removing any animation lose meaning or authored character — not merely decoration?
8. Does any heading say the same thing as its opening paragraph?
9. *Opening region:* at the declared desktop QA viewport and 100% zoom, do the verdict, one-sentence distillation, and next action appear without scrolling — and lead the DOM order at every other size? Is each section in its narrowest sufficient lane, with the lane choice and reason recorded in the design-system comment?

**Protocol:**

- Findings carry severity: **P0** contract violation / unsupported claim, **P1** wrong or missing load-bearing content, **P2** clarity or structure, **P3** polish. P0–P2 block completion; P3 may be waived with a one-line reason.
- A one-sentence evidence line is required **per finding**, never per passing answer.
- If no independent reviewer is available, the deliverable must say *"⚠ Self-reviewed only — no independent pass"* in its completion message **and** in the artifact footer. A silent degraded review is a failed review.
- Unresolved P0–P2 findings block completion. Cap the revision loop at one or two cycles — if it cannot converge, the problem is the source material, not the prose.
- Spend review effort where reader attention goes: executive summary and verdict get the most scrutiny, the appendix the least.

Do not present the writer's self-attested checklist to the user as evidence of quality. The lint output and the independent-review findings are the evidence.

---

## Modes

### Generate mode

Produce a reader-first report from source material (debate artifacts, data, a design decision, a set of findings).

1. Read the source material fully.
2. **Brief, proportional to the material.** State purpose, audience, and the single most important result as two or three assertions; invite correction once — then build. Never ask aesthetic questions ("what tone do you want?") — infer tone from the material. Only genuinely ambiguous, multi-section work gets the full brief with an **anti-goal** ("what would make this result feel wrong even if it looked polished?"). No requester available (background run)? Write the assumptions into the report header and proceed.
3. **State the settings inline:** density (standard / comprehensive), lane (brand / product), medium (chat / HTML), emphasis (quiet / confident). A later "make it denser" is a dial turn on these, not a regeneration.
4. **The specificity test (this skill's named central test):** *what does this material know that a generic template wouldn't?* If the answer is nothing, the report is a summary of summaries — say so instead of disguising it.
5. **Openings, when stakes justify it** (a requester is present AND the opening carries the argument): offer **three openings on three different axes** — e.g. verdict-first vs risk-first vs opportunity-first, or summary-then-evidence vs evidence-woven vs context-first — each labelled with one line. All three obey the **identity lock**: same verdict, same evidence base, same stated uncertainty; a variant that strengthens the verdict has crossed into fabrication. If two labels read alike, the variants are not different — redo. The plain standard opening is always one of the three, played straight. Otherwise, draft the standard opening directly.
6. Draft the executive core (verdict, one-sentence distillation, next action) and the executive summary first — before any other section.
7. Build the body around the result, each section opening with its strongest point. Define every term on first use.
8. Run lint, then independent review. Fix findings.
9. **Completion checklist:** contract questions pass; all surfaces agree (chat ↔ artifact ↔ PDF); no draft fragments remain (unused variants, placeholder sections, orphaned labels).

### Pass mode

Take an existing report draft (or a chat-level summary) and run an editorial pass to bring it into contract compliance.

1. Read the draft and classify violations in fix order: **unsupported claims and contradictions → missing empty states → structure/hierarchy drift → style → cleanup.** Fix in that order.
2. List the load-bearing facts and caveats — one line each. After the pass, every line must have survived.
3. **Anti-smuggling:** fix prose and style; do not restructure the argument, reorder sections, or shift the verdict's strength. If the structure is wrong, say so and recommend restructuring — do not quietly do it. When ambiguous between restyle and restructure, restyle, and say so.
4. Every edit must map to a finding — a lint hit, a review finding, or a violation class from step 1. An edit that maps to nothing is churn: revert it. A global edit is legitimate only against a named recurring finding ("the term X is used inconsistently 12 times"), never a vague "style".
5. Run lint, then independent review. Fix findings.
6. Preserve every fact and every material caveat — a pass that drops substance to improve style has failed. Check against the list from step 2.

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

**Unnamed empty state:**
- ✗ *(section simply absent from the findings report)*
- ✓ *"No access-control issues were found; all 9 configured routes require authentication (checked 2026-08-14)."*

**Trailing off:**
- ✗ *…findings section ends, document ends.*
- ✓ *"No action required this cycle; re-run the audit after the v2 migration (owner: platform team)."*

**Verbose burial:**
- ✗ Four paragraphs of background and methodology before the recommendation appears on screen 2.
- ✓ Verdict, one-line distillation, and next action in the opening viewport; methodology one click down in Layer 3.

**Repetition:**
- ✗ Two paragraphs both stating "retention is the priority" with different wording.
- ✓ One paragraph stating it once, with the supporting number.

## Layer hooks (typography stack)

1. When the deliverable is a rendered HTML report and copy changes: load `skill(name='web-typography')` and apply its engineering floors beneath this skill's house style
2. When a section explains a concept from scratch: apply the fresh-explain method via `skill(name='fresh-explain')`
3. When motion or interaction is in scope: load `skill(name='dynamic-typography')` for mechanics; this skill's one-earned-moment budget and timing bands are PINS overriding its ranges
4. When delegating writing to a subagent: pass `load_skills=['typographic-writing']` or the genre-appropriate stack - parent loading does not propagate to children

- Measure 62-68ch (prose only; section widths follow the viewport doctrine's lane table), one earned moment, timing bands are pinned values, never averaged with layer ranges.
- The chat-summary genre loads no typography layer.
