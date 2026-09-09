# Live Deployment Verification Gate

This document defines the evidence-state taxonomy and claim discipline agents must follow when reporting deployment status. It also documents the generic verifier script used to capture repo, config, install, and runtime evidence without hard-coding a specific integration.

## Evidence States

| State | Definition |
|-------|------------|
| **repo_implemented** | Code exists in the repository and is tracked by git. |
| **tests_passed** | Automated tests for the change pass in the repo. |
| **live_file_installed** | The file is present at its live target path via symlink or copy. |
| **active_config_registered** | The live config file references or registers the artifact. |
| **runtime_loaded** | The runtime has actually loaded or invoked the artifact. |
| **real_project_behavior_proven** | The artifact's effect has been observed in a real project scenario with concrete evidence. |

## Claim Language Rules

| Evidence State | May Say | Must Not Say |
|----------------|---------|--------------|
| **repo_implemented** | "implemented in repo" | "installed", "active", "working" |
| **tests_passed** | "repo tests pass" | "deployed", "runtime verified" |
| **live_file_installed** | "installed at live target" | "loaded" |
| **active_config_registered** | "registered in active config" | "runtime loaded" |
| **runtime_loaded** | "plugin loaded/handler invoked" | "end-to-end working" without real-project proof |
| **real_project_behavior_proven** | "working for [specific project/scenario]" with evidence | — |

If any live or runtime evidence state is unverified, final answers must say `Not verified live: [missing state]`.

## Using the Verifier

The canonical verifier script is `scripts/verify-live-deployment.sh`. It performs repo-safe checks and writes evidence files to a directory you specify.

```bash
bash scripts/verify-live-deployment.sh \
  --component component-name \
  --project /path/to/project \
  --evidence-dir /path/to/evidence \
  --live-target /path/to/installed/artifact \
  --config-reference expected-config-substring \
  --runtime-evidence /path/to/runtime/log
```

Required arguments:

- `--component`: Human-readable component name recorded in `summary.json`.
- `--project`: Project directory used as the real-project verification anchor. The verifier requires it to exist and be a git repository.
- `--evidence-dir`: Directory where evidence artifacts are written.

Optional evidence arguments:

- `--live-target`: Requires an installed artifact path to exist and records it in `live-paths.txt`.
- `--config-reference`: Requires the active OpenCode config to contain the given substring; this advances the highest state to `active_config_registered`.
- `--runtime-evidence`: Requires a non-empty runtime evidence file, copies it to `runtime-evidence.txt`, and advances the highest state to `runtime_loaded`.

The script intentionally does not prove `real_project_behavior_proven` by itself. Component-specific proof such as a CLI invocation, API call, browser/TUI trace, or domain-specific smoke test must be captured separately and cited in the closeout.
## Fresh-Boot Smoke Gate (complementary script)

The generic verifier above proves file/config states. A cutover can pass every pattern check yet ship a runtime that fails to boot — the 2026-09-08 incident (pattern-presence ≠ bootability). `scripts/smoke-boot-check.sh` closes that gap: it boots a FRESH throwaway `opencode run --print-logs` (random port, safe alongside live servers) and asserts plugins load (0 `failed to load plugin` lines), the agent resolves (0 `agent "..." not found` lines; agent-attributed `message=stream providerID=... agent=Sisyphus` canary line), a prompt round-trips the model loop (`exiting loop` line), opencode exits 0, and no pre-existing `opencode serve` process appears/disappears.

```bash
bash scripts/smoke-boot-check.sh   # exit 0 → 'Summary: smoke-boot OK | 0 plugin-load errors | 0 agent-not-found | stream+loop confirmed | opencode rc=0'
```

Exit 1 = broken boot (offending lines + log path on stderr) — a critical regression for any cutover. It is a MANDATORY post-cutover gate in the `update-to-latest` pipeline (see its Post-Cutover Smoke-Boot Gate section), run after the binary swap and patch reconciliation, before any `runtime_loaded` claim. `--print-logs` is load-bearing: it surfaces plugin-load ERROR lines that default output suppresses; the round-trip is therefore asserted via log-stream lines, not `"type":"text"` (which only exists in `--format json` mode).


## What It Checks

1. **Config symlink** — Verifies `~/.config/opencode/opencode.json` resolves to this repo's `configs/opencode/opencode.json`.
2. **Project anchor** — Verifies the supplied project path exists and is a git repository.
3. **Active config parse** — Parses the active config JSON and extracts its `plugin` array to `active-config-plugin-array.json`.
4. **Optional live target** — Verifies the requested installed artifact path exists.
5. **Optional config reference** — Verifies the active config contains a required registration/reference string.
6. **Optional runtime evidence** — Verifies the supplied runtime evidence file is non-empty and copies it into the evidence directory.

## Output Files

- `summary.json` — Overall result, check list, timestamps, marker timestamp, failure code, and highest earned state.
- `commands.txt` — Commands or command-shaped checks used during verification.
- `live-paths.txt` — Live config/artifact paths accepted by the verifier.
- `active-config-plugin-array.json` — Extracted `plugin` array from active OpenCode config.
- `active-config-extraction.log` — JSON parse/extraction log for the active config.
- `runtime-evidence.txt` — Copy of runtime evidence when `--runtime-evidence` is supplied.

## Stale Evidence Rules

The verifier records a marker timestamp at startup in `summary.json`. Runtime-specific probes should only pass runtime or real-project states when their evidence is at or after that marker and tied to the requested project/scenario. The generic script can only verify that a supplied runtime evidence file is non-empty; callers remain responsible for making that file precise enough to satisfy the claim being made.

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All requested checks passed. |
| 1 | One or more requested checks failed; inspect `summary.json`. |

## See Also

- [AGENTS.md](../AGENTS.md) — Source of the evidence-state taxonomy and claim discipline
- [Plugins Documentation](plugins.md) — Plugin deployment model
- [Configuration Documentation](configs.md) — Symlink scope caveat distinguishing config files from plugin targets
- [MANIFEST.md](../MANIFEST.md) — Complete artifact inventory
