# Performance Review: Wisdom System and Operator Tools

**Date**: 2026-09-15
**Plan**: `.omo/plans/perf-review-wisdom-operator-tools.md` (evidence from Tasks 1-15, assembled by Task 16)
**Repo**: `/home/ezotoff/ez-omo-config` at HEAD `85b0dbbfb1b4d364a1cf13b711058116b95c9736`, clean tree (baseline.txt, versions.txt: OpenCode 1.18.5, Python 3.10.12, jq 1.6, bash 5.1.16)
**Mode**: read-only review. No wisdom script was modified, no operator tool was modified, and the wisdom store was not mutated. Every remediation named below is a decision-gated proposal, not an executed change.
**Audience**: written for a reader who has not read the underlying evidence files. Every metric cites the evidence file it came from; all cited files live in `.sisyphus/evidence/perf-review-wisdom-operator-tools/`.

## Executive summary

The wisdom system is functionally sound but carries two large, fixable debts: search performance and store hygiene. `wisdom-search.sh` runs 13.9x to 255.9x slower than a single-jq baseline (1.11s for a 1-match query and 20.47s for a 32-match query against a 0.08s baseline) because it spawns 28 jq subprocesses per matched entry; the fix is a batched single-pass rewrite estimated at ~0.3-0.5s for any match count (task-8-search-rca.md, task-2-search-bench.txt). 42.4% of the store (75 of 177 entries in `system.jsonl`) violates the system's own GC criteria, with a classified cleanup plan projecting 177 to 103 active entries (task-9-gc-analysis.md). The operator-facing skill doc covers only 6 of 17 scripts, though its canonical contract section is fully accurate with drift 0 (task-12-skill-staleness.md). The decision framework keeps 15 of 20 reviewed items, tunes 4 (search, store, the search script row, the skill doc), consolidates 3 low-usage scripts into surviving engines, and retires nothing (task-14-wisdom-decision.md).

The operator tools are individually healthy and cheap (all 7 Python tools run in 0.02-0.43s with correct exit-code contracts, and all 7 have test coverage), but the policy manifest they enforce contradicts reality and their automation coverage is inverted. `configs/stack-locations.json` declares the live `.omo` planning directory forbidden, omits the canonical OMO runtime fork and the OpenCode source checkout, and these drifts cause 20 of patch-guard's 24 "forbidden" findings to be policy-caused false positives (task-11-accuracy.md). Exactly 1 of 11 tools is automation-wired, and it is the one with zero test coverage, while the 7 test-covered tools have zero automation (task-6-wiring.json, task-13-automation-gap.txt). The decision framework keeps 8 of 12 items, tunes 3 (the policy manifest, which gates the Task 18 reconciliation; stack-doctor's hardcoded policy check; legacy-name-classifier's 3 unclassified paths), instruments drift-detector into the existing 30-minute timer, and consolidates or retires nothing (task-15-tools-decision.md). All three remediation gates (Tasks 17, 18, 19) fired on this evidence and await execution decisions.

## Methodology

Every number in this report is traceable to an evidence file produced by Tasks 2-15 at the baseline HEAD above. Nothing was re-measured for this report (Task 16 assembles verified evidence only), and no reviewed system was modified: the store file `system.jsonl` ended the review with sha256 `d8226f503aafbaef163cf65f137f7d65bc41d7c73b935a7be4caa5b765c23d0f`, unchanged since before the GC analysis (task-9-gc-analysis.md, task-14-wisdom-decision.md). Measured values below are facts; projections are inference (labeled as projections); verdicts and follow-ups are recommendations recorded in decision matrices, none executed.

### Commands that produced the evidence

| Task | Representative exact commands | Evidence |
|------|------------------------------|----------|
| 2 | `/usr/bin/time -f '%e' ~/.sisyphus/scripts/wisdom-search.sh "<term>" --limit 10` (3 samples per query class, no `--touch`); match-count verification `wisdom-search.sh "plugin" --limit 100 --json \| jq 'length'` → 32 | task-2-search-bench.txt, task-2-search-empty.txt |
| 3 | jq replication of `wisdom-gc.sh:219-256` (`_is_stale`), epoch-exact against `date -d '90 days ago' +%s` (cutoff_epoch=1781691260) | task-3-store-health.json, task-3-malformed.txt |
| 4 | jq aggregation of `~/.sisyphus/wisdom/events.jsonl` by `.event` name within the retained 1000-line window; `grep -rl '<script-basename>'` over the repo for ref_count | task-4-usage.json, task-4-usage.meta.json, task-4-no-dead-claim.txt |
| 5 | `timeout 30 /usr/bin/time -f '%e s rc=%x' python3 scripts/<tool>.py` for all 7 Python tools; argparse probes with missing required args | task-5-tools.txt, task-5-tools.json, task-5-argparse.txt |
| 6 | `grep -rl '<basename-without-extension>' systemd/ scripts/ tests/ docs/ MANIFEST.md` (automation/test/doc census); safe runs of check-prerequisites.sh and audit-wisdom-first.sh; static logic review of check-live-config-drift.sh and smoke-boot-check.sh (smoke-boot never executed: it spawns a real `opencode run`) | task-6-wiring.json, task-6-wiring.txt, task-6-smoke-static.txt |
| 7 | `git log -1 --format='%ci' -- <path>` (commit date as the staleness signal, mtimes ignored as checkout artifacts); `grep -oE 'wisdom-[a-z-]+\.sh' skills/wisdom/SKILL.md \| sort -u` vs `ls scripts/wisdom/*.sh \| grep -v test- \| xargs -n1 basename \| sort -u`, diffed with `comm -13` | task-7-staleness.json, task-7-doc-gap.txt |
| 8 | Baseline: `/usr/bin/time -f '%e' jq -c --arg q 'plugin' 'select((.body // "") \| ascii_downcase \| contains($q))' ~/.sisyphus/wisdom/system.jsonl >/dev/null` (median 0.08s of 3); jq-spawn counting via a counting PATH shim that `exec`s `/usr/bin/jq`; static spawn enumeration from `wisdom-search.sh:411-489` + `wisdom-common.sh` | task-8-search-rca.md, task-8-scaling.txt |
| 9 | Per-entry classification (merge/delete/archive rules quoted in the evidence) applied to the Task 3 violation set; duplicate-body analysis via `jq -r '.body' \| sort \| uniq -d` plus whole-body verification | task-9-gc-analysis.md, task-9-never-accessed.txt, task-9-duplicates.txt |
| 10 | Synthesis of task-4-usage.json disposition + `docs/wisdom.md:55-443` script reference; no new measurement | task-10-deadweight.md, task-10-no-dead.txt |
| 11 | Drift table: `for p in $(jq -r '.planes[].paths[]' configs/stack-locations.json); do ep=$(eval echo "$p"); [ -e "$ep" ] && echo "EXISTS $p" || echo "MISSING $p"; done`; live-but-undeclared scan: classify every active patch `target_install_path` with `path-classifier.py` | task-11-accuracy.md, task-11-false-positive.txt |
| 12 | Three-source contract comparison: `grep -oE 'candidate\|verified\|published' \| sort -u` across `skills/wisdom/SKILL.md`, `docs/wisdom.md`, `wisdom-common.sh`; gap re-derivation identical to Task 7 | task-12-skill-staleness.md, task-12-contract.txt |
| 13 | Static source reading of the 7 tools (import graph, policy loading); count assertion `python3 -c "...automation_wired_count..."` over task-6-wiring.json | task-13-overlap.md, task-13-automation-gap.txt |
| 14, 15 | Decision matrices synthesized from Tasks 8-13 evidence; rules fixed before verdicts; no new measurement, no execution | task-14-wisdom-decision.md, task-14-followup.txt, task-15-tools-decision.md, task-15-omo-guard.txt |

### Evidence-file index

All files below exist in `.sisyphus/evidence/perf-review-wisdom-operator-tools/` (the directory's README.md carries the same index): baseline.txt, inventory.txt, versions.txt, task-1-scaffold.txt, task-1-inventory.txt, task-2-search-bench.txt, task-2-search-empty.txt, task-3-store-health.json, task-3-malformed.txt, task-4-usage.json, task-4-usage.meta.json, task-4-no-dead-claim.txt, task-5-tools.txt, task-5-tools.json, task-5-argparse.txt, task-6-wiring.json, task-6-wiring.txt, task-6-smoke-static.txt, task-7-staleness.json, task-7-doc-gap.txt, task-8-search-rca.md, task-8-scaling.txt, task-9-gc-analysis.md, task-9-never-accessed.txt, task-9-duplicates.txt, task-10-deadweight.md, task-10-no-dead.txt, task-11-accuracy.md, task-11-false-positive.txt, task-12-skill-staleness.md, task-12-contract.txt, task-13-overlap.md, task-13-automation-gap.txt, task-14-wisdom-decision.md, task-14-followup.txt, task-15-tools-decision.md, task-15-omo-guard.txt.

### Measurement caveats

Usage telemetry comes from `events.jsonl`, a 1000-line rolling ring (`WISDOM_EVENTS_MAX_LINES=1000`, wisdom-common.sh:27) that was at cap during the whole review. Event counts are therefore snapshot-bound to the window 2026-08-05T22:42:30Z to 2026-09-15T08:37:19Z (~41 days), not stable identifiers; zero events means "not run within the retained window", never "never runs" (task-4-usage.meta.json, task-10-deadweight.md).

## Wisdom metrics

Raw measurements from Tasks 2, 3, 4, and 7.

**Search benchmark** (task-2-search-bench.txt): wall-clock medians of 3 samples per class, `--limit 10`, run against the live script with no `--touch` (store sha256 verified identical before and after):

| Query | Matches | Median |
|-------|---------|--------|
| `zzzznonexistentqueryzzz` | 0 | 0.41s |
| `acquitted` | 1 | 1.11s |
| `absent` | 5 | 4.82s |
| `plugin` | 32 | 20.47s |

Scaling is monotonic and linear in match count: `--limit` truncates after match+rank, so a 32-match query returning 10 rows still costs ~20s. No-match exits rc=1 with "No matching entries found." on stderr, which is the documented contract, not a failure (task-2-search-empty.txt). Historical search telemetry (n=425 events before the benchmark) shows p50=356ms, p95=4900ms, max=85217ms, consistent with the curve.

**Store health** (task-3-store-health.json): `system.jsonl` holds 177 entries (243 store-wide across `projects/*.jsonl`). Against the GC script's own criteria replicated epoch-exact (cutoff 2026-06-17): never-accessed over 90 days = 59, last-accessed over 90 days = 16, low-score = 0 (structurally unsatisfiable at the default `min_score=0`), total violating = 75 of 177 (42.4%); 161 of 177 entries (91%) have never been read back. Metadata gaps = 27; duplicate fingerprints = 1; the events ring is at its 1000-line cap. The `duplicate_bodies=3` figure is a line-count artifact of `uniq -d` on multi-line bodies; the true count is 1 duplicate-body group (see Wisdom analysis).

**Script usage** (task-4-usage.json, task-4-usage.meta.json): 7 scripts active, 10 referenced-idle, 0 no-evidence. Active by event count: search 425, write 290, delete 205, edit 40, nominate 18, publish 11, closeout 11. Every script has ref_count at least 4 (wisdom-common.sh highest at 40; wisdom-restore.sh lowest at 4), which is why "no-evidence" never occurs and no script is claimed dead (task-4-no-dead-claim.txt).

**Staleness** (task-7-staleness.json, task-7-doc-gap.txt): `skills/wisdom/SKILL.md` last committed 2026-05-08 (0822a28); `scripts/wisdom/` last committed 2026-08-06 (8d400e8): a 3-month doc lag. SKILL.md documents 6 of 17 non-test scripts; gap_count = 11 (operator-facing gap 10, since wisdom-common.sh is a sourced library). None of the 11 names appears anywhere in SKILL.md. Docs are fresh (`docs/wisdom.md` 2026-09-05, `docs/skills.md` 2026-09-14).

## Wisdom analysis

Findings from Tasks 8, 9, 10, and 12.

**Search root cause: 28 jq spawns per matched entry** (task-8-search-rca.md, task-8-scaling.txt). The per-entry match loop (wisdom-search.sh:418-454) spawns 15 jq processes per matched entry and the ranking pass (:480-487) spawns 13 more, because `wisdom_normalize_record` is itself 9 jq calls and runs twice per entry. Empirical confirmation with a counting PATH shim: 0-match run = 16 spawns (the per-file filter plus event emit; the loop is skipped), and the per-match slope is 29.25 spawns. Cost is jq process startup (~22ms each), not data volume: the whole store is 243 lines across 12 files. Total time is linear, `T ≈ 0.41 + 0.62·N`, marginal cost 0.58-0.93s per match. Against the task-specified single-jq baseline of 0.08s (system.jsonl, median of 3), the live search is 13.9x slower at 1 match, 60.3x at 5, and 255.9x at 32; against the strictest ranking-inclusive floor of 0.12s it is 9.25x/40.2x/170.6x. The fix (proposal P1) batches filter+normalize+rank into one jq pass per store file, estimated at ~0.3-0.5s for any match count. The canonical ranking order (docs/wisdom.md:126-128) must be preserved exactly and is guarded by `test-wisdom-compat.sh:112-132`.

**Store GC: 75 violations classified, projection 177 to 103** (task-9-gc-analysis.md). Applying archive/delete/merge rules to the 75 violations yields merge 3, delete 8, archive 64. The merge group is the only true whole-body duplicate in the store: three byte-identical spacebot service-check entries (20260429-141446-s5j0, 20260429-142050-hpvz, 20260429-142210-ucu8), which is also the only duplicate fingerprint. The 8 delete candidates are one retracted test fixture and 7 auto-nominated command logs with no status field. Projection if the classified plan is applied: 177 to 103 active entries, violations 75 to 0, `system.jsonl` from 236,408 to 174,439 bytes. Three caveats: a single `wisdom-gc.sh --action archive` is coarser and would also archive the delete and merge candidates, so the plan needs per-entry actions; 9 test/QA fixtures are archive-only because `status=active` or `authority=published` blocks delete; and `projects/*.jsonl` holds 30 more violations under the same criteria, out of scope. No mutation was performed: the store sha256 was recorded before and after.

**No dead scripts; three consolidation candidates** (task-10-deadweight.md, task-10-no-dead.txt). The anti-overclaim rule holds throughout: absence of events in a capped window is not proof of disuse. Five scripts are strong should-emit-but-silent (sync, archive, gc, merge, migrate: every completed run should emit its mapped event, zero observed), observe is weak-silent (only `reset --yes` emits), and four have no event name at all (restore, manifest-write, knowledge-constants, wisdom-common). Three consolidation candidates emerge on function and usage: archive into `gc` (the bulk superset), restore into `migrate --restore` (restore is a strict subset with the lowest ref_count, 4, and no telemetry event, a coverage gap for a store-mutating operation), and knowledge-constants into wisdom-common (two sourced constant sources risk drift).

**SKILL.md is stale as an inventory, current as a contract** (task-12-skill-staleness.md, task-12-contract.txt). Verdict: stale. The Commands section omits 65% of the surface, including wisdom-delete.sh (205 events, the 3rd most-used script) and the entire maintenance verb set, so an agent reading only SKILL.md would conclude those tools do not exist. The canonical contract section is a different story: authority, status, and provenance token sets are identical across SKILL.md, docs/wisdom.md:84-86, and wisdom-common.sh:11-13, drift = 0. SKILL.md's evidence-verification ladder paraphrases 3 of the 6 AGENTS.md states and stops one level short of `real_project_behavior_proven`, an over-claim risk of exactly one level; aligning vocabulary is a recommendation, not a correctness bug.

## Wisdom decision framework

Decision record from Task 14 (task-14-wisdom-decision.md, follow-up coverage asserted in task-14-followup.txt). Rules were fixed before verdicts: R1 search speedup ratio over 5x triggers tune; R2 store violation share over 20% triggers tune; R3 per-script disposition from usage plus consolidation analysis; R4 skill-doc gap over 0 triggers tune. Any tune must preserve the canonical contract, guarded by `test-wisdom-compat.sh`.

Verdict census across 20 rows (search, store, 17 scripts, skill doc): **keep 15, tune 4, consolidate 3, retire 0, instrument-more 0.**

- **Tune, search** (rows 1 and 3, proposal P1): the batched single-pass rewrite described above, contract-guarded.
- **Tune, store** (row 2, proposal P5): apply the Task 9 classified plan per-entry (archive 64, delete 8, merge 3 into 1), never a single coarse `gc --action archive`. This verdict fires the Task 17 GC gate (42.4% over the 20% threshold).
- **Tune, skill doc** (row 20, proposal P6): additive update documenting the 10 operator-facing scripts, keep the verified contract section, adopt the 6-state evidence taxonomy with the capstone. This row also recommends firing the Task 19 test-wiring gate (3 orphaned `scripts/wisdom/test-*.sh` absent from `tests/run_all.sh`).
- **Consolidate 3** (proposals P2, P3, P4): archive into gc (with an ergonomics check first), restore into `migrate --restore` (or, if retained, add a `wisdom.lifecycle.restore` event), knowledge-constants into wisdom-common (low priority, touches 3 caller groups).
- **Keep the rest**, including wisdom-delete.sh: Task 10's prose called all of group A referenced-idle, but its own verified table marks delete active with 205 events; the table is the signal, the sentence was a summary error, and delete stays on usage evidence.

All follow-ups are proposals P1-P6; nothing was executed by the review.

## Operator-tools metrics

Raw measurements from Tasks 5, 6, and 7.

**Runtime and exit-code matrix** (task-5-tools.json, task-5-tools.txt, task-5-argparse.txt): all 7 Python tools ran within a 30s timeout, every runtime between 0.02s and 0.43s. Exit-code contract across the set: 0 = clean, 1 = findings (documented, not a crash), 2 = argparse usage error.

| Tool | Runtime | rc | Key result |
|------|---------|----|------------|
| stack-doctor | 0.43s | 1 | 1 blocking finding: `repo_root_omo` (repo-root .omo exists while declared forbidden); all 3 live config symlinks intact |
| drift-detector | 0.02s | 0 | drift 0; all 4 store-to-live mappings `same_symlink` |
| patch-guard | 0.04s | 1 | 24 of 26 targets forbidden, 2 allowed (repo root) |
| path-classifier | 0.03s | 0 | live opencode.json classified `control_plane`, writable |
| secrets-path-audit | 0.02s | 0 | 378 tracked paths on stdin, 0 secret findings |
| source-identity-check | 0.08s | 0 | `~/src/opencode` is a valid opencode checkout |
| legacy-name-classifier | 0.08s | 1 | 1087 occurrences: 823 historical, 253 deprecated-local, 8 required-upstream, 3 unclassified |

The patch-guard breakdown is 16 findings on the OMO runtime fork, 4 on `~/src/opencode`, and 4 on `~/.opencode/bin/opencode`. Note a correction: Task 5's summary prose said 6 src/opencode findings, but its own raw capture shows 4, and Task 11 verified the authoritative count is 4 (task-11-accuracy.md); this report carries 4.

**Wiring census** (task-6-wiring.json, task-13-automation-gap.txt): exactly 1 of 11 operator tools is automation-wired, `check-live-config-drift.sh` as ExecStart #2 of the 30-minute `opencode-patch-integrity-check.service`. All 7 Python tools are manual-only (0/7 wired) but test-covered (7/7, via `tests/test_stack_safety_scripts.sh`, `tests/test_stack_path_classifier.sh`, and `tests/regressions/006`); the 4 shell tools have zero test references. The relationship is inverted: the one automated tool is the untested one. Safe runs: check-prerequisites.sh rc=0 (37 passed, 3 optional warnings, 0 failed); audit-wisdom-first.sh rc=0 (all PASS). The static reviews found check-live-config-drift.sh logic correct (detection covers unstaged, staged, and untracked; fails safe on a missing repo) and smoke-boot-check.sh assertions sound (never executed; it spawns a real `opencode run` at API cost).

**Staleness** (task-7-staleness.json): all 7 Python tools were born in a single commit 2026-06-18 (ae44ac5) and have not changed since. No divergence between docs and tools was found in this set except the MANIFEST.md:284 inaccuracy noted in the analysis below.

## Operator-tools analysis

Findings from Tasks 11 and 13.

**Policy drift, not tool defects** (task-11-accuracy.md, task-11-false-positive.txt). Every one of the 9 declared paths in `configs/stack-locations.json` exists; the drift is classification versus reality, in three parts:

1. **The .omo contradiction.** `~/ez-omo-config/.omo` is declared `forbidden_zone` (writable=false) with the note that it "must never be created", yet it is the live OMO planning state: 49 plans, 95 evidence dirs, 22 notepads, 9.3 MB, with `boulder.json` written during the review itself. It is gitignored (`.gitignore:16`), so the never-commit intent is already enforced by git. This contradiction is what makes stack-doctor block. The framing is policy reconciliation, never deletion.
2. **Two undeclared live roots.** `~/oh-my-openagent-v4.19.2` is the canonical OMO runtime (opencode.json:28 loads it config-relatively) and `~/src/opencode` is the OpenCode source checkout (validated by source-identity-check), but the policy declares neither. Because the declared `source_plane` (~/oh-my-openagent) is a sibling rather than a parent of the fork, `path-classifier.classify()` (path-classifier.py:68-84) matches no plane, returns `unknown`, and patch-guard.py:85 forbids `unknown`. The mechanism is confirmed: the policy is wrong, not the path. These two roots produce 20 of patch-guard's 24 forbidden findings (16 fork + 4 src/opencode).
3. **Forbidden by design, not drift.** `~/.opencode/bin/opencode` is a declared `control_managed_runtime_child` target; its 4 findings are intentional install-managed denials and need no manifest change.

Projected effect of reconciling items 1 and 2 (inference): patch-guard forbidden drops from 24/26 to 4/26 and stack-doctor's blocking finding clears.

**No consolidation candidates; one documentation inaccuracy** (task-13-overlap.md). No tool fully subsumes another. patch-guard imports path-classifier (a consumer, not a duplicate; removing the classifier breaks patch-guard). stack-doctor and drift-detector are complementary by design: structural symlink integrity (3 mappings) versus content equivalence (4 mappings, adds oh-my-openagent.json); they can legitimately disagree on the same file. The inaccuracy: MANIFEST.md:284 claims stack-doctor consumes `stack-locations.json`, but its source has zero references to that file; its `repo_root_omo` check hardcodes `repo/.omo`, duplicating the forbidden-zone plane. Consequence: policy changes silently do not propagate to stack-doctor. The automation gap is scheduling, not correctness: the 30-minute timer runs only a git-status of `configs/`, so store-to-live content equivalence (drift-detector, 0.02s) and patch-target zones (patch-guard, 0.04s) are checked by nothing automated.

## Operator-tools decision framework

Decision record from Task 15 (task-15-tools-decision.md, `.omo` non-deletion guard asserted in task-15-omo-guard.txt). Rules R1-R6 were anchored to metrics before verdicts; R1 (zero full-subsumption pairs) forecloses retire and consolidate everywhere.

Verdict census across 12 rows: **keep 8, tune 3, instrument-more 1, retire 0, consolidate 0.**

- **Tune, `configs/stack-locations.json`** (row 8): drift = 1 policy contradiction + 2 undeclared roots, over the 0 threshold. This verdict **fires the Task 18 gate**. The Task 18 spec: add a `runtime_fork` plane for the OMO fork and an `opencode_source_plane` for `~/src/opencode` (both writable), reclassify `.omo` out of `forbidden_zone` into a `repo_runtime_state` plane (reclassification only; `.gitignore` already enforces the never-commit intent; deletion is proposed nowhere), leave `control_managed_runtime_child` and `secret_or_auth` untouched.
- **Tune, stack-doctor** (row 1): a code metric, not policy drift. Refactor the hardcoded `repo/.omo` check to call `path-classifier` against the policy file, and correct MANIFEST.md:284 in the same change. Note that Task 18's reconciliation alone clears the current blocking finding; the refactor removes the silent-drift class permanently.
- **Tune, legacy-name-classifier** (row 7): 3 of 1087 occurrences unclassified (0.28%), all the `oh-my-openagent` token under `.opencode/skill/add-provider/`, a path prefix missing from `classify()`. Single-rule fix, acceptance check is the 0-unclassified invariant.
- **Instrument-more, drift-detector** (row 2): wiring 0/7, runtime 0.02s, accuracy clean. Proposal: add as ExecStart #3 of the integrity service or a companion timer, so content equivalence is checked on the 30-minute cadence.
- **Keep the other 8**, including patch-guard deliberately: its 24/26 forbidden output is 20/24 policy-caused noise until Task 18 lands, so timer wiring is deferred behind Task 18 on purpose; after reconciliation the output becomes signal.

All follow-ups are proposals; no tool, config, or unit file was modified by the review.

## Residual risk and unverified states

Per the repo's evidence-state discipline (AGENTS.md, "Live Deployment Claim Discipline"), this section separates what was observed from what was projected, and marks everything not observed end-to-end.

**Evidence states claimed.** The tool and script runs cited above (Tasks 2, 5, 6) are runtime observations of the live scripts at their live paths: runtime_loaded for those specific invocations. Everything else in this report is repo_implemented or analysis over verified evidence. **Nothing in this review is claimed as real_project_behavior_proven.** All decision-framework verdicts are recommendations; all projections are inference, labeled as such.

**The wisdom store was not mutated by this review.** `system.jsonl` sha256 `d8226f503aafbaef163cf65f137f7d65bc41d7c73b935a7be4caa5b765c23d0f` was recorded unchanged across Tasks 9 and 14. Store mutations happen only in Task 17, which is decision-gated and, as of this assembly, not executed by this review.

**Remediation gate status (all three FIRED on this evidence).** Task 17 (wisdom store GC): FIRED, by the store verdict tune at 42.4% over the 20% threshold (task-14-wisdom-decision.md row 2). Task 18 (stack-locations reconciliation): FIRED, by the policy drift verdict tune, 1 contradiction + 2 undeclared roots over 0 (task-15-tools-decision.md row 8). Task 19 (wisdom test wiring): FIRED at recommend strength, by the skill-doc row's recommendation (task-14-wisdom-decision.md row 20). Tasks 17-19 may be executing concurrently with this assembly; any `task-17-*`, `task-18-*`, or `task-19-*` evidence files appearing in the evidence dir belong to those waves and are outside this report, which covers the review waves only.

**Not verified live:**

- Not verified live: post-fix search performance. The ~0.3-0.5s estimate for proposal P1 is static analysis plus floor measurements; no patched `wisdom-search.sh` has been built or run.
- Not verified live: post-reconciliation patch-guard output. The 24/26 to 4/26 projection is static classification over the current registry; Task 18 has not been applied.
- Not verified live: post-GC store state. The 177 to 103 projection applies the classified plan on paper only; Task 17 has not been applied.
- Not verified live: drift-detector timer wiring, the stack-doctor refactor, the legacy-name-classifier prefix rule, and the SKILL.md update. All are proposals with no implementation.
- Not verified live: `real_project_behavior_proven` for any reviewed artifact (no end-to-end behavior observation was in scope for this review).

**Residual risks and standing caveats.** Usage counts are snapshot-bound to the ~41-day ring window and will drift as the ring rotates; re-derive, do not reuse, if re-measured (task-4-usage.meta.json). The `projects/*.jsonl` stores carry 30 additional GC violations under the same criteria, out of scope for Task 9 and unaddressed by the Task 17 projection (task-9-gc-analysis.md). patch-guard remains noisy (24/26 forbidden) until Task 18 lands, so its output should not be treated as signal in the interim. MANIFEST.md:284 remains inaccurate until the stack-doctor follow-up corrects it. `wisdom-restore.sh` mutates the store with no telemetry event until P3 closes the gap in either direction. smoke-boot-check.sh was reviewed statically only, never executed, by design.

**Reader action.** The gates are decisions, not work orders: approve or reject Task 17 (store GC per the classified plan), Task 18 (policy reconciliation, never `.omo` deletion), and Task 19 (test wiring) on the evidence cited here. Nothing else requires action; no action was taken.
