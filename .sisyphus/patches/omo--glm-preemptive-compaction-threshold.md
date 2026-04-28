---
patch_id: "omo--glm-preemptive-compaction-threshold"
dependency: "oh-my-openagent"
target_file: "src/hooks/preemptive-compaction.ts"
target_install_path: "/home/ezotoff/omo-hub/projects/oh-my-openagent"
status: "active"
applied_date: "2026-04-10"
dep_version: "current"
upstream_issue: "none"
verification_pattern: "GLM_PREEMPTIVE_COMPACTION_THRESHOLD"
---

# GLM-Specific Preemptive Compaction Threshold

## Problem
The preemptive compaction hook used a single threshold of `0.78` (78%) for all models. For GLM-5.1 with a 200K context window, this means compaction only triggers at ~156K tokens. However, GLM models degrade significantly at ~100K tokens (50% of context) due to Z.AI infrastructure issues (confirmed in OpenCode issues #17981 and #15778). By the time compaction fires at 156K, the model is already producing minimal/empty responses and stuck in a continuation loop.

## Patch Description
Added a GLM-specific compaction threshold of `0.45` (45% = ~90K tokens for a 200K context). Uses the existing `isGlmModel()` utility from `src/agents/types.ts`.

Before: single `PREEMPTIVE_COMPACTION_THRESHOLD = 0.78` for all models.
After: `GLM_PREEMPTIVE_COMPACTION_THRESHOLD = 0.45` for GLM models, `0.78` for everything else.

```typescript
const threshold = isGlmModel(cached.modelID)
  ? GLM_PREEMPTIVE_COMPACTION_THRESHOLD
  : PREEMPTIVE_COMPACTION_THRESHOLD
```

## Verification
```bash
grep -n "GLM_PREEMPTIVE_COMPACTION_THRESHOLD" /home/ezotoff/omo-hub/projects/oh-my-openagent/src/hooks/preemptive-compaction-trigger.ts && echo "APPLIED" || echo "STALE"
```
Expected: Two matches — constant declaration and usage.

## Reapply Instructions
1. Add import at top of `preemptive-compaction-trigger.ts`: `import { isGlmModel } from "../agents/types"`
2. Add constant after `PREEMPTIVE_COMPACTION_THRESHOLD`: `const GLM_PREEMPTIVE_COMPACTION_THRESHOLD = 0.45`
3. In `runPreemptiveCompactionIfNeeded`, replace the single threshold check:
   ```typescript
   // Before:
   if (usageRatio < PREEMPTIVE_COMPACTION_THRESHOLD || !cached.modelID) return
   // After:
   const threshold = isGlmModel(cached.modelID)
     ? GLM_PREEMPTIVE_COMPACTION_THRESHOLD
     : PREEMPTIVE_COMPACTION_THRESHOLD
   if (usageRatio < threshold || !cached.modelID) return
   ```

## Durable Alternative
Upstream to oh-my-openagent repository via PR. Could also be made configurable per-provider in the OMO config schema rather than hardcoded.
Status: not-yet-pursued
