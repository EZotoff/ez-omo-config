---
patch_id: "omo--retries-before-fallback"
dependency: "oh-my-openagent"
target_file: "packages/omo-opencode/src/config/schema/runtime-fallback.ts, packages/omo-opencode/src/hooks/runtime-fallback/constants.ts, packages/omo-opencode/src/hooks/runtime-fallback/hook.ts, packages/omo-opencode/src/hooks/runtime-fallback/session-status-handler.ts, packages/omo-opencode/src/hooks/runtime-fallback/session-status-handler.test.ts"
target_install_path: "/home/ezotoff/oh-my-openagent-v4.19.2"
status: "active"
applied_date: "2026-08-15"
dep_version: "4.19.2"
upstream_issue: "none"
verification_pattern: "retries_before_fallback"
runtime_effective: true
note: "Source patch, committed in the fork as 49f6728 (branch fix/custom-patches-v4.19.2) and embedded in dist/index.js via the 2026-08-15 rebuild. runtime_effective: true since 2026-08-15 09:53 CEST — budget guard observed on real provider retry signals in the durable log (see Runtime Status)."
---

# Runtime Fallback Retries Before Fallback

## Problem

OMO's runtime-fallback hook treats OpenCode's provider auto-retry signal (`session.status` with `type: "retry"`) as a failover trigger on the FIRST occurrence. It aborts OpenCode's in-flight same-model retry (`abortSessionRequest(sessionID, "session.status.retry-signal")`) and immediately dispatches the fallback chain — observed 2026-08-15 06:25:44Z in ses_ffbec2fadffeQjbcRZb1lCu5fW and ses_fffbfd05dffe9g4tqKjXh1qFCv: retry signal detected at .937, abort at .958, fallback dispatched at .969 (22 ms; OpenCode never attempted retry #2).

OpenCode's native retry (`packages/opencode/src/session/retry.ts`) retries the same model with exponential backoff (2s initial, 2x factor, honors `retry-after` headers) and has NO attempt cap — it retries indefinitely. A single transient 429/5xx therefore abandons the configured primary model (zai-coding-plan/glm-5.3) for the whole turn, switching to openai/gpt-5.6-sol until a manual model change resets fallback state. The operator wants same-model retries to get a chance first.

## Patch Description

**Files changed (5):** source patch in the fork (commit 49f6728), rebuilt into `dist/index.js` on 2026-08-15.

1. `config/schema/runtime-fallback.ts` — new optional `retries_before_fallback: z.number().min(0).max(10)` field on `RuntimeFallbackConfigSchema` with doc comment.
2. `hooks/runtime-fallback/constants.ts` — `DEFAULT_CONFIG.retries_before_fallback = 0` (0 = legacy fail-on-first-signal behavior; upstream default unchanged).
3. `hooks/runtime-fallback/hook.ts` — plumb `retries_before_fallback` from `options.config` into the hook's resolved config.
4. `hooks/runtime-fallback/session-status-handler.ts` — after the dedupe-key registration and BEFORE the in-flight-retry override and abort, parse the attempt number (`extractRetryAttempt`) and early-return when `retries_before_fallback > 0 && attempt <= retries_before_fallback`, logging `retry signal within same-model retry budget - letting provider retry`. Attempts above the budget proceed to abort+fallback as before. Placement matters: the guard sits before the `sessionRetryInFlight` override so a budgeted retry never kills an in-flight native retry.
5. `session-status-handler.test.ts` — three new Given/When/Then tests: attempts 1-2 with budget 2 → no abort/dispatch; attempt 3 with budget 2 → abort+fallback; budget 0 → immediate fallback (legacy regression lock).

Config activation (this repo): `configs/oh-my-openagent/oh-my-openagent.json` → `runtime_fallback.retries_before_fallback: 2`.

Semantics: with N=2, OpenCode retries the same model on retry signals with `attempt <= 2` (waits 2s, then 4s); the first signal with `attempt = 3` aborts the loop and fails over to the agent's `fallback_models` chain. The dedupe retry-key map still records budgeted signals, so a repeated identical (attempt, message) key does not re-evaluate.

## Verification

```bash
# Source (necessary and sufficient for a source patch):
grep -c 'retries_before_fallback' /home/ezotoff/oh-my-openagent-v4.19.2/packages/omo-opencode/src/hooks/runtime-fallback/session-status-handler.ts   # >= 2
# Bundle (embedded via rebuild):
grep -c 'retries_before_fallback' /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js   # >= 3
# Tests:
cd /home/ezotoff/oh-my-openagent-v4.19.2 && bun test packages/omo-opencode/src/hooks/runtime-fallback/session-status-handler.test.ts   # 5 pass
# Config accepted:
python3 -c "import json; print(json.load(open('/home/ezotoff/ez-omo-config/configs/oh-my-openagent/oh-my-openagent.json'))['runtime_fallback']['retries_before_fallback'])"   # 2
```

## Runtime Verification

Behavioral patch (not a rendering/monkey patch); the sufficient check is observing the budget guard fire on a REAL provider retry signal:

1. After `systemctl --user restart opencode.service omo-tg.service`, confirm server start time changed (`ps -eo pid,lstart,etime,args | grep 'opencode serve'`).
2. Confirm the durable OMO log receives fresh entries (`~/.local/share/opencode/logs/oh-my-opencode.log`) — proves the rebuilt dist (with this patch + the re-applied dist patches) is the loaded runtime.
3. On the next real Z.AI rate-limit/transient error, the log must show `[runtime-fallback] retry signal within same-model retry budget - letting provider retry` with `retries_before_fallback: 2` for attempts 1-2, and only an attempt-3 signal may show `Detected provider auto-retry signal` → `Preparing fallback`. Absence of an immediate `Preparing fallback` after the first retry signal is the pass condition.
4. Flip `runtime_effective: true` and record the observation timestamp in a `## Runtime Status` section when step 3 is observed.

## Reapply Instructions

Source patch — reapply from fork commit 49f6728 (branch `fix/custom-patches-v4.19.2`):

```bash
cd /home/ezotoff/oh-my-openagent-v4.19.2
git show 49f6728 --stat          # 5 files listed
git cherry-pick 49f6728          # on the next-version patch branch
bun run build                    # rebuild dist/index.js
# then re-apply the two dist-level patches (omo--durable-log-path,
# omo--fallback-toast-origin) per their own reapply instructions —
# this rebuild clobbers them.
bash /home/ezotoff/ez-omo-config/scripts/verify-live-patches.sh
```

The threshold guard is the block starting `const retriesBeforeFallback = deps.config.retries_before_fallback ?? 0` in `session-status-handler.ts`; on a future upstream refactor, re-place it after the dedupe-key `sessionStatusRetryKeys.set(...)` and before any `abortSessionRequest` call.

## Durable Alternative

An upstream `runtime_fallback.retries_before_fallback` (or `min_retry_attempts`) config option in oh-my-openagent would eliminate this patch entirely — the knob is additive, defaults to legacy behavior (0), and upstream `session-status-handler.ts` has no attempt-threshold today (verified on v4.19.2 source).

Status: not-yet-pursued — candidate for an upstream PR against `code-yeongyu/oh-my-openagent`.

## Runtime Status

**Observed effective: 2026-08-15 09:53 CEST (post-restart, durable log).**

- Restart at 09:11:16 CEST loaded the rebuilt dist; budget guard first observed 42 minutes later.
- `~/.local/share/opencode/logs/oh-my-opencode.log` lines 17552/17558: ses_ffbec2fadffeQjbcRZb1lCu5fW (ComfyUI) hit real provider retry signals at attempt 1 (07:53:02Z) and attempt 2 (07:53:06Z) — both logged `retry signal within same-model retry budget - letting provider retry` with `retriesBeforeFallback: 2`; NO `Preparing fallback` followed. GLM 5.3 recovered on the native retry and the session stayed on zai-coding-plan/glm-5.3.
- Same for ses_ffd75c5a0ffeuRPX9ba6GJv7mm (Nestor, attempt 1 at 07:53:42Z) and ses_ffd6f68cfffeu7y9opbKFt2I2H (attempt 1 at 07:53:20Z): budgeted, recovered, no fallback.
- Cross-check via message DB: zero `openai/gpt-5.6-sol` assistant messages in any session after 07:11:16Z; all Sol messages (ComfyUI ×5, Nestor ×8, Veran ×2) predate the restart and were produced by the old fail-on-first-signal behavior.
- Not yet observed live: the exhausted-budget path (attempt 3 → abort → fallback). It is covered by unit tests (`session-status-handler.test.ts`, 5/5 pass); a live observation will land here when a provider fails three consecutive attempts.
