# merge-agent

**Base directory**: `~/.config/opencode/skills/merge-agent`

## Skill: merge-agent

Merge feature branches into main/master with conflict detection, rollback support, and guardrails.

**Triggers**: `/merge-worktree`, `merge branch`, `merge worktree`, `integrate branch`

---

See `SKILL.md` for full instructions.

## Installation

```bash
# Copy to active OpenCode skills directory
cp SKILL.md ~/.config/opencode/skills/merge-agent.md
```

## Quick Reference

```bash
# Merge current branch to main
/merge-worktree

# The skill will:
# 1. Validate pre-merge conditions
# 2. Acquire merge lock
# 3. Rebase onto main
# 4. Fast-forward merge
# 5. Release lock
```
