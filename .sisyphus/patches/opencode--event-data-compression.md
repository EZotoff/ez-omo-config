---
patch_id: "opencode--event-data-compression"
dependency: "opencode"
target_file: "packages/core/src/event/codec.ts"
target_install_path: "/home/ezotoff/.opencode/bin/opencode"
source_repo: "/home/ezotoff/src/opencode"
status: "active"
applied_date: "2026-10-03"
dep_version: "1.18.31-p3"
runtime_effective: true
upstream_issue: "none"
verification_pattern: "OPENCODE_EVENT_CODEC"
verification_strength: "discriminative"
required_evidence: "runtime"
surfaces: [server-api, tui-interactive]
---

# Event data compression (gz1 storage codec)

## Problem
Every part mutation during tool-output streaming persists a durable full-snapshot `event` row (`Session.updatePart` → `SessionV1.Event.PartUpdated`, all v1 session events durable). Bench sessions with giant tool outputs grew `~/.local/share/opencode/opencode.db` to 61.8 GB / 3M rows (2026-10-02 incident: TUI boot `GET /session` hung on the bloated DB). Growth rate ~8 GB per heavy bench day; 99.3% of recent event bytes from `message.part.updated.1`.

## Patch Description
Transparent lossless compression of `EventTable.data` at the drizzle column seam (`packages/core/src/event/sql.ts` — the `data` column becomes a `customType` wired to the codec). Rows whose JSON is ≥ 4096 bytes are stored as `gz1:` + base64(gzip(json)); smaller rows stay plain JSON. Every EventTable consumer (readAggregate, replay deep-equal divergence check, readAfter, sync history, workspace warp) decodes transparently — zero callsite edits. Wire payloads, ids, seqs, owner checks unchanged. Kill switch `OPENCODE_EVENT_CODEC=off` disables compression of new rows only; decode always on. Per-type byte accounting at the publish boundary (`event.ts` commitDurableEvent) + JSONL stats (`~/.local/share/opencode/event-codec-stats.jsonl`) with activation flush.

Measured: 4 KB payload → 36×, 50 KB tool-output JSON → 309× compression.

Oracle verdict context: demoting events (kills projections), retention (replayAll divergence), and delta-encoding (protocol version) were all rejected; the codec is the fork-safe fix. Upstream endgame = v2-style coalescing. Full plan: `.omo/plans/event-log-write-amplification.md` (Momus-approved round 4).

## Verification
Pattern (necessary, NOT sufficient):
```bash
grep -a -c 'OPENCODE_EVENT_CODEC' ~/.opencode/bin/opencode   # ≥ 1
grep -a -c 'gz1:' ~/.opencode/bin/opencode                    # ≥ 1
```
Both are string literals unique to this patch (discriminative).

## Runtime Verification
1. Run a tool-producing session (`opencode run --dir /tmp/opencode/<scratch> "run: echo hello"` style prompt).
2. Assert compressed rows exist: `python3 -c "import sqlite3; print(sqlite3.connect('file:'+__import__('os').path.expanduser('~/.local/share/opencode/opencode.db')+'?mode=ro', uri=True).execute(\"SELECT COUNT(*) FROM event WHERE data LIKE 'gz1:%'\").fetchone())"` > 0.
3. Resume the same session and confirm the prior tool output renders (decode-on-read works).
4. Check `~/.local/share/opencode/event-codec-stats.jsonl`: rowsCompressed > 0, decodeErrors == 0.
5. Regression signal: any `EventDataCodecError` or `Replay diverged` in `journalctl --user -u opencode*` → set runtime_effective: true, add ## Current Runtime Status; do NOT bump dep_version.

## Rollback
- FAST: set `Environment=OPENCODE_EVENT_CODEC=off` drop-ins for both units + `systemctl --user restart opencode.service opencode-interactive.service` (compressed rows remain readable by this binary).
- FULL (MANDATORY ORDER — a codec-less binary CANNOT read gz1: rows): stop both units → `python3 ~/ez-omo-config/scripts/event-codec-migrate-out.py` → verify zero `gz1:` rows remain (`SELECT count(*) FROM event WHERE data LIKE 'gz1:%'` = 0) → restore backup binary → start units. Pre-deploy drill: seed fixtures on a scratch copy (`--make-fixtures`), migrate out, verify old-binary reads.

## Reapply Instructions
1. Identify the EventTable column definition in the target version (`packages/core/src/event/sql.ts`, the `data:` column) — the customType wiring is the single seam; do NOT edit consumer callsites.
2. Re-add `packages/core/src/event/codec.ts` verbatim from the fork (branch `fix/event-data-compression`, commit `3e77f50399`+), restore the `eventDataColumn` customType + import in sql.ts, and the `recordEventTypeBytes` hook in `event.ts` commitDurableEvent.
3. Rebuild per AGENTS.md patch procedure with `OPENCODE_VERSION` matching the target version.
