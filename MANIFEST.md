# ez-omo-config Artifact Manifest

Complete inventory of 41 core artifacts for ez-omo-config repository scaffold.

## Artifacts Table

| # | Artifact Name | Source Path | Repo Path | Install Target | Dependency Cluster | Status |
|---|---|---|---|---|---|---|
| 1 | models-preset.md | `~/.config/opencode/command/` | `commands/` | `$HOME/.config/opencode/command/` | Slash Commands | Required |
| 1b | vscode.md | `~/.config/opencode/command/` | `commands/` | `$HOME/.config/opencode/command/` | Slash Commands | Required |
| 1c | session-info.md | `~/.config/opencode/command/` | `commands/` | `$HOME/.config/opencode/command/` | Slash Commands | Required |
| 2 | opencode.json | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Core Config | Required |
| 3 | opencode.jsonc | `~/.opencode/` | `configs/opencode/` | `$HOME/.opencode/` | Core Config | Required |
| 4 | provider-connect-retry.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Core Config | Required |
| 4b | retry-errors.json | `~/.config/opencode/` | `configs/` | `$HOME/.config/opencode/` | Core Config | Required |
| 4c | aspect-dynamics.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Aspect Dynamics | Optional |
| 4d | aspect-dynamics/config.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Aspect Dynamics | Optional |
| 4e | aspect-dynamics/context.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Aspect Dynamics | Optional |
| 4f | aspect-dynamics/heuristics.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Aspect Dynamics | Optional |
| 4g | aspect-dynamics/session-state.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Aspect Dynamics | Optional |
| 4h | aspect-dynamics/sets.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Aspect Dynamics | Optional |
| 4i | aspect-dynamics/nudge.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Aspect Dynamics | Optional |
| 4j | aspect-dynamics/logging.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Aspect Dynamics | Optional |
| 4k | aspect-dynamics/sets/emotions-v1.json | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Aspect Dynamics | Optional |
| 5 | oh-my-openagent.json | `~/.config/opencode/` | `configs/oh-my-openagent/` | `$HOME/.config/opencode/` | OMO Config | Required |
| 6 | worktree.ts | `~/.opencode/plugin/` | `plugins/` | `$HOME/.opencode/plugin/` | Worktree Plugin | Required |
| 7 | worktree/state.ts | `~/.opencode/plugin/worktree/` | `plugins/worktree/` | `$HOME/.opencode/plugin/worktree/` | Worktree Plugin | Required |
| 8 | worktree/terminal.ts | `~/.opencode/plugin/worktree/` | `plugins/worktree/` | `$HOME/.opencode/plugin/worktree/` | Worktree Plugin | Required |
| 9 | git-safety.ts | `~/.opencode/plugin/` | `plugins/` | `$HOME/.opencode/plugin/` | Git Safety | Required |
| 10 | review-enforcer.ts | `~/.opencode/plugin/` | `plugins/` | `$HOME/.opencode/plugin/` | Review Protocol | Required |
| 11 | kdco-primitives/ | `~/.opencode/plugin/kdco-primitives/` | `plugins/kdco-primitives/` | `$HOME/.opencode/plugin/kdco-primitives/` | KDCO Library | Required |
| 11b | vscode.ts | `~/.opencode/plugin/` | `plugins/` | `$HOME/.opencode/plugin/` | VS Code Launcher | Optional |
| 11c | session-info.ts | `~/.opencode/plugin/` | `plugins/` | `$HOME/.opencode/plugin/` | Session Info Clipboard | Required |
| 12 | wisdom/ | `~/.config/opencode/skills/wisdom/` | `skills/wisdom/` | `$HOME/.config/opencode/skills/` | Wisdom System | Required |
| 12b | knowledge/ | `~/.config/opencode/skills/knowledge/` | `skills/knowledge/` | `$HOME/.config/opencode/skills/` | Wisdom Shim (Deprecated) | Required |
| 13 | atlas-review-handler/ | `~/.config/opencode/skills/atlas-review-handler/` | `skills/atlas-review-handler/` | `$HOME/.config/opencode/skills/` | Review Orchestration | Required |
| 14 | review-protocol/ | `~/.config/opencode/skills/review-protocol/` | `skills/review-protocol/` | `$HOME/.config/opencode/skills/` | Review Protocol | Required |
| 15 | playwright/ | `~/.config/opencode/skills/playwright/` | `skills/playwright/` | `$HOME/.config/opencode/skills/` | Browser Testing | Optional |
| 16 | deployment/ | `~/.config/opencode/skills/deployment/` | `skills/deployment/` | `$HOME/.config/opencode/skills/` | Deployment | Optional |
| 17 | frontend-ui-ux/ | `~/.config/opencode/skills/frontend-ui-ux/` | `skills/frontend-ui-ux/` | `$HOME/.config/opencode/skills/` | Frontend/UX | Optional |
| 18 | wisdom-common.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 19 | wisdom-search.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 20 | wisdom-write.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 21 | wisdom-sync.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 22 | wisdom-archive.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 23 | wisdom-delete.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 24 | wisdom-edit.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 25 | wisdom-gc.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 26 | wisdom-merge.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 27 | ocx.jsonc | `~/.opencode/` | `extras/` | `$HOME/.opencode/` | Registry | Optional |

## Directory Structure

```
ez-omo-config/
├── commands/
│   └── models-preset.md    # Slash command prompt for model tables
│   └── vscode.md           # VS Code launcher (handled by plugin, no LLM)
│   └── session-info.md     # Session info clipboard (handled by plugin, no LLM)
├── configs/
│   ├── opencode/           # Main OpenCode configuration (3 files + aspect-dynamics)
│   ├── oh-my-openagent/     # Oh-My-OpenAgent configuration (1 file)
│   └── retry-errors.json    # Retry registry for provider-connect-retry plugin
├── plugins/
│   ├── worktree.ts         # Worktree plugin core
│   ├── git-safety.ts       # Git safety protocol plugin
│   ├── review-enforcer.ts  # Review enforcer plugin
│   ├── vscode.ts           # VS Code launcher plugin (intercepts /vscode command)
│   ├── session-info.ts     # Session info clipboard plugin (intercepts /session-info command)
│   ├── worktree/           # Worktree subdirectory (state.ts, terminal.ts)
│   └── kdco-primitives/    # Shared library
├── skills/
│   ├── wisdom/             # Wisdom propagation skill (primary runtime memory)
│   ├── knowledge/          # Deprecated compatibility shim (delegates to Wisdom)
│   ├── atlas-review-handler/ # Review orchestration skill
│   ├── review-protocol/    # Review protocol skill
│   ├── playwright/         # Browser testing skill
│   ├── deployment/         # Deployment helper skill
│   └── frontend-ui-ux/     # Frontend/UX design skill
├── scripts/
│   └── wisdom/             # Wisdom propagation scripts (9 files)
├── extras/                 # Extra configurations (ocx.jsonc)
├── docs/                   # Documentation for configs, plugins, skills, wisdom, compatibility debt
│   ├── COMPATIBILITY-DEBT.md  # Shim inventory with deletion criteria and removal milestones
├── tests/                  # Bash verification suite and helpers
├── scripts/                # Wisdom scripts, worktree scripts, and audit utilities
│   └── audit-wisdom-first.sh  # Validates no contradictory dual-system language remains
├── install.sh              # Bootstrap installer
├── README.md               # Project overview and installation guide
├── LICENSE                 # License file
└── MANIFEST.md             # This file
```

## Artifact Summary

- **Total Artifacts**: 41 core + 1 external (commands: 3, configs: 14, plugins: 6 + kdco-primitives dir, skills: 6 dirs + 1 external, scripts: 9, extras: 1)
- **Commands**: 3 slash command prompts (`models-preset.md`, `vscode.md`, `session-info.md`)
- **Core Configs**: 14 files (opencode.json, opencode.jsonc, provider-connect-retry.mjs, oh-my-openagent.json, retry-errors.json, aspect-dynamics.mjs, and 7 aspect-dynamics support modules + 1 seed set)
- **Plugins**: 3 main files + vscode.ts + session-info.ts + worktree/ (2 files) + kdco-primitives/ directory
- **Skills**: 7 directories (managed by install.sh) + 1 external (Vera, managed by `vera agent install`)
- **Scripts**: 9 wisdom shell scripts
- **Extras**: 1 file (ocx.jsonc)

### External Artifacts (Not in install.sh)

| # | Artifact | Path | Purpose | Install Command |
|---|----------|------|---------|-----------------|
| 31 | vera/ | `~/.config/opencode/skills/vera/` | Semantic code search skill | `vera agent install --client opencode` |

## Dependency Clusters

1. **Worktree Plugin Cluster**: worktree.ts → worktree/state.ts, worktree/terminal.ts, kdco-primitives/
2. **Wisdom System Cluster**: wisdom/ skill → wisdom-common.sh (sourced by all 8 other wisdom scripts)
3. **Review System Cluster**: atlas-review-handler/ → wisdom/ skill, review-protocol/
4. **Aspect Dynamics Cluster**: aspect-dynamics.mjs → aspect-dynamics/config.mjs, context.mjs, heuristics.mjs, session-state.mjs, sets.mjs, nudge.mjs, logging.mjs, and sets/emotions-v1.json
