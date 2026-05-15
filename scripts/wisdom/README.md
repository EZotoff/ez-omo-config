## Wisdom Scripts

- `wisdom-common.sh` — shared library used by the other wisdom scripts.
- `wisdom-search.sh` — searches wisdom stores with filters and optional JSON output.
- `wisdom-write.sh` — validates and writes new wisdom entries.
- `wisdom-closeout.sh` — closeout capture handler that writes canonical records with `provenance=closeout` and applies supersede/contradict lifecycle updates.
- `wisdom-nominate.sh` — passive infra-only nomination handler that writes canonical candidate records.
- `wisdom-sync.sh` — scans notepad learnings and syncs accepted entries into wisdom stores.
- `wisdom-archive.sh` — moves a wisdom entry from the active store to the archive store.
- `wisdom-delete.sh` — deletes a wisdom entry by ID.
- `wisdom-edit.sh` — updates fields on an existing wisdom entry.
- `wisdom-gc.sh` — reports, archives, or deletes stale / low-quality wisdom entries.
- `wisdom-merge.sh` — combines multiple wisdom entries into a single merged entry.
- `wisdom-migrate.sh` — creates migration backups, normalizes legacy wisdom records, and imports manifests into Wisdom idempotently.
- `wisdom-restore.sh` — restores a backup tarball produced by `wisdom-migrate.sh`.
- `wisdom-publish.sh` — publishes a Wisdom entry as a derivative artifact. Updates canonical record (authority=published, verified_at=now) but NEVER supersedes the source. Tracks emitted artifacts in metadata.published_artifacts with source digests for staleness detection.
- `wisdom-observe.sh` — operator-facing observability CLI. Subcommands: `status` (event file metadata), `read` (filtered event inspection), `trace TRACE_ID` (per-trace event timeline), `reset --yes` (safe truncation with reset event).
- `knowledge-lookup.sh` — **DEPRECATED compatibility shim**. Delegates to `wisdom-search.sh` for backward-compatible knowledge queries.
- `knowledge-snapshot.sh` — **DEPRECATED compatibility shim**. Generates session orientation snapshot from Wisdom store only.
- `knowledge-promote.sh` — **DEPRECATED compatibility shim**. Delegates to `wisdom-publish.sh` while preserving legacy CLI interface (`--wisdom-id`, `--type`, `--reason`, `--scope`).

Most non-common scripts source `./wisdom-common.sh` via `$(dirname "$0")/wisdom-common.sh` (notably `wisdom-migrate.sh` and runtime CRUD/search handlers). Keep the bundle co-located in the same directory.
