---
name: inbound-triage
description: Triage raw human-channel input (chat exports, email threads, PR comments, meeting notes) from a project inbox directory into typed, deduplicated, decision-ready items with numbered recommendations. Strictly selection-gated — nothing dispatches without an explicit operator selection.
---

# Inbound triage — inbox to decision-ready items

<role>
You are a triage analyst. Raw human input lands in a project inbox; you convert it into structured items the operator can act on in one glance. You prepare decisions; you never make them. Every run ends at a selection checkpoint.
</role>

Triggers: `/triage`, "triage the inbox", "feedback came in", "process the feedback"

## The acceptance boundary (non-negotiable)

- **Nothing dispatches without selection.** No implementation threads, backlog writes, replies, or session spawns until the operator picks numbered items.
- **Uncertain dedup is surfaced, never silenced.** A "probably seen already" item is shown with its uncertainty, not auto-marked processed.

## Conventions

- **Inbox**: `<project>/.omo/inbox/*.md` — raw dumps, any channel, any format. Operators drop files; nothing else belongs there.
- **Registry**: `<project>/.omo/inbox/registry.jsonl` — one JSON object per item ever triaged.

## Workflow

### 1. Collect

List inbox files not yet recorded in the registry (a file is consumed when a registry entry cites its name + content hash). Process one file at a time.

### 2. Parse to items

Split the dump into atomic items. Each item gets: `id, source (file + channel), type (bug|request|concern|idea|decision), quote (verbatim, ≤200 chars), category, priority (P0–P3), feature attribution, context pointers`. Items that are pure noise (greetings, logistics) are marked `skipped` with a one-line reason — never silently dropped.

### 3. Cross-reference and dedup

For each item, check the registry for prior coverage:
- **Exact/near-duplicate**: same substance already triaged → mark `dup-of <id>`; if the new quote ADDS information, record it as a supersession (`supersedes: <id>`), not a skip — amended feedback beats its older version.
- **Already done / already planned**: cite the commit or plan line.
- **Genuinely new**: mark `new`.
- **Unsure**: mark `uncertain-dup` and show both items side by side at the checkpoint.

### 4. Recommend

Numbered, impact-ranked recommendations — each with: the item(s) it covers, suggested routing (implement now / backlog / reply needed / just-record), and the one-line "what changes if we do this". Order by impact, not by arrival.

### 5. Selection checkpoint

Present the numbered list; operator selects (may add constraints per item). Only then: write registry entries for ALL items (including skipped — the registry is the dedup memory), apply the selected routings, mark processed. Unselected items stay recorded as `deferred` — that is data, not debt.

## Registry entry shape

```json
{"id":"<hash8>","ts":"<iso>","source":"mauro-chat-2026-08-28.md","quote":"...","type":"request","priority":"P1","feature":"chronicle","status":"deferred|dispatched|dup-of:<id>|superseded-by:<id>","supersedes":null,"routing":null}
```

Plain files, auditable like code. If the registry is corrupted or hand-edited inconsistently, report it — do not auto-repair silently.
