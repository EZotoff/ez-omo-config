# R4 — Update Process Findings

Scope: analysis only. This report describes what the current update process says it should do, what repository history shows has gone wrong, and observed systematic failure modes. It does not make architecture recommendations.

## Sources read

- `skills/update-to-latest/SKILL.md` in full.
- `skills/patch-tracker/SKILL.md` in full.
- `skills/patch-opencode/SKILL.md` in full.
- `tests/test_update_to_latest_skill.sh`.
- Current patch registry frontmatter under `.sisyphus/patches/*.md`.
- Git history searches with `GIT_MASTER=1 git log --all --regexp-ignore-case --extended-regexp --grep='update|upgrade|rollback|revert|resurface|regression'` and a broader body search for `lost|stale|false|inert|regress|resurface|rollback|ineffective|upstream|conflict|reapply|required|missing-target`.
- Targeted `git show --stat --patch` inspection of the update-pipeline introduction commits, the OMO v4.12.1 patch-registry update, the OpenCode v1.17.9 patch update, the DCP v3.1.13 migration, the Magic Context migration/rollback path, and the parent-wake rollback path.
- Wisdom searches for update/upgrade/version-bump/patch-reapplication failures and specific parent-wake/binary-patching terms. Wisdom returned no matching documented entries for these queries.

## What the update-to-latest process is supposed to do

The skill is explicitly a guided operational pipeline, not an automatic updater. Its stated role is to analyze current state, discover available OpenCode/OMO updates, produce a recommendation, and execute only after an exact human approval phrase.

The workflow has 13 mandatory phases:

1. Capture current-state inventory: config repo cleanliness, OpenCode version, OMO configured source vs live file vs runtime-loaded evidence, package versions, symlink targets, copied live artifacts, active patch list, and OMO source clone dirty state.
2. Discover latest OpenCode and OMO versions via GitHub Releases API first, GitHub API fallback second, npm registry fallback third. It explicitly bans using `opencode upgrade` as a discovery command.
3. Classify release delta as none/patch/minor/major/unknown; `unknown` escalates regression depth to Deep.
4. Read every patch registry entry, identify target files/install paths, determine overlap with upstream release notes/changelogs/commit diffs, and assign preliminary risk.
5. Produce benefit/effort/risk recommendation and GO/NO-GO verdict.
6. Select Light/Standard/Deep regression depth from a matrix.
7. Create a timestamped backup/restore bundle under `~/.ez-omo-backup/update-to-latest/<timestamp>/` and an evidence copy under `.sisyphus/evidence/update-to-latest/<timestamp>/`.
8. Stop for exact approval phrase: `YES, update OpenCode/OMO now`.
9. Execute planned update commands only after approval, logging command output.
10. Classify post-update patch state as unaffected, reapplied-cleanly, conflicted, obsolete-upstreamed, obsolete-replaced-by-config-or-plugin, missing-target, or needs-redesign.
11. Update patch tracker entries for changed patch states, versions, verification patterns, reapply instructions, and durable alternatives.
12. Run selected regression suite and trigger rollback policy on critical failures.
13. Produce evidence-state report using the exact AGENTS.md evidence taxonomy.

Important guardrails already present:

- It distinguishes `active_config_registered`, `live_file_installed`, and `runtime_loaded` for OMO source paths.
- It forbids blind `git pull` for local OMO source checkouts before branch/dirty-state/patch/session-continuity analysis.
- It requires non-mutating discovery before approval for local OMO source (`git fetch --all --tags --prune`), and forbids `git pull`, `git checkout`, `git reset`, `npm install`, or build commands before the approval gate.
- It has rollback bundle requirements and evidence-state claim discipline.
- It requires patch registry review before execution and patch lifecycle classification after execution.

## Patch tracker behavior relevant to updates

The patch-tracker skill has a separate post-update verification workflow. For every active patch, it resolves `{target_install_path}/{target_file}`, checks whether the target exists, greps for `verification_pattern`, and reports:

- `applied` when the pattern is found.
- `stale` when the file exists but the pattern is absent.
- `missing-target` when the target file does not exist.

For stale patches it surfaces reapply instructions and asks the operator to reapply or deprecate. For missing-target patches it asks the operator to check whether the dependency moved or was removed.

This is a registry/checklist mechanism, not a reapplication engine. It can detect some lost patches after an update, but only when the entry's target path and verification pattern are still accurate enough to run. It does not independently derive the desired patch from source, resolve conflicts, rebuild dependencies, or prove runtime behavior.

## Current patch registry shape

Current registry frontmatter contains 14 non-template entries plus the template. Status vocabulary is not normalized to the patch-tracker skill's documented `active|upstreamed|deprecated` set; observed statuses include `active`, `retired`, `superseded`, `rolled_back`, `upstreamed`, and `deprecated`.

Active OpenCode/OMO patches include:

- `opencode--command-hook-cancellation`: OpenCode source patch targeting `/home/ezotoff/src/opencode`, dep version `1.17.9-local`, verification pattern `cancelled: boolean|commandOutput.cancelled|HttpServerResponse.empty\(\)`.
- `opencode--commit-policy-unblock`: OpenCode source prompt patch targeting `/home/ezotoff/src/opencode`, dep version `1.17.9`, verification pattern `may create local commits freely`.
- `oh-my-openagent--context-overflow-max-token-error`: OMO v4.12.1 source patch, verification `isRequestTokenOverflowMessage`.
- `omo--exclude-selected-auto-slash-commands`: OMO v4.12.1 cross-package patch, verification includes `"vera"|"gad-experiment"|"session-info"|"session-id"|"vscode"`.
- `omo--clean-agent-display-names`: OMO v4.12.1 source patch, verification `sisyphus: "Sisyphus"`.
- `omo--commit-policy-alignment`: OMO v4.12.1 prompt/agent patch, verification `Git commits: follow the active git workflow`.
- `omo--glm-preemptive-compaction-threshold`: OMO v4.12.1 source patch, verification `GLM_PREEMPTIVE_COMPACTION_THRESHOLD`.

Inactive/special cases include retired DCP patches, superseded Boulder worktree patch, upstreamed activity-stagnation patch, rolled-back parent-wake patch, and deprecated config-level commit policy override.

## Git history patterns: what has gone wrong

### The safe update pipeline itself was added after update pain

On 2026-05-16, commits added `skills/update-to-latest/SKILL.md`, a textual guardrail test, install/docs wiring, and an initial patch-tracker entry. The test (`tests/test_update_to_latest_skill.sh`) verifies only that required strings exist in the skill. It does not simulate an update, execute patch verification, exercise rollback, or build/test OpenCode/OMO. The process is therefore documented and linted textually, not operationally proven by that test.

### OMO v4.12.1 migration required substantial patch registry surgery

The 2026-06-22 commit `57f5b3c docs(patches): update patch registry for OMO v4.12.1 migration` records the strongest direct evidence of update breakage. Its commit body says all 7 OMO patch entries had to be updated for the v4.12.1 monorepo structure:

- All OMO patch `dep_version` fields changed to `4.12.1`.
- Target paths moved into `packages/omo-opencode/src/` or `packages/skills-loader-core/src/`.
- Boulder worktree patch changed from active to superseded because upstream introduced a different works-map architecture.
- Activity-stagnation patch changed from active to upstreamed.
- Clean-display patch changed `post_update_status` from `unaffected` to `reapply_required`; the patch entry notes the earlier `unaffected` classification was false.
- Commit-policy patch was rescoped from 9 files to 5 surviving files because upstream deleted several Prometheus files and changed git-master content.
- Auto-slash patch became cross-package after the skills-loader-core split.
- Context-overflow patch gained a regression note: upstream re-added `max_tokens`, making the local false-positive fix necessary again.

This shows that the painful cases are not just merge conflicts. Upstream reorganizations can invalidate target paths, remove files, split packages, upstream some fixes with different architecture, and reintroduce previously fixed behavior.

### OpenCode v1.17.9 exposed source/binary disconnect

The 2026-06-22 commit `3ac4a66 docs(patches): update opencode--commit-policy-unblock for v1.17.9` documents a concrete source-binary failure mode. The patch target moved from `packages/opencode/src/tool/bash.txt` to `packages/opencode/src/tool/shell/shell.txt` plus prompt files. More importantly, the patch entry's revision history says the previous claim `No rebuild is needed` was false: prompt text is compiled into the Bun binary at build time via text imports. Editing source files alone was inert until rebuilding and installing the binary.

The later 2026-06-26 commit `e88ed15 docs: add OpenCode binary patching procedure to AGENTS.md + patch-opencode skill` codifies this as an operational hazard: never patch the live binary from `dev`, build from the exact live release tag, set `OPENCODE_VERSION` or the build reports `0.0.0-fix/...`, verify built version, backup/swap/restart, and test the real surface.

### DCP update showed dependency packaging changes break patch deployment assumptions

The 2026-06-22 commit `225b07f feat(dcp): migrate to v3.1.13 with tsup bundle model` changed DCP from per-module `dist/lib/*.js` patch targets to a single `dist/index.js` tsup bundle. This forced changes to:

- patch registry target files and reapply instructions;
- `install.sh` patch sync logic (`DCP_PATCH_FILES` changed from many per-module files to `index.js`/`index.js.map`);
- tests, which moved marker checks to the bundle while functional harnesses imported TypeScript source via `tsx`.

This is another source/runtime packaging mismatch: the thing to edit, the thing to deploy, and the thing to grep changed across versions.

### Context-management update caused regression and rollback churn

The 2026-06-23 commit `ea43281 feat(context): migrate DCP → Magic Context for context management` replaced DCP with Magic Context, retired DCP patches/tests, and explicitly ended with `Not verified live: runtime_loaded, real_project_behavior_proven. OpenCode restart required to load MC plugin.`

The next-day commit `a4d1a9a fix(context+parent-wake): disable Magic Context, enable OpenCode/OMO context hooks, patch parent-wake sync mode` says Magic Context caused invisible-message regressions after background sub-agent completion. It disabled Magic Context, re-enabled OpenCode/OMO context hooks, and added an OMO dist patch attempting to make parent wakes render in the TUI.

The 2026-06-25 rollback commit `2ca71a8 rollback(parent-wake): revert sync-mode patch — ineffective` says that patch did not fix the symptom. Messages were persisted to the server DB, but the live TUI did not render them. The patch was rolled back and marked `do_not_reapply`; the root cause was attributed to upstream OpenCode TUI SSE delivery. A follow-up config commit `360868a fix(omo): disable live parent-wake routing` enabled `experimental.disable_live_parent_wake_routing=true` as a rollback flag for externally routed parent wake turns.

This sequence shows that update work can create secondary patches that are later found ineffective, and that syntax/presence verification of a patch is insufficient when the bug is runtime-surface behavior.

### Plugin/API changes caused live behavior regressions despite repo changes

The 2026-06-24 commit `572eb63 fix(plugins): register session-info/session-id/vscode + replace throw-based abort with non-throw pattern` describes two update-related breakages:

- Three plugins existed but were not registered in `opencode.json#plugin`, so OpenCode never loaded them.
- A throw-based command-abort pattern stopped being swallowed after upstream OpenCode issue/PR changes around v1.17.5+, surfacing TUI error toasts.

The fix required config registration, code pattern changes, OMO patch changes, syncing a copied live plugin, and a regression test. This is a failure of active-config/runtime registration and plugin API compatibility, not merely patch reapplication.

### Retry/fallback changes show update interactions across OpenCode and OMO runtime behavior

Several June commits (`c10c23f`, `d7d06a5`, `52cbae1`) show retry/fallback behavior moving between OMO runtime fallback and the config-level provider-connect-retry plugin. One commit introduced session.status handling because OMO fallback deadlocked; another removed that path for GLM retry telemetry because OpenCode's own session.status retry events were not terminal errors and caused promptAsync races. These are not direct version bump commits, but they show a recurring issue: upstream runtime semantics change or interact with local plugins in ways textual patch presence cannot prove.

## Direct answers to requested failure-mode questions

### Does the update process verify patches are reapplied?

Partially, by procedure.

The update-to-latest skill requires patch review before execution, post-update classification, patch tracker updates, and regression verification. The regression matrix says even Light verification includes relevant patch greps. The patch-tracker skill separately defines a post-update verification workflow that checks active patch target paths and greps for each verification pattern.

Limits observed:

- The update skill describes the work but does not provide an executable patch-verification script tied to the update pipeline.
- The existing guardrail test only greps for textual requirements in the skill; it does not run a fake update or verify a patch registry entry against a target tree.
- Patch verification is pattern-based. It can miss semantic regressions when the pattern remains present but behavior is wrong, and it can produce false stale/missing-target results when upstream restructures files and the registry has not yet been updated.
- Current patch statuses include values outside patch-tracker's allowed set (`retired`, `superseded`, `rolled_back`), so any automation assuming only `active|upstreamed|deprecated` would need to handle repo reality.

### Does it test the binary after build?

The update-to-latest skill's generic regression phase says Light includes `binary runs`, and Deep includes full tests and rollback drill. It does not contain the detailed OpenCode binary patching sequence now documented elsewhere.

The separate `patch-opencode` skill and AGENTS procedure do require binary-specific verification: check the live version, build from exact release tag, set `OPENCODE_VERSION`, verify built binary `--version`, optionally grep for a patch-specific string, backup/swap/restart, and test the real broken surface. That binary-patching procedure appears to have been added after the v1.17.9 source/binary disconnect was discovered.

The systematic gap is that `update-to-latest` says an update execution may include `opencode upgrade` or manual binary replacement, but it does not embed the full `patch-opencode` exact-tag/source-clean/build-version/real-surface procedure in Phase 9 or Phase 12.

### Does it handle the source-binary disconnect?

Partially, and more strongly outside the update skill than inside it.

The update skill distinguishes configured source, installed file, and runtime-loaded evidence for OMO. It also inventories local OMO source clone branch/dirty state. That helps with local-source vs runtime confusion.

For OpenCode binary patches, the source-binary disconnect is handled by `patch-opencode` and AGENTS, not by the main update skill. Git history shows the disconnect was real: the OpenCode commit-policy patch had been documented as source-only/no-rebuild, but v1.17.9 proved prompt text is compiled into the Bun binary. The fix was to document a binary rebuild and installation process.

For bundled JS dependencies such as DCP, history shows a similar disconnect: patch source, built bundle, reference install, runtime cache, package cache, Bun cache, and process reload can all differ. The update skill's copied-artifact inventory and regression matrix acknowledge copied artifacts, but it does not provide dependency-specific cache synchronization logic except via existing repo scripts for DCP.

### What happens when upstream changes conflict with local patches?

The documented intended process is:

- pre-update: flag overlap between active patch targets and upstream release notes/changelogs/commit diffs;
- post-update: classify each patch as unaffected, reapplied-cleanly, conflicted, obsolete-upstreamed, obsolete-replaced-by-config-or-plugin, missing-target, or needs-redesign;
- update registry entries and reapply instructions;
- rollback if a critical patch is missing or still conflicted.

History shows actual conflict outcomes are varied:

- Some patches become obsolete because upstream implemented a different fix (`omo--boulder-worktree-authoritative-state` superseded; `omo--remove-activity-stagnation-bypass` upstreamed).
- Some patches need reapplication because upstream regressed the fixed behavior (`oh-my-openagent--context-overflow-max-token-error` note: upstream re-added `max_tokens`).
- Some patches need target rescoping because files moved or packages split (`omo--commit-policy-alignment`, `omo--exclude-selected-auto-slash-commands`).
- Some patches turn out ineffective and must be rolled back (`omo--parent-wake-sync-mode-for-tui-render`).
- Some patch entries themselves contained incorrect assumptions that were discovered only after update (`clean-display` previously marked unaffected; OpenCode commit-policy no-rebuild claim was false).

## Systematic issues found

1. The central update process is procedural documentation, not an executable state machine. The only direct test for `update-to-latest` is textual guardrail coverage.
2. Patch verification relies on grep patterns and human-maintained target paths. Upstream file moves, monorepo splits, bundles, generated dist files, and source-to-binary compilation all stress that model.
3. Patch registry metadata has drifted beyond the patch-tracker schema. Current statuses include `retired`, `superseded`, and `rolled_back`, while the patch-tracker validation rules document only `active`, `upstreamed`, and `deprecated`.
4. Runtime evidence is hard to obtain and often absent at the time of update commits. Several history entries explicitly say runtime/live behavior was not verified, or later prove that patch presence/syntax verification was not enough.
5. Source/binary/cache boundaries are recurring breakpoints: OpenCode prompt text compiled into binary, DCP source compiled into tsup bundle copied across caches, OMO source vs dist patch targets, and copied plugin targets that are not covered by the config symlink model.
6. Upstream can both fix and regress local bugs. The OMO v4.12.1 patch registry update contains examples of upstreaming one local patch, superseding another by a different architecture, and reintroducing a fixed `max_tokens` behavior.
7. Update-related changes often cascade into docs, tests, install.sh, config, plugin registration, live artifact sync, and runtime restarts. The failure modes are cross-surface, not isolated to dependency version numbers.
8. Wisdom did not contain retrievable entries for the requested update/patch-regression queries, even where commit messages claim a root cause was recorded in Wisdom. That weakens Wisdom as a reliable source for avoiding repeat update pain.

## Automation found

Static repository survey found these update-related or update-adjacent automation surfaces outside `skills/update-to-latest/SKILL.md`.

### Skills

- `skills/patch-tracker/SKILL.md`: patch registry CRUD plus post-update verification. It checks each active patch target and greps `verification_pattern`, then reports `applied`, `stale`, or `missing-target`.
- `skills/patch-opencode/SKILL.md`: binary patching procedure for live OpenCode. Requires exact release tag, `OPENCODE_VERSION`, build-version verification, backup, server stop/swap/restart, real-surface test, and rollback.
- `skills/register-retry-error/SKILL.md` and `skills/register-retry-error/AGENTS.md`: validates and atomically writes retry error patterns to `configs/retry-errors.json`. This is runtime registry update automation rather than stack update automation.

### Scripts

- `scripts/verify-live-deployment.sh`: evidence-state verifier. It checks config symlinks, git anchor, plugin registration, optional live target existence, config reference, and runtime evidence file. Emits a `summary.json` containing the highest verified state.
- `scripts/drift-detector.py`: compares store/live pairs for `opencode.json`, `provider-connect-retry.mjs`, `retry-errors.json`, and `oh-my-openagent.json`; classifies sync/drift/missing states.
- `scripts/patch-guard.py`: scans `.sisyphus/patches/*.md` frontmatter and flags patch target install paths in forbidden zones using `path-classifier.py` and `configs/stack-locations.json`.
- `scripts/source-identity-check.py`: reads a source checkout's `package.json` and reports package name/version. Used by the update skill for installed-version discovery.
- `scripts/path-classifier.py`, `scripts/legacy-name-classifier.py`, `scripts/stack-doctor.py`, and `scripts/secrets-path-audit.py`: stack-health helpers adjacent to update safety; not direct update executors.

### Install and rollback hooks

- `install.sh`: installs the update skill, has automatic backup to `~/.ez-omo-backup/<timestamp>/` before overwrites, prints a `Rollback hint: cp -R "$BACKUP_ROOT"/. "$HOME"/`, supports dry-run/copy/symlink modes, and contains idempotency checks.
- Historical DCP patch automation in `install.sh`: during the DCP era it copied patched bundle artifacts across reference, runtime, package-cache, XDG cache, and Bun cache locations. This is dependency-specific patch deployment automation, not a general patch reapplication engine.

### Tests

- `tests/test_update_to_latest_skill.sh`: 22 textual guardrails against the update skill. It verifies the documented procedure contains required strings, but it does not execute an update, simulate conflicts, or validate a rollback bundle.
- `tests/test_live_deployment_contract.sh` and `tests/test_verify_live_deployment.sh`: contract and behavior tests for live deployment verification.
- `tests/test_install_idempotent.sh`, `tests/test_install_modes.sh`, and `tests/test_install_dry_run.sh`: install-safety tests relevant to partial update workflows.
- `tests/test_commit_policy_patches.sh`: post-reapplication verifier for commit-policy patches. It hard-codes machine-local OpenCode/OMO source paths and checks source files plus the live OpenCode binary for stale/canonical policy strings.

### Configs and data

- `configs/oh-my-openagent/oh-my-openagent.json`: disables OMO's `auto-update-checker`, so updates are intentionally manual.
- `configs/opencode/magic-context.jsonc`: disabled rollback/reference config.
- `configs/retry-errors.json`: hot-reloadable runtime retry registry.
- `.sisyphus/patches/*.md`: data backbone for patch tracking; each entry is expected to include verification and reapply instructions. Current entries include active, retired, superseded, upstreamed, deprecated, and rolled-back states.

### Documentation

- `docs/update-migration-v1.14.28.md`: historical operator playbook with version delta, patch registry status, recommended update sequence, verification checklist, monitored files, and rollback plan.
- `docs/live-deployment-verification.md`: specification for the evidence-state verifier and claim language.
- `docs/dcp-byte-budget.md`: legacy DCP rollback paths.
- `docs/skills.md`, `docs/omo-config-reference.md`, `docs/configs.md`, `configs/opencode/README.md`, `MANIFEST.md`, `README.md`, and `AGENTS.md`: document the update-related skills, disabled auto-update hook, Magic Context rollback note, artifact inventory, backup/rollback behavior, evidence-state discipline, and OpenCode binary patching procedure.

### Automation conclusion

The repo has many update-adjacent checks and procedures, but the automation is fragmented. `update-to-latest` is a documented operational pipeline; `patch-tracker` verifies patches by grep; `patch-opencode` handles one binary-patching path; `verify-live-deployment.sh` verifies evidence states; `install.sh` backs up/restores config files and handles some dependency-specific sync. There is no single executable update runner that ties version discovery, patch application, conflict resolution, rebuilds, live install, runtime proof, and rollback into one enforced transaction.
