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

## Removal Test

Shims can be removed when **no active prompt references legacy names**. Run this check:

```bash
# Must return zero matches
grep -r "knowledge-lookup\|knowledge-snapshot\|knowledge-promote" \
  configs/oh-my-openagent/oh-my-openagent.json \
  commands/ \
  docs/
```

## Removal Milestone

**Target**: Remove remaining shell script shims in the next major cycle after all prompts and workflows have migrated to `wisdom` explicitly.

**Completed** (skill artifact cleanup):
- [x] All agents in `oh-my-openagent.json` use `wisdom` in their `skills` array
- [x] No agent lists `knowledge` in its `skills` array
- [x] `skills/knowledge/` directory is removed
- [x] `MANIFEST.md` is updated to remove shim entries
- [x] `README.md` artifact counts are updated
- [x] `install.sh` ITEMS array is updated to remove shim entries
- [x] `skills/README.md` is updated to remove the `knowledge/` entry

**Remaining** (shell script shims):
- [ ] No prompt text references `knowledge-lookup`, `knowledge-snapshot`, or `knowledge-promote`
- [ ] `scripts/audit-wisdom-first.sh` passes with zero banned phrase matches
- [ ] `scripts/wisdom/knowledge-lookup.sh` is removed
- [ ] `scripts/wisdom/knowledge-snapshot.sh` is removed
- [ ] `scripts/knowledge-promote.sh` is removed
- [ ] `scripts/wisdom/README.md` is updated to remove shim entries

## Why Not Remove Now

Removing the shell script shims immediately would break any active session or cached prompt that references the legacy `knowledge-*` commands. The one-cycle deprecation period ensures graceful migration without runtime failures.
