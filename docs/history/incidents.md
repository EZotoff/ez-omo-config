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
