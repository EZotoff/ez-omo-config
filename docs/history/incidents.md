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
