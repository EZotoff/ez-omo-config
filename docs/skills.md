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

| Skill | Status | Install Target |
|-------|--------|----------------|
| wisdom/ | Required | `$HOME/.config/opencode/skills/wisdom/` |
| atlas-review-handler/ | Required | `$HOME/.config/opencode/skills/atlas-review-handler/` |
| review-protocol/ | Required | `$HOME/.config/opencode/skills/review-protocol/` |
| playwright/ | Optional | `$HOME/.config/opencode/skills/playwright/` |
| deployment/ | Optional | `$HOME/.config/opencode/skills/deployment/` |
| frontend-ui-ux/ | Optional | `$HOME/.config/opencode/skills/frontend-ui-ux/` |

---

## See Also

- [Plugins Documentation](plugins.md) — review-enforcer.ts integration
- [Wisdom Documentation](wisdom.md) — wisdom scripts and usage
- [MANIFEST.md](../MANIFEST.md) — Complete artifact inventory
- `skills/README.md` — Quick reference
