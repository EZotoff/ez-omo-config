# Update Migration: opencode 1.4.11 → 1.14.28 + OMO v3.17.5

> **Created**: 2026-04-28  
> **Status**: Pre-update assessment complete, ready to execute  
> **Author**: Sisyphus (session investigation)

---

## Version Delta

| Component         | Installed                                           | Latest    | Gap                  | Released     |
| ----------------- | --------------------------------------------------- | --------- | -------------------- | ------------ |
| **opencode**      | 1.4.11 (binary at `~/.opencode/bin/opencode`)       | v1.14.28  | +10 minor versions   | Apr 27, 2026 |
| **oh-my-openagent** | local fork (`~/omo-hub/projects/oh-my-openagent`) | v3.17.5   | needs `git pull` + merge | Apr 24, 2026 |

**opencode repo**: `anomalyco/opencode` (not `sst/opencode`)  
**OMO repo**: `code-yeongyu/oh-my-openagent`

### opencode v1.14.28 Changelog (latest)

- Fixed `opencode upgrade` failing for bun installs unless in a directory with package.json

### OMO v3.17.5 Changelog (latest)

**Breaking/Important:**
- Rename transition updates across package detection, plugin/config compatibility, and install surfaces
- Task and tool behavior updates — delegate-task contract and runtime registration behavior
- Task-system default behavior alignment — omitted configuration behaves consistently across runtime paths
- Install and publish workflow hardening

**New Features:**
- GPT-5.5 native sisyphus support
- Team-mode worktree manager (optional per-member isolation)

**Bug Fixes:**
- CLI attach auth injection (loopback URLs only)
- tmux stale session sweep
- tmux serve/attach cleanup reliability
- Skill cache invalidation at session boundary
- Per-session caching, async FS migration

---

## Patch Registry Status

All 3 patches target **oh-my-openagent**. Registry at `.sisyphus/patches/`.

### 1. `omo--clean-agent-display-names` — ⚠️ HIGH RISK

- **What**: Strips role suffixes from agent display names (e.g., "Sisyphus - Ultraworker" → "Sisyphus")
- **Target**: `dist/index.js` in npm cache (`~/.cache/opencode/packages/oh-my-openagent@latest/`)
- **Risk**: HIGH — patches compiled output in package cache. Any OMO update refreshing the cache silently wipes it.
- **v3.17.5 impact**: "Rename transition updates across package detection, plugin/config compatibility, and install surfaces" may change package resolution.
- **Post-update action**: Must reapply to all cache copies after update.
- **Verification**: `grep -n 'sisyphus: "Sisyphus",' ~/.cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent/dist/index.js`
- **Durable alternative**: Upstream config-based display name override — status: not-yet-pursued

### 2. `omo--glm-preemptive-compaction-threshold` — ⚠️ MEDIUM RISK

- **What**: Lowers compaction threshold for GLM models from 78% to 45% (GLM degrades at ~100K tokens)
- **Target**: `src/hooks/preemptive-compaction-trigger.ts` in local source clone (`~/omo-hub/projects/oh-my-openagent`) **(changed from `preemptive-compaction.ts` in v3.17.5 — file was refactored)**
- **Risk**: MEDIUM — patches source in a git clone. Upstream merge will show conflicts rather than silently losing changes.
- **v3.17.5 impact**: File was refactored — threshold logic extracted to `preemptive-compaction-trigger.ts`. No compaction behavior changes.
- **Post-update action**: ✅ Reapplied to new file location.
- **Verification**: `grep -n "GLM_PREEMPTIVE_COMPACTION_THRESHOLD" ~/omo-hub/projects/oh-my-openagent/src/hooks/preemptive-compaction-trigger.ts`
- **Durable alternative**: Upstream PR or per-provider config option — status: not-yet-pursued

### 3. `omo--remove-activity-stagnation-bypass` — 🔴 HIGH RISK (confirmed still needed)

- **What**: Removes activity-based progress detection from todo-continuation-enforcer so only actual todo state changes count as progress.
- **Target**: 5 files in `src/hooks/todo-continuation-enforcer/` in local source clone
- **Risk**: HIGH — v3.17.5 explicitly changes "task-system default behavior alignment" and "delegate-task contract." This subsystem was modified upstream.
- **v3.17.5 impact**: **Bug NOT fixed upstream.** All activity-signal machinery still present: `recordActivity()`, `activitySignalCount`, `hasObservedExternalActivity`, `progressSource: "activity"`, `ContinuationProgressOptions.allowActivityProgress`. Changelog has no mention of stagnation/continuation fixes.
- **Post-update action**: ✅ Conflicts resolved during merge. Patch preserved (activity code removed).
- **Verification**: `grep -n '"none" | "todo"' ~/omo-hub/projects/oh-my-openagent/src/hooks/todo-continuation-enforcer/session-state.ts`
- **Durable alternative**: Upstream PR — status: not-yet-pursued

---

## Non-Patch Custom Code at Risk

| Artifact                        | Type                   | Risk   | Why                                                                                                                        |
| ------------------------------- | ---------------------- | ------ | -------------------------------------------------------------------------------------------------------------------------- |
| `provider-connect-retry.mjs`    | Plugin (official API)  | MEDIUM | Uses `ctx.client.session.*` methods, event shapes (`session.error`, `message.updated`, `session.idle`). Plugin API may have changed across 10 minor versions. |
| `retry-errors.json`             | Config (consumed by plugin) | LOW  | Contains provider-side error message patterns. Unlikely to change with opencode update.                                     |
| `opencode.json`                 | Config                 | MEDIUM | 10 minor versions of schema evolution. `$schema` reference should catch breaking changes.                                    |
| `oh-my-openagent.json`          | Config                 | MEDIUM | v3.17.5 has "rename transition updates" — agent keys, category names, or config fields may have changed.                    |

---

## Recommended Update Sequence

### Step 1: Pre-Update Backup

```bash
# Backup current opencode binary
cp ~/.opencode/bin/opencode ~/.opencode/bin/opencode.v1.4.11.bak

# Stash local OMO changes
cd ~/omo-hub/projects/oh-my-openagent
git stash push -m "pre-v3.17.5-merge-local-patches"

# Snapshot patch verification (run all 3 grep commands from patch entries)
```

### Step 2: Update opencode

```bash
opencode upgrade
# OR manual download:
# wget https://github.com/anomalyco/opencode/releases/download/v1.14.28/opencode-linux-x64.tar.gz
# tar xzf opencode-linux-x64.tar.gz -C ~/.opencode/bin/
opencode --version  # verify 1.14.28
```

### Step 3: Verify Plugin Compatibility

Launch opencode and check:
- `provider-connect-retry.mjs` loads without errors
- All providers connect successfully
- Retry plugin logs appear at `~/.config/opencode/retry-plugin.log`

### Step 4: Update OMO

```bash
cd ~/omo-hub/projects/oh-my-openagent
git fetch origin
git checkout v3.17.5  # or main if tracking latest
git stash pop         # reapply local patches
# Resolve conflicts in:
#   - src/hooks/todo-continuation-enforcer/session-state.ts
#   - src/hooks/todo-continuation-enforcer/non-idle-events.ts
#   - src/hooks/todo-continuation-enforcer/idle-event.ts
#   - src/hooks/todo-continuation-enforcer/types.ts
#   - src/hooks/preemptive-compaction.ts
```

### Step 5: Reapply Patches

Run verification for each patch:

```bash
# Patch 1: clean-agent-display-names
grep -n 'sisyphus: "Sisyphus",' ~/.cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent/dist/index.js

# Patch 2: glm-preemptive-compaction-threshold
grep -n "GLM_PREEMPTIVE_COMPACTION_THRESHOLD" ~/omo-hub/projects/oh-my-openagent/src/hooks/preemptive-compaction.ts

# Patch 3: remove-activity-stagnation-bypass
grep -n '"none" | "todo"' ~/omo-hub/projects/oh-my-openagent/src/hooks/todo-continuation-enforcer/session-state.ts
```

For any STALE patches, follow the **Reapply Instructions** section in the corresponding `.sisyphus/patches/*.md` entry.

### Step 6: Post-Update Verification

- [x] `opencode --version` returns 1.14.28
- [x] Patch 2 (glm-preemptive-compaction-threshold) verified — applied to new file `preemptive-compaction-trigger.ts`
- [x] Patch 3 (remove-activity-stagnation-bypass) verified — survived merge, no activity code remains
- [x] Patch 1 (clean-agent-display-names) verified — applied to 2 cache files
- [ ] `provider-connect-retry.mjs` functional (check on next opencode launch)
- [ ] All providers accessible (test a prompt with each major provider)
- [ ] OMO agents load correctly (Tab through agents in TUI)
- [ ] Compaction triggers correctly for GLM models (~90K tokens, not 156K)
- [ ] Todo continuation enforcer respects stagnation count (no infinite loops)
- [ ] Config files parse without schema errors

### Actual Update Notes

- **Merge conflict**: Only `session-state.ts` had conflicts — resolved by keeping our patch (no activity code) while incorporating upstream's `startPruneInterval` feature.
- **File refactoring**: Patch 2's target file changed from `preemptive-compaction.ts` to `preemptive-compaction-trigger.ts` in v3.17.5.
- **Package rename**: v3.17.5 introduces `oh-my-opencode` as a parallel package name. The `oh-my-opencode` dist already has clean display names — only `oh-my-openagent` dist needed patching.
- **Stash conflicts**: The pre-update stash contained extensive local modifications beyond our patches. These were discarded in favor of clean v3.17.5 + patch-only approach.

---

## Files to Monitor During Update

```
~/.opencode/bin/opencode                                    # Binary
~/.config/opencode/opencode.json                            # Main config (symlinked to repo)
~/.config/opencode/oh-my-openagent.json                     # OMO config (symlinked to repo)
~/.config/opencode/provider-connect-retry.mjs               # Retry plugin (symlinked to repo)
~/.config/opencode/retry-errors.json                        # Retry registry (symlinked to repo)
~/.cache/opencode/packages/oh-my-openagent@latest/          # OMO compiled cache (patched)
~/omo-hub/projects/oh-my-openagent/                         # OMO source (patched, git-managed)
~/omo-hub/projects/oh-my-openagent/src/hooks/preemptive-compaction.ts
~/omo-hub/projects/oh-my-openagent/src/hooks/todo-continuation-enforcer/
```

---

## Rollback Plan

If update causes critical issues:

```bash
# Rollback opencode binary
cp ~/.opencode/bin/opencode.v1.4.11.bak ~/.opencode/bin/opencode

# Rollback OMO source
cd ~/omo-hub/projects/oh-my-openagent
git checkout HEAD~1  # or the pre-merge commit
git stash pop        # restore local patches

# Reapply display name patch to cache
# (follow .sisyphus/patches/omo--clean-agent-display-names.md reapply instructions)
```
