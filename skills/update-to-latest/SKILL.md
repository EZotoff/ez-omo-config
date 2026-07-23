---
name: update-to-latest
description: Safety-critical operational pipeline for analyzing and executing OpenCode/OMO updates with explicit approval, patch preservation, rollback capability, and evidence-state discipline.
---

# Update to Latest

## Role and Purpose

This skill is a **guided operational pipeline for future agents**, NOT an automatic updater. It analyzes the current state, discovers available updates, produces a recommendation, and only executes after receiving explicit human approval. Future agents invoking this skill must follow every phase in order. No phase may be skipped.

## Non-Goals

- This skill does NOT automatically update OpenCode or OMO.
- We do not run package manager or update commands before the approval gate.
- This skill does NOT delete patch registry entries.
- This skill does NOT claim runtime success without evidence.

## 13 Mandatory Workflow Phases

### Phase 1: Preflight / Current-State Inventory

Before any update analysis, capture the complete current state:

1. **Git cleanliness** in the config repo: run `git status --short` and record whether the working tree is clean.
2. **OpenCode version**: run `opencode --version` and record the output.
3. **OMO configured source vs runtime source**: discover OMO path candidates (see OMO Path Discovery below), then distinguish these evidence levels explicitly:
   - `active_config_registered`: a live OpenCode config contains a `file://...oh-my-openagent` or `file://...oh-my-opencode` path.
   - `live_file_installed`: that path exists on disk and contains valid OMO source.
   - `runtime_loaded`: a currently running OpenCode process has actually loaded that path. Do not claim this from config alone.
   Record the current Git branch, upstream, commit hash, package name/version, and dirty state for every valid local source candidate.
4. **NPM / package versions**: record the installed versions of `opencode-ai`, `oh-my-opencode`, and `oh-my-openagent` where discoverable.
5. **Live symlink targets**: verify the four symlinked configs (`opencode.json`, `oh-my-openagent.json`, `provider-connect-retry.mjs`, `retry-errors.json`) point into this repo.
6. **Copied plugin / skill / script inventory**: list all artifacts installed by `install.sh` that are NOT symlinks (e.g. plugins under `~/.opencode/plugin/`, scripts under `~/.opencode/scripts/` and `~/.sisyphus/scripts/`).
7. **Active patch list**: run `ls .sisyphus/patches/*.md` and record every patch entry.
8. **Dirty state in OMO source clone**: run `git status --short` in the discovered OMO directory.

### Phase 2: Target / Latest-Version Discovery

Query upstream sources for available updates, including the GitHub Releases API and npm registry. This phase has concrete commands and a mandatory cascade. Agents must exhaust every documented source before declaring failure.

#### Anti-pattern ban

- `opencode upgrade` is an execution command, not a discovery or check command. Do NOT use it to discover the latest version.
- Do NOT stop discovery because a command lacks a `--check` or `--dry-run` flag. That is never a valid reason to halt version lookup.
- Do NOT report "Could not determine exact number" unless every fallback in the cascades below has been attempted and documented.
- Do NOT say "OMO is loaded from a local file path" from config evidence alone. Say "OMO is configured in active config as a local file path" unless runtime-loaded evidence proves the process loaded it.
- Do NOT prescribe `git pull` as the update action for a local OMO source checkout. A local source checkout requires branch, dirty-state, patch, and session-continuity analysis before any source movement.

#### OpenCode latest-version discovery cascade

Run these in order. Stop at the first one that returns a clean result, but record every attempt.

1. **First preference**: `gh release view --repo anomalyco/opencode --json tagName,publishedAt`
2. **Second preference**: `gh api repos/anomalyco/opencode/releases/latest --jq '.tag_name, .published_at'`
3. **Third preference**: `npm view opencode-ai version`

If the release tag and npm version differ, report both values. State which one is the operative update target and explain why.

#### OMO latest-version discovery cascade

Run these in order. Stop at the first one that returns a clean result, but record every attempt.

1. **First preference**: `gh release view --repo code-yeongyu/oh-my-openagent --json tagName,publishedAt`
2. **Second preference**: `gh api repos/code-yeongyu/oh-my-openagent/releases/latest --jq '.tag_name, .published_at'`
3. **Third preference**: `npm view oh-my-openagent version` and `npm view oh-my-opencode version`

If the two npm package names return different versions, report both. Explain the package rename or parallel-package situation. Do not collapse the discrepancy into "unknown".

#### Installed-version discovery

- **OpenCode installed version**: run `opencode --version` and record the exact output.
- **OMO configured source path**: inspect live OpenCode config entries (`~/.config/opencode/opencode.json` and related plugin arrays) for `file://` references to OMO. This proves only `active_config_registered`, not `runtime_loaded`.
- **OMO installed/local version**: inspect every discovered OMO source clone. Record `git status --short --branch`, `git remote -v`, `git rev-parse HEAD`, and package metadata from `package.json` (`name` and `version`). If the clone is a package installation, also record `npm list -g oh-my-openagent` or `npm list -g oh-my-opencode` output.
- **Runtime-loaded evidence**: only claim `runtime_loaded` for OMO if a running OpenCode process, runtime log, or equivalent observed evidence proves the file path was loaded in this session. Otherwise state `Not verified live: runtime_loaded`.

For every installed and latest value, state the exact command or source that produced it.

#### Local OMO source checkout safety rule

If OMO is configured as a local source checkout (`file://...oh-my-openagent` or `file://...oh-my-opencode`), the recommendation must not be a one-line `git pull`. Instead:

1. Report the exact evidence state: configured path, whether the path exists, branch, upstream, ahead/behind state, dirty files, package name/version, and whether runtime loading is verified.
2. If the checkout is dirty, on a custom/fix branch, ahead of upstream, or contains untracked patch/hook files, classify source update risk as **Deep**.
3. Require a dedicated local-source update plan before moving the branch: backup/restore bundle, patch registry review, current-session continuity risk, branch target selection, and rollback commands.
4. Prefer `git fetch --all --tags --prune` for non-mutating discovery. Do not run `git pull`, `git checkout`, `git reset`, `npm install`, or build commands before the explicit approval gate.
5. If the user is concerned about active OpenCode/TUI sessions, include a session-continuity warning and do not recommend switching branches until the user has accepted the interruption risk.

#### Failure-handling rule

If all sources in a cascade fail, do NOT say only "Could not determine exact number". Produce a structured blocker report containing:

- Every command that was attempted.
- The exact stderr, stdout, or failure mode for each attempt.
- Whether the failure was caused by network unavailability, missing `gh` or `npm` tooling, or authentication/permissions.
- The exact next manual command the human can run to verify the latest version.

#### Output contract

The recommendation/inventory output must include these fields for OpenCode and for OMO:

- **installed value** — the version currently in use.
- **latest value** — the version discovered from upstream.
- **source of installed value** — the exact command or file that produced the installed value.
- **source of latest value** — the exact command or API that produced the latest value.
- **confidence / caveat** — any discrepancy between sources, missing tools, or partial data.

### Phase 3: Release Delta Analysis

Classify each available update into one of the following categories:

- `none` — no update available.
- `patch` — patch-level change only.
- `minor` — minor version bump with new features.
- `major` — major version bump with breaking changes.
- `unknown` — cannot determine the delta from release notes or tags.

**Rule**: any classification of `unknown` automatically escalates the regression suite to **Deep**.

### Phase 4: Patch Registry Review

Read every `.sisyphus/patches/*.md` entry. For each active patch:

1. Identify the `target_file` and `target_install_path`.
2. Determine whether the upcoming update touches the same file paths or subsystems.
3. Flag any patch whose target file is mentioned in upstream release notes, changelogs, or commit diffs.
4. Record a preliminary risk level: `none`, `low`, `medium`, or `high`.

### Phase 5: Benefit / Effort / Risk Recommendation

Produce a single go/no-go recommendation with a clear rationale. The recommendation must include:

- **Benefit summary**: what improvements or fixes the update provides.
- **Effort estimate**: how many patches need reapplication, whether config changes are needed, and expected conflict resolution time.
- **Risk summary**: patch target overlap, config schema changes, plugin API changes, and any `unknown` deltas.
- **Recommended regression depth**: Light, Standard, or Deep.
- **Final verdict**: `GO` or `NO-GO`.

### Phase 6: Regression Depth Selection

Select the regression suite using the exact triggers in the Regression Matrix below. The recommendation from Phase 5 may be overridden if new information is discovered during patch review. Document any override and the reason.

### Phase 7: Backup / Restore Bundle Creation

Create a timestamped backup directory at:

```
~/.ez-omo-backup/update-to-latest/<timestamp>/
```

The backup must contain:

1. The config repo commit hash (`git rev-parse HEAD`).
2. The config repo `git status --short` output.
3. Copies or checksums of all four symlinked configs.
4. Checksums of all copied live targets (plugins, scripts, etc.).
5. A snapshot of the patch registry (copy all `.sisyphus/patches/*.md`).
6. Current upstream and local versions recorded in Phase 2.
7. Package manager metadata (e.g. `npm list -g opencode-ai` output, if applicable).
8. The exact planned update commands.
9. The exact restore commands to reverse the update.

**Do NOT include auth or API keys.**

Store a copy of the backup manifest at:

```
.sisyphus/evidence/update-to-latest/<timestamp>/
```

### Phase 8: Explicit Human Approval Gate

Present the recommendation from Phase 5 to the user. Ask for the literal phrase:

```
YES, update OpenCode/OMO now
```

If the user has not explicitly asked to execute the update now, stop after producing the update recommendation.

**Any response other than the exact phrase above aborts the pipeline.** Do not proceed with execution.

### Phase 9: Update Execution

Only run this phase after receiving the exact approval phrase from Phase 8. Execute the planned update commands in the exact order documented in the backup bundle. Typical commands may include:

- `opencode upgrade` or manual binary replacement.
- `git fetch origin && git checkout <tag>` in the OMO source clone.
- `npm update` or `npm install` for global or local packages.

Log every command and its output into the evidence directory.

### Phase 10: Patch Reapply / Deprecation Decisions

For each patch flagged in Phase 4, classify its post-update state:

- `unaffected` — the update did not touch the patched file.
- `reapplied-cleanly` — the patch was reapplied without conflicts.
- `conflicted` — the patch had merge conflicts that required manual resolution.
- `obsolete-upstreamed` — the fix is now present upstream; the patch is no longer needed.
- `obsolete-replaced-by-config-or-plugin` — a durable alternative (config, plugin, or hook) now covers the same need.
- `missing-target` — the patched file no longer exists in the updated dependency.
- `needs-redesign` — the patch must be rewritten for the new version.

**Obsolete classifications must be deprecated with rationale, NOT deleted.** Update the patch entry's `status` field to `deprecated` or `upstreamed`, and record the reason in the entry body.

### Phase 11: Patch Tracker Updates

For every patch whose classification changed in Phase 10, update the corresponding `.sisyphus/patches/*.md` entry:

1. Update `status` to the new classification.
2. Update `dep_version` to the new version range.
3. Update `verification_pattern` if the surrounding code changed.
4. Update `## Reapply Instructions` if the reapplication steps are different.
5. Update `## Durable Alternative` if a new alternative became available.

### Phase 12: Regression Verification

Run the regression suite selected in Phase 6:

- **Light** — smoke checks + targeted JSON validation + relevant patch greps.
- **Standard** — targeted tests + install dry-run or idempotency check + affected plugin or patch tests.
- **Deep** — full `bash tests/run_all.sh` + DCP startup checks + rollback drill.

Record all test results in the evidence directory. Any failure in a critical test triggers the Rollback Policy.

### Phase 13: Evidence Report and Claim Discipline

Produce a final report using the exact evidence states from AGENTS.md:

- `repo_implemented`
- `tests_passed`
- `live_file_installed`
- `active_config_registered`
- `runtime_loaded`
- `real_project_behavior_proven`

For each state, explicitly state whether it is verified or unverified. If any state is unverified, the report must include the exact sentence:

```
Not verified live: [state]
```

Replace `[state]` with the name of the unverified evidence state.

## Regression Matrix

| Depth | Trigger |
|-------|---------|
| **Light** | Patch-level update, no active patch target overlap, no config / schema / plugin / DCP / update-mechanism changes mentioned in release notes. |
| **Standard** | Minor update, OR copied artifacts are involved, OR normal plugin or skill compatibility risk, OR release notes mention config, agent, or provider changes. |
| **Deep** | Major update, OR any active patch target overlap, OR DCP or runtime behavior change, OR install or update mechanism change, OR config schema migration, OR a failed smoke check, OR an `unknown` release delta. |

### Regression Suite Details

- **Light**: Smoke checks (binary runs, configs parse) + targeted JSON validation on all symlinked configs + grep verification for every affected patch.
- **Standard**: All Light checks + targeted test scripts for affected subsystems + install dry-run or idempotency verification + plugin load test if plugin API changed.
- **Deep**: All Standard checks + full `bash tests/run_all.sh` + DCP startup warning probe + actual rollback drill (restore from backup and verify the system returns to the pre-update state).

## Rollback Policy

Every update creates a rollback bundle in the backup directory. The rollback drill is performed only for Deep or otherwise high-risk updates.

**Rollback is recommended if any of the following is true:**

- The OpenCode binary is unavailable or crashes after the update.
- The OMO command or doctor cannot load after the update.
- Any JSON config file is invalid or rejected by schema validation.
- A critical patch is missing or still conflicted after reapplication.
- A DCP startup warning regression is detected.
- The selected regression suite fails a critical test.
- Copied live artifacts are inconsistent with the repo state.

**Rollback procedure:**

1. Halt further update steps immediately.
2. Execute the exact restore commands documented in the backup bundle from Phase 7.
3. Verify the restored state matches the pre-update inventory from Phase 1.
4. Reapply any patches that were clean before the update.
5. Re-run the Light regression suite to confirm the restored system is functional.
6. Document the rollback reason in `.sisyphus/evidence/update-to-latest/<timestamp>/rollback.txt`.

## Patch Lifecycle Classifications

These are the exact classifications used in Phase 10:

- `unaffected`
- `reapplied-cleanly`
- `conflicted`
- `obsolete-upstreamed`
- `obsolete-replaced-by-config-or-plugin`
- `missing-target`
- `needs-redesign`

**Deprecate, do not delete.** Obsolete classifications (`obsolete-upstreamed`, `obsolete-replaced-by-config-or-plugin`) must update the patch entry's `status` to `deprecated` or `upstreamed` and preserve the file in `.sisyphus/patches/`. The history and rationale must remain available for future reference.

## OMO Path Discovery

Do NOT hardcode a single OMO path. Search the following candidates in order:

1. `~/omo-hub/projects/oh-my-openagent/`
2. `~/oh-my-openagent/`
3. Any `target_install_path` values referenced in existing `.sisyphus/patches/*.md` entries.

For each candidate, verify it contains valid OMO source by checking for a `package.json` that references `oh-my-openagent` or `oh-my-opencode` in its name or dependencies. Stop at the first valid match and record the resolved path. If no valid path is found, report the failure and stop the pipeline.

## Evidence-State Claim Discipline

All final reports must use the exact evidence-state names from AGENTS.md. No abbreviations, no paraphrasing.

| State | Definition |
|-------|------------|
| `repo_implemented` | Code exists in the repository and is tracked by git. |
| `tests_passed` | Automated tests for the change pass in the repo. |
| `live_file_installed` | The file is present at its live target path via symlink or copy. |
| `active_config_registered` | The live config file references or registers the artifact. |
| `runtime_loaded` | The runtime has actually loaded or invoked the artifact. |
| `real_project_behavior_proven` | The artifact's effect has been observed in a real project scenario with concrete evidence. |

### Claim Language Rules

- `repo_implemented` → may say "implemented in repo"; must NOT say "installed", "active", or "working".
- `tests_passed` → may say "repo tests pass"; must NOT say "deployed" or "runtime verified".
- `live_file_installed` → may say "installed at live target"; must NOT say "loaded".
- `active_config_registered` → may say "registered in active config"; must NOT say "runtime loaded".
- `runtime_loaded` → may say "plugin loaded" or "handler invoked"; must NOT say "end-to-end working" without real-project proof.
- `real_project_behavior_proven` → may say "working for [specific project]" with an evidence path.

If any live or runtime evidence state is unverified, the final report must say:

```
Not verified live: [state]
```

Replace `[state]` with the exact unverified state name.

## Examples

### Example 1: Recommendation-Only Run (No Execution)

**User**: "Should I update OpenCode?"

**Agent action**:

1. Run Phase 1 (inventory): OpenCode 1.4.11, OMO v3.17.5 local fork, 3 active patches, clean git state.
2. Run Phase 2 (discovery): OpenCode v1.14.28 is available.
3. Run Phase 3 (delta): `minor` (10 minor versions).
4. Run Phase 4 (patch review): 2 of 3 patches target OMO files, 1 targets npm cache.
5. Run Phase 5 (recommendation): GO with Standard regression. Rationale: significant feature gains, but plugin API and config schema may have changed across 10 minor versions.
6. Run Phase 6 (regression selection): Standard (minor update + plugin compatibility risk).
7. Run Phase 7 (backup): Create `~/.ez-omo-backup/update-to-latest/20260428-143022/`.
8. Run Phase 8 (approval gate): Present recommendation. User does NOT type "YES, update OpenCode/OMO now".

**Agent result**: Stop. Provide the recommendation summary and the backup path. Do not execute the update.

### Example 2: Approved Update Run

**User**: "YES, update OpenCode/OMO now"

**Agent action**:

1. Phases 1 through 7 as in Example 1.
2. Phase 8: exact approval phrase received. Proceed.
3. Phase 9: Execute `opencode upgrade`, then perform the approved local-source update plan for OMO. For a local checkout, use `git fetch --all --tags --prune` for discovery first, then only run the approved branch movement or merge commands after backup, patch review, and explicit approval.
4. Phase 10: Patch 1 (`unaffected`), Patch 2 (`reapplied-cleanly` to new file), Patch 3 (`conflicted` then resolved).
5. Phase 11: Update Patch 2 `target_file` to new path, update Patch 3 `dep_version` and `reapply instructions`.
6. Phase 12: Run Standard regression. All tests pass.
7. Phase 13: Report evidence states:
   - `repo_implemented` — verified (configs and patches tracked).
   - `tests_passed` — verified (Standard suite passed).
   - `live_file_installed` — verified (symlinked configs confirmed).
   - `active_config_registered` — verified (configs reference updated plugins).
   - `runtime_loaded` — Not verified live: runtime_loaded (process not restarted during this session).
   - `real_project_behavior_proven` — Not verified live: real_project_behavior_proven (no project task run yet).

**Agent result**: Update complete. Evidence saved to `.sisyphus/evidence/update-to-latest/20260428-143022/`.
