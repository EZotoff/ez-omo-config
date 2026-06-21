# Compatibility Debt Register

> **Status**: Closed (2026-06-21). All compatibility shims removed. Wisdom is the sole runtime memory store. This document is retained as a historical record.

## Background

The architecture transitioned from a dual-system model (manifests + knowledge as peer runtime stores) to a single-system model where **Wisdom is the only runtime memory store** and manifests are derivative artifacts only. Compatibility shims were added to avoid breaking existing prompts, scripts, and workflows that referenced the legacy `knowledge-*` commands.

This register tracked the shims with explicit deletion criteria and a removal milestone. All criteria are now satisfied and the shims have been removed.

## Removed Shims (Historical Record)

### 1. knowledge-lookup.sh (removed)

- **Path**: `scripts/wisdom/knowledge-lookup.sh`
- **Delegated to**: `wisdom-search.sh`
- **Purpose**: Backward-compatible query interface for agents and scripts that called `knowledge-lookup.sh`
- **Deletion criteria** (all satisfied): No active prompt references `knowledge-lookup`, no script in repo calls `knowledge-lookup.sh`, no external documentation directs users to it.

### 2. knowledge-snapshot.sh (removed)

- **Path**: `scripts/wisdom/knowledge-snapshot.sh`
- **Delegated to**: `wisdom-search.sh` with `--scope all --limit 1000`
- **Purpose**: Backward-compatible session orientation snapshot for agents that called `knowledge-snapshot.sh`
- **Deletion criteria** (all satisfied): No active prompt references `knowledge-snapshot`, no script in repo calls `knowledge-snapshot.sh`, no external documentation directs users to it.

### 3. knowledge-promote.sh (removed)

- **Path**: `scripts/knowledge-promote.sh`
- **Delegated to**: `wisdom-publish.sh`
- **Purpose**: Backward-compatible promotion interface that preserved legacy CLI (`--wisdom-id`, `--type`, `--reason`, `--scope`)
- **Deletion criteria** (all satisfied): No active prompt references `knowledge-promote`, no script in repo calls `knowledge-promote.sh`, no external documentation directs users to it.

### 4. skills/knowledge/ (removed)

- **Path**: `skills/knowledge/`
- **Purpose**: Skill-form wrapper around the three shim scripts above
- **Deletion criteria** (all satisfied): Wisdom is the sole runtime memory store; no agent in `oh-my-openagent.json` references `knowledge` in its skills array.

## Retained Files

### knowledge-constants.sh (retained — load-bearing)

- **Path**: `scripts/wisdom/knowledge-constants.sh`
- **Reason retained**: Sourced by 9 active files including `wisdom-publish.sh`, `manifest-write.sh`, and multiple test scripts. Defines the canonical constants (`WISDOM_BASE_DIR`, `WISDOM_SYSTEM_DIR`, `KNOWLEDGE_BASE_DIR`, `AUTHORITY_*`, `PROVENANCE_*`, `STATUS_*`, `SCOPE_*`) used across both subsystems.
- **Future**: Could be renamed to `wisdom-constants.sh` in a future refactor pass that updates all sourcing callers. The current name reflects historical origin, not current scope.

## Removal Milestone

**Status**: ✅ Completed 2026-06-21. All shims removed; Wisdom is the sole runtime memory store.

All removal criteria are satisfied and the shims have been deleted from the repo. The checklist below records what was verified before deletion:

- [x] All agents in `oh-my-openagent.json` use `wisdom` in their `skills` array
- [x] No agent lists `knowledge` in its `skills` array
- [x] `skills/knowledge/` directory is removed
- [x] `MANIFEST.md` is updated to remove shim entries
- [x] `README.md` artifact counts are updated
- [x] `install.sh` ITEMS array is updated to remove shim entries
- [x] `skills/README.md` is updated to remove the `knowledge/` entry
- [x] No prompt text references `knowledge-lookup`, `knowledge-snapshot`, or `knowledge-promote`
- [x] `scripts/audit-wisdom-first.sh` passes with zero banned phrase matches
- [x] `scripts/wisdom/knowledge-lookup.sh` is removed
- [x] `scripts/wisdom/knowledge-snapshot.sh` is removed
- [x] `scripts/knowledge-promote.sh` is removed
- [x] `scripts/wisdom/README.md` is updated to remove shim entries
- [x] `scripts/wisdom/test-knowledge-contracts.sh` is removed (tested only the deleted shims)
