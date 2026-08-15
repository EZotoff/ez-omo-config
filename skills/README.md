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

### patch-opencode/
Minimal-fix procedure for patching the live OpenCode binary. Builds from the exact release tag that matches the running version — never from `dev` or any other branch. Covers version pinning via `OPENCODE_VERSION`, source cleanliness verification, two-server stop sequence, patch-presence verification, and PR filing with template compliance notes.
- **Dependencies**: None (standalone procedure)
- **Use Case**: Patching upstream OpenCode bugs locally when waiting for PR merge is not viable
- **Install**: `install.sh --skills`

### debate/
Structured adversarial analysis protocol. Quick single-agent modes (challenge, panel, pre-mortem, red team) plus a decision-review protocol where one agent proposes, one critiques, the proposer revises, and a binding/advisory judge panel decides ADOPT/REVISE/REJECT/ESCALATE.
- **Dependencies**: None
- **Use Case**: Surfacing hidden assumptions, testing argument robustness, making complex architectural decisions
- **Install**: `install.sh --skills`

### reader-report/
Reader-first writing for any deliverable a human reads to understand a result — HTML reports, MD design docs, debate-result summaries, executive briefs, survey dashboards, handoff notes. Writes for a reader who has NOT read the preceding material. Encodes a reader contract (lead with the answer, strip process provenance, self-contained, distinguish fact/inference/recommendation), editorial preferences (no AI-speak, qualitative summaries), channel profiles (chat summary vs rendered report vs decision artifact), an HTML styling guide synthesising the proven house style with impeccable anti-slop tells, and lint-then-independent-review enforcement.
- **Dependencies**: None
- **Use Case**: Producing or editing any reader-facing report/summary/brief; loaded by `/debate` at result-synthesis points
- **Install**: `install.sh --skills`

### bench-author/
Multi-stage research, design, planning, and development of a single ez-omo-bench benchmark for one capability — an OMO sub-agent or task category. Exercises the real subject through the locally installed opencode for both experiments and evaluation; results are machine-readable per `bench/schemas/results.schema.json`. Includes authorized session mining (verbatim reuse, no censorship) and the Ten-Benchmark Shared-Capability Gate.
- **Dependencies**: `bench/` suite home (registry + schema), local `opencode` CLI
- **Use Case**: Authoring a benchmark for a specific sub-agent or category, or resuming an in-progress benchmark
- **Install**: `install.sh --skills`
