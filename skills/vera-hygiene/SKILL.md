---
name: vera-hygiene
description: Vera index hygiene and .veraignore management. Run this before indexing a large or external project, or whenever Vera indexing fails with permission errors, zero files/chunks, or watcher issues.
---

# Vera Hygiene Skill

Agents must run the Vera hygiene workflow before root-indexing a project that is large, externally cloned, or has previously failed to index cleanly.

## When to Use

Run `vera-hygiene.sh` in these situations:

- **Before root indexing** a large or external project for the first time
- After seeing **`no index found`** from `vera stats` or Vera commands
- After seeing **`Files: 0`** or **`Chunks: 0`** in Vera output
- After **permission denied** errors during `vera index` or `vera search`
- After a **segfault/exit 139** from the Vera binary during indexing
- After **watcher failure** (stale index, missing PID file, or `vera watch` dying)
- When `.veraignore` does not exist or is suspected to be incomplete

## How to Use

The script lives at `scripts/vera-hygiene.sh` (installed to `~/.sisyphus/scripts/vera-hygiene.sh`).

### Step 1: Check for blockers

```bash
~/.sisyphus/scripts/vera-hygiene.sh --project /absolute/path/to/project --check
```

- Exit 0: no blockers detected
- Exit 2: hygiene blockers exist (unreadable dirs, heavy generated dirs)

### Step 2: Preview the fix (optional)

```bash
~/.sisyphus/scripts/vera-hygiene.sh --project /absolute/path/to/project --dry-run
```

Prints the proposed `.veraignore` managed block and the commands that would run.

### Step 3: Apply the fix

```bash
~/.sisyphus/scripts/vera-hygiene.sh --project /absolute/path/to/project --apply
```

Creates or updates `.veraignore` in the project root, preserving all user content.

## What the Script Detects

1. **Unreadable directories** — exact relative paths of dirs the current user cannot read (e.g., container-owned `data/paperclip-postgres/`)
2. **Heavy/generated directories** — `node_modules/`, `.next/`, `out/`, `build/`, `coverage/`, `.sisyphus/`, etc., if present
3. **Self-indexing prevention** — always adds `.vera/` to prevent Vera from indexing its own index

## Safety Rules

- **Never overwrite user content** — only the managed block between `# BEGIN OMO VERA HYGIENE` and `# END OMO VERA HYGIENE` is modified
- **Never ignore tracked parents** — if source files tracked by git exist under a detected directory, that directory is skipped (commented out in the managed block)
- **No `#include .gitignore`** — Vera support for `#include` directives is not yet proven by fixture tests; relevant `.gitignore` rules are expanded inline with comments instead
- **No hardcoded project paths** — unreadable dirs are discovered at runtime via `find`, not hardcoded

## After Applying

Once `.veraignore` is updated, rebuild the Vera index:

```bash
cd /absolute/path/to/project
rm -rf .vera/
vera index .
vera stats
```

Expected: `Files:` and `Chunks:` are non-zero.

## Runtime Automation Note

`plugins/vera-runtime.ts` is manual by default to avoid blocking OpenCode session startup in large or first-time projects. Leave `OMO_VERA_RUNTIME_AUTOSTART` unset/false unless synchronous watcher bootstrap/recovery is acceptable, and leave `OMO_VERA_RUNTIME_TOOL_UPDATE` unset/false unless synchronous pre-tool `vera update .` is acceptable.

## See Also

- `docs/vera-implementation-plan.md` — Vera integration architecture
- `plugins/vera-runtime.ts` — Manual-by-default Vera runtime state and opt-in watcher supervision
- `scripts/worktree-post-create.sh` — Worktree hook that records manual Vera state by default and bootstraps the Vera index only when `OMO_VERA_RUNTIME_AUTOSTART=1`
