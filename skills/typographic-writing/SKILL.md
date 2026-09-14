---
name: typographic-writing
description: "L0 prose mechanics for the typography stack: drafting, rewriting, and critiquing text for cadence, punctuation discipline, clarity, voice, and medium fit. Fires on explicit user requests to draft, rewrite, or critique prose for cadence, punctuation, clarity, voice, or a named medium profile, and when another skill explicitly chains to it. NOT for ordinary chat answers, code, factual explanations, deliverables governed by another skill (reader-report, fresh-explain), HTML styling, or typography engineering (web-typography, dynamic-typography)."
---

# Typographic Writing

Use this skill when the main artifact is language: drafting, rewriting, editing, condensing, polishing, scripting, slide copy, or UI text. It runs on explicit user request or on chain from a higher-layer skill.

The objective is not to make text look casually human by adding quirks. The objective is to make it feel authored: purposeful, specific, rhythmically varied, and proportionate to its medium.

Writing has typography before it has fonts. Sentence length, paragraph shape, punctuation, headings, lists, emphasis, and whitespace all determine how a reader experiences language. Write so that form reveals meaning instead of competing with it.

## Method

### 1. Establish the reading situation

Before drafting, infer or identify:

- Who is reading, and what do they already know?
- What should they understand, believe, decide, or do afterward?
- Is the text read closely, scanned, heard aloud, projected, or used as an interface control?
- What level of evidence and qualification is expected, and what voice fits: formal, conversational, persuasive, neutral, technical, or playful?

If the user has already supplied this context, do not ask for it again.

### 2. Find the information spine

State the central idea internally in one plain sentence. Order supporting points by the reader's needs, not by the order in which the writer discovered them. Prefer a visible argument or narrative over a sequence of loosely related observations.

Know each paragraph's job: make a claim, give evidence, explain a mechanism, qualify a claim, contrast alternatives, give an example, draw an implication, or request an action. Do not keep a paragraph merely because its sentences are individually good.

### 3. Draft for meaning, then tune rhythm

First make the statement accurate. Then shape its cadence.

- Mix short, medium, and occasional long sentences. Avoid a mechanical pattern where every sentence has the same length or every paragraph has three sentences.
- A short sentence should earn its force. Do not manufacture drama by turning every other thought into a fragment.
- Vary sentence openings. Do not repeatedly begin with "This", "It is", "There are", or the same transition.
- Prefer concrete nouns and active verbs over adjective stacks and abstract nominalizations.
- Replace generic intensifiers ("very significant improvement") with the actual improvement when it is known.

## Punctuation as notation

Punctuation clarifies syntax and rhythm. It is not stage direction for the reader.

### Em-dash policy: discipline by default

The em dash is permitted but must be a deliberate choice, never a habit. Before inserting one, name the relation you actually mean and prefer its proper mark:

- new thought or emphasis: use a period
- light interruption: use commas
- explanation, consequence, or expansion: use a colon
- closely related independent clauses: use a semicolon, if the register supports it
- genuine aside: use parentheses
- range in running prose: prefer "to" or "through" when it reads naturally
- a sentence too overloaded for any of these: rewrite it

The default fix is often a better sentence, not a different dash.

Two rules hold always, in every mode and profile:

- `--` pseudo-dashes are banned outright. Never type two hyphens where a dash belongs.
- Quoted, cited, or source-styled text is preserved verbatim. Never re-punctuate a quotation, a citation, or text that carries another source's house style.

### Other punctuation

- Use one space after a sentence.
- Avoid exclamation marks unless the content genuinely calls for one. Avoid ellipses as a generic signal of informality or suspense.
- Avoid scare quotes and decorative quotation marks. Quote only when attribution, terminology, irony, or exact wording matters.
- Do not chain punctuation for emotion: `?!`, `!!!`, `...!` and similar forms are exceptional devices, not house style.
- Use semicolons sparingly. They should connect ideas, not make prose look literary.

## Profile: zero-em-dash

A named profile that tightens the default policy into a hard rule for new prose. It can be pinned two ways:

- by the user, in any request (for example "use the zero-em-dash profile"), or
- by a genre or higher-layer skill, as a pinned value under the layer contract.

When pinned, the rule for newly authored prose is: Do not use the em dash character. Do not use paired hyphens as a substitute. Choose the relation punctuation instead: period, colon, semicolon, commas, or parentheses.

The profile extends the ban to newly authored prose ONLY. It never requires rewriting text the user did not ask to change, and it never alters quotations, citations, or source-styled text; those are preserved verbatim always. When editing existing prose under the profile, apply the rule to sentences you newly write or restructure, and leave the rest unless asked.

## Mannerisms

Rewrite or delete these machine-written patterns when they appear without a real communicative purpose:

- generic scene-setting and throat-clearing before the point ("It is important to note that...", "In today's rapidly evolving landscape...")
- filler vocabulary: "delve into", "navigate", "leverage", "realm", "tapestry", "multifaceted"
- repeated "not only X, but Y" constructions, and rhetorical contrast in every paragraph
- a heading for every tiny idea, or excessive bolding of phrases the reader can already identify as important
- relentless three-item lists because three happens to sound complete
- recap sentences that repeat the previous paragraph, or a final paragraph that restates the whole answer
- false intimacy ("Here's the thing") when the voice has not earned it
- generic praise before criticism, generic caveats after every claim, or invented certainty

Do not ban a phrase merely because language models often use it. Ban unmotivated patterns. If a phrase is exact and natural in context, keep it.

When asked to make prose "more human", subtract first: generic framing, duplicated explanation, ritual caveats, over-signposting, decorative adjectives, punctuation as performance. Add personality only where the audience and medium benefit from it.

## Medium profiles

Apply the universal rules above, then select the closest profile.

### Research and technical

Optimize for precision, auditability, and controlled claims. Put the claim near its evidence; distinguish observation, interpretation, hypothesis, and recommendation; preserve uncertainty with exact qualifiers such as "suggests" or "is consistent with". Define terms before relying on them, keep rhetorical flourish low, and keep citations adjacent to the claims they support. Long is acceptable; tangled is not.

### Business and executive

Optimize for decision speed without stripping away evidence. Lead with the consequence, decision, or finding; follow with the strongest evidence and the relevant uncertainty. Separate facts from recommendations, make ownership and next actions explicit, and cut ceremonial language. Default sequence: finding -> evidence -> implication -> action.

### Marketing and editorial

Optimize for attention, comprehension, credibility, and memorability. Start with a concrete tension, benefit, or image rather than a generic claim of importance. Prefer one strong promise over several inflated ones, and use specificity as persuasion: examples, constraints, numbers, names. Let personality appear through choice of detail, not punctuation stunts.

### Presentation writing

Optimize for comprehension at a glance and support for spoken explanation. One main idea per slide; write for the eye and ear, not silent document reading. Prefer a claim as the slide title when the evidence supports one; keep fragments only when structurally parallel. Remove words the speaker will naturally supply.

### Product and UI copy

Optimize for action, prediction, and recovery. Name controls by what they do, put the key noun or verb early, and use the user's vocabulary, not the implementation's. On errors, tell the user what happened, why it matters, and what they can do next. No humor in destructive, security-sensitive, financial, or high-stress moments.

### General explanatory prose

Optimize for understanding and sustained reading. Give the reader a mental model before details when the topic is complex, and move between abstraction and concrete examples. Use transitions only when the relationship is not already obvious. Let paragraph length vary with the idea.

## Cadence checks

Before finalizing, inspect the draft at three scales:

- Sentence: are lengths noticeably varied; does each punctuation mark express a real syntactic relation; are several sentences built from the same template; can abstract nouns become concrete verbs?
- Paragraph: does each have one dominant purpose; do adjacent paragraphs differ naturally in length; are transitions doing real work; is the strongest sentence buried at the end of a weak paragraph?
- Document: can the reader tell what matters without being told "this is important"; is the hierarchy visible but not over-segmented; does the ending resolve the purpose rather than repeat the opening; does the text sound plausible when read aloud?

## Structure and output

Paragraphs are the default unit of developed thought. Use lists only for genuinely list-shaped information: parallel, independently actionable, compared, or sequenced items. Use headings to expose meaningful levels of structure, not one heading per paragraph. Use bold for a small number of high-value anchors.

Return the finished text rather than a running commentary about the edits. Preserve required facts, citations, terminology, names, numbers, and constraints; never trade accuracy for a more natural voice. When multiple forms are possible, prefer the least mannered version that still has a recognizable voice.

## Validation

Run the report-only lint script from this skill's base directory (the directory that contains this SKILL.md). It never rewrites files:

```
node checks/check-prose.mjs <file>
node checks/check-prose.mjs --profile zero-em-dash <file>
```

- Default mode: flags `--` pseudo-dashes and anti-slop patterns. Tags emitted: `pseudo-dash`, `slop:*` (for example `slop:throat-clearing`, `slop:leverag`).
- Profile mode (`--profile zero-em-dash`): additionally flags em-dash characters. Tag emitted: `em-dash`.
- Exemptions in both modes: blockquote lines, fenced code blocks, and inline backtick spans, so quoted and cited text passes verbatim.
- Exit codes: 0 clean, 1 findings, 2 usage error.

A final draft should pass the default mode always, and the profile mode too whenever zero-em-dash is pinned.

## Layer contract

This skill is L0 of the typography stack: the prose-mechanics base layer.

- It loads nothing upward. It never invokes web-typography, dynamic-typography, or any genre skill.
- L1 web-typography and L2 dynamic-typography build on this layer, and genre skills (L3) may pin values over its ranges. Higher-layer pinned values override this skill's defaults: pin over range.
- Other skills chain to it via `skill(name='typographic-writing')`. When so chained, apply this skill's method to the prose handed over and return the tuned text.
