#!/usr/bin/env bash
# Remote-presence drift check for source patches carried as fork commits.
#
# Every active entry in .sisyphus/patches/ that says "reapply from fork
# commit(s) <hashes> (branch X)" promises those commits live on the fork
# remote. The 2026-09-18 incident proved that promise can be false: the
# quota-only-fallback patch cited commits 754cec4ee..e6bb8b059 that existed
# only in a since-deleted local directory.
#
# This script phones the GitHub API for each cited hash and alerts when any
# is absent from the remote. It self-throttles to one real run per day so it
# can ride the 30-min integrity-check timer without hammering the API.
#
# Alert channels (mirrors integrity-alert.sh): journal line, marker file,
# desktop notification. Exit 0 when everything cited exists; exit 1 on drift;
# exit 2 when the check could not run (API unreachable) — the timer's
# OnFailure=opencode-integrity-alert.service then handles escalation.
set -euo pipefail

REPO="${EZ_OMO_CONFIG_REPO:-$HOME/ez-omo-config}"
PATCH_DIR="$REPO/.sisyphus/patches"
STATE_DIR="$HOME/.local/state/opencode"
STAMP="$STATE_DIR/patch-remote-check.last"
MARKER="$STATE_DIR/patch-remote-drift.alert"
# The only fork currently carrying patch branches. Override if more appear.
FORK_REPO="${PATCH_FORK_REPO:-EZotoff/oh-my-openagent}"
MIN_INTERVAL_HOURS="${PATCH_REMOTE_CHECK_HOURS:-23}"

mkdir -p "$STATE_DIR"

log() { systemd-cat -t patch-remote-check -p "$1" <<< "$2" 2>/dev/null || printf '%s\n' "$2" >&2; }

# --- self-throttle -----------------------------------------------------------
now=$(date +%s)
if [[ -f "$STAMP" ]]; then
	last=$(cat "$STAMP" 2>/dev/null || echo 0)
	if (( now - last < MIN_INTERVAL_HOURS * 3600 )); then
		exit 0
	fi
fi
echo "$now" > "$STAMP"

# --- collect cited hashes ----------------------------------------------------
# Lines that cite fork commits look like:
#   fork commits `754cec4ee` + `ea6656610` ... (branch `fix/custom-patches-v4.19.2`)
#   fork commit 49f6728 (branch `fix/custom-patches-v4.19.2`)
#   fork commit `08b79a849`, tag `v4.19.2-patches.1`
hashes=$(grep -h -i 'fork commit' "$PATCH_DIR"/*.md 2>/dev/null |
	grep -oE '\b[0-9a-f]{7,40}\b' | sort -u || true)

if [[ -z "$hashes" ]]; then
	log info "no fork-commit hashes cited by active patch entries; nothing to check"
	exit 0
fi

# --- ask the remote ----------------------------------------------------------
api_call() {
	local sha="$1"
	if command -v gh >/dev/null 2>&1; then
		gh api "repos/$FORK_REPO/commits/$sha" >/dev/null 2>&1
	else
		curl -sf -o /dev/null "https://api.github.com/repos/$FORK_REPO/commits/$sha"
	fi
}

# Reachability probe: if the repo endpoint itself fails, we could not run.
if ! api_call "$(git -C "$REPO" rev-parse --short=7 HEAD 2>/dev/null || echo main)" \
	&& ! gh api "repos/$FORK_REPO" >/dev/null 2>&1; then
	log err "GitHub API unreachable; check could not run"
	exit 2
fi

drift=0
checked=0
for sha in $hashes; do
	checked=$((checked + 1))
	if ! api_call "$sha"; then
		drift=$((drift + 1))
		log err "DRIFT: fork commit $sha cited in $PATCH_DIR/ is NOT on remote $FORK_REPO"
	fi
done

if (( drift > 0 )); then
	{
		echo "REMOTE-PRESENCE DRIFT: $drift of $checked cited fork commits missing from $FORK_REPO"
		echo "timestamp: $(date '+%Y-%m-%dT%H:%M:%S%z')"
		echo "Recovery paths in .sisyphus/patches/ are incomplete. Push the fork branch"
		echo "or fix the citations. See AGENTS.md Cooperation Contract item 8."
	} > "$MARKER"
	if command -v notify-send >/dev/null 2>&1; then
		notify-send -u critical 'Patch remote drift' \
			"$drift cited fork commits missing from $FORK_REPO — recovery paths incomplete" || true
	fi
	log err "REMOTE-PRESENCE DRIFT: $drift/$checked cited commits missing; marker: $MARKER"
	exit 1
fi

rm -f "$MARKER"
log info "remote-presence OK: $checked/$checked cited fork commits exist on $FORK_REPO"
exit 0
