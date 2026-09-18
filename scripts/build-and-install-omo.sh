#!/usr/bin/env bash
# build-and-install-omo.sh — receipt-gated rebuild/install/verify for the OMO dist
# (~/oh-my-openagent-v4.19.2/dist/index.js), Task 3 of .omo/plans/patch-provenance.md.
#
# Subcommands:
#   build [--dry-run]              validate fork ancestry per config/omo-lockfile.json,
#                                  then bun install && bun run build; write receipt
#                                  ~/.local/share/opencode/builds/omo-<dist-sha256>.json
#   install [dist] [--dry-run]     gate on receipt + dist verification_patterns,
#                                  node --check, backup, restart services
#   verify [--bootstrap]           receipt + generation + dist pattern check for the
#                                  current dist; --bootstrap writes the one-time
#                                  bootstrapped:true receipt for the current dist
#
# Env overrides (testing):
#   OMO_DIST_OVERRIDE   verify a specific dist file instead of the live dist
#   OMO_RUNTIME_PATH    OMO runtime dir (default ~/oh-my-openagent-v4.19.2)
#   OMO_LOCKFILE        lockfile path (default <repo>/config/omo-lockfile.json)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-patchset.sh
source "$SCRIPT_DIR/lib-patchset.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOCKFILE="${OMO_LOCKFILE:-$REPO_ROOT/config/omo-lockfile.json}"
OMO_REPO="${OMO_RUNTIME_PATH:-$HOME/oh-my-openagent-v4.19.2}"
OMO_DIST="${OMO_DIST_OVERRIDE:-$OMO_REPO/dist/index.js}"
PATCHES_DIR="$REPO_ROOT/.sisyphus/patches"
RECEIPT_PREFIX="omo"

die() { printf 'build-and-install-omo: %s\n' "$*" >&2; exit 1; }
usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

[[ -f "$LOCKFILE" ]] || die "lockfile not found: $LOCKFILE"
[[ -d "$PATCHES_DIR" ]] || die "patch registry not found: $PATCHES_DIR"

lockfile_json="$(jq . "$LOCKFILE")"
lock_dependency() { printf '%s' "$lockfile_json" | jq -r "$1"; }

GENERATION="$(lock_dependency '.generation')"
DEPENDENCY="$(lock_dependency '.dependency')"
CANONICAL_REF="$(lock_dependency '.canonical_ref')"
[[ "$DEPENDENCY" == "oh-my-openagent" ]] || die "lockfile dependency is $DEPENDENCY, expected oh-my-openagent"
[[ -n "$GENERATION" && -n "$CANONICAL_REF" ]] || die "lockfile missing generation/canonical_ref"
REGISTRY_DIGEST="$(patchset_sha256_file "$LOCKFILE")"

receipt_path_for() { printf '%s/%s-%s.json\n' "$RECEIPT_DIR" "$RECEIPT_PREFIX" "$1"; }

omo_receipt_read() {
    local receipt="$1"
    [[ -f "$receipt" ]] || return 1
    jq . "$receipt" >/dev/null 2>&1 || { printf 'corrupt receipt: %s\n' "$receipt" >&2; return 1; }
    cat "$receipt"
}

omo_receipt_write() {
    # omo_receipt_write <dist-sha256> <json>
    local sha="$1" json="$2"
    mkdir -p "$RECEIPT_DIR"
    printf '%s\n' "$json" | jq . > "${RECEIPT_DIR}/${RECEIPT_PREFIX}-${sha}.json"
}

# Dist patches are validated by verification_pattern grep (no ancestry possible
# for bundle-level edits). Patterns come from the entries' frontmatter.
dist_patch_ids() { printf '%s' "$lockfile_json" | jq -r '.dist_patches[].patch_id'; }
source_patch_commits() { printf '%s' "$lockfile_json" | jq -r '.patches[] | .implementation_commits[]'; }

frontmatter_value() { patchset_frontmatter_value "$@"; }

check_dist_patterns() {
    # check_dist_patterns <dist-file> — every dist patch entry's verification_pattern
    # must be present AND its entry status must be active.
    local dist="$1" pid status pattern failures=0
    while IFS= read -r pid; do
        local entry="$PATCHES_DIR/$pid.md"
        [[ -f "$entry" ]] || { printf 'DIST-PATCH MISSING-ENTRY %s\n' "$pid" >&2; failures=1; continue; }
        status="$(frontmatter_value "$entry" status)"
        if [[ "$status" != "active" ]]; then
            printf 'DIST-PATCH NOT-ACTIVE %s (status=%s) — update the lockfile\n' "$pid" "$status" >&2
            failures=1; continue
        fi
        pattern="$(frontmatter_value "$entry" verification_pattern)"
        [[ -n "$pattern" ]] || { printf 'DIST-PATCH NO-PATTERN %s\n' "$pid" >&2; failures=1; continue; }
        if ! patchset_pattern_present "$pattern" "$dist"; then
            printf 'DIST-PATCH STALE %s (pattern not in %s)\n' "$pid" "$dist" >&2
            failures=1
        fi
    done < <(dist_patch_ids)
    return "$failures"
}

validate_source_ancestry() {
    [[ -d "$OMO_REPO/.git" ]] || die "OMO repo not found: $OMO_REPO"
    local -a commits
    mapfile -t commits < <(source_patch_commits)
    (( ${#commits[@]} > 0 )) || die "lockfile has no source implementation commits"
    local c fail=0
    for c in "${commits[@]}"; do
        [[ ${#c} -eq 40 ]] || { printf 'ABBREVIATED-SHA %s (must be 40 chars)\n' "$c" >&2; fail=1; continue; }
        commit_exists "$OMO_REPO" "$c" || { printf 'UNRESOLVED %s\n' "$c" >&2; fail=1; continue; }
        commit_is_ancestor "$OMO_REPO" "$c" "$CANONICAL_REF" || { printf 'NOT-ANCESTOR %s vs %s\n' "$c" "$CANONICAL_REF" >&2; fail=1; }
    done
    (( fail == 0 )) || die "fork ancestry validation failed — run 'git -C ~/oh-my-openagent-v4.19.2 fetch origin' first, then re-check"
    git -C "$OMO_REPO" rev-parse --verify --quiet "$CANONICAL_REF^{commit}" >/dev/null \
        || die "canonical ref does not resolve: $CANONICAL_REF"
}

canonical_head() { git -C "$OMO_REPO" rev-parse "$CANONICAL_REF^{commit}"; }

write_receipt() {
    # write_receipt <dist-sha256> <dist-path> <bootstrapped:true|false>
    local sha="$1" dist="$2" bootstrapped="$3" head receipt
    head="$(canonical_head)"
    omo_receipt_write "$sha" "$(jq -n \
        --arg dep "$DEPENDENCY" --arg gen "$GENERATION" --arg sha "$sha" \
        --arg dist "$dist" --arg head "$head" --arg digest "$REGISTRY_DIGEST" \
        --argjson boot "$bootstrapped" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{dependency:$dep, generation:$gen, dist_sha256:$sha, dist_path:$dist,
          source_head:$head, registry_digest:$digest, bootstrapped:$boot, timestamp:$ts}')"
    receipt="$(receipt_path_for "$sha")"
    printf 'receipt: %s\n' "$receipt"
}

cmd_verify() {
    local bootstrap=0
    [[ "${1:-}" == "--bootstrap" ]] && bootstrap=1
    [[ -f "$OMO_DIST" ]] || die "dist file not found: $OMO_DIST"
    local sha receipt
    sha="$(sha256sum "$OMO_DIST" | awk '{print $1}')"
    receipt="$(receipt_path_for "$sha")"
    if [[ ! -f "$receipt" ]]; then
        if (( bootstrap == 0 )); then
            printf 'NO-RECEIPT dist %s sha256=%s\n' "$OMO_DIST" "$sha" >&2
            printf 'Run "%s verify --bootstrap" once to record the current dist.\n' "$0" >&2
            exit 1
        fi
        # Guarded one-time bootstrap: never bless an override path; require the
        # real dist to carry every dist pattern and the fork ancestry to hold.
        [[ -z "${OMO_DIST_OVERRIDE:-}" ]] || die "refusing to bootstrap an OMO_DIST_OVERRIDE artifact"
        validate_source_ancestry
        check_dist_patterns "$OMO_DIST" || die "bootstrap refused: dist verification_patterns incomplete"
        printf 'BOOTSTRAP writing receipt for current dist %s\n' "$OMO_DIST"
        write_receipt "$sha" "$OMO_DIST" true
    fi
    local receipt_json generation
    receipt_json="$(omo_receipt_read "$receipt")"
    generation="$(printf '%s' "$receipt_json" | jq -r '.generation')"
    [[ "$generation" == "$GENERATION" ]] || { printf 'GENERATION-MISMATCH receipt=%s lockfile=%s\n' "$generation" "$GENERATION" >&2; exit 1; }
    check_dist_patterns "$OMO_DIST" || exit 1
    printf 'VERIFIED omo dist %s sha256=%s generation=%s bootstrapped=%s\n' \
        "$OMO_DIST" "$sha" "$generation" "$(printf '%s' "$receipt_json" | jq -r '.bootstrapped')"
}

cmd_build() {
    local dry_run=0
    [[ "${1:-}" == "--dry-run" ]] && dry_run=1
    validate_source_ancestry
    if [[ -n "$(git -C "$OMO_REPO" status --porcelain)" ]]; then
        die "OMO repo working tree is dirty — commit or stash before rebuilding"
    fi
    local head; head="$(canonical_head)"
    if (( dry_run )); then
        printf 'DRY-RUN would: git -C %s checkout %s (detached)\n' "$OMO_REPO" "$head"
        printf 'DRY-RUN would: (cd %s && bun install && bun run build)\n' "$OMO_REPO"
        printf 'DRY-RUN would: reapply dist patches per .sisyphus/patches/omo--*.md entries\n'
        printf 'DRY-RUN would: write receipt %s/%s-<dist-sha256>.json\n' "$RECEIPT_DIR" "$RECEIPT_PREFIX"
        return 0
    fi
    local prev_branch; prev_branch="$(git -C "$OMO_REPO" rev-parse --abbrev-ref HEAD)"
    git -C "$OMO_REPO" checkout --detach "$head"
    (cd "$OMO_REPO" && bun install && bun run build)
    git -C "$OMO_REPO" checkout "$prev_branch"
    # A fresh rebuild loses the dist-level patches; they must be reapplied per
    # their registry entries BEFORE a receipt can be written.
    if ! check_dist_patterns "$OMO_REPO/dist/index.js"; then
        printf 'BUILD-NEEDS-DIST-REAPPLY rebuild dropped dist patches; reapply per .sisyphus/patches/omo--*.md entries, then re-run build (or apply + verify)\n' >&2
        exit 1
    fi
    local sha; sha="$(sha256sum "$OMO_REPO/dist/index.js" | awk '{print $1}')"
    write_receipt "$sha" "$OMO_REPO/dist/index.js" false
}

cmd_install() {
    local dist="" dry_run=0 arg
    for arg in "$@"; do
        case "$arg" in
            --dry-run) dry_run=1 ;;
            *) [[ -z "$dist" ]] && dist="$arg" || usage ;;
        esac
    done
    dist="${dist:-$OMO_DIST}"
    [[ -f "$dist" ]] || die "dist file not found: $dist"
    local sha receipt generation
    sha="$(sha256sum "$dist" | awk '{print $1}')"
    receipt="$(receipt_path_for "$sha")"
    if ! omo_receipt_read "$receipt" >/dev/null; then
        printf 'NO-RECEIPT dist sha256=%s has no receipt — refusing install\n' "$sha" >&2
        exit 1
    fi
    generation="$(omo_receipt_read "$receipt" | jq -r '.generation')"
    [[ "$generation" == "$GENERATION" ]] || die "generation mismatch: receipt=$generation lockfile=$GENERATION"
    check_dist_patterns "$dist" || die "dist verification_patterns incomplete — reapply per registry entries first"
    node --check "$dist" || die "node --check failed on $dist"
    if (( dry_run )); then
        printf 'DRY-RUN would: backup %s, copy %s over it, restart opencode services\n' "$OMO_DIST" "$dist"
        return 0
    fi
    [[ -z "${OMO_DIST_OVERRIDE:-}" ]] || die "refusing real install with OMO_DIST_OVERRIDE set (testing override)"
    local backup="$OMO_DIST.backup-$(date -u +%Y%m%dT%H%M%SZ)"
    cp "$OMO_DIST" "$backup"
    cp "$dist" "$OMO_DIST"
    systemctl --user stop opencode.service opencode-interactive.service
    systemctl --user start opencode.service opencode-interactive.service
    printf 'installed %s (backup: %s); services restarted — run verify + TUI check\n' "$OMO_DIST" "$backup"
}

main() {
    local cmd="${1:-}"; shift || true
    case "$cmd" in
        build)   cmd_build "$@" ;;
        install) cmd_install "$@" ;;
        verify)  cmd_verify "$@" ;;
        *) usage ;;
    esac
}

main "$@"
