---
description: Dual-track review — functional correctness and design quality in parallel, then merge findings
---

Run a two-lane review of the work at hand (document, design, or implementation):

Lane 1 — FUNCTIONAL (`oracle`): does it do what it claims? Requirements coverage, correctness, edge cases, evidence for every claimed behavior.

Lane 2 — DESIGN (`artistry` or best available design-oriented agent): is it good? Coherence, ergonomics, maintainability, whether the shape of the solution fits the shape of the problem.

Run the lanes in parallel; each sees the artifact but not the other lane's brief. Then merge: findings from both lanes in one list, tagged by lane; conflicts between the lanes stated explicitly (e.g., functional wants X, design wants not-X) — those conflicts are often the most valuable output; do not resolve them silently.

Boundary: review, not authorization — findings inform the operator's next move; nothing is applied or dispatched without them.
