---
patch_id: "omo--lookat-fallback-patience"
dependency: "oh-my-openagent"
target_file: "dist/index.js"
target_install_path: "/home/ezotoff/oh-my-openagent-v4.19.2"
source_repo: ""
status: "active"
applied_date: "2026-08-16"
dep_version: "4.19.2"
runtime_effective: false
upstream_issue: "none"
verification_pattern: "LOOK_AT_FALLBACK_PATIENCE_MS"
surfaces: ["server-api"]
note: "Live dist patch (Bun bundle, not minified — identifiers survive as-is). target_file is dist/index.js, the artifact loaded via file:// from opencode.json. verification_pattern is an identifier literal — pattern match is necessary but NOT sufficient; the ## Runtime Verification section is the only sufficient check."
---

# look_at Fallback Patience (empty-result re-poll)

## Problem

When the multimodal-looker agent's primary model fails mid-generation and OMO's runtime-fallback machinery rescues the look_at child session with a fallback model, the `look_at` tool races the rescue and loses. Proven sequence (2026-08-16, OMO log `~/.local/share/opencode/logs/oh-my-opencode.log`, child `ses_ff4118ffcffe...`):

1. `runLookAtSessionResult` dispatches the prompt synchronously (`promptSyncWithModelSuggestionRetry`, model `openai/gpt-5.6-terra`).
2. Primary fails; provider auto-retries attempts 1–2 (within `retries_before_fallback: 2`); attempt 3 triggers the runtime-fallback hook, which aborts the in-flight request and re-prompts with the fallback model (e.g. `google/gemini-3.7-flash`).
3. The abort resolves the sync dispatch; `waitForLookAtSessionResult` poll #1 sees an idle session whose messages are `[user, assistant(primary-attempt, empty)]` → `outcome.hasAssistant && outcome.completed` returns immediately (zero patience, ~11ms) with empty text.
4. The runner fetches messages ONCE, extracts no text, and returns `Error: No response from multimodal-looker agent` — ~2.5s BEFORE the fallback answer lands (tool gave up 18:56:18.703Z; gemini text arrived 18:56:20.7Z).

Observed 4× on 2026-08-16 (3 in session `ses_ff594298bffeWXBu7AhWFcF4jk` + 1 live repro): every failure had a complete correct answer sitting in the orphaned child session. Aggravated — not caused — by `retries_before_fallback: 2` (patch `omo--retries-before-fallback` stretches the idle-looking gap) and by the agent's `fallback_models` (commit `383fc74` in ez-omo-config, which is also what makes the rescue succeed at all).

## Patch Description

**Files changed (1):** `dist/index.js` — two edits inside/beside `runLookAtSessionResult`.

1. New module const beside the other look-at polling constants (`var IDLE_STABILITY_POLLS_REQUIRED = 3;`):
   ```js
   var LOOK_AT_FALLBACK_PATIENCE_MS = 60000;
   ```
2. The one-shot extract at the end of `runLookAtSessionResult` (between `log2("[look_at] Got N messages")` and `return responseText`) changed from `const responseText = ...; if (!responseText) { return "Error: No response..." }` to a bounded re-poll loop: when the extracted text is empty, re-fetch the child session's messages every 1s and re-extract, until text appears or `LOOK_AT_FALLBACK_PATIENCE_MS` (60s) expires; a messages-fetch error mid-loop breaks out to the existing `Error: No response from multimodal-looker agent` return. The success fast-path (text present on first extract) is unchanged.

This covers all three empty-outcome paths: the waiter's `hasAssistant && completed` early return, the waiter's `canConcludeIdle` stable-poll return, and the waiter being skipped entirely after a non-ambiguous prompt-dispatch failure. Worst-case cost: a truly-dead look_at (all fallbacks fail terminally) now blocks ~68s instead of ~8s before returning the same error string.

## Verification

**Pattern (necessary, NOT sufficient):**

```bash
grep -c 'LOOK_AT_FALLBACK_PATIENCE_MS' /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js          # must be 2 (decl + use)
grep -n 'runtime-fallback answer may still land' /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js  # must match (patience-loop log line)
grep -n 'const responseText = observedText' /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js      # must be EMPTY (pre-patch line gone)
node --check /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js                                     # must pass (syntax)
```

**Diff shape (necessary):** exactly one backup `index.js.pre-lookat-fallback-patience.*`; `diff <backup> dist/index.js` shows only the const insertion and the loop replacement (~20 changed lines total).

Regression corpus: `tests/regressions/013-lookat-fallback-patience.sh` (+ `.kill.sh` negative control against the preserved pre-patch backup).

## Runtime Verification

`verification_pattern` is an identifier literal that survives any bundle rebuild verbatim, so grep is necessary but not sufficient. The only sufficient check is observing a rescued look_at call return the fallback model's answer.

**Steps (server-api surface, no production restart needed):**

1. Start a throwaway server on an allocated port (loads the patched dist):
   `/deployment` skill → allocate port → `~/.opencode/bin/opencode serve --hostname 127.0.0.1 --port <allocated> &`
2. Through that server, run a session whose prompt instructs the agent to call `look_at` on an image (e.g. `/tmp/opencode/cr2-page-1.png`) and return the tool output verbatim. With the primary vision model quota-dead, the call exercises the exact race path.
3. Expected: the tool returns the fallback model's answer (NOT `Error: No response from multimodal-looker agent`), ~10–15s elapsed.
4. Confirm the patience loop ran: `grep 'Empty result; runtime-fallback answer may still land' ~/.local/share/opencode/logs/oh-my-opencode.log` — newest entry must postdate the server start.
5. Production rollout: `systemctl --user restart opencode.service omo-tg.service`, verify new PIDs (`ps -eo pid,lstart,args | grep 'opencode serve'`), spot-check one look_at call from a live session.

**Regression signal:** look_at returns `Error: No response from multimodal-looker agent` while the OMO log shows the fallback model's answer landing in the child session afterwards → set `runtime_effective: false`, add `## Current Runtime Status`, do NOT bump `dep_version`.

## Reapply Instructions

Dist-level patch on the OMO bundle. The v4.19.2 bundle is NOT minified (identifiers like `runLookAtSessionResult` and `LOOK_AT_FALLBACK_PATIENCE_MS` survive as written), but a rebuilt/newer dist may rename them — identify the active names in the TARGET version first.

1. `cp dist/index.js dist/index.js.pre-lookat-fallback-patience.$(date +%s)` (backup).
2. Locate the runner: `grep -n 'No response from multimodal-looker agent' dist/index.js` → the enclosing `runLookAtSessionResult` function.
3. Add `var LOOK_AT_FALLBACK_PATIENCE_MS = 60000;` next to `var IDLE_STABILITY_POLLS_REQUIRED = 3;`.
4. Replace the final one-shot extract (`const responseText = <observed text> ?? extractLatestAssistantText(messages);` … `return responseText;`) with: `let` binding + empty-guarded `while (!responseText && Date.now() < deadline)` loop that sleeps 1s, re-fetches `ctx.client.session.messages({ path: { id: sessionID } })`, re-extracts, and breaks on fetch error; keep the `Error: No response from multimodal-looker agent` return and the final `return responseText;` after the loop.
5. `node --check dist/index.js`, then run the Runtime Verification steps above, then `systemctl --user restart opencode.service omo-tg.service`.

## Durable Alternative

Upstream fix in OMO source: `packages/omo-opencode/src/tools/look-at/look-at-session-runner.ts` (and/or `look-at-session-waiter.ts`) — teach the waiter that an empty assistant outcome is not a conclusion while a runtime-fallback may still land (e.g. require non-empty text to conclude under `allowStableIdleWithoutActivity`, or subscribe to `session.status` retry/fallback events). The runtime-fallback hook (`runtime-fallback-abort:session.status.retry-signal`) and the look_at waiter live in the same package; coordinating them upstream removes this patch.

Status: not-yet-pursued
