# Compatibility Debt Register

This document tracks all one-cycle compatibility shims that exist to avoid breaking existing workflows during the Wisdom-first architecture cutover. These shims delegate to Wisdom-backed equivalents and emit deprecation warnings. They are NOT for new work.

## Background

The architecture transitioned from a dual-system model (manifests + knowledge as peer runtime stores) to a single-system model where **Wisdom is the only runtime memory store** and manifests are derivative artifacts only. To avoid breaking existing prompts, scripts, and workflows that referenced the legacy `knowledge-*` commands, compatibility shims were added. This register tracks them with explicit deletion criteria and a removal milestone.

## Shim Inventory

### 1. knowledge-lookup.sh

- **Path**: `scripts/wisdom/knowledge-lookup.sh`
- **Delegates to**: `wisdom-search.sh`
- **Added**: During Wisdom-first redesign cycle (Tasks 9-12)
- **Purpose**: Backward-compatible query interface for agents and scripts that called `knowledge-lookup.sh`
- **Deprecation warning**: Emitted to stderr on every invocation
- **Deletion criteria**:
  - No active prompt in `oh-my-openagent.json` references `knowledge-lookup`
  - No script in this repo calls `knowledge-lookup.sh`
  - No external documentation directs users to use `knowledge-lookup.sh`

### 2. knowledge-snapshot.sh

- **Path**: `scripts/wisdom/knowledge-snapshot.sh`
- **Delegates to**: `wisdom-search.sh` with `--scope all --limit 1000`
- **Added**: During Wisdom-first redesign cycle (Tasks 9-12)
- **Purpose**: Backward-compatible session orientation snapshot for agents that called `knowledge-snapshot.sh`
- **Deprecation warning**: Emitted to stderr on every invocation
- **Deletion criteria**:
  - No active prompt in `oh-my-openagent.json` references `knowledge-snapshot`
  - No script in this repo calls `knowledge-snapshot.sh`
  - No external documentation directs users to use `knowledge-snapshot.sh`

### 3. knowledge-promote.sh

- **Path**: `scripts/knowledge-promote.sh`
- **Delegates to**: `wisdom-publish.sh`
- **Added**: During Wisdom-first redesign cycle (Tasks 9-12)
- **Purpose**: Backward-compatible promotion interface that preserves legacy CLI (`--wisdom-id`, `--type`, `--reason`, `--scope`)
- **Deprecation warning**: Emitted to stderr on every invocation
- **Deletion criteria**:
  - No active prompt in `oh-my-openagent.json` references `knowledge-promote`
  - No script in this repo calls `knowledge-promote.sh`
  - No external documentation directs users to use `knowledge-promote.sh`

### 4. knowledge/ Skill

- **Path**: `skills/knowledge/SKILL.md`
- **Delegates to**: `wisdom/` skill behavior (all queries route to Wisdom-backed equivalents)
- **Added**: During Wisdom-first redesign cycle (Tasks 9-12)
- **Purpose**: Backward-compatible skill registration so existing agent configs that list `knowledge` in their `skills` array continue to function
- **Deprecation notice**: Marked as `[DEPRECATED]` in skill metadata
- **Deletion criteria**:
  - No agent in `oh-my-openagent.json` lists `knowledge` in its `skills` array
  - No prompt or workflow references the `knowledge` skill
  - All agents have been migrated to use `wisdom` explicitly

## Removal Test

Shims can be removed when **no active prompt references legacy names**. Run this check:

```bash
# Must return zero matches
grep -r "knowledge-lookup\|knowledge-snapshot\|knowledge-promote\|knowledge/" \
  configs/oh-my-openagent/oh-my-openagent.json \
  skills/ \
  commands/ \
  docs/
```

## Removal Milestone

**Target**: Remove all shims in the next major cycle after all agents have migrated to `wisdom` explicitly.

**Pre-removal checklist**:
- [ ] All agents in `oh-my-openagent.json` use `wisdom` in their `skills` array
- [ ] No prompt text references `knowledge-lookup`, `knowledge-snapshot`, or `knowledge-promote`
- [ ] `scripts/audit-wisdom-first.sh` passes with zero banned phrase matches
- [ ] `skills/knowledge/` directory is removed
- [ ] `scripts/wisdom/knowledge-lookup.sh` is removed
- [ ] `scripts/wisdom/knowledge-snapshot.sh` is removed
- [ ] `scripts/knowledge-promote.sh` is removed
- [ ] `MANIFEST.md` is updated to remove shim entries
- [ ] `README.md` artifact counts are updated
- [ ] `install.sh` ITEMS array is updated to remove shim entries
- [ ] `skills/README.md` is updated to remove the `knowledge/` entry
- [ ] `scripts/wisdom/README.md` is updated to remove shim entries

## Why Not Remove Now

Removing the shims immediately would break any active session or cached prompt that references the legacy `knowledge` skill or scripts. The one-cycle deprecation period ensures graceful migration without runtime failures.
