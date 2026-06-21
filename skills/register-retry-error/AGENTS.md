# Agent Error Learning Instructions

> Proactive retry-error recording for agent self-improvement

When you encounter an error that looks transient and retryable, record it so future sessions retry automatically.

---

## When to Record

Record an error when ALL of these are true:

1. **Session failed** due to provider/network issue (not user error)
2. **Error appears transient** — timeouts, connection failures, rate limits, not permanent failures
3. **You've seen this before** — same or similar error in comparable contexts
4. **Provider-related keywords** present — SSE, timeout, connection, ECONNREFUSED, rate limit

**Signal phrases**: "SSE read timed out", "connection refused", "unable to connect", "rate limit exceeded"

---

## How to Record

Follow this exact procedure to add a new error pattern to `~/.config/opencode/retry-errors.json`:

### Step 1: Read Current Registry

```javascript
const fs = require('fs');
const path = require('path');
const os = require('os');

const registryPath = path.join(os.homedir(), '.config', 'opencode', 'retry-errors.json');
const registry = JSON.parse(fs.readFileSync(registryPath, 'utf8'));
```

### Step 2: Craft the Pattern

Extract the specific error message substring. Escape regex special characters.

```javascript
// Bad: too generic
const pattern = 'timeout';  // NO — matches too much

// Good: specific
const pattern = 'SSE read timed out';  // YES — precise match
```

### Step 3: Validate the Regex

```javascript
try {
  new RegExp(pattern, 'i');
  console.log('Pattern valid');
} catch (e) {
  throw new Error(`Invalid regex: ${e.message}`);
}
```

### Step 4: Check for Duplicates

```javascript
const newId = 'my-error-id';  // kebab-case from description
const newPattern = 'my specific error';

// Check duplicate ID
if (registry.errors.some(e => e.id === newId)) {
  throw new Error(`Entry with id '${newId}' already exists`);
}

// Check duplicate pattern
if (registry.errors.some(e => e.pattern === newPattern)) {
  throw new Error('Pattern already registered');
}
```

### Step 5: Build the Entry

```javascript
const today = new Date().toISOString().split('T')[0];  // YYYY-MM-DD

const newEntry = {
  id: newId,
  pattern: newPattern,
  match_type: 'regex',
  max_retries: 3,
  backoff_ms: [1000, 6000, 36000],
  retry_after_tool_execution: false,
  description: 'Human-readable description of the error',
  added_by: 'agent',
  added_at: today
};

// Critical constraint: backoff_ms.length MUST equal max_retries
if (newEntry.backoff_ms.length !== newEntry.max_retries) {
  throw new Error('backoff_ms.length must equal max_retries');
}
```

### Step 6: Atomic Write

**CRITICAL**: Never write directly to the registry file. Use temp-file-then-rename:

```javascript
const tempPath = registryPath + '.tmp';

// Append new entry
registry.errors.push(newEntry);

// Write to temp file first
fs.writeFileSync(tempPath, JSON.stringify(registry, null, 2), 'utf8');

// Atomic rename (POSIX guarantees this is atomic)
fs.renameSync(tempPath, registryPath);

console.log(`✓ Registered: ${newId}`);
```

### Concrete Example

Adding a hypothetical "DNS lookup failed" error:

```javascript
const fs = require('fs');
const path = require('path');
const os = require('os');

const registryPath = path.join(os.homedir(), '.config', 'opencode', 'retry-errors.json');

// 1. Read current registry
const registry = JSON.parse(fs.readFileSync(registryPath, 'utf8'));

// 2. Define new error pattern
const newId = 'dns-lookup-failed';
const newPattern = 'getaddrinfo.*ENOTFOUND';

// 3. Validate regex
try {
  new RegExp(newPattern, 'i');
} catch (e) {
  throw new Error(`Invalid regex: ${e.message}`);
}

// 4. Check duplicates
if (registry.errors.some(e => e.id === newId)) {
  throw new Error(`Entry with id '${newId}' already exists`);
}
if (registry.errors.some(e => e.pattern === newPattern)) {
  throw new Error('Pattern already registered');
}

// 5. Build entry with today's date
const today = new Date().toISOString().split('T')[0];
const newEntry = {
  id: newId,
  pattern: newPattern,
  match_type: 'regex',
  max_retries: 3,
  backoff_ms: [1000, 6000, 36000],
  retry_after_tool_execution: false,
  description: 'DNS resolution failure — transient network issue',
  added_by: 'agent',
  added_at: today
};

// 6. Atomic write
const tempPath = registryPath + '.tmp';
registry.errors.push(newEntry);
fs.writeFileSync(tempPath, JSON.stringify(registry, null, 2), 'utf8');
fs.renameSync(tempPath, registryPath);

console.log(`✓ Successfully registered: ${newId}`);
```

---

## Pattern Crafting

### DO:

- Use **specific error message strings**: `"SSE read timed out"`, `"Connection refused"`
- **Escape regex special characters**: `\.`, `\(`, `\)`, `\[`, `\]`, `\*`, `\+`
- Test case-insensitive matching (the plugin compiles with `i` flag)
- Include **enough context to be specific** but not so much that minor wording changes break matches
- Use `.*` sparingly for variable parts: `"rate limit.*exceeded"`

### DON'T:

- Use **generic catch-all patterns**: bare `timeout`, `error`, `failed`
- Leave **unescaped special characters** that will break the regex
- Create patterns matching **too broadly** (e.g., `.*` that matches everything)
- Assume exact formatting — providers may change error message casing

### Escape Reference

| Char | Escape | Example match |
|------|--------|---------------|
| `.`  | `\.`   | literal dot   |
| `*`  | `\*`   | literal asterisk |
| `(`  | `\(`   | literal paren |
| `[`  | `\[`   | literal bracket |
| `?`  | `\?`   | literal question |

---

## What NOT to Record

**Never record these error types** — they're permanent or user-caused:

| Type | Examples | Why Skip |
|------|----------|----------|
| **Auth failures** | "Invalid API key", "Authentication failed" | Won't fix on retry |
| **Permission denied** | "Access denied", "Forbidden" | Requires user action |
| **Context length** | "Context length exceeded", "Too many tokens" | Permanent limit hit |
| **Validation errors** | "Invalid request", "Bad request" | User input problem |
| **Syntax errors** | Code won't compile, JSON parse fail | Fix the code first |
| **Config errors** | Wrong model name, invalid settings | Fix the config |

**Also skip**:
- Errors that should trigger **model fallback** (different model may succeed)
- Generic patterns that would match unrelated errors
- Errors after tool execution (safety — side effects already happened)

---

## Schema Reference

Complete field documentation for `retry-errors.json` entries:

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `id` | string | Yes | — | Unique kebab-case identifier (e.g., `"sse-read-timeout"`) |
| `pattern` | string | Yes | — | Valid regex pattern to match error messages |
| `match_type` | string | Yes | `"regex"` | Matching strategy (always `"regex"` for v1) |
| `max_retries` | integer | Yes | 3 | Number of retries AFTER initial attempt (3 = 4 total) |
| `backoff_ms` | number[] | Yes | `[1000,6000,36000]` | Delay in ms for each retry attempt. **MUST equal max_retries length** |
| `retry_after_tool_execution` | boolean | Yes | `false` | Whether to retry even after tool execution (default false = safe) |
| `description` | string | Yes | — | Human-readable explanation |
| `added_by` | string | Yes | `"operator"` | Who added this entry: `"seed"`, `"operator"`, or agent ID |
| `added_at` | string | Yes | current date | ISO date: `YYYY-MM-DD` |

### Constraints

1. **backoff_ms.length === max_retries** — Critical. Plugin validates this on load.
2. **Pattern must compile** — Invalid regex causes the rule to be skipped.
3. **ID must be unique** — Duplicate IDs cause confusion; check before adding.
4. **Date must be ISO format** — Use `new Date().toISOString().split('T')[0]`

### Plugin Behavior

The plugin hot-reloads the registry **on every error event**:

1. Reads `~/.config/opencode/retry-errors.json`
2. Validates each entry's shape
3. Compiles regex patterns with `i` flag (case-insensitive)
4. **Skips invalid individual rules** — one bad entry doesn't break others
5. Falls back to `[]` (no retries) if the entire registry fails to load

Your newly added entry takes effect **immediately** on the next error — no restart needed.

---

## Quick Checklist

Before writing a new error entry, verify:

- [ ] Pattern is specific (not generic `timeout`)
- [ ] Regex compiles with `new RegExp(pattern, 'i')`
- [ ] No duplicate ID exists
- [ ] No duplicate pattern exists
- [ ] `backoff_ms.length === max_retries`
- [ ] Using atomic write (temp file + rename)
- [ ] Date is ISO format (`YYYY-MM-DD`)
- [ ] Error is transient (not auth/validation/context-length)
