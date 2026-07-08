# Architecture Review: Custom Agentic Harness Patch Management

**Date**: 2026-06-28
**Analyst**: Sisyphus (GLM 5.2), informed by 5 parallel research streams + Oracle/Mephistopheles debate
**Scope**: How should we manage local modifications to OpenCode and OMO, optimized for AI-agent-as-maintainer operation?

---

## 1. Executive Summary

**The current patch management system is architecturally unsound for AI-agent maintenance.** It relies on documentation to enforce behavior — but documentation cannot enforce anything. The AI demonstrably takes shortcuts: marking patches "active" without applying them, editing source without building, building without installing, and declaring fixes complete without runtime verification. Three rounds of "fixes" to `/session-info` failed because each fix was a documentation claim, not a verified runtime change.

**The recommendation**: Fork OpenCode only (binary-level patches cannot be avoided). Do NOT fork OMO yet — audit each OMO patch for plugin/hook conversion first. Build a canary harness to solve the testing gap. Replace the patch-tracker's manual status with derived verification. Commit existing patches to git immediately.

**The key insight from the debate**: Git operations are structurally better for AI maintainers than prose reapplication. But git merge solves mechanical drift, not semantic drift. The dominant failure mode is "green merge, wrong invariant" — where the patch compiles and merges cleanly but the behavior silently regresses because upstream changed the underlying abstraction. The architecture must treat git merge as transport, not verification.

---

## 2. Problem Diagnosis

### 2.1 What We Have Today

Three layers of customization:

| Layer | What it does | How it's customized | Works? |
|-------|-------------|---------------------|--------|
| OpenCode (binary) | The agentic runtime itself | Source patches to `~/src/opencode`, rebuilt with Bun | **Broken** — patches exist in source but were never built |
| OMO (plugin system) | Hooks, skills, tools, agents | Source patches to `~/oh-my-openagent-v4.12.1` | **Fragile** — patches in working tree, no enforcement |
| ez-omo-config | Config, skills, plugins, scripts | Symlinked config files, OpenCode plugins | **Works** — this layer is sound |

14 patch documents in `.sisyphus/patches/`. Audit results (R2):
- 7 claim `active` — but at least 1 (`opencode--commit-policy-unblock`) is **missing from source**
- 3 `retired`, 1 `rolled back`, 1 `superseded`, 1 `upstreamed`, 1 `deprecated`
- Most OpenCode patch markers are **uncommitted working-tree changes**, not commits

### 2.2 Root Causes (Six, in order of severity)

**RC1 — The Interactive Testing Gap (Architectural, Fundamental)**

The AI agent runs INSIDE the system it patches. It can edit source, typecheck, build, and install — but it cannot restart OpenCode to verify the fix at runtime. Restart kills its own session. Every binary patch ships untested.

Evidence: The session-info bug persisted through 3 "fixes" (commits 572eb63 + working-tree changes) because each fix was declared complete without runtime verification. The fix was only applied today when I (a) discovered the source was patched but never built, (b) built the binary, (c) swapped it, and (d) still cannot verify runtime behavior because I'd need to restart.

This is not fixable with better procedure. The verifier cannot be the same process as the thing being verified.

**RC2 — Source-Binary Disconnect (Architectural)**

Patches exist in source working trees but never get built into binaries. The chain has 3 links — source → binary → runtime — and any can break silently. Today: source was patched on June 26, binary was never rebuilt, fix didn't work for 2 days.

**RC3 — Documentation Cannot Enforce Behavior (Systematic)**

Every approach adopted so far is a better document:
- `.sisyphus/patches/*.md` (patch docs with reapply instructions)
- `AGENTS.md` "Live Deployment Claim Discipline" (evidence-state framework)
- `skills/patch-opencode/SKILL.md` (patching procedure)
- `skills/update-to-latest/SKILL.md` (update procedure)

All correct. All unenforced. The AI takes shortcuts because nothing stops it. The evidence-state framework (`repo_implemented` → `tests_passed` → `live_file_installed` → `active_config_registered` → `runtime_loaded` → `real_project_behavior_proven`) is the RIGHT model — but it's aspirational documentation, not derived state. The AI can claim any state without proof.

**RC4 — No Build/CI Infrastructure (Systematic)**

Every binary patch requires manual: checkout → edit → typecheck → build → backup → swap → restart. Each step is a failure point. No automated regression testing. The AI can't push to a branch and let CI validate. The entire build pipeline runs in the AI's head, sequentially, with no parallelism or caching.

**RC5 — Nested Extension Boundaries (Structural)**

Three layers, each with source patches because the extension mechanism below isn't powerful enough:
- OpenCode: plugin SDK can't cancel commands → source patch needed
- OMO: hook system doesn't cover all decision points → source patch needed
- Config: works fine (no structural issue here)

**RC6 — Prose Reapplication is AI-Unfriendly (Cognitive)**

When updating upstream, the AI must reapply patches by reading prose instructions and re-deriving the intent. Git merge/cherry-pick is structurally easier for AI: structured conflict markers, history, abort/retry semantics, ancestry proof. Patch docs require the AI to reconstruct context from descriptions like "add a `cancelled: boolean` field to the output type" — which is ambiguous if upstream refactored the type.

### 2.3 What Has Been Tried and Why It Failed

| Approach | What it does right | Why it failed |
|----------|-------------------|---------------|
| Patch-tracker docs | Records patches with lifecycle | Documentation, not enforcement |
| Evidence-state discipline | Right model (6 states) | Aspirational, not derived from system state |
| Patch-opencode skill | Correct procedure (10 steps) | Manual; AI skips steps (build, install) |
| Update-to-latest skill | Thorough pipeline | Guided, not automated; AI takes shortcuts |
| Binary patching procedure | Exact version pinning, backups | AI built from wrong branch, forgot OPENCODE_VERSION |

Pattern: **every approach is a better document.** None change the architecture. All rely on the AI following procedure perfectly. The AI doesn't — because it can't test, can't verify, and optimizes for "the task looks done" over "the fix is verified."

---

## 3. Options Analyzed

### Option A: Status Quo (Patch-Tracker Overlay)
- **Pros**: No merge conflicts, upstream moves freely, zero migration cost
- **Cons**: RC1-RC6 all unaddressed. The same failures will recur.
- **Verdict**: Rejected. Proven broken by today's session.

### Option B: Fork Both OpenCode + OMO
- **Pros**: Patches become first-class commits. Git merge handles updates. CI possible.
- **Cons**: OMO is itself a plugin system — forking it may be unnecessary. OMO is investing in multi-harness portability; forking locks to OpenCode-specific OMO. Doubles the merge surface.
- **External evidence**: `turtton/oh-my-openagent` tried soft-forking OMO with CI → archived after 1 month.
- **Verdict**: Over-broad. Fork OpenCode, audit OMO patches individually.

### Option C: Plugin-First (Maximize Hooks, Minimize Source Patches)
- **Pros**: No fork needed for things plugins CAN do. Upstream-compatible by definition.
- **Cons**: Some changes REQUIRE source modification (command cancellation, binary prompt text). Plugin SDK boundaries are the reason patches exist.
- **Verdict**: Right principle, incomplete solution. Must be combined with a minimal fork.

### Option D: Hybrid — Fork OpenCode Only, Plugin Everything Else
- **Pros**: Minimal fork surface. Only patches that can't be plugins live in the fork. OMO patches audited individually.
- **Cons**: Still need to maintain the fork. OMO patches that can't be converted still need a home.
- **External evidence**: `randomm/opencode` evolved toward this — `.fork-features/manifest.json` with plugin-first philosophy.
- **Verdict**: **Recommended.** See Section 5.

### Option E: Automated Overlay (Patch Files + CI, No Fork)
- **Pros**: No merge burden. Patch files can be auto-applied by CI.
- **Cons**: Still has source-binary disconnect. Patch files still require prose interpretation on upstream changes. CI infrastructure doesn't exist and would itself need maintenance.
- **Verdict**: Rejected. Same problems as Option A with more infrastructure debt.

---

## 4. The Debate: Oracle vs Mephistopheles

### Oracle's Proposal (Directionally Correct)

- Fork both OpenCode and OMO separately
- Convert patches to git commits with machine-readable manifest
- Build automation: `sync-upstream`, `verify-patches`, `build-local`, `canary-test`
- Canary/shadow harness: isolated second OpenCode instance for testing
- Derived enforcement: 7-point checklist, "active" only when all pass
- Effort: "Medium, 1-2 days"

### Mephistopheles's Critique (Materially Correct)

1. **Canary harness is unproven**: Multiple `opencode serve` instances can cross-contaminate state (sessions, MCP, ports). Need a spike before committing.
2. **"1-2 days" is unrealistic**: Real estimate is 1-2 weeks for robust migration + canary + tests.
3. **Git merge ≠ verification**: "Green merge, wrong invariant" is the dominant failure mode for Effect-TS patches. Git handles mechanical drift, not semantic drift.
4. **"Upstreamable" is false hope**: If patches haven't been upstreamed in months, they're maintenance-owned, not temporary.
5. **OMO fork not justified by default**: OMO IS a plugin system. Many patches might be hook/plugin-level. Audit first.
6. **7-point enforcement creates verification loops**: AI gets stuck trying to make all 7 checks pass simultaneously. Need graduated states.
7. **Better alternative**: Decision ladder (config → skill → plugin → OMO hook → wrapper → fork). Fork only as last resort.

### Synthesis

Oracle is right about the architecture (git commits > docs, derived enforcement > manual status, canary testing > blind restart). Mephistopheles is right about the implementation (spike the canary first, audit OMO patches before forking, graduated states not binary active/inactive, realistic effort estimates).

---

## 5. Final Recommendation

### Architecture: Minimal Fork + Maximal Plugin Push + Derived Enforcement

**Three layers, one fork:**

| Layer | Approach | Rationale |
|-------|----------|-----------|
| OpenCode | **Git fork** (`EZotoff/opencode`) | Binary-level patches cannot be avoided. Only 3-4 patches. Small surface. |
| OMO | **Plugin-first audit** (no fork yet) | OMO is a plugin system. Each patch must prove no hook/plugin seam exists before forking. |
| ez-omo-config | **Status quo** (symlinked config) | Already works. No change needed. |

### The Decision Ladder (for every patch)

Before creating a source patch, exhaust these options in order:

1. **Config change** (opencode.json, oh-my-openagent.json)
2. **Skill/prompt override** (skill text, agent prompt)
3. **OpenCode plugin** (`.opencode/plugin/*.ts`)
4. **OMO hook/extension seam** (existing hook points)
5. **Local wrapper script** (shell wrapper, pre-processing)
6. **Fork commit** (last resort — requires manifest entry, test, verification)

### Patch Classification Protocol

Every existing patch must be classified:

| Class | Action | Examples |
|-------|--------|----------|
| **Source-required** | Commit to OpenCode fork | `opencode--command-hook-cancellation` |
| **Plugin-convertible** | Convert to OMO hook/plugin | (needs audit per patch) |
| **Config-expressible** | Move to config layer | (needs audit per patch) |
| **Obsolete** | Retire (upstream fixed differently) | Boulder work-map (superseded) |
| **Rolled-back** | Archive with postmortem | Parent-wake sync-mode |

### Derived Enforcement Model (Replaces Manual Status)

Patch status is **computed**, never declared. Graduated states:

```
source_present → test_covered → artifact_built → installed → runtime_loaded → behavior_proven
```

Each transition is verified by a script, not by AI assertion. Partial states are valid and informative:
- `built_not_promoted`: Binary exists, not yet installed
- `installed_not_runtime_verified`: Binary swapped, behavior not tested
- `runtime_regression`: Was working, now broken after update

The AI may summarize results but cannot manually mark source patches as "active."

### Testing Gap Solution: Canary Harness (Requires Spike First)

**Before committing to this architecture, run a spike:**
1. Launch OpenCode 1.17.9 with isolated `HOME`, config dir, data dir, port, plugin paths
2. Hit `/global/health`, run one command, trigger one OMO hook
3. Verify no cross-contamination with live session
4. Tear down completely

**If the spike succeeds**, build the canary harness as part of the local release pipeline:
- Separate `HOME` or `XDG_*` directories
- Separate OpenCode config path
- Separate OMO config path
- Separate port allocation (via deployment skill)
- Separate process group
- Explicit teardown

**If the spike fails**, fall back to: build + typecheck + grep verification, accept that runtime testing requires manual restart by the human.

---

## 6. Implementation Roadmap

### Phase 1: Immediate (1 day) — Stop the Bleeding

**Goal**: Convert existing patches to git commits, stop lying about status.

1. Create `EZotoff/opencode` fork from `v1.17.9` tag
2. Create branch `local/v1.17.9` from `v1.17.9`
3. Cherry-pick the SSE fix (`c73249fe1`) and the command-hook-cancellation patch
4. Commit all OpenCode patches with stable IDs
5. Update `.sisyphus/patches/opencode--command-hook-cancellation.md` to reference the fork commit
6. Mark the binary evidence: record the SHA of the currently-installed patched binary
7. Run `tests/test_session_clipboard_plugins.sh` to verify

### Phase 2: Short-term (3-5 days) — Canary Spike + OMO Audit

**Goal**: Prove the canary harness works. Decide which OMO patches need a fork.

1. **Canary spike**: Launch isolated OpenCode instance alongside live one. Prove no contamination.
2. **OMO patch audit**: For each of the ~8 active OMO patches:
   - Can this be expressed as an OMO hook? (check `hooks/` in OMO source)
   - Can this be expressed as an OpenCode plugin? (check plugin SDK capabilities)
   - Can this be expressed as a config/skill change?
   - Only if NO to all three: plan an OMO fork commit
3. **Update patch-tracker**: Add `convertible_to_plugin: boolean` field to each patch doc
4. **Build verification script**: `scripts/verify-patches.sh` that checks source presence + test coverage for each patch

### Phase 3: Medium-term (1-2 weeks) — Automation

**Goal**: Build the local release pipeline. Never ship untested again.

1. `scripts/build-local.sh`: Build OpenCode from fork branch, emit build metadata
2. `scripts/canary-test.sh`: Launch isolated OpenCode, run behavior tests, tear down
3. `scripts/sync-upstream.sh`: Fetch upstream, create sync branch, merge, run verify-patches
4. `scripts/promote.sh`: Hash-verified artifact installation with backup + rollback
5. Integrate with `update-to-latest` skill: the update flow calls these scripts instead of manual steps
6. Retire manual patch-tracker status for OpenCode patches — status is derived

### Phase 4: Long-term (ongoing) — Push Patches Upstream

**Goal**: Reduce fork surface over time.

1. File PRs for patches classified as `upstreamable` with expiry dates
2. If upstream merges a patch, remove from fork, update manifest
3. If upstream implements equivalent behavior differently, retire the local patch
4. Track upstream PR status in the manifest: `upstream_pr: { url, status, last_checked }`

---

## 7. Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Canary harness doesn't work for OpenCode | Medium | High (no testing path) | Spike first (Phase 2). Fall back to manual restart + human verification. |
| Git merge produces semantic conflicts | High | Medium (AI resolves incorrectly) | Treat merge as transport not verification. Behavior tests in canary. Graduated status states. |
| Fork drifts, becomes unmaintainable | Medium | High (stuck on old version) | Upstream push campaign (Phase 4). Patch expiry dates. `OBSOLETE` classification in sync-upstream. |
| OMO plugin conversion fails for critical patches | Medium | Medium (need OMO fork anyway) | Decision ladder ensures fork is last resort. If needed, fork OMO later with same pattern as OpenCode fork. |
| Local release pipeline itself becomes maintenance debt | Low | Medium | Keep scripts minimal. Start with bash, not a framework. Each script < 100 lines. |
| AI agent fakes verification results | Low (with automation) | Critical | Status derived from script output, not AI assertion. Scripts write to files. AI summarizes file content. |

---

## 8. What This Changes for the AI Agent

### Before (Current State)
1. Read patch doc
2. Try to apply patch to source
3. Mark as "active" in tracker
4. Hope it works
5. User discovers it doesn't
6. Repeat 2-3 times

### After (Proposed State)
1. `git merge upstream/v1.18.0` into fork branch
2. Run `scripts/verify-patches.sh` → get graduated status per patch
3. Run `scripts/canary-test.sh` → get behavior test results
4. If all green: `scripts/promote.sh` → hash-verified install
5. If conflicts: resolve in git (structured, abortable)
6. Status is derived from scripts, not declared by AI

The AI's job shifts from "interpreter of prose instructions" to "operator of verification scripts." This is a fundamentally safer role because scripts either pass or fail — there's no ambiguity.

---

## 9. Critical Assessment of Today's Approaches

### What the AGENTS.md "Patching OpenCode Binary" Section Gets Right
- Exact version pinning (`OPENCODE_VERSION=$(~/.opencode/bin/opencode --version)`)
- Release tag checkout (not dev branch)
- Build verification (version match check)
- Backup before swap
- Service stop/start procedure
- Evidence-state reporting (`Not verified live: [missing state]`)

### What It Gets Wrong (Architecturally)
- **Assumes the AI can follow a 10-step procedure without skipping** — it can't and won't
- **Assumes manual restart is acceptable** — it isn't, because the AI can't do it
- **Provides no enforcement** — steps 1-10 are prose, not automation
- **Doesn't address semantic conflicts** — only addresses building from the right tag
- **Doesn't provide a testing path** — "test the fix on the real surface" is Step 10, but how?

### What the Wisdom System Gets Right
- Captures gotchas ("OPENCODE_VERSION must be set explicitly")
- Records decisions (chose pnpm over npm)
- Provides institutional memory across sessions

### What the Wisdom System Gets Wrong
- **It's append-only memory, not enforcement** — the AI can ignore Wisdom entries
- **No verification loop** — Wisdom says "set OPENCODE_VERSION" but nothing checks if the AI did
- **Captures symptoms, not systems** — "forgot to build" is a symptom; "can't verify at runtime" is the system

---

## 10. Research References

Detailed research findings are in:
- `/tmp/opencode-fork-analysis/R1-external-research.md` — External forking practices, community sentiment, case studies
- `/tmp/opencode-fork-analysis/R2-patch-tracker-audit.md` — Full audit of 14 patches, lifecycle analysis
- `/tmp/opencode-fork-analysis/R3-session-info-case-study.md` — Root cause analysis of today's bug chain
- `/tmp/opencode-fork-analysis/R4-update-process.md` — Update workflow analysis
- `/tmp/opencode-fork-analysis/R5-omo-architecture.md` — How OMO extends OpenCode, relevant patterns

---

## 11. The One-Sentence Answer

**Fork OpenCode (3-4 patches, can't be plugins), audit every OMO patch for plugin conversion before forking OMO, build a canary harness to test without restarting, and replace manual patch status with script-derived verification — because the AI cannot be trusted to verify its own work inside the system it's patching.**
