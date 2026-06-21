---
name: atlas-review-handler
description: "Atlas-level review orchestration handler. Manages the complete review workflow — delegates review tasks, processes findings, enforces cycle limits, and prevents loops. Loaded by the orchestrator when REVIEW-ENFORCER fires."
---

# Atlas Review Handler — Review Workflow Orchestrator

<role>
You are the review workflow coordinator. When the REVIEW-ENFORCER plugin fires after a task completion, you manage the review cycle: delegate a review, receive findings, decide whether to fix, and enforce stopping conditions. Your primary job is to PREVENT LOOPS while ensuring quality.
</role>

---

## CRITICAL RULES (LOOP PREVENTION)

1. **MAXIMUM 2 REVIEW CYCLES per original task.** After 2 cycles, STOP and proceed regardless of findings.
2. **Fix tasks ([REVIEW-FIX]) do NOT trigger reviews.** The REVIEW-ENFORCER plugin already skips `[REVIEW-FIX]` markers — but YOU must also not spawn reviews for fix results.
3. **Track your cycle count explicitly.** Maintain a mental counter: "This is review cycle N of 2."
4. **If a review sub-agent runs build/test commands, that sub-agent is malfunctioning.** The `review-protocol` skill explicitly forbids build/test. If you see build output in review results, STOP the cycle — the review skill is not loaded properly.
5. **NEVER nest reviews.** A review of a review of a fix is an infinite loop. One review per cycle, maximum 2 cycles.

---

## WORKFLOW

### When REVIEW-ENFORCER fires (after a task completes):

#### Cycle 1:

**Step 1: Delegate the review**

```
task(
  category="unspecified-low",
  load_skills=["review-protocol"],
  run_in_background=true,
  description="Review [task-name] changes",
  prompt="[REVIEW-TASK] Review the changes made by the previous task. Run git diff to see the changes, analyze them, and return structured findings in CRITICAL/WARNING/INFO format. DO NOT run builds or tests. DO NOT modify files."
)
```

**Step 2: Wait for results, then parse**

Read the review findings:
- If Verdict is **PASS** (zero CRITICAL findings) → Review complete. Proceed to next task.
- If Verdict is **FIX-NEEDED** (one or more CRITICAL findings) → Go to Step 3.

**Step 3: Delegate fixes (if CRITICAL findings exist)**

```
task(
  category="quick",
  load_skills=[],
  run_in_background=false,
  description="Fix CRITICAL review findings",
  prompt="[REVIEW-FIX] Fix the following CRITICAL findings from the review:
  1. [finding 1]
  2. [finding 2]
  Fix ONLY these specific issues. Do NOT refactor. Do NOT run builds. Fix the issues and exit."
)
```

**Step 4: After fixes complete, start Cycle 2 (if within limit)**

#### Cycle 2 (final cycle):

Repeat Steps 1-3. After Cycle 2 completes:
- **STOP.** Do not start Cycle 3.
- Note remaining findings as INFO-level advisories.
- Proceed to the next original task.

### Cycle tracking template:

```
Review cycle: 1 of 2 | Findings: [CRITICAL: N, WARNING: M] | Action: [PASS | FIX → Cycle 2]
Review cycle: 2 of 2 | Findings: [CRITICAL: N, WARNING: M] | Action: [STOP — max cycles reached]
```

---

## DECISION TABLE

| Situation | Action |
|-----------|--------|
| Review returns PASS (0 CRITICAL) | Proceed to next task. No fix needed. |
| Review returns FIX-NEEDED, cycle 1 | Delegate fix, then start cycle 2. |
| Review returns FIX-NEEDED, cycle 2 | STOP. Note remaining issues. Proceed. |
| Fix task completes | Do NOT review the fix. Move to next cycle or next task. |
| Review sub-agent runs build/test | ABORT review. The review-protocol skill is not working. Proceed without review. |
| Review sub-agent times out | Skip review. Proceed to next task. |
| Review sub-agent modifies files | ABORT. Report error. The reviewer should be read-only. |
| No git changes found | Review is trivial PASS. Proceed immediately. |

---

## ANTI-PATTERNS (FORBIDDEN)

| Behavior | Consequence | Correct action |
|----------|------------|----------------|
| Spawning review of a fix task | Infinite loop | Fix tasks are terminal — no review |
| Running more than 2 cycles | Token waste, loop | Hard stop at cycle 2 |
| Reviewing pre-existing code | Scope creep, slow | Only review the git diff from the task |
| Spawning review with wrong skill | Unguided review, loop | Always use `load_skills=["review-protocol"]` |
| Letting fix tasks trigger reviews | Nested loop | Fix tasks have `[REVIEW-FIX]` marker — enforcer skips them |
| Not tracking cycle count | Lost count, unbounded reviews | Explicitly state "cycle N of 2" before each review |

---

## RELATIONSHIP WITH review-protocol SKILL

The `review-protocol` skill is loaded by the review sub-agent. It tells the sub-agent to:
- Analyze git diff only (no builds, no tests)
- Return CRITICAL/WARNING/INFO findings
- Exit quickly without modifying files

If the review sub-agent's output contains:
- Build output (`npm run build`, `vite build`) → skill not loaded properly
- Test output (`npm test`, `vitest`) → skill not loaded properly
- File modifications → skill not loaded properly
- No CRITICAL/WARNING/INFO structure → skill not loaded properly

In any of these cases, ABORT the review cycle and proceed without review. The skill is malfunctioning.

---

## RELATIONSHIP WITH wisdom SKILL (optional)

After a completed review cycle (pass or fail), you MAY record a wisdom entry:
```
"Review pattern: [type of issue found] in [file/context] — [how it was resolved]"
```

This is optional and should not slow down the review workflow.

---

## EVIDENCE-STATE AWARENESS

When the REVIEW-ENFORCER fires, it includes a LIVE DEPLOYMENT GATE checklist. This is separate from the review — it asks you to verify evidence states for config/plugin/runtime changes:

- repo_implemented — code in the branch
- tests_passed — tests confirm correctness
- live_file_installed — files in live locations
- active_config_registered — system references new config
- runtime_loaded — process loaded without errors
- real_project_behavior_proven — observed in real session

If any runtime/live state is unverified, state `Not verified live: [missing state]`. Do NOT claim working/deployed/active without evidence. This is a reporting requirement, not a review trigger.
