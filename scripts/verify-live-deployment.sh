#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

COMPONENT=""
PROJECT_PATH=""
EVIDENCE_DIR=""
PROBE_QUERY=""
PROBE_EXPECT=""

FAILURE_CODE=""
CHECK_RESULTS=()
MARKER_TIMESTAMP=""

HIGHEST_STATE="repo_implemented"
DEFAULT_AUTOMATION_MODE="manual"

usage() {
    cat <<'EOF'
Usage: verify-live-deployment.sh [OPTIONS]

Required:
  --component <name>       Component to verify (e.g., vera-runtime)
  --project <path>         Absolute path to the project directory
  --evidence-dir <path>    Directory to write evidence files

Optional:
  --probe-query <query>    Search query required to reach real_project_behavior_proven
  --probe-expect <string>  Expected substring or path in search results
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
    local result_json
    result_json="$(CHECK_NAME="$name" CHECK_STATUS="$status" CHECK_MESSAGE="$message" python3 - <<'PY'
import json
import os

print(json.dumps({
    "check": os.environ["CHECK_NAME"],
    "status": os.environ["CHECK_STATUS"],
    "message": os.environ["CHECK_MESSAGE"],
}, separators=(",", ":")))
PY
)"
    CHECK_RESULTS+=("$result_json")
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

    SUMMARY_PATH="$EVIDENCE_DIR/summary.json" \
    SUMMARY_COMPONENT="$COMPONENT" \
    SUMMARY_PROJECT_PATH="$PROJECT_PATH" \
    SUMMARY_EVIDENCE_DIR="$EVIDENCE_DIR" \
    SUMMARY_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    SUMMARY_MARKER_TIMESTAMP="$MARKER_TIMESTAMP" \
    SUMMARY_OVERALL="$overall" \
    SUMMARY_FAILURE_CODE="$FAILURE_CODE" \
    SUMMARY_HIGHEST_STATE="$HIGHEST_STATE" \
    SUMMARY_CHECKS_JSON="$checks_json" \
    python3 - <<'PY'
import json
import os

summary = {
    "component": os.environ["SUMMARY_COMPONENT"],
    "project_path": os.environ["SUMMARY_PROJECT_PATH"],
    "evidence_dir": os.environ["SUMMARY_EVIDENCE_DIR"],
    "timestamp": os.environ["SUMMARY_TIMESTAMP"],
    "marker_timestamp": os.environ["SUMMARY_MARKER_TIMESTAMP"],
    "overall": os.environ["SUMMARY_OVERALL"],
    "failure_code": os.environ["SUMMARY_FAILURE_CODE"],
    "highest_state": os.environ["SUMMARY_HIGHEST_STATE"],
    "checks": json.loads(os.environ["SUMMARY_CHECKS_JSON"]),
}

with open(os.environ["SUMMARY_PATH"], "w", encoding="utf-8") as fh:
    json.dump(summary, fh, indent=2)
    fh.write("\n")
PY
}

timestamp_second() {
    local ts="$1"
    if [[ "$ts" == *.*Z ]]; then
        printf '%sZ' "${ts%%.*}"
    else
        printf '%s' "$ts"
    fi
}

timestamp_at_or_after_marker() {
    local ts
    ts="$(timestamp_second "$1")"
    [[ "$ts" > "$MARKER_TIMESTAMP" || "$ts" == "$MARKER_TIMESTAMP" ]]
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
        --probe-query)
            PROBE_QUERY="$2"
            shift 2
            ;;
        --probe-expect)
            PROBE_EXPECT="$2"
            shift 2
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

EXPECTED_SYMLINK_TARGET="$REPO_ROOT/configs/opencode/opencode.json"
ACTUAL_SYMLINK_TARGET=""
ACTUAL_SYMLINK_TARGET="$(readlink -f "$HOME/.config/opencode/opencode.json" 2>/dev/null || true)"
log_cmd "readlink -f \"$HOME/.config/opencode/opencode.json\""

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

HIGHEST_STATE="live_file_installed"

ACTIVE_CONFIG="$HOME/.config/opencode/opencode.json"
log_cmd "test -f \"$ACTIVE_CONFIG\""
if [[ -f "$ACTIVE_CONFIG" ]]; then
    record_result "active_config_exists" "passed" \
        "Active config found: $ACTIVE_CONFIG"
    echo "$ACTIVE_CONFIG" >> "$EVIDENCE_DIR/live-paths.txt"
else
    record_result "active_config_exists" "failed" \
        "Active config not found: $ACTIVE_CONFIG"
    fail_with "active_config_missing"
fi

if ACTIVE_CONFIG_PATH="$ACTIVE_CONFIG" EVIDENCE_OUTPUT_DIR="$EVIDENCE_DIR" python3 - <<'PY' > "$EVIDENCE_DIR/active-config-extraction.log" 2>&1
import json
import os

try:
    active_config = os.environ["ACTIVE_CONFIG_PATH"]
    evidence_dir = os.environ["EVIDENCE_OUTPUT_DIR"]
    with open(active_config, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    plugin = data.get("plugin", [])
    if not isinstance(plugin, list):
        raise ValueError("plugin is not a list")
    explicit_vera = [item for item in plugin if isinstance(item, str) and "vera-runtime.ts" in item]
    if explicit_vera:
        raise ValueError("vera-runtime.ts must not be explicitly listed in opencode.json plugin array")
    with open(os.path.join(evidence_dir, "active-config-plugin-array.json"), "w", encoding="utf-8") as out:
        json.dump(plugin, out)
    print("ok")
except Exception as e:
    print("error:", e)
    raise SystemExit(1)
PY
then
    record_result "active_config_autoload" "passed" \
        "Active config has valid 'plugin' list key and does not explicitly list vera-runtime.ts"
    HIGHEST_STATE="active_config_registered"
else
    record_result "active_config_autoload" "failed" \
        "Active config missing valid 'plugin' list key"
    fail_with "active_config_invalid"
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

MARKER_TIMESTAMP="${OMO_VERIFY_MARKER_TIMESTAMP_OVERRIDE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
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
LIFECYCLE_EVENT_FOUND=0
STALE_REASON=""
EVIDENCE_FOUND=0

: > "$EVIDENCE_DIR/runtime-project-evidence.txt"

if [[ -f "$RUNTIME_LOG" ]]; then
    EVIDENCE_FOUND=1
    POST_MARKER_COUNT="$(grep -cE '\[2[0-9]{3}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}' "$RUNTIME_LOG" 2>/dev/null || true)"
    if [[ -n "$POST_MARKER_COUNT" && "$POST_MARKER_COUNT" -gt 0 ]]; then
        while IFS= read -r line; do
            log_ts="$(echo "$line" | grep -oE '2[0-9]{3}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z' | head -n1 || true)"
            if [[ -n "$log_ts" ]]; then
                if timestamp_at_or_after_marker "$log_ts"; then
                    if [[ "$line" == *"$REAL_PROJECT_PATH"* || "$line" == *"$WORKSPACE_KEY"* ]]; then
                        echo "$line" >> "$EVIDENCE_DIR/runtime-project-evidence.txt"
                        if [[ "$line" == *"event hook invoked"* || \
                             "$line" == *"session.created handled"* || \
                             "$line" == *"watcher started pid="* || \
                             "$line" == *"watcher_state verified"* ]]; then
                            LIFECYCLE_EVENT_FOUND=1
                        fi
                    fi
                fi
            fi
        done < "$RUNTIME_LOG"
    fi
    copy_evidence_snippets "$RUNTIME_LOG" "runtime-log-snippet.txt"
fi

WATCHER_STATUS=""
WATCHER_PID=""
WATCHER_WORKSPACE_KEY=""
WATCHER_WORKSPACE_PATH=""
LAST_VERIFIED=""
LAST_INDEXED=""
LAST_FAILURE_REASON=""
WATCHER_AUTOMATION_MODE=""
WATCHER_SESSION_COUNT="0"

if [[ -f "$WATCHER_STATE_FILE" ]]; then
    EVIDENCE_FOUND=1
    WATCHER_JSON="$(WATCHER_STATE_PATH="$WATCHER_STATE_FILE" python3 - <<'PY' 2>/dev/null
import json
import os
import sys

try:
    with open(os.environ["WATCHER_STATE_PATH"], "r", encoding="utf-8") as fh:
        data = json.load(fh)
    sessions = data.get("sessionIds", [])
    result = {
        "status": data.get("status", ""),
        "pid": data.get("pid", ""),
        "workspaceKey": data.get("workspaceKey", ""),
        "workspacePath": data.get("workspacePath", ""),
        "projectRoot": data.get("projectRoot", ""),
        "lastVerifiedAt": data.get("lastVerifiedAt", ""),
        "lastIndexedAt": data.get("lastIndexedAt", ""),
        "lastFailureReason": data.get("lastFailureReason", ""),
        "automationMode": data.get("automationMode", ""),
        "sessionCount": len(sessions) if isinstance(sessions, list) else 0,
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"error": str(e)}))
    sys.exit(1)
PY
)" || WATCHER_JSON="{}"

    WATCHER_STATUS="$(echo "$WATCHER_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('status',''))")"
    WATCHER_PID="$(echo "$WATCHER_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); pid=d.get('pid'); print(pid if isinstance(pid, int) and 1 < pid <= 4194304 else '')")"
    WATCHER_WORKSPACE_KEY="$(echo "$WATCHER_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('workspaceKey',''))")"
    WATCHER_WORKSPACE_PATH="$(echo "$WATCHER_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('workspacePath','') or d.get('projectRoot',''))")"
    LAST_VERIFIED="$(echo "$WATCHER_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('lastVerifiedAt',''))")"
    LAST_INDEXED="$(echo "$WATCHER_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('lastIndexedAt',''))")"
    LAST_FAILURE_REASON="$(echo "$WATCHER_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('lastFailureReason',''))")"
    WATCHER_AUTOMATION_MODE="$(echo "$WATCHER_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('automationMode',''))")"
    WATCHER_SESSION_COUNT="$(echo "$WATCHER_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('sessionCount',0))")"

    WATCHER_STATE_CAN_PROVE_RUNTIME=0
    if [[ "$WATCHER_AUTOMATION_MODE" == "autostart" && "$WATCHER_STATUS" == "running" && -n "$WATCHER_PID" && "$WATCHER_PID" != "null" ]]; then
        WATCHER_STATE_CAN_PROVE_RUNTIME=1
    fi

    if [[ "$WATCHER_AUTOMATION_MODE" == "manual" && "$WATCHER_STATUS" == "stopped" ]]; then
        echo "watcher_state manual-only: workspaceKey=$WATCHER_WORKSPACE_KEY workspacePath=$WATCHER_WORKSPACE_PATH status=$WATCHER_STATUS sessions=$WATCHER_SESSION_COUNT" >> "$EVIDENCE_DIR/runtime-project-evidence.txt"
    elif [[ -n "$LAST_VERIFIED" && "$LAST_VERIFIED" != "null" && "$WATCHER_STATE_CAN_PROVE_RUNTIME" -eq 1 ]]; then
        if timestamp_at_or_after_marker "$LAST_VERIFIED"; then
            if [[ "$WATCHER_WORKSPACE_KEY" == "$WORKSPACE_KEY" || "$WATCHER_WORKSPACE_PATH" == "$REAL_PROJECT_PATH" ]]; then
                RUNTIME_PROVEN=1
                echo "watcher_state verified: workspaceKey=$WATCHER_WORKSPACE_KEY workspacePath=$WATCHER_WORKSPACE_PATH lastVerifiedAt=$LAST_VERIFIED" >> "$EVIDENCE_DIR/runtime-project-evidence.txt"
            fi
        fi
    fi

    if [[ -n "$LAST_INDEXED" && "$LAST_INDEXED" != "null" && "$RUNTIME_PROVEN" -eq 0 && "$WATCHER_STATE_CAN_PROVE_RUNTIME" -eq 1 ]]; then
        if timestamp_at_or_after_marker "$LAST_INDEXED"; then
            if [[ "$WATCHER_WORKSPACE_KEY" == "$WORKSPACE_KEY" || "$WATCHER_WORKSPACE_PATH" == "$REAL_PROJECT_PATH" ]]; then
                RUNTIME_PROVEN=1
                echo "watcher_state indexed: workspaceKey=$WATCHER_WORKSPACE_KEY workspacePath=$WATCHER_WORKSPACE_PATH lastIndexedAt=$LAST_INDEXED" >> "$EVIDENCE_DIR/runtime-project-evidence.txt"
            fi
        fi
    fi

    copy_evidence_snippets "$WATCHER_STATE_FILE" "watcher-state-snippet.json"
fi

PID_VALID=0
if [[ -n "$WATCHER_PID" && "$WATCHER_PID" != "null" && "$WATCHER_PID" != "" ]]; then
    log_cmd "test -d /proc/$WATCHER_PID"
    if [[ -d "/proc/$WATCHER_PID" ]]; then
        PID_OWNER="$(stat -c '%U' "/proc/$WATCHER_PID" 2>/dev/null || true)"
        CURRENT_USER="$(id -un)"
        if [[ "$PID_OWNER" == "$CURRENT_USER" ]]; then
            PID_CMDLINE=""
            if [[ -f "/proc/$WATCHER_PID/cmdline" ]]; then
                PID_CMDLINE="$(tr '\0' ' ' < "/proc/$WATCHER_PID/cmdline" 2>/dev/null || true)"
            fi
            if [[ "$PID_CMDLINE" == *"vera"* && "$PID_CMDLINE" == *"watch"* && "$PID_CMDLINE" == *"$REAL_PROJECT_PATH"* ]]; then
                PID_VALID=1
                echo "$WATCHER_PID" > "$EVIDENCE_DIR/watcher-pid.txt"
            fi
        fi
    fi
fi

if [[ "$LIFECYCLE_EVENT_FOUND" -eq 1 ]]; then
    record_result "lifecycle_event_observed" "passed" \
        "Post-marker runtime log contains lifecycle event with exact project/workspace match"
elif [[ "$RUNTIME_PROVEN" -eq 1 ]]; then
    record_result "lifecycle_event_observed" "skipped" \
        "Runtime proof came from post-marker watcher state with exact project/workspace match; lifecycle log evidence not required"
else
    record_result "lifecycle_event_observed" "failed" \
        "No lifecycle event found in post-marker runtime log for project ($REAL_PROJECT_PATH) or workspace key ($WORKSPACE_KEY). Expected one of: event hook invoked, session.created handled, watcher started pid=, watcher_state verified"
fi

if [[ "$LIFECYCLE_EVENT_FOUND" -eq 1 || "$RUNTIME_PROVEN" -eq 1 ]]; then
    record_result "runtime_project_log" "passed" \
        "Runtime proven by lifecycle event or watcher state with exact project/workspace match"

    if [[ -z "$WATCHER_AUTOMATION_MODE" ]]; then
        WATCHER_AUTOMATION_MODE="$DEFAULT_AUTOMATION_MODE"
    fi

    if [[ "$HIGHEST_STATE" == "active_config_registered" ]]; then
        HIGHEST_STATE="runtime_loaded"
    fi
else
    if [[ -z "$STALE_REASON" ]]; then
        if [[ "$EVIDENCE_FOUND" -eq 1 ]]; then
            STALE_REASON="No lifecycle event or watcher state evidence with exact project path ($REAL_PROJECT_PATH) or workspace key ($WORKSPACE_KEY)"
        else
            STALE_REASON="No runtime log or watcher state found"
        fi
    fi
    record_result "runtime_project_log" "failed" "$STALE_REASON"
    fail_with "runtime_not_proven"
fi

if [[ "$WATCHER_AUTOMATION_MODE" == "autostart" ]]; then
    if [[ "$PID_VALID" -eq 1 ]]; then
        record_result "watcher_pid_owned" "passed" \
            "Watcher PID $WATCHER_PID is alive, owned by current user, and cmdline contains 'vera watch' with project path"
    else
        record_result "watcher_pid_owned" "failed" \
            "Watcher PID is missing, dead, not owned by current user, or cmdline does not contain 'vera watch' with exact project path. Required when automationMode=autostart"
        fail_with "watcher_pid_invalid"
    fi
else
    if [[ "$PID_VALID" -eq 1 ]]; then
        record_result "watcher_pid_owned" "passed" \
            "Watcher PID $WATCHER_PID is alive, owned by current user, and cmdline contains 'vera watch' with project path (manual mode; watcher validation not required)"
    else
        record_result "watcher_pid_owned" "skipped" \
            "Watcher PID validation skipped in manual mode (automationMode=$WATCHER_AUTOMATION_MODE)"
    fi
fi

VERA_OVERVIEW=""
VERA_FILES=0
VERA_CHUNKS=0

if command -v vera >/dev/null 2>&1; then
    log_cmd "vera overview (in $REAL_PROJECT_PATH)"
    if VERA_OVERVIEW="$(cd "$REAL_PROJECT_PATH" && vera overview 2>/dev/null)"; then
        echo "$VERA_OVERVIEW" > "$EVIDENCE_DIR/vera-overview.txt"
        VERA_FILES="$(echo "$VERA_OVERVIEW" | grep -oE 'Files:[[:space:]]*[0-9]+' | grep -oE '[0-9]+' | head -n1 || true)"
        VERA_CHUNKS="$(echo "$VERA_OVERVIEW" | grep -oE 'Chunks:[[:space:]]*[0-9]+' | grep -oE '[0-9]+' | head -n1 || true)"
        VERA_FILES="${VERA_FILES:-0}"
        VERA_CHUNKS="${VERA_CHUNKS:-0}"
    else
        echo "vera overview command failed" > "$EVIDENCE_DIR/vera-overview.txt"
    fi
else
    echo "vera binary not found in PATH" > "$EVIDENCE_DIR/vera-overview.txt"
fi

if [[ -d "$REAL_PROJECT_PATH/.vera" ]]; then
    if [[ "$VERA_FILES" -gt 0 && "$VERA_CHUNKS" -gt 0 ]]; then
        record_result "vera_root_index_nonempty" "passed" \
            "Root .vera index is non-hollow (Files: $VERA_FILES, Chunks: $VERA_CHUNKS)"
    else
        record_result "vera_root_index_nonempty" "failed" \
            "Root .vera index is hollow or missing (Files: ${VERA_FILES:-0}, Chunks: ${VERA_CHUNKS:-0})"
        fail_with "vera_index_hollow"
    fi
else
    record_result "vera_root_index_nonempty" "failed" \
        "Root .vera directory missing: $REAL_PROJECT_PATH/.vera"
    fail_with "vera_index_missing"
fi

NESTED_VERA_FOUND=0
while IFS= read -r -d '' nested_vera; do
    NESTED_VERA_FOUND=1
    break
done < <(find "$REAL_PROJECT_PATH" -mindepth 2 -type d -name '.vera' -print0 2>/dev/null)

if [[ "$NESTED_VERA_FOUND" -eq 1 ]]; then
    record_result "vera_nested_index" "failed" \
        "Nested .vera index found; only root .vera is accepted"
    fail_with "vera_index_nested"
else
    record_result "vera_nested_index" "passed" \
        "No nested .vera indexes found"
fi

SEARCH_HIT=0
if [[ -n "$PROBE_QUERY" ]]; then
    log_cmd "vera search '$PROBE_QUERY' (in $REAL_PROJECT_PATH)"
    if command -v vera >/dev/null 2>&1; then
        SEARCH_OUTPUT="$(cd "$REAL_PROJECT_PATH" && vera search "$PROBE_QUERY" 2>/dev/null || true)"
        echo "$SEARCH_OUTPUT" > "$EVIDENCE_DIR/vera-search.txt"

        if [[ -n "$PROBE_EXPECT" ]]; then
            if echo "$SEARCH_OUTPUT" | grep -qF "$PROBE_EXPECT"; then
                SEARCH_HIT=1
            fi
        else
            if echo "$SEARCH_OUTPUT" | grep -qF "$REAL_PROJECT_PATH"; then
                SEARCH_HIT=1
            elif echo "$SEARCH_OUTPUT" | grep -qE '^```[a-zA-Z0-9_./-]+:'; then
                SEARCH_HIT=1
            fi
        fi
    else
        echo "vera binary not found in PATH" > "$EVIDENCE_DIR/vera-search.txt"
    fi

    if [[ "$SEARCH_HIT" -eq 1 ]]; then
        record_result "vera_project_search" "passed" \
            "Search probe '$PROBE_QUERY' returned result under project root"
        HIGHEST_STATE="real_project_behavior_proven"
    else
        record_result "vera_project_search" "failed" \
            "Search probe '$PROBE_QUERY' did not return expected result"
        fail_with "vera_search_probe_failed"
    fi
else
    record_result "vera_project_search" "skipped" \
        "No --probe-query provided; highest_state capped at runtime_loaded"
    echo "No --probe-query provided" > "$EVIDENCE_DIR/vera-search.txt"
fi

write_summary

echo "All checks passed for component '$COMPONENT'."
echo "Highest state earned: $HIGHEST_STATE"
echo "Evidence written to: $EVIDENCE_DIR"
exit 0
