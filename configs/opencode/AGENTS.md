# Global Agent Instructions

These instructions apply to **every OpenCode session on this machine**, layered on top of any project-level `AGENTS.md`. Loaded from `~/.config/opencode/AGENTS.md` (symlinked into `ez-omo-config`).

## Use the `/deployment` skill before binding ports or launching services

Port conflicts span every project on this host. The `/deployment` skill owns the port registry (`~/.sisyphus/ports.json`) and worktree-local allocations (`~/.local/share/opencode/worktree-state/<project>/ports.json`).

**MUST**: Invoke `/deployment` FIRST, before any of:

- Dev servers: `npm run dev`, `yarn dev`, `pnpm dev`, `bun run dev`, `vite`, `next dev`, `nuxt dev`, `ng serve`, `python -m http.server`, `uvicorn`, `gunicorn`, `flask run`, `rails s`, `go run` (with listener), `cargo run` (with listener), `php artisan serve`, `docker run -p`, `docker compose up`, `podman run -p`, `kubectl port-forward`
- Production servers or background services that bind a port
- Integration / e2e tests that spin up services, databases, or brokers
- Choosing or "guessing" a free-looking port for any new service

The skill reserves a port range, allocates the next free port, and records the service. Do not `npm run dev -- --port 3000` (or any equivalent) without going through the skill.

**EXEMPT** (skill not required):

- Pure tests / builds that never bind a port: `pytest`, `go test`, `cargo test`, `tsc --noEmit`, `npm run build`, `npm run lint`
- One-shot scripts, REPLs, file transforms
- Anything that only opens outbound connections

If you are unsure whether the work binds a port, assume it does and invoke the skill.

When searching for code or understanding codebase structure, use this vanilla discovery protocol:

| Task Type | Primary Tool | Notes |
|-----------|--------------|-------|
| Conceptual/codebase discovery — "how does X work", "where is Y logic" | `codegraph_explore` | Use first when available; it returns relevant source and relationships in one call. |
| Symbol precision — goto definition, references, rename safety | LSP tools | Use `lsp_goto_definition`, `lsp_find_references`, and `lsp_rename` for exact language-server results. |
| Exact text/regex — identifiers, imports, TODOs, config strings | `grep` / `rg` | Use for literal or regex search, especially outside indexed code. |
| File discovery — list files by pattern | `glob` | Use for path patterns such as `**/*.test.ts` or `docs/**/*.md`. |

Prefer codegraph/LSP facts over memory. If a tool is unavailable or returns no useful result, fall back to the next appropriate vanilla tool without bootstrapping any repo-local search service.

## Before Modifying Unknown Systems

Before changing code or config in a system you didn't build in this session,
verify the one assumption most likely to be wrong. Read the registration path,
trace the call graph, or run a probe — whichever is fastest and could prove
your model incorrect. Skip this only when being wrong costs less than checking.

When a fix doesn't work, your model of the system is the suspect — not just
the fix. Before trying a second approach, re-read the source that governs
the behavior you're trying to change.

## Long-running job monitoring (2026-09-18 lesson)

Never launch a long-running batch (benchmarks, migrations, training, bulk
operations) and walk away. The launching agent monitors it actively: first
probe ~2 minutes in (catches crash-at-the-end bugs while only one unit of work
is lost), then probes with exponential backoff (30s → 60s → 120s → 240s, cap
~8 min), one fast probe per tool call — never sleep >60s inside a call. Any
failure (non-zero exit, missing output artifact, repeated empty replies) is
diagnosed and fixed immediately, not at the next status ping. Batches must
abort on repeated identical failures (circuit breaker); the agent's monitoring
is what makes the diagnosis arrive in minutes. This rule was added after an
operator had to request it three times while ~$2 of compute and ~6 hours were
invalidated by failures that ran to completion unobserved.

Campaigns expected to outlive a single tool call MUST run through opencode durable-run or the bench-campaign launcher, preserve full per-case stdout/stderr, and record the unit/run ID and monitoring owner — detachment transfers process lifetime, not responsibility.

### Benchmark campaign preflight

1. Probe every primary AND fallback model with one tiny call before any case or delegated reader starts — validate identity, endpoint family, credential source, usability, and quota; a reachable endpoint alone is not sufficient.
2. Treat quota reset timestamps as upper bounds — probe, don't wait.
3. Declare an admission budget: case count plus operator-set headroom.
4. Forbid substring `pkill`/`pgrep` — require owned unit/PID metadata.

## Context discipline for small-context models (2026-09-05 lesson)

A sub-agent on the local Qwen rig died mid-task from ONE tool output: unscoped `git status` in a repo with ~4,000 untracked files emitted more tokens than the model's whole 64k window. Rules for any session that may run on a context-limited model:

- **Never run unscoped `git status`, `git diff`, or `find` in a repo you haven't inspected first.** Scope to paths: `git status --porcelain -- <path>`, `git diff -- <file>`, `ls <dir>`. Check repo health cheaply first: `git status --porcelain | wc -l`.
- Prefer `git ls-files`, `git log --oneline -5`, and glob tools over raw listings.
- Tool outputs are capped globally (`tool_output.max_lines/max_bytes`) — when a result arrives truncated, narrow the query instead of repeating it.


## Plan-execution records (durable execution baseline + final-wave verdicts)

When you begin executing a work plan (a `/start-work` session — BEFORE the first task is dispatched), append this block to the END of the plan document being executed (normally `.omo/plans/*.md` — the plan you read before delegating tasks):

    ## Execution Record

    Execution baseline: <full HEAD SHA of the execution worktree — or the repo, if no worktree>

Create the section only if it does not exist; if an `Execution baseline:` line is already present (resumed execution), never overwrite or duplicate it.

When executing a plan with a Final Verification Wave: as you record each reviewer's verdict and check their F-box in the plan document, append `F#<n>: APPROVE|REJECT — <one-clause evidence>` to the plan's `## Execution Record` in the same editing pass — one line per reviewer, each reviewer's LATEST verdict, pointer-style evidence (command + exit code, evidence path, or file:line). The `#` is LITERAL — write `F#1:`, `F#2:`, not `F1:`, `F2:` — and the lines go INSIDE the `## Execution Record` section, never past later sections at document EOF. Example lines: `F#1: APPROVE — bash tests/run_all.sh exit 0`, `F#2: REJECT — missing evidence .sisyphus/evidence/x.md`. Reviewer subagents stay read-only — YOU (the orchestrator) write these lines. These lines are the durable record of execution: `boulder.json` is deleted at completion and records nothing; the plan document survives.

## Claude CLI auth model — subscription OAuth only, NO API key

This machine uses the **Claude Pro/Max subscription** (OAuth credentials in `~/.claude/.credentials.json`). There is no `ANTHROPIC_API_KEY` and one must **not** be provisioned.

**Consequences for any `claude` / `claude -p` invocation or wrapper:**

- **NEVER pass `--bare`.** It ignores OAuth/keychain and requires `ANTHROPIC_API_KEY` (or `apiKeyHelper` via `--settings`), which does not exist here. The invocation will fail auth.
- **NEVER set `ANTHROPIC_API_KEY=...`** in wrapper scripts, env files, MCP server configs, or skill instructions to "make it work". That routes through pay-per-token billing instead of the subscription and breaks the subscription commitment.
- The non-bare path is correct and intended: OAuth credentials are read automatically from `~/.claude/.credentials.json`. Hooks, `CLAUDE.md`, and skills auto-load — this is desired, not bleed to mitigate.
- To scope an invocation, use `--allowedTools`, `--add-dir`, `--permission-mode`, `--model`, `--system-prompt` / `--append-system-prompt`, `--max-turns`. **Not** `--bare`.

If a tool, plugin, skill, or proposal requires `--bare` or `ANTHROPIC_API_KEY`, it is wrong for this machine; redesign it to use the OAuth path.

Reference: wisdom entry `20260729-<id>` (search wisdom with `~/.sisyphus/scripts/wisdom-search.sh "claude subscription bare"`).

## Session-safe OpenCode server restarts (2026-09-16)

Two `opencode serve` instances run as systemd user services. Restarting either kills in-flight turns. **Never bare-restart when sessions may be active** — use the continuation script so active top-level sessions are snapshotted and resumed with a continuation prompt:

| Service | URL | Auth env file |
|---------|-----|---------------|
| `opencode.service` (headless) | `http://127.0.0.1:3021` | `~/.config/opencode/serve.env` |
| `opencode-interactive.service` (desktop TUI attach / OC Beacon) | `http://127.0.0.1:3030` | `~/.config/opencode/serve-interactive.env` |

```bash
# Default flags target opencode.service (dry-run: snapshot only, no restart):
~/ez-omo-config/scripts/restart-with-continuation.sh

# Full restart + resume, interactive server:
PW=$(grep ^OPENCODE_SERVER_PASSWORD= ~/.config/opencode/serve-interactive.env | cut -d= -f2-)
systemd-run --user --unit=restart-cont-$(date +%s) bash -c \
  '~/ez-omo-config/scripts/restart-with-continuation.sh --restart \\
     --service opencode-interactive.service --url http://127.0.0.1:3030 \\
     --password "$PW" >> ~/.local/share/opencode/restart-continuations/restart.log 2>&1'
```

- **Plain invocation is a dry-run** (snapshot only). Add `--restart` to actually restart and resume; `--resume-only --state-file <snapshot.json>` re-injects from a saved snapshot.
- **Continuation is the DEFAULT for all restarts**: both units carry systemd drop-ins (`systemd/user/*.service.d/continuation.conf`) — `ExecStop=` snapshots busy sessions on every stop/restart (keeper restarts included) and `ExecStartPost=` resumes snapshots younger than 1h, then marks them consumed. A plain `systemctl --user restart` is therefore session-safe with no extra flags.
- **Opt-out is explicit**: `restart-with-continuation.sh --bare-restart [--service <unit> --url <url>]` sets a bypass flag the hooks respect, restarting without snapshot/resume. Use only when continuation is genuinely unwanted.
- **Detached launch is mandatory when the calling session rides the target server**: the bash tool subprocess is a child of the server process, and the systemd cgroup kill during restart terminates it mid-run (leaving the server stopped). `systemd-run --user` puts the script in its own cgroup.
- Snapshot mechanics: `/session` and `/session/status` are **instance-scoped** (the global list misses other directories; status needs `?directory=`), so the script discovers recently-active directories from the shared session DB (read-only sqlite) and queries each. `busy` and `retry` sessions are captured; `retry` is deliberate — a restart wipes in-memory retry schedules, so those sessions need the kick. Injection is `POST /session/:id/prompt_async`.
- Snapshots and logs: `~/.local/share/opencode/restart-continuations/`. Never echo the server passwords.
- Hook activity log: `~/.local/share/opencode/restart-continuations/hooks.log`. After any restart, verify: `ps -eo pid,lstart,args | grep 'opencode serve'` shows a fresh start time.


## Protected runtime directories (2026-09-18 incident)

MANIFEST-tracked runtime installs in `$HOME` are **live infrastructure, never cleanup candidates** — regardless of how "stale" a versioned-looking directory name appears. Notably:

- `~/oh-my-openagent-v4.19.2` — canonical OMO fork runtime, loaded by `opencode.json#plugin` via a `file://` entry. Deleting it silently disables the OMO plugin.
- `~/.opencode/bin/` — the patched live OpenCode binary.

Any session doing disk cleanup, deduplication, or "stale version" sweeps MUST:

1. Treat every `file://` path in `opencode.json#plugin` and every MANIFEST External Artifact row as protected — exclude from deletion candidates.
2. Report such directories to the operator as review candidates instead of deleting them.
3. Never delete a directory whose removal would break a live config reference. If storage is the goal, propose the deletion and wait for explicit operator approval.

Incident reference: 2026-09-18, a benchmark-disk-cleanup session deleted `~/oh-my-openagent-v4.19.2`, silently unloading the OMO plugin and destroying unpushed fork commits.

## Portable Supervisor prototype — cross-project awareness (2026-09-18)

Three repos form one product (the OC Beacon Portable Supervisor prototype). Know which repo you are in and which seam you touch; the binding contract is [`~/ez-omo-config/docs/portable-supervisor-contract.md`](file:///home/ezotoff/ez-omo-config/docs/portable-supervisor-contract.md):

- **omo-pulse** (`~/AI_projects/ez-omo-dash`) — visual supervisor surface (attention queue, session cards, remote UI, deep-links). Central dev session for prototype work runs here.
- **voice-bridge / Vox** (`~/AI_projects/voice-bridge`) — voice brain: Gemini Live service on `127.0.0.1:18220`, tools, interrupts, confirmation-gated mutations.
- **ez-omo-config** — config store + contract home; contract changes land here FIRST, then per-repo implementation sessions.
- Run **one session per repo** (AGENTS.md/codegraph/tests are repo-scoped); cross-repo changes go contract → bridge → dash in that order.

Supervisory data contracts: escalations come from the supervisor ledger (`~/.local/state/opencode-supervisor/ledger.jsonl`, `TICK_DECIDED`+`ESCALATE`); never parse `[Supervisor]` console sessions for reading.

## Platform support

This config installs on **Linux (native)**, **macOS (native, Homebrew Bash 4.3+ required — stock `/bin/bash` is 3.2 and cannot run the wisdom scripts)**, and **Windows (via WSL only)**. OpenCode resolves config paths against `os.homedir()` on every OS, so install targets (`~/.config/opencode/`, `~/.opencode/`, `~/.local/share/opencode/`, `~/.sisyphus/`) never need platform-specific remapping. On macOS run `brew install bash bun jq python` first. On Windows run the installer **inside WSL** — Git Bash, Cygwin, and native PowerShell are not supported and `install.sh` will exit with a WSL setup link.
