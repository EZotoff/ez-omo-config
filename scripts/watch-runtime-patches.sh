#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${EZ_OMO_CONFIG_REPO:-$HOME/ez-omo-config}"
VERIFY_SCRIPT="$REPO_ROOT/scripts/verify-live-patches.sh"

inotifywait -m -e close_write,moved_to,moved_from,create,delete \
  --include 'opencode$' "$HOME/.opencode/bin/" |
  while IFS= read -r event; do
    printf 'OpenCode runtime binary event: %s\n' "$event" |
      systemd-cat -t opencode-patch-watcher -p info
    sleep 5
    if result=$("$VERIFY_SCRIPT" 2>&1); then
      printf 'OpenCode patch verification passed after event: %s\n%s\n' "$event" "$result" |
        systemd-cat -t opencode-patch-watcher -p info
    else
      printf 'OpenCode patch verification failed after event: %s\n%s\n' "$event" "$result" |
        systemd-cat -t opencode-patch-watcher -p err
    fi
  done
