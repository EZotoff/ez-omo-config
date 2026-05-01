---
name: wisdom
description: Primary runtime memory skill for institutional knowledge, operational facts, patterns, and decisions. Use for ALL knowledge queries including deployment, config, and infrastructure.
---

# Wisdom System

You have access to a shared knowledge store called **Wisdom** — institutional memory that accumulates patterns, gotchas, decisions, and operational facts across sessions. Wisdom is the **primary and only runtime memory store**. Use it to avoid repeating mistakes, to ground decisions in documented facts, and to reuse proven approaches.

## When to Use Wisdom

### Search Wisdom (before starting work)
- Before implementing a feature or fixing a bug, search for relevant learnings
- When encountering an unfamiliar error or build failure
- Before making architectural decisions
- When working in an area you haven't touched recently
- **For operational queries** (deployment paths, config values, infrastructure facts, provider gotchas) — ALWAYS search Wisdom first. Do NOT infer operational facts from code.

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
- `--authority LEVEL`: Filter by canonical authority (`candidate|verified|published`)
- `--status STATUS`: Filter by canonical status (`active|stale|superseded|retracted`)
- `--provenance VALUE`: Filter by canonical provenance (`closeout|nomination|manual|manifest-import|migration|publish-export|compat-shim`)
- Default search returns only `active` and `stale` entries.
- Use `--include-status superseded,retracted` to expose hidden lifecycle states when needed.
- Use `--touch` only when you intentionally want to update access telemetry.

**Qualifying answers by authority:**
- `published` or `verified` → state the answer as documented fact
- `candidate` → qualify: "This is a candidate finding, not yet verified"
- Nothing found → answer UNKNOWN: "No documented knowledge found. This is unknown/undocumented"

### Write
```bash
echo "CONTENT" | ~/.sisyphus/scripts/wisdom-write.sh --type TYPE --tags "tag1,tag2" [--scope system|project|plan]
```
- Content must be at least 20 characters
- Tags are required (comma-separated)
- Type is auto-classified if omitted
- Secrets are detected and blocked automatically
- Default authority is `candidate`, default status is `active`

### Edit
```bash
~/.sisyphus/scripts/wisdom-edit.sh ID --scope SCOPE [--set-authority LEVEL] [--set-status STATUS] [--set-provenance VALUE] [--dry-run]
```
- Update fields on an existing wisdom entry by ID
- Use `--set-authority` to promote or demote trust level
- Use `--set-status` to manage lifecycle (active, stale, superseded, retracted)
- Use `--dry-run` to preview changes

### Publish (promote to verified artifact)
```bash
~/.sisyphus/scripts/wisdom-publish.sh --id ID [--reason "justification"]
```
- Promotes a wisdom entry to `authority=published` and emits a derivative artifact
- Tracks published artifacts with source digests for staleness detection
- Requires an explicit reason

### Sync (after sessions with learnings)
```bash
~/.sisyphus/scripts/wisdom-sync.sh [--skip-llm] [--dry-run]
```
Syncs entries from notepad learnings into the wisdom store.

## Canonical Contract

Every wisdom entry carries a canonical trust and lifecycle contract:

| Field | Values | Meaning |
|-------|--------|---------|
| `authority` | `candidate`, `verified`, `published` | Trust level of the entry |
| `status` | `active`, `stale`, `superseded`, `retracted` | Lifecycle state |
| `provenance` | `closeout`, `nomination`, `manual`, `manifest-import`, `migration`, `publish-export`, `compat-shim` | How the entry originated |

**Ranking order**: `published` > `verified` > `candidate`. Within the same authority, `active` > `stale`. `superseded` and `retracted` are hidden by default.

**Conflict handling**: if the top two non-superseded matches are equally ranked, share the same topic, and mutually contradict, search returns `UNKNOWN` instead of guessing.

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

## Rules
- **NEVER infer operational/infra facts from code** — search Wisdom first
- **ALWAYS qualify answers** with authority level (published/verified/candidate/unknown)
- Prefer "unknown" over guessing
- Maximum 3 knowledge captures per task (avoid over-capturing)
- **Operational Reality Verification**: Operational facts about live config/runtime state are UNKNOWN until verified from live paths, active config, and runtime evidence.

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

**Promoting a verified finding:**
```bash
~/.sisyphus/scripts/wisdom-publish.sh --id 20250304-123456-abcd --reason "Verified through three successful deployments"
```
