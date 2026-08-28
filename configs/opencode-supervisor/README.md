# OpenCode Project Supervisor

Phase 0 is a read-only external observer. It reconciles top-level project sessions over HTTP, listens to SSE as a wake-up hint, projects human-visible turns, runs shadow judgment ticks, and records decisions in a local hash-chained ledger. It never writes to an OpenCode session.

The bundled `supervisor.json` installs to `$HOME/.config/opencode-supervisor/supervisor.json`. The loader prefers that runtime path and otherwise uses the bundled file. Unknown keys and modes fail closed. P0 accepts only `off` and `shadow`; later rollout modes are intentionally unavailable.

| Field | Meaning |
|---|---|
| `server_url` | Existing OpenCode server URL |
| `server_url` | Existing OpenCode server URL |
| `server_username` / `server_password_env` | HTTP Basic auth; password read from this env var at runtime (default `OPENCODE_SERVER_PASSWORD`, supplied by the systemd unit's `EnvironmentFile`) |
| `initial_window_days` | First-scan horizon: only sessions updated within this window are supervised (default 7) |
| `fetch_concurrency` | Bounded parallel HTTP fetches during reconcile scans (default 8) |
| `model` | Provider and model ID used for stateless judgment ticks |
| `grace_period_s` | Delay after idle before a tick |
| `min_intervention_interval_s` | Minimum interval between ticks for a root |
| `max_tick_concurrency` | Global tick concurrency ceiling |
| `target_history_cap_pairs` | Target-session history pair cap |
| `sibling_turn_window` | Recent changed turns included per sibling |
| `token_budget` | Approximate input cap using characters divided by four |
| `confidence_floor` | Decisions below this confidence become `ABSTAIN` |
| `roots` | Project paths and their `off` or `shadow` modes |

Runtime state is under `$HOME/.local/state/opencode-supervisor/`: `status.json` and `ledger.jsonl`. The API key is read from `$HOME/.local/share/opencode/auth.json` and is never written to status, ledger, or logs.

Evidence state: `repo_implemented`. Not verified live: `live_file_installed`, `active_config_registered`, `runtime_loaded`, `real_project_behavior_proven`.
