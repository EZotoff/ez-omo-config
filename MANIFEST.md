# ez-omo-config Artifact Manifest

Complete inventory of repo-managed artifacts for ez-omo-config repository scaffold.

> **Platform support**: artifacts install on Linux (native), macOS (native, Homebrew Bash 4.3+ required), and Windows via WSL. Install targets are identical across all three (`$HOME`-relative). See `install.sh` `detect_os()` and `README.md` "Platform Support". Cross-platform CI: `.github/workflows/cross-platform.yml`.

> **Counting semantics** (README category table follows the same rules): counts are tracked files per top-level directory (`git ls-files <dir> | wc -l`); a multi-file module directory (e.g. `aspect-dynamics/`, `supervisor/`, `kdco-primitives/`) may appear as one logical row in prose tables but its files count individually in category counts. The per-artifact table below is the single source of truth for paths, install targets, and statuses — README carries the category summary only.

## Artifacts Table

| # | Artifact Name | Source Path | Repo Path | Install Target | Dependency Cluster | Status |
|---|---|---|---|---|---|---|
| 1 | models-preset.md | `~/.config/opencode/command/` | `commands/` | `$HOME/.config/opencode/command/` | Slash Commands | Required |
| 1b | vscode.md | `~/.config/opencode/command/` | `commands/` | `$HOME/.config/opencode/command/` | Slash Commands | Required |
| 1c | session-id.md | `~/.config/opencode/command/` | `commands/` | `$HOME/.config/opencode/command/` | Slash Commands | Required |
| 1d | session-info.md | `~/.config/opencode/command/` | `commands/` | `$HOME/.config/opencode/command/` | Slash Commands | Required |
| 1e | handoff.md | `~/.config/opencode/command/` | `commands/` | `$HOME/.config/opencode/command/` | Slash Commands (handoff emission) | Optional |
| 1f | resume-from.md | `~/.config/opencode/command/` | `commands/` | `$HOME/.config/opencode/command/` | Slash Commands (handoff resume + decision checkpoint) | Optional |
| 1g | design-review.md | `~/.config/opencode/command/` | `commands/` | `$HOME/.config/opencode/command/` | Slash Commands (review preset) | Optional |
| 1h | option-compare.md | `~/.config/opencode/command/` | `commands/` | `$HOME/.config/opencode/command/` | Slash Commands (review preset) | Optional |
| 1i | dual-review.md | `~/.config/opencode/command/` | `commands/` | `$HOME/.config/opencode/command/` | Slash Commands (review preset) | Optional |
| 1j | escalate.md | `~/.config/opencode/command/` | `commands/` | `$HOME/.config/opencode/command/` | Slash Commands (review preset) | Optional |
| 2 | opencode.json | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Core Config | Required |
| 3 | opencode.jsonc | `~/.opencode/` | `configs/opencode/` | `$HOME/.opencode/` | Core Config | Required |
| 3b | dcp.jsonc.retired | `configs/opencode/` | `configs/opencode/` | (not installed) | RETIRED 2026-06-23 — DCP retired; Magic Context currently disabled | Archived |
| 4 | provider-connect-retry.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Core Config | Required |
| 4b | retry-errors.json | `~/.config/opencode/` | `configs/` | `$HOME/.config/opencode/` | Core Config | Required |
| 4c | worktree.jsonc | `~/.opencode/` | `configs/opencode/` | `$HOME/.opencode/` | Worktree Config | Required |
| 4d | aspect-dynamics.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Aspect Dynamics | Optional |
| 4e | aspect-dynamics/config.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Aspect Dynamics | Optional |
| 4f | aspect-dynamics/context.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Aspect Dynamics | Optional |
| 4g | aspect-dynamics/heuristics.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Aspect Dynamics | Optional |
| 4h | aspect-dynamics/session-state.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Aspect Dynamics | Optional |
| 4i | aspect-dynamics/sets.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Aspect Dynamics | Optional |
| 4j | aspect-dynamics/nudge.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Aspect Dynamics | Optional |
| 4k | aspect-dynamics/logging.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Aspect Dynamics | Optional |
| 4l | aspect-dynamics/sets/emotions-v1.json | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Aspect Dynamics | Optional |
| 4m | aspect-dynamics/sets/emotions-v2.json | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Aspect Dynamics | Optional |
| 4n | output-shaper.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Output Shaper | Optional |
| 4o | output-shaper/config.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Output Shaper | Optional |
| 4p | output-shaper/logging.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Output Shaper | Optional |
| 4q | output-shaper/model-gating.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Output Shaper | Optional |
| 4r | output-shaper/resume-detector.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Output Shaper | Optional |
| 4s | skill-nudger.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Skill Nudger | Optional |
| 4t | skill-nudger/config.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Skill Nudger | Optional |
| 4u | skill-nudger/logging.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Skill Nudger | Optional |
| 4v | skill-nudger/catalog.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Skill Nudger | Optional |
| 4w | skill-nudger/signals.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Skill Nudger | Optional |
| 4x | skill-nudger/state.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Skill Nudger | Optional |
| 4y | skill-nudger/nudge.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Skill Nudger | Optional |
| 4z | agent-default-guard.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Agent Default Guard (rewrites client-sent `build` agent to pinned `default_agent`; OC Beacon mitigation) | Required |
| 4ab | live-config-guard.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Live Config Guard (blocks write-intent ops on the live OpenCode/OMO config surface from sessions outside the config repo — 2026-09-10/12 sandbox-leak incidents; harness `tests/live-config-guard/`) | Required |
| 4aa | agent/document-writer.md | `~/.config/opencode/agent/` | `configs/opencode/agent/` | `$HOME/.config/opencode/agent/` | Opencode-native agent file for custom `document-writer` agent (frontmatter + body = system prompt; `agents.<name>.prompt` in oh-my-openagent.json is builtin-only/dead for custom names) | Required |
| 5 | oh-my-openagent.json | `~/.config/opencode/` | `configs/oh-my-openagent/` | `$HOME/.config/opencode/` | OMO Config | Required |
| 5b | supervisor.json | `~/.config/opencode-supervisor/` | `configs/opencode-supervisor/` | `$HOME/.config/opencode-supervisor/` | Project Supervisor P0 | Optional |
| 5c | supervisor/ | (repo only) | `supervisor/` | (executed from checkout) | Project Supervisor P0 | Optional |
| 6 | worktree.ts | `~/.opencode/plugin/` | `plugins/` | `$HOME/.opencode/plugin/` | Worktree Plugin | Required |
| 7 | worktree/state.ts | `~/.opencode/plugin/worktree/` | `plugins/worktree/` | `$HOME/.opencode/plugin/worktree/` | Worktree Plugin | Required |
| 8 | worktree/terminal.ts | `~/.opencode/plugin/worktree/` | `plugins/worktree/` | `$HOME/.opencode/plugin/worktree/` | Worktree Plugin | Required |
| 9 | git-safety.ts | `~/.opencode/plugin/` | `plugins/` | `$HOME/.opencode/plugin/` | Git Safety | Required |
| 10 | review-enforcer.ts | `~/.opencode/plugin/` | `plugins/` | `$HOME/.opencode/plugin/` | Review Protocol | Required |
| 10a | review-enforcer/helpers.ts | `~/.opencode/plugin/review-enforcer/` | `plugins/review-enforcer/` | `$HOME/.opencode/plugin/review-enforcer/` | Pure gating helpers (kept out of the plugin entry — opencode's loader calls every function export as a plugin constructor; 2026-09-08 incident) | Required |
| 10b | auto-checkpoint.ts | `~/.opencode/plugin/` | `plugins/` | `$HOME/.opencode/plugin/` | Checkpoint Plugin (opt-in runtime) | Required |
| 11 | kdco-primitives/ | `~/.opencode/plugin/kdco-primitives/` | `plugins/kdco-primitives/` | `$HOME/.opencode/plugin/kdco-primitives/` | KDCO Library | Required |
| 11b | vscode.ts | `~/.opencode/plugin/` | `plugins/` | `$HOME/.opencode/plugin/` | VS Code Launcher | Optional |
| 11c | session-id.ts | `~/.opencode/plugin/` | `plugins/` | `$HOME/.opencode/plugin/` | Session ID Clipboard | Required |
| 11d | session-info.ts | `~/.opencode/plugin/` | `plugins/` | `$HOME/.opencode/plugin/` | Session Info Clipboard | Required |
| 11h | clickable-links.ts | `~/.opencode/plugin/` | `plugins/` | `$HOME/.opencode/plugin/` | Clickable File Links (TUI) | Required |
| 12 | wisdom/ | `~/.config/opencode/skills/wisdom/` | `skills/wisdom/` | `$HOME/.config/opencode/skills/` | Wisdom System | Required |
| 12b | patch-tracker/ | `~/.config/opencode/skills/patch-tracker/` | `skills/patch-tracker/` | `$HOME/.config/opencode/skills/` | Patch Registry | Optional |
| 12c | register-retry-error/ | `~/.config/opencode/skills/register-retry-error/` | `skills/register-retry-error/` | `$HOME/.config/opencode/skills/` | Retry Error Registry | Optional |
| 12d | session-id/ | `~/.config/opencode/skills/session-id/` | `skills/session-id/` | `$HOME/.config/opencode/skills/` | Session ID Clipboard (skill form) | Optional |
| 12e | debate/ | `~/.config/opencode/skills/debate/` | `skills/debate/` | `$HOME/.config/opencode/skills/` | Structured Adversarial Analysis | Optional |
| 12f | reader-report/ | `~/.config/opencode/skills/reader-report/` | `skills/reader-report/` | `$HOME/.config/opencode/skills/` | Reader-First Report Writing | Optional |
| 12g | computer-use/ | `~/.config/opencode/skills/computer-use/` | `skills/computer-use/` | `$HOME/.config/opencode/skills/` | OS Computer Use (cua-driver MCP) | Optional |
| 13 | atlas-review-handler/ | `~/.config/opencode/skills/atlas-review-handler/` | `skills/atlas-review-handler/` | `$HOME/.config/opencode/skills/` | Review Orchestration | Required |
| 14 | review-protocol/ | `~/.config/opencode/skills/review-protocol/` | `skills/review-protocol/` | `$HOME/.config/opencode/skills/` | Review Protocol | Required |
| 16 | deployment/ | `~/.config/opencode/skills/deployment/` | `skills/deployment/` | `$HOME/.config/opencode/skills/` | Deployment | Optional |
| 16b | AGENTS.md (global) | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Atomic: Deployment + Core Config | Required |
| 28 | merge-agent/ | `~/.config/opencode/skills/merge-agent/` | `skills/merge-agent/` | `$HOME/.config/opencode/skills/` | Safe Merge | Optional |
| 29 | parallel-dev/ | `~/.config/opencode/skills/parallel-dev/` | `skills/parallel-dev/` | `$HOME/.config/opencode/skills/` | Parallel Dev | Optional |
| 30b | update-to-latest/ | `~/.config/opencode/skills/update-to-latest/` | `skills/update-to-latest/` | `$HOME/.config/opencode/skills/` | Update Pipeline | Optional |
| 30c | patch-opencode/ | `~/.config/opencode/skills/patch-opencode/` | `skills/patch-opencode/` | `$HOME/.config/opencode/skills/` | OpenCode Binary Patching | Optional |
| 30d | postmortem-policy/ | `~/.config/opencode/skills/postmortem-policy/` | `skills/postmortem-policy/` | `$HOME/.config/opencode/skills/` | Incident→Policy (approval-gated) | Optional |
| 30e | handoff-relay/ | `~/.config/opencode/skills/handoff-relay/` | `skills/handoff-relay/` | `$HOME/.config/opencode/skills/` | Session Handoff Emit/Resume | Optional |
| 30f | verify-built/ | `~/.config/opencode/skills/verify-built/` | `skills/verify-built/` | `$HOME/.config/opencode/skills/` | Stage-1 Alignment Verification | Optional |
| 30g | inbound-triage/ | `~/.config/opencode/skills/inbound-triage/` | `skills/inbound-triage/` | `$HOME/.config/opencode/skills/` | Inbox Triage (selection-gated) | Optional |
| 30h | add-provider/ (project-scoped) | (project-local) | `.opencode/skill/add-provider/` | not installed — OpenCode loads it from the repo when sessions run in this project | Provider/Model Onboarding (checklist + audit) | Required |
| 18 | wisdom-common.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 19 | wisdom-search.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 20 | wisdom-write.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 21 | wisdom-sync.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 22 | wisdom-archive.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 23 | wisdom-delete.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 24 | wisdom-edit.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 25 | wisdom-gc.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 26 | wisdom-merge.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 26a | wisdom-observe.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Observability | Required |
| 26b | wisdom-publish.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 26c | wisdom-closeout.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 26d | wisdom-nominate.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 26e | wisdom-migrate.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 26f | wisdom-restore.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 26g | manifest-write.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 26h | knowledge-constants.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 31 | worktree-post-create.sh | `~/.opencode/scripts/` | `scripts/` | `$HOME/.opencode/scripts/` | Worktree Hooks | Required |
| 32 | worktree-pre-delete.sh | `~/.opencode/scripts/` | `scripts/` | `$HOME/.opencode/scripts/` | Worktree Hooks | Required |
| 49 | verify-live-deployment.sh | `~/.sisyphus/scripts/` | `scripts/` | `$HOME/.sisyphus/scripts/` | Live Deployment Verification | Required |
| 27 | ocx.jsonc | `~/.opencode/` | `extras/` | `$HOME/.opencode/` | Registry | Optional |
| 28 | test_live_deployment_contract.sh | (repo only) | `tests/` | (repo only) | Live Deployment Verification | Required |
| 28a | test_dcp_bounded_range.sh | (repo only) | `tests/` | (repo only) | RETIRED 2026-06-23 — DCP Verification | Archived (`.retired`) |
| 28b | test_dcp_startup_warning.sh | (repo only) | `tests/` | (repo only) | RETIRED 2026-06-23 — DCP Verification | Archived (`.retired`) |
| 28d | test_review_enforcer_completion_instruction.sh | (repo only) | `tests/` | (repo only) | Review Enforcer Verification | Required |
| 28e | test_prometheus_planning_contract.sh | (repo only) | `tests/` | (repo only) | Prometheus Planning Contract | Required |
| 28f | test_openai_provider.sh | (repo only) | `tests/` | (repo only) | Codex Provider Verification | Required |
| 28g | test_update_to_latest_skill.sh | (repo only) | `tests/` | (repo only) | Update Pipeline Verification | Required |
| 28h | test_dcp_payload_budget.sh | (repo only) | `tests/` | (repo only) | RETIRED 2026-06-23 — DCP Byte-Budget Verification | Archived (`.retired`) |
| 28i | test_computer_use_skill.sh | (repo only) | `tests/` | (repo only) | Computer-Use Skill + Live MCP Safety Contract | Required |
| 28j | test_worktree_reclaim.sh | (repo only) | `tests/` | (repo only) | Worktree Reclaim Contract (worktree_delete target semantics) | Required |
| 28k | test_default_agent_pin.sh | (repo only) | `tests/` | (repo only) | Default-Agent Pin (`default_agent: Sisyphus` in opencode.json; anti-regression for the 2026-09-05 OC Beacon build-default incident) | Required |
| 28l | test_agent_default_guard.sh | (repo only) | `tests/` | (repo only) | Agent Default Guard plugin contract (build→default rewrite, fail-open paths, registry cache) | Required |
| 28m | test_plugin_console_hygiene.sh | (repo only) | `tests/` | (repo only) | Plugin Console Hygiene (no console.* in config-layer plugins and plugin entry files; anti-regression for the 2026-09-06 stdout spam) | Required |
| 29 | live-deployment-verification.md | (repo only) | `docs/` | (repo only) | Documentation | Required |
| 29b | patches.md | (repo only) | `docs/` | (repo only) | Documentation — patch index (thin index over `.sisyphus/patches/`) | Required |
| 30 | dcp-byte-budget.md | (repo only) | `docs/history/` | (repo only) | RETIRED 2026-06-23 — DCP byte-budget reference (historical) | Archived |
| 30b | history/ | (repo only) | `docs/history/` | (repo only) | Dated snapshots: incidents, retired DCP, update migrations, architecture reviews | Archived |
| 53 | `verify-live-patches.sh` | `~/.sisyphus/scripts/` | `scripts/` | `$HOME/.sisyphus/scripts/` | Rewritten patch verifier with all 7 structural fixes | Required |
| 54 | `watch-runtime-patches.sh` | `~/.sisyphus/scripts/` | `scripts/` | `$HOME/.sisyphus/scripts/` | inotify watcher for runtime binary integrity (OpenCode bin + OMO fork dist, recursive; `*.pre-*`/`*.tmp*` dist writes log-only) | Required |
| 54a | `integrity-alert.sh` | `~/.sisyphus/scripts/` | `scripts/` | `$HOME/.sisyphus/scripts/` | OnFailure alert writer (journal `INTEGRITY-ALERT` line + `~/.local/state/opencode/patch-integrity.alert` marker + guarded notify-send) for integrity-check failures | Optional |
| 55 | `opencode-patch-watcher.service` | `~/.config/systemd/user/` | `systemd/user/` | `$HOME/.config/systemd/user/` | systemd user service for watcher | Optional |
| 56 | `opencode-patch-integrity-check.service` | `~/.config/systemd/user/` | `systemd/user/` | `$HOME/.config/systemd/user/` | Periodic integrity check service (verify-live-patches + check-live-config-drift) | Optional |
| 57 | `opencode-patch-integrity-check.timer` | `~/.config/systemd/user/` | `systemd/user/` | `$HOME/.config/systemd/user/` | 30-minute periodic timer | Optional |
| 58 | `run_regressions.sh` | (repo only) | `tests/` | (repo only) | Regression corpus harness | Required |
| 59 | `regressions/` | (repo only) | `tests/` | (repo only) | 23 paired regression tests (46 files total) | Required |
| 59a | `harness.ts` | (repo only) | `tests/review-enforcer/` | (repo only) | Behavioral harness for review-enforcer gating (drives regression pairs 014/015/016; helpers module import since 018) | Required |
| 59b | `harness.mjs` | (repo only) | `tests/worktree-reclaim/` | (repo only) | Integration harness for worktree reclaim: target resolution, merged-delete, unmerged-keep, dirty-salvage, no-empty-snapshot | Required |
| 60 | `test_patch_entries.sh` | (repo only) | `tests/` | (repo only) | Patch-entry schema gate (frontmatter completeness: surfaces, runtime_effective, target_file) | Required |
| 61 | `test_patch_versions.sh` | (repo only) | `tests/` | (repo only) | Patch version drift gate after binary/OMO upgrades | Required |
| 63 | `derive-flare-chat-template.py` | (repo only) | `scripts/` | (repo only) | FLARE-4B chat-template generator (PARKED with `flare-serve.service`) | Optional |
| 62 | `flare-serve.service` | `~/.config/systemd/user/` | `systemd/user/` | `$HOME/.config/systemd/user/` | FLARE-4B local SGLang server (PARKED 2026-08-15 — unit disabled, provider removed from opencode.json; port 18200) | Optional |
| 62b | `opencode-supervisor.service` | `~/.config/systemd/user/` | `systemd/user/` | `$HOME/.config/systemd/user/` | Project Supervisor P0 shadow observer | Optional |
| 62c | `test_supervisor_config.sh` | (repo only) | `tests/` | (repo only) | Project Supervisor static contract | Required |
| 62d | `opencode-interactive.service` | `~/.config/systemd/user/` | `systemd/user/` | `$HOME/.config/systemd/user/` | OpenCode interactive attach daemon (127.0.0.1:3030, basic auth via serve-interactive.env; OC Beacon mobile client via tailscale serve TLS) | Optional |
| 62e | `opencode-integrity-alert.service` | `~/.config/systemd/user/` | `systemd/user/` | `$HOME/.config/systemd/user/` | OnFailure alert unit — fired when `opencode-patch-integrity-check.service` fails; journal + marker + desktop notification | Optional |
| 62f | `opencode-interactive-keeper.service` | `~/.config/systemd/user/` | `systemd/user/` | `$HOME/.config/systemd/user/` | Oneshot keeper — auto-starts/restarts `opencode-interactive.service` when 127.0.0.1:3030 is unreachable (two-probe guard vs load-spike false positives; covers the explicit-stop failure class that `Restart=` cannot) | Optional |
| 62g | `opencode-interactive-keeper.timer` | `~/.config/systemd/user/` | `systemd/user/` | `$HOME/.config/systemd/user/` | 1-minute keeper probe cadence (OnBootSec=1min; tightened from 2 min after the 2026-09-14 23:11 stop left an 80s dead window) | Optional |
| 63a | `smoke-boot-check.sh` | (repo only) | `scripts/` | (repo only) | Fresh-boot smoke gate for cutovers: throws away an `opencode run --print-logs` boot, asserts 0 plugin-load errors, 0 agent-not-found, agent-attributed stream + loop-exit lines, rc=0, serve-set unchanged (patterns-in-file ≠ bootable, 2026-09-08 incident) | Required |
| 63b | `check-live-config-drift.sh` | (repo only) | `scripts/` | (repo only) | Live-config drift check: fails when `configs/` has uncommitted changes; second `ExecStart` of `opencode-patch-integrity-check.service` (30-min cadence → `opencode-integrity-alert.service`). Collapses the restart-masked damage window from the 2026-09-10/12 incidents to ≤30 min | Required |
| 63c | `opencode-daemon-keeper.sh` | (repo only) | `scripts/` | (repo only) | Probe + recover script for the interactive daemon; `ExecStart` of `opencode-interactive-keeper.service` (1-min cadence). Recovers the agent-killed-daemon failure mode (2026-09-13/14 incidents) within ≤1 min | Required |
| 63d | `perf-review/` | (repo only) | `scripts/perf-review/` | (repo only) | Server-plugin performance metrics and log-census tooling | Required |
| 63e | `perf-review/` | (repo only) | `tests/perf-review/` | (repo only) | Server-plugin performance benchmark harnesses | Required |

## Directory Structure

```
ez-omo-config/
├── commands/
│   └── models-preset.md    # Slash command prompt for model tables + consistency scan
│   └── vscode.md           # VS Code launcher (handled by plugin, no LLM)
│   └── session-id.md       # Session ID clipboard (handled by plugin, no LLM)
│   └── session-info.md     # Session info clipboard (handled by plugin, no LLM)
├── configs/
│   ├── opencode/           # Main OpenCode configuration (4 files + aspect-dynamics + output-shaper)
│   ├── oh-my-openagent/     # Oh-My-OpenAgent configuration (1 file)
│   ├── opencode-supervisor/  # Project Supervisor P0 config and reference
│   └── retry-errors.json    # Retry registry for provider-connect-retry plugin
├── supervisor/              # Bun + strict TypeScript P0 observer service and tests
├── plugins/
│   ├── worktree.ts         # Worktree plugin core
│   ├── auto-checkpoint.ts  # Semantic session-scoped checkpoint plugin
│   ├── git-safety.ts       # Git safety protocol plugin
│   ├── review-enforcer.ts  # Review enforcer plugin (exports ONLY the plugin fn — loader contract)
│   ├── review-enforcer/    # Pure gating helpers (test-importable; not on the loader surface)
│   ├── vscode.ts           # VS Code launcher plugin (intercepts /vscode command)
│   ├── session-id.ts       # Session ID clipboard plugin (intercepts /session-id command)
│   ├── session-info.ts     # Session info clipboard plugin (intercepts /session-info command)
│   ├── clickable-links.ts  # System-prompt injection: file refs as clickable markdown links in TUI
│   ├── worktree/           # Worktree subdirectory (state.ts, terminal.ts)
│   └── kdco-primitives/    # Shared library
├── skills/
│   ├── wisdom/             # Wisdom propagation skill (primary runtime memory)
│   ├── patch-tracker/      # Patch registry CRUD and post-update verification
│   ├── register-retry-error/ # Retryable error pattern registration skill
│   ├── session-id/         # Session ID clipboard (skill form, mirrors /session-id plugin)
│   ├── atlas-review-handler/ # Review orchestration skill
│   ├── review-protocol/    # Review protocol skill
│   ├── deployment/         # Deployment helper skill
│   ├── merge-agent/        # Safe branch merging with guardrails
│   ├── parallel-dev/       # Multi-agent orchestration with decision framework
│   ├── update-to-latest/   # Safe OpenCode/OMO update pipeline with approval gate
│   ├── patch-opencode/     # Minimal-fix procedure for the live OpenCode binary
│   └── reader-report/     # Reader-first writing for reports/summaries/briefs
├── scripts/
│   ├── wisdom/             # Wisdom propagation scripts (10 files)
│   ├── worktree/           # Worktree lifecycle hooks (2 files)
│   ├── verify-live-patches.sh # Runtime-resolved tracked-patch verifier
│   └── watch-runtime-patches.sh # Runtime binary + OMO dist inotify watcher
├── systemd/user/           # Patch integrity units, Project Supervisor, interactive-daemon keeper
├── extras/                 # Extra configurations (ocx.jsonc)
├── docs/                   # Active documentation (configs, plugins, skills, wisdom, patches, verification, observability, compatibility debt, worktree state, OMO reference)
│   ├── patches.md            # Patch index over .sisyphus/patches/
│   └── history/              # Dated snapshots: incidents, retired DCP, update migrations, architecture reviews
│   ├── configs.md             # Config-layer system documentation with Non-Wisdom Observability Contract
│   ├── COMPATIBILITY-DEBT.md  # Shim inventory with deletion criteria and removal milestones
│   ├── live-deployment-verification.md  # Live Deployment Verification Gate documentation
├── tests/                  # Bash verification suite, 23-pair regression corpus, and harnesses
├── scripts/                # Wisdom scripts, worktree scripts, and audit utilities
│   └── audit-wisdom-first.sh  # Validates no contradictory dual-system language remains
├── install.sh              # Bootstrap installer
├── README.md               # Project overview and installation guide
├── LICENSE                 # License file
└── MANIFEST.md             # This file
```

## Artifact Summary

- **Total Artifacts**: repo-managed OpenCode/OMO commands, configs, plugins, skills, scripts, tests, docs, extras, and Docker templates.
- **Commands**: 10 slash command prompts (model presets, session utilities, handoff emit/resume, four review presets)
- **Core Configs**: existing OpenCode/OMO configs plus the Project Supervisor P0 `supervisor.json`. DCP retired 2026-06-23; see `dcp.jsonc.retired` for historical reference.
- **Plugins**: worktree, git safety, review, checkpoint, session clipboard, clickable-link, worktree support, and shared primitive files.
- **Skills**: managed skill directories. `playwright`, `frontend-ui-ux`, and `github-triage` ship with OMO upstream and are intentionally NOT vendored here. `worktree-coordinator` removed (was a doc index, not a skill). `knowledge/` removed (deprecated Wisdom compat shim).
- **Scripts**: wisdom shell scripts, worktree hooks, live deployment verification, the rewritten patch verifier, the runtime watcher, smoke-boot gate, and Python operator helpers.
- **Systemd**: 7 user units — patch watcher, integrity-check service + timer, integrity-failure alert, Project Supervisor, interactive attach daemon, and the parked FLARE-4B server.
- **Tests**: active repo verification scripts (109 tracked files), the 25-pair regression corpus (50 files), their harnesses, and retired DCP test scripts (`.retired` suffix, kept for historical reference).
- **Extras**: 1 file (ocx.jsonc)

### External Artifacts (Not in install.sh)

| # | Artifact | Path | Purpose | Install Command |
|---|----------|------|---------|-----------------|
| E1 | `auth.json.example` | `auth.json.example` | Template for `~/.local/share/opencode/auth.json`: 9 provider entries (7 API-key + 2 OAuth) covering the 11 enabled providers | `cp auth.json.example ~/.local/share/opencode/auth.json` |
| E2 | `check-prerequisites.sh` | `scripts/check-prerequisites.sh` | Verifies OpenCode CLI, bun, OMO npm cache, config files, local plugins, API keys, skills, Docker (optional), and patch docs | `./scripts/check-prerequisites.sh` |
| E3 | OpenCode CLI | external | Core AI coding assistant runtime | [opencode.ai](https://opencode.ai) |
| E4 | bun | external | JavaScript runtime for TypeScript plugin loading | [bun.sh](https://bun.sh) |
| E5 | `oh-my-openagent-v4.19.2` | `$HOME/oh-my-openagent-v4.19.2` (published fork of upstream **v4.19.2**: [EZotoff/oh-my-openagent](https://github.com/EZotoff/oh-my-openagent), tag `v4.19.2-patches.1`) | Canonical OMO runtime source carrying tracked local patches (index: `docs/patches.md`); replaces mutable npm `@latest` resolution | `git clone -b v4.19.2-patches.1 https://github.com/EZotoff/oh-my-openagent.git ~/oh-my-openagent-v4.19.2` + build; referenced config-relatively as `../../oh-my-openagent-v4.19.2` in `opencode.json` — see README "The OMO runtime fork" |
| E6 | Docker | external (optional) | Container runtime for worktree isolation | [docker.com](https://docker.com) |
| E7 | `browser-lifecycle-plugin` | external (optional) | Agent-browser session cleanup on idle. Not in default config — add manually to `opencode.json#plugin` if needed. | Clone from source and add `file://` path |
| E8 | `voice-bridge` (Vox) | `~/AI_projects/voice-bridge/` (external project) | Phone push-to-talk voice agent over Gemini Live that supervises the OpenCode fleet via the supervisor ledger; sibling Bun service on `127.0.0.1:18220`. Evidence: `live_file_installed` + `runtime_loaded` + `real_project_behavior_proven` (text-loopback e2e); real-voice dogfood not verified | `cd ~/AI_projects/voice-bridge && ./deploy/install.sh` |

## Patch Registry

Patches in `.sisyphus/patches/` document local modifications to external dependencies. Each entry includes verification patterns, reapply instructions, and durable alternative status.

| # | Patch ID | Dependency | Status | Applied | Verification |
|---|----------|------------|--------|---------|-------------|
| 1 | `opencode-dcp--bounded-range-archive-mode` | `@tarquinen/opencode-dcp@3.1.x` | retired 2026-06-23 | 2026-04-30 | RETIRED — DCP retired; Magic Context currently disabled |
| 2 | `opencode-dcp--byte-budget` | `@tarquinen/opencode-dcp@3.1.9` | retired 2026-06-23 | 2026-05-16 | RETIRED — DCP retired; Magic Context currently disabled |
| 3 | `opencode-dcp--compress-tool-prompt-contract` | `@tarquinen/opencode-dcp@3.1.9` | retired 2026-06-23 | 2026-05-17 | RETIRED — DCP retired; Magic Context currently disabled |
| 4 | `omo--boulder-worktree-authoritative-state` | `oh-my-openagent` | active | 2026-05-19 | `grep -n "worktreePath\|effectiveDirectory\|displayDirectory" ~/omo-hub/projects/oh-my-openagent/src/hooks/atlas/resolve-active-boulder-session.ts` |
| 5 | `ez-omo-config--commit-policy-override` | `ez-omo-config` | deprecated | 2026-04-28 | `grep -n "Never commit without explicit user direction" AGENTS.md` |
| 6 | `oh-my-openagent--context-overflow-max-token-error` | `oh-my-openagent@3.17.5` | active | 2026-05-14 | `grep -n "isRequestTokenOverflowMessage" ~/omo-hub/projects/oh-my-openagent/src/hooks/todo-continuation-enforcer/token-limit-detection.ts` |
| 7 | `omo--clean-agent-display-names` | `oh-my-openagent@4.4.0` | active | 2026-04-30 | `grep -n 'sisyphus: "Sisyphus"' ~/snap/alacritty/common/.cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent/dist/index.js` |
| 8 | `omo--commit-policy-alignment` | `oh-my-openagent` | active | 2026-05-02 | `grep -n "Git commits: follow the active git workflow" ~/oh-my-openagent/src/agents/sisyphus.ts` |
| 9 | `omo--exclude-selected-auto-slash-commands` | `oh-my-openagent` | active | 2026-05-14 | `grep -n 'gad-experiment' ~/omo-hub/projects/oh-my-openagent/src/hooks/auto-slash-command/constants.ts` |
| 10 | `omo--glm-preemptive-compaction-threshold` | `oh-my-openagent` | deprecated 2026-08-05 | 2026-04-10 | DEPRECATED — GLM 5.1 degradation problem does not occur on GLM 5.2 (1M context); OMO preemptive compaction disabled anyway |
| 11 | `omo--remove-activity-stagnation-bypass` | `oh-my-openagent` | active | 2026-04-10 | `grep -n '"none" \| "todo"' ~/omo-hub/projects/oh-my-openagent/src/hooks/todo-continuation-enforcer/session-state.ts` |
| 12 | `opencode--commit-policy-unblock` | `opencode` | active | 2026-05-02 | `grep -n "Git commits: follow the active git workflow" ~/src/opencode/packages/opencode/src/tool/bash.txt` |
| 13 | `omo--parent-wake-sync-mode-for-tui-render` | `oh-my-openagent` | rolled_back | 2026-06-24 | Do not reapply; ineffective workaround for upstream OpenCode TUI SSE rendering issue |
| 14 | `opencode--command-hook-cancellation` | `opencode` | active | 2026-06-26 | `grep -ER "cancelled: boolean|commandOutput.cancelled|HttpServerResponse.empty\(\)" ~/src/opencode/packages/plugin/src/index.ts ~/src/opencode/packages/opencode/src/session/prompt.ts ~/src/opencode/packages/opencode/src/server/routes/instance/httpapi/handlers/session.ts` |
| 15 | `opencode--sse-directory-filter-removal` | `opencode` | active | 2026-06-26 | `grep -q 'location?\.workspaceID === undefined' ~/src/opencode/packages/opencode/src/server/routes/instance/httpapi/handlers/event.ts` — removes directory filter that broke TUI rendering for worktree/plugin-initiated sessions |
| 16 | `opencode--link-click-wrapped-osc8` | `opencode` | active | 2026-07-06 | `grep -n 'buffers\.attributes\[idx\] >>> 8' ~/src/opencode/packages/tui/src/routes/session/index.tsx` — TS-level onMouseUp workaround for Alacritty wrapped OSC 8 hyperlink click bug |
| 17 | `omo--auto-slash-command-duplicate-user-args` | `oh-my-openagent@4.19.2` | active | 2026-07-06 | `test $(grep -c '## User Request' ~/oh-my-openagent-v4.19.2/dist/index.js) -eq 0` — removes duplicate user arguments footer from formatCommandTemplate |
| 18 | `omo--runtime-fallback-checktoolstate-bypass` | `oh-my-openagent` | active | 2026-07-25 | `grep -c 'checkToolState: false' ~/oh-my-openagent-v4.19.2/dist/index.js` — fork port of upstream PR #5357, hardens auto-retry dispatch against checkToolState deadlocks |
| 19 | `omo--sync-delegate-task-result-bloat` | `oh-my-openagent` | active | 2026-07-16 | `grep -c 'Subagent Result Bloat Prevention' configs/oh-my-openagent/oh-my-openagent.json` — config-level prompt_append mitigation on atlas/sisyphus agents; durable fix requires OMO code change in fetchSyncResult |
| 20 | `opencode--turn-summary-timestamp` | `opencode` | active | 2026-07-19 | `grep -c 'todayTimeOrDateTime' ~/src/opencode/packages/tui/src/routes/session/index.tsx` — local customization: shortDateTime 24h+date format for turn-summary timestamps |
| 21 | `omo--durable-log-path` | `oh-my-openagent` | active | 2026-08-05 | `grep -c '\.local/share/opencode/logs' ~/oh-my-openagent-v4.19.2/dist/index.js` — live dist patch (Bun-minified bundle); durable OMO log path so logs survive opencode serve restarts |
| 22 | `omo--fallback-toast-origin` | `oh-my-openagent` | active | 2026-08-05 | `grep -c 'formatFallbackOrigin' ~/oh-my-openagent-v4.19.2/dist/index.js` — live dist patch; appends the resolved agent + 6-char session suffix to runtime-fallback toasts so a single popup self-identifies its origin |
| 23 | `opencode--tui-pinned-session-race` | `opencode` | active | 2026-08-15 | `bash tests/regressions/012-pinned-session-race-fix.sh` — FIXED 2026-08-15 (source commit e7f5981ea): startup read merge guard + file-level prune RMW in `packages/tui/src/context/local.tsx`; compiled into live v1.18.5 binary; `runtime_effective: false` until live pin+prune verification |
| 24 | `omo--retries-before-fallback` | `oh-my-openagent` | active | 2026-08-15 | `grep -c 'retries_before_fallback' ~/oh-my-openagent-v4.19.2/dist/index.js` — source patch (fork commit 49f6728): adds `runtime_fallback.retries_before_fallback` knob; retry signals with attempt <= N are left to OpenCode's native same-model retry before OMO aborts and fails over. Live config sets N=2 |
| 25 | `oh-my-openagent--external-system-premise-discipline` | `oh-my-openagent` | active | 2026-08-13 | config-layer patch in `configs/oh-my-openagent/oh-my-openagent.json` — planning/review agents must state assumptions about external systems instead of fabricating state |
| 26 | `omo--model-less-spawn-fallback` | `oh-my-openagent` | active | 2026-08-14 | source patch in `packages/omo-opencode/src/features/background-agent/manager.ts` — background subagent spawns without an explicit model fall back to a configured default instead of failing |
| 27 | `omo--lookat-fallback-patience` | `oh-my-openagent` | active | 2026-08-16 | `grep -c 'LOOK_AT_FALLBACK_PATIENCE_MS' ~/oh-my-openagent-v4.19.2/dist/index.js` — live dist patch; look_at re-polls an empty child-session result for up to 60s so runtime-fallback answers that land after the primary model's failed attempt are retrieved instead of racing to `Error: No response from multimodal-looker agent`; regression pair `tests/regressions/013-lookat-fallback-patience.sh` |
| 28 | `oh-my-openagent--start-work-worktree-teardown` | `oh-my-openagent@4.19.2` | active | 2026-08-23 | `grep -c 'A worktree left behind is a leak' ~/oh-my-openagent-v4.19.2/dist/skills/start-work/SKILL.md` — plain-text skill patch; adds direct-mode worktree reclaim (merge → worktree remove → `branch -d`) as Completion step 3; closes the allocation/reclamation asymmetry that leaked 14 worktrees+branches |
| 29 | `omo--resume-skip-keep-running` | `oh-my-openagent@4.19.2` | active | 2026-08-30 | `grep -c 'keeping task running until next idle' ~/oh-my-openagent-v4.19.2/dist/index.js` — source patch (fork commit 8b883adab): busy-session resume skips (`active`/`reserved` gate statuses) keep the background task running instead of rolling it back to a terminal snapshot, so the child's eventual `session.idle` completes the task and notifies the parent; fixes the silent continuation deadlock observed 2026-08-30 (ses_facae8e4affezS7URnSTmMXIbz / bg_c16e323d); regression pair `tests/regressions/017-resume-skip-keep-running.sh` |
| 30 | `omo--ultrawork-subagent-guard` | `oh-my-openagent@4.19.2` | active | 2026-09-06 | `grep -c 'isSubagentSession' ~/oh-my-openagent-v4.19.2/packages/omo-opencode/src/plugin/system-transform.ts` — source patch (fork commits 52a175587 + 753602683): default-mode ultrawork system-prompt injection skips subagent/non-main sessions (mirrors keyword-detector hook.ts guard); main sessions keep injection; fixes the 26/28 bench-subject forced-announcement + one 0.0-score child-quit observed 2026-09-01 |
| 31 | `opencode--tui-session-directory-scope` | `opencode` | active | 2026-09-12 | `bash tests/regressions/020-session-directory-scope.sh` — source commit 106ace2f7 on fix/link-click-v1.18.5-solidjs: `sessionListQuery` returns `{}` so the server exact-filters the list to the attach directory (x-opencode-directory routing), and `session.updated` INSERTs from the daemon's unfiltered global /event stream are dropped unless they originate from this TUI's directory; stops foreign sessions (other `oa` terminals, /tmp dirs on the global project) appearing in the session list, quick-switch slots, and dialog fallback on the shared daemon; toggle retitled in app.tsx; compiled into v1.18.5 binary; `runtime_effective: false` until live tmux verification |
| 32 | `omo--writing-routing-to-document-writer` | `oh-my-openagent` | active | 2026-09-13 | `grep -n 'subagent_type="document-writer"' ~/oh-my-openagent-v4.19.2/packages/omo-opencode/src/agents/sisyphus/gpt-5-5.ts` |
| 33 | `omo--quota-only-fallback-same-model-retry` | `oh-my-openagent@4.19.2` | active | 2026-09-14 | `grep -c 'SameModelRetry' ~/oh-my-openagent-v4.19.2/packages/omo-opencode/src/hooks/runtime-fallback/auto-retry.ts` — source patch (fork commits 754cec4ee..e6bb8b059): only quota-exhaustion errors advance `fallback_models`; Z.AI concurrency throttles (`Rate limit reached for requests`) keep retrying the SAME model with exponential backoff capped at 120 s (`min(1000*2**attempt, 120000)`); covers session.status, terminal session.error, and message.updated paths (session-status-handler.ts is also changed but carries no SameModelRetry marker); 257/257 runtime-fallback tests; `runtime_effective: false` until a live non-quota throttle is observed (see entry) |
| 34 | `omo--family-reasoning-efforts` | `oh-my-openagent@4.19.2` | active | 2026-09-15 | `grep -c 'reasoningEfforts' ~/oh-my-openagent-v4.19.2/dist/index.js` — dist-level patch: per-family reasoning-effort ladders; the source file (model-capability-heuristics.ts) was never patched, so verify-live-patches reports STALE against `target_file` (integrity-timer notifications since 2026-09-15 17:49); port to source before the next fork rebuild or the fix is lost |
| 35 | `opencode--tui-pinned-session-window` | `opencode` | active | 2026-09-15 | `bash tests/regressions/021-pinned-session-window-fetch.sh` — source commit e5e715270 on fix/tui-pinned-session-window-v1.18.5: the session dialog fetches pinned sessions by ID (`session.get`) when they fall outside the newest-100 browse / 30-day sync windows, so the Pinned section is window-independent; fixes the 2026-09-14 veran incident where ~1,900 benchmark spam sessions pushed all pinned sessions out of the windows (pins silently vanished though the pin file was intact); installed binary sha256 a40da485, `runtime_effective: true` (live TUI observation in entry) |
| 36 | `opencode--tui-pin-directory-guard` | `opencode` | active | 2026-09-15 | `bash tests/regressions/022-pin-directory-guard.sh` — source commit ed579472d on fix/tui-pin-directory-guard-v1.18.5: the session dialog's `extra` rescue path (pin fetch-by-ID via unscoped `session.get`) drops sessions whose directory differs from `sdk.directory` while `session_directory_filter_enabled` is on; strict policy — no foreign pins visible anywhere, foreign pins stay in their own TUI; closes the cross-project re-leak found 2026-09-15 (pin-window patch bypassed the directory-scope invariant); `runtime_effective: true` (live A/B captures in entry, `.sisyphus/evidence/opencode--tui-pin-directory-guard/`) |
| 37 | `opencode--tui-subagent-spinner` | `opencode` | active | 2026-09-17 | `bash tests/regressions/024-subagent-spinner.sh` — source commits 8ed469559 + 8257e338c on fix/tui-subagent-spinner-v1.18.5: the Sessions dialog aggregates busy/retry statuses of hidden sub-agent child sessions into their parent rows (spinner while a background sub-agent runs); children unioned from the unfiltered `sync.data.session` list because the browse/search resources query with `roots:true` (first-commit iteration over `sessions()` alone was proven ineffective live); `runtime_effective: true` (live A/B 2026-09-17: parent idle + child busy → parent row rendered spinner frame) |

## Operator Tools (Repo-Only, Not Installed)

These Python helpers and config files support stack health, drift detection, and patch-guard enforcement. They run from the repo (not installed to `~/.config/opencode/` or `~/.sisyphus/`).

| Path | Purpose |
|------|---------|
| `configs/stack-locations.json` | Machine-readable ownership manifest for OpenCode/OMO stack locations on this host; consumed by `path-classifier.py` and `stack-doctor.py` |
| `scripts/stack-doctor.py` | Run read-only health checks for the OpenCode/OMO stack |
| `scripts/drift-detector.py` | Detect drift between repo store files and live OpenCode targets |
| `scripts/patch-guard.py` | Guard active patch install targets against forbidden stack zones |
| `scripts/path-classifier.py` | Classify canonical stack paths against `configs/stack-locations.json` |
| `scripts/secrets-path-audit.py` | Fail closed when tracked paths look like secrets or auth material |
| `scripts/restart-with-continuation.sh` | Snapshot active top-level sessions (per-directory `GET /session/status`), restart `opencode.service`, then re-inject a continuation prompt via `POST /session/:id/prompt_async`. Auth: `~/.config/opencode/serve.env` |
| `scripts/source-identity-check.py` | Report package and git identity for a source checkout |
| `scripts/legacy-name-classifier.py` | Classify legacy OpenCode/OMO naming occurrences in the config repo |

## Dependency Clusters

1. **Worktree Plugin Cluster**: worktree.ts → worktree/state.ts, worktree/terminal.ts, kdco-primitives/
2. **Wisdom System Cluster**: wisdom/ skill → wisdom-common.sh (sourced by wisdom scripts)
3. **Review System Cluster**: atlas-review-handler/ → wisdom/ skill, review-protocol/
4. **Aspect Dynamics Cluster**: aspect-dynamics.mjs → aspect-dynamics/config.mjs, context.mjs, heuristics.mjs, session-state.mjs, sets.mjs, nudge.mjs, logging.mjs, and sets/emotions-v1.json + sets/emotions-v2.json
5. **Output Shaper Cluster**: output-shaper.mjs → output-shaper/config.mjs, logging.mjs, model-gating.mjs, resume-detector.mjs
