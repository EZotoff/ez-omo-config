---
patch_id: "omo--gpt6-hephaestus-registration"
dependency: "oh-my-openagent"
target_file: "packages/omo-opencode/src/agents/hephaestus/agent.ts"
target_install_path: "/home/ezotoff/oh-my-openagent-v4.19.2"
status: "active"
applied_date: "2026-09-23"
dep_version: "4.19.2"
upstream_issue: "none"
verification_pattern: "GPT-5.3 Codex, GPT-5.4, GPT-5.5, GPT-5.6, and GPT-6 models"
runtime_effective: true
surfaces: "n/a (agent registration + chat.message hook logic, not rendering)"
note: "Source patch, fork commit 8822e6b2e on branch feature/wake-journal-outbox (pushed to EZotoff/oh-my-openagent). Runtime-verified 2026-09-23 after continuation-safe restart of both servers: GET /agent on :3021 and :3030 list Hephaestus (19 agents, was 18); probe session ses_f3267e7caffeUMW0oJ2iRT9IZk (Sisyphus + openai/gpt-6-sol, scratch dir) persisted agent=Sisyphus with no toast rewrite and no [Directory Context] injection and answered 'OK'; Hephaestus + gpt-6-sol probe session answered 'OK' (no injection in scratch dir without AGENTS.md, as designed)."
---

# Accept GPT-6 models for Hephaestus registration and Sisyphus-native GPT detection

## Problem

Commit `dc6bcb7` in ez-omo-config promoted the OpenAI models `gpt-5.6-sol/luna` to `gpt-6-sol/luna`. Three upstream GPT-5-anchored gates broke silently:

1. `isHephaestusSupportedModel()` (`agents/hephaestus/agent.ts`) accepted only gpt-5.3-codex/5.4/5.5/5.6 → with `agents.hephaestus.model = openai/gpt-6-sol`, Hephaestus registration was **skipped at server boot** ("Agent skipped: unsupported Hephaestus model"), removing the agent from the live registry (`GET /agent`: 18 agents, no Hephaestus).
2. `GPT_NATIVE_SISYPHUS_RE` (`agents/types.ts`) matched only `gpt-5.*` → the `no-sisyphus-gpt` hook treated `gpt-6-sol` as non-native and **force-rewrote Sisyphus sessions to the now-missing Hephaestus**, showing the "NEVER Use Sisyphus with GPT" error toast.
3. The rewrite then activated `hephaestus-agents-md-injector`, which prepends the project AGENTS.md **into the user message text** (`[Directory Context: …]` block), and dispatch of the unregistered agent errored out, stalling the session until the busy-stall watchdog aborted it (~10 min).

Observed 2026-09-23 on session ses_f3294d88affeIYwNZ00VrDyC5u (ez-omo-config): user prompt hijacked into a Hephaestus session with injected AGENTS.md, missing-agent error, stalled turn, watchdog abort, recovery as Sisyphus on fallback models.

## Patch Description

Fork commit `8822e6b2e`, branch `feature/wake-journal-outbox`, pushed to origin (EZotoff/oh-my-openagent) — satisfies the fork-push preservation rule before `status: active`.

- `agents/types.ts`: `GPT_NATIVE_SISYPHUS_RE` extended with `|gpt-6[.-]`; new `isGpt6Model()` (`/gpt-6(?:$|[.-])/` after provider-prefix strip).
- `agents/hephaestus/agent.ts`: new `GPT_6_RE = /^gpt-6(?:$|[.-])/i` accepted by `isHephaestusSupportedModel`; `getHephaestusPromptSource` maps GPT-6 models to the latest (`gpt-5-6`) prompt template; `UnsupportedHephaestusModelError` message lists GPT-6.
- `hooks/no-sisyphus-gpt/hook.ts`: toast text updated (GPT-6 models have GPT-native prompt support); `getNativeSisyphusGptVariant` short-circuits GPT-6 models to `"medium"` (parity with gpt-5.6-sol chain entry).

Tests: new `agents/hephaestus/gpt-6-registration.test.ts` (6 tests) + new no-sisyphus-gpt case for `gpt-6-sol` (no toast, no rewrite, variant `medium`). RED→GREEN verified; full `agents/`+`hooks/` sweep (2499 tests) shows byte-identical failure set before/after (67 pre-existing failures, incl. 2 case-sensitivity failures in no-sisyphus-gpt predating this patch).

## Verification

```bash
# Source gates accept gpt-6-sol:
grep -n "GPT_6_RE" /home/ezotoff/oh-my-openagent-v4.19.2/packages/omo-opencode/src/agents/hephaestus/agent.ts
grep -n "gpt-6" /home/ezotoff/oh-my-openagent-v4.19.2/packages/omo-opencode/src/agents/types.ts

# Rebuilt bundle (bun run build 2026-09-23) carries all three sites:
grep -c "GPT_6_RE" /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js   # >= 1
grep -n "gpt-6\[.-\]" /home/ezotoff/oh-my-openagent-v4.19.2/dist/index.js   # GPT_NATIVE_SISYPHUS_RE line

# Pushed to fork remote:
git -C /home/ezotoff/oh-my-openagent-v4.19.2 branch -r --contains 8822e6b2e   # origin/feature/wake-journal-outbox
```

## Runtime Status

Not yet effective: running `opencode serve` processes loaded the pre-patch bundle at startup. Requires the session-safe restart (both surfaces) to load the rebuilt `dist/index.js`, then: (a) `GET /agent` lists Hephaestus again, (b) a probe session with Sisyphus + openai/gpt-6-sol shows no toast, no agent rewrite, no `[Directory Context]` injection.
