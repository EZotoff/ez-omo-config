---
name: closeout
description: "Standalone, idempotent episode closeout. Mandatory-referenced by every terminal path (Atlas post-F-wave, in-session completion, lite completion). Inputs: episode manifest + linked artifacts + receipts ONLY (bounded session_evidence refs: message IDs + immutable excerpts; never full transcripts). Outputs: problem/intent restatement, per-phase work recap, learnings TLDR, next steps (potential vs mandatory follow_ups), and a terminal receipt closeout.status: complete|degraded|failed."
---

# Closeout — Episode Terminal Summary (Standalone, Idempotent)

<role>
You are the closeout writer for an episode. You read the episode manifest, its receipts, and the artifacts they link — nothing else. You produce a reader-first terminal summary and a status receipt. You never invent recap, never re-interpret transcripts, and never fabricate evidence. Re-running closeout on the same episode produces the same receipt with no duplicate artifacts.
</role>

---

## Invocation Paths

Every terminal path MUST invoke this skill (it references and enforces closeout; start-work does not own it):

- **Atlas post-F-wave** — after the last F-box verdict is recorded in the plan's `## Execution Record`.
- **In-session completion** — when a lane finishes outside Atlas (e.g. `/episode checkpoint` lanes).
- **Lite completion** — `--lite` lanes at teardown-receipt time.

## Inputs (bounded — read NOTHING else)

1. **Episode manifest**: `.omo/episodes/<slug>/manifest.yaml` (schema v0.2: `phases[]` with append-only sequence-numbered receipts, `learnings[]`, `follow_ups[]`).
2. **Linked artifacts** referenced by receipts (plan doc, `.reviews.md` ledger, evidence files).
3. **Receipts** — including bounded `session_evidence` refs: message IDs + immutable excerpts.

**NEVER read full session transcripts.** If a receipt's `session_evidence` is missing or unresolvable, that is a degraded-path input, not an invitation to go look.

## Procedure

1. **Verify receipts first**: run `scripts/episode-receipt.sh verify` (from the episode's project root) against the manifest. Closeout consumes validated receipts only. Record the exit code.
2. **Read** the manifest, receipts, and linked artifacts listed above.
3. **Write the closeout** to `.omo/episodes/<slug>/closeout.md` with the four output sections below.
4. **Emit the terminal receipt** as the final line block of `closeout.md` and (when the lane supports it) append a closeout receipt to the manifest via `scripts/episode-receipt.sh append`.
5. **Disposition learnings** (from `learnings[]`): mark each selected entry `promoted` (evidence + owner/scope → hand to `wisdom-write`), `duplicate`, or `discarded`. Unselected entries stay ephemeral — no diary.

## Output Sections (all four required, in order)

1. **Problem + intent restatement** — what problem the episode set out to solve, in plain language, sourced from the manifest's `intent` field.
2. **Work recap per phase** — one block per manifest phase, derived strictly from that phase's receipts. A phase without receipts gets the literal line "no receipts recorded" — never a reconstructed narrative.
3. **Learnings TLDR** — plain-language distillation of dispositioned `learnings[]` entries.
4. **Next steps** — two lists:
   - *Potential*: optional follow-on work, each item a single actionable sentence.
   - *Mandatory*: material gaps that MUST be carried forward. These are appended to the manifest's `follow_ups[]` with stable dedupe IDs (`fu-<slug>-<n>`) so the Supervisor can consume them without duplicates.

## Terminal Receipt

```
closeout.status: complete|degraded|failed
```

- **complete** — all phases have verified receipts; recap is fully sourced.
- **degraded** — one or more receipts are `verified: false`, missing, or evidence files fail digest match. Requirements:
  - The **opening summary** (first paragraph of `closeout.md`) MUST carry a visible flag: `⚠ DEGRADED: <one-line reason>`.
  - A **diagnostics list** names each unverified receipt and the specific gap (missing file, digest mismatch, missing checkpoint).
  - **Mandatory follow_ups** are emitted for every material gap.
  - Recap covers only what receipts support; unsupported phases are named as gaps — no silent loss, no invented recap.
- **failed** — the manifest itself is missing, unreadable, or has no verified receipts at all. State this plainly; do not produce a recap.

Fallback path: unverified receipts → degraded (never silently dropped, never "fixed" by reinterpreting the transcript).

## Idempotency Rules

- Re-running closeout overwrites `closeout.md` wholesale (same inputs → same sections → same status). It never appends duplicate sections.
- `follow_ups[]` appends use the dedupe ID — a re-run adds no duplicates.
- Dispositions (`promoted`/`duplicate`/`discarded`) are re-derived from the same `learnings[]`; re-running must not re-promote an already-promoted entry.

## Hard Prohibitions

- Never read session transcripts to "fill in" recap.
- Never mark `complete` with any unverified receipt present.
- Never invent a learning, a follow-up, or a phase outcome not backed by a receipt.
- Never claim runtime/live evidence states the receipts do not carry.
