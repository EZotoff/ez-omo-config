#!/usr/bin/env bash
# build-and-install-opencode.sh — transactional opencode binary installer with
# build receipts and recovery mode (patch-provenance plan, Task 2).
#
# Automates the manual AGENTS.md "Patching OpenCode Binary" procedure:
#   build   validate lockfile ancestry -> bun build -> receipt in
#           ~/.local/share/opencode/builds/<binary-sha256>.json
#   install receipted, generation-matched swap with live-binary backup and
#           session-safe service stop/start; --dry-run performs ALL checks,
#           swaps nothing; --recovery-from <backup> --reason "<text>" skips
#           remote/generation checks and writes a persistent red marker
#           (~/.local/state/opencode/provenance-recovery.alert) on real runs
#   verify  receipt + generation + (non-recovery) remote reachability of the
#           receipt's source_head; --bootstrap writes a one-time
#           "bootstrapped": true receipt for the current live binary
#
# Exit codes (verify): 0 verified / 1 drift / 2 unverifiable.
# Exit codes (build/install): 0 ok / 1 refusal or failure / 2 usage.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib-patchset.sh
source "$REPO/scripts/lib-patchset.sh"
# shellcheck source=parse-opencode-version.sh
source "$REPO/scripts/parse-opencode-version.sh"

gh_api_ok() {
    if command -v gh >/dev/null 2>&1; then
        gh api "repos/$FORK_GH_REPO" >/dev/null 2>&1
    else
        curl -sf -o /dev/null "https://api.github.com/repos/$FORK_GH_REPO"
    fi
}

LOCKFILE="${PATCH_LOCKFILE:-$REPO/config/patch-lockfile.json}"
SRC_REPO="$OPENCODE_SRC"
LIVE_BIN="$HOME/.opencode/bin/opencode"
DIST_BIN="$SRC_REPO/packages/opencode/dist/opencode-linux-x64/bin/opencode"
STATE_DIR="$HOME/.local/state/opencode"
RECOVERY_ALERT="$STATE_DIR/provenance-recovery.alert"
FORK_GH_REPO="${OPENCODE_FORK_GH:-EZotoff/opencode}"

die() { printf 'build-and-install-opencode: %s\n' "$*" >&2; exit 1; }
usage() {
    cat >&2 <<'USAGE'
usage:
  build-and-install-opencode.sh build
  build-and-install-opencode.sh install <binary> [--recovery-from <backup>]
                                       [--reason "<text>"] [--dry-run]
  build-and-install-opencode.sh verify [binary] [--bootstrap] [--source-head <sha>]
USAGE
    exit 2
}

lf_field() {
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2],""))' \
        "$LOCKFILE" "$1"
}

lockfile_values() {
    lockfile_load "$LOCKFILE"
    UPSTREAM="$(lf_field upstream_version)"
    UPSTREAM_BASE="$(lf_field upstream_base)"
    GENERATION="$(lf_field generation)"
    [[ -n "$UPSTREAM" && -n "$UPSTREAM_BASE" && -n "$GENERATION" ]] \
        || die "lockfile missing upstream_version/upstream_base/generation: $LOCKFILE"
    GEN_INT="${GENERATION##*.}"
    [[ "$GEN_INT" =~ ^[0-9]+$ ]] || die "cannot parse generation integer from: $GENERATION"
    VERSION_STRING="$UPSTREAM-p$GEN_INT"
}

required_commits_ancestor_of_head() {
    local head="$1" patch_id kind sha
    commit_is_ancestor "$SRC_REPO" "$UPSTREAM_BASE" "$head" \
        || die "upstream_base $UPSTREAM_BASE is not an ancestor of HEAD $head"
    while IFS=$'\t' read -r patch_id kind sha; do
        [[ "$kind" == "required" ]] || continue
        commit_exists "$SRC_REPO" "$sha" \
            || die "lockfile commit $sha ($patch_id) not found in $SRC_REPO"
        commit_is_ancestor "$SRC_REPO" "$sha" "$head" \
            || die "lockfile commit $sha ($patch_id) is not an ancestor of HEAD $head"
    done < <(python3 - "$LOCKFILE" <<'PYEOF'
import json, sys
for patch in json.load(open(sys.argv[1]))["patches"]:
    kind = patch.get("implementation_kind")
    if kind == "acknowledged-drift":
        continue
    for sha in patch.get("implementation_commits", []):
        print(f"{patch['patch_id']}\t{kind or 'required'}\t{sha}")
PYEOF
)
}

binary_sha() { sha256sum "$1" | awk '{print $1}'; }

gh_commit_exists() {
    local sha="$1"
    if command -v gh >/dev/null 2>&1; then
        gh api "repos/$FORK_GH_REPO/commits/$sha" >/dev/null 2>&1
    else
        curl -sf -o /dev/null "https://api.github.com/repos/$FORK_GH_REPO/commits/$sha"
    fi
}

# ---------------------------------------------------------------- build -----
cmd_build() {
    lockfile_values
    [[ -d "$SRC_REPO" ]] || die "source repo not found: $SRC_REPO"
    local dirty
    dirty="$(git -C "$SRC_REPO" status --porcelain --untracked-files=no)"
    [[ -z "$dirty" ]] || die "refusing build: dirty tracked source tree in $SRC_REPO (commit or stash first)"
    local head
    head="$(git -C "$SRC_REPO" rev-parse 'HEAD^{commit}')" \
        || die "cannot resolve HEAD in $SRC_REPO"
    required_commits_ancestor_of_head "$head"

    local build_cmd="OPENCODE_VERSION=$VERSION_STRING bun run script/build.ts --single --skip-install --skip-embed-web-ui"
    echo "building opencode $VERSION_STRING (generation $GENERATION)"
    (cd "$SRC_REPO/packages/opencode" && OPENCODE_VERSION="$VERSION_STRING" \
        bun run script/build.ts --single --skip-install --skip-embed-web-ui)

    [[ -x "$DIST_BIN" ]] || die "build finished but dist binary missing: $DIST_BIN"
    local built_ver bin_sha reg_digest extra receipt_path
    built_ver="$("$DIST_BIN" --version)"
    opencode_version_compatible "$UPSTREAM" "$built_ver" \
        || die "built binary version '$built_ver' incompatible with upstream $UPSTREAM"
    bin_sha="$(binary_sha "$DIST_BIN")"
    reg_digest="$(sha256sum "$LOCKFILE" | awk '{print $1}')"
    extra="$(python3 - "$built_ver" "$head" "$UPSTREAM_BASE" "$GENERATION" "$reg_digest" "$build_cmd" <<'PYEOF'
import json, sys
keys = ("binary_version", "source_head", "upstream_base", "generation",
        "registry_digest", "build_cmd")
print(",".join(f'"{k}":{json.dumps(v)}' for k, v in zip(keys, sys.argv[1:])))
PYEOF
)"
    receipt_path="$(receipt_write "$bin_sha" "$extra")"
    echo "receipt: $receipt_path"
    echo "binary:  $DIST_BIN ($bin_sha, version $built_ver)"
}

# --------------------------------------------------------------- install ----
cmd_install() {
    local binary="" recovery_from="" reason="" dry_run=0
    while (( $# )); do
        case "$1" in
            --recovery-from) recovery_from="${2:?}"; shift 2 ;;
            --reason) reason="${2:?}"; shift 2 ;;
            --dry-run) dry_run=1; shift ;;
            -*) usage ;;
            *) [[ -z "$binary" ]] || usage; binary="$1"; shift ;;
        esac
    done
    [[ -n "$binary" ]] || usage
    [[ -f "$binary" ]] || die "no such binary: $binary"
    lockfile_values

    local bin_sha runtime_ver
    bin_sha="$(binary_sha "$binary")"
    runtime_ver="$("$binary" --version 2>/dev/null || true)"

    local recovery=0
    if [[ -n "$recovery_from" ]]; then
        recovery=1
        [[ -n "$reason" ]] || die "--recovery-from requires --reason \"<text>\""
        [[ -f "$recovery_from" ]] || die "recovery backup not found: $recovery_from"
        # Recovery is the deliberate escape hatch: bound to the backup SHA and a
        # reason, it skips receipt/generation/remote checks and stays red via the
        # persistent marker until a normal receipted install clears it.
    else
        receipt_read "$bin_sha" >/dev/null \
            || die "no receipt for binary sha256 $bin_sha — run 'build' (or 'verify --bootstrap' for the current live binary) first; refusing install"
        local receipt_gen
        receipt_gen="$(receipt_read "$bin_sha" generation)"
        [[ "$receipt_gen" == "$GENERATION" ]] \
            || die "receipt generation '$receipt_gen' != lockfile generation '$GENERATION' — refusing install (use --recovery-from + --reason for a deliberate rollback)"
        opencode_version_compatible "$UPSTREAM" "$runtime_ver" \
            || die "binary version '$runtime_ver' incompatible with lockfile upstream $UPSTREAM"
    fi

    if (( dry_run )); then
        echo "DRY-RUN: all checks passed; nothing was modified"
        echo "  binary:      $binary ($bin_sha, version $runtime_ver)"
        echo "  generation:  $GENERATION"
        if (( recovery )); then
            echo "  mode:        RECOVERY from $recovery_from (reason: $reason)"
            echo "  marker:      would write $RECOVERY_ALERT (NOT written on dry-run)"
        else
            echo "  mode:        normal receipted install"
            echo "  receipt:     $RECEIPT_DIR/$bin_sha.json"
            local ts
            ts="$(date +%Y%m%d-%H%M%S)"
            echo "  backup:      would write $LIVE_BIN.backup-$runtime_ver-$GEN_INT-$ts"
        fi
        echo "  services:    would stop/start opencode.service opencode-interactive.service"
        return 0
    fi

    local backup
    backup="$LIVE_BIN.backup-$runtime_ver-$GEN_INT-$(date +%Y%m%d-%H%M%S)"
    cp -a "$LIVE_BIN" "$backup"
    echo "backed up live binary -> $backup"

    systemctl --user stop opencode.service opencode-interactive.service
    install -m 755 "$binary" "$LIVE_BIN"
    systemctl --user start opencode.service opencode-interactive.service
    echo "installed $bin_sha -> $LIVE_BIN; services restarted"

    if (( recovery )); then
        mkdir -p "$STATE_DIR"
        printf 'recovery install of %s from %s\nreason: %s\nbinary sha256: %s\ntimestamp: %s\n' \
            "$LIVE_BIN" "$recovery_from" "$reason" "$bin_sha" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            >> "$RECOVERY_ALERT"
        # Mark the receipt as recovery so 'verify' skips remote reachability.
        local rec_extra
        rec_extra="$(python3 - "$runtime_ver" "$GENERATION" "$reason" <<'PYEOF'
import json, sys
keys = ("binary_version", "generation", "recovery_reason")
print(",".join(f'"{k}":{json.dumps(v)}' for k, v in zip(keys, sys.argv[1:])) + ',"recovery":true')
PYEOF
)"
        receipt_write "$bin_sha" "$rec_extra" >/dev/null
        echo "RECOVERY MARKER WRITTEN: $RECOVERY_ALERT — provenance stays red until a normal receipted install"
    else
        if [[ -f "$RECOVERY_ALERT" ]]; then
            rm -f "$RECOVERY_ALERT"
            echo "cleared recovery marker (normal receipted install)"
        fi
    fi

    echo "post-install verification:"
    "$REPO/scripts/verify-live-patches.sh" || echo "WARNING: verify-live-patches.sh reported issues" >&2
    bash "$REPO/tests/test_patch_lockfile.sh" || echo "WARNING: lockfile validator failed" >&2
    echo "install complete: $bin_sha (generation $GENERATION)"
}

# ---------------------------------------------------------------- verify ----
cmd_verify() {
    local binary="" bootstrap=0 source_head=""
    while (( $# )); do
        case "$1" in
            --bootstrap) bootstrap=1; shift ;;
            --source-head) source_head="${2:?}"; shift 2 ;;
            -*) usage ;;
            *) [[ -z "$binary" ]] || usage; binary="$1"; shift ;;
        esac
    done
    binary="${binary:-$LIVE_BIN}"
    [[ -f "$binary" ]] || die "no such binary: $binary"
    lockfile_values

    local bin_sha runtime_ver
    bin_sha="$(binary_sha "$binary")"
    runtime_ver="$("$binary" --version 2>/dev/null || true)"
    opencode_version_compatible "$UPSTREAM" "$runtime_ver" \
        || die "binary version '$runtime_ver' incompatible with lockfile upstream $UPSTREAM — refusing (generation mismatch guard)"

    if ! receipt_read "$bin_sha" >/dev/null; then
        if (( bootstrap )); then
            [[ -n "$source_head" ]] || source_head="$(git -C "$SRC_REPO" rev-parse 'HEAD^{commit}' 2>/dev/null || true)"
            [[ -n "$source_head" ]] || die "--bootstrap needs --source-head or a resolvable HEAD in $SRC_REPO"
            required_commits_ancestor_of_head "$source_head"
            local reg_digest extra receipt_path
            reg_digest="$(sha256sum "$LOCKFILE" | awk '{print $1}')"
            extra="$(python3 - "$runtime_ver" "$source_head" "$UPSTREAM_BASE" "$GENERATION" "$reg_digest" <<'PYEOF'
import json, sys
keys = ("binary_version", "source_head", "upstream_base", "generation", "registry_digest")
print(",".join(f'"{k}":{json.dumps(v)}' for k, v in zip(keys, sys.argv[1:])) + ',"bootstrapped":true,"note":"one-time bootstrap receipt; current live binary accepted without an audited build (patch-provenance plan Task 2)"')
PYEOF
)"
            receipt_path="$(receipt_write "$bin_sha" "$extra")"
            echo "BOOTSTRAP receipt written: $receipt_path"
            echo "verified: $bin_sha (generation $GENERATION, bootstrapped)"
            return 0
        fi
        die "no receipt for binary sha256 $bin_sha (drift)"
    fi

    local receipt_gen source_head_rt recovery_receipt
    receipt_gen="$(receipt_read "$bin_sha" generation)"
    recovery_receipt="$(receipt_read "$bin_sha" recovery)"
    if [[ "$receipt_gen" != "$GENERATION" ]]; then
        echo "verify: DRIFT — receipt generation '$receipt_gen' != lockfile generation '$GENERATION'" >&2
        exit 1
    fi
    source_head_rt="$(receipt_read "$bin_sha" source_head)"
    if [[ "$recovery_receipt" != "true" && -n "$source_head_rt" ]]; then
        if ! gh_api_ok; then
            echo "verify: UNVERIFIABLE — GitHub API unreachable, cannot check $source_head_rt" >&2
            exit 2
        fi
        if ! gh_commit_exists "$source_head_rt"; then
            echo "verify: DRIFT — source_head $source_head_rt not reachable on $FORK_GH_REPO" >&2
            exit 1
        fi
    fi
    echo "verify: OK — $bin_sha (generation $GENERATION, source_head $source_head_rt)"
}

case "${1:-}" in
    build) shift; cmd_build "$@" ;;
    install) shift; cmd_install "$@" ;;
    verify) shift; cmd_verify "$@" ;;
    *) usage ;;
esac
