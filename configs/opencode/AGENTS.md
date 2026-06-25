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
