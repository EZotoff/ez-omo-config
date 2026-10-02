# /merge-worktree

Safely merge a worktree branch into main with strict local state tracking, lock discipline, and deterministic rollback.

## Header

- **Name**: `merge-agent`
- **Description**: Safely merge worktree branches into main with state tracking and conflict resolution
- **Triggers**: `/merge-worktree`, `merge branch`, `integrate worktree`

---

## Usage

```text
/merge-worktree <branch>
/merge-worktree --branch=<branch>
```

Optional runtime context:

- `project-id`: Used for state path resolution under `~/.local/share/opencode/worktree-state/<project-id>/`
- `session-id`: Used for merge lock ownership (`lockedBy`)

---

## Overview

This skill performs a guarded local-only merge flow:

1. **Pre-Merge Validation** — ensure we are in a feature worktree and clean
2. **Merge Lock Acquisition** — serialize merges via `merge.lock`
3. **Rebase Before Merge** — rebase branch onto `origin/main`
4. **Merge Execution** — merge from the **main worktree**, never from feature worktree context
5. **Post-Merge Cleanup** — finalize state, release resources, remove worktree
6. **Rollback** — deterministic failure handling for each failure mode

---

## Pre-Merge Validation

### 1) Verify we are in a worktree (NOT primary main checkout)

Run:

```bash
git rev-parse --git-common-dir
```

Rules:

- If result equals `.git` (or resolves to primary checkout root), **STOP**.
- Merge execution must originate from a feature worktree session, but actual merge command runs in the main worktree path using `git -C`.

### 2) Verify working tree is clean

Run:

```bash
git status --porcelain
```

Rules:

- Any output means uncommitted changes exist.
- **STOP** until all changes are committed.

### 3) Load branch state

Read state file:

```text
~/.local/share/opencode/worktree-state/<project-id>/worktrees/<branch>.json
```

Validate:

- file exists
- `branch` matches target branch
- `status` is eligible (`ready` or `merging` recovery state)
- `worktreePath` exists

If validation fails: mark state `failed` if possible and stop.

---

## Merge Lock Acquisition

Lock path:

```text
~/.local/share/opencode/worktree-state/<project-id>/merge.lock
```

Queue path:

```text
~/.local/share/opencode/worktree-state/<project-id>/merge-queue.json
```

### Lock algorithm

1. Check whether `merge.lock` exists.
2. If locked: wait **10 seconds**, retry, max **5 attempts**.
3. If still locked after 5 attempts: fail safely (`status=failed`) and stop.
4. On lock acquisition, write lock JSON:

```json
{
  "branch": "<branch>",
  "lockedAt": "<ISO timestamp>",
  "lockedBy": "<session-id>",
  "pid": 12345
}
```

5. Update `merge-queue.json`:
   - set `activeMerge` to `{ branch, lockedAt, lockedBy }`

Lock/state update requirements:

- Any failure writing lock/queue => rollback lock and stop.
- Merge lock must be removed on every terminal path (success or failure).

---

## Rebase Before Merge

From feature worktree:

```bash
git fetch origin main
git rebase origin/main
```

### Conflict policy (simple auto-resolution only)

- **Lockfiles**: accept **ours**
  - `package-lock.json`
  - `bun.lock`
- **Config files**: accept **theirs**

Suggested commands for simple cases:

```bash
git checkout --ours package-lock.json bun.lock
git checkout --theirs <config-file>
git add package-lock.json bun.lock <config-file>
git rebase --continue
```

### Complex conflicts

If conflict spans source logic, many files, or unclear intent:

1. `git rebase --abort`
2. Update worktree state `status` to `failed`
3. Clear `activeMerge` in `merge-queue.json`
4. Remove `merge.lock`
5. Flag for human review and stop

Do **not** perform AI-driven semantic conflict resolution beyond the simple rules above.

---

## Merge Execution (CRITICAL)

### Hard rule

**NEVER run `git checkout main` inside feature worktree** — main is already checked out in the primary worktree.

### 1) Locate main worktree path

```bash
git worktree list | grep '\[main\]\|\[master\]' | awk '{print $1}'
```

If no main/master worktree found: fail, release lock, stop.

### 2) Execute merge from main worktree

```bash
git -C <main-worktree-path> merge --no-ff <branch> -m "merge: <branch> into main"
```

### 3) Validate merged state with tests

```bash
cd <main-worktree-path> && npm test
```

If tests fail:

1. `git -C <main-worktree-path> merge --abort`
2. Update worktree state `status` to `failed`
3. Clear `activeMerge` in `merge-queue.json`
4. Remove `merge.lock`
5. Stop

---

## Post-Merge Cleanup

On successful merge + tests:

1. Update worktree state:
   - set `status` to `completed`
2. Update merge queue:
   - remove branch from `queue`
   - set `activeMerge` to `null`
3. Remove lock file:
   - `~/.local/share/opencode/worktree-state/<project-id>/merge.lock`
4. Free allocated port in:
   - `~/.local/share/opencode/worktree-state/<project-id>/ports.json`
5. Stop related container:
   - `docker compose -f <compose-file> down`
6. Delete worktree using `worktree_delete` tool
7. Remove branch state file:
   - `~/.local/share/opencode/worktree-state/<project-id>/worktrees/<branch>.json`

Final invariant: no stale lock, no stale active merge, no stale state entry.

---

## Guardrails (MUST INCLUDE)

- **NEVER run `git push`**
- **NEVER force-push**
- **NEVER delete main branch**
- **NEVER run git operations from wrong worktree**
- Never bypass lock acquisition
- Never leave `merge.lock` behind on terminal path
- Never mutate runtime state outside `~/.local/share/opencode/worktree-state/<project-id>/`
- Do not introduce CI/CD actions in this flow

---

## Rollback Instructions

### Failure Mode A: Validation failure (not worktree / dirty tree / missing state)

1. Do not start merge.
2. If lock was acquired early by mistake, remove `merge.lock`.
3. Ensure `merge-queue.json.activeMerge = null`.
4. Set `worktrees/<branch>.json.status = "failed"` when branch state exists.

### Failure Mode B: Could not acquire merge lock after retries

1. Do not run fetch/rebase/merge.
2. Set `worktrees/<branch>.json.status = "failed"`.
3. Leave existing lock untouched (owned by another session).
4. Ensure branch remains queued (or requeue with original priority).

### Failure Mode C: Rebase conflict (simple strategy failed or complex conflict)

1. `git rebase --abort`
2. Set `worktrees/<branch>.json.status = "failed"`
3. Set `merge-queue.json.activeMerge = null`
4. Remove `merge.lock`
5. Record manual review needed

### Failure Mode D: Merge command failed in main worktree

1. If merge in-progress: `git -C <main-worktree-path> merge --abort`
2. Set `worktrees/<branch>.json.status = "failed"`
3. Set `merge-queue.json.activeMerge = null`
4. Remove `merge.lock`
5. Keep worktree for manual recovery

### Failure Mode E: Tests failed after merge

1. `git -C <main-worktree-path> merge --abort`
2. Set `worktrees/<branch>.json.status = "failed"`
3. Set `merge-queue.json.activeMerge = null`
4. Remove `merge.lock`
5. Keep worktree for fixes/retry

### Failure Mode F: Cleanup failed (ports/container/worktree delete/state delete)

1. Main merge remains valid; do **not** rewrite history.
2. Retry cleanup idempotently:
   - clear `activeMerge`
   - remove `merge.lock`
   - clean `ports.json`
   - rerun `docker compose -f <compose-file> down`
   - retry `worktree_delete`
   - retry state file deletion
3. If still failing, set branch state to `failed` with cleanup note and escalate.

---

## Success Criteria

- Branch merged into main via `--no-ff` from main worktree path
- `npm test` passes in main worktree
- `worktrees/<branch>.json` completed then removed
- `merge-queue.json.activeMerge` cleared
- `merge.lock` removed
- `ports.json` entry removed
- container stopped and worktree deleted
- no push/force-push/remote mutation performed
