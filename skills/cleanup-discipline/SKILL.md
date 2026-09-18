---
name: cleanup-discipline
description: Disciplined disk-cleanup workflow for reclaiming storage without destroying live runtimes, unpushed work, or unrecoverable data. Use for ANY disk-space cleanup, storage reclamation, "what can we delete", purge/prune campaigns, or when asked to free up space — survey, classify, verify, capture, delete, report.
---

# Cleanup Discipline

<role>
You free disk space without losing data. Every deletion is either provably regenerable, verified redundant elsewhere, captured first, or explicitly operator-approved. Speed comes from parallel surveys, never from skipping verification.
</role>

## Phase 0 — Scope and authority

Establish from the operator, before proposing anything:
- **What is fair game** (e.g. "benchmark runs may be deleted" vs "regular sessions are archived and kept"). Ambiguity here is the #1 source of wrong deletions.
- **Archive policy**: which classes get archived-before-delete vs deleted outright. If the operator says "don't archive X", still capture *small result artifacts* (metrics, summaries) — bulk and results are different things.

## Phase 1 — Survey (read-only, parallel)

1. `df -h` first; every later number is relative to it.
2. Layered `du -xh --max-depth=1 | sort -rh` — root, then drill the top entries. `-x` to stay on one filesystem.
3. **Close the ledger.** Your itemized total must ≈ `df` used. If it doesn't, you are blind to something: non-root `du` cannot see root-only dirs — check `/var/lib/docker` (`docker system df`), `/var/lib/containers`, reserved blocks, and `lsof +L1` for deleted-but-held-open files. (Real case: 160G of Docker invisible to a non-root survey made a report 45% wrong.)
4. Re-scan on multi-day campaigns — caches regrow and new runs land between passes. Diff against the previous scan before re-proposing.

## Phase 2 — Classify every candidate

| Class | Examples | Rule |
|---|---|---|
| Regenerable cache | uv/npm/pip caches, HF cache, torch extensions | Prefer the tool's own clean (`uv cache clean`, `docker system prune`) over `rm` |
| Redundant copy | zips with extracted copies, shadow caches | **Verify redundancy before believing it** (Phase 3) |
| Result artifacts | metrics, reports, transcripts | Capture (Phase 4), then bulk is deletable |
| Runtime-tracked | plugin installs, patched builds, service dirs | **Default: do not touch** — see guard below |
| Active | running daemons' dirs, in-progress runs | Off-limits — check mtimes, `pgrep`, `docker ps` first |

**Runtime-tracked guard — never judge a directory by its name.** Version-suffixed dirs (`app-v4.19.2/`) are often the *live* install. Before deleting any dir that looks like an old checkout, old release, or cache:
1. Find what references it: configs, plugin entries, scripts, services (`grep -r` the dirname across `~/.config`, `~/.opencode`, project configs).
2. Run `live_patch_check` / inspect `.sisyphus/patches/` — if patches target paths under it, it is runtime-tracked; route through `/patch-tracker` instead.
3. If it is a git repo, run `git log --oneline @{u}..` (or `--branches --not --remotes`). Unpushed commits die with the worktree — surface them to the operator, never delete silently. (Real case: `~/oh-my-openagent-v4.19.2` was the live OMO runtime; deleting it broke the plugin and permanently lost the quota-only patch. Its "1 modified file" was build churn, but that check is no substitute for the reference/patch/unpushed checks.)
4. For >1G targets you did not create this session, consult wisdom/manifest (`wisdom-search.sh "<dirname>"`).

## Phase 3 — Verify redundancy claims

- "Already extracted" → find the extraction *locally* first; if absent, check other machines (`ssh <host> find …`, compare byte sizes for zips). (Real case: a zip assumed extracted locally had no local extraction — and was later proven byte-identical on another machine. Both checks changed the decision.)
- A dirty git file may be build churn — diff it. Minified-bundle hash bumps + variable renames = churn, deletable. But churn-verdicts do NOT skip the reference/patch/unpushed checks in Phase 2.
- Backup files: check age and whether the operator still wants rollback capability. A 1-day-old pre-restore backup is an operator decision, not a cache.

## Phase 4 — Capture before delete

- Identify the small result files inside bulky dirs (`metrics.json`, `run.json`, reports) vs working material (caches, fixtures, transcripts).
- Copy with preserved structure (`rsync -a --include=… --exclude='*'`), **verify the capture** (count files against expectation — e.g. "11/11 metrics.json"), tarball into the project's report location, then delete the bulk.
- Bench precedent: 40K of metrics captured from 36G of runs; earlier bench purges preserved 1900+ session transcripts into dated archive DBs. Follow that shape.

## Phase 5 — Execute

1. Prefer dedicated prune/clean commands over `rm`: `docker system prune` (safe) before `docker image prune -a` (aggressive — only with an operator-reviewed hit-list), `git count-objects -vH` then `git gc --prune=now` for bloated git dirs (check `size-garbage` — orphaned objects often dwarf real ones).
2. **First guard block = stop and hand the operator the exact command.** Rephrasing or reformulating a blocked deletion is a workaround, not a retry. Sudo-required items are not agent tasks — batch them into one paste-able block with per-item comments.
3. Group deletions into batches by risk class; get per-batch approval (`question` tool with explicit target lists and sizes). Never bundle an uncertain item into an approved batch.
4. Never delete inside a dir whose owning process is alive (a terminal's cache will be recreated mid-`rm` and error — that's a sign to leave it, not fight it).

## Phase 6 — Report with evidence

- `df` before → after; per-item freed vs predicted.
- Every skipped item **with the reason** (still-only-copy, runtime-tracked, active, needs sudo).
- Outstanding operator actions (sudo commands, aggressive-prune hit-lists) as a copy-paste block.
- Record anything genuinely new (a shadow-cache location, a blind spot) into wisdom so the next cleanup session starts smarter.

## Failure register (from real incidents)

| Failure | Consequence | Rule that prevents it |
|---|---|---|
| Deleted live OMO runtime dir (2026-09-18) | plugin dead for hours; quota-only patch lost forever | Phase 2 guard (references, patch-tracker, unpushed commits) |
| Ledger didn't sum to `df` | 160G Docker missed; proposal 45% wrong | Phase 1 step 3 |
| Deleted a zip assumed extracted | nearly destroyed the only local training-data copy | Phase 3 |
| Rephrased a guard-blocked `rm` | guard escalation; distrust | Phase 5 step 2 |
| Old cleanup session's transcript purged by later sweep | zero learnings extractable | Phase 4 (capture includes session history) |
| Sudo items deferred across sessions | journal vacuum pending for days | Phase 6 (batch into one operator block) |
