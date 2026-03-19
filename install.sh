#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

DRY_RUN=0
MODE="symlink"
SELECTION_SPECIFIED=0
INSTALL_COMMANDS=0
INSTALL_CONFIGS=0
INSTALL_PLUGINS=0
INSTALL_SKILLS=0
INSTALL_SCRIPTS=0

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="$HOME/.ez-omo-backup/$TIMESTAMP"
BACKUP_ROOT_CREATED=0

DIRECTORIES_CREATED=0
ITEMS_PROCESSED=0
ITEMS_INSTALLED=0
ITEMS_SKIPPED=0
ITEMS_BACKED_UP=0

ITEMS=(
    "commands|commands/models-preset.md|$HOME/.config/opencode/command/models-preset.md"
    "configs|configs/opencode/opencode.json|$HOME/.config/opencode/opencode.json"
    "configs|configs/opencode/opencode.jsonc|$HOME/.opencode/opencode.jsonc"
    "configs|configs/opencode/provider-connect-retry.mjs|$HOME/.config/opencode/provider-connect-retry.mjs"
    "configs|configs/oh-my-opencode/oh-my-opencode.json|$HOME/.config/opencode/oh-my-opencode.json"
    "configs|extras/ocx.jsonc|$HOME/.opencode/ocx.jsonc"
    "plugins|plugins/worktree.ts|$HOME/.opencode/plugin/worktree.ts"
    "plugins|plugins/worktree|$HOME/.opencode/plugin/worktree"
    "plugins|plugins/git-safety.ts|$HOME/.opencode/plugin/git-safety.ts"
    "plugins|plugins/review-enforcer.ts|$HOME/.opencode/plugin/review-enforcer.ts"
    "plugins|plugins/auto-checkpoint.ts|$HOME/.opencode/plugin/auto-checkpoint.ts"
    "plugins|plugins/kdco-primitives|$HOME/.opencode/plugin/kdco-primitives"
    "skills|skills/wisdom|$HOME/.config/opencode/skills/wisdom"
    "skills|skills/atlas-review-handler|$HOME/.config/opencode/skills/atlas-review-handler"
    "skills|skills/review-protocol|$HOME/.config/opencode/skills/review-protocol"
    "skills|skills/playwright|$HOME/.config/opencode/skills/playwright"
    "skills|skills/deployment|$HOME/.config/opencode/skills/deployment"
    "skills|skills/frontend-ui-ux|$HOME/.config/opencode/skills/frontend-ui-ux"
    "scripts|scripts/wisdom/wisdom-common.sh|$HOME/.sisyphus/scripts/wisdom-common.sh"
    "scripts|scripts/wisdom/wisdom-search.sh|$HOME/.sisyphus/scripts/wisdom-search.sh"
    "scripts|scripts/wisdom/wisdom-write.sh|$HOME/.sisyphus/scripts/wisdom-write.sh"
    "scripts|scripts/wisdom/wisdom-sync.sh|$HOME/.sisyphus/scripts/wisdom-sync.sh"
    "scripts|scripts/wisdom/wisdom-archive.sh|$HOME/.sisyphus/scripts/wisdom-archive.sh"
    "scripts|scripts/wisdom/wisdom-delete.sh|$HOME/.sisyphus/scripts/wisdom-delete.sh"
    "scripts|scripts/wisdom/wisdom-edit.sh|$HOME/.sisyphus/scripts/wisdom-edit.sh"
    "scripts|scripts/wisdom/wisdom-gc.sh|$HOME/.sisyphus/scripts/wisdom-gc.sh"
    "scripts|scripts/wisdom/wisdom-merge.sh|$HOME/.sisyphus/scripts/wisdom-merge.sh"
)

usage() {
    cat <<'EOF'
Usage: ./install.sh [OPTIONS]

Modes:
  --dry-run   Print planned actions without making changes
  --symlink   Create symlinks from install targets to repo files (default)
  --copy      Copy repo files to install targets

Selective install flags:
  --commands  Install slash commands only
  --configs   Install configuration files only
  --plugins   Install plugins only
  --skills    Install skills only
  --scripts   Install wisdom scripts only
  --all       Install everything (default)
  --help      Show this help text
EOF
}

log() {
    printf '%s\n' "$*"
}

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

detect_os() {
    case "$(uname -s)" in
        Darwin|Linux) ;;
        *) fail "Unsupported OS: $(uname -s). Only macOS and Linux are supported." ;;
    esac
}

resolve_path() {
    local path="$1"

    if [[ -d "$path" ]]; then
        (
            cd "$path"
            pwd -P
        )
        return 0
    fi

    local dir base
    dir="$(dirname "$path")"
    base="$(basename "$path")"
    (
        cd "$dir"
        printf '%s/%s\n' "$(pwd -P)" "$base"
    )
}

resolve_link_target() {
    local link_path="$1"
    local target

    target="$(readlink "$link_path")"
    if [[ "$target" = /* ]]; then
        resolve_path "$target"
    else
        resolve_path "$(dirname "$link_path")/$target"
    fi
}

same_symlink() {
    local source="$1"
    local target="$2"

    [[ -L "$target" ]] || return 1
    [[ "$(resolve_link_target "$target")" == "$(resolve_path "$source")" ]]
}

same_copy() {
    local source="$1"
    local target="$2"

    [[ -e "$target" && ! -L "$target" ]] || return 1

    if [[ -d "$source" ]]; then
        [[ -d "$target" ]] || return 1
        diff -qr "$source" "$target" >/dev/null 2>&1
    else
        [[ -f "$target" ]] || return 1
        cmp -s "$source" "$target"
    fi
}

ensure_parent_dir() {
    local target="$1"
    local parent

    parent="$(dirname "$target")"
    if [[ -d "$parent" ]]; then
        return 0
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "[DRY-RUN] Create directory: $parent"
    else
        mkdir -p "$parent"
    fi

    DIRECTORIES_CREATED=$((DIRECTORIES_CREATED + 1))
}

ensure_backup_root() {
    [[ "$BACKUP_ROOT_CREATED" -eq 1 ]] && return 0

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "[DRY-RUN] Create backup root: $BACKUP_ROOT"
    else
        mkdir -p "$BACKUP_ROOT"
    fi

    BACKUP_ROOT_CREATED=1
}

backup_target() {
    local target="$1"
    local relative backup_path

    ensure_backup_root

    relative="${target#"$HOME"/}"
    if [[ "$relative" == "$target" ]]; then
        relative="$(basename "$target")"
    fi
    backup_path="$BACKUP_ROOT/$relative"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "[DRY-RUN] Backup: $target -> $backup_path"
    else
        mkdir -p "$(dirname "$backup_path")"
        mv "$target" "$backup_path"
    fi

    ITEMS_BACKED_UP=$((ITEMS_BACKED_UP + 1))
}

copy_source() {
    local source="$1"
    local target="$2"

    if [[ -d "$source" ]]; then
        cp -Rp "$source" "$target"
    else
        cp -p "$source" "$target"
    fi
}

category_selected() {
    local category="$1"

    case "$category" in
        commands) [[ "$INSTALL_COMMANDS" -eq 1 ]] ;;
        configs) [[ "$INSTALL_CONFIGS" -eq 1 ]] ;;
        plugins) [[ "$INSTALL_PLUGINS" -eq 1 ]] ;;
        skills) [[ "$INSTALL_SKILLS" -eq 1 ]] ;;
        scripts) [[ "$INSTALL_SCRIPTS" -eq 1 ]] ;;
        *) return 1 ;;
    esac
}

verify_repo_structure() {
    local missing=0
    local category source_rel _target

    for item in "${ITEMS[@]}"; do
        IFS='|' read -r category source_rel _target <<< "$item"
        if ! category_selected "$category"; then
            continue
        fi

        if [[ ! -e "$REPO_ROOT/$source_rel" ]]; then
            printf 'Missing required source: %s\n' "$source_rel" >&2
            missing=1
        fi
    done

    [[ "$missing" -eq 0 ]] || fail "Repo structure verification failed."
}

install_item() {
    local source_rel="$1"
    local target="$2"
    local source="$REPO_ROOT/$source_rel"

    ITEMS_PROCESSED=$((ITEMS_PROCESSED + 1))

    ensure_parent_dir "$target"

    if same_symlink "$source" "$target" || same_copy "$source" "$target"; then
        log "Skip unchanged: $target"
        ITEMS_SKIPPED=$((ITEMS_SKIPPED + 1))
        return 0
    fi

    if [[ -e "$target" || -L "$target" ]]; then
        backup_target "$target"
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        if [[ "$MODE" == "symlink" ]]; then
            log "[DRY-RUN] Symlink: $target -> $source"
        else
            log "[DRY-RUN] Copy: $source -> $target"
        fi
    else
        if [[ "$MODE" == "symlink" ]]; then
            ln -s "$source" "$target"
        else
            copy_source "$source" "$target"
        fi
    fi

    ITEMS_INSTALLED=$((ITEMS_INSTALLED + 1))
}

parse_args() {
    local mode_seen=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=1
                ;;
            --symlink)
                if [[ "$mode_seen" -eq 1 && "$MODE" != "symlink" ]]; then
                    fail "Choose only one install mode: --symlink or --copy."
                fi
                MODE="symlink"
                mode_seen=1
                ;;
            --copy)
                if [[ "$mode_seen" -eq 1 && "$MODE" != "copy" ]]; then
                    fail "Choose only one install mode: --symlink or --copy."
                fi
                MODE="copy"
                mode_seen=1
                ;;
            --configs)
                INSTALL_CONFIGS=1
                SELECTION_SPECIFIED=1
                ;;
            --commands)
                INSTALL_COMMANDS=1
                SELECTION_SPECIFIED=1
                ;;
            --plugins)
                INSTALL_PLUGINS=1
                SELECTION_SPECIFIED=1
                ;;
            --skills)
                INSTALL_SKILLS=1
                SELECTION_SPECIFIED=1
                ;;
            --scripts)
                INSTALL_SCRIPTS=1
                SELECTION_SPECIFIED=1
                ;;
            --all)
                INSTALL_COMMANDS=1
                INSTALL_CONFIGS=1
                INSTALL_PLUGINS=1
                INSTALL_SKILLS=1
                INSTALL_SCRIPTS=1
                SELECTION_SPECIFIED=1
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
        shift
    done

    if [[ "$SELECTION_SPECIFIED" -eq 0 ]]; then
        INSTALL_COMMANDS=1
        INSTALL_CONFIGS=1
        INSTALL_PLUGINS=1
        INSTALL_SKILLS=1
        INSTALL_SCRIPTS=1
    fi
}

selected_groups() {
    local groups=()

    [[ "$INSTALL_COMMANDS" -eq 1 ]] && groups+=("commands")
    [[ "$INSTALL_CONFIGS" -eq 1 ]] && groups+=("configs")
    [[ "$INSTALL_PLUGINS" -eq 1 ]] && groups+=("plugins")
    [[ "$INSTALL_SKILLS" -eq 1 ]] && groups+=("skills")
    [[ "$INSTALL_SCRIPTS" -eq 1 ]] && groups+=("scripts")

    local IFS=', '
    printf '%s\n' "${groups[*]}"
}

print_summary() {
    log ""
    log "Install summary"
    log "- Mode: $MODE"
    log "- Dry run: $([[ "$DRY_RUN" -eq 1 ]] && printf 'yes' || printf 'no')"
    log "- Groups: $(selected_groups)"
    log "- Items processed: $ITEMS_PROCESSED"
    log "- Installed/updated: $ITEMS_INSTALLED"
    log "- Skipped unchanged: $ITEMS_SKIPPED"
    log "- Backups created: $ITEMS_BACKED_UP"
    log "- Directories created: $DIRECTORIES_CREATED"
    log ""

    if [[ "$ITEMS_BACKED_UP" -gt 0 || "$DRY_RUN" -eq 1 ]]; then
        log "Backup location: $BACKUP_ROOT"
        log "Rollback hint: cp -R \"$BACKUP_ROOT\"/. \"$HOME\"/"
    else
        log "No backups were needed."
    fi
}

main() {
    local category source_rel target

    parse_args "$@"
    detect_os
    verify_repo_structure

    for item in "${ITEMS[@]}"; do
        IFS='|' read -r category source_rel target <<< "$item"
        if category_selected "$category"; then
            install_item "$source_rel" "$target"
        fi
    done

    print_summary
}

main "$@"
