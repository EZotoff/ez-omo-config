# OhMyOpenCode Skills

This directory contains specialized skill modules that extend OpenCode agent capabilities for specific domains and workflows.

## Skills Overview

### wisdom/
Primary runtime memory skill for institutional knowledge. The single source of truth for operational facts, patterns, decisions, and cross-session learnings. All agents should consult Wisdom before inferring facts from code.
- **Dependencies**: None
- **Use Case**: Searching and recording learnings from plan execution; operational knowledge queries

### atlas-review-handler/
Atlas-level review orchestration handler. Processes automated review results from sub-agents, triages findings, delegates critical fixes, and manages the complete review workflow. After review cycle 2, unresolved CRITICAL findings require RULE/BLOCK/PARK closeout — never silent demotion to INFO (2026-09-09).
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

### computer-use/
OS-level computer use on the local X11 desktop via a skill-embedded MCP backed by the pinned cua-driver 0.20.0 systemd daemon. Lazy-exposes the 60-tool surface only when the skill is invoked (OMO `skill_mcp`). AT-SPI element rung first, pixel fallback, background co-work-safe input (overlay disabled — froze GNOME Shell on this dual-head). Native desktop ONLY: all browser work (logged-in or not) belongs to agent-browser; the daemon runs without the existing-profile grant by policy.
- **Dependencies**: machine-local cua-driver daemon (`~/.local/share/cua-driver/v0.20.0`, systemd user unit `cua-driver.service` with `--no-overlay`) — NOT installed by this repo
- **Use Case**: GUI apps without APIs, OS dialogs, desktop GUI QA — never the browser (agent-browser owns all web)

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
Structured adversarial analysis protocol. Quick single-agent modes (challenge, panel, pre-mortem, red team) plus a decision-review protocol where one agent proposes, one critiques, the proposer revises, and a binding/advisory judge panel decides ADOPT/REVISE/REJECT/ESCALATE. All `task()` dispatch prompts carry a `[DEBATE]` marker so the review-enforcer plugin skips them (debate output is analysis, not implementation work).
- **Dependencies**: None
- **Use Case**: Surfacing hidden assumptions, testing argument robustness, making complex architectural decisions
- **Install**: `install.sh --skills`

### reader-report/
Reader-first writing for any deliverable a human reads to understand a result — HTML reports, MD design docs, debate-result summaries, executive briefs, survey dashboards, handoff notes. Writes for a reader who has NOT read the preceding material. Encodes an 8-rule reader contract (lead with the answer, strip process provenance, self-contained, distinguish fact/inference/recommendation, name empty states, end with the reader's action, surfaces consistent incl. PDF), editorial preferences (no AI-speak, subtraction-first concision), channel profiles (chat summary vs rendered report vs decision artifact), and a rendered-report craft section with a desktop-first viewport doctrine (per-section width lanes: evidence up to ~1280px, wide/matrix content up to ~1600px; prose text-block pinned at 62–68ch with widescreen compositions — marginalia, companion rail, modulated flow, wide reading; empty margins are a defect; mobile collapse; five-step QA order) and an opening-region disclosure ladder (executive core = verdict + one-line distillation + next action visible in the first desktop viewport; supplementary receipts one click down in Layer 3), plus styling floor, house patterns, emphasis dial, Read-mode motion budget capped at one earned moment, PDF/mobile/robustness rules, findings-report genre guidance, and lint-then-independent-review enforcement with severity grades and a degraded-run declaration.
- **Dependencies**: None
- **Use Case**: Producing or editing any reader-facing report/summary/brief; loaded by `/debate` at result-synthesis points
- **Install**: `install.sh --skills`

### postmortem-policy/
Incident→policy ladder. After a workflow failure, regression, or repeated agent mistake: root cause → find the instruction gap (AGENTS.md / skills / wisdom) → propose the minimal amendment → stop at an apply/revise/drop checkpoint. Severity gate prevents policy spam; falsifiability requirement states how each rule's failure would be recognized.
- **Dependencies**: wisdom scripts (search/write) when a wisdom entry is the chosen amendment
- **Use Case**: Converting incidents into durable, minimal agent-policy changes without unapproved edits
- **Install**: `install.sh --skills`

### handoff-relay/
Session handoff emit/resume. Emission packages a session's mission, state, and next steps into a versioned `.builder-kit/audit/handoff-*.md` artifact at stable boundaries only (never on raw context-window pressure). Resume validates the artifact against the repo's actual state (STALE marks for moved HEAD), reads cited entry artifacts, and opens a continue/revise/archive decision checkpoint before any execution. Includes a cross-operator variant for other operators' agents.
- **Dependencies**: None; `/handoff` and `/resume-from` commands are thin wrappers
- **Use Case**: Cross-session, cross-operator context relay without copy-paste and without blind continuation
- **Install**: `install.sh --skills`

### verify-built/
Stage-1 acceptance verification: requirements-alignment check between the active plan/spec and the implementation diff. Binds every ledger to an immutable digest header (sha + dirty-state) so post-run changes visibly invalidate it; maps each requirement to commit/file/test evidence or marks GAP/INFERRED; always ends at an accept/fix-then-recheck/reject recommendation plus a residual-risk list. Stages 2 (project-owned empirical QA) and 3 (acceptance report) are documented but not assumed. Also GAP-flags a missing or incomplete plan execution record (`## Execution Record` with `Execution baseline:` and `F#` verdict lines) when the plan shows executed work.
- **Dependencies**: git; an active plan/spec to verify against
- **Use Case**: Replacing "did you actually do it" challenges with a digest-bound evidence ledger
- **Install**: `install.sh --skills`

### inbound-triage/
Selection-gated triage of raw human-channel input pasted directly into the session (primary flow) or dropped as inbox files (optional). Converts pastes into typed items (bug/request/concern/idea/decision) with priority and feature attribution; cross-references against a plain-file registry with version-aware supersession (amended feedback supersedes, uncertain dedup is surfaced, never silenced); presents numbered impact-ranked recommendations and dispatches nothing until the operator selects.
- **Dependencies**: None; per-project `.omo/inbox/` convention
- **Use Case**: WhatsApp/email/PR-comment feedback → decision-ready items with a dedup memory
- **Install**: `install.sh --skills`
