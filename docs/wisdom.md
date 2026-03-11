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
│                        │ search  write  sync   archive │   │
│                        │ delete   edit    gc    merge  │   │
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

**Example**:
```bash
# Search for Docker-related patterns
wisdom-search.sh docker --type pattern --limit 5

# Search with JSON output
wisdom-search.sh "build error" --scope project --project-id myapp --json
```

**Access Tracking**: Each search automatically updates `accessed` count and `last_accessed` timestamp for matched entries.

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
