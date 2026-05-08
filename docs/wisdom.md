# Wisdom System

> **Advanced Feature**: This is an optional, advanced feature for power users who want to accumulate and propagate knowledge across AI agent sessions. Most users do not need to configure or use the wisdom system.

## Overview

The wisdom system is a knowledge propagation mechanism for AI agents. It captures patterns, conventions, successful approaches, and important learnings discovered during development work, then makes this knowledge available in future sessions.

Think of wisdom as institutional memory for AI agents. When you discover that "always use `jq -Rs` for JSON string escaping" or "the build fails if node_modules is not cleaned first," the wisdom system records these insights so they are not lost between sessions.

## Architecture

The wisdom system consists of three integrated components:

```
┌─────────────────────────────────────────────────────────────┐
│                     WISDOM SYSTEM                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐      ┌─────────────────────────────┐     │
│  │  wisdom/     │      │      wisdom-*.sh Scripts    │     │
│  │   Skill      │──────┤                             │     │
│  │  (OpenCode)  │      │  ┌─────────────────────┐    │     │
│  └──────────────┘      │  │  wisdom-common.sh   │    │     │
│         │              │  │  (shared library)   │    │     │
│         │              │  └─────────────────────┘    │     │
│         ▼              │           ▲                 │     │
│  ┌──────────────┐      │     ┌─────┼─────┐           │     │
│  │   Notepads   │      │     │     │     │           │     │
│  │  learnings   │◄─────┼─────┘     │     │           │     │
│  │   .md files  │      │           │     │           │     │
│  └──────────────┘      │  ┌────────┼─────┼────────┐  │     │
│                        │  │        │     │        │  │     │
│                        │  ▼        ▼     ▼        ▼  │     │
│                        │ search write nominate sync archive ││
│                        │ delete  edit    gc      merge      ││
│                        └─────────────────────────────┘   │
│                                      │                    │
│                                      ▼                    │
│                        ┌─────────────────────────┐       │
│                        │   ~/.sisyphus/wisdom/   │       │
│                        │    (JSONL stores)       │       │
│                        └─────────────────────────┘       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Component Flow

1. **wisdom/ Skill**: OpenCode skill that provides high-level interface for searching and writing wisdom entries
2. **wisdom-*.sh Scripts**: Command-line tools for managing wisdom entries
3. **wisdom-common.sh**: Shared library containing all core functionality (sourced by all other scripts)
4. **Storage**: JSONL files in `~/.sisyphus/wisdom/` organized by scope

## Script Reference

All scripts are installed to `$HOME/.sisyphus/scripts/` and depend on `wisdom-common.sh`.

### wisdom-common.sh (Critical Dependency)

**Purpose**: Shared library containing core functionality for the entire wisdom system.

**Critical Note**: All other wisdom scripts source this file via `$(dirname "$0")/wisdom-common.sh`. The scripts must remain co-located in the same directory.

**Key Functions**:

| Function | Purpose |
|----------|---------|
| `wisdom_generate_id()` | Generate unique entry IDs (YYYYMMDD-HHMMSS-XXXX format) |
| `wisdom_get_store_path()` | Resolve JSONL file path for a scope |
| `wisdom_read_entry()` | Find entry by ID in a store |
| `wisdom_append_entry()` | Atomically append entry to store |
| `wisdom_remove_entry()` | Atomically remove entry by ID |
| `wisdom_update_entry()` | Atomically replace entry by ID |
| `wisdom_validate_jsonl_line()` | Validate entry against schema |
| `wisdom_classify_type()` | Auto-determine entry type from content |
| `wisdom_check_secret()` | Detect and block secrets in content |

**Constants**:
- `WISDOM_ROOT`: `~/.sisyphus/wisdom`
- `WISDOM_SCRIPTS`: `~/.sisyphus/scripts`
- Valid types: `gotcha`, `pattern`, `fact`, `decision`, `warning`
- Valid scopes: `system`, `project`, `plan`
- Valid authorities: `candidate`, `verified`, `published`
- Valid statuses: `active`, `stale`, `superseded`, `retracted`
- Valid provenances: `closeout`, `nomination`, `manual`, `manifest-import`, `migration`, `publish-export`, `compat-shim`

**Canonical Helpers**:

| Function | Purpose |
|----------|---------|
| `wisdom_normalize_authority()` | Maps legacy authority values into canonical values |
| `wisdom_normalize_status()` | Normalizes missing or legacy status values, including overdue stale detection |
| `wisdom_build_metadata()` | Builds the fixed metadata object with all required keys |
| `wisdom_rank_entry()` | Produces the canonical ranking tuple |
| `wisdom_compare_entries()` | Compares two entries using the canonical ranking algorithm |
| `wisdom_check_contradiction()` | Returns `UNKNOWN` for equal-rank contradictory entries on the same topic |
| `wisdom_normalize_record()` | Converts legacy records into the canonical schema |
| `wisdom_validate_canonical()` | Validates canonical authority/status/provenance/metadata rules |

### wisdom-search.sh

**Purpose**: Search wisdom stores with filtering, sorting, and access tracking.

**Usage**:
```bash
wisdom-search.sh QUERY [OPTIONS]
```

**Options**:
- `--scope SCOPE`: system|project|plan|all (default: all)
- `--type TYPE`: Filter by type (gotcha|pattern|fact|decision|warning)
- `--tags TAGS`: Comma-separated tags (any match)
- `--limit N`: Max results (default: 10)
- `--json`: Output as JSON array
- `--min-score N`: Filter by quality_score >= N
- `--project-id ID`: Limit to specific project
- `--authority LEVEL`: Filter by canonical authority level (`candidate|verified|published`)
- `--include-status LIST`: Extend default visibility with comma-separated statuses such as `superseded,retracted`
- `--provenance VALUE`: Filter by canonical provenance value
- `--origin-session ID`: Filter by canonical origin session ID
- `--touch`: Explicitly update `accessed` and `last_accessed` telemetry for returned entries

**Default retrieval**: searches only `active` and `stale` entries. `superseded` and `retracted` stay hidden unless explicitly included with `--include-status`.

**Canonical ranking**: results are ordered by query relevance, then status (`active > stale`), authority (`published > verified > candidate`), review freshness, `verified_at`, `created`, and `id`.

**Conflict handling**: if the top two non-superseded matches are equally ranked, share the same normalized topic key, have the same status/authority, carry different bodies, and mutually reference each other in `contradicts`, search returns `UNKNOWN` instead of guessing.

**Example**:
```bash
# Search for Docker-related patterns
wisdom-search.sh docker --type pattern --limit 5

# Search with JSON output
wisdom-search.sh "build error" --scope project --project-id myapp --json

# Include superseded entries explicitly
wisdom-search.sh docker --include-status superseded --json
```

**Access Tracking**: Search is read-only by default. Pass `--touch` to explicitly update `accessed` and `last_accessed` for matched entries.

### wisdom-write.sh

**Purpose**: Validate and write new wisdom entries to stores.

**Usage**:
```bash
wisdom-write.sh [OPTIONS]
```

**Options**:
- `--scope`: system|project|plan (default: system)
- `--type`: gotcha|pattern|fact|decision|warning (auto-classified if omitted)
- `--tags`: Comma-separated tags (required)
- `--content`: Content string (reads stdin if omitted)
- `--source`: Source identifier
- `--project-id`: Required for project/plan scope
- `--score`: Quality score integer (default: 0)
- `--authority`: `candidate|verified|published` (default canonical authority is `candidate`)
- `--provenance`: `closeout|nomination|manual|manifest-import|migration|publish-export|compat-shim`
- `--origin-session`: Optional source session ID
- `--verified-at`: Required when authority is `verified` or `published`
- `--review-due`: Optional review timestamp; overdue entries should use `status=stale`

**Example**:
```bash
# Write a pattern entry
echo "Always use jq -Rs for JSON string escaping" | \
  wisdom-write.sh --type pattern --tags "bash,jq,json"

# Write with explicit content
wisdom-write.sh --type gotcha --tags "docker,build" \
  --content "Docker build fails if .dockerignore excludes required files"
```

**Validation**:
- Content must be at least 20 characters
- Tags are required
- Secrets are detected and blocked

### wisdom-nominate.sh

**Purpose**: Preserve passive nomination as Wisdom-owned infra-only v1 behavior while writing canonical nomination records.

**Usage**:
```bash
wisdom-nominate.sh [OPTIONS]
```

**Options**:
- `--content`: Content string (reads stdin if omitted)
- `--tags`: Comma-separated tags
- `--scope`: `system|project|plan` (default: `system`)
- `--type`: Optional explicit type (`gotcha|pattern|fact|decision|warning`)
- `--project-id`: Required for `project`/`plan` scope
- `--session-id` / `--origin-session`: Optional source session ID
- `--source`: Source identifier (`nomination:passive` default)

**Infra-only v1 policy**:
- Accept when `scope=system`, **or**
- Accept when tags contain at least one infra tag: `infra`, `config`, `deployment`, `setup`
- Reject non-infra nominations with an informative message

**Canonical write contract**:
- `authority=candidate`
- `status=active`
- `provenance=nomination`
- `origin_session=<session-id|null>`

### wisdom-sync.sh

**Purpose**: Scan notepad learnings and sync new entries into wisdom stores.

**Pipeline Stages**:
1. **Scan**: Find all `~/.sisyphus/notepads/*/learnings.md` files
2. **Split**: Split files into sections on headers
3. **Filter**: Skip sections with body < 20 characters
4. **Dedup**: SHA-256 hash check against `.sync-state`
5. **Classify**: Auto-determine type via `wisdom_classify_type`
6. **LLM Gate**: Score 0-10 via opencode chat (unless `--skip-llm`)
7. **Write**: Call `wisdom-write.sh` for accepted entries (score >= 3)
8. **State**: Append hashes to `.sync-state`

**Usage**:
```bash
wisdom-sync.sh [OPTIONS]
```

**Options**:
- `--dry-run`: Show what would be synced without changes
- `--skip-llm`: Skip LLM quality gate
- `--verbose`: Print extra detail

**Example**:
```bash
# Preview what would be synced
wisdom-sync.sh --dry-run --verbose

# Sync without LLM scoring
wisdom-sync.sh --skip-llm
```

### wisdom-archive.sh

**Purpose**: Move a wisdom entry from active store to archive store.

**Usage**:
```bash
wisdom-archive.sh [OPTIONS] ID
```

**Options**:
- `--scope SCOPE`: system|project|plan (required)
- `--project-id ID`: Required for project/plan scope
- `--dry-run`: Show what would be archived

**Example**:
```bash
# Archive a system entry
wisdom-archive.sh --scope system 20250304-123456-abcd

# Archive with dry-run
wisdom-archive.sh --scope project --project-id myapp --dry-run 20250304-123456-abcd
```

**Safety**: Uses write-first-then-delete order. If archive write fails, original remains intact.

### wisdom-delete.sh

**Purpose**: Delete a wisdom entry by ID.

**Usage**:
```bash
wisdom-delete.sh [OPTIONS] ID
```

**Options**:
- `--scope SCOPE`: system|project|plan (required)
- `--project-id ID`: Required for project/plan scope
- `--dry-run`: Show what would be deleted
- `--force`: Skip confirmation prompt

**Example**:
```bash
# Delete with confirmation
wisdom-delete.sh --scope system 20250304-123456-abcd

# Delete without confirmation
wisdom-delete.sh --scope system --force 20250304-123456-abcd
```

**Exit Codes**:
- 0: Deleted successfully
- 1: Entry not found
- 2: Bad arguments
- 3: User cancelled

### wisdom-edit.sh

**Purpose**: Update individual fields of an existing wisdom entry.

**Usage**:
```bash
wisdom-edit.sh ID --scope SCOPE [--project-id PROJECT] [edit-flags] [--dry-run]
```

**Edit Flags** (at least one required):
- `--set-body "text"`: Replace body content
- `--set-type "type"`: Change entry type
- `--set-tags "tag1,tag2"`: Replace all tags
- `--add-tags "tag3,tag4"`: Append tags
- `--set-score N`: Set quality_score
- `--set-authority LEVEL`: Set canonical authority (`candidate|verified|published`)
- `--set-status STATUS`: Set canonical status (`active|stale|superseded|retracted`)
- `--set-provenance VALUE`: Set canonical provenance (`closeout|nomination|manual|manifest-import|migration|publish-export|compat-shim`)
- `--set-origin-session ID`: Set the source session ID string
- `--set-superseded-by ID`: Mark replacement entry when status is `superseded`
- `--set-verified-at ISO`: Set canonical verification timestamp
- `--set-review-due ISO`: Set review due timestamp

**Example**:
```bash
# Update type and tags
wisdom-edit.sh 20250304-123456-abcd --scope system \
  --set-type pattern --set-tags "rust,build"

# Add tags with dry-run
wisdom-edit.sh 20250304-123456-abcd --scope project --project-id myproj \
  --add-tags "api" --dry-run
```

### wisdom-gc.sh

**Purpose**: Garbage collection for stale or low-quality wisdom entries.

**Staleness Criteria** (any match = flagged):
- `accessed == 0` AND `created > stale-days` ago
- `last_accessed` is non-empty AND > stale-days old
- `quality_score > 0` AND `quality_score < min-score`

**Usage**:
```bash
wisdom-gc.sh [OPTIONS]
```

**Options**:
- `--scope SCOPE`: all|system|project|plan (default: all)
- `--project-id ID`: Required for project/plan scope
- `--stale-days N`: Days to consider stale (default: 90)
- `--min-score N`: Minimum quality score (default: 0)
- `--action ACTION`: report|archive|delete (default: report)
- `--dry-run`: Show what would be done
- `--force`: Skip confirmation for delete action

**Example**:
```bash
# Report all stale entries
wisdom-gc.sh --scope system

# Archive stale entries (dry-run)
wisdom-gc.sh --action archive --dry-run

# Delete low-quality entries
wisdom-gc.sh --min-score 50 --action delete --force
```

### wisdom-merge.sh

**Purpose**: Combine multiple wisdom entries into a single merged entry.

**Merge Behavior**:
- Body: Concatenated with `\n\n---\n\n` separator (unless `--body` override)
- Tags: Union of all tags, deduplicated (unless `--tags` override)
- Type: First entry's type (unless `--type` override)
- quality_score: Max of all source scores
- accessed: Sum of all source accessed counts
- source: "merged from: ID1, ID2, ..."
- created: Current ISO8601 timestamp

**Usage**:
```bash
wisdom-merge.sh --ids ID1,ID2,... --scope SCOPE [OPTIONS]
```

**Options**:
- `--ids IDS`: Comma-separated entry IDs (min 2, required)
- `--scope SCOPE`: system|project|plan (required)
- `--project-id ID`: Required for project/plan scope
- `--body TEXT`: Override merged body
- `--type TYPE`: Override type
- `--tags TAGS`: Override tags
- `--dry-run`: Preview without changes

**Example**:
```bash
# Merge two entries
wisdom-merge.sh --ids 20250304-1234-abcd,20250304-5678-efgh --scope system

# Merge with override (dry-run)
wisdom-merge.sh --ids ID1,ID2,ID3 --scope project --project-id myproj \
  --type pattern --dry-run
```

**Safety**: Merged entry is written first, then source entries are deleted. If write fails, originals remain.

### wisdom-migrate.sh

**Purpose**: Perform canonical migration for Wisdom-first runtime.

**What it does**:
1. Creates a timestamped backup tarball that includes Wisdom stores, manifest sources, skill directories, AGENTS.md, and OMO config.
2. Normalizes legacy Wisdom JSONL records in place using `wisdom_normalize_record` and canonical validation.
3. Imports manifests as canonical Wisdom records with `authority=published`, `provenance=manifest-import`, and mapped legacy metadata fields.

**Idempotence behavior**:
- Upsert matching order: `metadata.legacy_manifest_id` → `metadata.legacy_manifest_path` → canonical fingerprint (`scope+type+title+body`) → create.
- Exact matches merge tags and preserve highest authority/status rank.
- Replacement updates create a new record and supersede the old record (`status=superseded`, `superseded_by=<new-id>`).

**Usage**:
```bash
wisdom-migrate.sh

# run phases selectively
wisdom-migrate.sh --backup-only
wisdom-migrate.sh --normalize-only
wisdom-migrate.sh --import-only

# restore through migrate command
wisdom-migrate.sh --restore /path/to/backup.tar.gz --restore-target /tmp/restore-root
```

### wisdom-restore.sh

**Purpose**: Restore a backup tarball produced by `wisdom-migrate.sh`.

**Usage**:
```bash
wisdom-restore.sh --backup /path/to/backup.tar.gz
wisdom-restore.sh --backup /path/to/backup.tar.gz --target-root /tmp/restore-root
```

## Wisdom Observability

The wisdom subsystem emits structured observability events to a JSONL event store. Every wisdom script initializes an observability context on startup and emits events for capture, query, promotion, and lifecycle operations. This gives operators a complete audit trail of what the wisdom system is doing.

### Event Store Path

Events are written to:

```
${WISDOM_EVENTS_PATH:-${WISDOM_ROOT:-$HOME/.sisyphus/wisdom}/events.jsonl}
```

The default path is `~/.sisyphus/wisdom/events.jsonl`. Override with `WISDOM_EVENTS_PATH` for test isolation or custom locations.

### Event Schema

Every event is a single JSON line with the following required fields:

```json
{
  "schema_version": "1.0",
  "ts": "2025-03-15T14:32:10Z",
  "system": "wisdom",
  "event": "wisdom.write",
  "status": "success",
  "trace_id": "trace-1742051530-a1b2c3d4",
  "invocation_id": "inv-wisdom-write.sh-1742051530-e5f6g7h8",
  "parent_invocation_id": null,
  "script": "wisdom-write.sh",
  "pid": 12345,
  "duration_ms": 42
}
```

**Field Descriptions**:

| Field | Type | Description |
|-------|------|-------------|
| `schema_version` | string | Fixed at `"1.0"` |
| `ts` | string | ISO8601 UTC timestamp of emission |
| `system` | string | Fixed at `"wisdom"` |
| `event` | string | Event name (see Event Names below) |
| `status` | string | One of `started`, `success`, `skipped`, `failed` |
| `trace_id` | string | Shared across all scripts in a call tree |
| `invocation_id` | string | Unique per script invocation |
| `parent_invocation_id` | string or null | Parent script's invocation_id when nested |
| `script` | string | Name of the emitting script |
| `pid` | integer | Process ID of the emitting process |
| `duration_ms` | integer or null | Milliseconds since observability init, or null |

Events may also carry additional payload fields specific to the operation (for example, `scope`, `type`, or `entry_id`).

### Schema Version

The current schema version is `1.0`, defined by `WISDOM_EVENT_SCHEMA_VERSION` in `wisdom-common.sh`. All events emitted by the subsystem use this version. Future schema changes will bump this version and include migration notes here.

### Event Names

| Event Name | Emitted By | Description |
|-----------|------------|-------------|
| `wisdom.write` | `wisdom-write.sh` | A new wisdom entry was written |
| `wisdom.search` | `wisdom-search.sh` | A search was executed against wisdom stores |
| `wisdom.capture.closeout` | `wisdom-closeout.sh` | A closeout capture was processed |
| `wisdom.capture.nomination` | `wisdom-nominate.sh` | A passive nomination was accepted or rejected |
| `wisdom.capture.sync` | `wisdom-sync.sh` | A sync run completed |
| `wisdom.lookup` | `knowledge-lookup.sh` | A legacy lookup shim was invoked |
| `wisdom.snapshot` | `knowledge-snapshot.sh` | A legacy snapshot shim was invoked |
| `wisdom.promote.publish` | `wisdom-publish.sh` | An entry was promoted to published authority |
| `wisdom.lifecycle.edit` | `wisdom-edit.sh` | An entry was modified |
| `wisdom.lifecycle.authority_change` | `wisdom-edit.sh` | An entry's authority level changed |
| `wisdom.lifecycle.archive` | `wisdom-archive.sh` | An entry was moved to archive |
| `wisdom.lifecycle.delete` | `wisdom-delete.sh` | An entry was deleted |
| `wisdom.lifecycle.gc` | `wisdom-gc.sh` | Garbage collection run completed |
| `wisdom.lifecycle.merge` | `wisdom-merge.sh` | Entries were merged |
| `wisdom.lifecycle.migrate` | `wisdom-migrate.sh` | A migration run completed |
| `wisdom.observe.reset` | `wisdom-observe.sh` | The event store was truncated |

### Status Values

- `started` — The operation began (used sparingly)
- `success` — The operation completed normally
- `skipped` — The operation was skipped (for example, no results, or disabled)
- `failed` — The operation encountered an error

### Trace ID Semantics

A `trace_id` is generated once per top-level script invocation and propagated to all nested calls:

1. The first script in a call chain calls `wisdom_init_observability`, which generates a fresh `trace_id` if `WISDOM_TRACE_ID` is not already set.
2. Child scripts inherit the same `WISDOM_TRACE_ID` via environment export.
3. Each script gets its own `invocation_id`, but records the parent's `invocation_id` in `parent_invocation_id`.

This lets you follow a complete operation across `wisdom-closeout.sh` → `wisdom-write.sh` → `wisdom-edit.sh` as a single trace.

### Redaction Rules

Event payloads are redacted before emission to prevent secret leakage:

- **80-character preview cap**: Long values are truncated to 77 characters plus "..."
- **Secret replacement**: Known secret patterns are replaced with `[REDACTED]`:
  - OpenAI-style API keys (`sk-...`)
  - GitHub tokens (`ghp_...`)
  - Slack tokens (`xoxb-...`)
  - Bearer tokens
  - Private keys (`-----BEGIN...PRIVATE KEY-----`)
  - Credential assignments (`API_KEY=...`, `PASSWORD=...`, `TOKEN=...`)
  - `SECRET_SENTINEL_DO_NOT_LOG` markers
- **Whitespace normalization**: Multiple spaces are collapsed, leading/trailing whitespace is trimmed
- **SHA-256 hashes**: Content hashes may be used for correlation without exposing raw values

### Retention Policy

The event store enforces a **hard limit of 1000 events** (`WISDOM_EVENTS_MAX_LINES`). When a new event pushes the count over this limit, the oldest events are truncated automatically. This happens inside the same `flock` lock that appends the new event, so concurrent writes cannot interleave with truncation.

Override the limit:
```bash
export WISDOM_EVENTS_MAX_LINES=5000
```

### Disabled Mode

Set `WISDOM_OBSERVABILITY=0` to disable all event emission. In this mode:

- `wisdom_init_observability` returns immediately without generating IDs
- `wisdom_emit_event` returns immediately without writing
- `wisdom_reset_events` truncates the file but does not emit a reset event
- All wisdom scripts continue to function normally; only observability is silenced
- The `wisdom-observe.sh status` command reports `observability: no`

Use this for performance-sensitive batch operations or when you want to avoid event noise.

### wisdom-observe.sh CLI

The `wisdom-observe.sh` script is the operator-facing CLI for inspecting events.

**Subcommands**:

#### `status`
Print event file metadata: path, existence, line count, newest/oldest timestamps, retention limit, and whether observability is enabled.

```bash
wisdom-observe.sh status
```

#### `read`
Read events with optional filtering. Default human output is compact and deterministic (one line per event).

```bash
# Read all events
wisdom-observe.sh read

# Read with filters and JSON output
wisdom-observe.sh read --limit 10 --event wisdom.search --status success --json
```

**Options**:
- `--limit N`: Limit to N most recent events
- `--event EVENT`: Filter by event name
- `--status STATUS`: Filter by status
- `--json`: Output as JSON array

#### `trace TRACE_ID`
Print all events for a specific trace ID in timestamp order.

```bash
wisdom-observe.sh trace trace-1234567890-abc123 --json
```

**Options**:
- `--json`: Output as JSON array

#### `reset --yes`
Truncate the events file safely. Preserves the parent directory. Emits a `wisdom.observe.reset` event after truncation (unless `WISDOM_OBSERVABILITY=0`). Requires `--yes` flag — without it, exits non-zero with usage text.

```bash
wisdom-observe.sh reset --yes
```

**Safety**: Without `--yes`, the command exits with code 2 and makes no changes.

## Skill Integration

The `wisdom/` skill provides OpenCode integration for the wisdom system. It wraps the scripts and provides a high-level interface for agents.

### Skill → Scripts Dependency

```
wisdom/ skill
    ├── Calls wisdom-search.sh for queries
    ├── Calls wisdom-write.sh for recording
    └── Uses ~/.sisyphus/wisdom/ for storage
```

The skill loads automatically when OpenCode starts and provides:
- `wisdom search <query>`: Find relevant learnings
- `wisdom write <content>`: Record new learnings
- `wisdom sync`: Trigger sync from notepads

### Related Skills

- **atlas-review-handler**: Uses wisdom for recording review patterns and conventions
- **review-protocol**: Can inject wisdom about common code issues

## Storage Structure

Wisdom is stored in `~/.sisyphus/wisdom/` as JSONL files:

```
~/.sisyphus/wisdom/
├── system.jsonl              # System-wide wisdom
├── projects/
│   ├── my-project.jsonl      # Project-specific wisdom
│   └── another-app.jsonl
├── plans/
│   ├── plan-123.jsonl        # Plan-specific wisdom
│   └── refactor-456.jsonl
└── archive/
    ├── system.jsonl          # Archived system entries
    ├── projects/             # Archived project entries
    └── plans/                # Archived plan entries
```

### Entry Schema

Each entry is a JSON line with the following fields:

```json
{
  "id": "20250304-123456-abcd",
  "type": "pattern",
  "scope": "system",
  "tags": ["bash", "json", "jq"],
  "body": "Always use jq -Rs for JSON string escaping",
  "created": "2025-03-04T12:34:56Z",
  "accessed": 5,
  "last_accessed": "2025-03-10T08:15:30Z",
  "source": "sync:/home/user/.sisyphus/notepads/my-project/learnings.md",
  "quality_score": 8
}
```

**Field Descriptions**:

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique identifier (timestamp + random suffix) |
| `type` | string | Entry type: gotcha, pattern, fact, decision, warning |
| `scope` | string | Visibility scope: system, project, plan |
| `tags` | array | Searchable tags for categorization |
| `body` | string | The actual wisdom content |
| `created` | string | ISO8601 timestamp of creation |
| `accessed` | integer | Number of times entry was retrieved |
| `last_accessed` | string | ISO8601 timestamp of last access |
| `source` | string | Origin of the entry |
| `quality_score` | integer | Quality rating (0-10, higher is better) |

## Scope Levels

Wisdom operates at three scope levels:

### System Scope

- **Storage**: `~/.sisyphus/wisdom/system.jsonl`
- **Visibility**: All projects and plans
- **Use Case**: Universal patterns, language conventions, tool behaviors
- **Examples**: "Always use `set -euo pipefail` in bash scripts", "jq -Rs for JSON escaping"

### Project Scope

- **Storage**: `~/.sisyphus/wisdom/projects/{project_id}.jsonl`
- **Visibility**: Specific project only
- **Use Case**: Project-specific conventions, architecture decisions
- **Examples**: "This project uses pnpm instead of npm", "API routes must be prefixed with /api/v2"

### Plan Scope

- **Storage**: `~/.sisyphus/wisdom/plans/{plan_id}.jsonl`
- **Visibility**: Specific plan only
- **Use Case**: Temporary or experimental knowledge
- **Examples**: "Current migration step requires manual database backup"

## Usage Examples

### Common Workflows

#### 1. Search for Existing Wisdom

```bash
# Search all scopes for docker-related entries
wisdom-search.sh docker

# Search for patterns only, limit to 5 results
wisdom-search.sh "build" --type pattern --limit 5

# Search within a specific project
wisdom-search.sh "api" --scope project --project-id myapp --json
```

#### 2. Write New Wisdom

```bash
# Write a gotcha about a common mistake
echo "Always check if jq is installed before using it in scripts" | \
  wisdom-write.sh --type gotcha --tags "bash,jq,dependency"

# Write from file content
cat <<'EOF' | wisdom-write.sh --type pattern --tags "git,workflow"
When squashing commits, use --no-verify to skip hooks that might fail on temporary commit messages
EOF
```

#### 3. Sync from Notepads

```bash
# Preview what would be synced
wisdom-sync.sh --dry-run

# Actually sync (with LLM quality scoring)
wisdom-sync.sh

# Sync quickly (skip LLM)
wisdom-sync.sh --skip-llm
```

#### 4. Maintain Wisdom Quality

```bash
# Report stale entries
wisdom-gc.sh --stale-days 60

# Archive entries not accessed in 120 days
wisdom-gc.sh --stale-days 120 --action archive

# Merge duplicate entries
wisdom-merge.sh --ids ID1,ID2 --scope system

# Delete obsolete entry
wisdom-delete.sh --scope system --force 20250304-123456-abcd
```

#### 5. Edit Existing Entries

```bash
# Update tags on an entry
wisdom-edit.sh 20250304-123456-abcd --scope system --add-tags "deprecated"

# Fix a typo in the body
wisdom-edit.sh 20250304-123456-abcd --scope system \
  --set-body "Corrected wisdom text here"
```

## Installation

The wisdom scripts are installed to `$HOME/.sisyphus/scripts/`:

```bash
# Copy all wisdom scripts
cp scripts/wisdom/wisdom-*.sh ~/.sisyphus/scripts/

# Make them executable
chmod +x ~/.sisyphus/scripts/wisdom-*.sh

# Ensure jq is installed (required dependency)
which jq || echo "Install jq first: apt-get install jq / brew install jq"
```

**Prerequisites**:
- `jq` - JSON processor (required)
- `bash` 4.0+ (for associative arrays and modern features)
- `opencode` CLI (optional, for LLM quality scoring in sync)

## Security Considerations

The wisdom system includes built-in secret detection:

- API keys (OpenAI-style `sk-...`, GitHub `ghp_...`)
- Slack tokens (`xoxb-...`)
- Private keys (`-----BEGIN...`)
- Generic credential patterns

Entries containing secrets are blocked at write time. This detection logic is part of `wisdom-common.sh`.

## Troubleshooting

### Scripts fail with "jq not found"

Install jq:
```bash
# Ubuntu/Debian
sudo apt-get install jq

# macOS
brew install jq

# Fedora
sudo dnf install jq
```

### "Entry not found" errors

Verify the scope and project-id:
```bash
# List system entries
jq -r '.id' ~/.sisyphus/wisdom/system.jsonl

# List project entries
ls ~/.sisyphus/wisdom/projects/
```

### Sync not finding learnings

Check notepad locations:
```bash
ls -la ~/.sisyphus/notepads/*/learnings.md
```

### Permission denied

Ensure scripts are executable:
```bash
chmod +x ~/.sisyphus/scripts/wisdom-*.sh
```

## See Also

- [skills/README.md](skills/README.md) - Skill documentation
- [scripts/wisdom/README.md](scripts/wisdom/README.md) - Script bundle documentation
- `wisdom --help` - Skill help (when loaded in OpenCode)
