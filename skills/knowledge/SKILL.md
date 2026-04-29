---
name: knowledge
description: "[DEPRECATED] Compatibility shim. Delegates all queries to Wisdom-backed behavior. Use the `wisdom` skill for all new work."
---

# Knowledge Management (Deprecated)

> **DEPRECATION NOTICE**: This skill is a one-cycle compatibility shim. It delegates all behavior to the Wisdom system. For new work, use the `wisdom` skill directly.
>
> - Wisdom is the **only runtime memory store**
> - Manifests are derivative artifacts, never authoritative runtime storage
> - All `knowledge-*` scripts are shims that call `wisdom-*` equivalents

## When to Use This Skill

**Do not use this skill for new work.** Use the `wisdom` skill instead.

This skill exists only for backward compatibility during the deprecation cycle. If an existing prompt or workflow references `knowledge`, it will continue to function because the underlying commands delegate to Wisdom.

## Shim Commands (Compatibility Only)

All commands below are thin wrappers around Wisdom. They exist to avoid breaking existing workflows.

### knowledge-lookup.sh (shim)
```bash
~/.sisyphus/scripts/knowledge-lookup.sh "<query>" [--scope <scope>]
```
- **Deprecated**: delegates to `wisdom-search.sh`
- Emits a deprecation warning to stderr
- Returns Wisdom results with authority annotations

### knowledge-snapshot.sh (shim)
```bash
~/.sisyphus/scripts/knowledge-snapshot.sh
```
- **Deprecated**: generates session orientation from canonical Wisdom store only
- Emits a deprecation warning to stderr

### knowledge-promote.sh (shim)
```bash
~/.sisyphus/scripts/knowledge-promote.sh --wisdom-id <id> --type <type> --reason "<justification>"
```
- **Deprecated**: delegates to `wisdom-publish.sh` with legacy CLI interface
- Emits a deprecation warning to stderr

## Migration Path

Replace any usage of these commands with their Wisdom equivalents:

| Old (Deprecated) | New (Primary) |
|------------------|---------------|
| `knowledge-lookup.sh` | `wisdom-search.sh` |
| `knowledge-snapshot.sh` | `wisdom-search.sh` with `--scope` and `--limit` |
| `knowledge-promote.sh` | `wisdom-publish.sh` |
| `knowledge-write` (conceptual) | `wisdom-write.sh` |

## Canonical Contract

All results come from the Wisdom store and carry the canonical contract:

| Field | Values |
|-------|--------|
| `authority` | `candidate`, `verified`, `published` |
| `status` | `active`, `stale`, `superseded`, `retracted` |
| `provenance` | `closeout`, `nomination`, `manual`, `manifest-import`, `migration`, `publish-export`, `compat-shim` |

## Rules
- This skill is **compatibility-only**. Prefer `wisdom` for all new work.
- Do NOT rely on the retired lookup pattern that prioritized manifests. Use Wisdom directly.
- Wisdom is the single source of truth for runtime knowledge.
