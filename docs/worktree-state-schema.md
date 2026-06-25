# Worktree Parallel Development State Schema

Runtime state lives at `~/.local/share/opencode/worktree-state/` and is **not** stored in the git repo.
This layout mirrors the `opencode-worktree` style of flat, file-based state with simple locking.

## Directory Layout

```text
~/.local/share/opencode/worktree-state/<project-id>/
├── worktrees/
│   └── <branch>.json
├── merge-queue.json
├── merge.lock
└── ports.json
```

- `worktrees/` stores one JSON file per branch/worktree.
- `merge-queue.json` stores the merge queue and active merge lock metadata.
- `merge.lock` is the lock file for merge operations.
- `ports.json` maps allocated ports to branch names within the project's reserved range.

## Worktree State JSON Schema

File: `~/.local/share/opencode/worktree-state/<project-id>/worktrees/<branch>.json`

### Fields

| Field | Type | Required | Description |
|---|---|---:|---|
| `branch` | string | yes | Branch name for the worktree. |
| `worktreePath` | string | yes | Absolute path to the worktree checkout. |
| `status` | string | yes | Current state, e.g. `creating`, `ready`, `merging`, `merged`, `failed`, `deleted`. |
| `port` | number \| null | no | Reserved dev server port, if any. |
| `dockerContainerId` | string \| null | no | Associated container ID, if any. |
| `createdAt` | string (ISO 8601) | yes | Creation timestamp. |
| `agentSessionId` | string \| null | no | OpenCode agent session tied to the worktree. |
| `timeoutAt` | string (ISO 8601) \| null | no | Deadline for cleanup/expiration. |

### Example

```json
{
  "branch": "feature/search-index",
  "worktreePath": "/home/ezotoff/.local/share/opencode/worktree/omo-hub-feature-search-index",
  "status": "ready",
  "port": 4173,
  "dockerContainerId": "c9c3d5d8b7f1",
  "createdAt": "2026-03-19T10:15:00.000Z",
  "agentSessionId": "ses_abc123",
  "timeoutAt": "2026-03-19T14:15:00.000Z"
}
```

## Merge Queue JSON Schema

File: `~/.local/share/opencode/worktree-state/<project-id>/merge-queue.json`

### Shape

```json
{
  "queue": [],
  "activeMerge": null
}
```

### Fields

#### `queue`
Array of pending merge requests.

Each entry:

| Field | Type | Required | Description |
|---|---|---:|---|
| `branch` | string | yes | Branch waiting to merge. |
| `requestedAt` | string (ISO 8601) | yes | When the merge was requested. |
| `priority` | number | yes | Higher or lower priority value used by the scheduler. |

#### `activeMerge`
Current locked merge, or `null`.

| Field | Type | Required | Description |
|---|---|---:|---|
| `branch` | string | yes | Branch currently being merged. |
| `lockedAt` | string (ISO 8601) | yes | When the merge lock was acquired. |
| `lockedBy` | string | yes | Actor/session holding the merge lock. |

### Example

```json
{
  "queue": [
    {
      "branch": "feature/search-index",
      "requestedAt": "2026-03-19T10:20:00.000Z",
      "priority": 10
    },
    {
      "branch": "fix/api-timeout",
      "requestedAt": "2026-03-19T10:30:00.000Z",
      "priority": 20
    }
  ],
  "activeMerge": {
    "branch": "feature/search-index",
    "lockedAt": "2026-03-19T10:31:00.000Z",
    "lockedBy": "ses_abc123"
  }
}
```

## Lock File Mechanism

File: `~/.local/share/opencode/worktree-state/<project-id>/merge.lock`

- Presence of the file means the merge path is locked.
- Contents store locker info so other processes can identify who holds the lock.
- Deleting the file releases the lock.

### Suggested Contents

```json
{
  "lockedBy": "ses_abc123",
  "lockedAt": "2026-03-19T10:31:00.000Z",
  "branch": "feature/search-index",
  "pid": 12345
}
```

### Example

```json
{
  "lockedBy": "ses_abc123",
  "lockedAt": "2026-03-19T10:31:00.000Z",
  "branch": "feature/search-index",
  "pid": 12345
}
```

## Port Registry

Three-tier system:

### 1. Deployment Registry — Ranges (Project Ownership)

`~/.sisyphus/ports.json` `ranges` reserves a **contiguous port range** per project. This establishes project ownership of the range.

```json
{
  "ranges": {
    "omo-hub": { "start": 3000, "end": 3010 }
  }
}
```

### 2. Deployment Registry — Ports (Service Reservations)

`~/.sisyphus/ports.json` `ports` reserves **individual service ports** within a project's range for project-owned host-bound services. These ports are unavailable for worktree allocation.

```json
{
  "ports": {
    "3000": { "service": "next-web", "project": "omo-hub", "allocated": "2026-03-20" }
  }
}
```

### 3. Worktree State (Allocations)

`~/.local/share/opencode/worktree-state/<project>/ports.json` tracks **dynamic worktree port allocations** within the project's range.

```json
{
  "3004": "feature/search-index",
  "3005": "fix/api-timeout"
}
```

### Workflow

1. Project reserves range via `/deploy` → stored in deployment registry `ranges`
2. Project registers service ports → stored in deployment registry `ports`
3. Worktree created → hook allocates next free port from range, **excluding** both registered service ports and existing worktree allocations → stored locally
4. Worktree deleted → hook frees port in local registry

### Rules

- No port allocation if project has no reserved range (port stays null)
- Worktree allocation skips ports listed in global `ports` for the same project
- Worktree allocation skips ports already allocated in local worktree state
- If no free port remains in the range, allocation fails with an error (does not select outside the range)
- Keys are port numbers as strings, values are branch names
- Registry only contains currently active allocations

## Notes

- These files are runtime state only.
- Do not commit them to the repository.
- Do not replace this layout with SQLite or any other database.
