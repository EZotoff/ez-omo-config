#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROJECT_PATH=""
MODE=""  # check, dry-run, apply

BEGIN_MARKER="# BEGIN OMO VERA HYGIENE"
END_MARKER="# END OMO VERA HYGIENE"

usage() {
    cat <<'EOF'
Usage: vera-hygiene.sh --project <absolute-path> [--check|--dry-run|--apply]

Required:
  --project <path>    Absolute path to the project directory

Exactly one of:
  --check             Diagnose only; exit non-zero if hygiene blockers exist
  --dry-run           Print proposed .veraignore managed block and commands
  --apply             Update/create project .veraignore with managed block

Exit codes:
  0   No blockers detected (check) or operation succeeded (dry-run/apply)
  1   Invalid arguments or project validation failed
  2   Hygiene blockers detected (--check mode)
EOF
}

log_info() {
    printf 'INFO: %s\n' "$*"
}

log_warn() {
    printf 'WARN: %s\n' "$*" >&2
}

log_error() {
    printf 'ERROR: %s\n' "$*" >&2
}

fail() {
    log_error "$*"
    exit 1
}

parse_args() {
    local mode_seen=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project)
                PROJECT_PATH="${2:-}"
                if [[ -z "$PROJECT_PATH" ]]; then
                    fail "--project requires a non-empty argument"
                fi
                shift 2
                ;;
            --check)
                MODE="check"
                mode_seen=$((mode_seen + 1))
                shift
                ;;
            --dry-run)
                MODE="dry-run"
                mode_seen=$((mode_seen + 1))
                shift
                ;;
            --apply)
                MODE="apply"
                mode_seen=$((mode_seen + 1))
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                usage >&2
                fail "Unknown option: $1"
                ;;
        esac
    done

    if [[ -z "$PROJECT_PATH" ]]; then
        usage >&2
        fail "--project is required"
    fi

    if [[ "$mode_seen" -ne 1 ]]; then
        usage >&2
        fail "Exactly one of --check, --dry-run, --apply is required"
    fi
}

validate_project() {
    if [[ ! -d "$PROJECT_PATH" ]]; then
        fail "Project directory does not exist: $PROJECT_PATH"
    fi

    if [[ "$PROJECT_PATH" != /* ]]; then
        fail "--project must be an absolute path, got: $PROJECT_PATH"
    fi

    if [[ ! -d "$PROJECT_PATH/.git" ]]; then
        fail "Project is not a git repository (no .git directory): $PROJECT_PATH"
    fi
}

# Detect directories that are unreadable by attempting to list them.
# This catches container-owned dirs and permission-denied paths more
# reliably than find -readable, which root bypasses.
detect_unreadable_dirs() {
    local unreadable=()
    local dir

    while IFS= read -r -d '' dir; do
        local rel="${dir#$PROJECT_PATH/}"
        if [[ "$rel" == "$dir" ]]; then
            continue
        fi
        # Skip if nested under an already-found unreadable dir
        local skip=0
        local existing
        for existing in "${unreadable[@]}"; do
            if [[ "$rel" == "$existing"/* || "$rel" == "$existing" ]]; then
                skip=1
                break
            fi
        done
        if [[ "$skip" -eq 1 ]]; then
            continue
        fi
        # Actually attempt to list the directory
        if ! ls -A "$dir" >/dev/null 2>&1; then
            unreadable+=("$rel")
        fi
    done < <(find "$PROJECT_PATH" -mindepth 1 -type d -print0 2>/dev/null)

    printf '%s\n' "${unreadable[@]+"${unreadable[@]}"}"
}

# Detect common heavy/generated directories if they exist
detect_heavy_dirs() {
    local candidates=(
        "node_modules"
        ".next"
        "out"
        "build"
        "dist"
        "coverage"
        ".vera"
        ".sisyphus"
    )
    local found=()

    for cand in "${candidates[@]}"; do
        if [[ -d "$PROJECT_PATH/$cand" ]]; then
            found+=("$cand")
        fi
    done

    printf '%s\n' "${found[@]+"${found[@]}"}"
}

# Check if a path prefix has tracked source files underneath
has_tracked_files_under() {
    local prefix="$1"
    local count
    count=$(cd "$PROJECT_PATH" && git ls-files -- "$prefix" 2>/dev/null | wc -l)
    [[ "$count" -gt 0 ]]
}

# Check if a gitignore rule exists for a path
gitignore_has_rule() {
    local path="$1"
    # Use git check-ignore; if it returns 0, the path is ignored
    (cd "$PROJECT_PATH" && git check-ignore -q "$path" 2>/dev/null)
}

# Gather .gitignore patterns that would cover our detected items
gather_gitignore_rules() {
    local items=("$@")
    local rules=()
    local item

    for item in "${items[@]}"; do
        if gitignore_has_rule "$item"; then
            # Path is already ignored by git; note it for the managed block comment
            rules+=("# Already in .gitignore: $item")
        fi
    done

    printf '%s\n' "${rules[@]+"${rules[@]}"}"
}

# Build the managed ignore block
# Accepts newline-separated strings (NOT arrays) to handle multiple items correctly
build_managed_block() {
    local unreadable_str="$1"
    local heavy_str="$2"
    local gitignore_rules_str="$3"
    shift 3

    local unreadable=()
    local heavy=()
    local gitignore_rules=()

    if [[ -n "$unreadable_str" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && unreadable+=("$line")
        done <<< "$unreadable_str"
    fi
    if [[ -n "$heavy_str" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && heavy+=("$line")
        done <<< "$heavy_str"
    fi
    if [[ -n "$gitignore_rules_str" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && gitignore_rules+=("$line")
        done <<< "$gitignore_rules_str"
    fi

    local block=""
    block+="$BEGIN_MARKER"
    block+=$'\n'
    block+="# Auto-generated by vera-hygiene.sh — do not edit between markers"
    block+=$'\n'

    # Always include .vera/ to prevent self-indexing
    block+=".vera/"
    block+=$'\n'

    # Unreadable directories (exact paths)
    if [[ ${#unreadable[@]} -gt 0 ]]; then
        block+=$'\n'
        block+="# Unreadable directories (permission denied during indexing)"
        block+=$'\n'
        local d
        for d in "${unreadable[@]}"; do
            # Ensure trailing slash for directories
            if [[ "$d" != */ ]]; then
                d="$d/"
            fi
            block+="$d"
            block+=$'\n'
        done
    fi

    # Heavy/generated directories
    if [[ ${#heavy[@]} -gt 0 ]]; then
        block+=$'\n'
        block+="# Heavy or generated directories"
        block+=$'\n'
        local d
        for d in "${heavy[@]}"; do
            if [[ "$d" != */ ]]; then
                d="$d/"
            fi
            # Safety: do not add if tracked source files exist under it
            if has_tracked_files_under "$d"; then
                block+="# SKIPPED (tracked files underneath): $d"
            else
                block+="$d"
            fi
            block+=$'\n'
        done
    fi

    # Log files (safe to ignore, not tracked)
    block+=$'\n'
    block+="# Log files"
    block+=$'\n'
    block+="*.log"
    block+=$'\n'

    # Gitignore fallback note
    if [[ ${#gitignore_rules[@]} -gt 0 ]]; then
        block+=$'\n'
        block+="# .gitignore coverage notes"
        block+=$'\n'
        local r
        for r in "${gitignore_rules[@]}"; do
            block+="$r"
            block+=$'\n'
        done
    fi

    # Include directive note — only enable after fixture test proves support
    block+=$'\n'
    block+="# Note: #include .gitignore is not used here because Vera support"
    block+=$'\n'
    block+="# for #include directives has not been verified via fixture tests."
    block+=$'\n'
    block+="# Relevant .gitignore rules are expanded above instead."
    block+=$'\n'

    block+="$END_MARKER"

    printf '%s\n' "$block"
}

# Extract user content from existing .veraignore, removing the managed block
extract_user_content() {
    local file="$1"
    local in_block=0
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "$BEGIN_MARKER" ]]; then
            in_block=1
            continue
        fi
        if [[ "$line" == "$END_MARKER" ]]; then
            in_block=0
            continue
        fi
        if [[ "$in_block" -eq 0 ]]; then
            printf '%s\n' "$line"
        fi
    done < "$file"
}

# Write the new .veraignore with preserved user content and updated managed block
write_veraignore() {
    local managed_block="$1"
    local outfile="$PROJECT_PATH/.veraignore"
    local user_content=""

    if [[ -f "$outfile" ]]; then
        user_content=$(extract_user_content "$outfile")
    fi

    {
        if [[ -n "$user_content" ]]; then
            printf '%s\n' "$user_content"
            # Ensure a blank line before the managed block if user content exists
            printf '\n'
        fi
        printf '%s\n' "$managed_block"
    } > "$outfile"
}

# Print dry-run output
print_dry_run() {
    local managed_block="$1"
    local unreadable_str="$2"
    local heavy_str="$3"
    local blockers=0

    log_info "Project: $PROJECT_PATH"
    log_info "Mode: dry-run"
    log_info ""
    log_info "Proposed .veraignore managed block:"
    log_info "---"
    printf '%s\n' "$managed_block"
    log_info "---"
    log_info ""
    log_info "Proposed commands:"
    log_info "  cat > '$PROJECT_PATH/.veraignore' <<'VERAEOF'"
    printf '%s\n' "$managed_block" | while IFS= read -r line; do
        log_info "  $line"
    done
    log_info "  VERAEOF"
    log_info ""

    # Count blockers for exit code
    local unreadable=()
    local heavy=()
    if [[ -n "$unreadable_str" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && unreadable+=("$line")
        done <<< "$unreadable_str"
    fi
    if [[ -n "$heavy_str" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && heavy+=("$line")
        done <<< "$heavy_str"
    fi
    if [[ ${#unreadable[@]} -gt 0 || ${#heavy[@]} -gt 0 ]]; then
        blockers=$(( ${#unreadable[@]} + ${#heavy[@]} ))
    fi

    return 0
}

# Run check mode
run_check() {
    local unreadable=()
    local heavy=()
    local u h

    while IFS= read -r u; do
        [[ -n "$u" ]] && unreadable+=("$u")
    done < <(detect_unreadable_dirs)

    while IFS= read -r h; do
        [[ -n "$h" ]] && heavy+=("$h")
    done < <(detect_heavy_dirs)

    local blockers=0

    if [[ ${#unreadable[@]} -gt 0 ]]; then
        log_warn "Unreadable directories detected (${#unreadable[@]}):"
        for u in "${unreadable[@]}"; do
            log_warn "  - $u"
        done
        blockers=$((blockers + ${#unreadable[@]}))
    fi

    if [[ ${#heavy[@]} -gt 0 ]]; then
        log_warn "Heavy/generated directories detected (${#heavy[@]}):"
        for h in "${heavy[@]}"; do
            log_warn "  - $h"
        done
        blockers=$((blockers + ${#heavy[@]}))
    fi

    if [[ "$blockers" -gt 0 ]]; then
        log_warn ""
        log_warn "$blockers hygiene blocker(s) detected. Run with --dry-run to preview fixes, or --apply to update .veraignore."
        return 2
    else
        log_info "No hygiene blockers detected."
        return 0
    fi
}

# Run dry-run mode
run_dry_run() {
    local unreadable=()
    local heavy=()
    local u h

    while IFS= read -r u; do
        [[ -n "$u" ]] && unreadable+=("$u")
    done < <(detect_unreadable_dirs)

    while IFS= read -r h; do
        [[ -n "$h" ]] && heavy+=("$h")
    done < <(detect_heavy_dirs)

    local gitignore_rules=()
    local all_items=("${unreadable[@]+"${unreadable[@]}"}" "${heavy[@]+"${heavy[@]}"}")
    local r
    while IFS= read -r r; do
        [[ -n "$r" ]] && gitignore_rules+=("$r")
    done < <(gather_gitignore_rules "${all_items[@]}")

    local unreadable_nl="" heavy_nl="" gitignore_rules_nl=""
    if [[ ${#unreadable[@]} -gt 0 ]]; then
        unreadable_nl="$(printf '%s\n' "${unreadable[@]}")"
    fi
    if [[ ${#heavy[@]} -gt 0 ]]; then
        heavy_nl="$(printf '%s\n' "${heavy[@]}")"
    fi
    if [[ ${#gitignore_rules[@]} -gt 0 ]]; then
        gitignore_rules_nl="$(printf '%s\n' "${gitignore_rules[@]}")"
    fi
    local block
    block=$(build_managed_block "$unreadable_nl" "$heavy_nl" "$gitignore_rules_nl")

    print_dry_run "$block" "$unreadable_nl" "$heavy_nl"
}

# Run apply mode
run_apply() {
    local unreadable=()
    local heavy=()
    local u h

    while IFS= read -r u; do
        [[ -n "$u" ]] && unreadable+=("$u")
    done < <(detect_unreadable_dirs)

    while IFS= read -r h; do
        [[ -n "$h" ]] && heavy+=("$h")
    done < <(detect_heavy_dirs)

    local gitignore_rules=()
    local all_items=("${unreadable[@]+"${unreadable[@]}"}" "${heavy[@]+"${heavy[@]}"}")
    local r
    while IFS= read -r r; do
        [[ -n "$r" ]] && gitignore_rules+=("$r")
    done < <(gather_gitignore_rules "${all_items[@]}")

    local unreadable_nl="" heavy_nl="" gitignore_rules_nl=""
    if [[ ${#unreadable[@]} -gt 0 ]]; then
        unreadable_nl="$(printf '%s\n' "${unreadable[@]}")"
    fi
    if [[ ${#heavy[@]} -gt 0 ]]; then
        heavy_nl="$(printf '%s\n' "${heavy[@]}")"
    fi
    if [[ ${#gitignore_rules[@]} -gt 0 ]]; then
        gitignore_rules_nl="$(printf '%s\n' "${gitignore_rules[@]}")"
    fi
    local block
    block=$(build_managed_block "$unreadable_nl" "$heavy_nl" "$gitignore_rules_nl")

    write_veraignore "$block"
    log_info "Updated: $PROJECT_PATH/.veraignore"

    local total=$(( ${#unreadable[@]} + ${#heavy[@]} ))
    if [[ "$total" -gt 0 ]]; then
        log_info "Managed block includes $total ignored path(s)."
    fi
}

main() {
    parse_args "$@"
    validate_project

    cd "$PROJECT_PATH"

    case "$MODE" in
        check)
            run_check
            ;;
        dry-run)
            run_dry_run
            ;;
        apply)
            run_apply
            ;;
    esac
}

main "$@"
