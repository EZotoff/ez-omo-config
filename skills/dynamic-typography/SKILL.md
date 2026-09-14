---
name: dynamic-typography
description: "L2 mechanics for type in motion: variable-font axis animation, kinetic text, per-letter effects, scroll- and pointer-linked type, and typographic state transitions. Fires on implementing or auditing type-specific motion, or when chained from a higher layer. Ownership of motion budgets, timing doctrine, and effect-count policy belongs to genre skills and frontend owners; this skill defers to those budgets and supplies mechanics within them. Requires a working static composition, reduced-motion parity, accessible names, and layout stability."
---

# Dynamic Typography (L2: Motion Mechanics)

Use when typography changes over time or in response to input, state, viewport, scroll, or pointer. Motion must communicate something the reader benefits from; spectacle is not a job. Concentrate dynamic behavior in headings, navigation labels, controls, status text, metrics, and display type; keep reading text stable while it is being read.

## Entry condition

Verify the interface works as a static typographic composition before adding motion. If hierarchy, measure, contrast, semantics, or copy are weak, fix them first: animation is a multiplier and amplifies confusion with the same efficiency as clarity.

## What type motion may communicate

A typographic change should serve at least one job:

1. state: hover, focus, selected, active, loading, success, error
2. hierarchy: direct attention or signal a change in importance
3. continuity: show one typographic object becoming another
4. progress: encode a bounded process or data change
5. navigation: tell the reader where they are or where an interaction leads
6. responsive adaptation: fit width, optical size, weight, or spacing to the space
7. expressive delight: character, only after functional needs are met

If an effect does none of these, challenge whether it belongs. When motion encodes data (severity, intensity), typography must not be the sole channel: pair it with the numeric value, a label, or a color-independent marker.

## Effect-family selection ladder

Prefer the least disruptive mechanism that communicates the change. Perceptual cost, lowest to highest:

1. color or decoration change
2. grade or subtle weight change
3. style or slant change
4. width or tracking change
5. scale or position change (transform)
6. per-letter transforms
7. continuous or scroll-driven kinetic composition

Do not start at rung 7 because the font file makes it possible. Match the family to the job before choosing a library:

- Axis modulation: animate weight, grade, width, slant, optical size, or custom axes for state, emphasis, and responsive fit.
- Reveal and occlusion: clip, mask, or translate a wrapper while the real text stays in the DOM; entrances and disclosure that never delay essential information.
- Object motion: move whole words, lines, or headings with transforms; preserve identity across UI states (View Transitions as progressive enhancement, with a correct semantic source and destination).
- Timeline-driven: bind a bounded change to scroll or view timelines; native scroll-driven animation is enhancement, not baseline, and a JS fallback must not recreate motion the user asked to reduce.
- Scripted orchestration: WAAPI or a dedicated library only when several text objects must coordinate, interrupt, reverse, or track live input; do not import a large dependency for a single hover transition CSS already handles.

## Variable-font axis strategy

Never assume an axis exists. Inspect the font's declared axes and their min/default/max values (the fvar table, a font inspection tool, or the foundry's documentation) before writing any value, and gate the enhancement on support:

```css
@supports (font-variation-settings: normal) {
  /* variable-font enhancement */
}
```

Prefer mapped CSS properties for registered axes: font-weight (wght), font-stretch (wdth), font-style (slnt or italic), font-optical-sizing (opsz). Reserve font-variation-settings for custom axes or cases that need low-level control. Never copy axis values between fonts; a meaningful value in one family may be invalid in another.

Metric risk, safest first for inline contexts:

- Grade (GRAD): shifts darkness with less advance-width impact than weight; usually the first choice for interactive emphasis. Verify per font; metric stability is a design property, not a guarantee.
- Weight (wght): familiar and expressive; glyph widths can shift and nudge neighboring content.
- Width (wdth): changes measure directly and triggers reflow; reserve for display text or containers with reserved space.
- Optical size (opsz): should follow rendered size automatically; do not animate it for spectacle.
- Slant or italic: signals attitude, direction, or state; repeated oscillation becomes noise quickly.
- Custom axes: powerful, but name and document the perceptual change each one produces.

## Reduced motion first

Respect prefers-reduced-motion from the first commit, not as cleanup. Reduced mode removes interpolation while keeping final states, replaces spatial movement with instant or opacity changes, freezes decorative axis animation at readable defaults, and drops scroll- and pointer-linked motion entirely. The final visual state must remain understandable without the interpolation.

CSS covers the interpolation side:

```css
@media (prefers-reduced-motion: reduce) {
  .action-label { transition: none; }
}
```

CSS alone is not enough when JavaScript keeps computing and writing motion states; disable the logic too, and follow the preference if it changes mid-session:

```js
const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)');
if (!reduceMotion.matches) enableTypographicInteraction();
reduceMotion.addEventListener('change', (e) => {
  e.matches ? disableTypographicInteraction() : enableTypographicInteraction();
});
```

Never replace focus indication with motion, and never let animation be the only indication of state. A weight change on focus does not remove the obligation for a visible focus ring.

## Per-letter splitting and accessibility

Splitting text into spans creates expressive effects but damages semantics when done carelessly. Rules:

- preserve the original accessible name; the semantic text node stays in the DOM
- never force screen readers to announce one character at a time
- segment by grapheme cluster, not UTF-16 code unit; combining marks and emoji sequences must not split
- keep copy, selection, and whitespace behavior reasonable
- do not animate text into an order different from DOM order when the visual sequence carries meaning

Use Intl.Segmenter for grapheme-safe splitting:

```js
const segmenter = new Intl.Segmenter(lang, { granularity: 'grapheme' });
const graphemes = [...segmenter.segment(text)].map((s) => s.segment);
```

For heavily processed copies (scramble, glitch, outline, shadow, particles) use the decorative duplicate pattern: keep one stable semantic text node and render the animated layer separately with aria-hidden="true". The effect must never become the only readable copy. Prefer CSS pseudo-elements when they can produce the effect without DOM splitting at all.

## Layout stability

An axis animation that makes surrounding copy jump is a failed interaction. To keep motion from causing reflow:

- prefer metric-stable axes in inline contexts (grade over weight over width)
- reserve inline and block space for changing display text
- keep width-axis changes inside isolated display compositions
- avoid animating font-size in dense interfaces when a transform or non-geometric axis communicates the same state
- buttons must not change width on hover
- prefer CSS transforms over repeated layout-property writes for whole-object movement
- use tabular numerals for rapidly updating numbers to prevent horizontal jitter
- test the longest localized strings, not only the English demo copy

Do not hide essential text until a scroll trigger fires: keyboard, anchor-link, search, zoom, and reduced-motion users bypass choreography. Reveals enhance arrival; they never gate access.

## Performance budget

Measure the real page on representative devices; a smooth workstation is not evidence of smooth user hardware. Limit simultaneously animated text nodes, active axes, animated string length, JavaScript style-write frequency, expensive filters combined with type animation, and off-screen animation.

For continuous inputs (scroll, pointer): normalize and clamp the input to a bounded range, smooth noisy samples, update at most once per animation frame, and stop work when the element leaves the viewport. Pointer effects must tolerate touch, keyboard, and no-pointer environments, and must never carry required information or make characters flee the pointer on interactive controls.

Prefer CSS transitions for discrete state changes; use JavaScript only for genuinely continuous interaction or coordination CSS cannot express cleanly. Do not animate every telemetry tick: aggregate, debounce, or transition only meaningful state changes.

## Validation matrix

Test each effect at least against:

| Condition | Verify |
| --- | --- |
| Keyboard | focus state visible, stable, equivalent to hover |
| Touch | no functionality lost without hover |
| Reduced motion | continuous motion removed or replaced; final states intact |
| Zoom | type stays readable; controls do not clip |
| Slow device | interaction stays responsive |
| Font failure | fallback remains usable |
| Long localization | no collisions, no hover-induced reflow |
| Screen reader | text and accessible names stay coherent |
| Animation fully off | content and state still understandable |

## Layer contract

This is the motion-mechanics layer: floors, ranges, and patterns only. Authority stays upstream.

- Pinned values from higher layers (genre skills, frontend owners) are mandatory and never averaged with the ranges here.
- These ranges apply only to properties the higher layer left unpinned.
- Policies for motion budgets, timing doctrine, and effect-count live in L3 genre skills and with the frontend owner; when they pin an effect count, a timing ceiling, or an easing family, that pin wins.
- Reader-report's one-earned-moment budget is a pin this skill obeys: mechanics here serve that authored moment, and unearned effects stay static.
- Timing doctrine is deliberately absent from this file; ask the active genre skill or frontend owner for durations and easing.
