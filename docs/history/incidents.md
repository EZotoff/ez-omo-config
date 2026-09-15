# Incident & Experiment History

Dated operational record: incident forensics, parked experiments, removed components, and future-work sketches. Current configuration truth lives in the [README](../../README.md); patch status lives in the [patch registry](../../MANIFEST.md#patch-registry) and [docs/patches.md](../patches.md).

## Runaway-subagent incidents (June 2026)

Layered defenses against runaway subagent sessions were added after two forensic root causes:

- **14 Jun 2025, visual-engineering QA loop**: $43.58 / 14.3M input tokens in 77 minutes (stuck same-tool repeat).
- **21 Jun 2025, build/test ping-pong**: $12.75 / 50M cache-read tokens in 27 minutes (alternating `npm run build` ↔ `npm run test`).

Defenses now in live config (see README "Runaway-subagent defenses"): model demotion for `visual-engineering`, 2-turn error purge, and the OMO background-task circuit breaker (`maxToolCalls=500`, `consecutiveThreshold=15`).

**Known limitation**: `consecutiveThreshold` only catches *strictly* consecutive identical tool+input signatures. Alternating patterns and same-tool varying-input patterns reset the counter each call; the `maxToolCalls` cap is the only hard backstop for those. Shape-based alternation detection is planned as a sliding-window extension to OMO's circuit breaker (where task cancellation actually works), not as an OpenCode plugin.

## Removed: subagent-loop-guard plugin (2026-07-25)

`subagent-loop-guard.ts` was removed. Post-incident analysis showed its sliding-window rules (same-tool frequency, same-tool varying-input) matched legitimate tool-dense investigation work far more often than real doom loops, its only enforcement action was mutating bash calls into no-op echoes (agents routed around it by switching tools), and it hooked every session including root orchestrators despite being named for subagents. OMO's `consecutiveThreshold` already covers strict-repeat loops with real task cancellation. The remaining gap — alternation/varying-input shape detection — is planned as an OMO circuit-breaker extension in `manager.ts`, scoped to background subagent tasks, where cancellation authority exists.

## Future work: periodic lead-agent inspection (sketch, out of scope)

The defenses above are reactive (detect-and-block). A complementary proactive mechanism would let the lead agent periodically inspect running subagents without breaking their flow:

| Option | Mechanism | Breaks flow? | Complexity |
|--------|-----------|--------------|------------|
| Push (transcript inject) | Plugin calls `client.session.promptAsync(parentID, status)` every 15 min | Yes — processed as a new user turn | Medium |
| Pull (sidecar log) | Status snapshots to `~/.sisyphus/agent-watch/<child>.json`; parent reads when curious | No (passive) | Low |
| Pull (transcript annotation) | Annotate the parent's next tool call args with a status comment | No (in-band) | Medium |
| Upstream OMO patch | Fix `lastMessageAt` assignment in `manager.ts` so the existing babysitter hook fires | No (handled by OMO) | High |

Deferred until the circuit breaker has been observed in real visual-engineering subagent runs.

## Parked: FLARE-4B self-hosted provider (2026-08-15)

A self-hosted FLARE-4B provider (`systemd/user/flare-serve.service`, SGLang on port 18200) was trialled 2026-08-15 and disabled the same day: 14.6GB VRAM did not coexist with ComfyUI on the 16GB GPU. `small_model`/title generation reverted to `opencode-go/deepseek-v4-flash`, then moved to `ollama-cloud/deepseek-v4-flash:0731` (27 Aug 2026). Kept for a possible retry: the unit, `scripts/derive-flare-chat-template.py` (no-think decoding + consecutive-system-message merge for OpenCode's two system messages; stock template rejects with 400), and the model cache (`~/flare-cache`).

## Dual-bug fresh-session outage (2026-09-08)

Fresh OpenCode sessions failed because two independent defects overlapped. The primary failure was a destroyed OMO runtime bundle. A separate plugin export-surface violation produced a misleading, caught load error and initially appeared to be the cause.

### Timeline

- **05:51 UTC**: Fork `head_restraint` commits were present.
- **13:59:40 UTC**: An unguarded destructive redirect, in the form of `git show <ref>:dist/index.js > dist/index.js`, overwrote the 5.6 MB live `~/oh-my-openagent-v4.19.2/dist/index.js` bundle. The referenced `dist/` file was untracked, so `git show` failed and redirected its 67 bytes of git-fatal stderr into the live artifact.
- **14:12:58 UTC**: The first fresh session died with `default agent "Sisyphus" not found`. The unimportable OMO bundle prevented agent registration.
- **About 14:00 UTC onward**: The 30-minute integrity timer repeatedly failed with five stale patches, but emitted no operator-facing alert.
- **15:28 UTC**: A dirty `quick.model` edit occurred. It was unrelated to the outage. The qwen-tunnel endpoint it selected was down.
- **16:0x UTC**: Investigation tested the plugin theory. Fixing the review-enforcer export issue and running five large-prompt reproductions still produced five failures, disproving review-enforcer causality. A 30-second delayed-stdin run also failed, disproving the race theory.
- **Recovery**: The bundle was rebuilt from source at `688b8fd03`, then three dist patches were reapplied. The patch registry reported 21 applied and zero stale entries. A small-prompt end-to-end run exited 0, and a 1.28 MB bench-shaped session reached 443k tokens.

Evidence anchors: `/tmp/opencode/repro-crash-audit.log`, `/tmp/opencode/final-e2e.log`, and `~/.opencode/plugin/review-enforcer.log`.

### Root causes

1. **Plugin export-surface contract violation with delayed blast radius.** OpenCode's `getLegacyPlugins` loader calls every function export as a plugin constructor. Seven pure review-enforcer test helpers were exported beside the plugin entry point. The loader called `detectRecursion` with plugin input, which caused `output.includes is not a function`. The loader caught the error and continued, while alphabetical export order had already loaded the real plugin, so enforcement survived.
2. **Unguarded destructive redirect into a live runtime artifact during diagnostic exploration.** A failed diagnostic read redirected stderr directly into the live OMO bundle, replacing executable runtime content.

The message `failed to load plugin` described a caught, continued load error. Treating that label as a single-cause explanation delayed the diagnosis.

### Excluded cause and operating context

The Project Supervisor was not causal. It is a read-only HTTP and Server-Sent Events client on `127.0.0.1:3021`, writes only to its own state directory, and cannot affect standalone per-run servers used by the reproduction. The bundle corruption preceded the first session death by 13 minutes, which establishes the causal order.

Network egress was degraded to about 130 kbps. The background models.dev refresh failed but was non-fatal because the five-minute disk cache covered population. The qwen-tunnel LAN endpoint was down. These conditions complicated diagnosis but did not cause the bundle corruption or export-surface violation.

### Remediation and lesson

Four defenses now cover this incident class: watcher coverage for OMO `dist/` writes (`7f7f20b`), integrity-check `OnFailure` alerting (`ea67550`), a fresh-boot smoke gate (`f099af7`), and an exact md-table-formatter plugin pin (`ea67550`). The watcher treats verified rebuild and patch-reapply flows as expected dist writes, while other writes are suspect. The smoke gate proves a fresh boot, plugin loading, agent resolution, and a completed model loop rather than relying on file-pattern checks alone.

Root-cause claims now require fix-then-reproduce verification before handoff. A localized error is not proof of causality, especially when the runtime catches and continues after reporting it.


## Output-shaper clamp silent no-op (2026-09-15, present since 2026-08-07)

The output-shaper's reasoning-effort dialing produced zero token savings on most providers for ~5 weeks. Measurement (before/after averages on resume turns, input-size-matched, ~122k messages from `opencode.db` + 60k clamp events from `output-shaper.log`) showed −60% reasoning tokens for `openai/gpt-5.6-*` but nothing for zai/opencode-go/kimi/google — despite 73% of clamp volume targeting zai.

Root cause: the plugin wrote snake_case `reasoning_effort` (and top-level `thinkingLevel` for google) into `chat.params` `output.options`, but that object flows into AI SDK `providerOptions`, whose `@ai-sdk/openai-compatible` Zod schema accepts ONLY camelCase `reasoningEffort` (mapped to body `reasoning_effort`). Snake_case keys were silently dropped — the clamp never reached the wire. ollama-cloud DeepSeek models were additionally missing from CLAMP_TABLE entirely. The one working row (`openai`) worked because it already used the correct `reasoningEffort` spelling; kimi-for-coding (K2.7) partially worked because the `opencode-kimi-full` plugin reads both casings.

Fix: CLAMP_TABLE now uses OpenCode providerOptions vocabulary (`reasoningEffort` everywhere, `thinkingConfig: { thinkingLevel }` for google), adds ollama-cloud with a DeepSeek-only model allowlist (live A/B showed `reasoning_effort` INCREASES minimax-m3 reasoning erratically), and `isTargetModel()` takes a model id for allowlist gating. Live endpoint A/B (`/tmp/opencode/ab_test_reasoning.py`, 2026-09-15): zai glm-5.3/flash `reasoning_effort:"low"` cuts reasoning 106–172 tok → 0; ollama.com/v1 deepseek-v4-pro:0813 ≈ halves reasoning; regression guard is the `option-vocabulary` harness case.

Lesson: plugins writing `chat.params` options must use the AI SDK option vocabulary (see `provider/transform.ts` `reasoningEffort()` for the per-provider shapes), never raw HTTP body parameter names — and the old `casing-snake-vs-camel` harness case had enshrined the exact inverse assumption.

### Layer 2 (2026-09-15 13:00–14:05Z): OMO family-table reconciliation deleted/inverted the clamp

The vocabulary fix (commit d8a170f) was verified by SDK-level replication (echo body + live 297→0 reasoning tokens) but produced **zero effect on live traffic**: post-fix averages for glm-5.3 (real 359 vs placebo 308 vs pre-fix 361 reasoning tokens) were flat. A wire-capture proxy (temporary baseURL flip through a local forwarder, port registry entries 9417/9418, since freed) proved the clamp still never reached zai: `Clamped ... reasoningEffort=low` logged at T, request body at T+270ms carried NO `reasoning_effort`.

Root cause: the OMO fork's `chat.params` handler (runs after output-shaper in the plugin array) reconciles `options.reasoningEffort` against per-family capability tables (`packages/model-core/src/model-capability-heuristics.ts`): the **glm family declared no `reasoningEfforts`** → `resolveField` returns undefined → handler executes `delete output.options.reasoningEffort`; the **deepseek family aliased `low→high`** (inversion); **kimi** same delete as glm. This also silently killed OpenCode's own variant-derived efforts (sisyphus `high` never reached zai either) — only openai-family models and K2.7 (via the kimi plugin's header smuggling) ever worked.

A plugin-array reorder (output-shaper after the OMO fork) was tested and REJECTED: plugin init is sequential, and a later-positioned plugin becomes hostage to OMO's init completing — observed as output-shaper silently not loading on restarted servers. (Also: `opencode run` sessions whose directory ≠ server cwd never clamp — the resume-detector's messages query is directory-scoped and fails closed; live-agent sessions on their own project servers are unaffected.)

Fix: dist-level patch of the three family tables (`.sisyphus/patches/omo--family-reasoning-efforts.md`; glm/kimi get `reasoningEfforts: [low,medium,high,max]`, deepseek drops the low→high alias). Wire-proven at 14:04:57Z: clamp line 14:04:57.732 ↔ body `reasoning_effort:"low"` same turn; variant path proven at 14:03:09Z (`reasoning_effort:"high"` on an unclamped fresh turn). Requires server restart to load; opencode.service restarted 14:05:41Z, the 3030/46946 agent servers still run pre-patch dist.

Process lesson: a mid-verification `edit`-revert botched `output-shaper.mjs` (duplicate `const valueStr` → SyntaxError) and the plugin loader skips failed modules SILENTLY — "plugin loaded"-style startup log lines are the canary; check them after every config-layer change.