# Worktree Coordinator System

This directory contains documentation for the worktree parallel development system.

## Components

| Component | Location | Purpose |
|-----------|----------|---------|
| **merge-agent skill** | `skills/merge-agent/` | Safe branch merging with guardrails |
| **parallel-dev skill** | `skills/parallel-dev/` | Multi-agent orchestration coordinator |
| **State schema** | `docs/worktree-state-schema.md` | Runtime state file formats |
| **Hook scripts** | `scripts/worktree-*.sh` | postCreate/preDelete lifecycle hooks |
| **Docker template** | `docker/worktree-compose.template.yml` | Per-worktree container isolation |
| **Config** | `configs/opencode/worktree.jsonc` | Worktree sync and hook configuration |

## Installation

### 1. Skills

```bash
# Copy skills to active OpenCode config
cp skills/merge-agent/SKILL.md ~/.config/opencode/skills/merge-agent.md
cp skills/parallel-dev/SKILL.md ~/.config/opencode/skills/parallel-dev.md
```

### 2. Scripts

```bash
# Copy hook scripts to project's .opencode directory
mkdir -p /path/to/your/project/.opencode/scripts
cp scripts/worktree-post-create.sh /path/to/your/project/.opencode/scripts/
cp scripts/worktree-pre-delete.sh /path/to/your/project/.opencode/scripts/
chmod +x /path/to/your/project/.opencode/scripts/*.sh
```

### 3. Config

```bash
# Copy worktree.jsonc to project's .opencode directory
cp configs/opencode/worktree.jsonc /path/to/your/project/.opencode/
```

### 4. Docker (optional)

```bash
# Copy Docker template if using containerized dev environments
mkdir -p /path/to/your/project/.opencode/docker
cp docker/worktree-compose.template.yml /path/to/your/project/.opencode/docker/
```

## System-Specific Adaptations

### Paths

All scripts use `$HOME` for portability. No hardcoded `/home/username/` paths.

### State Directory

Runtime state lives at `~/.local/share/opencode/worktree-state/<project-id>/`:
- **NOT committed to git** (runtime state only)
- Shared across all worktrees of the same project

### Port Range

Default: 3100-3199. Modify in `worktree-post-create.sh` if conflicts occur:

```bash
for PORT in $(seq 3100 3199); do
```

### MAX_PARALLEL

Default: 4 concurrent worktrees. Modify in `worktree-post-create.sh`:

```bash
if [ "$ACTIVE_COUNT" -ge 4 ]; then
```

## Prerequisites

- **ocx** (OpenCode Extension Manager): `curl -fsSL https://ocx.kdco.dev/install.sh | sh`
- **opencode-worktree plugin**: `ocx add kdco/worktree`
- **jq**: For JSON state file manipulation
- **docker** (optional): For containerized worktrees

## Decision Framework

Before parallelizing, agents should evaluate:

1. **Independence**: Can work be split into 2+ INDEPENDENT subtasks?
2. **File overlap**: Will each subtask touch DIFFERENT files?
3. **Effort**: Is total effort > 30 minutes?

If ALL yes → consider parallelizing. Otherwise → sequential execution.

See `skills/parallel-dev/SKILL.md` for full decision matrix.
