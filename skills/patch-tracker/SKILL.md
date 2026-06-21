---
name: patch-tracker
description: Track and verify custom patches to external dependencies. Register, audit, and verify patches survive updates. CRUD lifecycle for patch entries with post-update verification.
---

# Patch Tracker — Skill for Dependency Patch CRUD and Verification

<role>
You are a patch registry operator. When custom patches are applied to external dependencies, you register, track, verify, and deprecate them. Your job is to prevent silent patch debt — patches that get lost on dependency updates without anyone noticing.

Triggers: `/patch-tracker`, `/check-patches`, `/register-patch`, `patch external`, `custom fix`, `won't survive update`, `dependency hack`, `check patches`, `verify patches`, `track patches`, `patch registry`, `dependency modifications`
</role>

---

> **⚠️ DURABLE ALTERNATIVE NUDGE — READ BEFORE PATCHING**
>
> BEFORE creating a direct patch, **ALWAYS** evaluate these alternatives in order:
>
> 1. **Can this be done via a plugin/hook?** (PREFERRED — survives updates automatically)
> 2. **Can this be done via configuration?** (PREFERRED — portable, no code changes)
> 3. **Can this be upstreamed?** (PREFERRED — benefits everyone, eliminates maintenance)
> 4. **Is a direct patch the ONLY option?** (LAST RESORT — register it below)
>
> Direct patches are **technical debt by design**. Every patch registered here is a liability that must be re-verified after every dependency update. If a durable alternative exists, use it instead.

---

## WORKFLOW

### 1. CREATE — Register a New Patch

When invoked with `/register-patch` or when a custom patch is applied:

**Step 1: Evaluate durable alternatives** (see nudge above). If a plugin, hook, or config option exists, use that instead and do NOT create a patch entry.

**Step 2: Gather required frontmatter fields (see `.sisyphus/patches/TEMPLATE.md`):**

| Field | Required | Description |
|-------|----------|-------------|
| `patch_id` | yes | Unique slug: `{dep}--{short-description}` (e.g., `omo--notepad-directive-scoping`) |
| `dependency` | yes | Package or tool name being patched |
| `target_file` | yes | Relative path within the dependency install directory |
| `target_install_path` | yes | Absolute path to the dependency install root |
| `status` | yes | `active` \| `upstreamed` \| `deprecated` |
| `applied_date` | yes | ISO 8601 date when patch was applied (YYYY-MM-DD) |
| `dep_version` | yes | Version or range when patch was applied (e.g., `"0.5.2"`, `">=0.5.0"`, `"current"`) |
| `upstream_issue` | yes | URL to upstream issue/PR tracking the fix, or `"none"` |
| `verification_pattern` | yes | Grep-compatible regex to verify patch is applied |

**Step 3: Gather required body sections:**

Per `.sisyphus/patches/TEMPLATE.md`, the entry body must include:
- `## Problem` — What was broken and why a patch was needed
- `## Patch Description` — What was changed, with before/after summary (no large diffs)
- `## Verification` — How to check if this patch is still applied. Include the exact grep command.
- `## Reapply Instructions` — Step-by-step instructions to reapply this patch if lost after an update
- `## Durable Alternative` — What would make this patch unnecessary (plugin, hook, config, upstream fix). Include status: `{pursued \| not-yet-pursued \| blocked-by-upstream \| not-applicable}`

**Step 3: Validate fields:**
- `patch_id` must match pattern: `^[a-z0-9]+--[a-z0-9-]+$`
- `verification_pattern` must be valid grep-compatible regex (test with `grep -E`)
- `target_file` must be a relative path (no leading `/`)
- `status` must be one of: `active`, `upstreamed`, `deprecated`
- All 5 body sections must be present and non-empty

**Step 4: Create the entry file:**

```bash
# File: .sisyphus/patches/{dep}--{slug}.md
```

Write the entry using the patch template format from `.sisyphus/patches/TEMPLATE.md`.

**Step 5: Capture evidence:**

```bash
# Verify the patch is currently applied
grep -n "${verification_pattern}" "${target_install_path}/${target_file}"
```

**MUST**: If grep finds no match, WARN that the patch may not be applied yet. Still create the entry but note the discrepancy.

---

### 2. READ — List and Inspect Patches

When invoked with `/check-patches` or asked to list patches:

**List all patches:**
```bash
ls -1 .sisyphus/patches/*.md 2>/dev/null | grep -v TEMPLATE.md
```

**Read a specific entry:**
```bash
cat .sisyphus/patches/{patch_id}.md
```

**Quick status summary:**
```bash
grep -l "status: active" .sisyphus/patches/*.md 2>/dev/null | wc -l    # active count
grep -l "status: stale" .sisyphus/patches/*.md 2>/dev/null | wc -l     # stale count
grep -l "status: deprecated" .sisyphus/patches/*.md 2>/dev/null | wc -l # deprecated count
grep -l "status: upstreamed" .sisyphus/patches/*.md 2>/dev/null | wc -l # upstreamed count
```

Report in summary format:
```
Patch Registry: N active, N stale, N deprecated, N upstreamed
```

---

### 3. UPDATE — Modify an Existing Patch Entry

When a patch changes (e.g., reapplied to a new version, verification pattern changes):

**Step 1:** Read the existing entry file.

**Step 2:** Preserve the `patch_id` — this is immutable. Also preserve `applied_date` as the original application date.

**Step 3:** Update the changed fields:
- Update `dep_version` if dependency version changed
- Update `verification_pattern` if the code changed
- Update `status` if the patch state changed
- Update `upstream_issue` if upstream status changed

**Step 4:** Update the `## Patch Description` body section if the change details are different.

**Step 5:** Update the `## Reapply Instructions` body section if the reapplication process changed.

**Step 6:** Write the updated entry back to the same file path.

**MUST**: Never change the `patch_id` or filename.

---

### 4. DEPRECATE — Mark a Patch as No Longer Needed

When a patch is upstreamed, a durable alternative is found, or the dependency is removed:

**Step 1:** Read the existing entry.

**Step 2:** Update `status` to one of:
- `upstreamed` — the fix was merged into the upstream dependency
- `deprecated` — a durable alternative was found or dependency removed

**Step 3:** Update the `## Durable Alternative` body section to document:
- Why the patch is no longer needed
- What replaced it (upstream fix, plugin, config option, etc.)
- Status: now `pursued` (if upstreamed) or `not-applicable` (if no longer relevant)

**CRITICAL**: Do **NOT** delete the entry file. Deprecated entries preserve history and rationale for future reference.

---

### 5. VERIFY — Post-Update Verification

When invoked with `/check-patches` after a dependency update, or on request:

**Step 1:** Read all entry files:
```bash
ls .sisyphus/patches/*.md 2>/dev/null | grep -v TEMPLATE.md
```

**Step 2:** For each entry where `status == "active"`:

a. Resolve the full target path: `{target_install_path}/{target_file}`

b. If the target file doesn't exist → report **"missing-target"**

c. If the target file exists → grep for the `verification_pattern`:
```bash
grep -E "${verification_pattern}" "${target_install_path}/${target_file}"
```

d. Match found → report **"applied"** ✓

e. No match → report **"stale"** ⚠️ (patch was lost during update)

**Step 3:** Summarize results:
```
Patch Verification Results:
  ✓ N applied    — patches confirmed present
  ⚠ N stale      — patches lost, need reapplication
  ✗ N missing-target — target files not found
  ○ N deprecated/upstreamed — skipped (inactive)
```

**Step 4:** For each **stale** patch:
- Surface the `## Reapply Instructions` body section from the entry
- Update the entry's `status` to `deprecated` (or keep as `active` if you plan to reapply)
- Prompt the operator to reapply or deprecate

**Step 5:** For each **missing-target** patch:
- Check if the dependency is still installed
- If removed, suggest deprecating the entry
- If reinstalled to a different path, suggest updating `target_install_path`

---

## VALIDATION RULES

| Rule | Action |
|------|--------|
| Missing required frontmatter fields | Reject: list all missing fields |
| Missing required body sections | Reject: all 5 sections must be present |
| `patch_id` doesn't match `{dep}--{slug}` | Reject: must follow naming convention `^[a-z0-9]+--[a-z0-9-]+$` |
| `verification_pattern` is not grep-compatible | Reject: test with `grep -E` first |
| `target_file` starts with `/` | Reject: must be relative path |
| `status` not in allowed values | Reject: must be one of `active`, `upstreamed`, `deprecated` |
| Filename doesn't match `{dep}--{slug}.md` | Reject: filename must equal `{patch_id}.md` |
| Duplicate `patch_id` | Reject: entry already exists, use UPDATE workflow |
| Deleting an entry file | Reject: use DEPRECATE workflow instead |

---

## EXAMPLES

### Example 1: Register a New Patch (CREATE)

**Scenario:** OpenCode's SSE handler doesn't respect a custom timeout. A direct patch to the source file is the only option after confirming no plugin hook exists.

**Input:**
```
/register-patch
dependency: opencode
target_file: src/sse/handler.ts
target_install_path: /home/user/.local/share/opencode
status: active
applied_date: 2026-03-19
dep_version: 0.5.2
upstream_issue: https://github.com/opencode/opencode/issues/421
verification_pattern: customTimeout\s*=\s*120000

## Problem
OpenCode's SSE handler has a hardcoded 30s timeout that disconnects on slow models.

## Patch Description
Changed the timeout from 30000ms to 120000ms to prevent premature disconnects.
Before: const timeout = 30000
After: const customTimeout = 120000

## Verification
```bash
grep -n "customTimeout\\s*=\\s*120000" /home/user/.local/share/opencode/src/sse/handler.ts
```

## Reapply Instructions
1. Open /home/user/.local/share/opencode/src/sse/handler.ts
2. Find line: const timeout = 30000
3. Replace with: const customTimeout = 120000
4. Restart OpenCode

## Durable Alternative
No config option for SSE timeout. No plugin hook for connection settings.
Upstream issue #421 filed but not yet merged.
Status: not-yet-pursued
```

**Actions performed:**
```bash
# 1. Create entry file
# File: .sisyphus/patches/opencode--fix-sse-timeout.md
# (written with all fields from template)

# 2. Verify patch is currently applied
grep -n "customTimeout\s*=\s*120000" /home/user/.local/share/opencode/src/sse/handler.ts
# Output: 42: const customTimeout = 120000
```

**Output:**
```
✓ Patch registered: opencode--fix-sse-timeout
  Dependency: opencode@0.5.2
  Target: src/sse/handler.ts
  Status: active
  Verification: CONFIRMED (line 42)
  Created: 2026-03-19
```

---

### Example 2: Post-Update Verification (VERIFY)

**Scenario:** OpenCode was updated from 0.5.2 to 0.6.0. Run verification to check all patches.

**Input:**
```
/check-patches
```

**Actions performed:**
```bash
# 1. List active patches
ls .sisyphus/patches/*.md | grep -v TEMPLATE.md
# opencode--fix-sse-timeout.md
# opencode--disable-telemetry.md
# vite--custom-hmr-port.md

# 2. Check each active patch
# opencode--fix-sse-timeout: grep for verification_pattern
grep -E "customTimeout\s*=\s*120000" /home/user/.local/share/opencode/src/sse/handler.ts
# No match → STALE

# opencode--disable-telemetry: grep for verification_pattern
grep -E "telemetry:\s*false" /home/user/.local/share/opencode/config/defaults.ts
# Match found → APPLIED

# vite--custom-hmr-port: target file check
test -f /home/user/project/node_modules/vite/dist/node/server.js
# File not found → MISSING-TARGET
```

**Output:**
```
Patch Verification Results:
  ✓ 1 applied       — patches confirmed present
  ⚠ 1 stale         — patches lost, need reapplication
  ✗ 1 missing-target — target files not found
  ○ 0 deprecated/upstreamed — skipped (inactive)

⚠ STALE: opencode--fix-sse-timeout
  Reapply instructions:
    1. Open /home/user/.local/share/opencode/src/sse/handler.ts
    2. Find line: const timeout = 30000
    3. Replace with: const customTimeout = 120000
    4. Restart OpenCode

✗ MISSING-TARGET: vite--custom-hmr-port
  Expected: /home/user/project/node_modules/vite/dist/node/server.js
  Action: Check if vite is still installed. If removed, deprecate this entry.
```

---

## ANTI-PATTERNS

| Anti-Pattern | Severity | Why |
|--------------|----------|-----|
| Direct-patching without checking for plugin/hook/config alternative first | HIGH | Creates unnecessary patch debt when a durable solution exists |
| Patching without registering | CRITICAL | Silent debt — patch is lost on next update with no record or reapply path |
| Pasting large diffs into entries | MEDIUM | Bloat, licensing concerns — reference the change, don't embed it |
| Modifying target files during verification | HIGH | Verification must be read-only — never alter files when checking status |
| Deleting entries instead of deprecating | MEDIUM | Loses history and rationale — future maintainers won't know why the patch existed |
| Skipping `## Durable Alternative` body section | HIGH | Without this, no one knows if a durable option was evaluated |
| Using non-grep-compatible verification patterns | MEDIUM | Verification step will silently fail, reporting false negatives |

---

## DISCOVERY

This skill is discoverable by:
- **Slash commands**: `/patch-tracker`, `/check-patches`, `/register-patch`
- **Keyword phrases**: "patch external", "custom fix", "won't survive update", "dependency hack", "check patches", "verify patches"
- **Description matches**: "track patches", "patch registry", "dependency modifications"
