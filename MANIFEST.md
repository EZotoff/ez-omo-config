# ez-omo-config Artifact Manifest

Complete inventory of 68 core artifacts for ez-omo-config repository scaffold.

> **Atomic install pathway**: an item may declare multiple groups via `+`-joined tags (e.g. `skills+configs`). It installs whenever ANY declared group is selected. Used by the global `AGENTS.md`, which must travel with the `/deployment` skill AND read like a config file. See `category_selected` in `install.sh`.

## Artifacts Table

| # | Artifact Name | Source Path | Repo Path | Install Target | Dependency Cluster | Status |
|---|---|---|---|---|---|---|
| 1 | models-preset.md | `~/.config/opencode/command/` | `commands/` | `$HOME/.config/opencode/command/` | Slash Commands | Required |
| 1b | vscode.md | `~/.config/opencode/command/` | `commands/` | `$HOME/.config/opencode/command/` | Slash Commands | Required |
| 1c | session-id.md | `~/.config/opencode/command/` | `commands/` | `$HOME/.config/opencode/command/` | Slash Commands | Required |
| 1d | session-info.md | `~/.config/opencode/command/` | `commands/` | `$HOME/.config/opencode/command/` | Slash Commands | Required |
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
| 5 | oh-my-openagent.json | `~/.config/opencode/` | `configs/oh-my-openagent/` | `$HOME/.config/opencode/` | OMO Config | Required |
| 6 | worktree.ts | `~/.opencode/plugin/` | `plugins/` | `$HOME/.opencode/plugin/` | Worktree Plugin | Required |
| 7 | worktree/state.ts | `~/.opencode/plugin/worktree/` | `plugins/worktree/` | `$HOME/.opencode/plugin/worktree/` | Worktree Plugin | Required |
| 8 | worktree/terminal.ts | `~/.opencode/plugin/worktree/` | `plugins/worktree/` | `$HOME/.opencode/plugin/worktree/` | Worktree Plugin | Required |
| 9 | git-safety.ts | `~/.opencode/plugin/` | `plugins/` | `$HOME/.opencode/plugin/` | Git Safety | Required |
| 10 | review-enforcer.ts | `~/.opencode/plugin/` | `plugins/` | `$HOME/.opencode/plugin/` | Review Protocol | Required |
| 10b | auto-checkpoint.ts | `~/.opencode/plugin/` | `plugins/` | `$HOME/.opencode/plugin/` | Checkpoint Plugin (opt-in runtime) | Required |
| 11 | kdco-primitives/ | `~/.opencode/plugin/kdco-primitives/` | `plugins/kdco-primitives/` | `$HOME/.opencode/plugin/kdco-primitives/` | KDCO Library | Required |
| 11b | vscode.ts | `~/.opencode/plugin/` | `plugins/` | `$HOME/.opencode/plugin/` | VS Code Launcher | Optional |
| 11c | session-id.ts | `~/.opencode/plugin/` | `plugins/` | `$HOME/.opencode/plugin/` | Session ID Clipboard | Required |
| 11d | session-info.ts | `~/.opencode/plugin/` | `plugins/` | `$HOME/.opencode/plugin/` | Session Info Clipboard | Required |
| 11e | vera-runtime.ts | `~/.opencode/plugin/` | `plugins/` | `$HOME/.opencode/plugin/` | Vera Runtime State / Opt-in Watcher Supervision | Required |
| 11f | subagent-loop-guard.ts | `~/.opencode/plugin/` | `plugins/` | `$HOME/.opencode/plugin/` | Subagent Loop Guard | Required |
| 11h | clickable-links.ts | `~/.opencode/plugin/` | `plugins/` | `$HOME/.opencode/plugin/` | Clickable File Links (TUI) | Required |
| 12 | wisdom/ | `~/.config/opencode/skills/wisdom/` | `skills/wisdom/` | `$HOME/.config/opencode/skills/` | Wisdom System | Required |
| 12b | patch-tracker/ | `~/.config/opencode/skills/patch-tracker/` | `skills/patch-tracker/` | `$HOME/.config/opencode/skills/` | Patch Registry | Optional |
| 12c | register-retry-error/ | `~/.config/opencode/skills/register-retry-error/` | `skills/register-retry-error/` | `$HOME/.config/opencode/skills/` | Retry Error Registry | Optional |
| 12d | session-id/ | `~/.config/opencode/skills/session-id/` | `skills/session-id/` | `$HOME/.config/opencode/skills/` | Session ID Clipboard (skill form) | Optional |
| 12e | debate/ | `~/.config/opencode/skills/debate/` | `skills/debate/` | `$HOME/.config/opencode/skills/` | Structured Adversarial Analysis | Optional |
| 13 | atlas-review-handler/ | `~/.config/opencode/skills/atlas-review-handler/` | `skills/atlas-review-handler/` | `$HOME/.config/opencode/skills/` | Review Orchestration | Required |
| 14 | review-protocol/ | `~/.config/opencode/skills/review-protocol/` | `skills/review-protocol/` | `$HOME/.config/opencode/skills/` | Review Protocol | Required |
| 16 | deployment/ | `~/.config/opencode/skills/deployment/` | `skills/deployment/` | `$HOME/.config/opencode/skills/` | Deployment | Optional |
| 16b | AGENTS.md (global) | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Atomic: Deployment + Core Config | Required |
| 28 | merge-agent/ | `~/.config/opencode/skills/merge-agent/` | `skills/merge-agent/` | `$HOME/.config/opencode/skills/` | Safe Merge | Optional |
| 29 | parallel-dev/ | `~/.config/opencode/skills/parallel-dev/` | `skills/parallel-dev/` | `$HOME/.config/opencode/skills/` | Parallel Dev | Optional |
| 30a | vera-hygiene/ | `~/.config/opencode/skills/vera-hygiene/` | `skills/vera-hygiene/` | `$HOME/.config/opencode/skills/` | Vera Hygiene | Optional |
| 30b | update-to-latest/ | `~/.config/opencode/skills/update-to-latest/` | `skills/update-to-latest/` | `$HOME/.config/opencode/skills/` | Update Pipeline | Optional |
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
| 26a | worktree-post-create.sh | `~/.opencode/scripts/` | `scripts/` | `$HOME/.opencode/scripts/` | Worktree Hooks | Required |
| 26b | worktree-pre-delete.sh | `~/.opencode/scripts/` | `scripts/` | `$HOME/.opencode/scripts/` | Worktree Hooks | Required |
| 26c | verify-live-deployment.sh | `~/.sisyphus/scripts/` | `scripts/` | `$HOME/.sisyphus/scripts/` | Live Deployment Verification | Required |
| 26d | vera-hygiene.sh | `~/.sisyphus/scripts/` | `scripts/` | `$HOME/.sisyphus/scripts/` | Vera Hygiene | Optional |
| 27 | ocx.jsonc | `~/.opencode/` | `extras/` | `$HOME/.opencode/` | Registry | Optional |
| 28 | test_live_deployment_contract.sh | (repo only) | `tests/` | (repo only) | Live Deployment Verification | Required |
| 28a | test_dcp_bounded_range.sh | (repo only) | `tests/` | (repo only) | RETIRED 2026-06-23 — DCP Verification | Archived (`.retired`) |
| 28b | test_dcp_startup_warning.sh | (repo only) | `tests/` | (repo only) | RETIRED 2026-06-23 — DCP Verification | Archived (`.retired`) |
| 28c | test_vera_hygiene.sh | (repo only) | `tests/` | (repo only) | Vera Hygiene Verification | Required |
| 28d | test_review_enforcer_completion_instruction.sh | (repo only) | `tests/` | (repo only) | Review Enforcer Verification | Required |
| 28e | test_prometheus_planning_contract.sh | (repo only) | `tests/` | (repo only) | Prometheus Planning Contract | Required |
| 28f | test_openai_provider.sh | (repo only) | `tests/` | (repo only) | Codex Provider Verification | Required |
| 28g | test_update_to_latest_skill.sh | (repo only) | `tests/` | (repo only) | Update Pipeline Verification | Required |
| 28h | test_dcp_payload_budget.sh | (repo only) | `tests/` | (repo only) | RETIRED 2026-06-23 — DCP Byte-Budget Verification | Archived (`.retired`) |
| 28i | test_subagent_loop_guard.sh | (repo only) | `tests/` | (repo only) | Subagent Loop Guard Verification | Required |
| 29 | live-deployment-verification.md | (repo only) | `docs/` | (repo only) | Documentation | Required |
| 30 | dcp-byte-budget.md | (repo only) | `docs/` | (repo only) | Byte-Budget Configuration Reference | Required |

## Directory Structure

```
ez-omo-config/
├── commands/
│   └── models-preset.md    # Slash command prompt for model tables
│   └── vscode.md           # VS Code launcher (handled by plugin, no LLM)
│   └── session-id.md       # Session ID clipboard (handled by plugin, no LLM)
│   └── session-info.md     # Session info clipboard (handled by plugin, no LLM)
├── configs/
│   ├── opencode/           # Main OpenCode configuration (4 files + aspect-dynamics)
│   ├── oh-my-openagent/     # Oh-My-OpenAgent configuration (1 file)
│   └── retry-errors.json    # Retry registry for provider-connect-retry plugin
├── plugins/
│   ├── worktree.ts         # Worktree plugin core
│   ├── auto-checkpoint.ts  # Semantic session-scoped checkpoint plugin
│   ├── git-safety.ts       # Git safety protocol plugin
│   ├── review-enforcer.ts  # Review enforcer plugin
│   ├── vscode.ts           # VS Code launcher plugin (intercepts /vscode command)
│   ├── session-id.ts       # Session ID clipboard plugin (intercepts /session-id command)
│   ├── session-info.ts     # Session info clipboard plugin (intercepts /session-info command)
│   ├── vera-runtime.ts     # Vera runtime state / opt-in watcher supervision plugin
│   ├── subagent-loop-guard.ts # Configured loop-pattern guard for subagent tool calls
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
│   ├── vera-hygiene/       # Vera index hygiene and .veraignore management
│   └── update-to-latest/   # Safe OpenCode/OMO update pipeline with approval gate
├── scripts/
│   ├── wisdom/             # Wisdom propagation scripts (10 files)
│   ├── worktree/           # Worktree lifecycle hooks (2 files)
│   └── vera-hygiene.sh     # Vera hygiene script
├── extras/                 # Extra configurations (ocx.jsonc)
├── docs/                   # Documentation for configs, plugins, skills, wisdom, compatibility debt, live deployment verification, and observability contract
│   ├── configs.md             # Config-layer system documentation with Non-Wisdom Observability Contract
│   ├── COMPATIBILITY-DEBT.md  # Shim inventory with deletion criteria and removal milestones
│   ├── live-deployment-verification.md  # Live Deployment Verification Gate documentation
├── tests/                  # Bash verification suite and helpers
├── scripts/                # Wisdom scripts, worktree scripts, and audit utilities
│   └── audit-wisdom-first.sh  # Validates no contradictory dual-system language remains
├── install.sh              # Bootstrap installer
├── README.md               # Project overview and installation guide
├── LICENSE                 # License file
└── MANIFEST.md             # This file
```

## Artifact Summary

- **Total Artifacts**: 68 core + 1 external (commands: 4, configs: 17, plugins: 12 files + kdco-primitives dir, skills: 13 dirs + 1 external, scripts: 14 wisdom + 2 worktree + 1 verify + 1 vera-hygiene + 7 Python operator helpers, tests: 19 active + 4 retired, extras: 1, docs: 6)
- **Commands**: 4 slash command prompts (`models-preset.md`, `vscode.md`, `session-id.md`, `session-info.md`)
- **Core Configs**: 17 files (opencode.json, opencode.jsonc, disabled magic-context.jsonc reference config, worktree.jsonc, provider-connect-retry.mjs, oh-my-openagent.json, retry-errors.json, stack-locations.json, aspect-dynamics.mjs, and 7 aspect-dynamics support modules + 2 seed sets). DCP retired 2026-06-23; see `dcp.jsonc.retired` for historical reference.
- **Plugins**: 7 main files + auto-checkpoint.ts + vscode.ts + session-id.ts + session-info.ts + vera-runtime.ts + subagent-loop-guard.ts + clickable-links.ts + worktree/ (2 files) + kdco-primitives/ directory
- **Skills**: 13 directories (managed by install.sh) + 1 external (Vera, managed by `vera agent install`). `playwright`, `frontend-ui-ux`, and `github-triage` ship with OMO upstream and are intentionally NOT vendored here. `worktree-coordinator` removed (was a doc index, not a skill — its content lives in `parallel-dev/SKILL.md`, `merge-agent/SKILL.md`, and `docs/worktree-state-schema.md`). `knowledge/` removed (deprecated Wisdom compat shim — Wisdom is the sole runtime memory store; shell-script shims deleted alongside).
- **Scripts**: 17 wisdom shell scripts (15 `wisdom-*` + `knowledge-constants.sh` + `manifest-write.sh`) + 2 worktree hook scripts + 1 live deployment verification script + 1 vera hygiene script + 7 Python operator helpers (stack-doctor, drift-detector, patch-guard, path-classifier, secrets-path-audit, source-identity-check, legacy-name-classifier)
- **Tests**: 19 active test scripts + 4 retired DCP test scripts (`.retired` suffix, kept for historical reference)
- **Extras**: 1 file (ocx.jsonc)

### External Artifacts (Not in install.sh)

| # | Artifact | Path | Purpose | Install Command |
|---|----------|------|---------|-----------------|
| 28 | vera/ | `~/.config/opencode/skills/vera/` | Semantic code search skill | `vera agent install --client opencode --scope global` |

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
| 9 | `omo--exclude-selected-auto-slash-commands` | `oh-my-openagent` | active | 2026-05-14 | `grep -n '"vera"|"gad-experiment"' ~/omo-hub/projects/oh-my-openagent/src/hooks/auto-slash-command/constants.ts` |
| 10 | `omo--glm-preemptive-compaction-threshold` | `oh-my-openagent` | active | 2026-04-10 | `grep -n "GLM_PREEMPTIVE_COMPACTION_THRESHOLD" ~/omo-hub/projects/oh-my-openagent/src/hooks/preemptive-compaction.ts` |
| 11 | `omo--remove-activity-stagnation-bypass` | `oh-my-openagent` | active | 2026-04-10 | `grep -n '"none" \| "todo"' ~/omo-hub/projects/oh-my-openagent/src/hooks/todo-continuation-enforcer/session-state.ts` |
| 12 | `opencode--commit-policy-unblock` | `opencode` | active | 2026-05-02 | `grep -n "Git commits: follow the active git workflow" ~/src/opencode/packages/opencode/src/tool/bash.txt` |

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
| `scripts/source-identity-check.py` | Report package and git identity for a source checkout |
| `scripts/legacy-name-classifier.py` | Classify legacy OpenCode/OMO naming occurrences in the config repo |

## Dependency Clusters

1. **Worktree Plugin Cluster**: worktree.ts → worktree/state.ts, worktree/terminal.ts, kdco-primitives/
2. **Vera Runtime Cluster**: vera-runtime.ts → (self-contained, manual-by-default, fails open if vera binary absent)
3. **Wisdom System Cluster**: wisdom/ skill → wisdom-common.sh (sourced by all 8 other wisdom scripts)
4. **Review System Cluster**: atlas-review-handler/ → wisdom/ skill, review-protocol/
5. **Aspect Dynamics Cluster**: aspect-dynamics.mjs → aspect-dynamics/config.mjs, context.mjs, heuristics.mjs, session-state.mjs, sets.mjs, nudge.mjs, logging.mjs, and sets/emotions-v1.json + sets/emotions-v2.json
