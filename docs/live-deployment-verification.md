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
4. **Plugin registered** — Confirms the plugin is listed in the active `opencode.json` plugin array.
5. **Project exists and is a git repo** — Validates the project path.
6. **Runtime proven** — Uses a timestamp marker to determine whether post-marker log entries or watcher state timestamps exist.
7. **Vera index exists** — Checks for the `.vera/` index directory (skips if watcher state reports `missing-binary` in fail-open mode).

### Output

The script writes these files to the evidence directory:

- `summary.json` — Overall result, check list, timestamps, and failure code
- `commands.txt` — Every command executed during verification
- `vera-runtime.log` — Copied snippet of the runtime log (if found)
- `watcher-state.json` — Copied snippet of the watcher state file (if found)

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All checks passed |
| 1 | One or more checks failed (see `summary.json`) |

## Stale Evidence Rules

The verifier defends against stale evidence with timestamp markers.

### How It Works

1. A marker timestamp is recorded at the start of verification (`date -u +%Y-%m-%dT%H:%M:%SZ`).
2. The script looks for log entries or watcher state timestamps that are **at or after** the marker.
3. If all found timestamps are **before** the marker, the evidence is considered stale and the check fails.

### Pre-existing Index Handling

By default, a pre-existing `.vera/` directory alone is not accepted as proof. The `--allow-existing-index` flag relaxes this for cases where you intentionally want to trust an already-built index. Without the flag, the verifier requires either:

- A post-marker log entry in `vera-runtime.log`, or
- A post-marker `lastVerifiedAt` or `lastIndexedAt` in the watcher state file.

## Vera/ANIA Regression Probe

The first concrete use case for the Live Deployment Verification Gate is the **Vera/ANIA regression probe**. This probe verifies that Vera semantic search and the ANIA (Automatic Nearest-Index Assurance) pipeline are actually functioning after deployment.

### What the Probe Validates

- Vera watcher is supervised by `vera-runtime.ts`
- The watcher PID is alive and health-checked every 60 seconds
- Index updates happen automatically after file-modifying tool executions
- The `.vera/` directory contains a fresh index for the project

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

- **Passed with runtime proven**: The Vera watcher has produced post-marker evidence. The pipeline is active.
- **Failed with stale evidence**: The watcher may be running, but it has not produced new evidence since the marker. Check `vera-runtime.log` for errors.
- **Failed with missing binary**: The `vera` binary is not installed. Install it with `vera agent install --client opencode`. The plugin fails open, so normal operation continues.

### Note on Unverified Behavior

The workflow requires the verifier to confirm live deployment, but concrete proof that Vera produces correct search results in a real project is tracked separately. Until Task 9 proves live behavior, agents should report `Not verified live: real_project_behavior_proven` when search accuracy has not been validated end to end.

## See Also

- [AGENTS.md](../AGENTS.md) — Source of the evidence-state taxonomy and claim discipline
- [Plugins Documentation](plugins.md) — `review-enforcer.ts` live gate and `vera-runtime.ts` active registration
- [Configuration Documentation](configs.md) — Symlink scope caveat distinguishing config files from plugin targets
- [MANIFEST.md](../MANIFEST.md) — Complete artifact inventory
