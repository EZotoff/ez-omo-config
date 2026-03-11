# ez-omo-config Artifact Manifest

Complete inventory of 26 core artifacts for ez-omo-config repository scaffold.

## Artifacts Table

| # | Artifact Name | Source Path | Repo Path | Install Target | Dependency Cluster | Status |
|---|---|---|---|---|---|---|
| 1 | opencode.json | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Core Config | Required |
| 2 | opencode.jsonc | `~/.opencode/` | `configs/opencode/` | `$HOME/.opencode/` | Core Config | Required |
| 3 | provider-connect-retry.mjs | `~/.config/opencode/` | `configs/opencode/` | `$HOME/.config/opencode/` | Core Config | Required |
| 4 | oh-my-opencode.json | `~/.config/opencode/` | `configs/oh-my-opencode/` | `$HOME/.config/opencode/` | OMO Config | Required |
| 5 | worktree.ts | `~/.opencode/plugin/` | `plugins/` | `$HOME/.opencode/plugin/` | Worktree Plugin | Required |
| 6 | worktree/state.ts | `~/.opencode/plugin/worktree/` | `plugins/worktree/` | `$HOME/.opencode/plugin/worktree/` | Worktree Plugin | Required |
| 7 | worktree/terminal.ts | `~/.opencode/plugin/worktree/` | `plugins/worktree/` | `$HOME/.opencode/plugin/worktree/` | Worktree Plugin | Required |
| 8 | git-safety.ts | `~/.opencode/plugin/` | `plugins/` | `$HOME/.opencode/plugin/` | Git Safety | Required |
| 9 | review-enforcer.ts | `~/.opencode/plugin/` | `plugins/` | `$HOME/.opencode/plugin/` | Review Protocol | Required |
| 10 | kdco-primitives/ | `~/.opencode/plugin/kdco-primitives/` | `plugins/kdco-primitives/` | `$HOME/.opencode/plugin/kdco-primitives/` | KDCO Library | Required |
| 11 | wisdom/ | `~/.config/opencode/skills/wisdom/` | `skills/wisdom/` | `$HOME/.config/opencode/skills/` | Wisdom System | Required |
| 12 | atlas-review-handler/ | `~/.config/opencode/skills/atlas-review-handler/` | `skills/atlas-review-handler/` | `$HOME/.config/opencode/skills/` | Review Orchestration | Required |
| 13 | review-protocol/ | `~/.config/opencode/skills/review-protocol/` | `skills/review-protocol/` | `$HOME/.config/opencode/skills/` | Review Protocol | Required |
| 14 | playwright/ | `~/.config/opencode/skills/playwright/` | `skills/playwright/` | `$HOME/.config/opencode/skills/` | Browser Testing | Optional |
| 15 | deployment/ | `~/.config/opencode/skills/deployment/` | `skills/deployment/` | `$HOME/.config/opencode/skills/` | Deployment | Optional |
| 16 | frontend-ui-ux/ | `~/.config/opencode/skills/frontend-ui-ux/` | `skills/frontend-ui-ux/` | `$HOME/.config/opencode/skills/` | Frontend/UX | Optional |
| 17 | wisdom-common.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 18 | wisdom-search.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 19 | wisdom-write.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 20 | wisdom-sync.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 21 | wisdom-archive.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 22 | wisdom-delete.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 23 | wisdom-edit.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 24 | wisdom-gc.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 25 | wisdom-merge.sh | `~/.sisyphus/scripts/` | `scripts/wisdom/` | `$HOME/.sisyphus/scripts/` | Wisdom Scripts | Required |
| 26 | ocx.jsonc | `~/.opencode/` | `extras/` | `$HOME/.opencode/` | Registry | Optional |

## Directory Structure

```
ez-omo-config/
├── configs/
│   ├── opencode/           # Main OpenCode configuration (3 files)
│   └── oh-my-opencode/     # Oh-My-OpenCode configuration (1 file)
├── plugins/
│   ├── worktree.ts         # Worktree plugin core
│   ├── git-safety.ts       # Git safety protocol plugin
│   ├── review-enforcer.ts  # Review enforcer plugin
│   ├── worktree/           # Worktree subdirectory (state.ts, terminal.ts)
│   └── kdco-primitives/    # Shared library
├── skills/
│   ├── wisdom/             # Wisdom propagation skill
│   ├── atlas-review-handler/ # Review orchestration skill
│   ├── review-protocol/    # Review protocol skill
│   ├── playwright/         # Browser testing skill
│   ├── deployment/         # Deployment helper skill
│   └── frontend-ui-ux/     # Frontend/UX design skill
├── scripts/
│   └── wisdom/             # Wisdom propagation scripts (9 files)
├── extras/                 # Extra configurations (ocx.jsonc)
├── docs/                   # Documentation for configs, plugins, skills, wisdom
├── tests/                  # Bash verification suite and helpers
├── install.sh              # Bootstrap installer
├── README.md               # Project overview and installation guide
├── LICENSE                 # License file
└── MANIFEST.md             # This file
```

## Artifact Summary

- **Total Artifacts**: 26 (configs: 4, plugins: 5 + kdco-primitives dir, skills: 6 dirs, scripts: 9, extras: 1)
- **Core Configs**: 4 files (opencode.json, opencode.jsonc, provider-connect-retry.mjs, oh-my-opencode.json)
- **Plugins**: 3 main files + worktree/ (2 files) + kdco-primitives/ directory
- **Skills**: 6 directories
- **Scripts**: 9 wisdom shell scripts
- **Extras**: 1 file (ocx.jsonc)

## Dependency Clusters

1. **Worktree Plugin Cluster**: worktree.ts → worktree/state.ts, worktree/terminal.ts, kdco-primitives/
2. **Wisdom System Cluster**: wisdom/ skill → wisdom-common.sh (sourced by all 8 other wisdom scripts)
3. **Review System Cluster**: atlas-review-handler/ → wisdom/ skill, review-protocol/
