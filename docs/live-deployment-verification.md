# Live Deployment Verification Gate

This document defines the evidence-state taxonomy and claim discipline that agents must follow when reporting deployment status. It also documents the verifier script, stale-evidence rules, and the first concrete regression probe.

## Evidence States

When reporting what has been done, agents must distinguish between six evidence states. Each state permits and forbids specific claim language.

| State | Definition |
|-------|------------|
| **repo_implemented** | Code exists in the repository and is tracked by git. |
| **tests_passed** | Automated tests for the change pass in the repo (unit, integration, or build). |
| **live_file_installed** | The file is present at its live target path (for example, `~/.config/opencode/...`) via symlink or copy. |
| **active_config_registered** | The live config file references or registers the artifact (for example, plugin listed in `opencode.json`, skill listed in `oh-my-openagent.json`). |
| **runtime_loaded** | The runtime has actually loaded or invoked the artifact (for example, plugin handler called, skill dispatched). |
| **real_project_behavior_proven** | The artifact's effect has been observed in a real project scenario with concrete evidence. |

## Claim Language Rules

| Evidence State | May Say | Must Not Say |
|----------------|---------|--------------|
| **repo_implemented** | "implemented in repo" | "installed", "active", "working" |
| **tests_passed** | "repo tests pass" | "deployed", "runtime verified" |
| **live_file_installed** | "installed at live target" | "loaded" |
| **active_config_registered** | "registered in active config" | "runtime loaded" |
| **runtime_loaded** | "plugin loaded/handler invoked" | "end-to-end working" (without real-project proof) |
| **real_project_behavior_proven** | "working for [specific project/scenario]" (with evidence path) | — |

### Unverified State Rule

If any live or runtime evidence state is unverified, final answers must say `Not verified live: [missing state]`.

## Using the Verifier

The canonical verifier script is `scripts/verify-live-deployment.sh`. It performs a sequence of checks and writes evidence to a directory you specify.

### Usage

```bash
bash scripts/verify-live-deployment.sh \
  --component vera-runtime \
  --project /path/to/project \
  --evidence-dir /path/to/evidence
```

### What It Checks

1. **Config symlink** — Verifies `~/.config/opencode/opencode.json` points to the expected repo path.
2. **Plugin file exists** — Checks the live plugin file is present at its install target.
3. **Plugin SHA match** — Compares SHA256 of the repo copy against the live copy.
4. **HOME plugin autoload path** — Confirms the plugin is installed under `~/.opencode/plugin/`, where OpenCode auto-loads plugin files. Vera runtime is intentionally not listed in `opencode.json`.
5. **Project exists and is a git repo** — Validates the project path.
6. **Runtime proven** — Requires post-marker log entries or watcher state timestamps that match the exact project path (`$REAL_PROJECT_PATH`) or workspace key (`$WORKSPACE_KEY`). Generic timestamps without project-specific evidence are rejected.
7. **Vera root index non-empty** — Runs `vera overview` from the project root and requires `Files > 0` and `Chunks > 0`. A `.vera/` directory alone is not accepted. Nested `.vera` directories (found with `find -mindepth 2`) are explicitly rejected.

### Output

The script writes these files to the evidence directory:

- `summary.json` — Overall result, check list, timestamps, and failure code
- `commands.txt` — Every command executed during verification
- `runtime-log-snippet.txt` — Copied snippet of the runtime log (if found)
- `watcher-state-snippet.json` — Copied snippet of the watcher state file (if found)
- `runtime-project-evidence.txt` — Project/workspace-specific runtime evidence accepted by the verifier
- `watcher-pid.txt` — Accepted watcher PID when autostart PID validation succeeds
- `active-config-plugin-array.json` — Extracted `plugin` array from active OpenCode config
- `vera-overview.txt` — Output from `vera overview` in the project root
- `vera-search.txt` — Output from `vera search` when `--probe-query` is provided

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All checks passed |
| 1 | One or more checks failed (see `summary.json`) |

## Stale Evidence Rules

The verifier defends against stale evidence with timestamp markers.

### How It Works

1. A marker timestamp is recorded at the start of verification (`date -u +%Y-%m-%dT%H:%M:%SZ`).
2. The script looks for log entries or watcher state timestamps that are **at or after** the marker at second precision. Evidence earlier in the same minute no longer passes.
3. Post-marker evidence must also contain the exact project path (`$REAL_PROJECT_PATH`) or workspace key (`$WORKSPACE_KEY`). Generic timestamps without project-specific context are treated as stale.
4. If all found timestamps are **before** the marker, or if post-marker evidence lacks exact project/workspace matching, the check fails.

### Pre-existing Index Handling

The `--allow-existing-index` flag has been removed (it was dead code). A pre-existing `.vera/` directory alone is never accepted as proof of a non-empty index. The verifier always requires:

- A non-empty root `.vera/` index (`vera overview` reports `Files > 0` and `Chunks > 0`).
- No nested `.vera/` indexes (only the root project `.vera/` is accepted).
- A post-marker lifecycle log entry in `vera-runtime.log` with exact project path or workspace key. Watcher state timestamps can corroborate runtime only for an autostart `running` watcher with a numeric safe PID; a manual `stopped` state from a worktree hook is not runtime-loaded evidence by itself. Watcher PID evidence applies only when `OMO_VERA_RUNTIME_AUTOSTART=1` is set and `/proc/<pid>` confirms current-user ownership plus an exact `vera watch <project>` command line.

## Vera/ANIA Regression Probe

The first concrete use case for the Live Deployment Verification Gate is the **Vera/ANIA regression probe**. This probe verifies that Vera semantic search and the ANIA (Automatic Nearest-Index Assurance) pipeline are actually functioning after deployment.

### What the Probe Validates

- `vera-runtime.ts` records project-specific runtime evidence without blocking OpenCode startup
- With `OMO_VERA_RUNTIME_AUTOSTART=1`, the watcher PID is alive, owned by the current user, and its cmdline contains `vera watch` with the exact project path
- With autostart enabled, health checks occur every 60 seconds; dead or unowned PIDs trigger bounded safe restart (max 3 attempts in 10 minutes)
- With `OMO_VERA_RUNTIME_TOOL_UPDATE=1`, index updates can happen before selected tool executions
- The root `.vera/` directory contains a non-empty index (`Files > 0`, `Chunks > 0`)
- No nested `.vera/` indexes exist anywhere under the project
- A search probe (`--probe-query`) succeeds and returns results under the project root

### How to Run the Probe

```bash
# 1. Start with a clean project or worktree
bash scripts/verify-live-deployment.sh \
  --component vera-runtime \
  --project /path/to/your/project \
  --evidence-dir /tmp/vera-probe-evidence

# 2. Inspect the evidence
cat /tmp/vera-probe-evidence/summary.json
```

### Interpreting Results

- **Passed with runtime proven**: The Vera runtime has produced post-marker lifecycle evidence with exact project path or workspace key match. In manual mode this proves the plugin handler was invoked without blocking startup; in autostart mode watcher state must also pass PID validation before watcher activity is claimed.
- **Failed with stale evidence**: The watcher may be running, but it has not produced new evidence since the marker, or post-marker evidence lacks exact project/workspace matching. Check `vera-runtime.log` for errors.
- **Failed with hollow index**: The `.vera/` directory exists but `vera overview` reports `Files: 0` or `Chunks: 0`. Run `vera-hygiene --apply` to exclude unreadable or heavy directories, then reindex.
- **Failed with nested index**: A nested `.vera/` directory was found under the project. Only the root `.vera/` is accepted. Remove nested indexes or add them to `.veraignore`.
- **Failed with missing binary**: The `vera` binary is not installed. Install it with `vera agent install --client opencode`. The plugin fails open, so normal operation continues.

### Note on Unverified Behavior

The workflow requires the verifier to confirm live deployment, but concrete proof that Vera produces correct search results in a real project requires a search probe (`--probe-query`). Without `--probe-query`, the highest state earned is `runtime_loaded`. Agents must provide `--probe-query` (and optionally `--probe-expect`) to reach `real_project_behavior_proven`. Until a search probe passes, agents should report `Not verified live: real_project_behavior_proven`.

## See Also

- [AGENTS.md](../AGENTS.md) — Source of the evidence-state taxonomy and claim discipline
- [Plugins Documentation](plugins.md) — `review-enforcer.ts` live gate and `vera-runtime.ts` HOME plugin autoload behavior
- [Configuration Documentation](configs.md) — Symlink scope caveat distinguishing config files from plugin targets
- [MANIFEST.md](../MANIFEST.md) — Complete artifact inventory
