#!/usr/bin/env bash
# check-wake-journal-growth.sh — read-only canary for OMO parent-wake journal health.
#
# Why: the wake-journal-outbox patch (omo--wake-journal-outbox) added a durable
# per-wake state machine. Runtime verification (2026-10-02, Branch A of
# .omo/plans/wake-redundancy-decision.md) showed shouldReply=true wakes consume
# reliably (65/65 post-rebuild), but shouldReply=false admit-only wakes
# systematically remain dispatched-awaiting-output (no assistant turn exists to
# satisfy exact-output consumption). This canary counts stale awaiting entries
# every 30 min so week-over-week growth — flip condition #1 for ever building a
# consumption-aware flush (>50 redundant wakes/week) — is measurable instead of
# anecdotal. Threshold register: wisdom "wake journal flip conditions" /
# .omo/plans/wake-redundancy-decision.md.
#
# Advisory only: ALWAYS exits 0. No alerting write-path until the growth signal
# is confirmed live (docs/rollout-protocol.md gates that).
# Coverage note: two-level glob matches <project>/ and <project>/<sub>/.omo
# trees (deeper worktree paths are not scanned — same coverage as the
# 2026-10-02 baseline measurement).
set -euo pipefail

STALE_SECS=1800 # WAKE_DEADLINE_MS — awaiting entries older than this are past deadline
now=$(date +%s)
total=0 stuck=0 consumed=0 dead=0
shopt -s nullglob
for f in "$HOME"/*/.omo/run-continuation/wakes/*.json \
         "$HOME"/*/*/.omo/run-continuation/wakes/*.json; do
	total=$((total + 1))
	state=$(jq -r '.state // "unreadable"' "$f" 2>/dev/null) || state="unreadable"
	case "$state" in
		consumed) consumed=$((consumed + 1)) ;;
		dead-letter) dead=$((dead + 1)) ;;
		dispatched-awaiting-output)
				mtime=$(stat -c %Y "$f" 2>/dev/null) || continue # race: journal consumed/deleted between glob and stat
			if [ $((now - mtime)) -gt "$STALE_SECS" ]; then
				stuck=$((stuck + 1))
			fi
			;;
	esac
done
echo "wake-journal canary: stale-awaiting(>30min)=${stuck} total=${total} consumed=${consumed} dead-letter=${dead}"
