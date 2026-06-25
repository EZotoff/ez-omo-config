# OhMyOpenCode Skills

This directory contains specialized skill modules that extend OpenCode agent capabilities for specific domains and workflows.

## Skills Overview

### wisdom/
Primary runtime memory skill for institutional knowledge. The single source of truth for operational facts, patterns, decisions, and cross-session learnings. All agents should consult Wisdom before inferring facts from code.
- **Dependencies**: None
- **Use Case**: Searching and recording learnings from plan execution; operational knowledge queries

### atlas-review-handler/
Atlas-level review orchestration handler. Processes automated review results from sub-agents, triages findings, delegates critical fixes, and manages the complete review workflow.
- **Dependencies**: review-protocol
- **Use Case**: Managing review workflows and handling code review automation
- **Live Gate Note**: The gate is enforced by tracked repo files: `AGENTS.md`, `plugins/review-enforcer.ts`, and `scripts/verify-live-deployment.sh`.

### review-protocol/
Automated code review agent that analyzes git diffs and returns structured findings in CRITICAL/WARNING/INFO format.
- **Dependencies**: None
- **Use Case**: Conducting code reviews of uncommitted or recent changes

### patch-tracker/
Patch registry operator. Tracks custom patches to external dependencies through a full CRUD lifecycle with post-update verification.
- **Dependencies**: `.sisyphus/patches/TEMPLATE.md`
- **Use Case**: Preventing silent patch debt

### register-retry-error/
Error registry operator. Registers new retryable error patterns in the centralized retry-errors registry.
- **Dependencies**: `retry-errors.json` registry, `provider-connect-retry.mjs` plugin
- **Use Case**: Adding new retryable error patterns at runtime

### session-id/
Minimal utility skill that copies the current OpenCode session ID to clipboard. Mirrors the behavior of the `session-id.ts` plugin.
- **Dependencies**: `opencode` CLI, `jq`, `xclip`
- **Use Case**: Quick clipboard copy of the current session ID

### deployment/
Infrastructure and deployment helper for server setup and service management. Maintains a port registry to avoid conflicts.
- **Dependencies**: None
- **Use Case**: Managing server setup, Docker deployments, port configuration

### update-to-latest/
Safe OpenCode/OMO update pipeline with explicit human approval gate, patch-tracker integration, rollback capability, and evidence-state claim discipline.
- **Dependencies**: `patch-tracker` skill (referenced)
- **Use Case**: Analyzing and executing OpenCode/OMO updates safely
- **Install**: `install.sh --skills`

### debate/
Structured adversarial debate protocol with configurable judge panels, scoring rubrics, and 6 distinct modes for rigorous technical analysis.
- **Dependencies**: None
- **Use Case**: Surfacing hidden assumptions, testing argument robustness, making complex architectural decisions
- **Install**: `install.sh --skills`
