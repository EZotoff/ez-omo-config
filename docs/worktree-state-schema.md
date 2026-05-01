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

Two-tier system:

### 1. Deployment Registry (Ranges)

`~/.sisyphus/ports.json` reserves **ranges** per project. Managed by deployment skill.

```json
{
  "ranges": {
    "omo-hub": { "start": 3000, "end": 3010 }
  }
}
```

### 2. Worktree State (Allocations)

`~/.local/share/opencode/worktree-state/<project>/ports.json` tracks **individual port allocations** within the project's range.

```json
{
  "3000": "feature/search-index",
  "3001": "fix/api-timeout"
}
```

### Workflow

1. Project reserves range via `/deploy` → stored in deployment registry
2. Worktree created → hook allocates next free port from range → stored locally
3. Worktree deleted → hook frees port in local registry

### Rules

- No port allocation if project has no reserved range (port stays null)
- Keys are port numbers as strings, values are branch names
- Registry only contains currently active allocations

## Vera Watchers JSON Schema

File: `~/.local/share/opencode/worktree-state/<project-id>/vera-watchers/<workspace-key>.json`

### Directory Layout

```text
~/.local/share/opencode/worktree-state/<project-id>/
├── worktrees/
│   └── <branch>.json
├── vera-watchers/
│   └── <workspace-key>.json
├── merge-queue.json
├── merge.lock
└── ports.json
```

- `vera-watchers/` stores one JSON file per workspace (not per branch).
- The workspace key is `<workspace-basename>-<sha1-8(realpath(workspacePath))>`.
- Project ID is `basename "$(git rev-parse --show-toplevel)"` (same as worktree scripts).

### Fields

| Field | Type | Required | Description |
|---|---|---:|---|
| `workspaceKey` | string | yes | Unique workspace identifier (`<basename>-<sha1-8(path)>`). |
| `workspacePath` | string | yes | Absolute path to the workspace directory. |
| `projectId` | string | yes | Project identifier from git toplevel basename. |
| `pid` | number \| null | yes | Process ID of the active `vera watch` process, or `null`. |
| `status` | string | yes | Current watcher state: `indexed`, `running`, `stale`, `stopped`, `missing-binary`, `index-failed`, `watch-failed`. |
| `sessionIds` | string[] | yes | OpenCode session IDs currently associated with this workspace. |
| `indexPath` | string | yes | Absolute path to the Vera index directory (typically `<workspace>/.vera`). |
| `watchLogPath` | string | yes | Absolute path to the per-workspace watcher log file. |
| `lastIndexedAt` | string (ISO 8601) \| null | yes | Timestamp of the last successful index, or `null`. |
| `startedAt` | string (ISO 8601) \| null | yes | Timestamp when the watcher process started, or `null`. |
| `lastVerifiedAt` | string (ISO 8601) \| null | yes | Timestamp of the last health/verification check, or `null`. |
| `lastFailureAt` | string (ISO 8601) \| null | yes | Timestamp of the last failure, or `null`. |
| `lastFailureReason` | string \| null | yes | Human-readable reason for the last failure, or `null`. |

### Status Values

| Status | Meaning |
|---|---|
| `indexed` | Index exists and is up-to-date; watcher not currently running. |
| `running` | `vera watch` process is active and monitoring the workspace. |
| `stale` | Index exists but may be out of date; re-index recommended. |
| `stopped` | No active watcher; no sessions associated. |
| `missing-binary` | `vera` binary not found in `$PATH`. |
| `index-failed` | Last `vera index` command exited with non-zero status. |
| `watch-failed` | `vera watch` process exited unexpectedly or failed to start. |

### Example

```json
{
  "workspaceKey": "my-project-a1b2c3d4",
  "workspacePath": "/home/ezotoff/projects/my-project",
  "projectId": "my-project",
  "pid": 12345,
  "status": "running",
  "sessionIds": ["ses_abc123"],
  "indexPath": "/home/ezotoff/projects/my-project/.vera",
  "watchLogPath": "/home/ezotoff/.opencode/plugin/vera-runtime/my-project-a1b2c3d4.log",
  "lastIndexedAt": "2026-05-01T10:00:00.000Z",
  "startedAt": "2026-05-01T10:00:00.000Z",
  "lastVerifiedAt": "2026-05-01T10:05:00.000Z",
  "lastFailureAt": null,
  "lastFailureReason": null
}
```

## Notes

- These files are runtime state only.
- Do not commit them to the repository.
- Do not replace this layout with SQLite or any other database.
