#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${EZ_OMO_CONFIG_REPO:-$HOME/ez-omo-config}"
VERIFY_SCRIPT="$REPO_ROOT/scripts/verify-live-patches.sh"
# OMO fork dist (separate deployable runtime bundle) — watch writes here too.
OMO_DIST="${OMO_FORK_DIST:-$HOME/oh-my-openagent-v4.19.2/dist}"

WATCH_PATHS=("$HOME/.opencode/bin/")
if [[ -d "$OMO_DIST" ]]; then
  WATCH_PATHS+=("$OMO_DIST")
else
  printf 'OMO fork dist not found, watching OpenCode bin only: %s\n' "$OMO_DIST" |
    systemd-cat -t opencode-patch-watcher -p warning
fi

# -r: dist/ has subdirectories; supported by inotify-tools on this host.
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
  done
