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

## Context discipline for small-context models (2026-09-05 lesson)

A sub-agent on the local Qwen rig died mid-task from ONE tool output: unscoped `git status` in a repo with ~4,000 untracked files emitted more tokens than the model's whole 64k window. Rules for any session that may run on a context-limited model:

- **Never run unscoped `git status`, `git diff`, or `find` in a repo you haven't inspected first.** Scope to paths: `git status --porcelain -- <path>`, `git diff -- <file>`, `ls <dir>`. Check repo health cheaply first: `git status --porcelain | wc -l`.
- Prefer `git ls-files`, `git log --oneline -5`, and glob tools over raw listings.
- Tool outputs are capped globally (`tool_output.max_lines/max_bytes`) — when a result arrives truncated, narrow the query instead of repeating it.


## Claude CLI auth model — subscription OAuth only, NO API key

This machine uses the **Claude Pro/Max subscription** (OAuth credentials in `~/.claude/.credentials.json`). There is no `ANTHROPIC_API_KEY` and one must **not** be provisioned.

**Consequences for any `claude` / `claude -p` invocation or wrapper:**

- **NEVER pass `--bare`.** It ignores OAuth/keychain and requires `ANTHROPIC_API_KEY` (or `apiKeyHelper` via `--settings`), which does not exist here. The invocation will fail auth.
- **NEVER set `ANTHROPIC_API_KEY=...`** in wrapper scripts, env files, MCP server configs, or skill instructions to "make it work". That routes through pay-per-token billing instead of the subscription and breaks the subscription commitment.
- The non-bare path is correct and intended: OAuth credentials are read automatically from `~/.claude/.credentials.json`. Hooks, `CLAUDE.md`, and skills auto-load — this is desired, not bleed to mitigate.
- To scope an invocation, use `--allowedTools`, `--add-dir`, `--permission-mode`, `--model`, `--system-prompt` / `--append-system-prompt`, `--max-turns`. **Not** `--bare`.

If a tool, plugin, skill, or proposal requires `--bare` or `ANTHROPIC_API_KEY`, it is wrong for this machine; redesign it to use the OAuth path.

Reference: wisdom entry `20260729-<id>` (search wisdom with `~/.sisyphus/scripts/wisdom-search.sh "claude subscription bare"`).

## Platform support

This config installs on **Linux (native)**, **macOS (native, Homebrew Bash 4.3+ required — stock `/bin/bash` is 3.2 and cannot run the wisdom scripts)**, and **Windows (via WSL only)**. OpenCode resolves config paths against `os.homedir()` on every OS, so install targets (`~/.config/opencode/`, `~/.opencode/`, `~/.local/share/opencode/`, `~/.sisyphus/`) never need platform-specific remapping. On macOS run `brew install bash bun jq python` first. On Windows run the installer **inside WSL** — Git Bash, Cygwin, and native PowerShell are not supported and `install.sh` will exit with a WSL setup link.
