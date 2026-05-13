# ez-omo-config Artifact Manifest

Complete inventory of 62 core artifacts for ez-omo-config repository scaffold.

## Artifacts Table

| # | Artifact Name | Source Path | Repo Path | Install Target | Dependency Cluster | Status |
|---|---|---|---|---|---|---|
| 1 | models-preset.md | `~/.config/opencode/command/` | `commands/` | `$HOME/.config/opencode/command/` | Slash Commands | Required |
| 1b | vscode.md | `~/.config/opencode/command/` | `commands/` | `$HOME/.config/opencode/command/` | Slash Commands | Required |
| 1c | session-id.md | `~/.config/opencode/command/` | `commands/` | `$HOME/.config/opencode/command/` | Slash Commands | Required |
| 1d | session-info.md | `~/.config/opencode/command/` | `commands/` | `$HOME/.config/opencode/command/` | Slash Commands | Required |
| 2 | opencode.json | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Core Config | Required |
| 3 | opencode.jsonc | `~/.opencode/` | `configs/opencode/` | `$HOME/.opencode/` | Core Config | Required |
| 3b | dcp.jsonc | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Core Config | Required |
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
| 11e | vera-runtime.ts | `~/.opencode/plugin/` | `plugins/` | `$HOME/.opencode/plugin/` | Vera Watcher Supervision | Required |
| 12 | wisdom/ | `~/.config/opencode/skills/wisdom/` | `skills/wisdom/` | `$HOME/.config/opencode/skills/` | Wisdom System | Required |
| 13 | atlas-review-handler/ | `~/.config/opencode/skills/atlas-review-handler/` | `skills/atlas-review-handler/` | `$HOME/.config/opencode/skills/` | Review Orchestration | Required |
| 14 | review-protocol/ | `~/.config/opencode/skills/review-protocol/` | `skills/review-protocol/` | `$HOME/.config/opencode/skills/` | Review Protocol | Required |
| 15 | playwright/ | `~/.config/opencode/skills/playwright/` | `skills/playwright/` | `$HOME/.config/opencode/skills/` | Browser Testing | Optional |
| 16 | deployment/ | `~/.config/opencode/skills/deployment/` | `skills/deployment/` | `$HOME/.config/opencode/skills/` | Deployment | Optional |
| 17 | frontend-ui-ux/ | `~/.config/opencode/skills/frontend-ui-ux/` | `skills/frontend-ui-ux/` | `$HOME/.config/opencode/skills/` | Frontend/UX | Optional |
| 28 | merge-agent/ | `~/.config/opencode/skills/merge-agent/` | `skills/merge-agent/` | `$HOME/.config/opencode/skills/` | Safe Merge | Optional |
| 29 | parallel-dev/ | `~/.config/opencode/skills/parallel-dev/` | `skills/parallel-dev/` | `$HOME/.config/opencode/skills/` | Parallel Dev | Optional |
| 30 | worktree-coordinator/ | `~/.config/opencode/skills/worktree-coordinator/` | `skills/worktree-coordinator/` | `$HOME/.config/opencode/skills/` | Worktree Coord | Optional |
| 30a | vera-hygiene/ | `~/.config/opencode/skills/vera-hygiene/` | `skills/vera-hygiene/` | `$HOME/.config/opencode/skills/` | Vera Hygiene | Optional |
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
| 26a | worktree-post-create.sh | `~/.opencode/scripts/` | `scripts/worktree/` | `$HOME/.opencode/scripts/` | Worktree Hooks | Required |
| 26b | worktree-pre-delete.sh | `~/.opencode/scripts/` | `scripts/worktree/` | `$HOME/.opencode/scripts/` | Worktree Hooks | Required |
| 26c | verify-live-deployment.sh | `~/.sisyphus/scripts/` | `scripts/` | `$HOME/.sisyphus/scripts/` | Live Deployment Verification | Required |
| 26d | vera-hygiene.sh | `~/.sisyphus/scripts/` | `scripts/` | `$HOME/.sisyphus/scripts/` | Vera Hygiene | Optional |
| 27 | ocx.jsonc | `~/.opencode/` | `extras/` | `$HOME/.opencode/` | Registry | Optional |
| 28 | test_live_deployment_contract.sh | (repo only) | `tests/` | (repo only) | Live Deployment Verification | Required |
| 28a | test_dcp_bounded_range.sh | (repo only) | `tests/` | (repo only) | DCP Verification | Required |
| 28b | test_dcp_startup_warning.sh | (repo only) | `tests/` | (repo only) | DCP Verification | Required |
| 28c | test_vera_hygiene.sh | (repo only) | `tests/` | (repo only) | Vera Hygiene Verification | Required |
| 28d | test_review_enforcer_completion_instruction.sh | (repo only) | `tests/` | (repo only) | Review Enforcer Verification | Required |
| 28e | test_prometheus_planning_contract.sh | (repo only) | `tests/` | (repo only) | Prometheus Planning Contract | Required |
| 29 | live-deployment-verification.md | (repo only) | `docs/` | (repo only) | Documentation | Required |

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
│   ├── vera-runtime.ts     # Vera watcher supervision plugin
│   ├── worktree/           # Worktree subdirectory (state.ts, terminal.ts)
│   └── kdco-primitives/    # Shared library
├── skills/
│   ├── wisdom/             # Wisdom propagation skill (primary runtime memory)
│   ├── atlas-review-handler/ # Review orchestration skill
│   ├── review-protocol/    # Review protocol skill
│   ├── playwright/         # Browser testing skill
│   ├── deployment/         # Deployment helper skill
│   ├── frontend-ui-ux/     # Frontend/UX design skill
│   ├── merge-agent/        # Safe branch merging with guardrails
│   ├── parallel-dev/       # Multi-agent orchestration with decision framework
│   ├── worktree-coordinator/ # Worktree parallel development guide
│   └── vera-hygiene/       # Vera index hygiene and .veraignore management
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

- **Total Artifacts**: 62 core + 1 external (commands: 4, configs: 16, plugins: 11 files + kdco-primitives dir, skills: 10 dirs + 1 external, scripts: 14, tests: 20, extras: 1, docs: 5)
- **Commands**: 4 slash command prompts (`models-preset.md`, `vscode.md`, `session-id.md`, `session-info.md`)
- **Core Configs**: 16 files (opencode.json, opencode.jsonc, dcp.jsonc, worktree.jsonc, provider-connect-retry.mjs, oh-my-openagent.json, retry-errors.json, aspect-dynamics.mjs, and 7 aspect-dynamics support modules + 1 seed set)
- **Plugins**: 7 main files + auto-checkpoint.ts + vscode.ts + session-id.ts + session-info.ts + vera-runtime.ts + worktree/ (2 files) + kdco-primitives/ directory
- **Skills**: 10 directories (managed by install.sh) + 1 external (Vera, managed by `vera agent install`)
- **Scripts**: 20 wisdom shell scripts (including 3 deprecated compatibility shims) + 2 worktree hook scripts + 1 live deployment verification script + 1 vera hygiene script
- **Tests**: 20 test scripts
- **Extras**: 1 file (ocx.jsonc)

### External Artifacts (Not in install.sh)

| # | Artifact | Path | Purpose | Install Command |
|---|----------|------|---------|-----------------|
| 28 | vera/ | `~/.config/opencode/skills/vera/` | Semantic code search skill | `vera agent install --client opencode --scope global` |

## Dependency Clusters

1. **Worktree Plugin Cluster**: worktree.ts → worktree/state.ts, worktree/terminal.ts, kdco-primitives/
2. **Vera Runtime Cluster**: vera-runtime.ts → (self-contained, fails open if vera binary absent)
3. **Wisdom System Cluster**: wisdom/ skill → wisdom-common.sh (sourced by all 8 other wisdom scripts)
4. **Review System Cluster**: atlas-review-handler/ → wisdom/ skill, review-protocol/
5. **Aspect Dynamics Cluster**: aspect-dynamics.mjs → aspect-dynamics/config.mjs, context.mjs, heuristics.mjs, session-state.mjs, sets.mjs, nudge.mjs, logging.mjs, and sets/emotions-v1.json
