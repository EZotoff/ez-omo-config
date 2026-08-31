# Provider/Model Onboarding Hardening — RCA & Solution Design

**Date**: 2026-08-30
**Status**: Design approved for implementation (this turn delivers analysis + design; scripts/runtimes land in follow-up commits)
**Trigger**: Repeated incidents when adding new models/providers to this repo (Aug 14 – Aug 30, 2026). A same-day audit (prototype validator run) found **9 latent issues** in the live config — the failure pattern is still active, not historical.

---

## 1. Incident Corpus

Every provider/model configuration incident in the last 6 weeks, reconstructed from git history and session records:

| # | Date | Commit(s) | What went wrong | Failure class |
|---|------|-----------|-----------------|---------------|
| 1 | Aug 15 | `c53d062` | `ollama-local` declared ctx 40960, server serves 61440 → premature compaction | Wrong declared limit |
| 2 | Aug 18 | `4c588d0` | Wrong Kimi model id — `opencode-kimi-full` plugin hooks (gated on exact id) never fired | Wrong model id |
| 3 | Aug 19 | `8cf88e4` | K2.7-era entry labeled as K3; true K3 (`k3` id, 1M ctx) had to be re-added | Stale metadata carried forward |
| 4 | Aug 19–20 | (session) | Kimi K3 declared 1M context but the user's plan tier serves 256K → mid-session overflows | Tier-dependent limits unknown |
| 5 | Aug 27 | `2711fbd` | `ollama-cloud/minimax-m3` model block missing `limit.output` → **config rejected at load** (`config-invalid`) | Schema violation |
| 6 | Aug 27 | `70eb9f4` | Title/small_model moved to ollama-cloud — correct on disk, but stale TUI panes kept pre-change config → title generation silently dead for 3 days (found Aug 30) | Config-activation gap |
| 7 | Aug 28 | `1776a57` | models.dev supplies phantom `limit.input=372000` for `openai/gpt-5.6-*`; config omitted `input`, per-field `??` merge let the upstream poison survive → auto-compaction at 352K instead of ~902K | Upstream metadata poisoning |
| 8 | Aug 28→29 | `78687c9` → `7663dd2` | `qwen-tunnel` provider block added but **not added to `enabled_providers`** — provider invisible until a follow-up fix next day | Coupled-surface omission |
| 9 | Aug 30 | (audit) | FLARE-4B precedent: promoted to `small_model`+title without trial → reverted (`9ca7895`→`a003cba`) | No promotion pipeline |

**Current latent state (2026-08-30 audit, see §4):** 7 agent-referenced models still omit `limit.input` (class #7 exposure), 1 model block omits both context and output (intentional, needs explicit marker).

---

## 2. Root-Cause Analysis

Per-incident causes collapse into **six systemic causes**. None of them is "the agent made a mistake" — every incident was structurally inevitable given the current workflow.

### RC1 — Correctness lives in prose, not in a machine-checkable contract
The rules for a valid provider/model entry exist (AGENTS.md "Provider Setup", docs/configs.md) but nothing executes them. `tests/test_openai_provider.sh` is a hardcoded snapshot for one provider (asserts specific names/models); it cannot catch a missing field in a *new* block. Every new provider starts from zero validation.

### RC2 — Facts are written from memory, not probed from sources
Model IDs, context/output limits, and catalog membership were written from recollection or stale registry snapshots in incidents #1–#4. The authoritative sources — the provider's live `/v1/models` endpoint and official model pages — were consulted only *after* breakage. Limit values are also tier- or deployment-dependent (Kimi plan tier, llama.cpp `n_ctx`), so "docs" are not always enough; the endpoint itself must be probed.

### RC3 — Adding one model touches 3–6 coupled surfaces with no integrity check
A single addition must update: the `provider.<id>.models` block, `enabled_providers`, OMO agent/category assignments and fallback chains in `oh-my-openagent.json`, possibly `small_model`/`agent.title.model`, the README provider table, and `auth.json`. Incident #8 (enabled-list omission) and #5 (incomplete block) are direct hits; reference drift after model retirement (`c59adcf` retiring glm-5/5.1/5.2) is the same class waiting to happen.

### RC4 — Validation happens at runtime, late and on the wrong surface
First feedback on a bad block is `config-invalid` at opencode load — or worse, a mid-session overflow/quota/model-not-found error (#4, #7). Nothing gates the *commit*. The repo already has the perfect integration point (`tests/run_all.sh` auto-discovery → review-enforcer gate) and it is unused for this purpose.

### RC5 — Config activation is manual and structurally incomplete
`systemctl --user restart opencode.service` refreshes one server; long-lived TUI panes embed their own servers that hold the pre-change config indefinitely (#6). Title generation has no fallback chain, so a stale process + a dead quota = silent failure for days. There is no tool that answers "are any running opencode processes older than the current config?"

### RC6 — New models enter production roles without a trial stage
`small_model` and `agent.title.model` are single-point roles with no fallback; incident #9 (and #6's title outage) show what happens when an unproven model is promoted into them. There is no defined promotion path (observe on a non-critical agent first).

---

## 3. Solution Design

Five layers, each mapped to the root causes it kills. Design principle: **make the wrong thing fail loudly at commit time, and make the right thing the path of least resistance.**

### L1 — Structural validator: `tests/test_provider_config.sh` (+ inline Python)

* Auto-discovered by `tests/run_all.sh` → runs in the review-enforcer gate (RC4). Zero new CI wiring.
* Offline (no network, no tokens) — safe for every commit and cross-platform CI.
* Checks, in order:

| # | Check | Kills |
|---|-------|------|
| 1 | Both JSONs parse | basics |
| 2 | Every enabled provider has a block (unless `BUILTIN_PROVIDERS`: google, openai, opencode-go, anthropic) | RC3 |
| 3 | Every non-builtin provider block is in `enabled_providers` **or** in `INTENTIONALLY_DISABLED` list (currently: `anthropic`) | #8/RC3 |
| 4 | Custom provider block: `npm` + `options.baseURL` present; every model has `limit.context` **and** `limit.output` **or** appears in `RUNTIME_LIMIT_EXCEPTIONS` | #5/RC1 |
| 5 | Reference integrity: every `provider/model` string in `opencode.json` (`small_model`, `agent.title.model`) and `oh-my-openagent.json` (agents, categories, fallback chains) resolves to a defined model — for non-builtins, against the config blocks; for builtins, against a checked-in `tests/data/builtin-models.txt` snapshot updated on demand | RC3 |
| 6 | **Explicit-limits rule**: every custom model referenced by OMO agents must declare `context`, `input`, and `output` explicitly — no silent per-field `??` merge from upstream registries | #7/RC2 |
| 7 | `auth.json` presence probe (skip when absent): every non-builtin, non-apiKey-inline provider id has an entry (key content never read, never printed) | RC3 |
| 8 | Docs-drift: every enabled provider id appears in README.md's provider table | RC3 |

* Exceptions are **declarative and reviewed** — three constants at the top of the test (`INTENTIONALLY_DISABLED`, `RUNTIME_LIMIT_EXCEPTIONS`, `BUILTIN_PROVIDERS`), each with an inline justification comment. Today's `kimi-for-coding` (limits discovered at runtime via `/coding/v1/models`) is the first entry in `RUNTIME_LIMIT_EXCEPTIONS` — making the current implicit assumption explicit and auditable.

### L2 — Live verification tool: `scripts/verify-providers-live.sh`

Operator-run (documented in the runbook; not in CI — costs tokens and needs network). Provides the runtime evidence layer the structural validator deliberately can't:

1. **Activation check** — `opencode models` output vs `enabled_providers`: every provider visible, every referenced model resolvable by the real binary.
2. **Catalog probe** — for each custom provider: live `/v1/models` fetch; report declared-vs-advertised model IDs and context (`n_ctx`) mismatches (RC2).
3. **Smoke test** (opt-in `--smoke`): one 5-token completion per enabled provider through `opencode run`; exit 1 on any failure; table output.
4. **Stale-process check** — `ps -o pid,lstart,args` of all opencode processes vs `opencode.json` mtime; any process older than the config → prominent warning with the exact cycle commands (RC5, incident #6).

### L3 — Runbook: `docs/runbooks/add-provider.md`

The canonical workflow, each step naming its tool (makes the right path the easy path):

1. **Probe sources**: provider's live catalog endpoint + official model page → record exact model ids, context/input/output limits, reasoning-field name. Never from memory (RC2).
2. **Write the block**: full `limit` triple (`context`/`input`/`output`) explicitly, `reasoning`/`attachment`/`interleaved` per endpoint behavior.
3. **Enable**: add to `enabled_providers` (same edit, always).
4. **Gate**: `bash tests/test_provider_config.sh` → must pass.
5. **Verify live**: `scripts/verify-providers-live.sh --smoke` → must pass.
6. **Commit** (validator runs again via run_all in the enforcer gate).
7. **Activate**: `systemctl --user restart opencode.service omo-tg.service` **+** cycle every TUI pane older than the commit (the L2 stale-process check prints the exact commands).
8. **Sync docs**: README provider table, docs/configs.md counts, MANIFEST if artifacts changed.

Plus a **promotion rule** (RC6): a new model serves a non-critical agent for an observation period before it may enter `small_model`/`agent.title.model` (single-point, no-fallback roles). The validator enforces the mechanism: `title.model`/`small_model` may only reference models that already exist elsewhere in agent assignments or carry a `# promoted <date>` marker in `RUNTIME_LIMIT_EXCEPTIONS`-style list.

### L4 — Process hygiene hook

Extend the existing 30-min `opencode-patch-integrity-check.timer` pattern: the stale-process check from L2.4 is cheap enough to run in the same cadence and journal an alert when config-mtime > process-start (early warning instead of 3-day silent title death). Design detail: check script stays read-only; alerting via the same journal channel the patch watcher uses.

### L5 — Regression corpus entries (repo convention)

Per the AGENTS.md cooperation contract ("when fixing a bug, add a paired `.sh`/`.kill.sh`"), incidents #5, #7, #8 get regression corpus entries — but the corpus entries simply **delegate** to L1 checks with a minimized fixture, so the knowledge lives in one place.

### Mapping summary

| Layer | Catches at | Kills |
|-------|-----------|-------|
| L1 validator | commit time | RC1, RC3, #5, #7, #8, docs drift |
| L2 live verify | pre-activation | RC2, RC5, tier/ctx mismatches, activation gaps |
| L3 runbook | process | RC2, RC6, restart discipline |
| L4 hygiene timer | runtime | RC5 early warning |
| L5 corpus | forever | regression memory |

### Evidence-state discipline

L1 lands as `tests_passed` (runs in run_all). L2/L3 claims runtime evidence only when actually executed and captured (per repo Live Deployment Claim Discipline — `runtime_loaded` / `real_project_behavior_proven` require observed runs, not script presence).

---

## 4. Current-State Audit (2026-08-30, prototype L1 run)

15 model references checked across both configs; 26 defined custom models. **9 findings:**

| Finding | Class | Disposition |
|---------|-------|-------------|
| `kimi-for-coding-oauth/kimi-for-coding`: `limit.context` + `limit.output` missing | #5 schema gap | **Intentional** (runtime discovery) → becomes first `RUNTIME_LIMIT_EXCEPTIONS` entry |
| `kimi-for-coding-oauth/k3` | #7 exposure | Fix at implementation: declare `input` explicitly |
| `ollama-cloud/deepseek-v4-flash:0731`, `deepseek-v4-pro:0813`, `minimax-m3` | #7 exposure | Fix at implementation |
| `qwen-tunnel/qwen3.8-27b` | #7 exposure | Fix at implementation |
| `zai-coding-plan/glm-5.3`, `glm-5.3-flash` | #7 exposure | Fix at implementation (probe Z.AI docs for true input limits first — RC2 applies to the fix itself) |

No dangling references, no orphaned provider blocks, no enabled-without-block entries today — those classes are currently clean.

---

## 5. Implementation Plan (follow-up)

1. **Commit 1**: `tests/test_provider_config.sh` + `tests/data/builtin-models.txt` + exception constants (with `kimi-for-coding` entry). Wire = none needed (auto-discovery).
2. **Commit 2**: fix the 7 `limit.input` findings (after live probing each provider's true input limit) + the exception marker for kimi.
3. **Commit 3**: `scripts/verify-providers-live.sh` (activation, catalog probe, stale-process; `--smoke` opt-in).
4. **Commit 4**: `docs/runbooks/add-provider.md` + README/docs cross-refs + L4 timer drop-in.
5. **Commit 5**: regression corpus entries for #5/#7/#8 classes.

Each commit passes `bash tests/run_all.sh` before landing (review-enforcer gate consumes it).
