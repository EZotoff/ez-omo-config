# Per-worktree Docker Compose template

Variables:

- `WORKTREE_PATH`: Absolute path to the worktree checkout
- `HOST_PORT`: Dynamically allocated port in the `3100-3199` range
- `BRANCH_NAME`: Git branch name for container identification

Usage:

```bash
WORKTREE_PATH=/path HOST_PORT=3100 BRANCH_NAME=feature docker compose up -d
```
