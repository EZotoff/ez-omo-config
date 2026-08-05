---
patch_id: "omo--glm-preemptive-compaction-threshold"
dependency: "oh-my-openagent"
target_file: "packages/omo-opencode/src/hooks/preemptive-compaction-trigger.ts"
target_install_path: "/home/ezotoff/oh-my-openagent-v4.19.2"
status: "deprecated"
deprecated_date: "2026-08-05"
deprecated_reason: "The GLM 5.1 mid-window context-degradation problem this patch addressed (quality drop past ~100K tokens on a 200K window, per OpenCode issues #17981 and #15778) does not occur on GLM 5.2 with its 1M context window. All agent roles now standardize on glm-5.2 (sisyphus, sisyphus-junior, atlas, metis, frontend-ui-ux-engineer). Additionally, OMO preemptive_compaction is disabled at the config level (experimental.preemptive_compaction=false) precisely because it triggers prematurely on 1M-context models; the patch's 0.45 threshold would compound that premature triggering if the subsystem were re-enabled."
applied_date: "2026-04-10"
dep_version: "4.19.2"
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

No longer needed. The GLM 5.1 degradation problem this patch worked around (significant quality drop at ~100K tokens, 50% of its 200K context) does not occur on GLM 5.2, which has a 1M context window and no analogous mid-window degradation. The stack now standardizes on glm-5.2 across all agent roles that previously used GLM models.

Additionally, OMO preemptive compaction is disabled at the config level (`experimental.preemptive_compaction=false`) because it triggers prematurely on 1M-context models. Re-enabling the subsystem with this patch's lowered 0.45 threshold would compound the premature-trigger problem rather than solve it.

If a future GLM model reintroduces mid-window degradation, the patch source remains in the OMO fork at `/home/ezotoff/oh-my-openagent-v4.19.2` and can be re-applied against the specific affected model.
Status: not-applicable
