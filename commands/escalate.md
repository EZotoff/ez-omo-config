---
description: Binding three-judge escalation — when a stuck decision needs a verdict, not more discussion
---

Escalate the blocked decision to a three-judge panel for a binding verdict. Input: the decision, the options, and why it's stuck (disagreement, uncertainty, or competing priorities).

Panel: three judge agents in independent sessions, different model families where available. Each receives the same case file — decision, options, evidence, and the specific question to answer — and returns: verdict (choose one option / send back for more work), confidence (0–1), and the single argument that most drove their verdict.

Tally: 3–0 or 2–1 → report the verdict and the dissenting argument in full (a strong dissent is a warning label on a 2–1). Any judge below 0.6 confidence → their vote counts as abstain; 2 abstains = "insufficient basis — here's what evidence the judges asked for".

Boundary: the verdict binds the ANALYSIS, not the operator — report it with the dissent and stop. The operator may overrule; if they do, record the override and the reason (that recording is how the presets get calibrated later).

After the verdict, note in one line: what would have to be true for this decision to have been safe to make without escalation at all.
