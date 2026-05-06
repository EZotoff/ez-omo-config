#!/usr/bin/env bash

# Contract harness for verify-live-deployment runtime evidence.
#
# Evidence-state predicates (contract for later verifier/runtime hardening):
# - live_file_installed:
#   * $HOME/.config/opencode/opencode.json exists and resolves to
#     /home/ezotoff/ez-omo-config/configs/opencode/opencode.json
#   * $HOME/.opencode/plugin/vera-runtime.ts exists and matches repo plugin
#     (symlink/SHA contract)
#
# - active_config_registered:
#   * HOME plugin autoload path exists (~/.opencode/plugin/vera-runtime.ts)
#   * active config JSON key is "plugin" (singular) and syntactically valid
#   * no explicit "vera-runtime.ts" plugin array entry required
#
# - runtime_loaded:
#   * exact real project path + workspace key appear in post-marker runtime
#     evidence (log/state)
#   * watcher state status is "running"
#   * watcher PID is alive, owned by current user, and command line contains
#     "vera watch" and exact project root
#
# - real_project_behavior_proven:
#   * runtime_loaded is satisfied
#   * root project .vera is non-hollow (Files > 0 and Chunks > 0)
#   * vera search returns at least one result anchored under project root
#
# This wave intentionally keeps default execution non-failing:
# - default mode: print scenario commands and exit 0
# - --self-test-fixtures: validate fixture generation + fake vera behavior
# - --run-scenario NAME: execute current verifier against one fixture scenario

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERIFY_SCRIPT="$REPO_ROOT/scripts/verify-live-deployment.sh"

source "$SCRIPT_DIR/helpers.sh"

CANONICAL_CONFIG_TARGET="$REPO_ROOT/configs/opencode/opencode.json"

RUN_MODE="list"
RUN_SCENARIO=""

ORIGINAL_PATH="$PATH"
FIXTURES_ROOT=""
FAKE_BIN_DIR=""

declare -a TMP_DIRS=()
declare -a STARTED_PIDS=()
declare -A SCENARIO_ENVS=()

cleanup() {
    local pid
    for pid in "${STARTED_PIDS[@]:-}"; do
        if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
            kill "$pid" >/dev/null 2>&1 || true
        fi
    done

    local dir
    for dir in "${TMP_DIRS[@]:-}"; do
        if [[ -n "$dir" && -d "$dir" ]]; then
            rm -rf "$dir"
        fi
    done
}

trap cleanup EXIT

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="$3"

    if [[ "$expected" != "$actual" ]]; then
        echo "FAIL: $message (expected='$expected' actual='$actual')"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi

    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
}

assert_command_succeeds() {
    local description="$1"
    shift

    if "$@" >/dev/null 2>&1; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    fi

    echo "FAIL: Command expected to succeed: $description"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
}

compute_workspace_key() {
    local project_root="$1"
    local real_project
    local base
    local hash

    real_project="$(cd "$project_root" && pwd -P)"
    base="$(basename "$real_project")"
    hash="$(printf '%s' "$real_project" | sha1sum | awk '{print $1}' | cut -c1-8)"
    printf '%s-%s' "$base" "$hash"
}

create_fake_vera() {
    local bin_dir="$1"
    local fake_vera="$bin_dir/vera"

    mkdir -p "$bin_dir"

    cat > "$fake_vera" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

subcommand="${1:-}"
if [[ $# -gt 0 ]]; then
    shift
fi

case "$subcommand" in
    overview)
        if [[ -n "${VERA_FAKE_OVERVIEW_FILE:-}" && -f "${VERA_FAKE_OVERVIEW_FILE}" ]]; then
            cat "${VERA_FAKE_OVERVIEW_FILE}"
        elif [[ -n "${VERA_FAKE_OVERVIEW_TEXT:-}" ]]; then
            printf '%b\n' "${VERA_FAKE_OVERVIEW_TEXT}"
        else
            cat <<'OUT'
Vera Index Overview
Files: 0
Chunks: 0
OUT
        fi
        ;;

    search)
        if [[ -n "${VERA_FAKE_SEARCH_FILE:-}" && -f "${VERA_FAKE_SEARCH_FILE}" ]]; then
            cat "${VERA_FAKE_SEARCH_FILE}"
        elif [[ -n "${VERA_FAKE_SEARCH_OUTPUT:-}" ]]; then
            printf '%s\n' "${VERA_FAKE_SEARCH_OUTPUT}"
        fi

        if [[ -n "${VERA_FAKE_SEARCH_EXIT_CODE:-}" ]]; then
            exit "${VERA_FAKE_SEARCH_EXIT_CODE}"
        fi
        ;;

    index|watch)
        printf 'fake vera %s ok\n' "$subcommand"
        ;;

    *)
        echo "fake vera: unsupported subcommand '$subcommand'" >&2
        exit 2
        ;;
esac
EOF

    chmod +x "$fake_vera"
}

start_fake_watcher_pid() {
    local project_root="$1"
    local pid

    bash -c "exec -a 'vera watch $project_root' sleep 900" >/dev/null 2>&1 &
    pid=$!
    STARTED_PIDS+=("$pid")
    printf '%s' "$pid"
}

create_fixture_common() {
    local fixtures_root="$1"
    local scenario_slug="$2"

    local fixture_dir="$fixtures_root/$scenario_slug"
    local project_dir="$fixture_dir/project-$scenario_slug"
    local home_dir="$fixture_dir/home"
    local project_id
    local workspace_key
    local watcher_dir
    local watcher_state_file
    local watcher_log_file
    local runtime_log_file
    local evidence_dir
    local fake_vera_data_dir

    mkdir -p "$fixture_dir"
    git init -q "$project_dir"

    mkdir -p "$home_dir/.config/opencode"
    mkdir -p "$home_dir/.opencode/plugin"

    ln -s "$CANONICAL_CONFIG_TARGET" "$home_dir/.config/opencode/opencode.json"
    ln -s "$REPO_ROOT/plugins/vera-runtime.ts" "$home_dir/.opencode/plugin/vera-runtime.ts"

    project_id="$(basename "$project_dir")"
    workspace_key="$(compute_workspace_key "$project_dir")"

    watcher_dir="$home_dir/.local/share/opencode/worktree-state/$project_id/vera-watchers"
    mkdir -p "$watcher_dir"

    watcher_state_file="$watcher_dir/${workspace_key}.json"
    watcher_log_file="$watcher_dir/${workspace_key}.log"
    runtime_log_file="$home_dir/.opencode/plugin/vera-runtime.log"

    evidence_dir="$fixture_dir/evidence"
    mkdir -p "$evidence_dir"

    fake_vera_data_dir="$fixture_dir/fake-vera"
    mkdir -p "$fake_vera_data_dir"

    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
        "$fixture_dir" \
        "$project_dir" \
        "$home_dir" \
        "$project_id" \
        "$workspace_key" \
        "$watcher_state_file" \
        "$watcher_log_file" \
        "$runtime_log_file" \
        "$evidence_dir" \
        "$fake_vera_data_dir" \
        "$watcher_dir"
}

write_scenario_env() {
    local env_file="$1"
    local scenario_name="$2"
    local fixture_dir="$3"
    local project_dir="$4"
    local home_dir="$5"
    local project_id="$6"
    local workspace_key="$7"
    local watcher_state_file="$8"
    local watcher_log_file="$9"
    local runtime_log_file="${10}"
    local evidence_dir="${11}"
    local overview_file="${12}"
    local search_file="${13}"
    local expected_outcome="${14}"
    local watcher_pid="${15:-}"

    cat > "$env_file" <<EOF
SCENARIO_NAME="$scenario_name"
FIXTURE_DIR="$fixture_dir"
PROJECT_DIR="$project_dir"
HOME_DIR="$home_dir"
PROJECT_ID="$project_id"
WORKSPACE_KEY="$workspace_key"
WATCHER_STATE_FILE="$watcher_state_file"
WATCHER_LOG_FILE="$watcher_log_file"
RUNTIME_LOG_FILE="$runtime_log_file"
EVIDENCE_DIR="$evidence_dir"
VERA_FAKE_OVERVIEW_FILE="$overview_file"
VERA_FAKE_SEARCH_FILE="$search_file"
EXPECTED_OUTCOME="$expected_outcome"
WATCHER_PID="$watcher_pid"
EOF
}

scenario_hollow_root_generic_log() {
    local fixtures_root="$1"
    local values
    local env_file
    local overview_file
    local search_file

    local fixture_dir
    local project_dir
    local home_dir
    local project_id
    local workspace_key
    local watcher_state_file
    local watcher_log_file
    local runtime_log_file
    local evidence_dir
    local fake_vera_data_dir
    local watcher_dir

    values="$(create_fixture_common "$fixtures_root" "hollow_root_generic_log")"
    IFS='|' read -r fixture_dir project_dir home_dir project_id workspace_key watcher_state_file watcher_log_file runtime_log_file evidence_dir fake_vera_data_dir watcher_dir <<< "$values"

    mkdir -p "$project_dir/.vera"

    overview_file="$fake_vera_data_dir/overview.txt"
    search_file="$fake_vera_data_dir/search.txt"

    cat > "$overview_file" <<'EOF'
Vera Index Overview
Files: 0
Chunks: 0
EOF

    cat > "$search_file" <<'EOF'
/tmp/unrelated-project/file.ts:1:const unrelated = true;
EOF

    cat > "$runtime_log_file" <<'EOF'
[2999-01-01T00:00:00Z] heartbeat workspace=wrong-workspace root=/tmp/not-this-project
EOF

    cat > "$watcher_state_file" <<'EOF'
{
  "status": "running",
  "pid": 999999,
  "workspaceKey": "wrong-workspace",
  "projectRoot": "/tmp/not-this-project",
  "lastVerifiedAt": "2999-01-01T00:00:00Z",
  "lastIndexedAt": "2999-01-01T00:00:00Z"
}
EOF

    cat > "$watcher_log_file" <<'EOF'
[2999-01-01T00:00:00Z] generic watcher heartbeat
EOF

    env_file="$fixture_dir/scenario.env"
    write_scenario_env \
        "$env_file" \
        "hollow_root_generic_log" \
        "$fixture_dir" \
        "$project_dir" \
        "$home_dir" \
        "$project_id" \
        "$workspace_key" \
        "$watcher_state_file" \
        "$watcher_log_file" \
        "$runtime_log_file" \
        "$evidence_dir" \
        "$overview_file" \
        "$search_file" \
        "Should fail once strict runtime_loaded and non-hollow root .vera checks are enforced"

    printf '%s' "$env_file"
}

scenario_nested_src_populated_root_hollow() {
    local fixtures_root="$1"
    local values
    local env_file
    local overview_file
    local search_file
    local watcher_pid

    local fixture_dir
    local project_dir
    local home_dir
    local project_id
    local workspace_key
    local watcher_state_file
    local watcher_log_file
    local runtime_log_file
    local evidence_dir
    local fake_vera_data_dir
    local watcher_dir

    values="$(create_fixture_common "$fixtures_root" "nested_src_populated_root_hollow")"
    IFS='|' read -r fixture_dir project_dir home_dir project_id workspace_key watcher_state_file watcher_log_file runtime_log_file evidence_dir fake_vera_data_dir watcher_dir <<< "$values"

    mkdir -p "$project_dir/.vera"
    mkdir -p "$project_dir/src/.vera"
    mkdir -p "$project_dir/src"

    cat > "$project_dir/src/.vera/overview.txt" <<'EOF'
Vera Index Overview
Files: 12
Chunks: 42
EOF

    overview_file="$fake_vera_data_dir/overview.txt"
    search_file="$fake_vera_data_dir/search.txt"

    cat > "$overview_file" <<'EOF'
Vera Index Overview
Files: 0
Chunks: 0
EOF

    cat > "$search_file" <<EOF
$project_dir/src/index.ts:1:export const nested = true;
EOF

    watcher_pid="$(start_fake_watcher_pid "$project_dir")"

    cat > "$runtime_log_file" <<EOF
[2999-01-01T00:00:00Z] runtime_loaded workspace=$workspace_key root=$project_dir action=watch
EOF

    cat > "$watcher_state_file" <<EOF
{
  "status": "running",
  "pid": $watcher_pid,
  "workspaceKey": "$workspace_key",
  "projectRoot": "$project_dir",
  "lastVerifiedAt": "2999-01-01T00:00:00Z",
  "lastIndexedAt": "2999-01-01T00:00:00Z"
}
EOF

    cat > "$watcher_log_file" <<EOF
[2999-01-01T00:00:00Z] watcher running workspace=$workspace_key root=$project_dir
EOF

    env_file="$fixture_dir/scenario.env"
    write_scenario_env \
        "$env_file" \
        "nested_src_populated_root_hollow" \
        "$fixture_dir" \
        "$project_dir" \
        "$home_dir" \
        "$project_id" \
        "$workspace_key" \
        "$watcher_state_file" \
        "$watcher_log_file" \
        "$runtime_log_file" \
        "$evidence_dir" \
        "$overview_file" \
        "$search_file" \
        "Should fail once verifier requires non-hollow root .vera despite populated nested src/.vera" \
        "$watcher_pid"

    printf '%s' "$env_file"
}

scenario_root_index_runtime_exact_search_hit() {
    local fixtures_root="$1"
    local values
    local env_file
    local overview_file
    local search_file
    local watcher_pid

    local fixture_dir
    local project_dir
    local home_dir
    local project_id
    local workspace_key
    local watcher_state_file
    local watcher_log_file
    local runtime_log_file
    local evidence_dir
    local fake_vera_data_dir
    local watcher_dir

    values="$(create_fixture_common "$fixtures_root" "root_index_runtime_exact_search_hit")"
    IFS='|' read -r fixture_dir project_dir home_dir project_id workspace_key watcher_state_file watcher_log_file runtime_log_file evidence_dir fake_vera_data_dir watcher_dir <<< "$values"

    mkdir -p "$project_dir/.vera"
    mkdir -p "$project_dir/src"

    cat > "$project_dir/.vera/index.sqlite" <<'EOF'
not-a-real-index-but-non-empty-for-fixture-contract
EOF

    overview_file="$fake_vera_data_dir/overview.txt"
    search_file="$fake_vera_data_dir/search.txt"

    cat > "$overview_file" <<'EOF'
Vera Index Overview
Files: 7
Chunks: 19
EOF

    cat > "$search_file" <<EOF
$project_dir/src/main.ts:1:export const live = 'verified';
EOF

    watcher_pid="$(start_fake_watcher_pid "$project_dir")"

    cat > "$runtime_log_file" <<EOF
[2999-01-01T00:00:00Z] runtime_loaded workspace=$workspace_key root=$project_dir action=watch
EOF

    cat > "$watcher_state_file" <<EOF
{
  "status": "running",
  "pid": $watcher_pid,
  "workspaceKey": "$workspace_key",
  "projectRoot": "$project_dir",
  "lastVerifiedAt": "2999-01-01T00:00:00Z",
  "lastIndexedAt": "2999-01-01T00:00:00Z"
}
EOF

    cat > "$watcher_log_file" <<EOF
[2999-01-01T00:00:00Z] watcher running workspace=$workspace_key root=$project_dir
EOF

    env_file="$fixture_dir/scenario.env"
    write_scenario_env \
        "$env_file" \
        "root_index_runtime_exact_search_hit" \
        "$fixture_dir" \
        "$project_dir" \
        "$home_dir" \
        "$project_id" \
        "$workspace_key" \
        "$watcher_state_file" \
        "$watcher_log_file" \
        "$runtime_log_file" \
        "$evidence_dir" \
        "$overview_file" \
        "$search_file" \
        "Should pass once strict runtime_loaded + real_project_behavior_proven logic is implemented" \
        "$watcher_pid"

    printf '%s' "$env_file"
}

build_all_fixtures() {
    FIXTURES_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/verify-live-fixtures.XXXXXX")"
    TMP_DIRS+=("$FIXTURES_ROOT")

    FAKE_BIN_DIR="$FIXTURES_ROOT/fake-bin"
    create_fake_vera "$FAKE_BIN_DIR"

    SCENARIO_ENVS["hollow_root_generic_log"]="$(scenario_hollow_root_generic_log "$FIXTURES_ROOT")"
    SCENARIO_ENVS["nested_src_populated_root_hollow"]="$(scenario_nested_src_populated_root_hollow "$FIXTURES_ROOT")"
    SCENARIO_ENVS["root_index_runtime_exact_search_hit"]="$(scenario_root_index_runtime_exact_search_hit "$FIXTURES_ROOT")"
}

validate_active_config_plugin_key() {
    local active_config="$1"

    if python3 -c "
import json
with open('$active_config', 'r', encoding='utf-8') as fh:
    data = json.load(fh)
plugin = data.get('plugin', [])
if not isinstance(plugin, list):
    raise SystemExit(1)
print('ok')
" >/dev/null 2>&1; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    fi

    echo "FAIL: active config does not expose valid 'plugin' list key: $active_config"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
}

self_test_single_fixture() {
    local scenario_name="$1"
    local env_file="${SCENARIO_ENVS[$scenario_name]}"
    local overview_out
    local search_out
    local config_target
    local plugin_target
    local pid_owner
    local pid_cmd

    # shellcheck disable=SC1090
    source "$env_file"

    echo "--- Self-test fixture: $SCENARIO_NAME ---"

    assert_dir_exists "$FIXTURE_DIR"
    assert_dir_exists "$PROJECT_DIR"
    assert_dir_exists "$HOME_DIR"
    assert_file_exists "$HOME_DIR/.config/opencode/opencode.json"
    assert_file_exists "$HOME_DIR/.opencode/plugin/vera-runtime.ts"
    assert_file_exists "$WATCHER_STATE_FILE"
    assert_file_exists "$RUNTIME_LOG_FILE"
    assert_file_exists "$VERA_FAKE_OVERVIEW_FILE"
    assert_file_exists "$VERA_FAKE_SEARCH_FILE"

    config_target="$(readlink -f "$HOME_DIR/.config/opencode/opencode.json")"
    assert_equals "$CANONICAL_CONFIG_TARGET" "$config_target" "Config symlink target must match canonical repo config"

    plugin_target="$(readlink -f "$HOME_DIR/.opencode/plugin/vera-runtime.ts")"
    assert_equals "$REPO_ROOT/plugins/vera-runtime.ts" "$plugin_target" "Plugin symlink target must match repo plugin"

    validate_active_config_plugin_key "$HOME_DIR/.config/opencode/opencode.json"

    overview_out="$FIXTURE_DIR/self-test-overview.txt"
    search_out="$FIXTURE_DIR/self-test-search.txt"

    (
        cd "$PROJECT_DIR"
        HOME="$HOME_DIR" \
        PATH="$FAKE_BIN_DIR:$ORIGINAL_PATH" \
        VERA_FAKE_OVERVIEW_FILE="$VERA_FAKE_OVERVIEW_FILE" \
        VERA_FAKE_SEARCH_FILE="$VERA_FAKE_SEARCH_FILE" \
            vera overview > "$overview_out"

        HOME="$HOME_DIR" \
        PATH="$FAKE_BIN_DIR:$ORIGINAL_PATH" \
        VERA_FAKE_OVERVIEW_FILE="$VERA_FAKE_OVERVIEW_FILE" \
        VERA_FAKE_SEARCH_FILE="$VERA_FAKE_SEARCH_FILE" \
            vera search "contract" > "$search_out"

        HOME="$HOME_DIR" PATH="$FAKE_BIN_DIR:$ORIGINAL_PATH" vera index >/dev/null
        HOME="$HOME_DIR" PATH="$FAKE_BIN_DIR:$ORIGINAL_PATH" vera watch >/dev/null
    )
    TESTS_PASSED=$((TESTS_PASSED + 4))

    case "$SCENARIO_NAME" in
        hollow_root_generic_log)
            assert_grep 'Files: 0' "$overview_out"
            assert_grep '/tmp/unrelated-project' "$search_out"
            assert_no_grep "$WORKSPACE_KEY" "$RUNTIME_LOG_FILE"
            assert_no_grep "$PROJECT_DIR" "$RUNTIME_LOG_FILE"
            assert_no_grep "$WORKSPACE_KEY" "$WATCHER_STATE_FILE"
            assert_no_grep "$PROJECT_DIR" "$WATCHER_STATE_FILE"
            assert_grep '"status": "running"' "$WATCHER_STATE_FILE"
            ;;

        nested_src_populated_root_hollow)
            assert_grep 'Files: 0' "$overview_out"
            assert_file_exists "$PROJECT_DIR/src/.vera/overview.txt"

            if [[ -n "$WATCHER_PID" ]] && kill -0 "$WATCHER_PID" >/dev/null 2>&1; then
                TESTS_PASSED=$((TESTS_PASSED + 1))
            else
                echo "FAIL: Nested fixture watcher PID is not alive: $WATCHER_PID"
                TESTS_FAILED=$((TESTS_FAILED + 1))
            fi

            assert_grep "$WORKSPACE_KEY" "$RUNTIME_LOG_FILE"
            assert_grep "$PROJECT_DIR" "$RUNTIME_LOG_FILE"
            assert_grep '"status": "running"' "$WATCHER_STATE_FILE"
            ;;

        root_index_runtime_exact_search_hit)
            assert_grep 'Files: 7' "$overview_out"
            assert_grep "$PROJECT_DIR/src/main.ts" "$search_out"

            if [[ -n "$WATCHER_PID" ]] && kill -0 "$WATCHER_PID" >/dev/null 2>&1; then
                TESTS_PASSED=$((TESTS_PASSED + 1))
            else
                echo "FAIL: Positive fixture watcher PID is not alive: $WATCHER_PID"
                TESTS_FAILED=$((TESTS_FAILED + 1))
            fi

            if [[ -n "$WATCHER_PID" ]]; then
                pid_owner="$(ps -o user= -p "$WATCHER_PID" 2>/dev/null | xargs || true)"
                pid_cmd="$(ps -o args= -p "$WATCHER_PID" 2>/dev/null || true)"

                assert_equals "$(id -un)" "$pid_owner" "Watcher PID must be owned by current user"

                if [[ "$pid_cmd" == *"vera watch"* && "$pid_cmd" == *"$PROJECT_DIR"* ]]; then
                    TESTS_PASSED=$((TESTS_PASSED + 1))
                else
                    echo "FAIL: Watcher command does not contain vera watch + exact project root"
                    TESTS_FAILED=$((TESTS_FAILED + 1))
                fi
            fi

            assert_grep "$WORKSPACE_KEY" "$RUNTIME_LOG_FILE"
            assert_grep "$PROJECT_DIR" "$RUNTIME_LOG_FILE"
            assert_grep '"status": "running"' "$WATCHER_STATE_FILE"
            ;;
    esac
}

run_self_test_fixtures() {
    build_all_fixtures

    assert_file_exists "$FAKE_BIN_DIR/vera"
    assert_command_succeeds "fake vera must be executable" test -x "$FAKE_BIN_DIR/vera"

    self_test_single_fixture "hollow_root_generic_log"
    self_test_single_fixture "nested_src_populated_root_hollow"
    self_test_single_fixture "root_index_runtime_exact_search_hit"

    echo ""
    echo "=========================================="
    echo "Fixtures root: $FIXTURES_ROOT"
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"
    echo "=========================================="

    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi

    exit 0
}

run_scenario() {
    local scenario_name="$1"
    shift
    local extra_args=("$@")
    local env_file
    local exit_code

    build_all_fixtures

    env_file="${SCENARIO_ENVS[$scenario_name]:-}"
    if [[ -z "$env_file" || ! -f "$env_file" ]]; then
        echo "Unknown scenario: $scenario_name" >&2
        echo "Valid scenarios: ${!SCENARIO_ENVS[*]}" >&2
        exit 1
    fi

    # shellcheck disable=SC1090
    source "$env_file"

    echo "Running scenario: $SCENARIO_NAME"
    echo "Expected (future strict verifier): $EXPECTED_OUTCOME"

    set +e
    (
        cd "$REPO_ROOT"
        HOME="$HOME_DIR" \
        PATH="$FAKE_BIN_DIR:$ORIGINAL_PATH" \
        VERA_FAKE_OVERVIEW_FILE="$VERA_FAKE_OVERVIEW_FILE" \
        VERA_FAKE_SEARCH_FILE="$VERA_FAKE_SEARCH_FILE" \
            "$VERIFY_SCRIPT" \
                --component vera-runtime \
                --project "$PROJECT_DIR" \
                --evidence-dir "$EVIDENCE_DIR" \
                "${extra_args[@]}"
    )
    exit_code=$?
    set -e

    echo "Scenario verifier exit code: $exit_code"
    echo "Evidence directory: $EVIDENCE_DIR"
    echo "Summary file: $EVIDENCE_DIR/summary.json"

    exit "$exit_code"
}

run_single_scenario_no_exit() {
    local scenario_name="$1"
    shift
    local extra_args=("$@")
    local env_file
    local exit_code

    env_file="${SCENARIO_ENVS[$scenario_name]:-}"
    if [[ -z "$env_file" || ! -f "$env_file" ]]; then
        echo "Unknown scenario: $scenario_name" >&2
        return 1
    fi

    # shellcheck disable=SC1090
    source "$env_file"

    echo ""
    echo "=== Running scenario: $SCENARIO_NAME ==="
    echo "Expected: $EXPECTED_OUTCOME"

    set +e
    (
        cd "$REPO_ROOT"
        HOME="$HOME_DIR" \
        PATH="$FAKE_BIN_DIR:$ORIGINAL_PATH" \
        VERA_FAKE_OVERVIEW_FILE="$VERA_FAKE_OVERVIEW_FILE" \
        VERA_FAKE_SEARCH_FILE="$VERA_FAKE_SEARCH_FILE" \
            "$VERIFY_SCRIPT" \
                --component vera-runtime \
                --project "$PROJECT_DIR" \
                --evidence-dir "$EVIDENCE_DIR" \
                "${extra_args[@]}"
    )
    exit_code=$?
    set -e

    echo "Scenario verifier exit code: $exit_code"
    return "$exit_code"
}

run_all_scenarios() {
    local failed=0

    build_all_fixtures

    local exit_code

    exit_code=0
    run_single_scenario_no_exit "hollow_root_generic_log" || exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        echo "FAIL: hollow_root_generic_log expected to fail but passed"
        failed=1
    else
        echo "PASS: hollow_root_generic_log failed as expected (exit=$exit_code)"
    fi

    exit_code=0
    run_single_scenario_no_exit "nested_src_populated_root_hollow" || exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        echo "FAIL: nested_src_populated_root_hollow expected to fail but passed"
        failed=1
    else
        echo "PASS: nested_src_populated_root_hollow failed as expected (exit=$exit_code)"
    fi

    exit_code=0
    run_single_scenario_no_exit "root_index_runtime_exact_search_hit" "--probe-query" "live" || exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo "FAIL: root_index_runtime_exact_search_hit expected to pass but failed (exit=$exit_code)"
        failed=1
    else
        echo "PASS: root_index_runtime_exact_search_hit passed as expected"
    fi

    echo ""
    echo "=========================================="
    if [[ $failed -eq 1 ]]; then
        echo "RESULT: FAILED (at least one scenario had unexpected outcome)"
    else
        echo "RESULT: PASSED (all scenarios behaved as expected)"
    fi
    echo "=========================================="

    return "$failed"
}

print_usage() {
    cat <<'EOF'
Usage: bash tests/test_verify_live_deployment.sh [OPTIONS]

Default (no options):
  Run all three scenarios against the strict verifier and assert expected outcomes.

Options:
  --self-test-fixtures                Build fixtures + fake vera and validate scaffold
  --run-scenario <name>               Run scripts/verify-live-deployment.sh against one scenario
  --list-scenarios                    Print named scenarios and example commands
  --help                              Show this help text

Named scenarios:
  hollow_root_generic_log
  nested_src_populated_root_hollow
  root_index_runtime_exact_search_hit
EOF
}

print_scenario_commands() {
    cat <<'EOF'
verify-live-deployment contract harness

Default mode runs all scenarios with strict assertions:
  bash tests/test_verify_live_deployment.sh

Scenario commands for individual debugging:
  bash tests/test_verify_live_deployment.sh --run-scenario hollow_root_generic_log
  bash tests/test_verify_live_deployment.sh --run-scenario nested_src_populated_root_hollow
  bash tests/test_verify_live_deployment.sh --run-scenario root_index_runtime_exact_search_hit

Fixture self-check command:
  bash tests/test_verify_live_deployment.sh --self-test-fixtures
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --self-test-fixtures)
            RUN_MODE="self-test"
            shift
            ;;

        --run-scenario)
            RUN_MODE="run-scenario"
            RUN_SCENARIO="${2:-}"
            shift 2
            ;;

        --list-scenarios)
            RUN_MODE="list"
            shift
            ;;

        --help)
            print_usage
            exit 0
            ;;

        *)
            echo "Unknown option: $1" >&2
            print_usage >&2
            exit 1
            ;;
    esac
done

if [[ "$RUN_MODE" == "self-test" ]]; then
    run_self_test_fixtures
elif [[ "$RUN_MODE" == "run-scenario" ]]; then
    if [[ -z "$RUN_SCENARIO" ]]; then
        echo "--run-scenario requires a scenario name" >&2
        exit 1
    fi
    run_scenario "$RUN_SCENARIO"
else
    run_all_scenarios
fi
