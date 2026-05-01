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

## Config-Layer Plugins

This document covers TypeScript plugins under `plugins/`. The repository also includes two config-layer JavaScript plugins that live in `configs/opencode/` and are documented in [Configuration Documentation](configs.md):

- **`provider-connect-retry.mjs`** — Consumes the `retry-errors.json` registry for error pattern matching, backoff scheduling, nudge prompts, and fallback model selection.
- **`aspect-dynamics.mjs`** — Performs deterministic heuristic scoring on conversation transcripts and dispatches transcript-visible advisory nudges. Uses 7 support modules under `aspect-dynamics/` and loads seed aspect sets from `aspect-dynamics/sets/`. No model-backed scoring in MVP; deferred fields (`scoringModel`, `polishingModel`, `dreamAgent`) are reserved for future use.

---

## session-id.ts

**Purpose**: Copies the invoking OpenCode session ID to the clipboard without any LLM round-trip.

**Features**:

- Intercepts `/session-id` via `command.execute.before`
- Uses the invoking hook's `sessionID` directly
- Writes the raw session ID to the system clipboard with `xclip`

**Dependencies**: None (self-contained)

**Install Target**: `$HOME/.opencode/plugin/session-id.ts`

---

## session-info.ts

**Purpose**: Copies project path, git branch, session title, and invoking session ID to the clipboard without any LLM round-trip.

**Features**:

- Intercepts `/session-info` via `command.execute.before`
- Resolves the active branch from the current worktree/project directory
- Reads the invoking session title from the SDK using the hook's `sessionID`
- Writes `Project <path>:<branch>; Session <title>; ID <session-id>` to the system clipboard with `xclip`

**Dependencies**: OpenCode plugin client session API

**Install Target**: `$HOME/.opencode/plugin/session-info.ts`

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

**Purpose**: Injects review workflow instructions after task completion so plan execution gets reviewed consistently. Also enforces the Live Deployment Verification Gate by requiring agents to distinguish between evidence states when reporting deployment status.

**Features**:

- Automatic review triggers on task completion
- Enforces review quality gates
- Integrates with review-protocol skill
- Ensures consistent review coverage across tasks
- **Live Deployment Gate**: Agents must report evidence states accurately. Unverified live or runtime states must be flagged with `Not verified live: [missing state]`.

**Dependencies**: Works alongside `review-protocol/` skill

**Install Target**: `$HOME/.opencode/plugin/review-enforcer.ts`

---

## auto-checkpoint.ts

**Purpose**: Creates semantic session-scoped git checkpoint commits when sessions become idle or complete work, using an LLM helper session to select files and compose messages from a bounded candidate set.

**Features**:

- **Root-session-tree scoping**: Only files attributed to the current root session tree are eligible for checkpointing. Child-session work rolls up to its root and never creates standalone checkpoints.
- **Deterministic path attribution**: Tracks file ownership via `tool.execute.before`/`after` hooks, marking newly dirty paths per root session. Baseline-dirty and multi-root-conflicted paths are excluded.
- **Helper-session semantic selection**: Creates an ephemeral helper session with a `[auto-checkpoint helper]` title prefix, dispatches a strict JSON prompt with candidate files and diff payload, polls for response, and deletes the helper session afterward.
- **Temp-index safety**: Stages validated semantic subsets through an isolated temporary git index (`GIT_INDEX_FILE`), leaving the real index untouched whether the commit succeeds or skips.
- **Skip-on-ambiguity guards**: Skips checkpointing when candidates are empty, binary, oversized, conflicted, or when the LLM returns malformed/low-confidence/out-of-scope proposals.
- **Mutex-time revalidation**: All expensive operations (candidate collection, LLM proposal, commit staging) occur inside the worktree mutex with revalidation of idle state, HEAD SHA, and dirty tree.

**Dependencies**: None (self-contained)

**Install Target**: `$HOME/.opencode/plugin/auto-checkpoint.ts`

---

## vera-runtime.ts

**Purpose**: Supervises Vera semantic search watchers during active OpenCode sessions, ensuring indexes stay fresh without manual intervention.

**Features**:

- **Fail-open behavior**: If the `vera` binary is missing, the plugin logs a warning and continues normal operation without error
- **Automatic watcher lifecycle**: Hooks into `session.created` to start watchers, `session.deleted` to stop them
- **Tool execution guard**: `tool.execute.before` hook verifies watcher health before file-modifying tools run
- **Health checks**: Every 60 seconds verifies the watcher PID is still alive
- **State persistence**: Tracks watcher state per project in `~/.local/share/opencode/worktree-state/<project-id>/vera-watchers/`

**Event Hooks**:

| Hook | When Fired | Action |
|------|-----------|--------|
| `session.created` | New session starts | Start or verify Vera watcher for the project |
| `session.deleted` | Session ends | Stop Vera watcher if no other sessions need it |
| `tool.execute.before` | Before any tool executes | If tool modifies files, trigger `vera update .` |

**Dependencies**: None (self-contained; falls open if `vera` binary absent)

**Active Registration Requirement**:

`vera-runtime.ts` must be registered in the active `opencode.json` plugin array. The verifier checks this with:

```bash
grep -q 'vera-runtime' "$HOME/.config/opencode/opencode.json"
```

If the plugin is present at the install target but not registered in the active config, OpenCode will not load it. After adding the plugin to `opencode.json` in the repo, the symlinked config makes the change immediately active.

**Install Target**: `$HOME/.opencode/plugin/vera-runtime.ts`

**Log Location**: `$HOME/.opencode/plugin/vera-runtime.log`

**State Location**: `~/.local/share/opencode/worktree-state/<project-id>/vera-watchers/`

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
