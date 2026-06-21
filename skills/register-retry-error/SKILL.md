---
name: register-retry-error
description: Register a new retryable error pattern in the error retry registry. Use when encountering errors that should trigger automatic retry.
---

# Register Retry Error — Skill for Error Pattern Registration

<role>
You are an error registry operator. When encountering errors that should trigger automatic retries, you register new error patterns in the centralized registry. Your job is to validate patterns, prevent duplicates, and ensure atomic writes to the registry file.

Triggers: `/register-retry-error`, `register retry error`, `add retry pattern`
</role>

---

## WORKFLOW

### 1. Accept Parameters

When invoked with `/register-retry-error`, request or receive:
- **pattern** (required): The error message pattern to match (regex string)
- **description** (required): Human-readable explanation of the error
- **max_retries** (optional): Number of retries after initial attempt (default: 3)
- **backoff_ms** (optional): Array of delay times in milliseconds (default: [1000, 6000, 36000])
- **retry_after_tool_execution** (optional): Whether to retry even after tool execution (default: false)
- **added_by** (optional): Your identifier or "operator" (default: "operator")

### 2. Validate Regex Pattern

Before proceeding, validate the provided pattern:

```javascript
try {
  new RegExp(pattern)
} catch (e) {
  throw new Error(`Invalid regex pattern: ${e.message}`)
}
```

**MUST**: Reject invalid patterns immediately with clear error message.

### 3. Generate Kebab-Case ID

Create a unique `id` from the `description`:
- Convert to lowercase
- Replace spaces and underscores with hyphens
- Remove special characters (keep only alphanumeric and hyphens)
- Limit to ~50 characters
- Ensure it matches the pattern: `^[a-z0-9]([a-z0-9-]*[a-z0-9])?$`

Example:
- "Network timeout on SSE stream" → "network-timeout-on-sse-stream"
- "Provider Rate Limited" → "provider-rate-limited"

### 4. Check for Duplicates

Read the current registry file: `~/.config/opencode/retry-errors.json`

**MUST** verify:
- No existing entry has the same `id` (duplicate key)
- No existing entry has the same `pattern` string (duplicate pattern)

If duplicates found, reject with reason: "Entry with id '{id}' already exists" or "Pattern already registered"

### 5. Prepare Registry Entry

Create the new entry object with ALL required fields:

```json
{
  "id": "generated-from-description",
  "pattern": "provided-regex-string",
  "match_type": "regex",
  "max_retries": 3,
  "backoff_ms": [1000, 6000, 36000],
  "retry_after_tool_execution": false,
  "description": "provided-description",
  "added_by": "operator",
  "added_at": "YYYY-MM-DD (current date in ISO format)"
}
```

Replace default values with user-provided values where specified. **Important**: Always use the current date in ISO format (YYYY-MM-DD) for `added_at`, computed at the time of registration.

**Verify**: `backoff_ms.length === max_retries` (critical constraint)

### 6. Atomic Write to Registry

**MUST USE ATOMIC WRITE** to prevent JSON corruption:

```javascript
const fs = require('fs');
const path = require('path');
const os = require('os');

const registryPath = path.join(os.homedir(), '.config', 'opencode', 'retry-errors.json');
const tempPath = registryPath + '.tmp';

// 1. Read current registry
const registry = JSON.parse(fs.readFileSync(registryPath, 'utf8'));

// 2. Append new entry
registry.errors.push(newEntry);

// 3. Write to temp file
fs.writeFileSync(tempPath, JSON.stringify(registry, null, 2), 'utf8');

// 4. Rename atomically (atomic on POSIX systems)
fs.renameSync(tempPath, registryPath);
```

**CRITICAL**: Never write directly to the registry file. Always:
1. Write to temp file first
2. Then rename (atomic)
3. Clean up temp file on error

### 7. Confirm Registration

On success, report:

```
✓ Successfully registered new error pattern
  ID: {generated-id}
  Pattern: {pattern}
  Max Retries: {max_retries}
  Backoff: {backoff_ms}
  Description: {description}
  Added At: {timestamp}

The new pattern will take effect on the next error event (hot-reload).
```

---

## VALIDATION RULES

| Rule | Action |
|------|--------|
| Invalid regex | Reject with error message, do NOT write |
| Duplicate id | Reject, suggest alternative id |
| Duplicate pattern | Reject, warn that pattern is already registered |
| Backoff length mismatch | Reject: `backoff_ms.length must equal max_retries` |
| Missing required fields | Reject: list missing fields |
| File write fails | Reject: include error message, do NOT corrupt registry |
| Registry file missing | Reject: registry file must exist (created by task-1) |
| Registry file invalid JSON | Reject: report JSON parse error, do NOT overwrite |

---

## PATTERN CRAFTING GUIDELINES

### DO:
- ✓ Use specific error message strings: `"SSE read timed out"`, `"Connection refused"`
- ✓ Escape regex special characters: `\.`, `\(`, `\)`, `\[`, `\]`
- ✓ Use case-insensitive matching (patterns compiled with `i` flag)
- ✓ Test the pattern against actual error messages before committing
- ✓ Include enough context to be specific but not so much that minor wording changes break matches

### DON'T:
- ✗ Generic catch-all patterns: bare `timeout`, `error`, `failed`
- ✗ Unescaped special characters that will break the regex
- ✗ Patterns matching too broadly (e.g., `.*` that matches everything)
- ✗ Patterns for permanent errors: auth failures, syntax errors, context-length exceeded
- ✗ Patterns for user-caused errors: invalid input, wrong config

---

## EXAMPLES

### Example 1: Register SSE Timeout (Already Exists)
**Input:**
- Pattern: `SSE read timed out`
- Description: LLM SSE stream read timeout

**Output:**
```
ID: sse-read-timeout
Pattern: SSE read timed out
Max Retries: 3
Backoff: [1000, 6000, 36000]
Added At: {current-date}
```

### Example 2: Register Rate Limit Error
**Input:**
- Pattern: `rate limit.*exceeded|too many requests`
- Description: Provider rate limit exceeded on API call
- max_retries: 4
- backoff_ms: [2000, 10000, 30000, 60000]

**Output:**
```
ID: provider-rate-limit-exceeded
Pattern: rate limit.*exceeded|too many requests
Max Retries: 4
Backoff: [2000, 10000, 30000, 60000]
Description: Provider rate limit exceeded on API call
Added At: {current-date}
```

---

## ANTI-PATTERNS (NEVER DO THESE)

| Violation | Severity | Reason |
|-----------|----------|--------|
| Accept raw JSON input | CRITICAL | Must parse and validate parameters individually |
| Allow overwriting existing entries | CRITICAL | Duplicates must be rejected |
| Skip regex validation | CRITICAL | Invalid patterns break the plugin at runtime |
| Direct file write (no temp file) | CRITICAL | Risks JSON corruption on write failure |
| Add edit/delete/list functionality | CRITICAL | v1 is register-only; no CRUD beyond append |
| Allow patterns that match permanent errors | HIGH | Would cause unnecessary retries on fatal errors |
| Generic catch-all patterns | HIGH | Would retry errors that shouldn't be retried |

---

## DISCOVERY

This skill is discoverable by:
- **Slash command**: `/register-retry-error`
- **Keyword phrases**: "register retry error", "add retry pattern", "register error pattern"
- **Description match**: Searching for "error" or "registry" or "retry"
