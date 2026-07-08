# R1 — External Research: Maintaining Local Patches to AI Development Tools

> **Scope.** Facts only, no recommendations. Sources cited inline with URLs and commit/file refs where available.
> Audience: the architecture-debate agent that will synthesize findings against the user's local patch-tracker setup (`.sisyphus/patches/*.md`).
> Method: GitHub repo enumeration via `gh api` + WebSearch + WebFetch. All direct URLs are dated 2026 unless noted.

---

## 0. Quick Index

1. The user's own stack — the `anomalyco/opencode` + `code-yeongyu/oh-my-openagent` ecosystem in numbers.
2. The "patch-tracker" pattern — the user's chosen approach vs. community alternatives.
3. Real OpenCode forks on GitHub (with branch/rebase strategy + pain points).
4. Real oh-my-openagent forks (the user's other half) — four public examples.
5. Direct community sentiment: forking OpenCode/OMO.
6. Direct community sentiment: forking VS Code (Cursor/Windsurf/Void/CortexIDE) — long-term-fork post-mortems.
7. Direct community sentiment: forking Cline → Roo Code → Zoo Code — what happens when the maintainer walks away.
8. Direct community sentiment: Aider/Continue/Pi/Codex — non-fork alternatives.
9. Tradeoff catalogues from authoritative third parties.
10. The "patch lane" / overlay / plugin-overlay pattern in the wild.
11. AI-agent-as-maintainer tooling (Claude Code, OpenCode, Aider) for fork sync.
12. Case study: Cohere's automated vLLM fork (the only published end-to-end case).
13. Direct observations about OMO's own architecture pivot (plugin-first, multi-harness).

---

## 1. The user's own stack in numbers (June 2026)

Source: `gh api repos/anomalyco/opencode` on 2026-06-28.

| Repo | Stars | Forks | Open issues | Default branch | Latest release | License |
|---|---|---|---|---|---|---|
| `anomalyco/opencode` | 180,058 | **22,127** | 7,025 | `dev` | v1.17.11 (2026-06-25) | MIT |
| `code-yeongyu/oh-my-openagent` | 63,775 | 5,217 | 721 | `dev` | v4.12.1+ | SUL-1.0 |

Key facts:
- OpenCode has **22,127 forks** as of 2026-06-28 ([gh API result](https://api.github.com/repos/anomalyco/opencode)).
- 460 contributors to upstream OpenCode; primary language TypeScript (70.2%).
- Built with Bun; release cadence is roughly weekly (release v1.17.10 on 2026-06-24, v1.17.11 on 2026-06-25 — within 24 hours).
- 13,000+ commits and 828 releases across the project's lifetime.
- OMO was originally called `oh-my-opencode` and is dual-published during the rename transition. Compatibility layer in `opencode.json` prefers the new entry `oh-my-openagent` while still loading legacy entries with a warning.
- OMO is **already implemented as an OpenCode plugin**, not a fork. The entire plugin source is in `packages/omo-opencode/src/` and consumes OpenCode's public plugin API (`@opencode-ai/plugin`). This is critical context for the fork debate.

Sources:
- [anomalyco/opencode repo metadata](https://github.com/anomalyco/opencode)
- [code-yeongyu/oh-my-openagent repo metadata](https://github.com/code-yeongyu/oh-my-openagent)
- [code-yeongyu/oh-my-openagent README at ee938aa](https://github.com/code-yeongyu/oh-my-openagent/blob/ee938aa09751de9448e6847af7311304a86e3653/README.md)

---

## 2. The "patch-tracker" pattern — what it is and what alternatives exist

### 2.1 The user's pattern (per `00-plan.md` + `AGENTS.md`)
- Local file: `.sisyphus/patches/*.md` — each file is a **reapply recipe**, not committed code.
- Updates are *not* automated: an AI agent (Sisyphus) reads the recipe and re-applies it on top of a freshly installed OpenCode+OMO.
- A separate `update-to-latest` skill orchestrates the process.

### 2.2 The community has converged on a small number of patterns

| Pattern | What is stored | Where it lives | Examples found |
|---|---|---|---|
| **A. Patch-tracker docs** (user's choice) | Reapply recipes in markdown | `.sisyphus/patches/*.md` | The user (no other public example found with this exact shape) |
| **B. Patch directory + CI** | `.patch` files applied at build time | `patches/*.patch` + `scripts/apply-patches.sh` + GitHub Actions | `turtton/oh-my-openagent`, `smola/opencode`, the `patch-package` ecosystem |
| **C. Full fork + manifest** | The whole diverged source tree + a JSON manifest listing divergences | The fork repo + `.fork-features/manifest.json` | `randomm/opencode`, `reallyjustasquirrel/opencode`, `BOHUYESHAN-APB/openagent-labforge`, `Vacbo/oh-my-opencode` |
| **D. Plugin / npm package** | The customization as a separate npm-distributed package that loads at runtime via the host's plugin API | npm + host's `plugin` array | `oh-my-openagent` itself, `@turtton/oh-my-openagent`, `aider-mcp-server`, `claude-code-redact` |
| **E. config + docs only** | Pure configuration (no code changes) | `AGENTS.md`, `oh-my-openagent.jsonc`, host config files | The dominant pattern for `oh-my-openagent` "Light" edition, most of the `anywhere-agents`-style repos |

### 2.3 The community has also converged on what they call this

- "**Soft fork**" / "**patch-based distribution**": don't fork the source tree, apply patches at build time ([turtton/oh-my-openagent README](https://github.com/turtton/oh-my-openagent))
- "**Hard fork**" / "**long-lived fork**": keep a full diverged tree, rebase on a schedule ([randomm/opencode](https://github.com/randomm/opencode), [Cohere vLLM fork blog](https://cohere.com/blog/automating-fork-maintenance-with-ai-agents))
- "**Plugin-first**": extend via the host's plugin system, never modify the host ([OpenCode plugin docs](https://opencode.ai/docs/plugins/))
- "**Overlay**" / "**patch lane**": keep customizations in a separate directory mounted over upstream at build/run time ([MegaCpp patch lane post](https://megacpp.com/blog/how-we-keep-a-patch-lane/))
- "**Monkey-patching**": replace classes/modules at import time ([vLLM plugin blog](https://vllm.ai/blog/2025-11-20-vllm-plugin-system))
- "**Full fork**" / "**custom build**": track upstream with a hard rebase ([smola/opencode](https://github.com/smola/opencode), [Cohere vLLM case](https://cohere.com/blog/automating-fork-maintenance-with-ai-agents))

---
## 3. Real OpenCode forks on GitHub

The `gh api repos/anomalyco/opencode/forks?per_page=100&sort=stargazers` query returned 100 forks. The five that actually look like *intentional* customizations (not just "star and forget") are:

### 3.1 `smola/opencode` — Soft fork, patch directory, npm-patches only
- Repo: https://github.com/smola/opencode
- Default branch: `smola/staging`
- Created 2026-01-31, last push 2026-04-09
- Stars: 0, Forks: 0 (low visibility)
- 10,967 commits on the staging branch (full mirror of upstream)
- README declares it is a "soft-fork with a small set of targeted changes":
  1. Exposed `OPENCODE_SESSION_ID` and `OPENCODE_TOOL_PART_ID` env vars to child processes
  2. Improved Bash/Grep/Glob guidance
  3. Added a micro-benchmark suite under `benchmarks/`
- Has a `patches/` directory with **2 patches** (both for npm dependencies, not OpenCode source):
  - `@standard-community%2Fstandard-openapi@0.2.9.patch`
  - `solid-js@1.9.10.patch` (a fix from the SolidJS issue tracker for transitions)
- These patches are applied at `bun install` time via the standard `patch-package` flow inherited from OpenCode's own `bun.lock` setup.

**Implication for the user:** the only public "OpenCode soft fork" the researcher could find uses *npm-package* patches, not OpenCode source patches. This is the lighter, more compatible end of the spectrum.

### 3.2 `reallyjustasquirrel/opencode` — Hard fork, nightly rebase via GitHub Actions
- Repo: https://github.com/reallyjustasquirrel/opencode
- Default branch: `hardened`
- Created 2026-04-14, last push 2026-06-23
- 11,161 commits on hardened (full mirror of upstream plus custom commits)
- 1 release tagged
- Adds: a security-hardening layer (permission safety floor, dangerous command detection, shell obfuscation detection, denial tracking, dangerous file lists) — 203 permission tests.
- **CI workflow `.github/workflows/nightly-hardened.yml`** (full source captured during research) is the canonical example of automated AI-tool-fork maintenance:
  - Cron: 04:00 UTC daily
  - Steps: `git fetch upstream dev` → `git reset --hard upstream/dev` on `dev` → `git rebase dev` on `hardened` → if conflict, `gh issue create` with title "Nightly rebase conflict — YYYY-MM-DD" and label "bug", then `exit 1` (no automatic force-push) → on success, typecheck, test, build CLI, package VS Code extension, create prerelease.
  - The conflict path is **human-in-the-loop**: opens an issue, exits 1. The system never auto-resolves with `--theirs` or `--ours`.
- Their README claims: "The `hardened` branch is rebased onto upstream `dev` nightly via GitHub Actions."

**Implication for the user:** this is the upper end of automation. A nightly CI is the boundary of "fully automated for fork maintenance." Anything more complex (semantic conflict resolution, code understanding) is not done here.

### 3.3 `randomm/opencode` — Hard fork with `.fork-features/manifest.json` + AI merge command
- Repo: https://github.com/randomm/opencode
- Default branch: `dev`
- Created 2026-05-15, last push 2026-05-15
- Stars: 2
- Has a directory `.fork-features/` (full content captured during research) containing:
  - `manifest.json` (28KB) — the registry of every intentional divergence
  - `verify.ts` — a Bun test that checks each feature's "criticalCode markers" survived the merge
  - `verify-manifest.mjs` and `verify-critical.mjs` — node-based checkers
  - `reports/` — dated institutional memory
  - `bunfig.toml` and `README.md`
- The manifest schema is rich: each feature entry has `status`, `description`, `issue`, `newFiles`, `modifiedFiles`, `deletedFiles`, `criticalCode[]`, `tests[]`, `upstreamTracking.relatedPRs[]`, `upstreamTracking.relatedIssues[]`, `upstreamTracking.absorptionSignals[]`.
- The README (full text captured) explicitly describes the workflow:
  > "Run `/sync-upstream` inside opencode. What happens: 1. Agent reads manifest.json and last 3 sync reports for context; 2. Fetches upstream and analyzes the gap; 3. Checks absorption signals — if upstream absorbed a feature, STOPS and asks you; 4. Creates sync branch, merges upstream; 5. Resolves conflicts using manifest knowledge (criticalCode markers); 6. Runs verify.ts to confirm all fork features survived; 7. Runs full test suite and typecheck; 8. Writes a dated report to `reports/`; 9. Presents summary and recommends merge if green."
- 11 documented fork features, e.g.:
  - `async-tasks` — background task execution with slot-based concurrency, tracks upstream PRs `anomalyco/opencode#7206` and issues `#5887`
  - `permission-bubbling` — tracks upstream PRs `#12584`, `#12136` and issues `#12566`, `#12133` for "absorption signals"
  - `loop-message-cache` — performance fix for long sessions, has absorption signals like `streamAfter`, `needsFullRefresh`
  - `taskctl` — full autonomous task pipeline with 22 new files and ~25 tests, 5 phases

**Implication for the user:** this is the *most* advanced public fork-governance system found. The `.fork-features/manifest.json` is functionally equivalent to a patch-tracker but stored as JSON with executable verifiers. Their `criticalCode` markers + `absorptionSignals` are a discipline the user's patch-tracker does not enforce.

### 3.4 `latitudes-dev/shuvcode` — Informal fork
- Repo: https://github.com/Latitudes-Dev/shuvcode
- 104 stars, default branch: `integration`
- Description: "unofficial fork of opencode.ai"
- Not deeply analyzed; appears to be an internal-customization fork without public governance docs.

### 3.5 Other notable OpenCode forks
- `leohenon/opencode-vim` (69★) — adds vim mode; appears to use a `ocv` default branch (custom)
- `Jaiminp007/finny` (51★) — re-frames OpenCode as "An AI Financial Harness for systemic trading" (default `dev` branch, last push 2026-06-04)
- `PlunderStruck/opencode` (4★) — for local models, disables parallel tool calls
- `okuyam2y/opencode-nofc` — for providers without native function calling (Hermes/XML tool parser)
- `OneOfLzx/opencode-sentinel` (36★) — security-enhanced, only connects to private AI servers
- `Chetic/opencode-offline` (10★) — "100% offline"
- `connorads/opencode` (48★) — `dev` branch, last push 2026-01-09 (likely abandoned)
- `Patrick-Toulme/opencode` (6★) — adds `/goal`, `/btw`, and "full subagent swarm runtime"
- `hoodini/logan` (5★) — "Logan, the AI Coding Agent. Based on OpenCode, modified by Yuval Avidani (YUV.AI)"
- `bb-deeplearning/codemaxxxing` (5★) — "Clauseo and bbdeeplearning's internal flavour of opencode"
- `kortix-ai/opencode` (4★) — under a `kortix` branch, last push 2026-06-28
- `neat-technologies/neat-opencode` (2★) — "neat fork for autonomous remediation pipelines. Owned by @sguckiran"

### 3.6 Archived OpenCode forks
- `pelidan/opencode` (12★) — archived; default branch `ubuntu2204-builds`
- `stackblitz/opencode` (4★) — archived; default branch `dev`
- `Soul-Brews-Studio/opencode-archived` (9★) — explicitly named "archived"
- `code-yeongyu/opencode` (3★) — the OMO maintainer's own OpenCode fork, last push 2026-06-01 (likely an old experiment)

**Observation:** only 4 of the 100+ star-counted OpenCode forks have public, reusable fork-maintenance infrastructure (smola, reallyjustasquirrel, randomm, BOHUYESHAN-APB). The rest are one-off "I made a personal change" forks.

### 3.7 OpenCode issues that show fork pain from upstream's perspective
- **Issue #21369 — "chore: remove plugin system divergence with upstream"** (closed not_planned, 2026-04-07): the `randomm/opencode` maintainer opened an issue in *their own fork* to remove 6 plugin files (1,505 lines) their fork had stripped. Quoted from the issue body:
  > "Our fork stripped out 6 plugin files (~1505 lines) to simplify the plugin loading system. This divergence: Is NOT tracked in `.fork-features/manifest.json`; Provides no value to our fork; Causes pain during every upstream sync (merge conflicts, manual reconciliation); Violates our principle: 'Keep divergence only in areas where there is value'."
  This is a fork maintainer publicly admitting divergence = sync pain.
- **Issue #14671 — "[FEATURE] Prevent workflows from running in fork repositories"**: documents that *all 27* upstream GitHub Actions workflows execute when forks `git pull upstream dev`, causing CI minutes waste, queued jobs, and broken notifications. The proposed fix is `if: github.repository == 'anomalyco/opencode'` guards.
- **Issue #28463 — "Guard upstream automation workflows from forks"**: same problem from a different angle.

---
## 4. Real oh-my-openagent (OMO) forks on GitHub

OMO is significantly younger than OpenCode, so the fork ecosystem is smaller but growing. Four public forks were identified:

### 4.1 `turtton/oh-my-openagent` — Soft fork, patch directory + CI, **the most directly analogous case to the user's stack**
- Repo: https://github.com/turtton/oh-my-openagent
- Default branch: `main`
- Created 2026-03-18, last push 2026-04-15
- **Archived 2026-04-19** (now read-only)
- 14 npm tags, 37 commits
- Description: "Optimized for GitHub Copilot users"
- **The whole repo is a patch-overlay distribution.** Three files in `patches/`:
  - `001-block-true-waiting.patch` (26,780 bytes — the largest single patch)
  - `002-disable-todo-continuation-enforcer.patch` (522 bytes)
  - `003-skip-guards-for-blocking-tasks.patch` (3,619 bytes)
- Three scripts in `scripts/`:
  - `fetch-upstream.sh` — `git clone --depth 1 --branch $TAG https://github.com/code-yeongyu/oh-my-openagent.git $TMPDIR/upstream`, strip `.git`, move to `./upstream/`
  - `apply-patches.sh` — iterates `patches/*.patch`, runs `patch -d upstream/ -p1 --batch --forward --fuzz=0 --dry-run` first, then applies; bails on any fuzz
  - `build-and-prepare.sh` — runs `bun install --frozen-lockfile` (falls back to `bun install`), `bun run build`, copies `upstream/dist/` to `dist/`, rewrites `package.json` to be `@turtton/oh-my-openagent` with `upstream: { repo: "code-yeongyu/oh-my-openagent", version: "3.12.3" }`
- One CI workflow `.github/workflows/publish.yml` (full content captured):
  - Triggers: push to `main` (when patches/scripts/package.json/.github changes), daily cron `0 9 * * *`, manual `workflow_dispatch`
  - Steps: `Determine upstream tag` (auto via `git ls-remote --tags --sort=-v:refname` if not provided) → `Check if already published` (queries npm registry, computes next `-copilot.N` revision) → if scheduled and already tracking that upstream version, **skip the entire job** (idempotent) → fetch → apply patches → build → publish with `--provenance --tag latest` → update `.upstream-version` file, commit, tag, push.
  - Scheduled cron skips re-runs once the upstream version is tracked (saves CI minutes).
  - Manual `workflow_dispatch` accepts an upstream tag override and a copilot revision override.
  - Uses Node 22.22.1 with the note: "Node 22.22.2 has broken npm (nodejs/node#62425)"
  - Uses OIDC Trusted Publishers for npm provenance.
- Versioning: `<upstream-ver>-copilot.<N>` (e.g. `3.12.3-copilot.1`). The copilot revision number increments for patch-only changes.
- README explicitly says:
  > "This is a patch-based distribution of oh-my-openagent. Instead of maintaining a full fork, we apply targeted patches to upstream source code and publish as `@turtton/oh-my-openagent` on npm. All patches focus on reducing unnecessary premium request consumption that occurs with GitHub Copilot's usage model. The upstream project is automatically tracked, and new releases are published with patches applied via CI."
- The patches modify agent prompts, the background-task manager, and runtime config defaults. The 001 patch is 26KB — a substantial semantic change to how the agent orchestrator waits for results (switches from "end response, wait for system-reminder" to "block=true on background_output").
- Patches use `diff -ruN --no-dereference` and clean-apply to upstream without fuzz (`--fuzz=0`), so the verification is strict — if upstream moves, the patch fails and the CI exits 1.

**Implication for the user:** this is **the exact pattern** for what the user is building, minus the `npm publish` step. The CI architecture is reproducible by replacing the npm publish steps with `git commit && git push` to a patches branch.

### 4.2 `BOHUYESHAN-APB/openagent-labforge` — Hard fork with `upstream-audit` document
- Repo: https://github.com/BOHUYESHAN-APB/openagent-labforge
- Default branch: `main`
- Created 2026-03-07, last push 2026-06-25
- 0 stars, 0 forks
- A full fork of OMO with a `docs/release/` directory:
  - `upstream-oh-my-openagent-3.11-plus-audit.md` (5,238 bytes, full content captured): an **upstream audit document** that lists, for each upstream release from v3.11.0 to v3.14.0, the candidate items that may need porting into the fork. Each release is a checklist of features/fixes to consider.
  - `upstream-publish-notes.md` (1,143 bytes)
  - `rebrand-plan.md` (2,586 bytes)
  - `research-packaging-architecture.md` (2,273 bytes)
- The audit document's "Next pass" section explicitly orders:
  > "Recommended implementation order: 1. runtime correctness fixes; 2. config and path-discovery parity; 3. background-agent / continuation guard parity; 4. command and skill discovery parity; 5. packaging / doctor / release workflow parity."
- Candidate items include specific upstream features: "ULW-loop Oracle verification requirement", "GPT-5.4-first prompt routing", "Atlas Final Verification Wave orchestration logic", "smart circuit breaker in background-agent manager", "background-task fallback-chain registration", "writable-directory fallback for data/cache paths", "MCP OAuth callback port binding robustness", "permission merge-order fix preserving explicit deny", and many more.

**Implication for the user:** this is the **explicit upstream-changelog-tracking pattern**. The audit doc is human-maintained per upstream release, and is the closest analogue to a patch-tracker that *also* tracks when patches become obsolete (upstream absorbed them).

### 4.3 `Vacbo/oh-my-opencode` — Hard fork with AI-driven 3-pass sync pipeline
- Repo: https://github.com/Vacbo/oh-my-opencode
- Default branch: `main`
- Recent commit: 2026-04-21 — "docs: fork sync methodology + deviation register (#52)"
- Adds three CI workflows and a deviation register:
  - `upstream-tag-watcher.yml` — watches for new upstream tags
  - `upstream-analyzer.yml` — 3-pass AI classifier: Pass 1 classifies each upstream commit as GOOD / NEEDS_REVIEW / SLOP, Pass 2 verifies SLOP candidates with a stronger model, Pass 3 synthesizes release cost-benefit summary
  - `publish.yml` — builds and publishes `@vacbo/oh-my-opencode` to npm (main package + 11 platform binaries + GitHub release)
  - `sync-upstream.yml` — **disabled**, kept for reference
- The deviation register lives at `docs/fork-deviations.md` (analogous to the user's `.sisyphus/patches/*.md`).
- The commit message includes the operational state:
  > "Published version: @vacbo/oh-my-opencode@3.18.0; Last upstream tag synced (upstream-version.txt): v3.17.0; Latest upstream stable tag: v3.18.0; Fork dev vs upstream/dev: 43 ahead / 60 behind; Sync pipeline: upstream-tag-watcher.yml + upstream-analyzer.yml (3-pass AI classifier); Release pipeline: publish.yml (main package + 11 platform binaries + GitHub release); Legacy pipeline: sync-upstream.yml — disabled, kept for reference"
- The 3-pass pipeline cherry-picks into `sync/upstream/{tag}-{good|review|slop}` branches. Fork-only fixes must not land on `sync/upstream/*` branches — those are reserved for upstream cherry-picks.
- Commit types are tracked per commit: `sync-cherrypick` (already upstream, not yet rebased-over) vs `fork-only-fix` (not present upstream, marked Try-to-upstream or Never-upstream).
- The legacy `sync-upstream.yml` is explicitly described as "superseded by analyzer."

**Implication for the user:** this is the **most automated** OMO fork-sync pattern found. The 3-pass AI classifier + `docs/fork-deviations.md` register is functionally what the user's patch-tracker would look like at full automation.

### 4.4 `allOwO/opencode-codex-orch` — Hard fork derived from OMO
- Repo: https://github.com/allOwO/opencode-codex-orch
- Default branch: `main`
- Created 2026-03-20
- Description: "Multi-agent orchestration plugin for OpenCode. Multiple models, multiple agents, one coordinated team. This project is derived from oh-my-openagent (omo) and its slim variant oh-my-opencode-slim (omo-slim). It has been purpose-built for OpenAI Codex: all Anthropic/Claude-specific logic, prompts, and model routing have been stripped out, leaving a lean, GPT/Codex-focused orchestration core."
- Includes a "merge-upstream" skill — "guided upstream merge workflow that preserves fork identity, slim architecture, and Codex-first design decisions."

**Implication for the user:** an example of an OMO fork that *removes* a major feature (Anthropic/Claude support) rather than adding. The cost of divergence is the same.

### 4.5 `mpazik/openagent` — Hard fork, adds "agent and tools support"
- Repo: https://github.com/mpazik/openagent
- Default branch: `agent-support`
- 9 stars
- Last push 2025-09-08 (older; possibly abandoned)

### 4.6 The pattern: 4 distinct OMO-fork maintenance strategies in 6 months
| Fork | Strategy | Automation level | Status |
|---|---|---|---|
| `turtton/oh-my-openagent` | Patch overlay + CI rebuild | Daily CI, auto-publishes to npm | Archived 2026-04-19 (after ~1 month) |
| `BOHUYESHAN-APB/openagent-labforge` | Hard fork + manual audit doc | Manual | Active (low activity) |
| `Vacbo/oh-my-opencode` | Hard fork + 3-pass AI sync | AI-driven | Active |
| `allOwO/opencode-codex-orch` | Hard fork + merge-upstream skill | AI-assisted | Active |

**No two of the four use the same approach.** This is direct evidence that the OMO-fork community has not converged on a single pattern, and that the "right answer" depends on the fork's goals.

---
## 5. Direct community sentiment: forking OpenCode

### 5.1 The OpenCode maintainers' position
- The OpenCode plugin system (the one OMO uses) was introduced in response to Issue #753 ("Feature Request: Extensible Plugin System for OpenCode" by ChrisKotsis, 2025-07-08). The issue body explicitly states:
  > "Currently, teams need to fork OpenCode to add these specialized features, which creates maintenance challenges and makes it harder to benefit from upstream improvements."
- The maintainers' reply, via `thdxr`:
  > "We want just about everything to be fully customizable, but some of our plugin system still needs some improvements: notably a UI plugin system so you can customize the tui to your liking; also there are more hooks for the backend that we should add to allow additional customization."
- Several community requests have been filed and explicitly closed/declined with the message "this belongs in a plugin":
  - #19919 (UI extensibility for plugins)
  - #17492 (TUI customization)
  - #6330 (Generic UI Intent Channel)
- The "Plugin Mesh Architecture with 8 Infrastructure Layers" feature request (Issue #13957, NikolaySt, 2026-02-17) — **closed** — was an attempt to provide enough plugin power that no fork would be needed. The author proposed 8 new layers: Bus, Channel Adapters, Cron, Router, Pipeline, Tool Decorators, Gateway RPC, Stream Transforms. The PR description (which the issue references) is 257 tests passing — but the issue is closed, suggesting the maintainers are not committing to this expansion now.
- 28+ open issues request "more plugin hooks" so the requester can stop forking:
  - #10868 (Storage, Schema, TUI, and Command Registration hooks): "It's a hassle to keep the project aligned with the latest commits. I've implemented it (with Opus) directly in the source code since there's no hook to make use of."
  - #19428 (improve plugin development support): enumerates 4+ related issues and PRs
  - #20034 (UI Plugin API for rendering custom components in message parts)
  - #19919 (Frontend UI extensibility for plugins)
  - #5148 (Comprehensive Plugin Pipeline - Middleware-Style Data Flow Control): "every penny spent here is a dime in savings" (from the requester)
  - #6521 (Window System as Foundation for UI Plugin Ecosystem)

### 5.2 The official OpenCode position: "plugin-first"
- The official docs page (https://opencode.ai/docs/plugins/) describes plugins as the supported extension model.
- An OpenCode maintainer wrote (in response to a fork plea):
  > "We want just about everything to be fully customizable" but explicitly disclaimed UI/plugin-API completeness.
- The OMO team (code-yeongyu) has bet on this — they ship OMO as a plugin, not a fork, and have a public ROADMAP to extend the plugin surface further.

### 5.3 OMO's own positioning
- OMO is officially a plugin that extends OpenCode. From the AGENTS.md:
  > "OpenCode plugin (npm: `oh-my-opencode`, dual-published as `oh-my-openagent` during the rename transition) extending OpenCode with 11 agents, 53-60 lifecycle hooks (base / +team-mode) across 60 dirs, 20-39 tools (gated by config flags including team-mode), 3-tier MCP system (built-in + .mcp.json + skill-embedded), Hashline LINE#ID edit tool, IntentGate keyword detector, Team Mode (parallel multi-agent coordination, OFF by default), Boulder feature (boulder-state work tracking + cli/boulder subcommand), configurable agent ordering, and Claude Code compatibility."
- OMO has a "Multi-Harness Agent OS Refactor in Progress" ROADMAP (per the README at the top of the repo):
  > "We are restructuring the codebase to support multiple agent harnesses (OpenCode, Codex, Pi, Claude Code, and others). The most urgent work is the package layering refactor: separating pure TypeScript core logic, MCP servers, skills, and adapter shims into distinct layers so the same logic can be reused across harnesses without duplication."
- OMO ships two editions of one product: **Ultimate** (OpenCode plugin) and **Light** (Codex CLI portable components via `lazycodex-ai`). The same code powers both — the Layer/Adapter pattern is real, not aspirational.
- OMO's plugin system relies on the OpenCode public API. When that API changes (e.g. the v1.3.8 plugin loader regression, see below), OMO users hit breakage.

### 5.4 Recent OpenCode regressions that hurt OMO
- Issue #20139 (2026-03-30): v1.3.8 broke all npm plugins. The new `oc-plugin` field in package.json was required, breaking `oh-my-opencode-slim`, `opencode-mystatus`, and `superpowers`. Fixed in v1.3.9. This is a concrete example of the "plugin API changes break downstream" cost.
- Issue #20203 (2026-03-31): `deduplicatePlugins` silently removes plugins whose entry point is `dist/index.js` — 7+ duplicate-tracking issues filed (#8759, #10115, #11159, #12285, #14304, #17716).
- Issue #20149 (2026-03-30): npm plugin loader rejects `package.json` main entries without `./` prefix.
- Issue #31463 (2026-06-09): "Plugin import hangs silently when resolving npm specifiers (e.g. oh-my-openagent@latest)" — the Npm.add() reify() deadlocks silently on cold cache. This is *the* user's OMO plugin hanging on first run after a clear.
- Issue #22452 (2026-04-14): `opencode plugin <new-version>` requires `--force` to upgrade; output is confusing.

### 5.5 OMO issues that show the "OMO replaces OpenCode" tension
- Issue #5156 (2026-06-11): "Allow default OpenCode agents to coexist with OMO agents". The user describes:
  > "Installing oh-my-openagent replaces the stock OpenCode agents (`OpenCode-Builder`, `plan`, `build`, etc.) entirely. There is no way to keep both OMO's specialized agents (Sisyphus, Oracle, Librarian, Explore, etc.) and the default OpenCode agents available for selection."
  > "In `agent-config-assembly.ts`, `assembleSisyphusEnabledConfig()` builds `config.agent` from scratch using only OMO's builtin agents + user-defined agents (with protected-name filtering). The original `config.agent` entries from stock OpenCode are not carried through, so they are silently dropped."
- This is a side effect of OMO's plugin-not-fork architecture: OMO's override of OpenCode's agent config is all-or-nothing, even though both are theoretically independent.

### 5.6 OMO's own ROADMAP publicly stated
From the OMO README at the top of the repo:
> "Multi-Harness Agent OS Refactor in Progress: We are restructuring the codebase to support multiple agent harnesses (OpenCode, Codex, Pi, Claude Code, and others). If you are interested in contributing, please read the ROADMAP first. PRs related to roadmap work should use the ROADMAP label."

This signals: OMO is investing in *not* being OpenCode-specific. The user is betting on a project that is intentionally making itself portable.

---
## 6. Direct community sentiment: forking VS Code (Cursor/Windsurf/Void/CortexIDE)

The IDE-side of "forking an AI tool" has a richer public history of long-term-fork post-mortems.

### 6.1 The Cursor/Windsurf case (ox.security report, 2025-08-28)
Source: [https://www.ox.security/blog/the-curse-of-the-fork-when-patching-is-not-trivial/](https://www.ox.security/blog/the-curse-of-the-fork-when-patching-is-not-trivial/)
- Both Cursor and Windsurf are forks of VS Code.
- As of 2025-08-28, they were both based on **VS Code 1.99.3** — four minor versions behind the current 1.103.2.
- They were running Chromium versions **six major releases behind** the latest.
- VS Code itself maintains an up-to-date Chromium dependency, but the forks inherited an old version and never rebased it.
- 80+ cataloged CVEs in the embedded Chromium; the forks' transitive dependency is the security debt.
- Quote:
  > "While major vendors like Microsoft promptly patch their products, patches for forked products with actively exploited vulnerabilities found in the wild are often significantly delayed."

### 6.2 The Eclipse Foundation position (Thomas Froment, 2025-12-09)
Source: [https://blogs.eclipse.org/post/thomas-froment/why-cursor-windsurf-and-co-fork-vs-code-shouldnt](https://blogs.eclipse.org/post/thomas-froment/why-cursor-windsurf-and-co-fork-vs-code-shouldnt)
> "Forks come with hidden costs: ongoing rebasing, licensing puzzles, marketplace restrictions, and dependence on Microsoft's governance."
> "Recent events have made this more concrete. In 2025, Microsoft extensions like the C and C++ tooling stopped working in Cursor and other forks, due to licensing and distribution enforcement."
> "Almost all forks... You either lag behind upstream, users notice, or you staff an ongoing rebasing team, expensive."
> "Eclipse Theia and Open VSX are hosted by the Eclipse Foundation, which means vendor neutral governance, transparent IP management, and community driven roadmaps."

### 6.3 The Void/CortexIDE case
- `voideditor/void` — "We've paused work on the Void IDE (this repo) to explore a few novel coding ideas. We want to focus on innovation over feature-parity. Void will continue running, but without maintenance some existing features might stop working over time."
- `OpenCortexIDE/cortexide` — a fork of Void (which is a fork of VS Code), tracking VS Code 1.118.1.
- Quote: "A fork of Void, which itself is a fork of the VS Code repository (currently tracking VS Code 1.118.1). We acknowledge and thank both projects for their foundational work."
- This is a fork-of-a-fork-of-VS Code. The cumulative technical debt is implied.

### 6.4 The stochastic sandbox "The Stack — Cursor" analysis (2026-03-30)
Source: [https://stochasticsandbox.com/posts/the-stack-2026-03-30/](https://stochasticsandbox.com/posts/the-stack-2026-03-30/)
> "Cursor's deep VS Code fork is both their moat and their most significant liability. By forking rather than building a plugin, they can instrument the editor at a level no plugin can match — but they've committed to permanently tracking VS Code's release cadence while also maintaining their own feature layer on top. Every upstream VS Code update is a potential merge conflict."
> "This tradeoff becomes more expensive as the product matures. In 2024-2025, moving fast on a fork made sense. By 2026, they're carrying meaningful technical debt from two years of divergence, and competitors building natively on the Language Server Protocol (LSP) or on cleaner abstractions are starting to close the feature gap."

### 6.5 The Substack "How Cursor Actually Works" deep dive (2026-02-27)
Source: [https://theaiengineer.substack.com/p/how-cursor-actually-works](https://theaiengineer.substack.com/p/how-cursor-actually-works)
> "Cursor's founders made the fork decision in 2022. Aman Sanger, Sualeh Asif, Michael Truell, and Arvid Lunnemark, all from MIT, built Cursor as a direct fork of VS Code's open-source codebase. This gave them full control over the editor's rendering pipeline, file system hooks, and extension host. Every AI feature in Cursor, from speculative tab completions to Shadow Workspace to Background Agents, required editor-level access that no plugin API provides."
> "A wrapper or plugin can only use what VS Code's extension API exposes. A fork means compiling and shipping your own editor binary, with full control over internals. The distinction matters: wrappers add features on top. Forks change what's underneath."
> "The tradeoff: every time Microsoft updates VS Code, Cursor has to merge upstream changes into a diverging codebase. That's real engineering overhead. But it's the price of building features that are architecturally impossible as plugins."

---
## 7. Direct community sentiment: forking Cline → Roo Code → Zoo Code

This is the single most data-rich case of an AI-tool fork lifecycle.

### 7.1 Timeline
- Cline: launched by saoudrizwan, 2024. Apache 2.0. 5M+ VS Code installs as of 2026-06. 58K+ stars.
- Roo Code: forked from Cline in late 2024 (originally "Roo Cline"). Added custom modes (Code, Architect, Ask, Debug, Orchestrator), diff-based editing, multi-agent personas. 22K+ stars.
- Roo Code was **shut down 2026-05-15** by the Roo Code Inc. team.
- The Roo Code GitHub repo (RooCodeInc/Roo-Code) is **archived as read-only**. Final version v3.54.0. The product site roocode.com now redirects to Roomote.
- ZooCode (`Zoo-Code-Org/Zoo-Code/`) is a community fork started by the Roo Code community to continue the project.

### 7.2 What fork maintainers say
- Multiple comparison pieces (Morph, Pickuma, aicoolies, CodePick, myaiverdict, AutoKaam) all document the same tension:
  - Roo Code "tends to ship experimental knobs quickly. Cline tends to move more conservatively on its core loop."
  - The Roo Code custom-mode YAML schema is "undocumented in the visible UI" (AutoKaam).
- "The big disadvantage of forking... moving fast on a fork made sense. By 2026, they're carrying meaningful technical debt from two years of divergence."
- "Do not adopt archived Roo Code without a maintenance plan." (aicoolies)
- "Cline is the safer default for most new users because Roo Code was shut down" (aicoolies)
- "Roo Code's strongest governance idea was Custom Modes" — "That is useful, but archived status makes it risky as a new standard unless a maintained fork carries the same ideas forward."

### 7.3 The Roo Code → SKILL.md skills format
- The Roo Code custom-modes system inspired a SKILL.md format (in `.roo/skills/`) that the Cline team later **adopted directly** in 2026.
- The migration path documented in Cline's skills guide:
  > "Roo Code, the most popular Cline fork, shut down on May 15, 2026. That pushed its user base back to Cline... If you were using Roo Code with SKILL.md skills, the migration is straightforward. If you are new to Cline, skills are one of the reasons it's worth trying. Project skills: `.cline/skills/` in your repository root. Personal skills: `~/.cline/skills/` in your home directory."
- This is a concrete example of "upstream absorbed the fork's innovation."

### 7.4 The pattern: fork → shutdown → upstream absorbs → everyone migrates back
- Continue: acquired by Cursor 2026-06-18 (Apache 2.0 code remains; ongoing maintenance from Continue team ends)
- Roo Code: shut down 2026-05-15
- AutoGen (Microsoft): in maintenance mode; recommends users move to Microsoft Agent Framework
- AG2 (`ag2ai/ag2`): community fork continues the lineage under Apache 2.0

---
## 8. Direct community sentiment: Aider / Continue / Pi / Codex

### 8.1 Aider
- Aider (`Aider-AI/aider`, Paul Gauthier, 46,355 stars, 4,604 forks) is **deliberately not forking-friendly** — it expects users to configure it, not modify it.
- The FAQ explicitly says: "License: Apache 2.0. Free to use, fork, and modify." But the Aider community standard workflow is to write `.aider.conf.yml`, `.aiderignore`, and conventions files rather than fork.
- Aider's customization points (per the FAQ): `.aider.conf.yml`, `.aiderignore`, coder subsystems in `aider/coders/`, edit formats (`--edit-format whole|diff|udiff`).
- Aider has no native MCP support; the workaround pattern is third-party servers (`disler/aider-mcp-server`, `sengokudaikon/aider-mcp-server`, `lutzleonhardt/mcpm-aider`).
- The Aider-AI/aider forks on discofork.ai show 10 community forks with consistent "Prefer upstream unless..." warnings:
  - `dwash96/cecli` — "Stick with upstream if you value maximum compatibility"
  - `quinlanjager/aider` — "Skip it if you want the most current upstream release train and the lowest maintenance risk"
  - `ntegrals/aider` — "This fork looks more like an abandoned or private customization branch than a healthy alternative distribution"
  - `joshuavial/aider` — "the maintenance burden and missing upstream progress make this a poor default choice"
- The Quinlanjager/Aider fork pattern is the most common: "MCP support" → not yet merged upstream → use NixOS package overrides to use the experimental fork (`overridePythonAttrs`).

### 8.2 Continue (acquired by Cursor 2026-06-18)
- Continue: "Continue has been acquired by Cursor... It's been an honor to work and build with the Continue community."
- PearAI is the most visible example of building on Continue: "PearAI built on Continue as a submodule and marketed an open, multi-model IDE experience. With upstream frozen, PearAI and similar projects inherit the full maintenance burden."
- The acquisition did not change the Apache 2.0 license on existing releases.
- Recommendation: "Pin 2.0.0 if you need stability while you evaluate alternatives. Audit whether PearAI, Cursor, or an internal fork fits your compliance and editor requirements."

### 8.3 Pi
- Pi (`earendil-works/pi`): local-first MIT-licensed alternative to Cursor. "100% local (no telemetry)".
- Marketed as a terminal agent that runs in any terminal.
- Claim: "zero IDE lock-in" because no proprietary fork.
- Pi's own positioning vs. forks:
  > "Cursor: The AI-native IDE — a proprietary fork of VS Code with built-in model inference and codebase indexing. Organisations migrate to Pi to escape per-seat pricing, the proprietary IDE fork, and opaque data handling policies that send source code through vendor infrastructure."

### 8.4 OpenAI Codex CLI
- Codex has an official plugin system (https://developers.openai.com/codex/plugins/build).
- Plugin format: `.codex-plugin/plugin.json` manifest + `skills/`, `hooks/`, `.app.json`, `.mcp.json`.
- The "Light edition" of OMO (via `lazycodex-ai`) is the example: ships 8+ components (rules, comment-checker, git-bash, lsp, ultrawork, ulw-loop, start-work-continuation, telemetry) into Codex's plugin system.

### 8.5 Gemini CLI
- Gemini CLI has an "Extensions" system (https://geminicli.com/docs/extensions/writing-extensions/).
- An extension is a "shipping container" bundling MCP servers, context files (`GEMINI.md`), custom slash commands, tool restrictions, agent skills, hooks, custom themes.
- "Before Extensions, customizing the CLI often involved manually editing configuration files like `settings.json`, a process that could be 'messy and error-prone'."
- Install: `gemini extensions install <github-url>`.

### 8.6 Claude Code
- Plugins (https://code.claude.com/docs/en/plugins) are the unit of distribution: skills + agents + hooks + MCP servers + LSP servers.
- Skills are the most portable primitive — they conform to the `agentskills` spec (markdown with YAML frontmatter) and are read by Cursor, Codex, Cline, and Gemini CLI.
- Plugins live in `~/.claude/plugins/<name>/` and reference each other with `${CLAUDE_PLUGIN_ROOT}`.

---
## 9. Tradeoff catalogues from authoritative third parties

### 9.1 The patch-package / fork-pattern ecosystem (Andrew Nesbitt, 2026-05-01)
Source: [https://nesbitt.io/2026/05/01/patching-and-forking-in-package-managers.html](https://nesbitt.io/2026/05/01/patching-and-forking-in-package-managers.html)
- System package managers "are designed around the assumption that carrying patches is part of the job."
- Language package managers "were designed around the assumption that it shouldn't be."
- Three have built-in patch support: pnpm (`pnpm patch <pkg>`), Bun (`bun patch <pkg>`), Composer (`cweagans/composer-patches`, `vaimo/composer-patches`).
- npm and Yarn Classic: third-party `patch-package` (https://www.npmjs.com/package/patch-package). "Patches created by patch-package are automatically and gracefully applied when you use npm(>=5) or yarn."
- For Rust: third-party `cargo-patch` crate, or `patch-crate` (edit in place, generate diff).
- Bundler, Go, uv, Poetry, Mix, Swift PM, NuGet, Stack, Cabal: no patch-file mechanism. pip has `patch-package`. Pub has `patch_package`. Gradle has `brambolt/gradle-patching` (not widely adopted).
- Quote:
  > "Both approaches bring their own maintenance burden. A fork needs to stay in sync with upstream changes unrelated to the vulnerability. GitHub forks have issues, Actions, Dependabot, and security features all disabled by default, so a fork needs manual setup before it works as a proper maintained project. For a two-line security fix, that's a lot of infrastructure to carry."

### 9.2 The vLLM plugin-system blog (2025-11-20)
Source: [https://vllm.ai/blog/2025-11-20-vllm-plugin-system](https://vllm.ai/blog/2025-11-20-vllm-plugin-system)
Direct comparison: "Option B — Maintain your own vLLM fork" is documented as:
> "Maintaining a long-running fork means: ❌ Constantly rebasing or merging upstream changes; ❌ Resolving conflicts on rapidly changing areas; ❌ Reapplying your patches manually; ❌ Performing heavy compatibility testing; ❌ Managing internal developer workflows around a custom vLLM artifact."

Monkey-patching is documented as:
> "Monkey patching typically requires replacing entire classes or modules, even if you only want to change ten lines. This means... forces you to diff and re-sync your files - exactly the same problem as a fork, just disguised inside your Python package."

The plugin system is the recommendation:
> "Use the plugin system, I created a small extensions package that acts as a container for all custom modifications. Instead of replacing entire modules or forking the whole repository, each patch: Contains just the exact code snippet or class that needs to change; Can be enabled or disabled at runtime; Can specify minimum supported vLLM versions; Can remain dormant unless a specific model config requests it. Because plugins are applied at runtime, we maintain a single, unified container image for serving multiple models while selectively enabling different patches per model."

### 9.3 The MegaCpp "How we keep a patch lane" blog (2026-04-18)
Source: [https://megacpp.com/blog/how-we-keep-a-patch-lane/](https://megacpp.com/blog/how-we-keep-a-patch-lane/)
The exact pattern the user is building, with explicit guidance:
> "The second layer is a small, deliberate set of local forks or overlays. The rule is straightforward: only carry a fork when there is a real diff to justify it, and every carried change needs a retirement condition."
> "We tried to carry every Megatron fix as a full fork. That worked, but rebasing against a moving development branch became too expensive for changes that were often very small. We kept fuller forks where the diff justified them and used lighter overlays elsewhere."
> "We also kept three hard rules: every local patch must be tracked, every tracked patch needs a retirement condition, and nothing retires silently."
> "Pinned environments are the source of truth. No lockfile heroics, and installs should not drift underneath you."
> "Carry full forks only when the diff is substantial; use lighter overlays for genuinely small surgical fixes."
> "Every local patch needs a matching public-facing entry with a reproducer and a readable explanation."
> "Only when a narrow, reviewable diff is carrying a real runtime or correctness win and a lighter overlay cannot express it honestly."

### 9.4 The CuriousBox blog "The Fork in the Road" (2025-04-19)
Source: [https://blog.curiousbox.ai/p/the-fork-in-the-road-why-vs-code](https://blog.curiousbox.ai/p/the-fork-in-the-road-why-vs-code)
- "Forking VS Code often starts as a small change... However, over time, the gained freedom is typically used and changes to the fork accumulate. As a consequence, maintaining compatibility with the rapidly evolving VS Code codebase becomes increasingly challenging." — EclipseSource
- "Guaranteed marketplace access: As a native extension, ProdE users maintain access to the complete VS Code extension ecosystem."
- "Security benefits: Operates within VS Code's security model rather than creating a new attack surface."

### 9.5 The Dify community thread (langgenius/dify Discussion #32446)
Source: [https://github.com/langgenius/dify/discussions/32446](https://github.com/langgenius/dify/discussions/32446)
Multiple community responses converge on:
- "Git submodules for custom components - keeps them separate from core"
- "CI/CD pipeline that applies patches after pulling upstream"
- "Semantic versioning your customizations - helps track breaking changes"
- "Treat customizations as a separate layer, not inline modifications. This makes upgrades much smoother."
- "Rebase your fork weekly (small conflicts better than big ones)"
- "Never commit upstream changes to your branch"
- "Use git rerere to remember conflict resolutions"
- "Mount these at build time or runtime" (overlay approach)
- "Keep upstream untouched. Apply customizations as an overlay layer at build time. This makes upgrades a matter of rebuilding, not resolving conflicts."

### 9.6 The Nick Desaulniers "Forking is not free" post (2023-02-01, still widely cited)
Source: [https://nickdesaulniers.github.io/blog/2023/02/01/forking-is-not-free-the-hidden-costs/](https://nickdesaulniers.github.io/blog/2023/02/01/forking-is-not-free-the-hidden-costs/)
> "The process of updating a fork is known as 'rebasing,' re-establishing the point at which a fork first diverged. Depending on how much work was done on the mainline vs the fork... the work involved in rebasing will be directly proportional to the distance of the divergence."
> "In this way, developing software from a fork is a source of accumulation of tech debt; it may not cost you anything today. But should you ever plan to rebase your software, you will pay for it."
> "If the number of upstream changes... Given a timespan and planned frequency of rebasing, you can calculate the number of rebases in a time frame. If no rebases are planned, the cost goes to zero (i.e. parking a fork, cutting a release). More rebases means more pain."

### 9.7 "Your Fork Will Outlive Your Patience" (DEV Community, 2026-02-16)
Source: [https://dev.to/microseyuyu/your-fork-will-outlive-your-patience-a-systems-thinking-post-mortem-56pk](https://dev.to/microseyuyu/your-fork-will-outlive-your-patience-a-systems-thinking-post-mortem-56pk)
> "Every internal fork starts as a one-liner: 'we just need to fix this one file.' Six months later you're maintaining four parallel repositories, dreading each release, and spending more time keeping forks alive than building the thing they were supposed to enable."
> "A fork is a liability, not an asset. The moment you fork, you've created a maintenance obligation that grows with every upstream commit. If you can't get your changes upstream within a bounded timeframe, you are accumulating structural debt that compounds."

### 9.8 The OpenCode plugin docs page (https://opencode.ai/docs/plugins/)
> "Plugins allow you to extend OpenCode by hooking into various events and customizing behavior. You can create plugins to add new features, integrate with external services, or modify OpenCode's default behavior."
> "npm plugins are installed automatically using Bun at startup. Packages and their dependencies are cached in `~/.cache/opencode/node_modules/`."
> "Local plugins and custom tools can use external npm packages. Add a `package.json` to your config directory with the dependencies you need."

### 9.9 The "Vendor Independence for AI Coding Tools" guide
Source: [https://learntoprompt.org/guides/vendor-independence.html](https://learntoprompt.org/guides/vendor-independence.html)
> "Coding tools change fast. Product... change, plugin systems change, marketplaces change, hook... change, and... only inside one vendor... plugin manifest or one... you do not really own your..."
> "Plugins are still useful. They are just not where your logic should live. Not 'pick one and hope.' Make the manifest disposable. The plugin manifest should describe the shared workflow, not contain the only copy of it."

### 9.10 The "Plugin Feature Comparison Grid" by johnlindquist (2026-03-03)
Source: [https://gist.github.com/johnlindquist/217aaa5023879dfa9bc654c7d7ad0260](https://gist.github.com/johnlindquist/217aaa5023879dfa9bc654c7d7ad0260)
Compares Claude Code, Cursor, Codex CLI, OpenCode, Gemini CLI, Windsurf, VS Code / Copilot, Aider, and "Open Plugin" on plugin capabilities. The OpenCode row shows: "Plugin manifest/metadata: yes (Open Plugin-compatible manifest)" — i.e. OpenCode has aligned its plugin format with a cross-vendor spec.

---
## 10. The "patch lane" / overlay / plugin-overlay pattern in the wild

### 10.1 Dify customizations (Revolution AI)
- White-label fork with overlay approach
- "mora-overlay/web/i18n/fa-IR/" + "mora-overlay/web/components/" + "mora-overlay/api/extensions/"
- "Docker Compose overlay pattern: Mount your custom files over upstream in docker-compose.override.yml"

### 10.2 DreamServer `FORKABILITY.md`
Source: [https://github.com/Light-Heart-Labs/DreamServer/blob/main/dream-server/docs/FORKABILITY.md](https://github.com/Light-Heart-Labs/DreamServer/blob/main/dream-server/docs/FORKABILITY.md)
- "For smaller changes, prefer extensions, model catalogs, presets, and docs over patching installer internals. A small extension is easier to keep current than a large fork."
- "**Fork-and-pin:** start from a tagged release or audited commit, apply a small downstream layer, and update only on a cadence you control."
- "**Fork-and-mirror:** operate your own mirror of the repository and allowed artifacts, then merge selected upstream tags or commits after local validation."
- The "Forkability" model explicitly recommends: "record upstream commit or release tag last merged; changed defaults; added, removed, or disabled services; hardware assumptions; model and image pins; private patches to installer, CLI, compose, or dashboard code; validation commands and fleet receipts used after each upstream merge."

### 10.3 The "forkable" checklist (from FORKABILITY.md)
A fork should be:
- `forkable`
- `permission; customizable through extension points`
- `reproducible from pinned dependencies and mirrored artifacts`
- `validated through repeatable public and private test`
- The high-risk change map documents the specific files that are safe to modify: `install-core.sh`, `installers/phases/*`, `dream-cli`, `installers/lib/compose-select.sh`, `scripts/resolve-compose-stack.sh`, `docker-compose.base.yml` and hardware overlays, dashboard-api auth, host-agent, extension install routes, generated config writers for `.env`, LiteLLM, Hermes, OpenCode, and Perplexica.

### 10.4 Anywhere-agents pattern (yzhao062/anywhere-agents)
Source: [https://github.com/yzhao062/anywhere-agents](https://github.com/yzhao062/anywhere-agents)
- "A maintained, opinionated configuration for Claude Code and Codex that follows you across every project, every machine, every session."
- Pattern: "anywhere-agents publishes one curated, maintained configuration that any project inherits in two lines of setup. The maintainer improves one file; every consuming repo picks it up on the next session."
- "Git is the subscription engine. `git pull` gets updates. Fork and `git merge upstream/main` if you want to diverge."
- For Claude Code: "updates are automatic. anywhere-agents installs a SessionStart hook that runs bootstrap every time you open a Claude Code session."
- "To pin to a specific version, fork the repo and check out a tag in your fork, then point consumers at your fork instead of the main branch."
- This is the **single-file / config-only** pattern: don't fork the tool, fork the *config pack*.

---
## 11. AI-agent-as-maintainer tooling (the AI-fork-sync ecosystem)

This is the most rapidly evolving space and is the most directly relevant to the user's "AI agent as maintainer" question.

### 11.1 Cohere's automated vLLM fork (the only published end-to-end case study)
Source: [https://cohere.com/blog/automating-fork-maintenance-with-ai-agents](https://cohere.com/blog/automating-fork-maintenance-with-ai-agents)
- The Cohere team maintains a long-lived fork of vLLM (for serving their `cohere-transcribe-03-2026` ASR model).
- "Maintaining a long-lived fork of an actively developed project is a recurring cost. But upstream releases also carry features, performance improvements, and bug fixes that you want."
- Their 3-step loop: Sync → Measure (tests, benchmarks, evals) → Fix (conflicts, adapt to API changes, update tests).
- They evaluated merge, cherry-pick, rebase:
  > "Merge preserves both histories, but produces a tangled commit graph... Cherry-pick gives precise control, but doesn't scale when upstream moves hundreds of commits per release; you end up maintaining a growing list of picks that drifts out of sync. Rebase replays your custom commits on top of the new upstream tag, producing a clean, linear history where your patches sit clearly on top. The tradeoff is that rebase rewrites history and forces a force-push, but for a fork with a small number of custom commits on top of a fast-moving upstream, the clarity is worth it."
- Their agent skill pipeline:
  1. Detect which upstream tag the fork is currently based on
  2. Check whether a newer tag exists
  3. Rebase custom commits from v1 onto v2
  4. Resolves conflicts using upstream diffs for context
  5. Verify the result with test-runner
  6. If tests fail: inspect
- Example conflict: "a routine upstream release silently broke Cohere's `cohere-transcribe-03-2026` ASR model on our fork, with the fix flowing back upstream as a vLLM PR."

This is the **most complete public case study** of an AI agent doing the work the user wants their Sisyphus agents to do.

---
### 11.2 `dris1153/upstream-sync` (Claude Code skill, 2026-03-29)
Source: [https://github.com/dris1153/upstream-sync](https://github.com/dris1153/upstream-sync)
- A Claude Code skill that syncs a fork with upstream by reading diffs and editing files directly.
- Steps: Extract (fetch upstream, extract per-file diffs since last sync) → Evaluate (Claude reads each diff, compares with local code, decides apply/adapt/partial apply/skip) → Edit (Claude applies changes directly with Edit/Write tools) → Track (saves last synced commit to `.upstream-sync.json`) → Report.
- Comparison to `git merge`:
  - Control: All-or-nothing (merge) vs Per-file, per-hunk decisions (skill)
  - History: Merge commits, upstream history mixed in (merge) vs Clean local commits only (skill)
  - Conflicts: Cryptic conflict markers (merge) vs Claude understands intent and combines intelligently (skill)
  - Customizations: Can be overwritten silently (merge) vs Explicitly preserved, upstream adapted to fit (skill)
  - Tracking: Merge-base advances automatically (merge) vs Explicit sync state, committed to git (skill)

---
### 11.3 `loongxjin/forksync` (Electron + CLI, 2026)
Source: [https://github.com/loongxjin/forksync](https://github.com/loongxjin/forksync)
- "Auto-sync GitHub fork repos with upstream. Resolve merge conflicts using AI agents (Claude Code, OpenCode, Codex). Desktop app (Electron) + CLI."
- Strategy presets: `agent_resolve`, `manual`, `preserve_ours`, `preserve_theirs`, `balanced`.
- Auto-detects agents: Claude Code (`claude`), OpenCode (`opencode`), Codex (`codex`).
- Workflow: fetch → merge → detect conflicts → agent resolve → review → commit.

### 11.4 `sdfa66065-lang/convergeai` (semantic fork-sync, 2026-01-31)
Source: [https://github.com/sdfa66065-lang/convergeai](https://github.com/sdfa66065-lang/convergeai)
- "ConvergeAI is a semantic fork-sync engine that uses AI coding agents to resolve merge conflicts between upstream open-source projects and internal enterprise forks."
- Approach: "Understands both sides — fetches upstream PR intent *and* internal ticket constraints; Resolves semantically — blends new upstream architecture with required business rules; Validates automatically — runs compilers and test suites, self-correcting on failure."
- Uses a "Context Distiller MCP" tool to fetch upstream PR metadata from GitHub + internal constraints from Jira, then uses `claude-haiku-4-5-20251001` to produce structured plaintext guidance with semantic anchor tags.

### 11.5 `AaronZ345/codebase-argus` (downstream fork sync, 2026)
Source: [https://github.com/AaronZ345/codebase-argus](https://github.com/AaronZ345/codebase-argus)
- "Codebase Argus gives maintainers a review desk for codebase evidence. It reviews pull requests, failing CI logs, and long-lived fork syncs with the same set of signals."
- The "downstream lane":
  - Projected merge conflicts from `git merge-tree`
  - Rebase simulation in a temporary worktree
  - Patch-equivalent commits from `git cherry`
  - Semantic movement from `git range-diff`
  - Fork-ahead commits already covered upstream
  - Agent-safe merge/rebase runbooks
- Tribunal mode: runs multiple reviewers (Codex CLI, Claude CLI, Gemini CLI) against the same PR/CI log/fork sync context.

---
### 11.6 `tesseracode/tesserapatch` (natural-language patch tracker, 2026-04-17)
Source: [https://github.com/tesseracode/tesserapatch](https://github.com/tesseracode/tesserapatch)
- "Fork. Customize. Reconcile. Repeat. — Natural-language-driven patching for open-source software."
- The closest to a *productized* version of the user's patch-tracker.
- 4-phase reconciliation: reverse-apply → operation-level → semantic → forward-apply.
- Skills bundled for 6 coding agent harnesses (Claude Code, OpenCode, Codex, Aider, Gemini CLI, Cursor).
- State in `.tpatch/` folder with human-readable Markdown and JSON files.

### 11.7 `dmzoneill/github-ai-contributor` (fork-as-PR-creator, 2026-02-09)
Source: [https://github.com/dmzoneill/github-ai-contributor](https://github.com/dmzoneill/github-ai-contributor)
- Prompt-driven, headless AI system that autonomously contributes to OSS via forks.
- 5 agents: issue-feedback, pipeline-fix, rebase-sync, coding-fix, bug-scanner.
- Runs every 3 hours via GitHub Actions.
- Monitors `Redhat-forks` and `dmzoneill-forks` orgs, scans upstream issues, assesses confidence, submits PRs.

### 11.8 `kingbootoshi/fork` (worktree isolation, 2026)
Source: [https://github.com/kingbootoshi/fork](https://github.com/kingbootoshi/fork)
- Copy-on-write repo forks + forked agent chats.
- Designed for *parallel agent work*, not fork-of-upstream maintenance.

### 11.9 `eddiedunn/claude-code-agent` (grind)
- DAG-based task execution across git worktrees.
- Merge command: "Interactive merge with conflict resolution. Merges clean branches automatically. Prompts only when conflicts occur."

---
## 12. AI agent maintenance cost patterns (the meta-question)

### 12.1 What the OpenCode community shows about agent-driven maintenance
- OpenCode ships releases within 24 hours of each other (v1.17.10 → v1.17.11 in 2026-06-24 to 2026-06-25). The maintenance tax on downstream is high.
- OMO has a `ROADMAP.md` and ships two editions of one product (Ultimate + Light).
- OMO is publicly investing in a "Multi-Harness Agent OS Refactor" specifically because OMO-as-OpenCode-plugin is too tightly coupled to one host.
- The maintainers' "Building in Public" page says:
  > "The maintainer builds and maintains oh-my-openagent in real-time with Jobdori, an AI assistant running on a heavily customized fork of OpenClaw."

### 12.2 What the fork-of-fork-of-fork case shows
- Continue → acquired by Cursor 2026-06-18
- Roo Code → shut down 2026-05-15
- Void → "We've paused work on the Void IDE"
- CortexIDE → fork of Void which is a fork of VS Code
- AG2 → community fork of Microsoft's AutoGen (in maintenance mode)
- PearAI → built on Continue (now frozen)
- The pattern: forks-with-forks that lose upstream maintenance are abandoned or shelved within 12-18 months of the upstream acquisition/shutdown.

### 12.3 The "retiring a fork" case study
Source: [https://venturecrane.com/articles/retiring-a-fork-that-stopped-earning/](https://venturecrane.com/articles/retiring-a-fork-that-stopped-earning/)
- "We had been running our own fork of [Hermes]. This is the story of why we forked, why the fork quietly stopped earning its keep, and how a first-principles audit turned 'keep it, it costs nothing' into 'delete it, it costs more than you think.'"
- "The fork cost us a second point of failure on every provision, a re-tagging ritual on every version bump, and a confusing extra repository that made every new contributor stop and ask what it was for."

### 12.4 The "yage.ai" acquisition analysis (2026-05-19)
Source: [https://yage.ai/share/open-source-acquisition-ai-infra-en-20260519.html](https://yage.ai/share/open-source-acquisition-ai-infra-en-20260519.html)
> "If the upstream gets acquired by a competitor, goes bankrupt, or changes direction, a fork protects the code but leaves you carrying the entire maintenance burden of a runtime—security patches, platform support, performance optimization. Acquisition eliminates that uncertainty."
> "A fork is defense; acquisition is offense."
> "Previously, seeing an MIT license on an open-source tool felt safe—fork as last resort. Now, an additional layer is necessary: whose capital stands behind the maintainers? Who influences the roadmap? If the tool gets acquired by a competitor, how much maintenance burden can you carry post-fork?"

### 12.5 The "MegaCpp patch lane" finding
> "We tried to carry every Megatron fix as a full fork. That worked, but rebasing against a moving development branch became too expensive for changes that were often very small. We kept fuller forks where the diff justified them and used lighter overlays elsewhere."

This is direct empirical evidence for the pattern the user's `.sisyphus/patches/*.md` is trying to capture: **use the lightest tool that can express the change honestly**.

### 12.6 The Cohere finding
> "Maintaining a long-lived fork of an actively developed project is a recurring cost. But upstream releases also carry features, performance improvements, and bug fixes that you want. Staying in sync is not just maintenance, it's how the fork keeps getting better."

This is the strongest argument *for* maintaining a fork (when you do): upstream value flows into your fork. But the cost is non-zero and recurring.

### 12.7 What "vLLM plugin system" conclusion says
> "The plugin-based extensions model removes that trade-off. It lets you innovate rapidly while staying in sync with the rapidly growing vLLM ecosystem."

The plugin approach is the third option the user has: skip the fork entirely, ship a plugin. The OpenCode plugin system is designed for exactly this.

---

## 13. Direct observations about OMO's own architecture pivot

The most important strategic observation from this research:

### 13.1 OMO is already plugin-based
- The "framework-level" OMO plugin (DeepWiki, OpenCode-Book chapter 15.1) includes 11 agents, 15 tools, 53 hooks, 20 feature modules, 3 MCP servers. It is implemented entirely as an OpenCode plugin.
- OMO's package layout is: `packages/omo-opencode/src/` (the OpenCode plugin) + `packages/omo-codex/` (the Light edition for Codex CLI) + 18 Core packages + 3 MCP packages.
- OMO's `AGENTS.md` documents the layered architecture (Plugin Interface Layer → Capability Layer → Infrastructure → OpenCode Plugin Runtime).

### 13.2 OMO is explicitly betting on multi-harness
- The README at the top says: "Multi-Harness Agent OS Refactor in Progress: We are restructuring the codebase to support multiple agent harnesses (OpenCode, Codex, Pi, Claude Code, and others). If you are interested in contributing, please read the ROADMAP first."
- The "Layer" split (pure TypeScript core logic, MCP servers, skills, adapter shims) means the same logic can be reused across harnesses without duplication.
- OMO is preparing for a future where its logic can run on multiple AI tools. This makes OMO-as-a-fork-of-OpenCode strictly less attractive than OMO-as-a-plugin-of-multiple-harnesses.

### 13.3 The user's stack is on the wrong side of this bet
- The user maintains patches to BOTH OpenCode (the binary) and OMO (the plugin).
- The OMO team is moving toward making OMO harness-agnostic. Patches to OMO that are tied to OpenCode-specific behavior are at risk of becoming obsolete when OMO moves to a new harness.
- Patches to the OpenCode binary are a different kind of risk: the binary is forked at a specific version (1.17.9 per `AGENTS.md`) and tracked through the `update-to-latest` skill.

### 13.4 The OpenCode maintainers' own behavior
- The "Fork and modify" pattern in the plugin system is documented as the *anti-pattern* in multiple open issues.
- Multiple open feature requests explicitly state "if this hook existed I wouldn't need to fork."
- The Plugin Mesh Architecture proposal (8 new infrastructure layers) was an attempt to eliminate the fork-pain reason. It was *closed*, not merged, indicating the maintainers are not committing to this expansion in the near term.

### 13.5 What the user's patch-tracker would map to in the community
- The user maintains patches to OpenCode (binary) + OMO (plugin).
- The community analog of "patches to OMO the plugin" is **PRs to OMO** (the `oh-my-openagent` repo). The OMO team explicitly accepts contributions.
- The community analog of "patches to OpenCode the binary" is **upstream PRs** — but the OpenCode plugin system exists specifically so these aren't needed. The `randomm/opencode` team found this out and decided to remove their plugin-system divergence.

---
## 14. Summary observations (no recommendations)

1. **The user's stack sits at the intersection of two well-documented fork-pain patterns**: AI tool forks (OMO 4 forks, OpenCode 22k+ forks) and binary-vendor forks (Cursor/Windsurf/Void/CortexIDE).

2. **The most directly analogous case to the user's stack is `turtton/oh-my-openagent`**: a patch-overlay distribution of OMO, with `.patch` files + `scripts/apply-patches.sh` + GitHub Actions CI that auto-publishes to npm. It worked for ~1 month before being archived, which is itself a data point about the maintenance tax of a single-maintainer patch-overlay.

3. **The most advanced case is `Vacbo/oh-my-opencode`**: a hard fork of OMO with a 3-pass AI sync classifier and a `docs/fork-deviations.md` register. It is essentially the user's patch-tracker but with AI-driven sync automation.

4. **The most automation-friendly case is `randomm/opencode`**: a hard fork of OpenCode with a `.fork-features/manifest.json` governance system, a `/sync-upstream` AI command, executable `verify.ts` checks, and a `reports/` directory for institutional memory. The `criticalCode` markers + `absorptionSignals` are disciplines the user's patch-tracker does not enforce.

5. **The most pessimistic case is `reallyjustasquirrel/opencode`**: a hard fork with nightly rebase via GitHub Actions. On conflict, it opens a GitHub issue and exits 1. The system never auto-resolves semantic conflicts.

6. **The OMO team's own bet is plugin-first, multi-harness, harness-agnostic**. The user is patching OMO at exactly the layer OMO is trying to make portable. Patches that are tied to OpenCode-specific behavior have a real risk of becoming obsolete as OMO's package layering refactor lands.

7. **The OpenCode maintainers' own bet is also plugin-first**. Multiple open issues request "more hooks so I don't have to fork." The Plugin Mesh proposal was closed without merging. The OpenCode team is not committing to expanding the plugin API to eliminate fork-pain in the near term.

8. **Forks of AI tools in 2026 have a 12-18 month half-life when upstream changes ownership or stops maintaining**. Continue (acquired by Cursor 2026-06-18), Roo Code (shut down 2026-05-15), Void (paused), AutoGen (Microsoft moved to Agent Framework). The user's stack is on two AI tools that are both moving fast.

9. **Patch-overlay and plugin-overlay patterns have lower half-lives than full forks** when upstream is fast-moving. The `patch-package` community's evidence is that patches have to be regenerated on every upstream change in the affected area, but the patch itself is a single line item with a known retirement condition.

10. **No two of the four public OMO forks use the same approach**. The community has not converged. The four are: patch-overlay + CI (`turtton`), hard fork + manual audit (`BOHUYESHAN-APB`), hard fork + 3-pass AI sync (`Vacbo`), hard fork + merge-upstream skill (`allOwO`). The user's choice of patch-tracker is a fifth, not yet validated publicly.

11. **AI-agent-as-maintainer tooling is rapidly maturing but still requires human review**. `Cohere vLLM fork` is the only published end-to-end case study of an agent rebase-and-fix loop working in production. `dris1153/upstream-sync`, `forksync`, `convergeai`, `codebase-argus` are all 2026 releases.

12. **The user's "AI agent as maintainer" advantage is real but bounded by API surface**. The OpenCode plugin API does not currently cover (a) the binary itself, (b) TUI rendering, (c) full schema/UI extension. Patches to these layers will continue to require either upstream PRs or fork maintenance.

---

## 15. Source index (for downstream re-verification)

### Repos
- https://github.com/anomalyco/opencode — 22k+ forks, 180k stars, 828 releases, dev branch
- https://github.com/code-yeongyu/oh-my-openagent — 63k stars, 5.2k forks, plugin, dual-edition
- https://github.com/smola/opencode — soft fork, `patches/` with npm-dep patches
- https://github.com/reallyjustasquirrel/opencode — hard fork, nightly rebase, security hardening
- https://github.com/randomm/opencode — hard fork, `.fork-features/manifest.json`, `/sync-upstream` AI command
- https://github.com/turtton/oh-my-openagent — soft fork of OMO, patches + CI, archived 2026-04-19
- https://github.com/BOHUYESHAN-APB/openagent-labforge — hard fork of OMO, `upstream-audit` doc
- https://github.com/Vacbo/oh-my-opencode — hard fork of OMO, 3-pass AI sync
- https://github.com/allOwO/opencode-codex-orch — hard fork derived from OMO
- https://github.com/Aider-AI/aider — Aider, 46k stars
- https://github.com/continuedev/continue — Continue, acquired by Cursor 2026-06-18
- https://github.com/RooCodeInc/Roo-Code — Roo Code, shut down 2026-05-15
- https://github.com/earendil-works/pi — Pi, MIT, terminal-native

### Issues (cited by number)
- anomalyco/opencode #753 (initial plugin system request)
- anomalyco/opencode #13957 (Plugin Mesh, closed)
- anomalyco/opencode #14671 (workflow fork guards)
- anomalyco/opencode #20139 (v1.3.8 plugin loader regression)
- anomalyco/opencode #20203 (deduplicatePlugins silent data loss)
- anomalyco/opencode #20149 (npm plugin main entry)
- anomalyco/opencode #21369 (randomm removes plugin divergence)
- anomalyco/opencode #22452 (plugin upgrade UX)
- anomalyco/opencode #28463 (workflow fork guards, dup)
- anomalyco/opencode #31463 (plugin import hang on cold cache)
- code-yeongyu/oh-my-openagent #5156 (OMO replaces stock agents)
- code-yeongyu/oh-my-openagent #3917 (Anthropic prefill fix)
- langgenius/dify Discussion #32446 (Dify customization discussion)

### Blog posts / articles
- https://www.ox.security/blog/the-curse-of-the-fork-when-patching-is-not-trivial/ — Cursor/Windsurf CVEs
- https://blogs.eclipse.org/post/thomas-froment/why-cursor-windsurf-and-co-fork-vs-code-shouldnt — Eclipse position
- https://stochasticsandbox.com/posts/the-stack-2026-03-30/ — Cursor long-term-fork post-mortem
- https://theaiengineer.substack.com/p/how-cursor-actually-works — Cursor architecture deep dive
- https://cohere.com/blog/automating-fork-maintenance-with-ai-agents — Cohere vLLM case study (the gold standard)
- https://megacpp.com/blog/how-we-keep-a-patch-lane/ — patch lane methodology
- https://nesbitt.io/2026/05/01/patching-and-forking-in-package-managers.html — patch-package ecosystem
- https://vllm.ai/blog/2025-11-20-vllm-plugin-system — vLLM plugin system vs fork vs monkey-patch
- https://dev.to/microseyuyu/your-fork-will-outlive-your-patience-a-systems-thinking-post-mortem-56pk — fork post-mortem
- https://venturecrane.com/articles/retiring-a-fork-that-stopped-earning/ — retiring a fork
- https://yage.ai/share/open-source-acquisition-ai-infra-en-20260519.html — OSS acquisition in AI
- https://nickdesaulniers.github.io/blog/2023/02/01/forking-is-not-free-the-hidden-costs/ — classic fork-cost analysis
- https://learntoprompt.org/guides/vendor-independence.html — vendor independence for AI tools
- https://mcp.directory/blog/claude-code-skills-vs-subagents-vs-plugins-vs-hooks-2026 — Claude Code primitives comparison

### Forksync / AI-fork-maintainer tools
- https://github.com/dris1153/upstream-sync — Claude Code skill
- https://github.com/loongxjin/forksync — Electron + CLI
- https://github.com/sdfa66065-lang/convergeai — semantic fork-sync engine
- https://github.com/AaronZ345/codebase-argus — PR/fork review desk
- https://github.com/tesseracode/tesserapatch — natural-language patch tracker
- https://github.com/dmzoneill/github-ai-contributor — headless fork-and-contribute
- https://github.com/yzhao062/anywhere-agents — config-pack fork
- https://gist.github.com/johnlindquist/217aaa5023879dfa9bc654c7d7ad0260 — plugin comparison grid

### Plugin / extension system references
- https://opencode.ai/docs/plugins/ — OpenCode plugin docs
- https://code.claude.com/docs/en/plugins — Claude Code plugin docs
- https://developers.openai.com/codex/plugins/build — Codex plugin build
- https://geminicli.com/docs/extensions/writing-extensions/ — Gemini CLI extension docs
- https://github.com/Light-Heart-Labs/DreamServer/blob/main/dream-server/docs/FORKABILITY.md — DreamServer forkability model

### Specific OMO issue referenced
- https://github.com/code-yeongyu/oh-my-openagent/blob/ee938aa09751de9448e6847af7311304a86e3653/README.md — OMO README with "Multi-Harness Agent OS Refactor in Progress"

### OpenCode Book chapter on OMO
- https://www.opencodebook.xyz/en/chapter_15_oh-my-opencode_deep_dive/15.1_project_overview_and_architecture — 4-layer architecture analysis

### 00-plan.md (the user's plan)
- /tmp/opencode-fork-analysis/00-plan.md — full 34-line multi-phase plan

---

*End of R1. No recommendations per the request. Synthesis is the next agent's job.*
