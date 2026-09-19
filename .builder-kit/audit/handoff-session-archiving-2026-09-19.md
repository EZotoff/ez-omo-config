# Handoff: OpenCode session archiving — investigate stall, automate weekly, 30-day retention
- emitted: 2026-09-19 21:05 CEST | source session: opencode central dev session (ez-omo-dash repo) | source heads: ez-omo-config @ 5528c7b (master, clean); ez-omo-dash @ 50d9bd9 (feat/project-list-mode, dirty — other agents' WIP, hands off)
- supersedes: none
- repo note: this is OPS work and lives here per the portable-supervisor contract's
  session-run discipline ("Ops/config/docs → ez-omo-config"). The archiver itself is
  machine-global tooling under `~/.local/share/opencode/` — this repo is its versioning
  and automation home going forward.

## Mission
OpenCode session archiving (`~/.local/share/opencode/opencode_maintenance.py`) silently
stopped after **Jul 22**. The session DB now holds **7,570 sessions / 177,586 messages**,
**1,181 sessions older than 60 days** (oldest 2026-06-23), and bench campaigns are the
dominant noise source (ez-omo-bench = 84% of recent DB writes; 5,234/7,570 sessions are
subagent children). Operator requirements, verbatim intent:
- **Retention: sessions stay for 1 month.**
- **Cadence: archiving runs EVERY WEEK** (automated — the manual monthly habit is what died).
- **Bucket semantics: by session last activity (`time_updated`), not creation date** —
  operator's intuition, and the existing script already agrees (see State ¶4). Confirm in
  analysis, then formalize.
Done-condition: a weekly systemd user timer runs the archiver; retention cutoff = 30 days
on `time_updated`; the Aug+Sep backlog is archived and pruned; the omo-pulse dashboard no
longer shows 2-month-old session cards.

## Entry artifacts (read these first)
1. `~/.local/share/opencode/opencode_maintenance.py` — THE archiver. argparse, month
   buckets via `_month_bucket(time_updated)` (line 302), cutoff query already
   `WHERE time_updated < ?` (line 288), `_preflight_mutating_command` guard for
   destructive runs. Last modified Jul 15 12:39. Consider importing/versioning it in this
   repo (ops tooling belongs here) and installing a copy to the live location.
2. `~/.local/share/opencode/archives/` — output evidence:
   `archive-2026-03.db.gz` (created Apr 15) → `04.db.gz` (May 15) → `05.db.gz`+`06.db.gz`
   (both Jul 15) → **`archive-2026-07.db` (Jul 22, .gz compression step skipped)** → then
   nothing. Plus `veran-bench-spam-20260914.db` / `-20260915.db`: ad-hoc bench-spam
   cleanups already happened twice in September — bench sessions are a known problem.
3. `~/.local/share/opencode/archive_sessions.py` (Mar 8) + `cleanup_db.py` (Mar 12) —
   older JSONL-export generation, likely superseded by the maintenance script; confirm
   before touching.
4. `~/.local/share/opencode/archive/` — Mar 8 per-project JSONL exports (the oldest
   generation, last run Mar 8).

## State (all measured 2026-09-19 evening, read-only probes)
- No scheduler exists for the archiver: no systemd user timer, no crontab entry. The
  monthly runs were manual invocations; the habit stopped after Jul 22. (Do NOT go
  digging through shell history to find who ran it — irrelevant.)
- Age histogram (weeks ago : session count): 0:1520, 1:1181, 2:913, 3:387, 4:1038,
  5:402, 6:441, 7:320, 8:479, 9:719, 10:178, 11:2, 12:1 — accumulation in every bucket,
  no pruning cliff since ~week 12.
- ez-omo-dash project alone: 62 sessions, 14 older than 60d (operator sees these cards in
  the omo-pulse focus remote — that is the visible symptom that triggered this handoff).
- DB is WAL mode; 5,234/7,502 sessions have `parent_id` (subagent children); bench
  campaigns spawn the bulk of them (top parents carry 60–122 subagents each).
- Downstream coupling: the omo-pulse dashboard (ez-omo-dash, :4300) rebuilds snapshots
  every 10s with synchronous SQLite reads over this DB; multi-second UI freezes scale
  with row volume. Pruning 60d+ sessions directly shrinks those freezes. (Its worker-
  thread read fix is tracked separately in ITS backlog — not this session's job.)

## Next steps (each with done-condition)
1. **Reconstruct the archiver's CLI + stop cause.** Read `opencode_maintenance.py` fully;
   document exact commands for archive + prune + the preflight behavior. Why it stopped:
   the evidence says manual invocations simply ceased (no scheduler ever existed) — the
   fix is scheduling, not debugging a crash. Done-condition: the script versioned in this
   repo + a written CLI cheat-sheet committed alongside.
2. **Decide + document retention semantics.** Recommendation to validate: cutoff on
   `time_updated` (last activity) at 30 days — matches operator intent, matches the
   script's existing query, and protects long-lived sessions that are still in use (any
   activity refreshes `time_updated`). Edge cases to settle explicitly:
   - sessions currently attached/open in panes (the interactive daemon's live sessions):
     exempt or archive-resurrect? Prefer exempt (detection options: the opencode daemon
     knows connected clients; or cross-check the omo-pulse zellij layout dump).
   - long-running bench campaign sessions (weeks-old but active): `time_updated` protects
     them automatically.
   - archive file grouping for WEEKLY runs: keep per-month files keyed on the session's
     activity month (weekly runs append), or switch to per-week files — pick one and
     document; do not leave both naming schemes in play.
3. **Automate weekly.** Install a systemd user timer + service in this repo (follow the
   repo's unit conventions). Weekly cadence per operator. The service should log to a
   stable file and exit 0 on "nothing to do". Done-condition: `systemctl --user
   list-timers` shows it; forced manual run succeeds and produces an archive artifact.
4. **Catch up the backlog.** Run the archiver for the Aug+Sep buckets (and compress
   `archive-2026-07.db`, which was left uncompressed). Respect the preflight; prefer a
   window when few agents run. Done-condition: sessions older than 30d count ≈ 0
   (excluding exempted live sessions); archives exist for every month ≤ last month;
   `SELECT COUNT(*) FROM session` drops by ~1,000+.
5. **Bench-side spam mitigation — coordinate, don't implement here.** Bench campaigns are
   the volume driver (84% of recent writes; campaigns spawn 60–122 subagent sessions
   each). The bench repo needs a structural mitigation (e.g. archive campaign sessions at
   campaign end) — that belongs in a bench-repo session; from here, document the proposal
   in this repo (ops home) so the operator can hand it over. Done-condition: proposal
   committed to docs/.
6. **End-to-end verification.** Rerun the age queries (recreate them; they were run in
   the source session via bun:sqlite readonly): >60d count near zero, histogram cliff at
   the retention edge. Then confirm the omo-pulse remote (`ez-omo-dash` :4300
   `/?view=remote`) no longer lists 2-month-old cards.

## Prohibitions
- NEVER write to OpenCode's DB except through the maintenance script's own
  archive+prune flow with its preflight satisfied. Everything else stays read-only.
- Do not run archive/prune while bench campaigns or many agents are mid-run — schedule
  around activity (the preflight helps, but do not rely on it alone).
- Do not delete or recompress `archive-2026-07.db` without first verifying archive
  integrity (it is uncompressed data, not garbage).
- Do not modify the omo-pulse repo (ez-omo-dash) — dashboard-side follow-up is
  coordinated by the operator in that repo's own session.
- Do not implement bench-repo code changes — that is a separate bench-repo session (see
  step 5: propose here, implement there).
