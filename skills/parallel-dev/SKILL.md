# parallel-dev

## Should I Parallelize? Decision Framework

BEFORE spawning worktrees, evaluate:

### MANDATORY Preconditions (ALL must be YES)
1. Can the work be split into 2+ INDEPENDENT subtasks? (no shared state, no sequential dependencies)
2. Will each subtask touch DIFFERENT files? (minimal overlap = minimal merge conflicts)
3. Is the total effort > 30 minutes? (parallelization overhead: ~5 min setup + ~5 min merge per agent)

### Risk Assessment (proceed if acceptable)
4. If one agent fails, can others continue? (failure isolation)
5. Can merge conflicts be resolved? (same-file changes = high conflict risk)

### Decision Matrix
| Subtasks | File Overlap | Effort | Decision |
|----------|--------------|--------|----------|
| 1        | N/A          | Any    | ❌ NO — not parallelizable |
| 2+       | None         | <30min | ❌ NO — overhead exceeds benefit |
| 2+       | None         | >30min | ✅ YES — parallelize |
| 2+       | Some         | >30min | ⚠️ CAUTION — plan for conflicts |
| 2+       | High         | Any    | ❌ NO — sequential is safer |

### Examples
- ✅ "Implement auth + Implement payments" → Different modules, parallelize
- ✅ "Fix bug in API + Add tests for utils" → Different files, parallelize
- ❌ "Refactor X + Add feature using X" → Sequential dependency, sequential execution
- ❌ "Fix typo + Update README" | <5min total → Overhead exceeds benefit, sequential
- ⚠️ "Update header in app.tsx + Add route in app.tsx" → Same file, sequential or plan for conflict

---

## Header

- **Name**: `parallel-dev`
- **Description**: Coordinate multi-agent parallel development with isolated worktrees, state-driven monitoring, and safe merge handoff
- **Triggers**: `/parallel-dev`, `parallel development`, `spawn agents`

---

## Workflow Overview

```text
Decision Framework
  → Pre-Flight Check
  → Spawn Worktrees
  → Dispatch Tasks
  → Monitor Progress
  → Trigger Merge
  → Cleanup/Close
```

Lifecycle: **Decision → Spawn worktrees → Dispatch tasks → Monitor → Merge → Cleanup**.

---

## TODO Tracking (Coordinator)

Use this checklist to keep orchestration deterministic:

- [ ] Phase 1 complete: pre-flight checks passed and capacity available
- [ ] Phase 2 complete: required worktrees created via `worktree_create`
- [ ] Phase 3 complete: task dispatch delivered to each spawned agent
- [ ] Phase 4 complete: status monitored until terminal state
- [ ] Phase 5 complete: merge triggered (self-triggered or coordinator-triggered)
- [ ] Phase 6 complete: failures handled, stale worktrees cleaned where required

---

## Phase 1: Pre-Flight Check

### Goals
Validate that the coordinator can safely launch additional parallel agents.

### Capacity Rule (MAX_PARALLEL)
- **Hard limit**: `MAX_PARALLEL=4` active worktrees.
- If active worktrees are already 4, do not spawn more; queue or defer tasks.

### Required Checks

1) Resolve project state root:

```text
~/.local/share/opencode/worktree-state/<project-id>/
```

2) Inspect active worktree state files:

```bash
ls ~/.local/share/opencode/worktree-state/<project-id>/worktrees/
```

3) Count active entries:

```bash
grep -l '"status": *"active"' *.json | wc -l
```

4) Abort spawning when count >= 4.

### Important Boundary
- Coordinator **reads** state under `~/.local/share/opencode/worktree-state/<project-id>/`.
- Coordinator does **not** create or initialize state files; hook scripts own state creation.

---

## Phase 2: Spawning Agents in Worktrees

### Tool Contract
Use:

```text
worktree_create(branch, baseBranch?)
```

Critical behavior:
- `worktree_create` returns a **message string** (NOT `session_id`).
- The plugin opens a new tmux window named after the branch.
- That tmux window runs an independent OpenCode instance for the spawned worktree.

### Port and Runtime Context
After spawning, read branch state:

```text
~/.local/share/opencode/worktree-state/<project-id>/worktrees/<branch>.json
```

Extract runtime metadata (for dispatch instructions), including allocated port.

### State Ownership
- Post-create hook (`.opencode/scripts/worktree-post-create.sh`) creates state and starts Docker.
- Coordinator **must not** recreate this logic.

---

## Phase 3: Dispatching Work

Use one of two delivery mechanisms.

### Option A: Task File (preferred)

1. Before `worktree_create`, write task instructions to:

```text
~/.local/share/opencode/worktree-state/<project-id>/tasks/<branch>.md
```

2. Post-create hook copies this to spawned worktree:

```text
.opencode/current-task.md
```

3. Spawned agent reads `.opencode/current-task.md` on startup.

Why preferred:
- Durable handoff and easy audit trail in `worktree-state` task artifacts.

### Option B: tmux send-keys

After `worktree_create`, send instructions directly:

```text
interactive_bash(tmux_command="send-keys -t <branch-name> '<instructions>' Enter")
```

Use for quick or recovery dispatch when task file is unavailable.

### Agent Instructions Template (mandatory guardrails)

```text
You are working in worktree branch <branch>.
- NEVER switch to main branch
- NEVER modify files outside this worktree
- Your app is served at http://localhost:<port>
- When done: commit all changes, then load merge-agent skill: /merge-worktree <branch>
```

Additional dispatch rule:
- Do **not** use `task()` for worktree dispatch; it runs in the current session, not the spawned worktree.

---

## Phase 4: Monitoring Progress

### Status Polling
Monitor each branch state file in:

```text
~/.local/share/opencode/worktree-state/<project-id>/worktrees/<branch>.json
```

Expected status flow:

```text
active → merging → completed | failed
```

### Timeout Enforcement
- Read `timeoutAt` from state.
- If current time > `timeoutAt` while status is still `active`, initiate timeout cleanup path (Phase 6).

### Tmux Visibility
Check window presence and activity:

```text
interactive_bash(tmux_command="list-windows")
```

---

## Phase 5: Merge Triggering

### Preferred Path
Agents self-trigger merge by following the dispatch template:

```text
/merge-worktree <branch>
```

### Coordinator Fallback
If coordinator observes branch ready/completed-but-not-merged state, send merge command via tmux:

```text
interactive_bash(tmux_command="send-keys -t <branch-name> '/merge-worktree <branch>' Enter")
```

### Merge Implementation
- Merge orchestration must use merge-agent skill (`load_skills=["merge-agent"]` behavior in the merge worker context).
- Coordinator should not duplicate merge-agent internals.

---

## Phase 6: Failure Handling

### Timeout
- Condition: `timeoutAt` elapsed and status remains `active`.
- Action: trigger worktree cleanup:

```text
worktree_delete("timeout")
```

### Failed Status
- Condition: state transitions to `failed`.
- Action: flag for human review and keep worktree for debugging unless explicit cleanup requested.

### Cleanup Hooks
- Cleanup automatically invokes pre-delete hook (`.opencode/scripts/worktree-pre-delete.sh`).
- Coordinator should rely on hook side effects instead of re-implementing them.

---

## Non-Negotiable Guardrails

- Never create custom state roots (do not use `.sisyphus/`).
- Never have coordinator write canonical state files in `worktrees/` directly.
- Never implement agent-to-agent messaging in this skill.
- Never implement custom tmux session management.
- Always use `~/.local/share/opencode/worktree-state/<project-id>/` as the state authority.

---

## Quick Operator Checklist

1. Apply decision framework first.
2. Enforce `MAX_PARALLEL=4`.
3. Spawn with `worktree_create` and treat return as message string.
4. Read `<branch>.json` for allocated port and runtime status.
5. Dispatch via **task file** (preferred) or **send-keys**.
6. Monitor status/timeouts until `completed` or `failed`.
7. Ensure merge runs through merge-agent.
8. Cleanup timeout branches and preserve failed branches for debug.
