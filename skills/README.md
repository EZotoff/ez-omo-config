# OhMyOpenCode Skills

This directory contains specialized skill modules that extend the OpenCode agent capabilities for specific domains and workflows.

## Skills Overview

### wisdom/
Primary runtime memory skill for institutional knowledge. The single source of truth for operational facts, patterns, decisions, and cross-session learnings. All agents should consult Wisdom before inferring facts from code.
- **Dependencies**: None
- **Use Case**: Searching and recording learnings from plan execution; operational knowledge queries

### atlas-review-handler/
Atlas-level review orchestration handler. Processes automated review results from sub-agents, triages findings, delegates critical fixes, and manages the complete review workflow (request → delegate → receive results → parse findings → fix loop → verify).
- **Dependencies**: review-protocol
- **Use Case**: Managing review workflows and handling code review automation
- **Live Gate Note**: This is a **referenced external skill**. It does **not** enforce the Live Deployment Verification Gate, unless later versioned in this repo. The gate is enforced by tracked repo files: `AGENTS.md`, `plugins/review-enforcer.ts`, and `scripts/verify-live-deployment.sh`.

### review-protocol/
Automated code review agent that analyzes git diffs and returns structured findings. Verifies code quality, catches issues, and provides structured feedback in CRITICAL/WARNING/INFO format.
- **Dependencies**: None
- **Use Case**: Conducting code reviews of uncommitted or recent changes
- **Live Gate Note**: This is a **referenced external skill**. It does **not** enforce the Live Deployment Verification Gate, unless later versioned in this repo. The gate is enforced by tracked repo files: `AGENTS.md`, `plugins/review-enforcer.ts`, and `scripts/verify-live-deployment.sh`.

### patch-tracker/
Patch registry operator. Tracks custom patches to external dependencies through a full CRUD lifecycle (CREATE, READ, UPDATE, DEPRECATE, VERIFY) with post-update verification. Surfaces a "durable alternative nudge" before allowing direct patches.
- **Dependencies**: `.sisyphus/patches/TEMPLATE.md`
- **Use Case**: Preventing silent patch debt — patches lost on dependency updates with no record

### register-retry-error/
Error registry operator. Registers new retryable error patterns in the centralized retry-errors registry (`~/.config/opencode/retry-errors.json`). Validates regex patterns, prevents duplicates, and uses atomic writes.
- **Dependencies**: `retry-errors.json` registry, `provider-connect-retry.mjs` plugin
- **Use Case**: Adding new retryable error patterns at runtime

### session-id/
Minimal utility skill that copies the current OpenCode session ID to clipboard via `opencode session list -n 1` + `jq` + `xclip`. Mirrors the behavior of the `session-id.ts` plugin (which intercepts the `/session-id` slash command without an LLM round-trip).
- **Dependencies**: `opencode` CLI, `jq`, `xclip`
- **Use Case**: Quick clipboard copy of the current session ID

### deployment/
Infrastructure and deployment helper for setting up servers, configuring ports, running services locally, docker-compose, and deployment-related tasks. Maintains port registry to avoid conflicts.
- **Dependencies**: None
- **Use Case**: Managing server setup, Docker deployments, port configuration

### update-to-latest/
Safe OpenCode/OMO update pipeline with explicit human approval gate, patch-tracker integration, rollback capability, and evidence-state claim discipline. A 13-phase guided operational pipeline that analyzes available updates, produces a go/no-go recommendation, and only executes after explicit human approval.
- **Dependencies**: `patch-tracker` skill (referenced)
- **Use Case**: Analyzing whether to update OpenCode or OMO, executing updates safely with full rollback capability
- **Install**: `install.sh --skills`

### debate/
Structured adversarial debate protocol with configurable judge panels, scoring rubrics, and 6 distinct modes for rigorous technical analysis. Orchestrates multi-agent debates with formal rules, evidence tracking, and consensus building. Uses deterministic label blinding (Alpha/Beta only — judges never see agent names).
- **Dependencies**: None (orchestrates other agents via `task()`)
- **Use Case**: Surfacing hidden assumptions, testing argument robustness, making complex architectural decisions, evaluating competing approaches
- **Install**: `install.sh --skills`

### vera-hygiene/
Vera index hygiene and `.veraignore` management. Detects unreadable directories, heavy/generated dirs, and safely updates `.veraignore` with a marker-managed block. Must be run before indexing large or external projects, or after Vera indexing failures.
- **Dependencies**: `vera-hygiene.sh` script
- **Use Case**: Pre-indexing hygiene, fixing permission-denied indexing failures, preventing self-indexing
- **Install**: `install.sh --skills` (installs both skill and script)

### vera/ (External)
Semantic code search and discovery using hybrid BM25+vector retrieval with cross-encoder reranking. Local-first Rust binary with ONNX embeddings — no API keys needed. Provides 70%+ token reduction during codebase discovery compared to brute-force grep.
- **Dependencies**: `vera` binary (install: `bunx @vera-ai/cli install`)
- **Use Case**: Codebase discovery, semantic search, finding logic by concept
- **Install**: `vera agent install --client opencode`
- **Note**: Not stored in this repo — installed externally via Vera's CLI
