# Proposal: Bench-Campaign Session-Spam Mitigation (for the ez-omo-bench repo)

Status: **proposal only** — implementation belongs to a bench-repo session (handoff
2026-09-19, step 5). Ops home: this document. Author context: session-archiving run, 2026-09-19.

## Problem

Bench campaigns are the dominant volume driver in the OpenCode session DB:

- 84% of recent DB writes originate from bench activity (measured 2026-09-19).
- 5,234 / 7,570 sessions carry `parent_id` (subagent children); top bench parents spawn
  **60–122 subagent sessions each**, one campaign at a time.
- The DB reached 7.5k sessions / 179k messages between archiver runs; dashboard snapshot
  rebuilds (omo-pulse, 10s cadence, synchronous SQLite reads) freeze in proportion to row volume.
- Ad-hoc cleanups were already needed twice in September
  (`archives/veran-bench-spam-20260914.db`, `...-20260915.db`) — reactive, not structural.

Weekly 30-day retention alone would still let one heavy week deposit thousands of
short-lived rows into the hot DB.

## Proposed mitigation (recommended)

**Archive campaign sessions at campaign end, inside the bench launcher.**

1. **Detect campaign sessions deterministically.** Two stable markers already exist:
   - `session.directory` = the bench repo / its worktrees;
   - `session.title` carries the `bench-deleg:` prefix (delegated cases) or the campaign
     slug (e.g. `deep-glm53-v2-anchor-20260919`).
   Persist the full set of session IDs (parents + subagent children) in the campaign's
   run-artifacts directory at launch time (`bench-campaign` state already records unit/run IDs).

2. **At campaign end (success or failure — an `EXIT`/trap hook in `run-case.sh` and the
   campaign launcher), invoke the global archiver scoped to the campaign:**
   ```
   opencode_maintenance.py archive --days 0 --apply --where-id-file <campaign-session-ids.txt>
   ```
   This requires a small **enhancement to `opencode_maintenance.py`** (owned by
   ez-omo-config, this repo): a `--where-id-file` option that restricts
   `_select_eligible_session_ids` to an explicit ID list (`--days 0` = everything in the
   list). All existing safety properties carry over: monthly bucket copy, row-count
   validation, integrity checks, post-delete verification, preflight. No raw DB writes
   from the bench repo — it only calls the maintenance script, honoring the standing
   prohibition.

3. **Fallback if a campaign dies without running the hook:** the weekly timer still reclaims
   everything within ≤ 30 days of last activity (bench sessions are written during the
   campaign, so they age out together ~30 days after the campaign ends). The end-hook just
   shrinks the dwell time from weeks to minutes.

## Alternatives considered

- **Mark campaign sessions expired at creation** (backdate `time_updated`) — requires direct
  DB writes from bench code, violates the write-path prohibition, and breaks the dashboard's
  view of *running* campaigns. Rejected.
- **Cap subagent fanout / reuse a parent session for subagents** — reduces volume but changes
  bench semantics (per-subagent transcripts are the point of a bench). Rejected as primary;
  fine as a per-campaign opt-in.
- **Post-campaign direct DELETE** — bypasses archive+validate+verify; loses the transcripts
  the bench exists to produce. Rejected.

## Handoff notes for the bench-repo session

- Add the end-of-campaign hook + session-ID capture in `bin/run-case.sh` / the campaign
  launcher; keep artifacts under the campaign's run-artifacts dir.
- Ask an ez-omo-config session to add `--where-id-file` to `opencode_maintenance.py` first
  (small, testable, keeps a single write-path tool).
- Success criteria: after a campaign ends, `SELECT COUNT(*) FROM session WHERE directory
  LIKE '%ez-omo-bench%' AND id NOT IN (currently-running)` drops to ~0 within minutes, all
  removed rows present in `archives/archive-YYYY-MM.db(.gz)`, hot-DB integrity `ok`.
