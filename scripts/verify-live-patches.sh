#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Usage: %s [--json] [--schema-only] [--tree PATH | BINARY_PATH]\n' "${0##*/}" >&2
    exit 2
}

yaml_frontmatter_value() {
    local file="$1"
    local key="$2"
    awk -v wanted="$key" '
        NR == 1 && $0 == "---" { in_frontmatter = 1; next }
        in_frontmatter && $0 == "---" { exit }
        in_frontmatter && index($0, wanted ":") == 1 {
            value = substr($0, length(wanted) + 2)
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            if (value ~ /^".*"$/ || value ~ /^\047.*\047$/) {
                value = substr(value, 2, length(value) - 2)
            }
            print value
            exit
        }
    ' "$file"
}

find_repo_root() {
    local current
    current="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    while [[ "$current" != "/" ]]; do
        if [[ -d "$current/.sisyphus/patches" ]]; then
            printf '%s\n' "$current"
            return 0
        fi
        current="$(dirname "$current")"
    done
    return 1
}

resolve_config_runtime() {
    local dependency="$1"
    local config_path="$2"

    if [[ "$dependency" == "oh-my-openagent" && -n "${OMO_RUNTIME_PATH:-}" ]]; then
        printf '%s\n' "$OMO_RUNTIME_PATH"
        return 0
    fi
    [[ "$dependency" == "oh-my-openagent" && -f "$config_path" ]] || return 1

    VERIFY_CONFIG="$config_path" python3 -c '
import json
import os
import sys
from urllib.parse import unquote, urlparse

with open(os.environ["VERIFY_CONFIG"], encoding="utf-8") as handle:
    plugins = json.load(handle).get("plugin", [])
paths = []
for plugin in plugins:
    if isinstance(plugin, str) and plugin.startswith("file://"):
        paths.append(unquote(urlparse(plugin).path))
preferred = [path for path in paths if "oh-my-openagent" in path]
selected = preferred[0] if preferred else (paths[0] if len(paths) == 1 else "")
if not selected:
    sys.exit(1)
print(selected)
' 2>/dev/null
}

read_runtime_version() {
    local dependency="$1"
    local root="$2"
    local version="unknown"

    if [[ "$dependency" == "opencode" || "$dependency" == "opencode-dcp" ]]; then
        if [[ -x "$root" ]]; then
            version="$("$root" --version 2>/dev/null || true)"
        fi
    elif [[ -f "$root/package.json" ]]; then
        version="$(VERIFY_PACKAGE="$root/package.json" python3 -c '
import json
import os
with open(os.environ["VERIFY_PACKAGE"], encoding="utf-8") as handle:
    print(json.load(handle).get("version", "unknown"))
' 2>/dev/null || true)"
    fi
    printf '%s\n' "${version:-unknown}"
}

versions_match() {
    local expected="$1"
    local actual="$2"
    local minimum

    [[ -z "$expected" || "$expected" == "current" || "$actual" == "unknown" ]] && return 0
    expected="${expected%-local}"
    actual="${actual#v}"
    if [[ "$expected" == '>='* ]]; then
        minimum="${expected#>=}"
        VERIFY_MINIMUM="$minimum" VERIFY_ACTUAL="$actual" python3 -c '
import os
import re
import sys

def parts(value):
    return tuple(int(part) for part in re.findall(r"\d+", value)[:3])

sys.exit(0 if parts(os.environ["VERIFY_ACTUAL"]) >= parts(os.environ["VERIFY_MINIMUM"]) else 1)
' 2>/dev/null
        return
    fi
    [[ "$actual" == "$expected" || "$actual" == "$expected"-* ]]
}

pattern_matches() {
    local pattern="$1"
    shift
    local check_path
    # ALL listed targets must match — a single match is not sufficient.
    # This prevents silent patch loss when a rebuild drops the marker from
    # dist/index.js but the source file still contains it.
    for check_path in "$@"; do
        if ! VERIFY_PATTERN="$pattern" VERIFY_PATH="$check_path" python3 -c '
import os
import re
import sys

pattern = os.environ["VERIFY_PATTERN"]
path = os.environ["VERIFY_PATH"]
with open(path, "rb") as handle:
    data = handle.read()
text = data.decode("utf-8", errors="ignore")
try:
    matched = re.search(pattern, text, re.MULTILINE) is not None
except re.error:
    matched = pattern in text
sys.exit(0 if matched else 1)
'; then
            return 1
        fi
    done
    return 0
}

JSON_OUTPUT=0
MODE="live"
TARGET=""
while (($#)); do
    case "$1" in
        --json)
            JSON_OUTPUT=1
            shift
            ;;
        --schema-only)
            MODE="schema"
            shift
            ;;
        --tree)
            [[ $# -ge 2 && "$MODE" == "live" && -z "$TARGET" ]] || usage
            MODE="tree"
            TARGET="$2"
            shift 2
            ;;
        --help|-h)
            usage
            ;;
        --*)
            usage
            ;;
        *)
            [[ "$MODE" == "live" && -z "$TARGET" ]] || usage
            MODE="binary"
            TARGET="$1"
            shift
            ;;
    esac
done

REPO_ROOT="${EZ_OMO_CONFIG_REPO:-}"
if [[ -z "$REPO_ROOT" ]]; then
    REPO_ROOT="$(find_repo_root || true)"
fi
[[ -n "$REPO_ROOT" ]] || { printf 'Unable to locate repository root\n' >&2; exit 2; }

PATCH_DIR="${PATCH_DIR:-$REPO_ROOT/.sisyphus/patches}"
CONFIG_PATH="${OPENCODE_CONFIG:-$REPO_ROOT/configs/opencode/opencode.json}"
[[ -d "$PATCH_DIR" ]] || { printf 'Patch directory not found: %s\n' "$PATCH_DIR" >&2; exit 2; }

if [[ "$MODE" == "live" ]]; then
    TARGET="${OPENCODE_BINARY:-$HOME/.opencode/bin/opencode}"
fi

total=0
applied=0
stale=0
missing=0
drift=0
schema_fail=0
results_file="$(mktemp)"
trap 'rm -f "$results_file"' EXIT

shopt -s nullglob
entries=("$PATCH_DIR"/*.md)
for entry in "${entries[@]}"; do
    status="$(yaml_frontmatter_value "$entry" status)"
    [[ "$status" != "active" ]] && continue

    patch_id="$(yaml_frontmatter_value "$entry" patch_id)"
    dependency="$(yaml_frontmatter_value "$entry" dependency)"
    target_file="$(yaml_frontmatter_value "$entry" target_file)"
    target_install_path="$(yaml_frontmatter_value "$entry" target_install_path)"
    dep_version="$(yaml_frontmatter_value "$entry" dep_version)"
    verification_pattern="$(yaml_frontmatter_value "$entry" verification_pattern)"
    patch_id="${patch_id:-${entry##*/}}"

    # Schema-only mode: validate entry frontmatter completeness without
    # needing the binary. Catches metadata destruction (e.g., a cutover
    # commit that deletes the surfaces field or collapses target_file
    # to a generic value). Runs for ALL active patches regardless of dependency.
    if [[ "$MODE" == "schema" ]]; then
        total=$((total + 1))
        detail=""
        surfaces_val="$(yaml_frontmatter_value "$entry" surfaces)"
        runtime_eff="$(yaml_frontmatter_value "$entry" runtime_effective)"

        # Rule 1: target_file must be present
        if [[ -z "$target_file" ]]; then
            detail="missing target_file"
        fi

        # Rule 2: rendering-path target_file requires surfaces field
        if [[ -z "$detail" && ( "$target_file" == *"cli/cmd/run/"* || "$target_file" == *"tui/src/routes/"* || "$target_file" == *"server/routes/"* ) ]]; then
            if [[ -z "$surfaces_val" ]]; then
                detail="rendering-path target_file missing required 'surfaces' field"
            fi
        fi

        # Rule 3: patches with surfaces require runtime_effective flag
        if [[ -z "$detail" && -n "$surfaces_val" && -z "$runtime_eff" ]]; then
            detail="patch with 'surfaces' field missing required 'runtime_effective' field"
        fi

        if [[ -n "$detail" ]]; then
            result="SCHEMA-VIOLATION"
            schema_fail=$((schema_fail + 1))
        else
            result="SCHEMA-OK"
        fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$patch_id" "$dependency" "$target_file" "schema" "$result" "$detail" >> "$results_file"
        continue
    fi

    if [[ "$MODE" == "binary" && "$dependency" != "opencode" && "$dependency" != "opencode-dcp" ]]; then
        continue
    fi

    total=$((total + 1))
    runtime_path=""
    runtime_ver="unknown"
    result=""
    display_path=""
    check_paths=()

    if [[ "$MODE" == "binary" || ( "$MODE" == "live" && "$PATCH_DIR" == "$REPO_ROOT/.sisyphus/patches" && ( "$dependency" == "opencode" || "$dependency" == "opencode-dcp" ) ) ]]; then
        runtime_path="$TARGET"
        display_path="$TARGET"
        runtime_ver="$(read_runtime_version "$dependency" "$TARGET")"
        [[ -f "$TARGET" ]] && check_paths+=("$TARGET")
    else
        if [[ "$MODE" == "tree" ]]; then
            runtime_path="$TARGET"
        else
            runtime_path="$(resolve_config_runtime "$dependency" "$CONFIG_PATH" || true)"
            if [[ -z "$runtime_path" ]]; then
                if [[ "$dependency" == "opencode" ]]; then
                    runtime_path="$TARGET"
                else
                    runtime_path="$target_install_path"
                fi
            fi
        fi
        display_path="$runtime_path"
        runtime_ver="$(read_runtime_version "$dependency" "$runtime_path")"

        IFS=',' read -ra target_files <<< "$target_file"
        all_targets_present=1
        for relative_file in "${target_files[@]}"; do
            relative_file="${relative_file#"${relative_file%%[![:space:]]*}"}"
            relative_file="${relative_file%"${relative_file##*[![:space:]]}"}"
            check_path="$runtime_path/$relative_file"
            if [[ ! -f "$check_path" ]]; then
                all_targets_present=0
            else
                check_paths+=("$check_path")
            fi
        done
        if ((all_targets_present == 0)); then
            result="MISSING-TARGET"
        fi
    fi

    if [[ -z "$result" && ${#check_paths[@]} -eq 0 ]]; then
        result="MISSING-TARGET"
    elif [[ -z "$result" ]] && ! versions_match "$dep_version" "$runtime_ver"; then
        result="VERSION-DRIFT"
    elif [[ -z "$result" ]] && pattern_matches "$verification_pattern" "${check_paths[@]}"; then
        result="APPLIED"
    elif [[ -z "$result" ]]; then
        result="STALE"
    fi

    case "$result" in
        APPLIED) applied=$((applied + 1)) ;;
        STALE) stale=$((stale + 1)) ;;
        MISSING-TARGET) missing=$((missing + 1)) ;;
        VERSION-DRIFT) drift=$((drift + 1)) ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$patch_id" "$dependency" "$target_file" "$runtime_ver" "$result" "$display_path" >> "$results_file"
done

if ((JSON_OUTPUT)); then
    VERIFY_RESULTS="$results_file" VERIFY_TOTAL="$total" VERIFY_APPLIED="$applied" VERIFY_STALE="$stale" VERIFY_MISSING="$missing" VERIFY_DRIFT="$drift" VERIFY_SCHEMA_FAIL="$schema_fail" python3 -c '
import csv
import json
import os

rows = []
with open(os.environ["VERIFY_RESULTS"], encoding="utf-8", newline="") as handle:
    for patch_id, dependency, target, runtime, status, path in csv.reader(handle, delimiter="\t"):
        rows.append({"patch_id": patch_id, "dependency": dependency, "target": target,
                     "runtime": runtime, "status": status, "path": path})
summary = {"total": int(os.environ["VERIFY_TOTAL"]), "applied": int(os.environ["VERIFY_APPLIED"]),
           "stale": int(os.environ["VERIFY_STALE"]), "missing_target": int(os.environ["VERIFY_MISSING"]),
           "version_drift": int(os.environ["VERIFY_DRIFT"]), "schema_fail": int(os.environ["VERIFY_SCHEMA_FAIL"])}
           "stale": int(os.environ["VERIFY_STALE"]), "missing_target": int(os.environ["VERIFY_MISSING"]),
           "version_drift": int(os.environ["VERIFY_DRIFT"])}
print(json.dumps({"patches": rows, "summary": summary}, sort_keys=True))
'
else
    printf '%-52s %-17s %-28s %-10s %-15s %s\n' PATCH_ID DEP TARGET RUNTIME STATUS PATH
    printf '%150s\n' '' | tr ' ' '-'
    while IFS=$'\t' read -r patch_id dependency target_file runtime_ver result display_path; do
        printf '%s %-52s %-17s %-28s %-10s %s\n' "$result" "$patch_id" "$dependency" "$target_file" "$runtime_ver" "$display_path"
    done < "$results_file"
    printf 'Summary: %d total | %d applied | %d stale | %d missing-target | %d version-drift | %d schema-violation\n' "$total" "$applied" "$stale" "$missing" "$drift" "$schema_fail"
fi

if ((stale > 0 || missing > 0 || drift > 0 || schema_fail > 0)); then
    exit 1
fi
exit 0
