# OpenCode Session Archiving — Retention Semantics & CLI Cheat-Sheet

Formalized 2026-09-19 (handoff: `.builder-kit/audit/handoff-session-archiving-2026-09-19.md`).
The archiver is [scripts/opencode_maintenance.py](../scripts/opencode_maintenance.py), versioned here and
symlink-installed to `~/.local/share/opencode/opencode_maintenance.py`. Automation:
`opencode-session-archive.timer` (weekly, Monday 04:30 local, `Persistent=true`).
Run log: `~/.local/share/opencode/session-archive.log`.

## Retention semantics (formal)

**Policy: a session is eligible for archive+prune when `session.time_updated < now_utc − 30 days`.**

- `time_updated` is the session's **last activity** timestamp (UTC ms epoch), refreshed on every
  message/part write. This matches the operator's intent ("sessions stay for 1 month", bucket by
  last activity) and the script's own cutoff query (`WHERE time_updated < ?`).
- Creation date is **never** used. A long-lived session that stays active never ages out.
- On archive: rows are copied into per-month archive SQLite files (see grouping below),
  row-count-validated, integrity-checked, then deleted from the hot DB inside one transaction with
  a post-delete count + integrity verification. Archival is lossless; `restore` brings a session back.

### Edge cases (settled)

1. **Sessions open in panes but idle > 30 days — NOT exempted (documented decision).**
   Exemption would require the archiver to introspect live daemon clients, which has no read-only
   path from a SQLite-only script. Mitigation instead: `restore` (below) reinserts a session and
   refreshes its `time_updated`, which also shields it from re-archiving for another 30 days.
   Weekly cadence keeps the accidental-loss window small; if a pane goes blank after a Monday
   04:30 run, restore from the newest monthly archive.
2. **Long-running bench campaigns (weeks-old but active)** — protected automatically: any campaign
   write refreshes `time_updated` and moves the whole window forward.
3. **Archive file grouping for weekly runs — per-month files, weekly appends (single scheme).**
   Target files stay `archives/archive-YYYY-MM.db`, keyed on each session's **activity month**
   (`_month_bucket(time_updated)`). A weekly run appends that week's eligible sessions to the
   matching month's file via `INSERT OR IGNORE` with additive column reconciliation (schema drift
   from OpenCode updates is handled). No per-week files exist or will be created.
4. **Compression**: after each apply, past-month `.db` archives are gzipped to `.db.gz` (read-back
   verified); the current activity month stays plain `.db` for appends. A `.db.gz` is re-materialized
   transparently if a late session needs to append to that month.
5. **Subagent children** (`parent_id` set) are archived/pruned on their own `time_updated` — no
   parent-child coupling. Bench-spam volume is addressed separately:
   [bench-session-spam-mitigation.md](bench-session-spam-mitigation.md).

## CLI cheat-sheet

All commands dry-run by default; add `--apply` to mutate. `--days` defaults to 30 (operator policy;
raised from the historical 5). DB: `~/.local/share/opencode/opencode.db`, archives:
`~/.local/share/opencode/archives/`.

```bash
M=~/.local/share/opencode/opencode_maintenance.py   # → symlink into this repo's scripts/

# Read-only status: hot-DB health, eligible-session breakdown by activity month, archive inventory
python3 $M status

# Archive + prune: preview plan, then apply
python3 $M archive              # dry-run: prints per-month batches + size estimates
python3 $M archive --apply      # copies to archives/, validates, prunes hot DB, gzips past months

# Bring one session back (also refreshes time_updated → re-shields it for 30 days)
python3 $M restore --archive ~/.local/share/opencode/archives/archive-2026-07.db.gz --session <id>

# WAL checkpoint + incremental vacuum (optional, run manually after big prunes)
python3 $M maintenance --apply
```

Exit codes: `0` ok (including "nothing to archive"), `1` error, `10` DB busy/locked,
`11` low disk, `12` integrity failure. The timer's log captures stdout; a busy night simply
retries next Monday (`Persistent=true` also catches machine-off windows).

Preflight on every mutating run: DB file-lock + open-fd check, disk space (2× estimated payload +
500 MB buffer), full integrity check. Do not run archive/prune while bench campaigns or many agents
are mid-run — the preflight helps but is not a substitute for picking a quiet window.

## Automation

- `systemd/user/opencode-session-archive.timer` — `OnCalendar=Mon *-*-* 04:30:00`, `Persistent=true`.
- `systemd/user/opencode-session-archive.service` — oneshot
  `opencode_maintenance.py archive --days 30 --apply`, logging to
  `~/.local/share/opencode/session-archive.log`.
- Verify: `systemctl --user list-timers | grep session-archive`.

## History

- 2026-03: JSONL export era (`archive_sessions.py`, `archive/` per-project exports) — superseded.
- 2026-04 → 2026-07: monthly manual runs of the SQLite archiver; habit stopped after Jul 22.
- 2026-09-19: retention formalized at 30 days on `time_updated`; weekly timer installed;
  Jul–Aug backlog archived and pruned.
