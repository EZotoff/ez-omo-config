#!/usr/bin/env bash
# test_patch_lockfile.sh — validate the opencode patch-set lockfile
#
# Checks (per .omo/plans/patch-provenance.md Task 1):
#   1. config/patch-lockfile.json parses as JSON and has required fields
#   2. Bijection: every status:active opencode--*.md registry entry appears
#      exactly once in lockfile patches[], and every lockfile patch_id maps
#      to an active entry
#   3. upstream_base is the full (40-char) SHA of the tag v<upstream_version>
#   4. Every required implementation_commit: 40-char full SHA, resolves as a
#      commit in the source repo, AND is an ancestor of the canonical ref head
#   5. Canonical branch tip is reachable on the fork remote (ls-remote) and
#      matches the local ref — per-commit remote presence follows from
#      ancestry + tip identity, so no per-commit API calls are made
#   6. Duplicate patch_id rejected; abbreviated (<40 char) SHAs rejected
#   7. implementation_kind "acknowledged-drift" entries exempt from commit
#      requirements (their superseded_commits are recorded, not required)
#
# Env overrides for tamper-testing:
#   PATCH_LOCKFILE=<path>   validate an alternative lockfile
#   OPENCODE_SRC=<path>     alternative opencode source repo
#
# Mirrors tests/test_patch_entries.sh output convention: "PASS: ..." / exit 0.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../../scripts/lib-patchset.sh
source "$REPO_ROOT/scripts/lib-patchset.sh"

LOCKFILE="${PATCH_LOCKFILE:-$REPO_ROOT/config/patch-lockfile.json}"
PATCH_DIR="$REPO_ROOT/.sisyphus/patches"

echo "=== Patch Lockfile Validation ==="
echo "Lockfile: $LOCKFILE"
echo "Source repo: $OPENCODE_SRC"
echo ""

fail() {
    echo ""
    echo "FAIL: $1"
    exit 1
}

[[ -d "$OPENCODE_SRC/.git" ]] || fail "source repo not found or not a git repo: $OPENCODE_SRC (set OPENCODE_SRC)"

# --- 1. Structural validation ---
lockfile_load "$LOCKFILE" || fail "lockfile structural validation failed"
echo "OK: JSON parses, required top-level fields present"

# --- Resolve canonical head locally ---
UPSTREAM_VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["upstream_version"])' "$LOCKFILE")"
UPSTREAM_BASE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["upstream_base"])' "$LOCKFILE")"
CANONICAL_REF="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["canonical_ref"])' "$LOCKFILE")"
CANONICAL_HEAD="$(git -C "$OPENCODE_SRC" rev-parse "$CANONICAL_REF" 2>/dev/null)" \
    || fail "canonical ref $CANONICAL_REF does not resolve in $OPENCODE_SRC"

# --- 3. upstream_base matches the release tag commit ---
[[ ${#UPSTREAM_BASE} -eq 40 ]] || fail "upstream_base is not a full 40-char SHA: $UPSTREAM_BASE"
TAG_COMMIT="$(git -C "$OPENCODE_SRC" rev-parse "v${UPSTREAM_VERSION}^{commit}" 2>/dev/null)" \
    || fail "tag v$UPSTREAM_VERSION does not resolve in $OPENCODE_SRC"
[[ "$UPSTREAM_BASE" == "$TAG_COMMIT" ]] \
    || fail "upstream_base $UPSTREAM_BASE != v$UPSTREAM_VERSION commit $TAG_COMMIT"
echo "OK: upstream_base == v$UPSTREAM_VERSION commit ($UPSTREAM_BASE)"

# --- 2. Bijection with active registry entries ---
# Active patch_ids from opencode--*.md frontmatter (status: active).
ACTIVE_IDS="$(mktemp)"
LOCK_IDS="$(mktemp)"
trap 'rm -f "$ACTIVE_IDS" "$LOCK_IDS"' EXIT
for entry in "$PATCH_DIR"/opencode--*.md; do
    [[ -f "$entry" ]] || continue
    pid="$(sed -n 's/^patch_id:[[:space:]]*"\?\([^"]*\)"\?$/\1/p' "$entry" | head -1)"
    status="$(sed -n 's/^status:[[:space:]]*"\?\([^"]*\)"\?$/\1/p' "$entry" | head -1)"
    [[ "$status" == "active" ]] && echo "$pid" >> "$ACTIVE_IDS"
done
python3 -c 'import json,sys; [print(p["patch_id"]) for p in json.load(open(sys.argv[1]))["patches"]]' "$LOCKFILE" > "$LOCK_IDS"

# duplicate lockfile patch_ids
DUPES="$(sort "$LOCK_IDS" | uniq -d)"
[[ -z "$DUPES" ]] || fail "duplicate patch_id(s) in lockfile: $(echo "$DUPES" | tr '\n' ' ')"

# every active entry present in lockfile exactly once
MISSING_FROM_LOCK=""
while IFS= read -r pid; do
    count="$(grep -cx "$pid" "$LOCK_IDS" || true)"
    [[ "$count" -eq 1 ]] || MISSING_FROM_LOCK="$MISSING_FROM_LOCK $pid"
done < "$ACTIVE_IDS"
[[ -z "$MISSING_FROM_LOCK" ]] || fail "active registry entry(ies) missing or duplicated in lockfile:$MISSING_FROM_LOCK"

# every lockfile patch maps to an active entry
MISSING_FROM_REGISTRY=""
while IFS= read -r pid; do
    grep -qx "$pid" "$ACTIVE_IDS" || MISSING_FROM_REGISTRY="$MISSING_FROM_REGISTRY $pid"
done < "$LOCK_IDS"
[[ -z "$MISSING_FROM_REGISTRY" ]] || fail "lockfile patch_id(s) with no active registry entry:$MISSING_FROM_REGISTRY"
echo "OK: bijection holds ($(wc -l < "$LOCK_IDS" | tr -d ' ') active opencode patches <-> lockfile entries)"

# --- 4/6/7. Per-patch commit validation ---
python3 - "$LOCKFILE" <<'PYEOF' > /tmp/opencode-lockfile-commits.txt
import json, sys
for p in json.load(open(sys.argv[1]))["patches"]:
    kind = p.get("implementation_kind", "source")
    if kind == "acknowledged-drift":
        continue  # exempt: superseded commits are recorded, not required
    for sha in p.get("implementation_commits", []):
        print(f"{p['patch_id']}\t{sha}")
PYEOF
while IFS=$'\t' read -r pid sha; do
    [[ ${#sha} -eq 40 ]] || fail "$pid: implementation commit is not a full 40-char SHA: $sha"
    commit_exists "$OPENCODE_SRC" "$sha" \
        || fail "$pid: commit does not resolve in $OPENCODE_SRC: $sha"
    commit_is_ancestor "$OPENCODE_SRC" "$sha" "$CANONICAL_HEAD" \
        || fail "$pid: commit is NOT an ancestor of $CANONICAL_REF ($CANONICAL_HEAD): $sha"
done < /tmp/opencode-lockfile-commits.txt
rm -f /tmp/opencode-lockfile-commits.txt
N_COMMITS="$(python3 -c '
import json,sys
n=0
for p in json.load(open(sys.argv[1]))["patches"]:
    if p.get("implementation_kind")!="acknowledged-drift":
        n+=len(p.get("implementation_commits",[]))
print(n)' "$LOCKFILE")"
echo "OK: $N_COMMITS implementation commits exist and are ancestors of the canonical head"

# --- 5. Canonical branch tip is on the fork remote ---
REMOTE_NAME="${CANONICAL_REF#refs/remotes/}"    # fork/fix/all-patches-v1.18.5
REMOTE="${REMOTE_NAME%%/*}"                     # fork
BRANCH="${REMOTE_NAME#*/}"                      # fix/all-patches-v1.18.5
REMOTE_TIP="$(git -C "$OPENCODE_SRC" ls-remote "$REMOTE" "refs/heads/$BRANCH" 2>/dev/null | awk '{print $1}')"
[[ -n "$REMOTE_TIP" ]] || fail "canonical branch refs/heads/$BRANCH not found on remote '$REMOTE'"
[[ "$REMOTE_TIP" == "$CANONICAL_HEAD" ]] \
    || fail "remote branch tip $REMOTE_TIP != local canonical head $CANONICAL_HEAD (push or refetch)"
echo "OK: canonical branch tip $CANONICAL_HEAD is pushed to $REMOTE"

echo ""
echo "PASS: patch lockfile validates (structure, bijection, ancestry, remote presence)"
exit 0
