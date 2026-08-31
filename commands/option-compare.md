---
description: Compare options — draft each independently, then judge them against each other
---

Run an option-comparison review. Input: the decision to make and the candidate options (or ask the operator to enumerate them first).

Stage 1 — DRAFT EACH: for each option, one `oracle` agent drafts the best honest case for that option — including its costs and failure modes — WITHOUT seeing the other options' drafts (independence is the point; brief each agent only on its own option and the shared context).

Stage 2 — JUDGE: a judge agent (different model family from the drafters if available) sees all drafts and ranks them with explicit criteria and weights, stating what evidence would change the ranking.

Stage 3 — ADVERSARIAL CHECK: one challenger agent attacks the judge's ranking — where is it pattern-matching rather than arguing?

Synthesize: ranking with confidence levels, the strongest argument for and against the top pick, and what evidence would flip the decision.

Boundary: analysis, not authorization — the ranking informs the operator's pick; nothing is selected or dispatched without them.
