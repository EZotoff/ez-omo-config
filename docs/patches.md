# Patch Index

Thin index over the authoritative patch registry. Every entry lives in [.sisyphus/patches/](../.sisyphus/patches/) with verification patterns, reapply instructions, and durable-alternative status. The same registry is tabulated with verification commands in [MANIFEST.md](../MANIFEST.md#patch-registry).

- **Status values**: `active` (applied to a live dependency) · `retired` / `deprecated` (no longer applied) · `superseded` / `upstreamed` (obsoleted by upstream) · `rolled_back` (reverted as ineffective).
- **runtime_effective** (shown only where tracked): whether the patched behavior has been *observed* on the live surface — pattern-presence in a binary is not effectiveness. `-` = not applicable.

## OpenCode binary patches (live binary v1.18.5, rebuilt via `update-to-latest`)

| Patch | Status | runtime_effective | Entry |
|---|---|---|---|
| `opencode--command-hook-cancellation` — no-LLM cancellation for `/session-id`, `/session-info`, `/vscode` | active | true | [entry](../.sisyphus/patches/opencode--command-hook-cancellation.md) |
| `opencode--commit-policy-unblock` | active | true | [entry](../.sisyphus/patches/opencode--commit-policy-unblock.md) |
| `opencode--link-click-wrapped-osc8` — TUI link-click workaround for Alacritty wrapped-OSC-8 regression | active | true | [entry](../.sisyphus/patches/opencode--link-click-wrapped-osc8.md) |
| `opencode--turn-summary-timestamp` — 24h+date turn-summary format | active | true | [entry](../.sisyphus/patches/opencode--turn-summary-timestamp.md) |
| `opencode--sse-directory-filter-removal` — needs reimplementation for rewritten `event.ts` | active | false | [entry](../.sisyphus/patches/opencode--sse-directory-filter-removal.md) |
| `opencode--tui-pinned-session-race` — v2 compiled in; awaiting live pin+prune verification | active | false | [entry](../.sisyphus/patches/opencode--tui-pinned-session-race.md) |

## OMO fork patches (fork base v4.19.2 at `~/oh-my-openagent-v4.19.2`)

Source patches (carried as fork commits) and dist-level patches (applied to the built `dist/index.js` bundle) are distinguished in each entry's `target_file`/reapply section.

| Patch | Status | runtime_effective | Entry |
|---|---|---|---|
| `omo--retries-before-fallback` — `runtime_fallback.retries_before_fallback` knob (fork commit 49f6728) | active | true | [entry](../.sisyphus/patches/omo--retries-before-fallback.md) |
| `omo--resume-skip-keep-running` — busy-session resume keeps background task running (fork commit 8b883adab) | active | false | [entry](../.sisyphus/patches/omo--resume-skip-keep-running.md) |
| `omo--model-less-spawn-fallback` — background spawn model default | active | true | [entry](../.sisyphus/patches/omo--model-less-spawn-fallback.md) |
| `omo--lookat-fallback-patience` — 60s re-poll for fallback answers (dist) | active | true | [entry](../.sisyphus/patches/omo--lookat-fallback-patience.md) |
| `omo--durable-log-path` — logs survive serve restarts (dist) | active | true | [entry](../.sisyphus/patches/omo--durable-log-path.md) |
| `omo--fallback-toast-origin` — toasts name originating agent/session (dist) | active | false | [entry](../.sisyphus/patches/omo--fallback-toast-origin.md) |
| `oh-my-openagent--start-work-worktree-teardown` — `/start-work` worktree reclaim step | active | true | [entry](../.sisyphus/patches/oh-my-openagent--start-work-worktree-teardown.md) |
| `oh-my-openagent--context-overflow-max-token-error` | active | — | [entry](../.sisyphus/patches/oh-my-openagent--context-overflow-max-token-error.md) |
| `oh-my-openagent--external-system-premise-discipline` (config-layer) | active | — | [entry](../.sisyphus/patches/oh-my-openagent--external-system-premise-discipline.md) |
| `omo--auto-slash-command-duplicate-user-args` (dist) | active | — | [entry](../.sisyphus/patches/omo--auto-slash-command-duplicate-user-args.md) |
| `omo--clean-agent-display-names` (dist) | active | — | [entry](../.sisyphus/patches/omo--clean-agent-display-names.md) |
| `omo--commit-policy-alignment` | active | — | [entry](../.sisyphus/patches/omo--commit-policy-alignment.md) |
| `omo--exclude-selected-auto-slash-commands` | active | — | [entry](../.sisyphus/patches/omo--exclude-selected-auto-slash-commands.md) |
| `omo--runtime-fallback-checktoolstate-bypass` (fork port of upstream PR #5357) | active | — | [entry](../.sisyphus/patches/omo--runtime-fallback-checktoolstate-bypass.md) |
| `omo--sync-delegate-task-result-bloat` (config-level prompt_append) | active | — | [entry](../.sisyphus/patches/omo--sync-delegate-task-result-bloat.md) |
| `omo--ultrawork-subagent-guard` — default-mode ultrawork injection skips subagent/non-main sessions (fork commits 52a175587 + 753602683) | active | true | [entry](../.sisyphus/patches/omo--ultrawork-subagent-guard.md) |
| `ez-omo-config--commit-policy-override` | deprecated | — | [entry](../.sisyphus/patches/ez-omo-config--commit-policy-override.md) |
| `omo--glm-preemptive-compaction-threshold` | deprecated | — | [entry](../.sisyphus/patches/omo--glm-preemptive-compaction-threshold.md) |
| `omo--boulder-worktree-authoritative-state` | superseded | — | [entry](../.sisyphus/patches/omo--boulder-worktree-authoritative-state.md) |
| `omo--remove-activity-stagnation-bypass` | upstreamed | — | [entry](../.sisyphus/patches/omo--remove-activity-stagnation-bypass.md) |
| `omo--parent-wake-sync-mode-for-tui-render` | rolled_back | — | [entry](../.sisyphus/patches/omo--parent-wake-sync-mode-for-tui-render.md) |

## Retired DCP patches (DCP removed 2026-06-23)

`opencode-dcp--bounded-range-archive-mode`, `opencode-dcp--byte-budget`, `opencode-dcp--compress-tool-prompt-contract` — all retired. Reference: [docs/history/dcp-byte-budget.md](history/dcp-byte-budget.md).

## Maintenance

- Schema and drift gates: `tests/test_patch_entries.sh` (frontmatter completeness), `tests/test_patch_versions.sh` (version drift after upgrades).
- Verifier: `scripts/verify-live-patches.sh` (also runs every 30 min via `opencode-patch-integrity-check.timer`).
- Watcher: `scripts/watch-runtime-patches.sh` (`opencode-patch-watcher.service`) — inotify (`close_write,moved_to,moved_from,create,delete`) on `~/.opencode/bin/` (files matching `opencode$`) and `$HOME/oh-my-openagent-v4.19.2/dist` (recursive). dist writes are expected ONLY during verified rebuild+reapply flows (patch-tracker/update-to-latest); any other dist write is suspect. `*.pre-*` / `*.tmp*` dist writes are legitimate patch-flow backups and are logged informationally only — never alerted.
- Failure alerting: if the periodic check fails, `OnFailure=opencode-integrity-alert.service` fires — it writes a marker (`~/.local/state/opencode/patch-integrity.alert`), logs `INTEGRITY-ALERT: patch verification failing` to the journal, and sends a critical `notify-send` (guarded for headless rigs). Bridges the 2026-09-08 4+-hour silent-failure gap.
- After ANY binary/OMO upgrade, all active patches must be reconciled in the same commit — see [AGENTS.md](../AGENTS.md).
