# Plugin System

The OpenCode plugin system extends agent capabilities through TypeScript-based plugins that hook into the agent lifecycle. Plugins in this repository provide git worktree management, safety enforcement, and review workflow automation.

## Overview

Plugins are TypeScript modules loaded by OpenCode at runtime. They can:

- Register new tools and commands
- Hook into agent lifecycle events
- Manage persistent state via SQLite
- Spawn and manage terminal sessions
- Enforce safety protocols and workflows

Plugins in this bundle are copied from the local OpenCode plugin registry and packaged for reuse across installations.

---

## worktree.ts

**Purpose**: Creates isolated git worktrees for AI sessions and coordinates session state plus terminal spawning.

**Features**:

- Automatic worktree creation from base branches
- SQLite-backed session state persistence
- Cross-platform terminal spawning (tmux integration)
- Session lifecycle management (create, attach, cleanup)
- Port coordination across multiple worktrees

**Dependencies**:

- `./worktree/state` — SQLite persistence layer
- `./worktree/terminal` — Terminal session management
- `kdco-primitives/` — Shared library (project ID, shell escaping, tmux detection, temp paths, logging, timeout helpers, types)

**Install Target**: `$HOME/.opencode/plugin/worktree.ts`

---

## git-safety.ts

**Purpose**: Blocks destructive shell and git commands and reports working tree safety before risky operations.

**Features**:

- Detects destructive git operations (force push, hard reset, etc.)
- Blocks dangerous shell commands
- Provides pre-operation safety checks
- Reports working tree status (modified, staged, untracked files)
- Recommends protective actions before risky operations

**Dependencies**: None (self-contained)

**Install Target**: `$HOME/.opencode/plugin/git-safety.ts`

---

## review-enforcer.ts

**Purpose**: Injects review workflow instructions after task completion so plan execution gets reviewed consistently.

**Features**:

- Automatic review triggers on task completion
- Enforces review quality gates
- Integrates with review-protocol skill
- Ensures consistent review coverage across tasks

**Dependencies**: Works alongside `review-protocol/` skill

**Install Target**: `$HOME/.opencode/plugin/review-enforcer.ts`

---

## kdco-primitives/

**Purpose**: Shared library used by all plugins in the bundle. Provides common utilities and type definitions.

**Contents**:

- Project ID lookup and management
- Shell escaping utilities
- Tmux detection and helpers
- Temporary path generation
- Logging utilities
- Timeout helpers
- Shared TypeScript types

**Dependencies**: None (foundational library)

**Install Target**: `$HOME/.opencode/plugin/kdco-primitives/`

**Important**: This directory must be installed with the plugin bundle. Moving or removing it breaks worktree-related imports.

---

## worktree/ Subdirectory

The `worktree/` subdirectory contains supporting modules for the main `worktree.ts` plugin.

### worktree/state.ts

**Purpose**: SQLite-backed persistence for worktree session state and pending operations.

**Features**:

- Session state storage (worktree paths, branch names, ports)
- Pending operation tracking
- Cleanup queue management
- Cross-session state recovery

**Dependencies**: `kdco-primitives/`

**Install Target**: `$HOME/.opencode/plugin/worktree/state.ts`

### worktree/terminal.ts

**Purpose**: Cross-platform terminal spawning and tmux helpers.

**Features**:

- Spawn terminals on Linux and macOS
- Tmux session detection and management
- Terminal multiplexer integration
- Process lifecycle tracking

**Dependencies**: `kdco-primitives/`

**Install Target**: `$HOME/.opencode/plugin/worktree/terminal.ts`

---

## Dependency Graph

```
worktree.ts
├── worktree/state.ts
│   └── kdco-primitives/
├── worktree/terminal.ts
│   └── kdco-primitives/
└── kdco-primitives/

git-safety.ts
└── (self-contained)

review-enforcer.ts
└── (integrates with review-protocol skill)
```

---

## Installation Notes

1. **Complete Bundle Required**: The worktree plugin requires `worktree/state.ts`, `worktree/terminal.ts`, and `kdco-primitives/` to function. Install all files together.

2. **Relative Imports**: Plugins use relative imports (e.g., `./worktree/state`, `./kdco-primitives/`). Maintain the directory structure during installation.

3. **No Hardcoded Paths**: Packaged plugins use normalized paths. No personal paths or secrets are embedded.

4. **TypeScript Support**: Plugins are TypeScript modules. OpenCode loads them directly; no compilation step required.

---

## See Also

- [Skills Documentation](skills.md) — Review protocol integration
- [MANIFEST.md](../MANIFEST.md) — Complete artifact inventory
- `plugins/README.md` — Quick reference
