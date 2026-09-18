#!/usr/bin/env bash
set -euo pipefail

# Verdict model (patch-provenance plan, Task 5):
#   - opencode-- entries (dependency "opencode", live/binary modes) get
#     evidence-typed states when their verification_pattern matches:
#       PROVENANCE-VERIFIED  build receipt for the live binary sha256 exists,
#                            receipt generation == lockfile generation, and
#                            every required lockfile implementation_commit is
#                            an ancestor of the receipt's source_head
#                            (computed ONCE per run, not per patch).
#       RUNTIME-VERIFIED     PROVENANCE-VERIFIED plus a passing smoke entry
#                            for this binary sha in $SMOKE_RESULTS_DIR/<sha>.json
#                            for patches with required_evidence: runtime.
#                            Smoke ids are the patch_id minus the "opencode--"
#                            prefix (contract with tests/smoke/, Task 6); a smoke
#                            id that is a hyphen-prefix of the patch suffix
#                            also matches (e.g. "bash-lifecycle" covers
#                            "bash-lifecycle-group-cleanup").
#       WEAK-MARKER          pattern matched but provenance is unavailable —
#                            NEVER counts toward a green summary.
#   - WEAK-MARKER for a lockfile-required patch means provenance is unsatisfied
#     → exit 1. Missing (pending) runtime smoke is amber, not red: exit 0.
#   - OMO and opencode-dcp entries keep their grep-based APPLIED verdicts; the
#     summary output distinguishes the two sections.
#   - --schema-only and --tree modes are unchanged in behavior.

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

config_file = os.path.abspath(os.environ["VERIFY_CONFIG"])
config_dir = os.path.dirname(config_file)
# Relative specs resolve the way opencode loads them: against the directory of the
# config file AS OPENCODE SEES IT. When verifying the repo-side copy of a config that
# is symlinked live at ~/.config/opencode/, that base is ~/.config/opencode.
live_candidate = os.path.join(os.path.expanduser("~/.config/opencode"), os.path.basename(config_file))
if os.path.realpath(live_candidate) == os.path.realpath(config_file):
    config_dir = os.path.dirname(live_candidate)
with open(os.environ["VERIFY_CONFIG"], encoding="utf-8") as handle:
    plugins = json.load(handle).get("plugin", [])
paths = []
for plugin in plugins:
    if not isinstance(plugin, str):
        continue
    if plugin.startswith("file://"):
        paths.append(unquote(urlparse(plugin).path))
    elif plugin.startswith("."):
        # config-relative spec: resolve like opencode config/plugin.ts (against the config file dir)
        paths.append(os.path.normpath(os.path.join(config_dir, plugin)))
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

# Provenance inputs (patch-provenance plan): build receipts via lib-patchset.sh,
# lockfile generation, smoke-result store. All degrade silently when absent.
LIB_PATCHSET="$REPO_ROOT/scripts/lib-patchset.sh"
if [[ -f "$LIB_PATCHSET" ]]; then
    # shellcheck disable=SC1090
    source "$LIB_PATCHSET"
else
    RECEIPT_DIR="${RECEIPT_DIR:-$HOME/.local/share/opencode/builds}"
    OPENCODE_SRC="${OPENCODE_SRC:-$HOME/src/opencode}"
fi
SMOKE_RESULTS_DIR="${SMOKE_RESULTS_DIR:-$HOME/.local/share/opencode/smoke-results}"
PATCH_LOCKFILE="${PATCH_LOCKFILE:-$REPO_ROOT/config/patch-lockfile.json}"

receipt_field() {
    # receipt_field <binary_sha256> <key> — receipt value or "" (never fails)
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2],""))' \
        "$RECEIPT_DIR/$1.json" "$2" 2>/dev/null || true
}

if [[ "$MODE" == "live" ]]; then
    TARGET="${OPENCODE_BINARY:-$HOME/.opencode/bin/opencode}"
fi

# ---- Lockfile required-patch map (used by both schema and live modes) ----
LOCK_GEN=""
declare -A LOCK_REQUIRED=()
if [[ -f "$PATCH_LOCKFILE" ]]; then
    LOCK_GEN="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("generation",""))' "$PATCH_LOCKFILE" 2>/dev/null || true)"
    while IFS=$'\t' read -r lock_pid lock_commits; do
        [[ -n "$lock_pid" ]] || continue
        LOCK_REQUIRED["$lock_pid"]="$lock_commits"
    done < <(python3 -c '
import json, sys
for patch in json.load(open(sys.argv[1])).get("patches", []):
    if patch.get("required"):
        print(patch["patch_id"], *patch.get("implementation_commits", []), sep="\t")
' "$PATCH_LOCKFILE" 2>/dev/null || true)
fi

# ---- Provenance state: computed ONCE per run for live/binary modes ----
PROV_MODE=0
[[ "$MODE" == "live" || "$MODE" == "binary" ]] && PROV_MODE=1
PROV_STATE="unavailable"
PROV_DETAIL=""
PROV_BIN_SHA=""
declare -A SMOKE_PASS=()
declare -A SMOKE_FAIL=()

if (( PROV_MODE )); then
    if [[ ! -f "$TARGET" ]]; then
        PROV_STATE="no-binary"
        PROV_DETAIL="binary not found: $TARGET"
    elif [[ ! -f "$PATCH_LOCKFILE" ]]; then
        PROV_STATE="no-lockfile"
        PROV_DETAIL="lockfile missing: $PATCH_LOCKFILE"
    else
        PROV_BIN_SHA="$(sha256sum "$TARGET" | awk '{print $1}')"
        if [[ ! -f "$RECEIPT_DIR/$PROV_BIN_SHA.json" ]]; then
            PROV_STATE="no-receipt"
            PROV_DETAIL="no build receipt for binary sha256 $PROV_BIN_SHA in $RECEIPT_DIR"
        else
            receipt_gen="$(receipt_field "$PROV_BIN_SHA" generation)"
            if [[ "$receipt_gen" != "$LOCK_GEN" ]]; then
                PROV_STATE="generation-mismatch"
                PROV_DETAIL="receipt generation '$receipt_gen' != lockfile generation '$LOCK_GEN'"
            else
                source_head_rt="$(receipt_field "$PROV_BIN_SHA" source_head)"
                if [[ -z "$source_head_rt" ]]; then
                    PROV_STATE="bad-receipt"
                    PROV_DETAIL="receipt missing source_head"
                elif [[ ! -d "$OPENCODE_SRC/.git" ]]; then
                    PROV_STATE="no-source-repo"
                    PROV_DETAIL="source repo unavailable: $OPENCODE_SRC"
                else
                    ancestry_fails=""
                    for lock_pid in "${!LOCK_REQUIRED[@]}"; do
                        for commit_sha in ${LOCK_REQUIRED["$lock_pid"]}; do
                            if ! git -C "$OPENCODE_SRC" merge-base --is-ancestor "$commit_sha" "$source_head_rt" >/dev/null 2>&1; then
                                ancestry_fails+="${ancestry_fails:+ }$lock_pid"
                                break
                            fi
                        done
                    done
                    if [[ -n "$ancestry_fails" ]]; then
                        PROV_STATE="ancestry-fail"
                        PROV_DETAIL="implementation commits not ancestors of receipt source_head: $ancestry_fails"
                    else
                        PROV_STATE="verified"
                        PROV_DETAIL="receipt generation $LOCK_GEN, source_head ${source_head_rt:0:12}"
                    fi
                fi
            fi
        fi
    fi
    # Smoke results for this binary sha (Task 6 contract: JSON array of
    # {"smoke"|"id": <smoke-id>, "result": "PASS"|"FAIL"|"SKIP", ...})
    if [[ -n "$PROV_BIN_SHA" && -f "$SMOKE_RESULTS_DIR/$PROV_BIN_SHA.json" ]]; then
        while IFS=$'\t' read -r smoke_id smoke_result; do
            [[ -n "$smoke_id" ]] || continue
            if [[ "$smoke_result" == "PASS" ]]; then
                SMOKE_PASS["$smoke_id"]=1
            else
                SMOKE_FAIL["$smoke_id"]=1
            fi
        done < <(python3 -c '
import json, sys
try:
    entries = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
if not isinstance(entries, list):
    sys.exit(0)
for entry in entries:
    if not isinstance(entry, dict):
        continue
    smoke_id = entry.get("smoke") or entry.get("id") or ""
    result = entry.get("result", "")
    if smoke_id and result:
        print(smoke_id, result, sep="\t")
' "$SMOKE_RESULTS_DIR/$PROV_BIN_SHA.json" 2>/dev/null || true)
    fi
fi

total=0
applied=0
stale=0
missing=0
drift=0
schema_fail=0
acknowledged=0
prov_verified=0
runtime_verified=0
weak=0
runtime_pending=0
runtime_failed=0
prov_unsatisfied=0
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

        # Rule 4 (patch-provenance plan T5): active opencode-- entries that the
        # lockfile marks required must declare evidence-typed verification
        # fields. Acknowledged-drift entries (lockfile required:false) exempt.
        if [[ -z "$detail" && "$dependency" == "opencode" && "$patch_id" == opencode--* && -n "${LOCK_REQUIRED[$patch_id]:-}" ]]; then
            strength_val="$(yaml_frontmatter_value "$entry" verification_strength)"
            evidence_val="$(yaml_frontmatter_value "$entry" required_evidence)"
            if [[ "$strength_val" != "weak" && "$strength_val" != "discriminative" ]]; then
                detail="verification_strength must be 'weak' or 'discriminative'"
            elif [[ "$evidence_val" != "provenance" && "$evidence_val" != "runtime" ]]; then
                detail="required_evidence must be 'provenance' or 'runtime'"
            fi
        fi

        if [[ -n "$detail" ]]; then
            result="SCHEMA-VIOLATION"
            schema_fail=$((schema_fail + 1))
        else
            result="SCHEMA-OK"
        fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$patch_id" "$dependency" "$target_file" "schema" "$result" "" "$detail" >> "$results_file"
        continue
    fi

    if [[ "$MODE" == "binary" && "$dependency" != "opencode" && "$dependency" != "opencode-dcp" ]]; then
        continue
    fi

    total=$((total + 1))
    runtime_path=""
    runtime_ver="unknown"
    result=""
    detail=""
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
        if ((all_targets_present == 0)) && [[ -n "$target_install_path" && "$target_install_path" != "$runtime_path" ]]; then
            # Config-layer patches target files in this repo (target_install_path),
            # not inside the dependency tree resolved from the plugin array.
            alt_present=1
            alt_paths=()
            for relative_file in "${target_files[@]}"; do
                relative_file="${relative_file#"${relative_file%%[![:space:]]*}"}"
                relative_file="${relative_file%"${relative_file##*[![:space:]]}"}"
                if [[ -f "$target_install_path/$relative_file" ]]; then
                    alt_paths+=("$target_install_path/$relative_file")
                else
                    alt_present=0
                fi
            done
            if ((alt_present == 1)); then
                runtime_path="$target_install_path"
                display_path="$runtime_path"
                check_paths=("${alt_paths[@]}")
                all_targets_present=1
            fi
        fi
        if ((all_targets_present == 0)); then
            result="MISSING-TARGET"
        fi
    fi

    if [[ -z "$result" && ${#check_paths[@]} -eq 0 ]]; then
        result="MISSING-TARGET"
    elif [[ -z "$result" ]] && ! versions_match "$dep_version" "$runtime_ver"; then
        runtime_eff_check="$(yaml_frontmatter_value "$entry" runtime_effective)"
        if [[ "$runtime_eff_check" == "false" ]]; then
            result="ACKNOWLEDGED-DRIFT"
        else
            result="VERSION-DRIFT"
        fi
    elif [[ -z "$result" ]] && pattern_matches "$verification_pattern" "${check_paths[@]}"; then
        result="APPLIED"
        # Evidence-typed verdicts for opencode binary patches (live/binary modes).
        # A matched pattern alone proves nothing for weak markers; authority is
        # the build receipt + lockfile ancestry (or a runtime smoke).
        if (( PROV_MODE )) && [[ "$dependency" == "opencode" && "$patch_id" == opencode--* ]]; then
            required_ev="$(yaml_frontmatter_value "$entry" required_evidence)"
            if [[ "$PROV_STATE" == "verified" && -n "${LOCK_REQUIRED[$patch_id]:-}" ]]; then
                if [[ "$required_ev" == "runtime" ]]; then
                    smoke_id="${patch_id#opencode--}"
                    smoke_ok=0
                    for known_id in "${!SMOKE_PASS[@]}"; do
                        if [[ "$known_id" == "$smoke_id" || "$smoke_id" == "$known_id"-* ]]; then
                            smoke_ok=1
                            break
                        fi
                    done
                    if (( smoke_ok )); then
                        result="RUNTIME-VERIFIED"
                    else
                        result="PROVENANCE-VERIFIED"
                        detail="runtime smoke pending: $smoke_id in $SMOKE_RESULTS_DIR/$PROV_BIN_SHA.json"
                        for known_id in "${!SMOKE_FAIL[@]}"; do
                            if [[ "$known_id" == "$smoke_id" || "$smoke_id" == "$known_id"-* ]]; then
                                detail="runtime smoke FAIL: $known_id in $SMOKE_RESULTS_DIR/$PROV_BIN_SHA.json"
                            fi
                        done
                    fi
                else
                    result="PROVENANCE-VERIFIED"
                fi
            else
                result="WEAK-MARKER"
                if [[ "$PROV_STATE" == "verified" ]]; then
                    detail="pattern matched; patch not in lockfile required set: $PATCH_LOCKFILE"
                else
                    detail="pattern matched; provenance unavailable ($PROV_STATE: $PROV_DETAIL)"
                fi
            fi
        fi
    elif [[ -z "$result" ]]; then
        result="STALE"
    fi

    case "$result" in
        APPLIED) applied=$((applied + 1)) ;;
        STALE) stale=$((stale + 1)) ;;
        MISSING-TARGET) missing=$((missing + 1)) ;;
        VERSION-DRIFT) drift=$((drift + 1)) ;;
        ACKNOWLEDGED-DRIFT) acknowledged=$((acknowledged + 1)) ;;
        PROVENANCE-VERIFIED)
            prov_verified=$((prov_verified + 1))
            [[ "$detail" == "runtime smoke pending:"* ]] && runtime_pending=$((runtime_pending + 1))
            [[ "$detail" == "runtime smoke FAIL:"* ]] && runtime_failed=$((runtime_failed + 1))
            ;;
        RUNTIME-VERIFIED) runtime_verified=$((runtime_verified + 1)) ;;
        WEAK-MARKER)
            weak=$((weak + 1))
            # Weak markers for lockfile-required patches mean unsatisfied
            # provenance (or a runtime smoke FAIL) — never an acceptable state.
            if [[ -n "${LOCK_REQUIRED[$patch_id]:-}" ]]; then
                prov_unsatisfied=$((prov_unsatisfied + 1))
            fi
            ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$patch_id" "$dependency" "$target_file" "$runtime_ver" "$result" "$display_path" "$detail" >> "$results_file"
done

# Provenance summary color: GREEN requires every required opencode-- patch to be
# at least PROVENANCE-VERIFIED with no pending runtime smoke and no smoke FAILs;
# AMBER = provenance satisfied but runtime evidence pending; RED = provenance
# missing/mismatched for any required patch.
PROV_COLOR="RED"
if (( prov_unsatisfied == 0 && runtime_failed == 0 )); then
    if (( runtime_pending == 0 )); then
        PROV_COLOR="GREEN"
    else
        PROV_COLOR="AMBER"
    fi
fi
PROV_SMOKE_FAILS=""
for smoke_id in "${!SMOKE_FAIL[@]}"; do
    PROV_SMOKE_FAILS+="${PROV_SMOKE_FAILS:+ }$smoke_id"
done

if ((JSON_OUTPUT)); then
    VERIFY_RESULTS="$results_file" VERIFY_TOTAL="$total" VERIFY_APPLIED="$applied" VERIFY_STALE="$stale" VERIFY_MISSING="$missing" VERIFY_DRIFT="$drift" VERIFY_SCHEMA_FAIL="$schema_fail" VERIFY_ACKNOWLEDGED="$acknowledged" VERIFY_PROV_MODE="$PROV_MODE" VERIFY_PROV_COLOR="$PROV_COLOR" VERIFY_PROV_STATE="$PROV_STATE" VERIFY_PROV_DETAIL="$PROV_DETAIL" VERIFY_PROV_BIN_SHA="$PROV_BIN_SHA" VERIFY_PROV_VERIFIED="$prov_verified" VERIFY_RUNTIME_VERIFIED="$runtime_verified" VERIFY_WEAK="$weak" VERIFY_RUNTIME_PENDING="$runtime_pending" VERIFY_RUNTIME_FAILED="$runtime_failed" VERIFY_PROV_UNSATISFIED="$prov_unsatisfied" VERIFY_SMOKE_FAILS="$PROV_SMOKE_FAILS" python3 -c '
import csv
import json
import os

rows = []
with open(os.environ["VERIFY_RESULTS"], encoding="utf-8", newline="") as handle:
    for raw in csv.reader(handle, delimiter="\t"):
        while len(raw) < 7:
            raw.append("")
        patch_id, dependency, target, runtime, status, path, detail = raw
        row = {"patch_id": patch_id, "dependency": dependency, "target": target,
               "runtime": runtime, "status": status, "path": path}
        if detail:
            row["detail"] = detail
        rows.append(row)
summary = {"total": int(os.environ["VERIFY_TOTAL"]), "applied": int(os.environ["VERIFY_APPLIED"]),
           "stale": int(os.environ["VERIFY_STALE"]), "missing_target": int(os.environ["VERIFY_MISSING"]),
           "version_drift": int(os.environ["VERIFY_DRIFT"]), "schema_fail": int(os.environ["VERIFY_SCHEMA_FAIL"]),
           "acknowledged_drift": int(os.environ["VERIFY_ACKNOWLEDGED"])}
out = {"patches": rows, "summary": summary}
if os.environ["VERIFY_PROV_MODE"] == "1":
    out["opencode_provenance"] = {
        "state": os.environ["VERIFY_PROV_COLOR"].lower(),
        "provenance_state": os.environ["VERIFY_PROV_STATE"],
        "detail": os.environ["VERIFY_PROV_DETAIL"],
        "binary_sha256": os.environ["VERIFY_PROV_BIN_SHA"],
        "provenance_verified": int(os.environ["VERIFY_PROV_VERIFIED"]),
        "runtime_verified": int(os.environ["VERIFY_RUNTIME_VERIFIED"]),
        "weak": int(os.environ["VERIFY_WEAK"]),
        "runtime_pending": int(os.environ["VERIFY_RUNTIME_PENDING"]),
        "runtime_failed": int(os.environ["VERIFY_RUNTIME_FAILED"]),
        "provenance_unsatisfied": int(os.environ["VERIFY_PROV_UNSATISFIED"]),
        "smoke_fails": os.environ["VERIFY_SMOKE_FAILS"].split(),
    }
print(json.dumps(out, sort_keys=True))
'
else
    printf '%-52s %-17s %-28s %-10s %-19s %s\n' PATCH_ID DEP TARGET RUNTIME STATUS PATH
    printf '%150s\n' '' | tr ' ' '-'
    while IFS=$'\t' read -r patch_id dependency target_file runtime_ver result display_path detail; do
        printf '%s %-52s %-17s %-28s %-10s %-19s %s\n' "$result" "$patch_id" "$dependency" "$target_file" "$runtime_ver" "$display_path" "$detail"
    done < "$results_file"
    printf 'Summary (grep verdicts: omo/opencode-dcp/config layers): %d total | %d applied | %d stale | %d missing-target | %d version-drift | %d acknowledged-drift | %d schema-violation\n' "$total" "$applied" "$stale" "$missing" "$drift" "$acknowledged" "$schema_fail"
    if (( PROV_MODE )); then
        printf 'Summary (opencode binary provenance): %s | binary %s | %s | provenance-verified %d | runtime-verified %d | runtime-pending %d | runtime-failed %d | weak %d' "$PROV_COLOR" "${PROV_BIN_SHA:-n/a}" "$PROV_STATE" "$prov_verified" "$runtime_verified" "$runtime_pending" "$runtime_failed" "$weak"
        [[ "$PROV_STATE" != "verified" && -n "$PROV_DETAIL" ]] && printf ' | %s' "$PROV_DETAIL"
        [[ -n "$PROV_SMOKE_FAILS" ]] && printf ' | smoke FAIL: %s' "$PROV_SMOKE_FAILS"
        printf '\n'
    fi
fi

if ((stale > 0 || missing > 0 || drift > 0 || schema_fail > 0)); then
    exit 1
fi
# Timer exit-code contract: exit 0 = acceptable state. Weak markers for
# lockfile-required patches (unsatisfied provenance) and runtime smoke FAILs
# are NOT acceptable; pending runtime smoke (AMBER) is.
if ((prov_unsatisfied > 0 || runtime_failed > 0)); then
    exit 1
fi
exit 0
