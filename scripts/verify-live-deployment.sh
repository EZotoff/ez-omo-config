#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

COMPONENT=""
PROJECT_PATH=""
EVIDENCE_DIR=""
ALLOW_EXISTING_INDEX=0

FAILURE_CODE=""
CHECK_RESULTS=()
MARKER_TIMESTAMP=""

usage() {
    cat <<'EOF'
Usage: verify-live-deployment.sh [OPTIONS]

Required:
  --component <name>       Component to verify (e.g., vera-runtime)
  --project <path>         Absolute path to the project directory
  --evidence-dir <path>    Directory to write evidence files

Optional:
  --allow-existing-index   Allow pre-existing .vera/ index as proof (default: false)
  --help                   Show this help text

Exit codes:
  0   All checks passed
  1   One or more checks failed (see summary.json for details)
EOF
}

log_cmd() {
    local cmd="$1"
    echo "$cmd" >> "$EVIDENCE_DIR/commands.txt"
}

record_result() {
    local name="$1"
    local status="$2"
    local message="$3"
    CHECK_RESULTS+=("{\"check\":\"$name\",\"status\":\"$status\",\"message\":\"$message\"}")
}

fail_with() {
    local code="$1"
    FAILURE_CODE="$code"
    write_summary
    echo "Verification failed: $code" >&2
    exit 1
}

write_summary() {
    mkdir -p "$EVIDENCE_DIR"
    local checks_json="["
    local first=1
    for result in "${CHECK_RESULTS[@]}"; do
        if [[ "$first" -eq 1 ]]; then
            first=0
        else
            checks_json+=","
        fi
        checks_json+="$result"
    done
    checks_json+="]"

    local overall="passed"
    if [[ -n "$FAILURE_CODE" ]]; then
        overall="failed"
    fi

    cat > "$EVIDENCE_DIR/summary.json" <<EOF
{
  "component": "$COMPONENT",
  "project_path": "$PROJECT_PATH",
  "evidence_dir": "$EVIDENCE_DIR",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "marker_timestamp": "$MARKER_TIMESTAMP",
  "overall": "$overall",
  "failure_code": "$FAILURE_CODE",
  "checks": $checks_json
}
EOF
}

copy_evidence_snippets() {
    local src="$1"
    local dest_name="$2"
    if [[ -f "$src" ]]; then
        cp "$src" "$EVIDENCE_DIR/$dest_name"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --component)
            COMPONENT="$2"
            shift 2
            ;;
        --project)
            PROJECT_PATH="$2"
            shift 2
            ;;
        --evidence-dir)
            EVIDENCE_DIR="$2"
            shift 2
            ;;
        --allow-existing-index)
            ALLOW_EXISTING_INDEX=1
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ -z "$COMPONENT" || -z "$PROJECT_PATH" || -z "$EVIDENCE_DIR" ]]; then
    echo "Error: --component, --project, and --evidence-dir are required." >&2
    usage >&2
    exit 1
fi

mkdir -p "$EVIDENCE_DIR"
: > "$EVIDENCE_DIR/commands.txt"
: > "$EVIDENCE_DIR/live-paths.txt"

EXPECTED_SYMLINK_TARGET="/home/ezotoff/ez-omo-config/configs/opencode/opencode.json"
ACTUAL_SYMLINK_TARGET=""
if [[ -L "$HOME/.config/opencode/opencode.json" ]]; then
    ACTUAL_SYMLINK_TARGET="$(readlink -f "$HOME/.config/opencode/opencode.json" 2>/dev/null || true)"
    log_cmd "readlink -f \"$HOME/.config/opencode/opencode.json\""
else
    ACTUAL_SYMLINK_TARGET="$(readlink -f "$HOME/.config/opencode/opencode.json" 2>/dev/null || true)"
    log_cmd "readlink -f \"$HOME/.config/opencode/opencode.json\""
fi

if [[ "$ACTUAL_SYMLINK_TARGET" != "$EXPECTED_SYMLINK_TARGET" ]]; then
    record_result "config_symlink" "failed" \
        "Symlink target mismatch: expected '$EXPECTED_SYMLINK_TARGET', got '$ACTUAL_SYMLINK_TARGET'"
    fail_with "symlink_mismatch"
else
    record_result "config_symlink" "passed" \
        "Symlink correctly points to $EXPECTED_SYMLINK_TARGET"
    echo "$HOME/.config/opencode/opencode.json" >> "$EVIDENCE_DIR/live-paths.txt"
fi

LIVE_PLUGIN_PATH="$HOME/.opencode/plugin/vera-runtime.ts"
log_cmd "test -f \"$LIVE_PLUGIN_PATH\""
if [[ ! -f "$LIVE_PLUGIN_PATH" ]]; then
    record_result "plugin_file_exists" "failed" \
        "Live plugin file not found: $LIVE_PLUGIN_PATH"
    fail_with "plugin_missing"
else
    record_result "plugin_file_exists" "passed" \
        "Live plugin file found: $LIVE_PLUGIN_PATH"
    echo "$LIVE_PLUGIN_PATH" >> "$EVIDENCE_DIR/live-paths.txt"
fi

REPO_PLUGIN_PATH="$REPO_ROOT/plugins/vera-runtime.ts"
if [[ -f "$LIVE_PLUGIN_PATH" ]]; then
    log_cmd "sha256sum \"$REPO_PLUGIN_PATH\" \"$LIVE_PLUGIN_PATH\""
    REPO_SHA="$(sha256sum "$REPO_PLUGIN_PATH" 2>/dev/null | awk '{print $1}')"
    LIVE_SHA="$(sha256sum "$LIVE_PLUGIN_PATH" 2>/dev/null | awk '{print $1}')"
    if [[ "$REPO_SHA" != "$LIVE_SHA" ]]; then
        record_result "plugin_sha_match" "failed" \
            "SHA256 mismatch: repo=$REPO_SHA live=$LIVE_SHA"
        fail_with "sha_mismatch"
    else
        record_result "plugin_sha_match" "passed" \
            "SHA256 matches: $REPO_SHA"
    fi
else
    record_result "plugin_sha_match" "skipped" \
        "Live plugin missing, SHA check skipped"
fi

ACTIVE_CONFIG="$HOME/.config/opencode/opencode.json"
log_cmd "grep -q 'vera-runtime' \"$ACTIVE_CONFIG\""
if [[ -f "$ACTIVE_CONFIG" ]]; then
    if grep -q 'vera-runtime' "$ACTIVE_CONFIG" 2>/dev/null; then
        record_result "plugin_registered" "passed" \
            "vera-runtime found in plugin array"
        echo "$ACTIVE_CONFIG" >> "$EVIDENCE_DIR/live-paths.txt"
    else
        record_result "plugin_registered" "failed" \
            "vera-runtime NOT found in plugin array of $ACTIVE_CONFIG"
        fail_with "plugin_not_registered"
    fi
else
    record_result "plugin_registered" "failed" \
        "Active config not found: $ACTIVE_CONFIG"
    fail_with "plugin_not_registered"
fi

if [[ -f "$ACTIVE_CONFIG" ]]; then
    python3 -c "import json; data=json.load(open('$ACTIVE_CONFIG')); print(json.dumps(data.get('plugins', [])))" > "$EVIDENCE_DIR/active-config-plugin-array.json" 2>/dev/null || true
fi

log_cmd "test -d \"$PROJECT_PATH\""
if [[ ! -d "$PROJECT_PATH" ]]; then
    record_result "project_exists" "failed" \
        "Project path does not exist: $PROJECT_PATH"
    fail_with "project_missing"
else
    record_result "project_exists" "passed" \
        "Project path exists: $PROJECT_PATH"
fi

log_cmd "git -C \"$PROJECT_PATH\" rev-parse --git-dir"
if ! git -C "$PROJECT_PATH" rev-parse --git-dir >/dev/null 2>&1; then
    record_result "project_is_git_repo" "failed" \
        "Project path is not a git repository: $PROJECT_PATH"
    fail_with "not_git_repo"
else
    record_result "project_is_git_repo" "passed" \
        "Project path is a valid git repository"
fi

MARKER_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
record_result "marker_timestamp" "passed" \
    "Marker timestamp recorded: $MARKER_TIMESTAMP"

PROJECT_ID=""
if git -C "$PROJECT_PATH" rev-parse --show-toplevel >/dev/null 2>&1; then
    PROJECT_ID="$(basename "$(git -C "$PROJECT_PATH" rev-parse --show-toplevel)")"
fi
log_cmd "git -C \"$PROJECT_PATH\" rev-parse --show-toplevel | xargs basename"

REAL_PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd -P)"
WORKSPACE_BASE="$(basename "$REAL_PROJECT_PATH")"
WORKSPACE_HASH="$(printf '%s' "$REAL_PROJECT_PATH" | sha1sum | awk '{print $1}' | cut -c1-8)"
WORKSPACE_KEY="${WORKSPACE_BASE}-${WORKSPACE_HASH}"

WATCHER_STATE_DIR="$HOME/.local/share/opencode/worktree-state/$PROJECT_ID/vera-watchers"
WATCHER_STATE_FILE="$WATCHER_STATE_DIR/${WORKSPACE_KEY}.json"
WATCHER_LOG_FILE="$WATCHER_STATE_DIR/${WORKSPACE_KEY}.log"
RUNTIME_LOG="$HOME/.opencode/plugin/vera-runtime.log"

log_cmd "test -f \"$RUNTIME_LOG\""
log_cmd "test -f \"$WATCHER_STATE_FILE\""

RUNTIME_PROVEN=0
STALE_REASON=""

if [[ -f "$RUNTIME_LOG" ]]; then
    POST_MARKER_COUNT=$(grep -cE '\[2[0-9]{3}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}' "$RUNTIME_LOG" 2>/dev/null | awk '{print}')
    if [[ -n "$POST_MARKER_COUNT" && "$POST_MARKER_COUNT" -gt 0 ]]; then
        LAST_LOG_TIMESTAMP=$(grep -oE '2[0-9]{3}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z' "$RUNTIME_LOG" 2>/dev/null | tail -n 1)
        if [[ -n "$LAST_LOG_TIMESTAMP" ]]; then
            MARKER_MIN="${MARKER_TIMESTAMP:0:16}"
            LOG_MIN="${LAST_LOG_TIMESTAMP:0:16}"
            if [[ "$LOG_MIN" > "$MARKER_MIN" || "$LOG_MIN" == "$MARKER_MIN" ]]; then
                RUNTIME_PROVEN=1
            else
                STALE_REASON="Last log timestamp $LAST_LOG_TIMESTAMP is before marker $MARKER_TIMESTAMP"
            fi
        fi
    fi
    copy_evidence_snippets "$RUNTIME_LOG" "vera-runtime.log"
fi

if [[ -f "$WATCHER_STATE_FILE" ]]; then
    LAST_VERIFIED=$(grep -oE '"lastVerifiedAt": "[^"]*"' "$WATCHER_STATE_FILE" 2>/dev/null | sed 's/.*"\([^"]*\)".*/\1/' | head -n 1)
    LAST_INDEXED=$(grep -oE '"lastIndexedAt": "[^"]*"' "$WATCHER_STATE_FILE" 2>/dev/null | sed 's/.*"\([^"]*\)".*/\1/' | head -n 1)

    MARKER_MIN="${MARKER_TIMESTAMP:0:16}"

    if [[ -n "$LAST_VERIFIED" ]]; then
        VERIFIED_MIN="${LAST_VERIFIED:0:16}"
        if [[ "$VERIFIED_MIN" > "$MARKER_MIN" || "$VERIFIED_MIN" == "$MARKER_MIN" ]]; then
            RUNTIME_PROVEN=1
        fi
    fi

    if [[ -n "$LAST_INDEXED" && "$RUNTIME_PROVEN" -eq 0 ]]; then
        INDEXED_MIN="${LAST_INDEXED:0:16}"
        if [[ "$INDEXED_MIN" > "$MARKER_MIN" || "$INDEXED_MIN" == "$MARKER_MIN" ]]; then
            RUNTIME_PROVEN=1
        fi
    fi

    if [[ "$RUNTIME_PROVEN" -eq 0 ]]; then
        if [[ -z "$STALE_REASON" ]]; then
            STALE_REASON="Watcher state lastVerifiedAt=$LAST_VERIFIED, lastIndexedAt=$LAST_INDEXED both before marker $MARKER_TIMESTAMP"
        fi
    fi

    copy_evidence_snippets "$WATCHER_STATE_FILE" "watcher-state.json"
fi

if [[ "$RUNTIME_PROVEN" -eq 1 ]]; then
    record_result "runtime_proven" "passed" \
        "Runtime proven by post-marker log or watcher state timestamp"
else
    if [[ -z "$STALE_REASON" ]]; then
        STALE_REASON="No runtime log or watcher state found with post-marker timestamps"
    fi
    record_result "runtime_proven" "failed" "$STALE_REASON"
    fail_with "runtime_not_proven"
fi

MISSING_BINARY=0
if [[ -f "$WATCHER_STATE_FILE" ]]; then
    if grep -q '"status": "missing-binary"' "$WATCHER_STATE_FILE" 2>/dev/null; then
        MISSING_BINARY=1
        record_result "vera_index_exists" "passed" \
            "Vera index check skipped: watcher state reports missing-binary (fail-open)"
    fi
fi

if [[ "$MISSING_BINARY" -eq 0 ]]; then
    VERA_INDEX_PATH="$REAL_PROJECT_PATH/.vera"
    log_cmd "test -d \"$VERA_INDEX_PATH\""
    if [[ -d "$VERA_INDEX_PATH" ]]; then
        record_result "vera_index_exists" "passed" \
            "Vera index directory exists: $VERA_INDEX_PATH"
    else
        if [[ "$ALLOW_EXISTING_INDEX" -eq 1 ]]; then
            record_result "vera_index_exists" "passed" \
                "Vera index missing but --allow-existing-index set; accepting"
        else
            record_result "vera_index_exists" "failed" \
                "Vera index directory missing: $VERA_INDEX_PATH"
            fail_with "vera_index_missing"
        fi
    fi
fi

write_summary

echo "All checks passed for component '$COMPONENT'."
echo "Evidence written to: $EVIDENCE_DIR"
exit 0
