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
- Enforces max 2 review iterations per task; after cycle 2, unresolved CRITICAL findings require RULE/BLOCK/PARK closeout (in-scope fix with recorded ruling / stop for the user / user-accepted residual risk) — never demotion to INFO (fixed 2026-09-09)
- Manages workflow: request → delegate → receive → parse → fix → verify
- Conditional intermediary-output audit (added 2026-09-05, consolidated same day): REVIEW-TASK prompts for data-producing tasks read ≥5 raw outputs per stage and report degenerate patterns (empty outputs, zero-variance scores, duplicated template clauses) as CRITICAL; REVIEW-FIX prompts sweep ALL sibling call sites when a fix belongs to a call-site class (partial-application antidote)

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

### patch-opencode/

**Purpose**: Minimal-fix procedure for patching the live OpenCode binary from the exact release tag that matches the running version.

**Features**:

- Verifies the live OpenCode version before source checkout
- Requires a clean source tree before creating a release-tag fix branch
- Builds with `OPENCODE_VERSION` so patched binaries preserve the live version string
- Covers backup, service stop/start, patch-presence verification, rollback, and PR template caveats
- Enforces evidence-state language for runtime/live verification claims

**Dependencies**: Local OpenCode source checkout at `~/src/opencode`; `bun`; systemd user services when patching the live server surfaces

**Use Case**: Applying a local OpenCode binary patch safely while waiting for upstream merge/release.

**Status**: Optional

**Install Target**: `$HOME/.config/opencode/skills/patch-opencode/`

**Install Method**: `install.sh --skills`

---

### debate/

**Purpose**: Structured adversarial analysis protocol. Provides quick single-agent modes and a primary decision-review protocol where one agent proposes, one critiques, the proposer revises, and a judge panel decides whether to ADOPT, REVISE, REJECT, or ESCALATE.

**Features**:

- Decision-review protocol: block-level thesis tree → critique (strict / generous-steelman / neutral) → revision → judge evaluation
- Decision-action verdicts: ADOPT / REVISE / REJECT / ESCALATE (not winner-picking)
- Binding/advisory judge weights — Analyst is binding by default; Aesthete and Stylist are advisory
- Quick single-agent modes: 1:1 Direct Challenge, Panel Review, Pre-mortem, Red Team, Architecture Adversary
- Three decision-review modes: Architecture Decision, Comparative Analysis, Writing Refinement
- Persist-on-collect rule for all judge/reviewer output
- Retry & recovery protocol with quorum logic

**Dependencies**: None (orchestrates other agents via `task()`)

**Use Case**: Surfacing hidden assumptions, testing argument robustness, making complex architectural decisions, evaluating competing approaches

**Status**: Optional

**Install Target**: `$HOME/.config/opencode/skills/debate/`

**Install Method**: `install.sh --skills`

### computer-use/

**Purpose**: OS-level computer use on the local X11 desktop via the pinned [cua-driver](https://github.com/trycua/cua) 0.20.0 daemon — a skill-embedded MCP (`mcp.cua` in SKILL.md frontmatter) so the 60-tool surface enters agent context ONLY when the skill is invoked (lazy exposure via OMO's `skill_mcp`).

**Features**:

- AT-SPI element rung first (element_token addressing, zero coordinate math), pixel fallback, background/foreground delivery ladder
- Background input is co-work safe: never moves the user's cursor; overlay permanently disabled (caused GNOME Shell freezes on this dual-head, A/B verified 2026-08-17)
- Browser work is OUT OF SCOPE by policy (2026-08-20): agent-browser owns all web tasks, logged-in or not (persistent named sessions for logins). The daemon runs without the existing-profile grant, so cua browser attach is refused by design
- Decision ladder against alternatives: bash > agent-browser (anonymous web) > this skill

**Browser policy**: all web tasks (including logged-in accounts) route to agent-browser; cua browser tools are unused and the existing-profile grant is removed from the daemon unit. Historical attach findings live in wisdom entry `20260818-010629-03d1` and [trycua/cua#3239](https://github.com/trycua/cua/issues/3239) (0.21.0 enables `dom_event` page input — noted upstream, unused here).

**Transport split**: non-image operations use lazy OMO `skill_mcp`; screenshot operations MUST use cua-driver's CLI `screenshot_out_file` and then `look_at`. OMO currently JSON-stringifies skill-MCP results, so inline MCP image blocks would become base64 text and flood the agent's context.

**Upstream tracking**: [#3236 overlay freeze](https://github.com/trycua/cua/issues/3236) · [#3237 coordinate frame](https://github.com/trycua/cua/issues/3237) · [#3238 launch focus](https://github.com/trycua/cua/issues/3238) · [#3239 Linux browser attach/input](https://github.com/trycua/cua/issues/3239)

**Dependencies**: machine-local daemon (NOT in this repo): `~/.local/share/cua-driver/v0.20.0/` binary, systemd user unit `cua-driver.service` (`serve --no-overlay`, unconfined — this is what restores AT-SPI vs snap-confined clients), default socket `~/.cache/cua-driver/cua-driver.sock`, telemetry disabled via `~/.cua-driver/config.json`

**Use Case**: Native GUI apps without APIs, OS dialogs, GUI QA of desktop software — native desktop only, never the browser

**Status**: Optional

**Install Target**: `$HOME/.config/opencode/skills/computer-use/`

**Install Method**: `install.sh --skills`

---

---

## Acceptance-Boundary Skills (2026-08-31)

Four capabilities productizing the operator's recurring workflow patterns (veran corpus analysis, Jul–Aug 2026). All four share one contract — the **acceptance boundary**: they collect evidence, prepare decisions, and stop at explicit decision checkpoints; none of them dispatches, merges, continues, or writes policy without an explicit operator selection.

### postmortem-policy/
Incident→policy ladder: root cause → find the instruction gap in AGENTS.md/skills/wisdom → propose the minimal amendment → apply/revise/drop checkpoint. Severity gate against policy spam; falsifiability requirement on every rule.

**Install Target**: `$HOME/.config/opencode/skills/postmortem-policy/`

**Install Method**: `install.sh --skills`

### handoff-relay/
Handoff emit/resume: versioned `.builder-kit/audit/handoff-*.md` artifacts emitted only at stable boundaries; resume validates against actual repo state (STALE marks), reads cited artifacts, and opens continue/revise/archive before executing. Wraps into `/handoff` and `/resume-from` commands.

**Install Target**: `$HOME/.config/opencode/skills/handoff-relay/`

**Install Method**: `install.sh --skills`

### verify-built/
Stage-1 acceptance verification: plan-vs-diff alignment ledger bound to an immutable digest header; every requirement mapped to evidence or marked GAP/INFERRED; ends at accept/fix-then-recheck/reject plus residual-risk list; a plan with executed work but a missing/incomplete execution record (`## Execution Record`, `Execution baseline:`, `F#` verdict lines) also yields record GAP rows. Stages 2–3 (project-owned empirical QA; acceptance report) documented, not assumed.

**Install Target**: `$HOME/.config/opencode/skills/verify-built/`

**Install Method**: `install.sh --skills`

### inbound-triage/
Selection-gated triage: raw input pasted directly into the session (primary — the operator never touches files) or dropped as optional `.omo/inbox/*.md` → typed items with priority/feature attribution → version-aware dedup registry (supersession, uncertain-dup surfaced) → numbered recommendations; dispatch strictly after operator selection.

**Install Target**: `$HOME/.config/opencode/skills/inbound-triage/`

**Install Method**: `install.sh --skills`

### Review-preset commands
Four visible, editable composition templates in `commands/`: `/design-review` (draft→critique→challenge), `/option-compare` (independent drafts → judge → adversarial check), `/dual-review` (functional + design lanes in parallel, conflicts stated), `/escalate` (binding three-judge panel with dissent and calibration note). All end at operator decisions; none dispatches autonomously.

---

## Dependency Clusters

```
Wisdom System Cluster:
wisdom/ → wisdom-common.sh → wisdom-search.sh, wisdom-write.sh, etc.

Review System Cluster:
atlas-review-handler/ → review-protocol/ (direct dependency)
                    → wisdom/ (reference)

Acceptance-Boundary Cluster (mutual contract, no code dependency):
postmortem-policy/ + handoff-relay/ + verify-built/ + inbound-triage/ → decision checkpoints → operator
```

---

## Installation Summary

| Skill | Status | Install Target | Install Method |
|-------|--------|----------------|----------------|
| wisdom/ | Required | `$HOME/.config/opencode/skills/wisdom/` | `install.sh` |
| patch-tracker/ | Optional | `$HOME/.config/opencode/skills/patch-tracker/` | `install.sh` |
| register-retry-error/ | Optional | `$HOME/.config/opencode/skills/register-retry-error/` | `install.sh` |
| session-id/ | Optional | `$HOME/.config/opencode/skills/session-id/` | `install.sh` |
| postmortem-policy/ | Optional | `$HOME/.config/opencode/skills/postmortem-policy/` | `install.sh` |
| handoff-relay/ | Optional | `$HOME/.config/opencode/skills/handoff-relay/` | `install.sh` |
| verify-built/ | Optional | `$HOME/.config/opencode/skills/verify-built/` | `install.sh` |
| inbound-triage/ | Optional | `$HOME/.config/opencode/skills/inbound-triage/` | `install.sh` |
| atlas-review-handler/ | Required | `$HOME/.config/opencode/skills/atlas-review-handler/` | `install.sh` |
| review-protocol/ | Required | `$HOME/.config/opencode/skills/review-protocol/` | `install.sh` |
| deployment/ | Optional | `$HOME/.config/opencode/skills/deployment/` | `install.sh` |
| update-to-latest/ | Optional | `$HOME/.config/opencode/skills/update-to-latest/` | `install.sh` |
| patch-opencode/ | Optional | `$HOME/.config/opencode/skills/patch-opencode/` | `install.sh` |
| debate/ | Optional | `$HOME/.config/opencode/skills/debate/` | `install.sh` |
| computer-use/ | Optional | `$HOME/.config/opencode/skills/computer-use/` | `install.sh` (needs machine-local cua-driver daemon) |

**Note**: `playwright`, `frontend-ui-ux`, and `github-triage` ship with [OMO upstream](https://github.com/code-yeongyu/oh-my-openagent) and are intentionally NOT vendored here. OMO registers them automatically when `bunx oh-my-openagent install` is run.

---

## Project-Scoped Skills

Besides the installed (user-scoped) skills above, the repo carries skills that load from the project's `.opencode/skill/` directory — OpenCode picks them up automatically for sessions running inside this repository, with no install step.

| Skill | Scope | Location | Purpose |
|-------|------|----------|---------|
| `add-provider/` | Project | `.opencode/skill/add-provider/` (not installed) | Provider/model onboarding checklist + offline reference-integrity audit. MUST-USE when adding or changing models/providers in `configs/opencode/opencode.json` — prevents the six recurring setup failure classes documented in its `references/rca-2026-08-30.md` |

---

## See Also

- [Plugins Documentation](plugins.md) — review-enforcer.ts integration
- [Wisdom Documentation](wisdom.md) — wisdom scripts and usage
- [MANIFEST.md](../MANIFEST.md) — Complete artifact inventory
- `skills/README.md` — Quick reference
