---
patch_id: "omo--family-reasoning-efforts"
dependency: "oh-my-openagent"
target_file: "packages/model-core/src/model-capability-heuristics.ts"
target_install_path: "/home/ezotoff/oh-my-openagent-v4.19.2"
status: "active"
applied_date: "2026-09-15"
dep_version: "4.19.2"
upstream_issue: "none"
verification_pattern: "reasoningEfforts: \\[\"low\", \"medium\", \"high\", \"max\"\\]"
runtime_effective: true
note: "Dist-level patch (applied directly to dist/index.js; source tree NOT yet patched — port to packages/model-core/src/model-capability-heuristics.ts before the next fork rebuild or the fix is lost). runtime_effective: true since 2026-09-15 14:04:57Z — wire capture showed reasoning_effort:low on a clamped zai glm-5.3-flash resume turn (proxy capture, /tmp/opencode test rig)."
---

# Model-Family Reasoning-Effort Tables (glm / deepseek / kimi)

## Problem

OMO's `chat.params` reconciliation (`createChatParamsHandler` → `resolveCompatibleModelSettings` → `resolveField`) validates every `options.reasoningEffort` against per-family capability tables in `packages/model-core/src/model-capability-heuristics.ts`:

- **glm family** declares `variants` but NO `reasoningEfforts` → `resolveField("low", undefined, ..., familyKnown=true, ...)` returns `{ value: undefined, reason: "unsupported-by-model-family" }` → the handler executes `delete output.options.reasoningEffort`. Every `reasoning_effort` — plugin clamps AND OpenCode variant-derived values (e.g. sisyphus `high`) — was silently deleted for all GLM models. Verified by wire capture 2026-09-15 13:31Z: clamp logged (`reasoningEffort=low`), request body carried no `reasoning_effort`.
- **deepseek family** declared `reasoningEfforts: ["high","max"]` with aliases `low→high, medium→high` → a `low` clamp was INVERTED to `high` on the wire.
- **kimi family** declared no `reasoningEfforts` → same delete as glm (k3 clamps never reached the wire; K2.7 only worked because the opencode-kimi-full plugin smuggles effort via the `x-opencode-kimi-reasoning-effort` header, bypassing options).

This stacked on top of the output-shaper vocabulary bug (snake_case `reasoning_effort` dropped by the `@ai-sdk/openai-compatible` Zod schema — see `configs/opencode/output-shaper/model-gating.mjs` and docs/history/incidents.md) and made ALL post-2026-08-07 reasoning-effort dialing on zai/deepseek/kimi a no-op.

## Patch Description

Dist-level edit of the three family entries in `dist/index.js` (source equivalent: `packages/model-core/src/model-capability-heuristics.ts`):

1. `glm`: add `reasoningEfforts: ["low", "medium", "high", "max"]`.
2. `deepseek`: `reasoningEfforts: ["low", "medium", "high", "max"]`; drop the `low→high` and `medium→high` aliases (keep `xhigh→max`).
3. `kimi`: add `reasoningEfforts: ["low", "medium", "high", "max"]`.

Values verified against live endpoints 2026-09-15 (`/tmp/opencode` A/B harness):
- z.ai coding-plan glm-5.3/glm-5.3-flash: body `reasoning_effort:"low"` cuts reasoning 106–172 tok → 0.
- ollama.com/v1 deepseek-v4-pro:0813: `low` ≈ halves reasoning; api.deepseek.com deepseek-flash accepts `low`.
- Kimi K2.7/K3 accept `reasoning_effort` (K3 variants low/high/max; `medium` 400s — `medium` is listed for K2.7 compatibility but the resume clamp only ever sends `low`).

Effect: `reasoningEffort` values within the declared ladders now pass OMO reconciliation untouched (clamped `low` reaches the wire; variant `high` reaches the wire); out-of-range values still reconcile (e.g. `xhigh→max` on deepseek).

## Verification

```bash
# Dist patch present (three family entries):
grep -c 'reasoningEfforts: \["low", "medium", "high", "max"\]' /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js   # 3 (glm, deepseek, kimi)
grep -c 'low: "high"' /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js   # 0 (alias removed from deepseek)
# Module still parses/imports:
cd /tmp && bun -e 'await import("/home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js").then(m => console.log(Object.keys(m)))'
```

## Runtime Verification

2026-09-15 14:04:57Z — production wire proof via local capture proxy: clamped resume turn
(`output-shaper.log`: `Clamped zai-coding-plan/glm-5.3-flash resume turn: reasoningEffort=low` at 14:04:57.732)
produced request body `"reasoning_effort":"low"` at 14:04:57 (same turn). Pre-patch control at 13:31:21Z:
clamp logged, body carried NO `reasoning_effort`. Variant path proof at 14:03:09Z: unclamped fresh turn
carried `reasoning_effort:"high"` (sisyphus high variant — previously also deleted).

Server-level rollout: only `opencode serve` processes started after 2026-09-15 ~14:01Z load the patched
dist. Long-lived pre-patch servers keep deleting/inverting until restarted (opencode.service restarted
14:05:41Z; the 3030/46946 agent servers were NOT force-restarted — live sessions attached).

## Port to Source (before next fork rebuild)

Apply the same three edits to `packages/model-core/src/model-capability-heuristics.ts`, commit on
`fix/custom-patches-v4.19.2`, and fold into the next `v4.19.2-patches.N` tag — otherwise a rebuild
from source silently loses this fix.
