# OhMyOpenCode Skills

This directory contains specialized skill modules that extend the OpenCode agent capabilities for specific domains and workflows.

## Skills Overview

### wisdom/
Primary runtime memory skill for institutional knowledge. The single source of truth for operational facts, patterns, decisions, and cross-session learnings. All agents should consult Wisdom before inferring facts from code.
- **Dependencies**: None
- **Use Case**: Searching and recording learnings from plan execution; operational knowledge queries

### knowledge/ (Deprecated)
Compatibility shim that delegates to Wisdom-backed behavior. Retained during a one-cycle deprecation period to avoid breaking existing workflows. Use `wisdom/` for all new work.
- **Dependencies**: wisdom
- **Use Case**: Backward compatibility only

### atlas-review-handler/
Atlas-level review orchestration handler. Processes automated review results from sub-agents, triages findings, delegates critical fixes, and manages the complete review workflow (request → delegate → receive results → parse findings → fix loop → verify).
- **Dependencies**: review-protocol
- **Use Case**: Managing review workflows and handling code review automation

### review-protocol/
Automated code review agent that analyzes git diffs and returns structured findings. Verifies code quality, catches issues, and provides structured feedback in CRITICAL/WARNING/INFO format.
- **Dependencies**: None
- **Use Case**: Conducting code reviews of uncommitted or recent changes

### playwright/
Browser testing agent using playwright-cli. Verifies frontend functionality works correctly with actual user-visible behavior testing, not just error checking.
- **Dependencies**: None
- **Use Case**: Testing UI functionality, exploratory testing, verifying app works correctly

### deployment/
Infrastructure and deployment helper for setting up servers, configuring ports, running services locally, docker-compose, and deployment-related tasks. Maintains port registry to avoid conflicts.
- **Dependencies**: None
- **Use Case**: Managing server setup, Docker deployments, port configuration

### frontend-ui-ux/
Designer-turned-developer UI/UX specialist that crafts stunning UI/UX with multi-dimensional analysis for deep design work. Provides UI/UX expertise even without design mockups.
- **Dependencies**: None
- **Use Case**: Visual engineering, UI design improvements, UX enhancements

### vera/ (External)
Semantic code search and discovery using hybrid BM25+vector retrieval with cross-encoder reranking. Local-first Rust binary with ONNX embeddings — no API keys needed. Provides 70%+ token reduction during codebase discovery compared to brute-force grep.
- **Dependencies**: `vera` binary (install: `bunx @vera-ai/cli install`)
- **Use Case**: Codebase discovery, semantic search, finding logic by concept
- **Install**: `vera agent install --client opencode`
- **Note**: Not stored in this repo — installed externally via Vera's CLI
