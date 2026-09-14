---
name: web-typography
description: "Engineering floors for typesetting static HTML/CSS: semantic structure, measure, leading, fluid clamp() scales, variable-font axes, font loading, accessibility, i18n. Use when implementing or auditing static web typography, or when chained by a deliverable skill that needs a type-engineering layer beneath its pins. Supplies ranges and mechanics only; visual identity, typeface choice, and design-world decisions belong to the active frontend owner (frontend-ui-ux, /frontend, or impeccable when present), and this skill defers on those questions rather than overriding the owner."
---

# Web Typography (L1 Engineering Floors)

This layer engineers how static text renders in HTML/CSS: hierarchy, measure, leading, scales, font loading, accessibility, language coverage. It supplies floors and working ranges, nothing on the design side. When frontend-ui-ux, /frontend, or impeccable is active, that owner owns the look; this skill defers on identity questions and keeps the engineering side honest. Full uncut source text: `references/web-typography-full.md` in the repo root.

## Layer contract

- This is L1 in a stack: typographic-writing (L0) -> web-typography (L1) -> dynamic-typography (L2) -> genre/deliverable skills (L3).
- This skill defines engineering floors and ranges ONLY.
- A value pinned by a higher layer is MANDATORY where it applies. A genre skill's pinned measure (an exact ch value inside this skill's range) replaces the range outright. Never average, blend, or split the difference between a pin and a range.
- Apply these ranges only to properties no higher layer has pinned.
- Never claim identity or font-choice authority. Asked "which typeface?": route the question to the frontend owner; answer only the mechanical tests a candidate must pass (script coverage, real weights, distinguishable glyphs, license, reliable WOFF2 files).

## Workflow

### 1. Semantic structure first

Before styling, inspect the content model. Prefer elements that express the content:

- `h1`-`h6` for document hierarchy; `p` for paragraphs
- `ul`, `ol`, `dl` for actual lists and term/value structures
- `blockquote`/`q`, `figure`/`figcaption`, `table`/`th`/`td` as the content demands
- `code`, `pre`, `kbd`, `samp` for computational text
- `strong` for importance and `em` for stress, not mere styling

Do not repair an incoherent document outline with CSS. Set document `lang`; it drives pronunciation, hyphenation, and glyph selection.

### 2. Typographic roles before sizes

Name the roles first: display/hero, page title, section heading, body, lead, label, metadata, caption, code, numeric. For each role, decide what contrast it needs against its neighbors. Hierarchy can come from size, weight, width, case, spacing, color, or position; push one or two controls, not all of them. A strong hierarchy usually makes fewer distinctions, not more.

### 3. Measure (floor: 45-75ch)

For continuous Latin-script body text, keep the measure inside **45-75ch**, tuned against typeface, size, leading, language, and content. Dense technical notation may want the roomy end; narrow sidebars the tight end. Never stretch paragraphs across a wide desktop just because the container can grow.

```css
.prose { max-inline-size: var(--measure); } /* set within 45-75ch unless pinned */
```

If a higher layer pins an exact measure, that pin wins and this range is not consulted.

### 4. Leading (floor: 1.45-1.7)

Unitless `line-height` for body text in the **1.45-1.7** zone. Longer lines usually need more leading; darker or larger-bodied faces need more air; headings generally sit tighter than paragraphs. Judge the text block as texture: lines easy to follow without looking disconnected.

```css
:root {
  --leading-body: 1.58;     /* inside 1.45-1.7 unless pinned */
  --leading-heading: 1.08;  /* display tightening is a role decision */
}
body { line-height: var(--leading-body); }
h1, h2, h3 { line-height: var(--leading-heading); }
```

### 5. Fluid scale with clamp()

Use relative units so zoom and resize work. Interpolate within deliberate minimum and maximum sizes:

```css
:root {
  --text-sm: clamp(0.84rem, 0.81rem + 0.12vw, 0.92rem);
  --text-base: clamp(1rem, 0.96rem + 0.18vw, 1.12rem);
  --text-lg: clamp(1.2rem, 1.08rem + 0.5vw, 1.55rem);
  --text-xl: clamp(1.6rem, 1.28rem + 1.25vw, 2.5rem);
}
```

Never make important text depend on viewport units alone: the minimum keeps mobile text usable, the maximum prevents theatrical desktop inflation. Use fewer scale steps than the token system allows.

### 6. Alignment and wrapping

Default to left-aligned ragged-right body text in LTR. Justify only when font, language, hyphenation, measure, and browser behavior were tested together. Do not center sustained reading text. No manual `<br>` for one viewport's wrap; use progressive enhancement:

```css
h1, h2, .display { text-wrap: balance; }
.prose p { text-wrap: pretty; }
```

### 7. Variable fonts

Prefer high-level CSS properties for registered axes:

- `font-weight` for wght
- `font-stretch` for wdth
- `font-style` for italic/slant where supported
- `font-optical-sizing` for opsz (`auto` when the font supports it)

Reserve `font-variation-settings` for custom axes or lower-level control. This skill pins no axis value literals as doctrine: real values come from the identity owner and the font's declared ranges. For changing numeric interfaces, reduce jitter with `font-variant-numeric: tabular-nums`. Never condense or stretch glyphs with CSS transforms to make copy fit: edit the copy, change the measure, use a real width axis, or route the typeface question upward.

### 8. Font loading floors

- Deliver WOFF2; load only the families, scripts, axes, weights, and styles actually used
- Do not hide readable text for seconds while fonts download: set `font-display` deliberately (a common baseline is `swap`)
- Choose fallbacks with similar metrics; where shift remains, apply metric overrides: `size-adjust`, `ascent-override`, `descent-override`, `line-gap-override`

```css
@font-face {
  font-family: "App Sans";
  src: url("/fonts/app-sans.woff2") format("woff2");
  font-weight: 100 900;
  font-style: normal;
  font-display: swap;
}
/* Fallback metric matching lives in a separate @font-face for the
   fallback stack; size-adjust / ascent-override / descent-override /
   line-gap-override values must be derived from the actual pairing. */
```

Do not subset so aggressively that user names, languages, or currency symbols render as missing glyphs. Prefer one capable variable font over many static files when the system genuinely needs the range.

### 9. Reference baseline

```css
:root {
  --font-body: var(--font-identity, system-ui), sans-serif;
  --font-mono: ui-monospace, "SFMono-Regular", Consolas, monospace;
  --measure: 68ch;      /* inside 45-75ch; change or pin per product */
  --leading: 1.58;      /* inside 1.45-1.7; change or pin per product */
}
html { font-family: var(--font-body); font-optical-sizing: auto; }
body { margin: 0; font-size: 1rem; line-height: var(--leading); }
.prose { max-inline-size: var(--measure); }
.prose p { text-wrap: pretty; }
h1, h2, h3 { line-height: 1.08; text-wrap: balance; }
code, pre { font-family: var(--font-mono); }
```

`--font-identity` is the frontend owner's decision; `system-ui` here is only the head of the fallback stack when no identity font is set.

## Accessibility floors

- Text must zoom to at least 200 percent without loss of content or functionality; never disable pinch zoom
- Content must reflow at a 320 CSS px equivalent viewport instead of forcing line-by-line horizontal panning
- Layout must survive user spacing overrides to line, paragraph, letter, and word spacing: no clipped text, no overlapping controls
- Text is real text, not rasterized words; hierarchy is never conveyed by color alone; focus states remain visible

## i18n checklist (condensed)

- CJK line-breaking: test with real CJK samples; check wrapping rules and punctuation handling
- RTL: use logical properties (`max-inline-size`, `margin-inline`, `text-align: start`) so mirroring is mechanical, not a rewrite
- Script-boundary fallback: font stacks must cover the scripts actually displayed; inspect the fallback at each script boundary
- `hyphens: auto` only with correct `lang` metadata and after visual testing
- Beware uppercase transforms on localized text (dotless/dotted i cases); test localized dates, currency, and long compound words

## Validation

Run the embedded risk scanner (path relative to this skill's base directory):

```bash
node checks/check-web-type.mjs <file.css|file.html> [...]
```

It scans CSS files and HTML inline `<style>` blocks, prints `file:line: <tag>`, and reports four risk tags: `px-body-copy` (px/vw font-size on a body-copy-likely selector with no rem counterpart), `zoom-lock` (viewport meta disabling user zoom), `fvs-out-of-range` (font-variation-settings numeric axis outside 0-1000), `motion-no-reduced-motion` (transition on a type property with no prefers-reduced-motion guard). Exit codes: 0 clean, 1 findings, 2 usage error.

Then test the rendered page, not just the stylesheet: 200 percent zoom, 320px reflow, fallback appearance before the webfont arrives, spacing-override survival, CJK and RTL samples where relevant.

## Anti-patterns (condensed)

- Five typefaces where two roles would suffice; tiny body copy compensated by line-height
- Full-width desktop paragraphs; letterspaced lowercase body text
- Faux bold or faux italic when real styles exist; transforms deforming text to fit
- Manual line breaks tuned to one screen width; centered multi-paragraph reading text
- Narrow justified columns without tested hyphenation; rivers of word-space
- Many static font files where one variable font serves the system; content hidden while a font loads

## Output contract

When implementing, return or modify semantic HTML and CSS rather than describing intended typography. When auditing, prioritize fixes in this order: semantics and comprehension, accessibility, rhythm, font loading and stability, expressive polish. Route identity and typeface questions to the active frontend owner.
