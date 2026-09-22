#!/usr/bin/env python3
"""OpenCode database maintenance scaffold with safety checks."""

from __future__ import annotations

import argparse
import fcntl
import gzip
import logging
import os
import sys
from pathlib import Path
import shutil
import sqlite3
import tempfile
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

DEFAULT_RETENTION_DAYS = 30  # operator retention policy (2026-09-19); was 5

DB_PATH = os.path.expanduser("~/.local/share/opencode/opencode.db")
ARCHIVE_DIR = os.path.expanduser("~/.local/share/opencode/archives")

EXIT_OK = 0
EXIT_ERROR = 1
EXIT_BUSY = 10
EXIT_LOW_DISK = 11
EXIT_INTEGRITY_FAIL = 12

DISK_BUFFER_BYTES = 500 * 1024 * 1024
COPY_CHUNK_SIZE = 500

ARCHIVE_TABLES: tuple[tuple[str, str], ...] = (
    ("session", "id"),
    ("message", "session_id"),
    ("part", "session_id"),
    ("todo", "session_id"),
    ("session_share", "session_id"),
)

ARCHIVE_SCHEMA_TABLES = tuple(table for table, _ in ARCHIVE_TABLES)
ARCHIVE_DELETE_ORDER: tuple[tuple[str, str], ...] = (
    ("part", "session_id"),
    ("todo", "session_id"),
    ("session_share", "session_id"),
    ("message", "session_id"),
    ("session", "id"),
)

AUTO_VACUUM_MODES = {
    0: "NONE",
    1: "FULL",
    2: "INCREMENTAL",
}

LOGGER = logging.getLogger("opencode_maintenance")


@dataclass(frozen=True)
class ArchiveBatch:
    month: str
    session_ids: list[str]
    archive_path: Path
    estimated_bytes: int
    source_counts: dict[str, int]


@dataclass(frozen=True)
class MaintenanceMetrics:
    wal_size_bytes: int
    auto_vacuum: int
    freelist_count: int
    journal_mode: str
    page_count: int
    page_size: int


def configure_logging(verbose: bool) -> None:
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.INFO,
        format="%(levelname)s: %(message)s",
        stream=sys.stdout,
    )


def get_cutoff_timestamp(retention_days: int) -> int:
    cutoff = datetime.now(timezone.utc) - timedelta(days=retention_days)
    return int(cutoff.timestamp() * 1000)


def get_db_connection(path: str, readonly: bool = False) -> sqlite3.Connection:
    expanded_path = os.path.expanduser(path)
    if readonly:
        uri = f"file:{Path(expanded_path).as_posix()}?mode=ro"
        return sqlite3.connect(uri, uri=True, timeout=30, isolation_level=None)
    return sqlite3.connect(expanded_path, timeout=30, isolation_level=None)


def check_integrity(db_conn: sqlite3.Connection) -> bool:
    row = db_conn.execute("PRAGMA integrity_check;").fetchone()
    result = row[0] if row else None
    LOGGER.debug("integrity_check result=%r", result)
    return result == "ok"


MAINTENANCE_LOCK_PATH = os.path.expanduser(
    "~/.local/share/opencode/opencode-maintenance.lock"
)

_maintenance_lock_handle = None


def check_db_busy(db_path: str) -> bool:
    """True only when another opencode_maintenance run is already active.

    The historical heuristic — treating any process holding the DB's
    ``-wal``/``-shm`` sidecars open as "busy" — permanently blocked the
    weekly timer while the always-on ``opencode serve`` instances were
    running (every logged run exited EXIT_BUSY; see
    docs/session-archiving.md). Holding a WAL sidecar open is normal for
    SQLite readers and never blocks a writer in WAL mode; ``busy_timeout``
    on this script's connections is the real concurrency guard. The only
    genuine hazard is two maintenance runs racing each other, so mutual
    exclusion is an flock on a dedicated lockfile, held for the lifetime
    of this process.
    """
    global _maintenance_lock_handle
    if _maintenance_lock_handle is not None:
        return False  # this process already holds the maintenance lock

    lock_handle = open(MAINTENANCE_LOCK_PATH, "a+")
    try:
        fcntl.flock(lock_handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        lock_handle.close()
        LOGGER.debug(
            "maintenance lock held by another run: %s", MAINTENANCE_LOCK_PATH
        )
        return True

    _maintenance_lock_handle = lock_handle  # held until process exit; OS releases on exit
    LOGGER.debug("maintenance lock acquired: %s", MAINTENANCE_LOCK_PATH)
    return False


def check_disk_space(path: str, required_bytes: int) -> bool:
    expanded_path = Path(os.path.expanduser(path))
    probe_path = expanded_path if expanded_path.exists() else expanded_path.parent
    while not probe_path.exists() and probe_path != probe_path.parent:
        probe_path = probe_path.parent

    _, _, free_bytes = shutil.disk_usage(probe_path)
    minimum_bytes = required_bytes + DISK_BUFFER_BYTES
    LOGGER.debug(
        "disk space probe=%s free=%s required=%s minimum=%s",
        probe_path,
        free_bytes,
        required_bytes,
        minimum_bytes,
    )
    return free_bytes >= minimum_bytes


def _db_size_bytes(db_path: str) -> int:
    total = 0
    for candidate in (db_path, f"{db_path}-wal", f"{db_path}-shm"):
        try:
            total += os.path.getsize(os.path.expanduser(candidate))
        except OSError:
            continue
    return total


def _main_db_size_bytes(db_path: str) -> int:
    try:
        return os.path.getsize(os.path.expanduser(db_path))
    except OSError:
        return 0


def _wal_size_bytes(db_path: str) -> int:
    try:
        return os.path.getsize(os.path.expanduser(f"{db_path}-wal"))
    except OSError:
        return 0


def _ensure_db_exists(db_path: str) -> bool:
    exists = Path(os.path.expanduser(db_path)).exists()
    if not exists:
        LOGGER.error("Database not found: %s", os.path.expanduser(db_path))
    return exists


def _run_integrity_check(db_path: str, readonly: bool = True) -> int:
    try:
        with get_db_connection(db_path, readonly=readonly) as conn:
            if not check_integrity(conn):
                LOGGER.error("Database integrity check failed")
                return EXIT_INTEGRITY_FAIL
    except sqlite3.Error as exc:
        LOGGER.error("Failed to run integrity check: %s", exc)
        return EXIT_INTEGRITY_FAIL
    return EXIT_OK


def _preflight_mutating_command(args: argparse.Namespace) -> int:
    if not _ensure_db_exists(args.db_path):
        return EXIT_ERROR

    if check_db_busy(args.db_path):
        LOGGER.error("Database is busy or locked: %s", args.db_path)
        return EXIT_BUSY

    required_bytes = max(_db_size_bytes(args.db_path), 1)
    if not check_disk_space(args.archive_dir, required_bytes):
        LOGGER.error(
            "Insufficient disk space for maintenance work in %s",
            os.path.expanduser(args.archive_dir),
        )
        return EXIT_LOW_DISK

    return _run_integrity_check(args.db_path, readonly=False)


def _chunked(items: list[str], size: int = COPY_CHUNK_SIZE):
    for index in range(0, len(items), size):
        yield items[index : index + size]


def _month_bucket(timestamp_ms: int) -> str:
    return datetime.fromtimestamp(timestamp_ms / 1000, tz=timezone.utc).strftime(
        "%Y-%m"
    )


def _format_bytes(num_bytes: int) -> str:
    units = ["B", "KB", "MB", "GB", "TB"]
    size = float(max(num_bytes, 0))
    for unit in units:
        if size < 1024 or unit == units[-1]:
            return f"{size:.1f} {unit}"
        size /= 1024
    return f"{num_bytes} B"


def _placeholders(count: int) -> str:
    return ",".join("?" for _ in range(count))


def _estimate_value_size(value: object) -> int:
    if value is None:
        return 0
    if isinstance(value, bytes):
        return len(value)
    if isinstance(value, str):
        return len(value.encode("utf-8"))
    if isinstance(value, bool):
        return 1
    if isinstance(value, int):
        return 8
    if isinstance(value, float):
        return 8
    return len(str(value).encode("utf-8"))


def _estimate_rows_size(rows: list[tuple]) -> int:
    return sum(sum(_estimate_value_size(value) for value in row) for row in rows)


def _fetch_rows_for_session(
    conn: sqlite3.Connection, table: str, key_col: str, session_id: str
) -> list[tuple]:
    cursor = conn.execute(f"SELECT * FROM {table} WHERE {key_col} = ?", (session_id,))
    return cursor.fetchall()


def _select_eligible_session_ids(conn: sqlite3.Connection, cutoff_ms: int) -> list[str]:
    cursor = conn.execute("SELECT id FROM session WHERE time_updated < ?", (cutoff_ms,))
    return [row[0] for row in cursor.fetchall()]


def _load_session_months(
    conn: sqlite3.Connection, session_ids: list[str]
) -> dict[str, list[str]]:
    buckets: dict[str, list[str]] = {}
    for chunk in _chunked(session_ids):
        cursor = conn.execute(
            f"SELECT id, time_updated FROM session WHERE id IN ({_placeholders(len(chunk))})",
            tuple(chunk),
        )
        for session_id, time_updated in cursor.fetchall():
            month = _month_bucket(time_updated)
            buckets.setdefault(month, []).append(session_id)
    return dict(sorted(buckets.items()))


def _summarize_archive_batch(
    conn: sqlite3.Connection,
    month: str,
    session_ids: list[str],
    archive_dir: str,
) -> ArchiveBatch:
    estimated_bytes = 0
    source_counts = {table: 0 for table, _ in ARCHIVE_TABLES}
    for session_id in session_ids:
        for table, key_col in ARCHIVE_TABLES:
            rows = _fetch_rows_for_session(conn, table, key_col, session_id)
            source_counts[table] += len(rows)
            estimated_bytes += _estimate_rows_size(rows)
    archive_path = Path(os.path.expanduser(archive_dir)) / f"archive-{month}.db"
    return ArchiveBatch(
        month=month,
        session_ids=session_ids,
        archive_path=archive_path,
        estimated_bytes=estimated_bytes,
        source_counts=source_counts,
    )


def _build_archive_plan(
    db_path: str, archive_dir: str, cutoff_ms: int
) -> tuple[list[ArchiveBatch], list[str]]:
    with get_db_connection(db_path, readonly=True) as hot_conn:
        eligible_ids = _select_eligible_session_ids(hot_conn, cutoff_ms)
        if not eligible_ids:
            return [], []

        batches = []
        for month, session_ids in _load_session_months(hot_conn, eligible_ids).items():
            batches.append(
                _summarize_archive_batch(hot_conn, month, session_ids, archive_dir)
            )
    return batches, eligible_ids


def _archive_schema_entries(hot_conn: sqlite3.Connection) -> list[tuple[str, str]]:
    table_sql_rows = hot_conn.execute(
        f"""
        SELECT name, sql
        FROM sqlite_master
        WHERE type = 'table'
          AND name IN ({_placeholders(len(ARCHIVE_SCHEMA_TABLES))})
          AND sql IS NOT NULL
        """,
        ARCHIVE_SCHEMA_TABLES,
    ).fetchall()
    table_sql_map = {name: sql for name, sql in table_sql_rows}

    ordered_table_entries = [
        (name, table_sql_map[name]) for name in ARCHIVE_SCHEMA_TABLES
    ]
    index_entries = [
        (f"index:{index}", sql)
        for index, sql in hot_conn.execute(
            f"""
            SELECT name, sql
            FROM sqlite_master
            WHERE type = 'index'
              AND tbl_name IN ({_placeholders(len(ARCHIVE_SCHEMA_TABLES))})
              AND sql IS NOT NULL
            ORDER BY name
            """,
            ARCHIVE_SCHEMA_TABLES,
        ).fetchall()
    ]
    return ordered_table_entries + index_entries


def _reconcile_archive_table_columns(
    hot_conn: sqlite3.Connection, arch_conn: sqlite3.Connection, table: str
) -> None:
    """ADD COLUMN for hot-schema columns missing from an existing archive table.

    Handles schema drift when OpenCode ships additive columns on a table that
    already has an older-schema archive DB (e.g. ``session`` grew from 19 to 29
    columns). Only safe ADD COLUMNs are issued: a missing column must be nullable
    or carry a default value. NOT NULL columns without a default cannot be added
    to a non-empty table and are raised as an error rather than guessed; this has
    never occurred for an additive OpenCode schema change to date.
    """
    # PRAGMA table_info columns: cid, name, type, notnull, dflt_value, pk
    hot_columns = {
        row[1]: row for row in hot_conn.execute(f"PRAGMA table_info({table})")
    }
    archive_column_names = {
        row[1] for row in arch_conn.execute(f"PRAGMA table_info({table})")
    }
    for col_name, hot_row in hot_columns.items():
        if col_name in archive_column_names:
            continue
        _, _, col_type, notnull, default_value, _ = hot_row
        type_clause = f" {col_type}" if col_type else ""
        if default_value is not None:
            default_clause = f" DEFAULT {default_value}"
        elif notnull:
            raise sqlite3.DatabaseError(
                f"cannot reconcile {table}.{col_name}: "
                "NOT NULL without default; refusing to guess a filler value"
            )
        else:
            default_clause = ""
        arch_conn.execute(
            f'ALTER TABLE "{table}" ADD COLUMN "{col_name}"'
            f"{type_clause}{default_clause}"
        )
        LOGGER.info(
            "reconciled archive column table=%s column=%s type=%s default=%r",
            table,
            col_name,
            col_type,
            default_value,
        )

def _ensure_archive_schema(
    hot_conn: sqlite3.Connection, arch_conn: sqlite3.Connection
) -> None:
    existing_table_names = {
        row[0]
        for row in arch_conn.execute(
            """
            SELECT name
            FROM sqlite_master
            WHERE type = 'table'
              AND sql IS NOT NULL
            """
        ).fetchall()
    }
    existing_index_names = {
        row[0]
        for row in arch_conn.execute(
            """
            SELECT name
            FROM sqlite_master
            WHERE type = 'index'
              AND sql IS NOT NULL
            """
        ).fetchall()
    }

    for object_name, sql in _archive_schema_entries(hot_conn):
        if object_name.startswith("index:"):
            if object_name.removeprefix("index:") in existing_index_names:
                continue
        elif object_name in existing_table_names:
            continue
        arch_conn.execute(sql)

    for table in ARCHIVE_SCHEMA_TABLES:
        _reconcile_archive_table_columns(hot_conn, arch_conn, table)


def _materialize_archive_db(archive_path: Path) -> tuple[bool, bool]:
    if archive_path.exists():
        return True, False

    gzip_path = archive_path.with_suffix(archive_path.suffix + ".gz")
    if not gzip_path.exists():
        return False, False

    temp_path = archive_path.with_suffix(archive_path.suffix + ".tmp")
    try:
        with gzip.open(gzip_path, "rb") as src, open(temp_path, "wb") as dst:
            shutil.copyfileobj(src, dst, length=1024 * 1024)
        with open(temp_path, "rb") as check_handle:
            check_handle.read(4096)
        temp_path.replace(archive_path)
        return True, True
    except Exception:
        if temp_path.exists():
            temp_path.unlink()
        raise


def _cleanup_materialized_gzip_source(
    archive_path: Path, materialized_from_gzip: bool
) -> None:
    if not materialized_from_gzip:
        return
    gzip_path = archive_path.with_suffix(archive_path.suffix + ".gz")
    if gzip_path.exists():
        gzip_path.unlink()


def _set_archive_journal_mode(
    arch_conn: sqlite3.Connection, archive_path: Path
) -> None:
    result = arch_conn.execute("PRAGMA journal_mode=DELETE;").fetchone()
    journal_mode = result[0].lower() if result and result[0] else ""
    if journal_mode != "delete":
        raise sqlite3.DatabaseError(
            f"unexpected journal mode for archive {archive_path}: {journal_mode!r}"
        )


def _count_rows_for_ids(
    conn: sqlite3.Connection, table: str, key_col: str, session_ids: list[str]
) -> int:
    total = 0
    for chunk in _chunked(session_ids):
        cursor = conn.execute(
            f"SELECT COUNT(*) FROM {table} WHERE {key_col} IN ({_placeholders(len(chunk))})",
            tuple(chunk),
        )
        total += int(cursor.fetchone()[0])
    return total


def _validate_archive_batch(
    arch_conn: sqlite3.Connection, batch: ArchiveBatch, archive_path: Path
) -> None:
    archive_counts = {
        table: _count_rows_for_ids(arch_conn, table, key_col, batch.session_ids)
        for table, key_col in ARCHIVE_TABLES
    }
    for table, expected_count in batch.source_counts.items():
        actual_count = archive_counts[table]
        if actual_count != expected_count:
            raise sqlite3.DatabaseError(
                f"archive row-count mismatch for {archive_path} table={table}: "
                f"expected {expected_count}, found {actual_count}"
            )

    if not check_integrity(arch_conn):
        raise sqlite3.DatabaseError(
            f"archive integrity check failed for {archive_path}"
        )


def _copy_archive_batch(db_path: str, batch: ArchiveBatch) -> None:
    archive_path = batch.archive_path
    archive_path.parent.mkdir(parents=True, exist_ok=True)
    _, materialized_from_gzip = _materialize_archive_db(archive_path)

    with (
        get_db_connection(db_path, readonly=True) as hot_conn,
        get_db_connection(str(archive_path), readonly=False) as arch_conn,
    ):
        _ensure_archive_schema(hot_conn, arch_conn)
        _set_archive_journal_mode(arch_conn, archive_path)

        try:
            arch_conn.execute("BEGIN")
            for session_id in batch.session_ids:
                for table, key_col in ARCHIVE_TABLES:
                    rows = _fetch_rows_for_session(hot_conn, table, key_col, session_id)
                    if not rows:
                        continue
                    arch_conn.executemany(
                        f"INSERT OR IGNORE INTO {table} VALUES ({_placeholders(len(rows[0]))})",
                        rows,
                    )
            arch_conn.execute("COMMIT")
        except Exception:
            arch_conn.execute("ROLLBACK")
            raise

        _validate_archive_batch(arch_conn, batch, archive_path)

    _cleanup_materialized_gzip_source(archive_path, materialized_from_gzip)


def _aggregate_source_counts(batches: list[ArchiveBatch]) -> dict[str, int]:
    totals = {table: 0 for table, _ in ARCHIVE_TABLES}
    for batch in batches:
        for table, count in batch.source_counts.items():
            totals[table] += count
    return totals


def _current_hot_counts(conn: sqlite3.Connection) -> dict[str, int]:
    return {
        table: int(conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0])
        for table, _ in ARCHIVE_TABLES
    }


def _delete_archived_rows(
    db_path: str, archived_session_ids: list[str], archived_counts: dict[str, int]
) -> None:
    with get_db_connection(db_path, readonly=False) as hot_conn:
        before_counts = _current_hot_counts(hot_conn)
        expected_after = {
            table: before_counts[table] - archived_counts[table]
            for table, _ in ARCHIVE_TABLES
        }

        try:
            hot_conn.execute("BEGIN")
            for table, key_col in ARCHIVE_DELETE_ORDER:
                for chunk in _chunked(archived_session_ids):
                    hot_conn.execute(
                        f"DELETE FROM {table} WHERE {key_col} IN ({_placeholders(len(chunk))})",
                        tuple(chunk),
                    )

            after_counts = _current_hot_counts(hot_conn)
            for table, expected in expected_after.items():
                actual = after_counts[table]
                if actual != expected:
                    raise sqlite3.DatabaseError(
                        f"hot-db row-count mismatch for {table}: expected {expected}, found {actual}"
                    )

            if not check_integrity(hot_conn):
                raise sqlite3.DatabaseError(
                    "hot-db integrity check failed after archive delete"
                )

            hot_conn.execute("COMMIT")
        except Exception:
            hot_conn.execute("ROLLBACK")
            raise


def _compress_file_to_gzip(source_path: Path, target_path: Path) -> None:
    temp_path = target_path.with_suffix(target_path.suffix + ".tmp")
    try:
        with open(source_path, "rb") as src, gzip.open(temp_path, "wb") as dst:
            shutil.copyfileobj(src, dst, length=1024 * 1024)
        with gzip.open(temp_path, "rb") as check_handle:
            check_handle.read(4096)
        temp_path.replace(target_path)
        source_path.unlink()
    except Exception:
        if temp_path.exists():
            temp_path.unlink()
        raise


def _compress_past_month_archives(archive_dir: str) -> None:
    archive_root = Path(os.path.expanduser(archive_dir))
    if not archive_root.exists():
        return

    current_month = datetime.now(timezone.utc).strftime("%Y-%m")
    for archive_path in sorted(archive_root.glob("archive-*.db")):
        month = archive_path.stem.removeprefix("archive-")
        if month == current_month:
            LOGGER.info("keeping current month archive uncompressed: %s", archive_path)
            continue

        gzip_path = archive_path.with_suffix(archive_path.suffix + ".gz")
        if gzip_path.exists():
            LOGGER.info(
                "compressed archive already exists; leaving db in place: %s", gzip_path
            )
            continue

        LOGGER.info("compressing archive %s -> %s", archive_path, gzip_path)
        _compress_file_to_gzip(archive_path, gzip_path)


def _current_utc_timestamp_ms() -> int:
    return int(datetime.now(timezone.utc).timestamp() * 1000)


def _auto_vacuum_mode_name(mode: int) -> str:
    return AUTO_VACUUM_MODES.get(mode, f"UNKNOWN({mode})")


def _current_auto_vacuum(conn: sqlite3.Connection) -> int:
    row = conn.execute("PRAGMA auto_vacuum;").fetchone()
    return int(row[0]) if row else 0


def _collect_maintenance_metrics(
    conn: sqlite3.Connection, db_path: str
) -> MaintenanceMetrics:
    auto_vacuum = _current_auto_vacuum(conn)
    freelist_row = conn.execute("PRAGMA freelist_count;").fetchone()
    journal_row = conn.execute("PRAGMA journal_mode;").fetchone()
    page_count_row = conn.execute("PRAGMA page_count;").fetchone()
    page_size_row = conn.execute("PRAGMA page_size;").fetchone()
    return MaintenanceMetrics(
        wal_size_bytes=_wal_size_bytes(db_path),
        auto_vacuum=auto_vacuum,
        freelist_count=int(freelist_row[0]) if freelist_row else 0,
        journal_mode=str(journal_row[0]).lower()
        if journal_row and journal_row[0]
        else "unknown",
        page_count=int(page_count_row[0]) if page_count_row else 0,
        page_size=int(page_size_row[0]) if page_size_row else 0,
    )


def _log_maintenance_metrics(label: str, metrics: MaintenanceMetrics) -> None:
    LOGGER.info(
        "%s wal_size_bytes=%s (%s) auto_vacuum=%s (%s) freelist_count=%s journal_mode=%s page_count=%s page_size=%s",
        label,
        metrics.wal_size_bytes,
        _format_bytes(metrics.wal_size_bytes),
        metrics.auto_vacuum,
        _auto_vacuum_mode_name(metrics.auto_vacuum),
        metrics.freelist_count,
        metrics.journal_mode,
        metrics.page_count,
        metrics.page_size,
    )


def _run_wal_checkpoint(conn: sqlite3.Connection) -> tuple[int, int, int]:
    row = conn.execute("PRAGMA wal_checkpoint(TRUNCATE);").fetchone()
    if row is None:
        raise sqlite3.DatabaseError("wal_checkpoint(TRUNCATE) returned no result")
    if len(row) < 3:
        raise sqlite3.DatabaseError(
            f"wal_checkpoint(TRUNCATE) returned unexpected shape: {row!r}"
        )

    result = (int(row[0]), int(row[1]), int(row[2]))
    LOGGER.info("wal checkpoint(TRUNCATE) result=%s", result)
    if result[0] > 0:
        LOGGER.warning(
            "wal checkpoint reported busy frames (blocked=%s); continuing",
            result[0],
        )
    return result


def _maybe_migrate_auto_vacuum(
    conn: sqlite3.Connection, db_path: str, migrate_auto_vacuum: bool
) -> int:
    current_mode = _current_auto_vacuum(conn)
    if not migrate_auto_vacuum:
        LOGGER.info(
            "auto_vacuum migration not requested; current auto_vacuum=%s (%s)",
            current_mode,
            _auto_vacuum_mode_name(current_mode),
        )
        return EXIT_OK

    if current_mode == 0:
        required_bytes = max(_main_db_size_bytes(db_path) * 2, 1)
        LOGGER.info(
            "auto_vacuum migration requested; requiring disk space for 2x database size (%s)",
            _format_bytes(required_bytes),
        )
        if not check_disk_space(db_path, required_bytes):
            LOGGER.error(
                "Insufficient disk space for auto_vacuum migration on %s (need %s + buffer)",
                db_path,
                _format_bytes(required_bytes),
            )
            return EXIT_LOW_DISK

        LOGGER.info("migrating auto_vacuum from NONE to INCREMENTAL via VACUUM")
        conn.execute("PRAGMA auto_vacuum=INCREMENTAL;")
        conn.execute("VACUUM;")
        verified_mode = _current_auto_vacuum(conn)
        if verified_mode != 2:
            raise sqlite3.DatabaseError(
                "auto_vacuum migration failed verification: expected 2 (INCREMENTAL)"
            )
        LOGGER.info(
            "Auto-vacuum migrated to INCREMENTAL. This was a one-time operation."
        )
        return EXIT_OK

    LOGGER.info(
        "auto_vacuum already configured as %s (%s); skipping migration",
        current_mode,
        _auto_vacuum_mode_name(current_mode),
    )
    return EXIT_OK


def _run_incremental_vacuum(
    conn: sqlite3.Connection, db_path: str
) -> tuple[MaintenanceMetrics, MaintenanceMetrics]:
    before_metrics = _collect_maintenance_metrics(conn, db_path)
    conn.execute("PRAGMA incremental_vacuum(50000);")
    after_metrics = _collect_maintenance_metrics(conn, db_path)

    LOGGER.info(
        "incremental_vacuum(50000) metrics auto_vacuum=%s (%s) freelist_before=%s freelist_after=%s page_count_before=%s page_count_after=%s wal_size_before=%s wal_size_after=%s",
        after_metrics.auto_vacuum,
        _auto_vacuum_mode_name(after_metrics.auto_vacuum),
        before_metrics.freelist_count,
        after_metrics.freelist_count,
        before_metrics.page_count,
        after_metrics.page_count,
        before_metrics.wal_size_bytes,
        after_metrics.wal_size_bytes,
    )
    if after_metrics.auto_vacuum != 2:
        LOGGER.info(
            "incremental vacuum may be a no-op because auto_vacuum=%s (%s)",
            after_metrics.auto_vacuum,
            _auto_vacuum_mode_name(after_metrics.auto_vacuum),
        )
    return before_metrics, after_metrics


def _log_maintenance_dry_run(
    metrics: MaintenanceMetrics, migrate_auto_vacuum: bool, db_path: str
) -> None:
    _log_maintenance_metrics("current maintenance state:", metrics)
    LOGGER.info("dry-run only; no checkpoint or vacuum statements executed")
    LOGGER.info(
        "would run PRAGMA wal_checkpoint(TRUNCATE) and log (blocked, pages_wal, pages_checkpointed)"
    )
    if migrate_auto_vacuum:
        LOGGER.info(
            "would evaluate explicit auto_vacuum migration request based on current auto_vacuum=%s (%s)",
            metrics.auto_vacuum,
            _auto_vacuum_mode_name(metrics.auto_vacuum),
        )
        if metrics.auto_vacuum == 0:
            required_bytes = max(_main_db_size_bytes(db_path), 1) * 2
            LOGGER.info(
                "would require disk space for 2x database size (%s), then run PRAGMA auto_vacuum=INCREMENTAL and VACUUM",
                _format_bytes(required_bytes),
            )
        else:
            LOGGER.info(
                "would skip auto_vacuum migration because it is already configured"
            )
    else:
        LOGGER.info(
            "would skip auto_vacuum migration unless --migrate-auto-vacuum is explicitly provided"
        )
    LOGGER.info(
        "would run PRAGMA incremental_vacuum(50000) and report before/after freelist_count and page_count"
    )


def _format_bytes_with_exact(num_bytes: int) -> str:
    return f"{_format_bytes(num_bytes)} ({num_bytes} bytes)"


def _render_table(headers: tuple[str, ...], rows: list[tuple[str, ...]]) -> list[str]:
    widths = [len(header) for header in headers]
    for row in rows:
        for index, value in enumerate(row):
            widths[index] = max(widths[index], len(value))

    def _render_row(row: tuple[str, ...]) -> str:
        return "  ".join(value.ljust(widths[index]) for index, value in enumerate(row))

    separator = "  ".join("-" * width for width in widths)
    return [_render_row(headers), separator, *(_render_row(row) for row in rows)]


def _collect_hot_db_row_counts(conn: sqlite3.Connection) -> dict[str, int]:
    return {
        table: int(conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0])
        for table in ("session", "message", "part", "todo")
    }


def _run_quick_check(conn: sqlite3.Connection) -> str:
    row = conn.execute("PRAGMA quick_check;").fetchone()
    return str(row[0]) if row and row[0] is not None else "unknown"


def _collect_eligible_session_breakdown(
    conn: sqlite3.Connection, cutoff_ms: int
) -> list[tuple[str, int]]:
    rows = conn.execute(
        """
        SELECT strftime('%Y-%m', time_updated / 1000.0, 'unixepoch') AS month_bucket,
               COUNT(*)
        FROM session
        WHERE time_updated < ?
        GROUP BY month_bucket
        ORDER BY month_bucket
        """,
        (cutoff_ms,),
    ).fetchall()
    return [(str(month), int(count)) for month, count in rows]


def _collect_eligible_session_size_estimates(
    conn: sqlite3.Connection, cutoff_ms: int
) -> dict[str, int]:
    estimates: dict[str, int] = {}
    estimate_queries = (
        """
        SELECT strftime('%Y-%m', time_updated / 1000.0, 'unixepoch') AS month_bucket,
               COALESCE(SUM(
                   COALESCE(LENGTH(id), 0) +
                   COALESCE(LENGTH(project_id), 0) +
                   COALESCE(LENGTH(parent_id), 0) +
                   COALESCE(LENGTH(slug), 0) +
                   COALESCE(LENGTH(directory), 0) +
                   COALESCE(LENGTH(title), 0) +
                   COALESCE(LENGTH(version), 0) +
                   COALESCE(LENGTH(share_url), 0) +
                   COALESCE(LENGTH(summary_additions), 0) +
                   COALESCE(LENGTH(summary_deletions), 0) +
                   COALESCE(LENGTH(summary_files), 0) +
                   COALESCE(LENGTH(summary_diffs), 0) +
                   COALESCE(LENGTH(revert), 0) +
                   COALESCE(LENGTH(permission), 0) +
                   COALESCE(LENGTH(workspace_id), 0)
               ), 0)
        FROM session
        WHERE time_updated < ?
        GROUP BY month_bucket
        """,
        """
        SELECT strftime('%Y-%m', s.time_updated / 1000.0, 'unixepoch') AS month_bucket,
               COALESCE(SUM(LENGTH(m.data)), 0)
        FROM message AS m
        JOIN session AS s ON s.id = m.session_id
        WHERE s.time_updated < ?
        GROUP BY month_bucket
        """,
        """
        SELECT strftime('%Y-%m', s.time_updated / 1000.0, 'unixepoch') AS month_bucket,
               COALESCE(SUM(LENGTH(p.data)), 0)
        FROM part AS p
        JOIN session AS s ON s.id = p.session_id
        WHERE s.time_updated < ?
        GROUP BY month_bucket
        """,
        """
        SELECT strftime('%Y-%m', s.time_updated / 1000.0, 'unixepoch') AS month_bucket,
               COALESCE(SUM(
                   COALESCE(LENGTH(t.content), 0) +
                   COALESCE(LENGTH(t.status), 0) +
                   COALESCE(LENGTH(t.priority), 0)
               ), 0)
        FROM todo AS t
        JOIN session AS s ON s.id = t.session_id
        WHERE s.time_updated < ?
        GROUP BY month_bucket
        """,
        """
        SELECT strftime('%Y-%m', s.time_updated / 1000.0, 'unixepoch') AS month_bucket,
               COALESCE(SUM(
                   COALESCE(LENGTH(ss.id), 0) +
                   COALESCE(LENGTH(ss.secret), 0) +
                   COALESCE(LENGTH(ss.url), 0)
               ), 0)
        FROM session_share AS ss
        JOIN session AS s ON s.id = ss.session_id
        WHERE s.time_updated < ?
        GROUP BY month_bucket
        """,
    )

    for query in estimate_queries:
        for month_bucket, estimated_bytes in conn.execute(
            query, (cutoff_ms,)
        ).fetchall():
            estimates[str(month_bucket)] = estimates.get(str(month_bucket), 0) + int(
                estimated_bytes or 0
            )
    return estimates


def _collect_eligible_session_stats(
    conn: sqlite3.Connection, cutoff_ms: int
) -> tuple[int, int, list[tuple[str, int, int]]]:
    breakdown = _collect_eligible_session_breakdown(conn, cutoff_ms)
    estimates = _collect_eligible_session_size_estimates(conn, cutoff_ms)
    total_count = sum(count for _, count in breakdown)
    detailed_breakdown = [
        (month, count, estimates.get(month, 0)) for month, count in breakdown
    ]
    total_estimated_bytes = sum(
        estimated_bytes for _, _, estimated_bytes in detailed_breakdown
    )
    return total_count, total_estimated_bytes, detailed_breakdown


def _collect_archive_inventory(
    archive_dir: str,
) -> tuple[list[tuple[str, str, int, str, str]], int, str | None]:
    archive_root = Path(os.path.expanduser(archive_dir))
    if not archive_root.exists():
        return [], 0, f"Archive directory not found: {archive_root}"

    archive_files = sorted(path for path in archive_root.iterdir() if path.is_file())
    if not archive_files:
        return [], 0, f"No archive files found in {archive_root}"

    entries: list[tuple[str, str, int, str, str]] = []
    total_size = 0
    for archive_path in archive_files:
        size_bytes = archive_path.stat().st_size
        total_size += size_bytes

        if archive_path.suffixes[-2:] == [".db", ".gz"]:
            entries.append(
                (
                    archive_path.name,
                    "archive db.gz",
                    size_bytes,
                    "-",
                    "compressed only; not decompressed",
                )
            )
            continue

        if archive_path.suffix == ".db":
            session_count = "-"
            note = "-"
            try:
                with get_db_connection(
                    str(archive_path), readonly=True
                ) as archive_conn:
                    row = archive_conn.execute(
                        "SELECT COUNT(*) FROM session"
                    ).fetchone()
                    session_count = str(int(row[0]) if row else 0)
            except sqlite3.Error as exc:
                note = f"session count unavailable: {exc}"
            entries.append(
                (
                    archive_path.name,
                    "archive db",
                    size_bytes,
                    session_count,
                    note,
                )
            )
            continue

        entries.append(
            (
                archive_path.name,
                "other file",
                size_bytes,
                "-",
                "unrecognized file",
            )
        )

    return entries, total_size, None


def _prepare_restore_archive_db(archive_path: Path) -> tuple[Path, Path | None]:
    if archive_path.suffix != ".gz":
        return archive_path, None

    with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as temp_handle:
        temp_path = Path(temp_handle.name)

    try:
        with gzip.open(archive_path, "rb") as src, open(temp_path, "wb") as dst:
            shutil.copyfileobj(src, dst, length=1024 * 1024)
        with open(temp_path, "rb") as check_handle:
            check_handle.read(4096)
        return temp_path, temp_path
    except Exception:
        if temp_path.exists():
            temp_path.unlink()
        raise


def _cleanup_temp_restore_archive(temp_path: Path | None) -> None:
    if temp_path is None:
        return
    try:
        temp_path.unlink(missing_ok=True)
    except OSError:
        LOGGER.warning("failed to remove temporary restore archive: %s", temp_path)


def _readonly_db_uri(db_path: Path) -> str:
    return f"file:{db_path.resolve().as_posix()}?mode=ro"


def _writable_db_uri(db_path: str) -> str:
    return f"file:{Path(os.path.expanduser(db_path)).resolve().as_posix()}?mode=rw"


def _session_row_counts(
    conn: sqlite3.Connection, session_id: str, schema: str | None = None
) -> dict[str, int]:
    table_prefix = f"{schema}." if schema else ""
    counts = {
        "session": int(
            conn.execute(
                f"SELECT COUNT(*) FROM {table_prefix}session WHERE id = ?",
                (session_id,),
            ).fetchone()[0]
        )
    }
    for table in ("message", "part", "todo", "session_share"):
        counts[table] = int(
            conn.execute(
                f"SELECT COUNT(*) FROM {table_prefix}{table} WHERE session_id = ?",
                (session_id,),
            ).fetchone()[0]
        )
    return counts


def _format_session_summary(session_row: sqlite3.Row) -> str:
    preferred_columns = [
        name
        for name in ("id", "title", "time_created", "time_updated")
        if name in session_row.keys()
    ]
    if not preferred_columns:
        preferred_columns = list(session_row.keys())
    return ", ".join(
        f"{column}={session_row[column]!r}" for column in preferred_columns
    )


def _log_restore_report(
    archive_path: Path, session_row: sqlite3.Row, source_counts: dict[str, int]
) -> None:
    LOGGER.info("restore archive=%s", archive_path)
    LOGGER.info("restore session %s", _format_session_summary(session_row))
    LOGGER.info(
        "restore counts session=%s message=%s part=%s todo=%s session_share=%s",
        source_counts["session"],
        source_counts["message"],
        source_counts["part"],
        source_counts["todo"],
        source_counts["session_share"],
    )


def _restore_session_apply(
    db_path: str, archive_db_path: Path, session_id: str, source_counts: dict[str, int]
) -> int:
    restored_time_updated = _current_utc_timestamp_ms()
    attach_uri = _readonly_db_uri(archive_db_path)
    hot_db_uri = _writable_db_uri(db_path)

    with sqlite3.connect(
        hot_db_uri, uri=True, timeout=30, isolation_level=None
    ) as hot_conn:
        attached = False
        in_transaction = False
        try:
            hot_conn.execute("ATTACH DATABASE ? AS archive", (attach_uri,))
            attached = True

            hot_conn.execute("BEGIN")
            in_transaction = True

            hot_conn.execute(
                "INSERT INTO session SELECT * FROM archive.session WHERE id = ?",
                (session_id,),
            )
            hot_conn.execute(
                "INSERT INTO message SELECT * FROM archive.message WHERE session_id = ?",
                (session_id,),
            )
            hot_conn.execute(
                "INSERT INTO part SELECT * FROM archive.part WHERE session_id = ?",
                (session_id,),
            )
            hot_conn.execute(
                "INSERT INTO todo SELECT * FROM archive.todo WHERE session_id = ?",
                (session_id,),
            )
            hot_conn.execute(
                "INSERT OR IGNORE INTO session_share SELECT * FROM archive.session_share WHERE session_id = ?",
                (session_id,),
            )
            hot_conn.execute(
                "UPDATE session SET time_updated = ? WHERE id = ?",
                (restored_time_updated, session_id),
            )

            restored_counts = _session_row_counts(hot_conn, session_id)
            for table, expected_count in source_counts.items():
                actual_count = restored_counts[table]
                if actual_count != expected_count:
                    raise sqlite3.DatabaseError(
                        f"restore row-count mismatch for {table}: expected {expected_count}, found {actual_count}"
                    )

            restored_time_row = hot_conn.execute(
                "SELECT time_updated FROM session WHERE id = ?", (session_id,)
            ).fetchone()
            restored_time = restored_time_row[0] if restored_time_row else None
            if restored_time != restored_time_updated:
                raise sqlite3.DatabaseError(
                    "restore failed to refresh session.time_updated"
                )

            if not check_integrity(hot_conn):
                raise sqlite3.DatabaseError(
                    "hot-db integrity check failed after restore"
                )

            hot_conn.execute("COMMIT")
            in_transaction = False
        except Exception:
            if in_transaction:
                hot_conn.execute("ROLLBACK")
            raise
        finally:
            if attached:
                hot_conn.execute("DETACH DATABASE archive")

    LOGGER.info(
        "restored session=%s into hot db with refreshed time_updated=%s",
        session_id,
        restored_time_updated,
    )
    return EXIT_OK


def _log_archive_plan(batches: list[ArchiveBatch]) -> int:
    eligible_count = sum(len(batch.session_ids) for batch in batches)
    LOGGER.info("eligible sessions=%s", eligible_count)
    for batch in batches:
        LOGGER.info(
            "month=%s sessions=%s estimated_bytes=%s target=%s source_counts=%s",
            batch.month,
            len(batch.session_ids),
            batch.estimated_bytes,
            batch.archive_path,
            batch.source_counts,
        )
    return eligible_count


def handle_archive(args: argparse.Namespace) -> int:
    if not _ensure_db_exists(args.db_path):
        return EXIT_ERROR

    cutoff_ms = get_cutoff_timestamp(args.days)
    cutoff_utc = datetime.fromtimestamp(cutoff_ms / 1000, tz=timezone.utc)
    LOGGER.info(
        "archive requested mode=%s cutoff_ms=%s cutoff_utc=%s db=%s archive_dir=%s",
        "apply" if args.apply else "dry-run",
        cutoff_ms,
        cutoff_utc.strftime("%Y-%m-%d %H:%M:%S UTC"),
        args.db_path,
        args.archive_dir,
    )

    if check_db_busy(args.db_path):
        LOGGER.error("Database is busy or locked: %s", args.db_path)
        return EXIT_BUSY

    integrity_code = _run_integrity_check(args.db_path, readonly=True)
    if integrity_code != EXIT_OK:
        return integrity_code

    try:
        batches, eligible_ids = _build_archive_plan(
            args.db_path, args.archive_dir, cutoff_ms
        )
    except sqlite3.Error as exc:
        LOGGER.error("Failed to build archive plan: %s", exc)
        return EXIT_ERROR

    if not batches:
        LOGGER.info("nothing to archive")
        return EXIT_OK

    estimated_bytes = sum(batch.estimated_bytes for batch in batches)
    required_bytes = max(estimated_bytes * 2, 1)
    if not check_disk_space(args.archive_dir, required_bytes):
        LOGGER.error(
            "Insufficient disk space for archive work in %s (need %s + 500MB buffer)",
            os.path.expanduser(args.archive_dir),
            _format_bytes(required_bytes),
        )
        return EXIT_LOW_DISK

    eligible_count = _log_archive_plan(batches)
    LOGGER.info(
        "archive preflight estimated_total_bytes=%s for %s eligible sessions",
        _format_bytes(estimated_bytes),
        eligible_count,
    )

    if not args.apply:
        LOGGER.info("dry-run only; no archive files created and no hot-db rows deleted")
        return EXIT_OK

    try:
        for batch in batches:
            LOGGER.info(
                "copying month=%s sessions=%s target=%s",
                batch.month,
                len(batch.session_ids),
                batch.archive_path,
            )
            _copy_archive_batch(args.db_path, batch)
            LOGGER.info(
                "validated archive month=%s counts=%s target=%s",
                batch.month,
                batch.source_counts,
                batch.archive_path,
            )

        _delete_archived_rows(
            args.db_path,
            eligible_ids,
            _aggregate_source_counts(batches),
        )
        LOGGER.info(
            "deleted archived rows from hot database for %s sessions", len(eligible_ids)
        )

        _compress_past_month_archives(args.archive_dir)
    except sqlite3.Error as exc:
        LOGGER.error("Archive failed: %s", exc)
        return EXIT_ERROR
    except OSError as exc:
        LOGGER.error("Archive file operation failed: %s", exc)
        return EXIT_ERROR

    LOGGER.info("archive apply completed successfully")
    return EXIT_OK


def handle_restore(args: argparse.Namespace) -> int:
    LOGGER.info(
        "restore requested mode=%s db=%s archive=%s session=%s",
        "apply" if args.apply else "dry-run",
        args.db_path,
        args.archive,
        args.session,
    )
    if not _ensure_db_exists(args.db_path):
        return EXIT_ERROR

    archive_path = Path(args.archive)
    if not archive_path.exists():
        LOGGER.error("Archive not found: %s", archive_path)
        return EXIT_ERROR

    temp_archive_path: Path | None = None
    try:
        archive_db_path, temp_archive_path = _prepare_restore_archive_db(archive_path)

        with get_db_connection(str(archive_db_path), readonly=True) as archive_conn:
            archive_conn.row_factory = sqlite3.Row
            session_row = archive_conn.execute(
                "SELECT * FROM session WHERE id = ?", (args.session,)
            ).fetchone()
            if session_row is None:
                LOGGER.error(
                    "Session %s not found in archive %s", args.session, archive_path
                )
                return EXIT_ERROR

            source_counts = _session_row_counts(archive_conn, args.session)
            _log_restore_report(archive_path, session_row, source_counts)

        with get_db_connection(args.db_path, readonly=True) as hot_conn:
            existing_row = hot_conn.execute(
                "SELECT id FROM session WHERE id = ?", (args.session,)
            ).fetchone()
            if existing_row is not None:
                LOGGER.warning("session %s already in hot DB, skipping", args.session)
                return EXIT_OK

        if not args.apply:
            LOGGER.info("dry-run only; no hot-db rows restored")
            return EXIT_OK

        return _restore_session_apply(
            args.db_path, archive_db_path, args.session, source_counts
        )
    except sqlite3.Error as exc:
        LOGGER.error("Restore failed: %s", exc)
        return EXIT_ERROR
    except OSError as exc:
        LOGGER.error("Restore file operation failed: %s", exc)
        return EXIT_ERROR
    finally:
        _cleanup_temp_restore_archive(temp_archive_path)


def handle_maintenance(args: argparse.Namespace) -> int:
    LOGGER.info(
        "maintenance requested mode=%s db=%s migrate_auto_vacuum=%s",
        "apply" if args.apply else "dry-run",
        args.db_path,
        args.migrate_auto_vacuum,
    )
    if not _ensure_db_exists(args.db_path):
        return EXIT_ERROR

    if not args.apply:
        try:
            with get_db_connection(args.db_path, readonly=True) as conn:
                current_metrics = _collect_maintenance_metrics(conn, args.db_path)
        except sqlite3.Error as exc:
            LOGGER.error("Failed to inspect maintenance state: %s", exc)
            return EXIT_ERROR

        _log_maintenance_dry_run(
            current_metrics, args.migrate_auto_vacuum, args.db_path
        )
        return EXIT_OK

    if check_db_busy(args.db_path):
        LOGGER.error("Database is busy or locked: %s", args.db_path)
        return EXIT_BUSY

    integrity_code = _run_integrity_check(args.db_path, readonly=False)
    if integrity_code != EXIT_OK:
        return integrity_code

    try:
        with get_db_connection(args.db_path, readonly=False) as conn:
            before_checkpoint = _collect_maintenance_metrics(conn, args.db_path)
            _log_maintenance_metrics(
                "maintenance state before apply:", before_checkpoint
            )

            _run_wal_checkpoint(conn)
            after_checkpoint = _collect_maintenance_metrics(conn, args.db_path)
            _log_maintenance_metrics(
                "maintenance state after checkpoint:", after_checkpoint
            )

            migration_code = _maybe_migrate_auto_vacuum(
                conn, args.db_path, args.migrate_auto_vacuum
            )
            if migration_code != EXIT_OK:
                return migration_code

            if args.migrate_auto_vacuum:
                post_migration_metrics = _collect_maintenance_metrics(
                    conn, args.db_path
                )
                _log_maintenance_metrics(
                    "maintenance state after auto_vacuum evaluation:",
                    post_migration_metrics,
                )

            vacuum_before, vacuum_after = _run_incremental_vacuum(conn, args.db_path)
            freed_pages_estimate = (
                vacuum_before.freelist_count - vacuum_after.freelist_count
            )
            reclaimed_bytes_estimate = freed_pages_estimate * max(
                vacuum_after.page_size, vacuum_before.page_size, 0
            )
            LOGGER.info(
                "incremental vacuum conservative report freed_pages_estimate=%s reclaimed_bytes_estimate=%s page_count_delta=%s freelist_before=%s freelist_after=%s",
                freed_pages_estimate,
                reclaimed_bytes_estimate,
                vacuum_before.page_count - vacuum_after.page_count,
                vacuum_before.freelist_count,
                vacuum_after.freelist_count,
            )
            _log_maintenance_metrics("maintenance state after apply:", vacuum_after)
    except sqlite3.Error as exc:
        LOGGER.error("Maintenance failed: %s", exc)
        return EXIT_ERROR

    return EXIT_OK


def handle_status(args: argparse.Namespace) -> int:
    if not _ensure_db_exists(args.db_path):
        return EXIT_ERROR

    cutoff_ms = get_cutoff_timestamp(args.days)
    cutoff_utc = datetime.fromtimestamp(cutoff_ms / 1000, tz=timezone.utc)

    try:
        with get_db_connection(args.db_path, readonly=True) as conn:
            metrics = _collect_maintenance_metrics(conn, args.db_path)
            row_counts = _collect_hot_db_row_counts(conn)
            quick_check_result = _run_quick_check(conn)
            eligible_total, eligible_estimated_bytes, eligible_breakdown = (
                _collect_eligible_session_stats(conn, cutoff_ms)
            )
    except sqlite3.Error as exc:
        LOGGER.error("Failed to inspect status: %s", exc)
        return EXIT_ERROR

    try:
        archive_entries, total_archive_size, archive_notice = (
            _collect_archive_inventory(args.archive_dir)
        )
    except OSError as exc:
        LOGGER.error("Failed to inspect archive directory: %s", exc)
        return EXIT_ERROR

    lines = [
        "OpenCode Maintenance Status",
        "==========================",
        f"Database: {args.db_path}",
        f"Archive directory: {args.archive_dir}",
        f"Retention cutoff: {cutoff_utc.strftime('%Y-%m-%d %H:%M:%S UTC')} ({args.days} days)",
        "",
        "Hot DB Health",
        "-------------",
    ]

    health_rows = [
        ("DB size", _format_bytes_with_exact(_main_db_size_bytes(args.db_path))),
        ("WAL size", _format_bytes_with_exact(metrics.wal_size_bytes)),
        ("session rows", str(row_counts["session"])),
        ("message rows", str(row_counts["message"])),
        ("part rows", str(row_counts["part"])),
        ("todo rows", str(row_counts["todo"])),
        ("freelist_count", str(metrics.freelist_count)),
        (
            "auto_vacuum",
            f"{_auto_vacuum_mode_name(metrics.auto_vacuum)} ({metrics.auto_vacuum})",
        ),
        ("journal_mode", metrics.journal_mode),
        ("quick_check", quick_check_result),
    ]
    lines.extend(f"{label:<18} {value}" for label, value in health_rows)

    lines.extend(["", "Eligible Sessions", "-----------------"])
    lines.append(f"{'eligible_sessions':<18} {eligible_total}")
    lines.append(
        f"{'eligible_size_est':<18} {_format_bytes_with_exact(eligible_estimated_bytes)} (approximate payload bytes)"
    )
    if eligible_breakdown:
        lines.append("")
        lines.extend(
            _render_table(
                ("Month", "Sessions", "Approx Size"),
                [
                    (month, str(count), _format_bytes_with_exact(estimated_bytes))
                    for month, count, estimated_bytes in eligible_breakdown
                ],
            )
        )
    else:
        lines.append("No sessions are currently eligible for archival.")

    lines.extend(["", "Archive Inventory", "-----------------"])
    if archive_notice:
        lines.append(archive_notice)
    else:
        inventory_rows = [
            (filename, kind, _format_bytes_with_exact(size_bytes), sessions, note)
            for filename, kind, size_bytes, sessions, note in archive_entries
        ]
        lines.extend(
            _render_table(
                ("Filename", "Type", "Size", "Sessions", "Notes"),
                inventory_rows,
            )
        )
    lines.append("")
    lines.append(
        f"{'total_archive_size':<18} {_format_bytes_with_exact(total_archive_size)}"
    )

    print("\n".join(lines))
    return EXIT_OK if quick_check_result == "ok" else EXIT_INTEGRITY_FAIL


def build_parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument(
        "--apply",
        action="store_true",
        help="apply changes instead of running in dry-run mode",
    )
    common.add_argument(
        "--days",
        type=int,
        default=DEFAULT_RETENTION_DAYS,
        help=f"retention window in days (default: {DEFAULT_RETENTION_DAYS})",
    )
    common.add_argument(
        "--db-path",
        default=DB_PATH,
        help=f"SQLite database path (default: {DB_PATH})",
    )
    common.add_argument(
        "--archive-dir",
        default=ARCHIVE_DIR,
        help=f"archive directory path (default: {ARCHIVE_DIR})",
    )
    common.add_argument(
        "--verbose",
        action="store_true",
        help="enable debug logging",
    )

    parser = argparse.ArgumentParser(
        description="OpenCode database maintenance scaffold",
        parents=[common],
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    archive_parser = subparsers.add_parser(
        "archive",
        parents=[common],
        help="archive old session data",
        description="Archive old session data.",
    )
    archive_parser.set_defaults(handler=handle_archive)

    restore_parser = subparsers.add_parser(
        "restore",
        parents=[common],
        help="restore archived session data",
        description="Restore one archived session into the hot database.",
    )
    restore_parser.add_argument(
        "--archive",
        required=True,
        help="archive database path (.db or .db.gz)",
    )
    restore_parser.add_argument(
        "--session",
        required=True,
        help="session ID to restore from the archive",
    )
    restore_parser.set_defaults(handler=handle_restore)

    maintenance_parser = subparsers.add_parser(
        "maintenance",
        parents=[common],
        help="run WAL checkpoint and vacuum maintenance",
        description="Run maintenance workflow for WAL checkpointing and vacuuming.",
    )
    maintenance_parser.add_argument(
        "--migrate-auto-vacuum",
        action="store_true",
        help="explicitly migrate auto_vacuum from NONE to INCREMENTAL with VACUUM",
    )
    maintenance_parser.set_defaults(handler=handle_maintenance)

    status_parser = subparsers.add_parser(
        "status",
        help="show maintenance status",
        description="Show read-only database health and archive inventory.",
    )
    status_parser.add_argument(
        "--days",
        type=int,
        default=DEFAULT_RETENTION_DAYS,
        help=f"retention window in days (default: {DEFAULT_RETENTION_DAYS})",
    )
    status_parser.add_argument(
        "--db-path",
        default=DB_PATH,
        help=f"SQLite database path (default: {DB_PATH})",
    )
    status_parser.add_argument(
        "--archive-dir",
        default=ARCHIVE_DIR,
        help=f"archive directory path (default: {ARCHIVE_DIR})",
    )
    status_parser.add_argument(
        "--verbose",
        action="store_true",
        help="enable debug logging",
    )
    status_parser.set_defaults(handler=handle_status)

    return parser


def main(argv: list[str] | None = None) -> None:
    parser = build_parser()
    args = parser.parse_args(argv)
    args.db_path = os.path.expanduser(args.db_path)
    args.archive_dir = os.path.expanduser(args.archive_dir)
    if hasattr(args, "archive"):
        args.archive = os.path.expanduser(args.archive)
    configure_logging(args.verbose)

    exit_code = args.handler(args)
    raise SystemExit(exit_code)


if __name__ == "__main__":
    main()
