# Plugin System

The OpenCode plugin system extends agent capabilities through TypeScript-based plugins that hook into the agent lifecycle. Plugins in this repository provide git worktree management, safety enforcement, review workflow automation, and configured loop-pattern mitigation.

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

- **`provider-connect-retry.mjs`** — Consumes the `retry-errors.json` registry for error pattern matching, backoff scheduling, nudge prompts, and unified agent-chain fallback. On exhaustion, fallback is resolved from the failing session's agent `fallback_models` chain in `oh-my-openagent.json` (same-provider entries skipped, so self-fallback is structurally impossible). Surfaces terminal conditions (no eligible agent-chain fallback, retries exhausted, dispatch failures) as TUI toasts via `ctx.client.tui.showToast`; routine operation is logged to `~/.config/opencode/retry-plugin.log` only. See [Configuration Documentation](configs.md) for the fallback resolution and toast behavior.
- **`aspect-dynamics.mjs`** — Performs deterministic heuristic scoring on conversation transcripts and dispatches transcript-visible advisory nudges. Uses 7 support modules under `aspect-dynamics/` and loads seed aspect sets from `aspect-dynamics/sets/`. No model-backed scoring in MVP; deferred fields (`scoringModel`, `polishingModel`, `dreamAgent`) are reserved for future use.

---

## session-id.ts

**Purpose**: Copies the invoking OpenCode session ID to the clipboard and cancels the command pipeline via the local OpenCode command-hook cancellation patch.

**Features**:

- Intercepts `/session-id` via `command.execute.before`
- Uses the invoking hook's `sessionID` directly
- Writes the raw session ID to the system clipboard with `xclip`
- Clears `output.parts` and sets `output.cancelled = true`; true no-LLM behavior requires the active `opencode--command-hook-cancellation` local OpenCode patch

**Dependencies**: Active local OpenCode `opencode--command-hook-cancellation` patch for true no-LLM cancellation

**Install Target**: `$HOME/.opencode/plugin/session-id.ts`

---

## session-info.ts

**Purpose**: Copies project path, git branch, session title, and invoking session ID to the clipboard and cancels the command pipeline via the local OpenCode command-hook cancellation patch.

**Features**:

- Intercepts `/session-info` via `command.execute.before`
- Resolves the active branch from the current worktree/project directory
- Reads the invoking session title from the SDK using the hook's `sessionID`
- Writes `Project <path>:<branch>; Session <title>; ID <session-id>` to the system clipboard with `xclip`
- Clears `output.parts` and sets `output.cancelled = true`; true no-LLM behavior requires the active `opencode--command-hook-cancellation` local OpenCode patch

**Dependencies**: OpenCode plugin client session API; active local OpenCode `opencode--command-hook-cancellation` patch for true no-LLM cancellation

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

**Purpose**: Blocks destructive shell and git commands and reports working tree safety before risky operations. Three defence layers, each catching a distinct class of destructive action.

**Features**:

- **Layer 1 — Always-block (non-git)**: `rm -rf` outside the safe-cleanup list (node_modules, dist, .cache, etc.), `find -delete`, `curl|bash`, `docker compose down -v`, `chmod -R 777`, `chmod 000`, `dd of=/dev/`, `mkfs`, `shred`, `wipefs`. Blocked regardless of git state.
- **Layer 1.5 — History rewrite (always-block, post-commit)**: `git commit --amend`, `git rebase` (except `--abort`/`--continue`/`--skip`), `git push --force` / `-f` / `--force-with-lease`, `git branch -D`, `git stash clear`, `git reflog expire`, `git gc --prune[=now]`, and `git reset [--soft|--mixed|--hard] <ref>` where `<ref>` resolves to a strict ancestor of HEAD. **Always blocked regardless of dirty-tree state** — the dominant post-commit destructive pattern (agent commits, then resets/amends/rebases to discard commits) has a clean tree by definition, so Layer 2's dirty-tree gate misses it. Forensic origin: veran `feat/compounding-capture-additions`, session `ses_02c3a15e` — agent ran `git revert` twice then `git reset --hard <revert-pre-tip>` to discard the reverts; tree was clean → guard allowed it → 2 commits orphaned.
- **Layer 1.5b — Reset-ancestor async check**: For `git reset <ref>`, the plugin resolves `<ref>` to a SHA, compares to HEAD, and runs `git merge-base --is-ancestor <sha> HEAD`. Blocks only if `<ref>` is a strict ancestor (HEAD will move backward). Allows fast-forward resets, no-op resets (`reset --hard HEAD`), and file-path resets (`reset HEAD <file>` — `<file>` doesn't resolve to a commit).
- **Layer 2 — Dirty-tree conditional (git)**: `git reset --hard` (no ref), `git checkout --`, `git checkout .`, `git restore` (without `--staged`), `git clean -f`, `git stash drop`, `git checkout -f`. Blocked when the working tree is dirty; clean tree → allowed. On block, the plugin attempts a protective auto-stash before throwing, so the user's uncommitted work survives.
- **Worktree-aware (Fix A)**: All git-state checks (`isInGitRepo`, `gitStatus`, `gitStashPush`, `detectResetRewrite`) run at the bash command's actual cwd, resolved as `output.args.workdir` → leading `cd <path> &&` in the command string → `ctx.directory`. Without this, an agent operating in a git worktree (e.g. `/start-work` worktree mode) would bypass every git-state check, because `ctx.directory` is the OpenCode project root, not the worktree.
- **Pre-operation safety check tool**: `git_safety_check` returns the dirty-tree status of the project root with file lists and recommended protective action.
- **Commit-message payload stripping (false-positive mitigation)**: Pattern matching runs on a sanitized command with `git commit -m "..."` / `git tag -m "..."` / `--message="..."` payloads replaced by `<msg>`. Without this, any commit message that mentions a destructive command (e.g. citing `git reset --hard <sha>` as forensic evidence) false-positives and blocks the commit itself — empirically observed twice during A+B development. Real destructive ops sit OUTSIDE quoted message payloads, so stripping eliminates false positives without introducing false negatives. Handles multiple `-m` flags and bash ANSI-C `$'...'` quoting; does not handle escaped quotes inside the message (rare in agent practice) or heredoc (`-F` already keeps the message body out of the command string).
- **Test hooks via globalThis**: Pure helpers (`parseLeadingCd`, `resolveWorkdir`, `detectHistoryRewriteCommand`, `detectResetRewrite`, `stripCommitMessagePayloads`, `HISTORY_REWRITE_PATTERNS`) are exposed on `globalThis.__gitSafetyTestHooks` for unit testing (`tests/git-safety/harness.ts`). They MUST NOT be a module export: OpenCode's plugin loader rejects any module with a non-function export, which silently disabled this plugin 2026-08-06..2026-08-20.
- **`__test__` export**: Pure helpers (`parseLeadingCd`, `resolveWorkdir`, `detectHistoryRewriteCommand`, `detectResetRewrite`, `HISTORY_REWRITE_PATTERNS`) are exported as a named `__test__` symbol for unit testing — see `tests/git-safety/harness.ts`.
**Dependencies**: None (self-contained)

**Install Target**: `$HOME/.opencode/plugin/git-safety.ts`

---

## review-enforcer.ts

**Purpose**: Injects review workflow instructions after task completion so plan execution gets reviewed consistently. Also enforces the Live Deployment Verification Gate by requiring agents to distinguish between evidence states when reporting deployment status.

**Features**:

- Automatic review triggers on task completion
- Automatic review triggers on task completion
- Enforces review quality gates
- **Gated injection**: consultative subagent or category dispatches (oracle/metis/momus/explore/librarian/multimodal-looker/document-writer, category mephistopheles) are skipped — analysis work has no implementation to review — as are OMO sync-task abort stubs, degenerate near-empty outputs (<250 chars, no success indicator), and dispatches carrying the `[REVIEW-TASK]`/`[REVIEW-FIX]`/`[DEBATE]` marker (the `/debate` skill prefixes all its dispatch prompts with `[DEBATE]`, covering judge categories artistry/writing/ultrabrain which also do implementation work elsewhere). Plan-complete injection requires the current session to be in the active boulder's `session_ids` lineage (mirrors OMO's `resolveActiveBoulderSession` predicate; legacy bare ids normalized with the `opencode:` prefix) and a status other than paused/abandoned. Guards against stale machine-global `boulder.json` hijacking unrelated sessions (2026-08-16 misfire; pairs 014/015) and review mandates stamped on provider-exhausted abort stubs (2026-08-19 misfire; pair 016).
- Integrates with review-protocol skill
- **CRITICAL closeout semantics (2026-09-09)**: the injected instruction states that after the maximum two review cycles, unresolved CRITICAL findings require handler closeout (RULE/BLOCK/PARK) and must never be represented as approval (regression pair 019)
- Runs `tests/run_regressions.sh` and includes the regression corpus output in review and plan-completion instructions
- Ensures consistent review coverage across tasks
- **Live Deployment Gate**: Agents must report evidence states accurately. Unverified live or runtime states must be flagged with `Not verified live: [missing state]`.

**Live Deployment Gate Checklist (Inline)**:

The plugin enforces the following inline checklist on agents after implementation work:

1. **repo_implemented** — Confirm code exists in repository and is tracked by git
2. **tests_passed** — Verify automated tests pass (unit, integration, build)
3. **live_file_installed** — Check file is present at live target path (symlink or copy)
4. **active_config_registered** — Verify artifact is referenced in active config (plugin array, skill list)
5. **runtime_loaded** — Confirm runtime has loaded/invoked the artifact (handler called, skill dispatched)
6. **real_project_behavior_proven** — Validate artifact's effect observed in real project with concrete evidence

**Claim Language Enforcement**:

At each evidence state, agents may only use approved claim language:

| State | May Say | Must Not Say |
|-------|---------|--------------|
| repo_implemented | "implemented in repo" | "installed", "active", "working" |
| tests_passed | "repo tests pass" | "deployed", "runtime verified" |
| live_file_installed | "installed at live target" | "loaded" |
| active_config_registered | "registered in active config" | "runtime loaded" |
| runtime_loaded | "plugin loaded/handler invoked" | "end-to-end working" |
| real_project_behavior_proven | "working for [project]" (with evidence) | — |

**Unverified State Rule**: If any live/runtime state is unverified, output must include: `Not verified live: [missing state]`

**Plan Completion Closeout Summary**: When all plan tasks are complete, the plugin injects a `PLAN_COMPLETION_INSTRUCTION` requiring a response-only `Closeout Summary` covering TLDR of functionality created, expected behavior, user testing follow-up, and an evidence caveat (`Not verified live: [missing state]`). The closeout must not be written to `.sisyphus/`, notepads, evidence files, or wisdom — it is response-only.

**Dependencies**: `plugins/review-enforcer/helpers.ts` (pure gating helpers — MUST stay out of the plugin entry: OpenCode's plugin loader calls every function export of a plugin module as a plugin constructor, so exported helpers got invoked with PluginInput and threw `output.includes is not a function` on every fresh server, 2026-09-08; regression pair 018). Works alongside `review-protocol/` skill

**Install Target**: `$HOME/.opencode/plugin/review-enforcer.ts`

---

## auto-checkpoint.ts

**Purpose**: Creates semantic session-scoped git checkpoint commits when sessions become idle or complete work, using an LLM helper session to select files and compose messages from a bounded candidate set.

**Runtime default**: Enabled on this machine via `OPENCODE_AUTO_CHECKPOINT_ENABLE=1` set in **both** EnvironmentFiles that feed OpenCode servers: `~/.config/openchamber/openchamber.env` (for `opencode.service` on port 3021, used by the OpenChamber web UI) AND `~/AI_projects/omo-tg/.env` (for `omo-tg.service`, which spawns its own `opencode serve --port 4096` child for Telegram-driven sessions). File logging is also enabled via `OPENCODE_AUTO_CHECKPOINT_FILE_LOG=1` in both files. On a fresh install without these env vars, the plugin loads but returns empty hooks (no checkpoints). To enable on another machine, set both env vars in whatever EnvironmentFile(s) the OpenCode systemd units consume, then restart the corresponding services.

**Two-server gotcha**: This machine runs two `opencode serve` processes — one per systemd unit. Each unit has its own EnvironmentFile, and child processes inherit only the parent unit's env. Setting the vars in only one file enables the plugin on only one server. Always set in both, and verify via `tr '\0' '\n' < /proc/$(pgrep -f 'opencode serve' | head -1)/environ | grep CHECKPOINT`.

**Timing**: `idleMs=30000` (30s session idle before a checkpoint is considered), `quietMs=5000` (5s no-tool-activity signal), `cooldownMs=300000` (at most one checkpoint per 5 minutes per root session tree).

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

---

## agent-git-workflow.ts

**Purpose**: Force-loads a parallel-agent git coordination procedure into every session's system prompt via `experimental.chat.system.transform`. Supplies the procedural layer that the commit-policy patches (permission) and auto-checkpoint plugin (idle-timeout safety-net commits) cannot provide on their own: when to branch, when to sync, how to format commits so other agents can parse history, how to handle merge conflicts.

**Hook**: `experimental.chat.system.transform` — appends one ~350-token instruction block to `output.system` per LLM round-trip. Fail-open (throws caught by host). Same pattern as `clickable-links.ts`.

**What it tells agents**:

- **Commit reflex**: commit after every logical unit (bug fixed, refactor step done, feature slice complete, tests written). Do not wait for auto-checkpoint; do not ask.
- **Commit format**: Conventional Commits subject only. No author override, no trailers, no footers — attribution is owned by the active Git config and `git_master` setting.
- **Branching reflex**: at the start of non-trivial work, check `git log --since='2 hours ago' --all` and `git branch -a`. Branch as `agent/<agent-name>/<task-scope>` if another agent's work overlaps your target files. Otherwise master/trunk is fine.
- **Sync protocol**: on a branch older than 30 min, `git fetch && git rebase origin/master` before non-trivial edits. Resolve conflicts directly.
- **Branch lifecycle (worktree-aware)**: merge with `--no-ff` from the main worktree, then `git worktree remove <path>` and `git branch -d` (lowercase; `-D` is blocked by git-safety). Prefer the `worktree_delete` tool for worktree branches — it runs pre-delete hooks and snapshots dirty trees. Never silently discard uncommitted work in a completed worktree. Push only when explicitly authorized.
- **Out of scope**: idle checkpoints (auto-checkpoint), multi-agent worktree orchestration (parallel-dev skill), complex merges with state tracking (merge-agent skill).

**Why this is a plugin, not a skill**: the user reported that permissive commit text in the base system prompt was insufficient — agents still didn't commit proactively because they had permission but no trigger or procedure. A skill would require explicit invocation; this plugin force-loads the procedure into every session so the reflex is always present. The procedure is short enough (~350 tokens) that the per-session cost is negligible.

**Complementary artifacts**:
- `opencode--commit-policy-unblock` patch — replaces blanket "never commit" with permissive policy in OpenCode system prompts.
- `omo--commit-policy-alignment` patch — same replacement in OMO agent instructions.
- `auto-checkpoint.ts` plugin — idle-timeout safety-net commits.
- `clickable-links.ts` plugin — same hook pattern, different purpose (TUI link formatting).

**Dependencies**: None (self-contained, type-only import from `@opencode-ai/plugin`).

**Install Target**: `$HOME/.opencode/plugin/agent-git-workflow.ts`

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
└── review-enforcer/helpers.ts  # pure gating helpers (loader never auto-loads subdirectories)

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

---

## Dropped Command-Level Patch Guard

The command-level patch guard plugin was dropped in Track B v2. It was superseded by the inotify watcher (`opencode-patch-watcher.service`), which catches writes at the kernel event level regardless of mechanism. The regex-based allowlist approach could not cover the unbounded set of file-writing mechanisms on Linux.
