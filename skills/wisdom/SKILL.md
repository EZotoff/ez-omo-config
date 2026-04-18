# Wisdom System

> **Note**: For operational knowledge queries (deployment, config, infrastructure), use the `knowledge` skill instead. This wisdom skill remains for general wisdom write/search operations.

You have access to a shared knowledge store called **Wisdom** — institutional memory that accumulates patterns, gotchas, and decisions across sessions. Use it to avoid repeating mistakes and to leverage proven approaches.

## When to Use Wisdom

### Search Wisdom (before starting work)
- Before implementing a feature or fixing a bug, search for relevant learnings
- When encountering an unfamiliar error or build failure
- Before making architectural decisions
- When working in an area you haven't touched recently

### Write Wisdom (after discovering something)
- After finding a non-obvious fix or workaround (type: `gotcha`)
- After establishing a reusable pattern or convention (type: `pattern`)
- After making an architectural decision with tradeoffs (type: `decision`)
- After learning a project-specific fact that isn't documented (type: `fact`)
- After identifying a dangerous pitfall others should avoid (type: `warning`)

## Commands

### Search
```bash
~/.sisyphus/scripts/wisdom-search.sh "QUERY" [--scope system|project|plan|all] [--type TYPE] [--limit N] [--json]
```
- `--scope`: Default `all`. Use `system` for universal patterns, `project` for project-specific.
- `--type`: `gotcha`, `pattern`, `fact`, `decision`, `warning`
- `--limit`: Default 10
- `--json`: Machine-readable output

### Write
```bash
echo "CONTENT" | ~/.sisyphus/scripts/wisdom-write.sh --type TYPE --tags "tag1,tag2" [--scope system|project|plan]
```
- Content must be at least 20 characters
- Tags are required (comma-separated)
- Type is auto-classified if omitted
- Secrets are detected and blocked automatically

### Sync (after sessions with learnings)
```bash
~/.sisyphus/scripts/wisdom-sync.sh [--skip-llm] [--dry-run]
```
Syncs entries from notepad learnings into the wisdom store.

## Scope Levels
- **system** (default): Universal — all projects and sessions. Use for language conventions, tool behaviors, general best practices.
- **project**: Specific to one project. Use for project-specific conventions and architecture decisions. Requires `--project-id`.
- **plan**: Temporary/experimental. Use for plan-specific knowledge. Requires `--project-id`.

## Entry Types
| Type | When to use |
|------|------------|
| `gotcha` | Non-obvious traps, unexpected behaviors, "I spent hours on this" moments |
| `pattern` | Reusable approaches, proven conventions, "this is how we do it here" |
| `fact` | Important but undocumented project/domain knowledge |
| `decision` | Architectural choices with reasoning and tradeoffs |
| `warning` | Dangerous pitfalls, "don't do X because Y" |

## Example Workflows

**Before fixing a bug:**
```bash
~/.sisyphus/scripts/wisdom-search.sh "build error node_modules" --scope system --limit 5
```

**After finding a gotcha:**
```bash
echo "Docker build fails if .dockerignore excludes required files — always check .dockerignore before debugging Docker build failures" | \
  ~/.sisyphus/scripts/wisdom-write.sh --type gotcha --tags "docker,build,.dockerignore"
```

**After a significant architecture decision:**
```bash
echo "Chose pnpm over npm for monorepo support — workspace protocol handling is critical for local package development" | \
  ~/.sisyphus/scripts/wisdom-write.sh --type decision --tags "pnpm,monorepo,architecture"
```
