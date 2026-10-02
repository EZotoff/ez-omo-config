#!/usr/bin/env bash
# check-plugin-load-health.sh — detect fresh plugin-load failures in the live server log.
#
# Why: OpenCode's plugin loader logs "failed to load plugin" ERROR lines that
# default output suppresses; nobody sees them until forensic log mining. Two
# incidents proved the blast radius: 2026-08-06 git-safety `__test__` object
# export (~1,251 errors, guardrails offline 14 days) and 2026-08→09
# review-enforcer helper exports (2,084 `output.includes` errors) — both silent
# because the failure mode is one log line per server start, no toast, no test
# failure (static registration tests like regressions/010 keep passing while
# the plugin is dead at load). The /update-to-latest Post-Cutover Smoke-Boot
# Gate catches this at cutover, but binary installs that bypass the skill
# (custom patched builds) get no such check. This script collapses detection
# to the integrity timer's 30-minute cadence: unit fails →
# opencode-integrity-triage.service fires (OnFailure).
#
# Mechanism: inode+byte-offset watermark on the live log; each run inspects
# only bytes appended since the previous run. First run bootstraps the
# watermark to EOF (observe mode — never alerts on history). Log rotation
# (inode change or size shrink) resets the watermark to 0 of the new file.
# Plugin paths under /tmp/ are excluded: scratch-dir probe sessions
# deliberately load fake plugins (session-attachment hygiene policy) and must
# not gate prod health. The watermark advances even when alerting, so each
# failure line alerts exactly once.
set -euo pipefail

LOG_PATH="${OPENCODE_LOG_PATH:-$HOME/.local/share/opencode/log/opencode.log}"
STATE_DIR="${PLUGIN_LOAD_HEALTH_STATE_DIR:-$HOME/.local/state/opencode}"
STATE_FILE="$STATE_DIR/plugin-load-health.state"

if [ ! -f "$LOG_PATH" ]; then
	echo "plugin-load health: log missing (${LOG_PATH}) — nothing to check"
	exit 0
fi

mkdir -p "$STATE_DIR"
cur_inode=$(stat -c %i "$LOG_PATH")
cur_size=$(stat -c %s "$LOG_PATH")

inode="$cur_inode"
offset="$cur_size" # first run: observe mode, skip history
if [ -f "$STATE_FILE" ]; then
	read -r inode offset < "$STATE_FILE" || { inode="$cur_inode"; offset="$cur_size"; }
fi
# rotation (new inode) or truncation (size shrink) → rescan new file from start
if [ "$inode" != "$cur_inode" ] || [ "$offset" -gt "$cur_size" ]; then
	offset=0
fi

new_bytes=$((cur_size - offset))
failures=0
if [ "$new_bytes" -gt 0 ]; then
	# tail -c +N is 1-based; inspect only the newly appended region
	matches=$(tail -c +$((offset + 1)) "$LOG_PATH" |
		grep -a "failed to load plugin" |
		grep -av "path=file:///tmp/" || true)
	if [ -n "$matches" ]; then
		failures=$(printf '%s\n' "$matches" | wc -l)
		echo "PLUGIN-LOAD HEALTH: ${failures} new 'failed to load plugin' line(s) in ${LOG_PATH}:" >&2
		printf '%s\n' "$matches" | head -10 | cut -c1-300 >&2
		echo "" >&2
		echo "Safety/review plugins may be OFFLINE on a running server. Check:" >&2
		echo "  - export contract comments in ~/ez-omo-config/plugins/*" >&2
		echo "  - the smoke-boot gate section in the update-to-latest skill" >&2
	fi
fi

printf '%s %s\n' "$cur_inode" "$cur_size" > "$STATE_FILE"

if [ "$failures" -gt 0 ]; then
	exit 1
fi
echo "plugin-load health: clean (${new_bytes} new bytes scanned)"
