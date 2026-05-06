# Skill System

The OhMyOpenCode skill system provides specialized domain expertise through modular skill packages that extend OpenCode agent capabilities. Skills cover areas from code review automation to browser testing and deployment management.

## Overview

Skills are self-contained directories with metadata and implementation that OpenCode loads dynamically. They can:

- Provide specialized knowledge for specific domains
- Register new tools and capabilities
- Chain together for complex workflows
- Store and propagate learned patterns

Skills are categorized as **Required** (core functionality) or **Optional** (domain-specific enhancements).

---

## Required Skills

These skills provide core functionality and are essential for the OhMyOpenCode workflow.

### wisdom/

**Purpose**: Wisdom propagation system for accumulating cross-plan learnings.

**Features**:

- Records patterns, conventions, and successful approaches
- Enables knowledge reuse across development sessions
- Supports system, project, and plan-level scope
- Integrates with wisdom shell scripts for storage

**Dependencies**: wisdom-common.sh, wisdom-search.sh, wisdom-write.sh, etc. (see [wisdom.md](wisdom.md))

**Use Case**: Searching and recording learnings from plan execution

**Status**: Required

**Install Target**: `$HOME/.config/opencode/skills/wisdom/`

---

### atlas-review-handler/

**Purpose**: Atlas-level review orchestration handler. Manages the complete review workflow.

**Features**:

- Processes automated review results from sub-agents
- Triages findings (CRITICAL/WARNING/INFO)
- Delegates critical fixes via task()
- Enforces max 2 review iterations per task
- Manages workflow: request → delegate → receive → parse → fix → verify

**Dependencies**:

- `review-protocol/` skill (required)
- `wisdom/` skill (referenced)

**Live Gate Enforcement Note**:

`atlas-review-handler/` and `review-protocol/` are external skills. They are **not** the source of mandatory Live Deployment Verification Gate enforcement. The core live gate is enforced in tracked repo surfaces: `AGENTS.md` (evidence-state taxonomy), `plugins/review-enforcer.ts` (runtime gate), and `scripts/verify-live-deployment.sh` (canonical verifier). Skills may reference the gate, but the authoritative enforcement lives in the repo's tracked files.

**Use Case**: Managing review workflows and handling code review automation

**Status**: Required

**Install Target**: `$HOME/.config/opencode/skills/atlas-review-handler/`

---

### review-protocol/

**Purpose**: Automated code review agent that analyzes git diffs and returns structured findings.

**Features**:

- Analyzes uncommitted or recent changes
- Returns findings in CRITICAL/WARNING/INFO format
- Verifies code quality and catches issues
- Provides structured, actionable feedback

**Dependencies**: None

**Live Gate Enforcement Note**:

Like `atlas-review-handler/`, this skill participates in review workflows but does **not** enforce the Live Deployment Verification Gate. The gate is enforced by tracked repo files: `AGENTS.md`, `plugins/review-enforcer.ts`, and `scripts/verify-live-deployment.sh`.

**Use Case**: Conducting code reviews of uncommitted or recent changes

**Status**: Required

**Install Target**: `$HOME/.config/opencode/skills/review-protocol/`

---

## Optional Skills

These skills provide domain-specific enhancements and can be installed based on project needs.

### playwright/

**Purpose**: Browser testing agent using playwright-cli for frontend verification.

**Features**:

- Verifies frontend functionality with actual user-visible behavior
- More thorough than simple error checking
- Tests real user interactions
- 4x more token-efficient than MCP approaches

**Dependencies**: None

**Use Case**: Testing UI functionality, exploratory testing, verifying apps work correctly

**Status**: Optional

**Install Target**: `$HOME/.config/opencode/skills/playwright/`

---

### deployment/

**Purpose**: Infrastructure and deployment helper for server setup and service management.

**Features**:

- Server setup and configuration
- Port management with registry to avoid conflicts
- Docker and docker-compose support
- Local service running
- Deployment task automation

**Dependencies**: None

**Use Case**: Managing server setup, Docker deployments, port configuration

**Status**: Optional

**Install Target**: `$HOME/.config/opencode/skills/deployment/`

---

### frontend-ui-ux/

**Purpose**: Designer-turned-developer UI/UX specialist for visual engineering.

**Features**:

- Crafts stunning UI/UX even without design mockups
- Multi-dimensional analysis for deep UI work
- Provides UI/UX expertise and recommendations
- Design pattern knowledge

**Dependencies**: None

**Use Case**: Visual engineering, UI design improvements, UX enhancements

**Status**: Optional

**Install Target**: `$HOME/.config/opencode/skills/frontend-ui-ux/`

---

### vera-hygiene/

**Purpose**: Vera index hygiene and `.veraignore` management. Prevents indexing failures by excluding unreadable, heavy, or generated paths.

**Features**:

- Detects unreadable directories (e.g., container-owned data dirs)
- Detects heavy/generated directories (`node_modules/`, `.next/`, `build/`, etc.)
- Prevents Vera self-indexing (always excludes `.vera/`)
- Preserves all existing user `.veraignore` content
- Marker-managed block (`# BEGIN OMO VERA HYGIENE` / `# END OMO VERA HYGIENE`)
- Tracked-file safety: skips broad parent dirs if git-tracked files exist underneath
- Three modes: `--check`, `--dry-run`, `--apply`

**Dependencies**: `scripts/vera-hygiene.sh`

**Use Case**: Pre-indexing hygiene for large/external projects, fixing permission-denied or zero-files indexing failures

**Status**: Optional (Recommended)

**Install Target**: `$HOME/.config/opencode/skills/vera-hygiene/` (skill), `$HOME/.sisyphus/scripts/vera-hygiene.sh` (script)

**Install Method**: `install.sh --skills` or `install.sh --scripts`

---

### vera/

**Purpose**: Semantic code search and discovery for efficient codebase navigation.

**Features**:

- Hybrid retrieval: BM25 + vector search + cross-encoder reranking
- Local-first: single Rust binary, ONNX embeddings, no API keys needed
- Fast indexing: ~8 seconds for multi-MB codebases
- Token-efficient Markdown output (40% smaller than JSON)
- Background watcher for automatic index freshness
- Dead code detection and symbol reference tracing

**Dependencies**: None (self-contained binary)

**Use Case**: Codebase discovery, finding logic by concept, semantic search, avoiding token-wasting grep for discovery

**Status**: Optional (Recommended)

**Install Target**: `$HOME/.config/opencode/skills/vera/` (installed via `vera agent install --client opencode`)

**Agents Using This Skill**: `explore`, `sisyphus`, `librarian`, `prometheus`

**Install Method**: `vera agent install --client opencode --scope global`

**Note**: Vera is installed globally via its own CLI. Global scope is recommended so all projects and agents share the same Vera installation. Project scope is optional and only needed if the global install fails. Vera is NOT managed by `install.sh`. See [Vera Implementation Plan](../docs/vera-implementation-plan.md) for details.

---

## Dependency Clusters

```
Wisdom System Cluster:
wisdom/ → wisdom-common.sh → wisdom-search.sh, wisdom-write.sh, etc.

Review System Cluster:
atlas-review-handler/ → review-protocol/ (direct dependency)
                    → wisdom/ (reference)
```

---

## Installation Summary

| Skill | Status | Install Target | Install Method |
|-------|--------|----------------|----------------|
| wisdom/ | Required | `$HOME/.config/opencode/skills/wisdom/` | `install.sh` |
| atlas-review-handler/ | Required | `$HOME/.config/opencode/skills/atlas-review-handler/` | `install.sh` |
| review-protocol/ | Required | `$HOME/.config/opencode/skills/review-protocol/` | `install.sh` |
| playwright/ | Optional | `$HOME/.config/opencode/skills/playwright/` | `install.sh` |
| deployment/ | Optional | `$HOME/.config/opencode/skills/deployment/` | `install.sh` |
| frontend-ui-ux/ | Optional | `$HOME/.config/opencode/skills/frontend-ui-ux/` | `install.sh` |
| vera-hygiene/ | Optional (Recommended) | `$HOME/.config/opencode/skills/vera-hygiene/` | `install.sh` |
| vera/ | Optional (Recommended) | `$HOME/.config/opencode/skills/vera/` | `vera agent install --client opencode` |

---

## See Also

- [Plugins Documentation](plugins.md) — review-enforcer.ts integration
- [Wisdom Documentation](wisdom.md) — wisdom scripts and usage
- [MANIFEST.md](../MANIFEST.md) — Complete artifact inventory
- `skills/README.md` — Quick reference
