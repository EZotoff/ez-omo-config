#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

COMPONENT=""
PROJECT_PATH=""
EVIDENCE_DIR=""
LIVE_TARGET=""
CONFIG_REFERENCE=""
RUNTIME_EVIDENCE=""

FAILURE_CODE=""
CHECK_RESULTS=()
MARKER_TIMESTAMP=""
HIGHEST_STATE="repo_implemented"

usage() {
    cat <<'EOF'
Usage: verify-live-deployment.sh [OPTIONS]

Required:
  --component <name>       Component to verify
  --project <path>         Absolute path to the project directory
  --evidence-dir <path>    Directory to write evidence files

Optional:
  --live-target <path>       Installed artifact path required for live_file_installed
  --config-reference <text>  Substring expected in active opencode.json for active_config_registered
  --runtime-evidence <path>  Non-empty runtime evidence file required for runtime_loaded
  --help                     Show this help text

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

write_summary() {
    mkdir -p "$EVIDENCE_DIR"
    local checks_json="["
    local first=1
    local result
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

fail_with() {
    local code="$1"
    FAILURE_CODE="$code"
    write_summary
    echo "Verification failed: $code" >&2
    exit 1
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
        --live-target)
            LIVE_TARGET="$2"
            shift 2
            ;;
        --config-reference)
            CONFIG_REFERENCE="$2"
            shift 2
            ;;
        --runtime-evidence)
            RUNTIME_EVIDENCE="$2"
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
MARKER_TIMESTAMP="${OMO_VERIFY_MARKER_TIMESTAMP_OVERRIDE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
record_result "marker_timestamp" "passed" "Marker timestamp recorded: $MARKER_TIMESTAMP"

EXPECTED_CONFIG_TARGET="$REPO_ROOT/configs/opencode/opencode.json"
ACTIVE_CONFIG="$HOME/.config/opencode/opencode.json"
log_cmd "readlink -f \"$ACTIVE_CONFIG\""
ACTUAL_CONFIG_TARGET="$(readlink -f "$ACTIVE_CONFIG" 2>/dev/null || true)"

if [[ "$ACTUAL_CONFIG_TARGET" != "$EXPECTED_CONFIG_TARGET" ]]; then
    record_result "config_symlink" "failed" \
        "Symlink target mismatch: expected '$EXPECTED_CONFIG_TARGET', got '$ACTUAL_CONFIG_TARGET'"
    fail_with "config_symlink_mismatch"
fi
record_result "config_symlink" "passed" "Active config points to $EXPECTED_CONFIG_TARGET"
echo "$ACTIVE_CONFIG" >> "$EVIDENCE_DIR/live-paths.txt"
HIGHEST_STATE="live_file_installed"

log_cmd "test -d \"$PROJECT_PATH\""
if [[ ! -d "$PROJECT_PATH" ]]; then
    record_result "project_exists" "failed" "Project path does not exist: $PROJECT_PATH"
    fail_with "project_missing"
fi
record_result "project_exists" "passed" "Project path exists: $PROJECT_PATH"

log_cmd "git -C \"$PROJECT_PATH\" rev-parse --git-dir"
if ! git -C "$PROJECT_PATH" rev-parse --git-dir >/dev/null 2>&1; then
    record_result "project_is_git_repo" "failed" "Project path is not a git repository: $PROJECT_PATH"
    fail_with "not_git_repo"
fi
record_result "project_is_git_repo" "passed" "Project path is a valid git repository"

log_cmd "python3 parse active opencode config"
if ACTIVE_CONFIG_PATH="$ACTIVE_CONFIG" EVIDENCE_OUTPUT_DIR="$EVIDENCE_DIR" python3 - <<'PY' > "$EVIDENCE_DIR/active-config-extraction.log" 2>&1
import json
import os

with open(os.environ["ACTIVE_CONFIG_PATH"], "r", encoding="utf-8") as fh:
    data = json.load(fh)

plugin = data.get("plugin", [])
if not isinstance(plugin, list):
    raise SystemExit("plugin key is not a list")

with open(os.path.join(os.environ["EVIDENCE_OUTPUT_DIR"], "active-config-plugin-array.json"), "w", encoding="utf-8") as out:
    json.dump(plugin, out, indent=2)
    out.write("\n")

print("ok")
PY
then
    record_result "active_config_parse" "passed" "Active config JSON parsed and plugin array extracted"
else
    record_result "active_config_parse" "failed" "Active config is invalid or plugin key is not a list"
    fail_with "active_config_invalid"
fi

if [[ -n "$LIVE_TARGET" ]]; then
    log_cmd "test -e \"$LIVE_TARGET\""
    if [[ ! -e "$LIVE_TARGET" ]]; then
        record_result "live_target" "failed" "Live target missing: $LIVE_TARGET"
        fail_with "live_target_missing"
    fi
    record_result "live_target" "passed" "Live target exists: $LIVE_TARGET"
    echo "$LIVE_TARGET" >> "$EVIDENCE_DIR/live-paths.txt"
fi

if [[ -n "$CONFIG_REFERENCE" ]]; then
    log_cmd "grep -F config reference \"$ACTIVE_CONFIG\""
    if ! grep -Fq "$CONFIG_REFERENCE" "$ACTIVE_CONFIG"; then
        record_result "active_config_reference" "failed" "Reference not found in active config"
        fail_with "active_config_reference_missing"
    fi
    record_result "active_config_reference" "passed" "Reference found in active config"
    HIGHEST_STATE="active_config_registered"
fi

if [[ -n "$RUNTIME_EVIDENCE" ]]; then
    log_cmd "test -s \"$RUNTIME_EVIDENCE\""
    if [[ ! -s "$RUNTIME_EVIDENCE" ]]; then
        record_result "runtime_evidence" "failed" "Runtime evidence missing or empty: $RUNTIME_EVIDENCE"
        fail_with "runtime_evidence_missing"
    fi
    cp "$RUNTIME_EVIDENCE" "$EVIDENCE_DIR/runtime-evidence.txt"
    record_result "runtime_evidence" "passed" "Runtime evidence is non-empty: $RUNTIME_EVIDENCE"
    HIGHEST_STATE="runtime_loaded"
fi

write_summary

echo "Verification passed: $COMPONENT ($HIGHEST_STATE)"
echo "Evidence written to: $EVIDENCE_DIR"
exit 0
