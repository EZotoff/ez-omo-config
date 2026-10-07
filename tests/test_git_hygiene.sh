#!/usr/bin/env bash
# test_git_hygiene.sh — fixture tests for scripts/git-hygiene.sh
#
# Covers the tiered push discipline contract (plugins/agent-git-workflow.ts):
#   1. observe mode never pushes (personal repo stays unpushed)
#   2. push mode pushes PERSONAL current branch when fast-forwardable
#   3. push mode NEVER force-pushes a diverged branch (remote wins, reported)
#   4. SHARED repos are never pushed in any mode
#   5. NO-REMOTE repos are reported
#   6. invalid mode exits non-zero
#
# Fixtures are local bare repos under /tmp — the personal ones live under a
# path containing /EZotoff/ so URL-owner classification matches production.
# Bare repos are seeded first so fresh clones get proper upstream tracking.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HYGIENE="$REPO_ROOT/scripts/git-hygiene.sh"

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

TMP="$(mktemp -d /tmp/opencode/git-hygiene-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

FIX="$TMP/fixture"
REMOTES="$TMP/remotes"
STATE="$TMP/state"
mkdir -p "$FIX" "$REMOTES/EZotoff" "$REMOTES/Veran-Dev" "$STATE"

FAILURES=0
fail() { echo "FAIL: $*" >&2; FAILURES=$((FAILURES + 1)); }
assert_contains() { # $1 haystack $2 needle $3 what
    grep -qF -- "$2" <<<"$1" || fail "$3 (missing: $2)"
}

GITC=(-c user.email=test@test -c commit.gpgsign=false)

# --- fixtures ------------------------------------------------------------
git init -q -b main "$REMOTES/EZotoff/personal.git" --bare
git init -q -b main "$REMOTES/EZotoff/second.git" --bare
git init -q -b main "$REMOTES/Veran-Dev/shared.git" --bare

seed() { # $1 bare path — push one commit so clones get upstream tracking
    local s="$TMP/seeds/$(basename "$1" .git)"
    git clone -q "$1" "$s"
    echo seed >"$s/f" && git -C "$s" add f
    git -C "$s" "${GITC[@]}" commit -qm "chore: seed"
    git -C "$s" push -q origin main
}
seed "$REMOTES/EZotoff/personal.git"
seed "$REMOTES/Veran-Dev/shared.git"
seed "$REMOTES/EZotoff/second.git"
SHARED_SEED_REV="$(git -C "$REMOTES/Veran-Dev/shared.git" rev-parse main)"

# repoP: personal remote, 1 unpushed commit
git clone -q "$REMOTES/EZotoff/personal.git" "$FIX/repoP"
echo one >"$FIX/repoP/f" && git -C "$FIX/repoP" add f
git -C "$FIX/repoP" "${GITC[@]}" commit -qm "feat: one"

# repoS: shared remote, 1 unpushed commit
git clone -q "$REMOTES/Veran-Dev/shared.git" "$FIX/repoS"
echo two >"$FIX/repoS/f" && git -C "$FIX/repoS" add f
git -C "$FIX/repoS" "${GITC[@]}" commit -qm "feat: two"

# repoN: no remote at all
git init -q -b main "$FIX/repoN"
echo three >"$FIX/repoN/f" && git -C "$FIX/repoN" add f
git -C "$FIX/repoN" "${GITC[@]}" commit -qm "feat: three"

# repoD: diverged from its personal remote (rival push from another clone)
git clone -q "$REMOTES/EZotoff/second.git" "$FIX/repoD"
git clone -q "$REMOTES/EZotoff/second.git" "$FIX/repoD-other"
echo rival >"$FIX/repoD-other/f" && git -C "$FIX/repoD-other" add f
git -C "$FIX/repoD-other" "${GITC[@]}" commit -qm "feat: rival"
git -C "$FIX/repoD-other" push -q origin main
echo local >"$FIX/repoD/f2" && git -C "$FIX/repoD" add f2
git -C "$FIX/repoD" "${GITC[@]}" commit -qm "feat: local-only"

rev() { git -C "$1" rev-parse "${2:-HEAD}"; }

run_hygiene() { # $1 mode
    GIT_HYGIENE_ROOTS="$FIX" \
    GIT_HYGIENE_STATE="$STATE" \
    GIT_HYGIENE_MODE="$1" \
    bash "$HYGIENE"
}

# --- 1. observe mode ------------------------------------------------------
OUT_OBSERVE="$(run_hygiene observe || true)"
assert_contains "$OUT_OBSERVE" "PERSONAL    $FIX/repoP [main] unpushed=1" "observe: personal pile reported"
assert_contains "$OUT_OBSERVE" "SHARED      $FIX/repoS" "observe: shared reported"
assert_contains "$OUT_OBSERVE" "NO-REMOTE   $FIX/repoN" "observe: no-remote reported"
[[ "$(rev "$REMOTES/EZotoff/personal.git" main)" != "$(rev "$FIX/repoP")" ]] ||
    fail "observe: pushed despite observe mode"
grep -q '"action":"observe"' "$STATE/log.jsonl" || fail "observe: jsonl action not recorded"

# --- 2. push mode, fast-forwardable personal ------------------------------
OUT_PUSH="$(run_hygiene push || true)"
assert_contains "$OUT_PUSH" "PUSHED      $FIX/repoP [main] pushed 1 commit(s)" "push: personal FF push"
[[ "$(rev "$REMOTES/EZotoff/personal.git" main)" == "$(rev "$FIX/repoP")" ]] ||
    fail "push: remote main does not match repoP HEAD after FF push"

# --- 3. diverged: never forced --------------------------------------------
assert_contains "$OUT_PUSH" "DIVERGED    $FIX/repoD" "push: divergence reported"
[[ "$(rev "$REMOTES/EZotoff/second.git" main)" == "$(rev "$FIX/repoD-other")" ]] ||
    fail "push: diverged remote was overwritten (force-like behavior!)"

# --- 4. shared: never pushed -----------------------------------------------
assert_contains "$OUT_PUSH" "SHARED      $FIX/repoS" "push: shared reported, not pushed"
[[ "$(rev "$REMOTES/Veran-Dev/shared.git" main)" == "$SHARED_SEED_REV" ]] ||
    fail "push: shared remote received commits"

# --- 5. no-remote reported --------------------------------------------------
assert_contains "$OUT_PUSH" "NO-REMOTE   $FIX/repoN" "push: no-remote reported"

# --- 6. invalid mode --------------------------------------------------------
if GIT_HYGIENE_ROOTS="$FIX" GIT_HYGIENE_STATE="$STATE" GIT_HYGIENE_MODE=bogus \
    bash "$HYGIENE" >/dev/null 2>&1; then
    fail "invalid mode did not exit non-zero"
fi

# ---------------------------------------------------------------------------
if [[ $FAILURES -eq 0 ]]; then
    echo "PASS: git-hygiene (observe/push/FF/diverged/shared/no-remote/mode-validation)"
else
    echo "git-hygiene: $FAILURES failure(s)" >&2
    exit 1
fi
