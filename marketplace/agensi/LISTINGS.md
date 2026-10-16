# Agensi Pilot — Listing Package

Two skills packaged for the Agensi.io marketplace (pilot, 2026-10-16).
Strategy: **debate = free** (discovery funnel — Agensi's own data shows free
skills drive all marketplace traffic), **typographic-writing = paid**
(niche but valuable; the shipped lint script is the tangible differentiator).

## Upload-ready artifacts

| Skill | Zip | Price | Category (agensi.io) |
|---|---|---|---|
| debate | `debate-skill.zip` | **Free** | Research & Analysis (or Agents & Orchestration) |
| typographic-writing | `typographic-writing.zip` | **$9** | Writing & Content |

## Listing: debate (FREE)

**Name**: Structured Debate & Decision Review

**Tagline**: Turn any decision into proposal → critique → revision → judged verdict (ADOPT/REVISE/REJECT/ESCALATE).

**Description**:

Your agent is agreeable. Ask it "is this a good idea?" and it will usually say yes. This skill replaces yes-man reasoning with structured adversarial analysis.

Two layers:

- **Quick modes** (one agent, minutes): 1:1 direct challenge, parallel panel review, pre-mortem ("the project failed 6 months from now — what happened?"), red team (maximum-adversary security analysis), and a quick architecture propose-attack-revise exchange.
- **Decision Review protocol** (full run): one agent proposes a thesis decomposed into independently-scoreable blocks, a critic attacks each block under an explicit stance (strict / generous-steelman / neutral), the proposer revises, and a 3–5 judge panel scores the result. Verdicts are decision actions — ADOPT, REVISE, REJECT, ESCALATE — derived mechanically from block scores, never from which argument sounded best.

Includes production-grade mechanics most debate prompts skip: persist-every-judge-output-before-parsing, quorum rules, retry/recovery protocol, a crash-recovery state file so a restart never fabricates lost stages, a binding-vs-advisory judge weight system, and reader-first result delivery (no insider-baseball score dumps in the summary).

Works on any agent that can dispatch subagents or separate model calls (Claude Code, Codex CLI, OpenCode, Gemini CLI, Cursor); degrades gracefully to single-agent mode otherwise.

**Use cases**: architecture decisions, vendor/tool comparisons, plan stress-tests, writing refinement with judges, security reviews.

**Tags**: `decision-making`, `architecture`, `red-team`, `critical-thinking`, `code-review`, `agents`, `adversarial`, `planning`

## Listing: typographic-writing (PAID — $9)

**Name**: Typographic Writing — Prose That Reads Authored

**Tagline**: Cadence, punctuation discipline, and anti-AI-slop mechanics for drafting, rewriting, and editing — with a working prose linter included.

**Description**:

The difference between text that reads authored and text that reads generated is not vibes. It is mechanics: sentence-length variation, punctuation that expresses real syntactic relations, paragraphs with one job each, and the discipline to delete the patterns models default to.

This skill encodes those mechanics as an executable method:

- **Method**: establish the reading situation → find the information spine → draft for meaning, then tune rhythm.
- **Punctuation as notation**: a decision table for every mark, with an em-dash discipline policy and a strict zero-em-dash profile you can pin per request.
- **Anti-slop mannerisms list**: throat-clearing, "delve into", relentless three-item lists, false intimacy, recap endings — rewrite rules, not a banned-word list.
- **Six medium profiles**: research/technical, business/executive, marketing/editorial, presentation, UI copy, general explanatory.
- **Three-scale cadence check**: sentence, paragraph, document — run before finalizing any draft.

**Ships with a working linter** (`checks/check-prose.mjs`, Node.js, zero dependencies): flags pseudo-dashes and slop patterns, supports the zero-em-dash profile, preserves quotes and code blocks verbatim, exit codes for CI use.

For anyone whose agent writes: reports, docs, newsletters, landing pages, slide copy, emails.

**Use cases**: drafting, rewriting, editing, de-slopping AI text, style enforcement.

**Tags**: `writing`, `editing`, `copywriting`, `documentation`, `prose`, `style`, `content`, `communication`

## Your upload steps (~10–15 min)

1. Sign up at https://www.agensi.io (needs an email you control).
2. Connect a payout method: Stripe Connect (bank payout, KYC) or USDC via Zoneless. Required before the paid skill goes live; the free one needs it too for later paid listing.
3. Creator Dashboard → "Submit a Skill" → upload `debate-skill.zip`, paste the free listing above, category Research & Analysis, tags as listed, price Free.
4. Submit `typographic-writing.zip` with its listing, price **$9** (one-time).
5. Review is 24–48h (automated 8-point scan + human). Respond to any reviewer questions by email.

## Post-listing checklist

- [ ] Both listings live and rendering correctly (check via /skills search).
- [ ] Install debate via MCP or one-liner into a vanilla Claude Code and run one pre-mortem — confirm it works outside our stack.
- [ ] Test the paid skill's hosted `run_skill` output quality once live.
- [ ] Set a calendar reminder ~2 weeks out: check installs/sales; decide continue/kill per the pilot criteria (effort already sunk is ~1 day; kill if <5 installs and <2 sales by then).
