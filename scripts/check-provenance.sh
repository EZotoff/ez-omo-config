#!/usr/bin/env bash
# Provenance audit for the live OpenCode binary and OMO dist (patch-provenance
# plan, Task 7). Rides the 30-min integrity-check timer as the 4th ExecStart.
#
# Checks, per artifact (binary / OMO dist):
#   1. receipt exists in ~/.local/share/opencode/builds/ for the live sha256
#   2. receipt generation == lockfile generation
#   3. non-bootstrapped receipts: source_head reachable on the fork remote
#      (ls-remote tip identity, mirroring tests/test_patch_lockfile.sh step 5);
#      bootstrapped receipts: accepted but noted
#   4. smoke freshness: PASS entries for turn-summary-timestamp and
#      bash-lifecycle in ~/.local/share/opencode/smoke-results/<sha>.json
#      (missing = amber "runtime pending", NOT exit-failing; FAIL = exit 1)
#   5. recovery / emergency-bypass markers reported loudly (amber)
#
# Exit codes: 0 acceptable (green or amber-pending); 1 hard provenance
# failure; 2 infrastructure error (remote/git unreachable).
set -euo pipefail

REPO="${EZ_OMO_CONFIG_REPO:-$HOME/ez-omo-config}"
BUILDS_DIR="$HOME/.local/share/opencode/builds"
SMOKE_DIR="$HOME/.local/share/opencode/smoke-results"
STATE_DIR="$HOME/.local/state/opencode"
RECOVERY_ALERT="$STATE_DIR/provenance-recovery.alert"
EMERGENCY_ALERT="$STATE_DIR/patch-guard-emergency.alert"
LOCK_OC="$REPO/config/patch-lockfile.json"
LOCK_OMO="$REPO/config/omo-lockfile.json"
OC_BIN="$HOME/.opencode/bin/opencode"
OC_SRC="${OPENCODE_SRC:-$HOME/src/opencode}"
OMO_DIST="${OMO_DIST_OVERRIDE:-$HOME/oh-my-openagent-v4.19.2/dist/index.js}"

log() { systemd-cat -t patch-provenance -p "$1" <<< "$2" 2>/dev/null || printf '%s\n' "$2" >&2; }
note() { echo "  $1"; log info "$1"; }
amber() { echo "  AMBER: $1"; log warning "AMBER: $1"; }
hard() { echo "  FAIL: $1"; log err "FAIL: $1"; hard_fail=$((hard_fail + 1)); }
infra() { echo "  INFRA: $1"; log err "INFRA: $1"; infra_fail=$((infra_fail + 1)); }

hard_fail=0
infra_fail=0

# remote_reachable <src-repo> <canonical_ref> <sha>
# 0 = sha is ancestor of remote branch tip; 1 = not reachable; 2 = infra error
remote_reachable() {
	local repo="$1" ref="$2" sha="$3"
	local remote="${ref#refs/remotes/}"; remote="${remote%%/*}"
	local branch="${ref#refs/remotes/$remote/}"
	local tip
	tip="$(git -C "$repo" ls-remote "$remote" "refs/heads/$branch" 2>/dev/null | awk '{print $1}')" || return 2
	[[ -n "$tip" ]] || return 2
	git -C "$repo" merge-base --is-ancestor "$sha" "$tip" 2>/dev/null && return 0
	return 1
}

# audit_artifact <label> <artifact> <lockfile> <receipt-name-prefix> <src-repo>
audit_artifact() {
	local label="$1" artifact="$2" lockfile="$3" prefix="$4" src_repo="$5"
	echo "== $label audit =="

	local sha generation receipt rc
	sha="$(sha256sum "$artifact" | awk '{print $1}')" || { infra "cannot hash $artifact"; return; }
	generation="$(jq -r .generation "$lockfile" 2>/dev/null)" || { infra "unreadable lockfile $lockfile"; return; }
	receipt="$BUILDS_DIR/$prefix$sha.json"

	if [[ ! -f "$receipt" ]]; then
		hard "$label: no receipt for sha256 $sha in $BUILDS_DIR"
	else
		jq -e . "$receipt" >/dev/null 2>&1 || { infra "$label: corrupt receipt $receipt"; return; }
		local rgen
		rgen="$(jq -r .generation "$receipt")"
		if [[ "$rgen" != "$generation" ]]; then
			hard "$label: receipt generation '$rgen' != lockfile generation '$generation'"
		elif [[ "$(jq -r '.bootstrapped // false' "$receipt")" == "true" ]]; then
			note "$label: receipted (generation $rgen) — BOOTSTRAPPED receipt, no audited build happened yet"
		else
			local shead
			shead="$(jq -r .source_head "$receipt")"
			remote_reachable "$src_repo" "$(jq -r .canonical_ref "$lockfile")" "$shead"
			rc=$?
			case $rc in
				0) note "$label: receipted (generation $rgen); source_head $shead reachable on fork remote" ;;
				1) hard "$label: source_head $shead NOT reachable on fork remote" ;;
				2) infra "$label: fork remote unreachable; cannot verify source_head $shead" ;;
			esac
		fi
	fi

	# Smoke freshness (binary only, keyed by the live binary sha)
	if [[ "$label" == "binary" ]]; then
		local smoke_file="$SMOKE_DIR/$sha.json" id result
		if [[ ! -f "$smoke_file" ]]; then
			amber "smoke results missing for binary sha $sha — runtime pending"
		else
			for id in turn-summary-timestamp bash-lifecycle; do
				result="$(jq -r --arg id "$id" '[.[] | select((.smoke_id==$id) or (.smoke_id | startswith($id)))][-1].result // ""' "$smoke_file" 2>/dev/null)" || result=""
				case "$result" in
					PASS) note "smoke $id: PASS for this binary" ;;
					FAIL) hard "smoke $id: FAIL recorded for binary sha $sha" ;;
					*) amber "smoke $id: no result for this binary — runtime pending" ;;
				esac
			done
		fi
	fi
}

[[ -f "$LOCK_OC" ]] || infra "lockfile missing: $LOCK_OC"
[[ -f "$LOCK_OMO" ]] || infra "lockfile missing: $LOCK_OMO"
(( infra_fail == 0 )) && audit_artifact "binary" "$OC_BIN" "$LOCK_OC" "" "$OC_SRC"
(( infra_fail == 0 )) && audit_artifact "omo-dist" "$OMO_DIST" "$LOCK_OMO" "omo-" "$HOME/oh-my-openagent-v4.19.2"

echo "== markers =="
if [[ -f "$RECOVERY_ALERT" ]]; then
	amber "RECOVERY marker present: $RECOVERY_ALERT — provenance is red until a normal receipted install"
	log warning "recovery marker present: $RECOVERY_ALERT"
else
	note "no recovery marker"
fi
if [[ -f "$EMERGENCY_ALERT" ]]; then
	amber "EMERGENCY-BYPASS marker present: $EMERGENCY_ALERT — $(head -c 200 "$EMERGENCY_ALERT" | tr '\n' ' ')"
	log warning "emergency-bypass marker present: $EMERGENCY_ALERT"
else
	note "no emergency-bypass marker"
fi

if (( infra_fail > 0 )); then
	log err "provenance audit could not run: $infra_fail infrastructure error(s)"
	echo "PROVENANCE AUDIT: INFRASTRUCTURE ERROR ($infra_fail)"
	exit 2
fi
if (( hard_fail > 0 )); then
	log err "PROVENANCE AUDIT FAILED: $hard_fail hard failure(s)"
	echo "PROVENANCE AUDIT: FAILED ($hard_fail)"
	exit 1
fi
log info "provenance audit OK (amber warnings, if any, above)"
echo "PROVENANCE AUDIT: OK"
exit 0
