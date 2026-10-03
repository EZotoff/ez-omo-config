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

## Before upstream contributions (PRs/issues to external repos)

Before creating any PR or issue on a repo you didn't create in this session:
1. Read the repo's PR/issue templates and CONTRIBUTING.md first; follow them exactly. Some repos auto-close non-compliant PRs within hours (anomalyco/opencode: 2h).
2. Run `~/.sisyphus/scripts/wisdom-search.sh "<repo owner/name>"` and act on any gotchas — prior attempts may exist that you don't know about.
3. If a prior PR/issue of ours on this repo was bot-closed, say so in the new one.

## Before Modifying Unknown Systems

Before changing code or config in a system you didn't build in this session,
verify the one assumption most likely to be wrong. Read the registration path,
trace the call graph, or run a probe — whichever is fastest and could prove
your model incorrect. Skip this only when being wrong costs less than checking.

When a fix doesn't work, your model of the system is the suspect — not just
the fix. Before trying a second approach, re-read the source that governs
the behavior you're trying to change.

## Long-running job monitoring (2026-09-18 lesson; rewritten 2026-09-28 after the unbound-probe audit; 2026-10-02 backoff made escalation-first + mechanical)

**A turn-based agent has no clock. Ending your turn cancels every probe you announced.**
Nothing re-kicks an idle session — no timer, no scheduler. "I'll check again in ~60s" as a
parting sentence is a promise to do nothing. Monitoring a long-running batch (benchmarks,
migrations, training, bulk operations) is therefore only legal in one of two forms:

1. **Hold the turn**: stay in-turn with an **escalating** probe schedule — NEVER repeat
the same interval; every probe must wait longer than the last (first probe ~2 min into
the job, then roughly 30s → 60s → 120s → 240s, cap ~8 min). Keep each individual
`sleep` ≤60s per tool call — chunk longer waits into repeated ≤60s sleeps inside one
call and pass a raised tool timeout. Each wait must produce observable progress — a
status check, a log read, a decision. Never one giant sleep; never a sleep with no probe
attached. Where the repo provides a stateful backoff helper (e.g. `bin/watch-probe.sh`
in ez-omo-bench), prefer it over hand-rolled sleeps — model memory does not keep a
probe counter, scripts do.
2. **Arm a wake trigger**: delegate monitoring to a `run_in_background` subagent that
holds its OWN turn, sleep-loop-probes the job, and returns the verdict — its completion
notification genuinely wakes you. The watcher must emit tool activity at least every
10–15 minutes (background sessions die on the ~30-minute inactivity window) and the
watched job must be idempotent/re-dispatchable via a STATE file so a killed watcher can
be relaunched losslessly.

What is ILLEGAL: ending the turn on "I'll probe/monitor/track" without a wake trigger.
Fixed-interval polling is the second violation: if your last two probes waited the same
time, the schedule is broken — escalate. The first-probe timing still applies (~2 minutes
into the job, catching crash-at-the-end bugs while only one unit of work is lost). Any failure (non-zero exit, missing output artifact, repeated
empty replies) is diagnosed and fixed immediately, not at the next status ping. Batches
must abort on repeated identical failures (circuit breaker). History: the 2026-09-18
incident (operator requested monitoring three times while ~$2 of compute and ~6 hours
were invalidated by failures that ran to completion unobserved) and the 2026-09-26/28
audit (agents in ez-omo-bench/veran ended turns on probe promises that never fired;
the operator returned with the outcome every time).

Known duplicate nudges (2026-10-02): if a `[BACKGROUND TASK COMPLETED]` nudge arrives and `background_output` reports no new output, treat it as a known duplicate of an already-collected result and stop — do not re-do the completed work. (OMO parent-wake force-dispatch tail; measured ~1% of delivered wakes — 2026-10-02 wake-redundancy decision, Branch A.)


**No unbound promises (2026-09-23 lesson).** Commit to future action only after arming a wake trigger and recording a durable handle: an owned background task with a deadline and task ID, or a continuation hook owning this session plus its state file. An operator handoff ends responsibility, not a trigger. If arming can't be verified, say "needs your input" and give current state. Promises are bounded: "observed until <deadline> via <handle>". On any wake, reconcile from durable state before acting.
### Benchmark campaign preflight

1. Probe every primary AND fallback model with one tiny call before any case or delegated reader starts — validate identity, endpoint family, credential source, usability, and quota; a reachable endpoint alone is not sufficient.
2. Treat quota reset timestamps as upper bounds — probe, don't wait.
3. Declare an admission budget: case count plus operator-set headroom.
4. Forbid substring `pkill`/`pgrep` — require owned unit/PID metadata.
5. Check provider quota headroom before launching (and when investigating a possible rate-limit failure): run `~/.sisyphus/scripts/quotas.sh` (Z.AI, ChatGPT, Ollama Cloud, Kimi, OpenCode Go; `--json` for raw payload). Treat unreachable, errored, or STALE entries as unknown — never infer headroom. If you lack shell access, ask a shell-capable parent to run it and report the output.

## Context discipline for small-context models (2026-09-05 lesson)

A sub-agent on the local Qwen rig died mid-task from ONE tool output: unscoped `git status` in a repo with ~4,000 untracked files emitted more tokens than the model's whole 64k window. Rules for any session that may run on a context-limited model:

- **Never run unscoped `git status`, `git diff`, or `find` in a repo you haven't inspected first.** Scope to paths: `git status --porcelain -- <path>`, `git diff -- <file>`, `ls <dir>`. Check repo health cheaply first: `git status --porcelain | wc -l`.
- Prefer `git ls-files`, `git log --oneline -5`, and glob tools over raw listings.
- Tool outputs are capped globally (`tool_output.max_lines/max_bytes`) — when a result arrives truncated, narrow the query instead of repeating it.

## Session attachment hygiene

Parentless OpenCode sessions appear in the operator's session picker (subagent/task sessions are parented and hidden). Attach a session to a real project directory only when its transcript is productive work worth finding again: implementation, investigation, review, planning, or other work with future reference value.

Throwaway invocations MUST run in a dedicated scratch directory instead. This includes model/provider identity or quota probes, load-balancer checks, one-word reply tests ("Reply with exactly: OK", "say ok"), harness/compliance checks, smoke tests, and any `opencode run` invocation whose transcript has no future value. Prefer:

    scratch="$(mktemp -d /tmp/opencode/probe.XXXXXX)"
    opencode run --dir "$scratch" ...

`--dir` is preferable to a shell `cd`: it explicitly controls instance/project attachment (relative file arguments then resolve against that directory, so use absolute paths for project files). `--title` alone is not isolation — it only renames the session. When using `--attach`, `--dir` names a directory on the server host, so create the scratch directory there. Worktrees are real project directories: productive work belongs there, but throwaway probes launched from a worktree still belong in scratch.

The same rule applies to scripts and direct API clients: throwaway sessions must use a scratch-directory instance (or be created as children of an existing parent session). **Do not send productive work to /tmp** — sessions with future reference value belong in their project directory. Incidents: 2026-09-19 regression-test spam (13 sessions in ez-omo-config), 2026-09-19/20 probe spam (~15 "PROBE-OK"/"LB_OK"/one-word-reply sessions in ez-omo-bench and ez-omo-config).


## Plan-execution records (durable execution baseline + final-wave verdicts)

When you begin executing a work plan (a `/start-work` session — BEFORE the first task is dispatched), append this block to the END of the plan document being executed (normally `.omo/plans/*.md` — the plan you read before delegating tasks):

    ## Execution Record

    Execution baseline: <full HEAD SHA of the execution worktree — or the repo, if no worktree>

Create the section only if it does not exist; if an `Execution baseline:` line is already present (resumed execution), never overwrite or duplicate it.

When executing a plan with a Final Verification Wave: as you record each reviewer's verdict and check their F-box in the plan document, append `F#<n>: APPROVE|REJECT — <one-clause evidence>` to the plan's `## Execution Record` in the same editing pass — one line per reviewer, each reviewer's LATEST verdict, pointer-style evidence (command + exit code, evidence path, or file:line). The `#` is LITERAL — write `F#1:`, `F#2:`, not `F1:`, `F2:` — and the lines go INSIDE the `## Execution Record` section, never past later sections at document EOF. Example lines: `F#1: APPROVE — bash tests/run_all.sh exit 0`, `F#2: REJECT — missing evidence .sisyphus/evidence/x.md`. Reviewer subagents stay read-only — YOU (the orchestrator) write these lines. These lines are the durable record of execution: `boulder.json` is deleted at completion and records nothing; the plan document survives.

## Session-safe OpenCode server restarts (2026-09-16)

Two `opencode serve` instances run as systemd user services. Restarting either kills in-flight turns. **Never bare-restart when sessions may be active** — use the continuation script so active top-level sessions are snapshotted and resumed with a continuation prompt:

| Service | URL | Auth env file |
|---------|-----|---------------|
| `opencode.service` (headless) | `http://127.0.0.1:3021` | `~/.config/opencode/serve.env` |
| `opencode-interactive.service` (desktop TUI attach / OC Beacon) | `http://127.0.0.1:3030` | `~/.config/opencode/serve-interactive.env` |

```bash
# Default flags target opencode.service (dry-run: snapshot only, no restart):
~/ez-omo-config/scripts/restart-with-continuation.sh

# Full restart + resume, interactive server (auth env file auto-selected from
# --service; no password on any command line):
systemd-run --user --unit=restart-cont-$(date +%s) bash -c \
  '~/ez-omo-config/scripts/restart-with-continuation.sh --restart \\
     --service opencode-interactive.service --url http://127.0.0.1:3030 \\
     >> ~/.local/share/opencode/restart-continuations/restart.log 2>&1'
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

## Measurement-subject fidelity (2026-10-02 bonsai-perf postmortem)

When a task names a specific artifact/config/model as the subject of measurement or
optimization, substituting an adjacent one (different quant, engine format, config,
or comparison conditions) is a DECISION FORK, not a footnote: surface it to the
operator at discovery time with options and a recommendation BEFORE proceeding.
The same applies to any estimate offered where a measurement was required, and to
any comparison table mixing conditions (spec-decoding on/off, decode vs e2e) —
label conditions or don't pool. Recording a substitution as a "deviation" and
continuing is the exact failure this rule prohibits.
