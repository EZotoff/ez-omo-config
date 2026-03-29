# parallel-dev

**Base directory**: `~/.config/opencode/skills/parallel-dev`

## Skill: parallel-dev

Coordinate multi-agent parallel development with isolated worktrees, state-driven monitoring, and safe merge handoff.

**Triggers**: `/parallel-dev`, `parallel development`, `spawn agents`

---

See `SKILL.md` for full instructions.

## Installation

```bash
# Copy to active OpenCode skills directory
cp SKILL.md ~/.config/opencode/skills/parallel-dev.md
```

## Quick Reference

```bash
# Evaluate and execute parallel development
/parallel-dev

# The skill will:
# 1. Run decision framework (should I parallelize?)
# 2. Pre-flight checks (capacity, dependencies)
# 3. Spawn worktrees via worktree_create
# 4. Dispatch tasks to spawned agents
# 5. Monitor progress via state files
# 6. Trigger merge when complete
```

## Decision Framework

**Before parallelizing, ask:**
1. Can work be split into 2+ INDEPENDENT subtasks?
2. Will each subtask touch DIFFERENT files?
3. Is total effort > 30 minutes?

If ALL yes → consider parallelizing. Otherwise → sequential.
