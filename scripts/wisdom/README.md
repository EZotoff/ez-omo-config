## Wisdom Scripts

- `wisdom-common.sh` — shared library used by the other wisdom scripts.
- `wisdom-search.sh` — searches wisdom stores with filters and optional JSON output.
- `wisdom-write.sh` — validates and writes new wisdom entries.
- `wisdom-sync.sh` — scans notepad learnings and syncs accepted entries into wisdom stores.
- `wisdom-archive.sh` — moves a wisdom entry from the active store to the archive store.
- `wisdom-delete.sh` — deletes a wisdom entry by ID.
- `wisdom-edit.sh` — updates fields on an existing wisdom entry.
- `wisdom-gc.sh` — reports, archives, or deletes stale / low-quality wisdom entries.
- `wisdom-merge.sh` — combines multiple wisdom entries into a single merged entry.

All non-common scripts source `./wisdom-common.sh` via `$(dirname "$0")/wisdom-common.sh`, so the bundle must keep these filenames together in the same directory.
