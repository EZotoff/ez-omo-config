#!/usr/bin/env bash
set -euo pipefail

# wisdom-restore.sh — Restore a Wisdom migration backup tarball.

usage() {
    cat >&2 <<'EOF'
Usage: wisdom-restore.sh --backup TARBALL [--target-root DIR]

Options:
  --backup TARBALL      Path to backup tar.gz produced by wisdom-migrate.sh
  --target-root DIR     Restore root directory (default: /)
  --help, -h            Show this help
EOF
}

BACKUP_TARBALL=""
TARGET_ROOT="/"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --backup)
            BACKUP_TARBALL="${2:-}"
            shift 2
            ;;
        --target-root)
            TARGET_ROOT="${2:-}"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            usage
            exit 2
            ;;
    esac
done

if [[ -z "$BACKUP_TARBALL" ]]; then
    echo "ERROR: --backup is required" >&2
    usage
    exit 2
fi

if [[ ! -f "$BACKUP_TARBALL" ]]; then
    echo "ERROR: Backup tarball not found: $BACKUP_TARBALL" >&2
    exit 1
fi

mkdir -p "$TARGET_ROOT"
tar -xzf "$BACKUP_TARBALL" -C "$TARGET_ROOT"

echo "Restore complete: $BACKUP_TARBALL -> $TARGET_ROOT"
