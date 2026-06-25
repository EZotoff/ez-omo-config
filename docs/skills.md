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

`atlas-review-handler/` and `review-protocol/` are **referenced external skills**. They are **not** the source of mandatory Live Deployment Verification Gate enforcement, unless they are later versioned in this repo. The core live gate is enforced in tracked repo surfaces: `AGENTS.md` (evidence-state taxonomy), `plugins/review-enforcer.ts` (runtime gate), and `scripts/verify-live-deployment.sh` (canonical verifier). Skills may reference the gate, but the authoritative enforcement lives in the repo's tracked files.

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

Like `atlas-review-handler/`, this skill is a **referenced external skill** and participates in review workflows but does **not** enforce the Live Deployment Verification Gate, unless it is later versioned in this repo. The gate is enforced by tracked repo files: `AGENTS.md`, `plugins/review-enforcer.ts`, and `scripts/verify-live-deployment.sh`.

**Use Case**: Conducting code reviews of uncommitted or recent changes

**Status**: Required

**Install Target**: `$HOME/.config/opencode/skills/review-protocol/`

---

## Optional Skills

These skills provide domain-specific enhancements and can be installed based on project needs.

### patch-tracker/

**Purpose**: Patch registry operator skill. Tracks custom patches to external dependencies through a full CRUD lifecycle with post-update verification.

**Features**:

- Register patches with required frontmatter (patch_id, dependency, target_file, verification_pattern, etc.)
- Five required body sections per entry (Problem, Patch Description, Verification, Reapply Instructions, Durable Alternative)
- READ / UPDATE / DEPRECATE / VERIFY workflows
- "Durable alternative nudge" — refuses to register a patch if a plugin, hook, or config option would solve the problem
- Detects stale patches after dependency updates and surfaces reapply instructions

**Dependencies**: `.sisyphus/patches/TEMPLATE.md` (patch entry template)

**Use Case**: Preventing silent patch debt — patches that get lost on dependency updates with no record

**Status**: Optional

**Install Target**: `$HOME/.config/opencode/skills/patch-tracker/`

---

### register-retry-error/

**Purpose**: Error registry operator skill. Registers new retryable error patterns in the centralized retry-errors registry.

**Features**:

- Validates regex patterns, kebab-case IDs, and backoff length constraints
- Prevents duplicate IDs and duplicate patterns
- Atomic write protocol (temp file + rename) to prevent JSON corruption
- Used alongside the `provider-connect-retry.mjs` plugin and `retry-errors.json` config

**Dependencies**: `~/.config/opencode/retry-errors.json` (the registry)

**Use Case**: Adding new retryable error patterns to the runtime retry plugin

**Status**: Optional

**Install Target**: `$HOME/.config/opencode/skills/register-retry-error/`

---

### session-id/

**Purpose**: Minimal utility skill that copies the current OpenCode session ID to the clipboard.

**Features**:

- Single one-liner workflow using `opencode session list -n 1 --format json` + `jq` + `xclip`
- Triggers on `/session-id`
- Mirrors the behavior of the `session-id.ts` plugin (which intercepts the slash command without an LLM round-trip)

**Dependencies**: `opencode` CLI, `jq`, `xclip`

**Use Case**: Quick clipboard copy of the current session ID for sharing or bookmarking

**Status**: Optional

**Install Target**: `$HOME/.config/opencode/skills/session-id/`

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

### update-to-latest/

**Purpose**: Safe OpenCode/OMO update pipeline with explicit human approval gate, patch-tracker integration, rollback capability, and evidence-state claim discipline.

**Features**:

- 13-phase guided operational pipeline for analyzing and executing updates
- Explicit human approval gate before any update commands run
- Patch registry review and overlap detection with upstream changes
- Timestamped backup bundle creation with restore commands
- Adaptive regression testing: Light, Standard, or Deep suites
- Evidence-state claim discipline using exact AGENTS.md taxonomy
- Rollback policy with automatic restore on critical test failures
- Patch lifecycle classifications: unaffected, reapplied-cleanly, conflicted, obsolete-upstreamed, obsolete-replaced-by-config-or-plugin, missing-target, needs-redesign

**Dependencies**: `patch-tracker` skill (referenced)

**Use Case**: Analyzing whether to update OpenCode or OMO, producing a go/no-go recommendation, and executing updates safely with full rollback capability

**Status**: Optional

**Install Target**: `$HOME/.config/opencode/skills/update-to-latest/`

**Install Method**: `install.sh --skills`

---

### debate/

**Purpose**: Structured adversarial debate protocol for rigorous technical analysis. Orchestrates multi-agent debates with formal rules, evidence tracking, and consensus building.

**Features**:

- 5-segment debate protocol (S1-S5): Core Thesis → Evidence & Reasoning → Steel-Man & Counter → Implications → Cross-Examination
- 6 distinct modes for different analytical needs
- Configurable judge panels with scoring rubrics
- Deterministic label blinding (Alpha/Beta only — judges never see agent names)
- Evidence tracking with formal citation requirements
- Consensus building through adversarial examination

**Dependencies**: None (orchestrates other agents via `task()`)

**Use Case**: Surfacing hidden assumptions, testing argument robustness, making complex architectural decisions, evaluating competing approaches

**Status**: Optional

**Install Target**: `$HOME/.config/opencode/skills/debate/`

**Install Method**: `install.sh --skills`

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
| patch-tracker/ | Optional | `$HOME/.config/opencode/skills/patch-tracker/` | `install.sh` |
| register-retry-error/ | Optional | `$HOME/.config/opencode/skills/register-retry-error/` | `install.sh` |
| session-id/ | Optional | `$HOME/.config/opencode/skills/session-id/` | `install.sh` |
| atlas-review-handler/ | Required | `$HOME/.config/opencode/skills/atlas-review-handler/` | `install.sh` |
| review-protocol/ | Required | `$HOME/.config/opencode/skills/review-protocol/` | `install.sh` |
| deployment/ | Optional | `$HOME/.config/opencode/skills/deployment/` | `install.sh` |
| update-to-latest/ | Optional | `$HOME/.config/opencode/skills/update-to-latest/` | `install.sh` |
| debate/ | Optional | `$HOME/.config/opencode/skills/debate/` | `install.sh` |

**Note**: `playwright`, `frontend-ui-ux`, and `github-triage` ship with [OMO upstream](https://github.com/code-yeongyu/oh-my-openagent) and are intentionally NOT vendored here. OMO registers them automatically when `bunx oh-my-openagent install` is run.

---

## See Also

- [Plugins Documentation](plugins.md) — review-enforcer.ts integration
- [Wisdom Documentation](wisdom.md) — wisdom scripts and usage
- [MANIFEST.md](../MANIFEST.md) — Complete artifact inventory
- `skills/README.md` — Quick reference
