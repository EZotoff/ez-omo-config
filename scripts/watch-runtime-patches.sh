#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${EZ_OMO_CONFIG_REPO:-$HOME/ez-omo-config}"
VERIFY_SCRIPT="$REPO_ROOT/scripts/verify-live-patches.sh"
ALERT_SCRIPT="$REPO_ROOT/scripts/integrity-alert.sh"
# OMO fork runtime dir + dist (separate deployable runtime bundle).
OMO_RUNTIME="${OMO_FORK_RUNTIME:-$HOME/oh-my-openagent-v4.19.2}"
OMO_DIST="${OMO_FORK_DIST:-$OMO_RUNTIME/dist}"

log() { systemd-cat -t opencode-patch-watcher -p "$1" <<< "$2"; }

alert_runtime_delete() {
	local detail="$1"
	log err "INTEGRITY-ALERT: OMO runtime directory deleted/moved: $detail"
	if [[ -x "$ALERT_SCRIPT" ]]; then
		"$ALERT_SCRIPT" opencode-patch-watcher.service >/dev/null 2>&1 || true
	fi
}

# Re-arm loop: if a watched tree is deleted, inotifywait exits and the loop
# re-establishes watches once the directories reappear (rebuild/reclone).
while true; do
	# Parent-level guard (NON-recursive — $HOME must never be watched with -r):
	# catches whole-directory deletion/move of the runtime dir itself.
	# 2026-09-18 incident: rm -rf ~/oh-my-openagent-v4.19.2 killed the recursive
	# dist watches silently and no alert fired.
	parent_pid=""
	if [[ -d "$OMO_RUNTIME" ]]; then
		inotifywait -m -q -e delete,moved_from --format '%e %w%f' "$HOME" 2>/dev/null |
			while IFS= read -r line; do
				events="${line%% *}"
				path="${line#* }"
				[[ "$path" == "$OMO_RUNTIME" ]] || continue
				case "$events" in
					*DELETE*|*MOVED_FROM*) alert_runtime_delete "$path [$events]" ;;
				esac
			done &
		parent_pid=$!
	fi

	# Main watch: live binary dir + OMO dist (recursive).
	WATCH_PATHS=("$HOME/.opencode/bin/")
	if [[ -d "$OMO_DIST" ]]; then
		WATCH_PATHS+=("$OMO_DIST")
	else
		log warning "OMO fork dist not found, watching OpenCode bin only: $OMO_DIST"
	fi

	log info "watching: ${WATCH_PATHS[*]} (parent guard: $([[ -n "$parent_pid" ]] && echo on || echo off))"
	# shellcheck disable=SC2086
	inotifywait -m -r -e close_write,moved_to,moved_from,create,delete \
		"${WATCH_PATHS[@]}" |
		while read -r watched events file; do
			event_line="${watched} ${events} ${file}"
			case "$watched" in
				"$HOME/.opencode/bin/"*)
					# same filter as the former --include 'opencode$'
					[[ "$file" == *opencode ]] || continue
					printf 'OpenCode runtime binary event: %s\n' "$event_line" |
						systemd-cat -t opencode-patch-watcher -p info
					sleep 5
					if result=$("$VERIFY_SCRIPT" 2>&1); then
						printf 'OpenCode patch verification passed after event: %s\n%s\n' "$event_line" "$result" |
							systemd-cat -t opencode-patch-watcher -p info
					else
						printf 'OpenCode patch verification failed after event: %s\n%s\n' "$event_line" "$result" |
							systemd-cat -t opencode-patch-watcher -p err
					fi
					;;
				"$OMO_DIST"|"$OMO_DIST"/*)
					case "$file" in
						# *.pre-* / *.tmp* are legitimate patch-flow backups: log-only, never alert.
						*.pre-*|*.tmp*)
							printf 'OMO dist patch-flow backup write (log-only): %s\n' "$event_line" |
								systemd-cat -t opencode-patch-watcher -p info
							;;
						*)
							printf 'OMO dist write outside verified patch flow (suspect; expected only during rebuild+reapply via patch-tracker/update-to-latest): %s\n' "$event_line" |
								systemd-cat -t opencode-patch-watcher -p warning
							;;
					esac
					;;
			esac
		done || true

	# inotifywait exited (watched tree deleted or error) — re-arm.
	[[ -n "$parent_pid" ]] && kill "$parent_pid" 2>/dev/null || true
	wait "$parent_pid" 2>/dev/null || true
	log warning "inotifywait exited (watched tree deleted or error); re-arming in 10s"
	sleep 10
done
