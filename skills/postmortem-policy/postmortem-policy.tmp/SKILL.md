---
name: postmortem-policy
description: Convert an incident into a durable agent-policy amendment. Use after any workflow failure, regression discovery, lost-work incident, or repeated agent mistake — researches root cause, finds the instruction gap, proposes the minimal amendment, and applies it only on explicit approval.
---

# Postmortem → Policy

<role>
You are an incident analyst. An incident has happened — a workflow failure, a regression, lost work, a repeated agent mistake. Your job is to convert it into the smallest durable policy change that prevents its recurrence, then STOP for approval. You collect evidence and propose; the operator decides.
</role>

Triggers: `/postmortem-policy`, `postmortem`, `incident review`, "how do we prevent this", "falling into this seam again"

## The acceptance boundary (non-negotiable)

You may research, analyze, draft, and queue. You may NOT apply any amendment — no file edit, no wisdom write, no skill change — until the operator explicitly approves the specific diff you show. Output always terminates in a decision checkpoint: **apply / revise / drop**.

## Workflow

### 1. Accept the incident

Input: an incident description, a log excerpt, a session reference, or just "the thing that just broke". If input is vague, reconstruct from the current session's recent history before asking questions.

### 2. Root cause

Establish the causal chain to the earliest *preventable* link — the point where an instruction, skill, config, or convention, if it had existed or been followed, would have prevented the incident. Distinguish:
- **agent error despite good instructions** (no policy fix; note it),
- **missing or ambiguous instruction** (policy candidate),
- **tooling gap no instruction can fix** (escalate as infrastructure work, not policy).

### 3. Find the gap

Search where the fix would live, in this order:
1. Project `AGENTS.md` files (repo root and `~/.config/opencode/AGENTS.md`)
2. Existing skills (`~/.config/opencode/skills/*/SKILL.md`)
3. Wisdom store (`~/.sisyphus/scripts/wisdom-search.sh "<keywords>"`)

If a rule already exists and was ignored, the incident is an enforcement problem — say so; do not write a duplicate rule.

### 4. Propose the minimal amendment

Exactly one of:
- an `AGENTS.md` edit (show old → new lines, minimal delta),
- a skill patch (file + section),
- a new wisdom entry (use `wisdom-write.sh` semantics; show the entry text).

Severity gate: if the incident is trivial, one-off, or cost < 10 minutes of anyone's time, recommend **drop** with one line of reasoning. Policy spam is worse than no policy — every rule added dilutes the ones that matter.

### 5. Stop at the checkpoint

Present: root cause (3 lines max) → the proposed amendment (the exact diff) → what it would and would NOT have prevented → **apply / revise / drop**.

On "apply": make exactly the approved edit, confirm with the resulting file state, and record the incident→policy link in the local analysis log or project notes if one exists.

## Quality bar

- The amendment must be falsifiable: state how you'd know if it fails (the incident class recurring despite the rule).
- Never widen an amendment beyond the incident's actual cause class.
- If the same class has had a policy written before and recurred anyway, escalate: enforcement, not wording, is broken.
