# ez-omo-config — Agent Instructions

## What This Is

This project is the **versioned config store** for OpenCode and Oh-My-OpenAgent (OMO).
The active configs are **symlinked** to this repo — editing a file here IS editing the live config.

## Config Locations

| Purpose | Store path (git-tracked) | Live symlink (OpenCode reads this) |
|---------|--------------------------|-------------------------------------|
| **OpenCode config** | `configs/opencode/opencode.json` | `~/.config/opencode/opencode.json` → store |
| **OMO config** | `configs/oh-my-openagent/oh-my-openagent.json` | `~/.config/opencode/oh-my-openagent.json` → store |
| **Provider retry plugin** | `configs/opencode/provider-connect-retry.mjs` | `~/.config/opencode/provider-connect-retry.mjs` → store |
| **Retry error registry** | `configs/retry-errors.json` | `~/.config/opencode/retry-errors.json` → store |
| **Agent default guard** | `configs/opencode/agent-default-guard.mjs` | `~/.config/opencode/agent-default-guard.mjs` → store |
| **Auth / API keys** | — | `~/.local/share/opencode/auth.json` (NEVER committed) |

## How It Works

Live configs are symlinks pointing into this repo:
```
~/.config/opencode/opencode.json        →  ~/ez-omo-config/configs/opencode/opencode.json
~/.config/opencode/oh-my-openagent.json →  ~/ez-omo-config/configs/oh-my-openagent/oh-my-openagent.json
```

**There is ONE file, not two.** Editing either path modifies the same file. Changes are immediately visible to OpenCode AND tracked by git.

## Rules for Agents

1. **Edit the store path** (files in this repo). The symlinks ensure OpenCode sees the change.
2. **No propagation needed.** The old copy-and-adapt workflow is dead. There is no second file to sync.
3. **Never commit auth/API keys.** `~/.local/share/opencode/auth.json` is machine-local.
4. **No machine-specific paths.** `opencode.json` uses relative paths for all local plugins (e.g. `./provider-connect-retry.mjs`, `../../.opencode/plugin/clickable-links.ts`), resolved by OpenCode against the config file's directory. No manual path updates are needed on a new machine.
5. **Validate JSON after editing.** Run `python3 -c "import json; json.load(open('path'))"` on changed files.
6. **Server vs TUI restart.** Closing/reopening the TUI does NOT restart the `opencode serve` server process. Plugins, OMO runtime, and in-memory session state are initialized once at server startup. Config changes (plugin array, agent settings) require `systemctl --user restart opencode.service` to take full effect (the former `omo-tg.service` unit is masked/retired). Always verify with `ps -eo pid,lstart,etime,args | grep 'opencode serve'` that the server start time actually changed before assuming a restart worked.

## Live Deployment Claim Discipline

When reporting what has been done, agents must distinguish between six evidence states. Each state permits and forbids specific claim language.

### Evidence States

| State | Definition |
|-------|------------|
| **repo_implemented** | Code exists in the repository and is tracked by git. |
| **tests_passed** | Automated tests for the change pass in the repo (unit, integration, or build). |
| **live_file_installed** | The file is present at its live target path (e.g. `~/.config/opencode/...`) via symlink or copy. |
| **active_config_registered** | The live config file references or registers the artifact (e.g. plugin listed in `opencode.json`, skill listed in `oh-my-openagent.json`). |
| **runtime_loaded** | The runtime has actually loaded or invoked the artifact (e.g. plugin handler called, skill dispatched). |
| **real_project_behavior_proven** | The artifact's effect has been observed in a real project scenario with concrete evidence. |

### Claim Language Table

| Evidence State | May Say | Must Not Say |
|----------------|---------|--------------|
| **repo_implemented** | "implemented in repo" | "installed", "active", "working" |
| **tests_passed** | "repo tests pass" | "deployed", "runtime verified" |
| **live_file_installed** | "installed at live target" | "loaded" |
| **active_config_registered** | "registered in active config" | "runtime loaded" |
| **runtime_loaded** | "plugin loaded/handler invoked" | "end-to-end working" (without real-project proof) |
| **real_project_behavior_proven** | "working for [specific project/scenario]" (with evidence path) | — |

### Symlink Scope Caveat

The symlinked config behavior described in the Config Locations table and How It Works section applies **only** to the listed symlinked config files (`opencode.json`, `oh-my-openagent.json`, `provider-connect-retry.mjs`, `retry-errors.json`). Installed plugin targets such as `$HOME/.opencode/plugin/*.ts` are **separate deployable artifacts** and do not share the "one file, not two" symlink property. Plugin files are copied or symlinked by `install.sh` and must be treated as distinct deployment targets.

### Plugin Registration Caveat

Plugins in `~/.opencode/plugin/*.ts` are auto-loaded by OpenCode at startup, **but command-pipeline interception only works for plugins registered in `opencode.json#plugin`**. A plugin file symlinked to `~/.opencode/plugin/` is not enough if it needs to intercept commands, hooks, or system transforms. Always verify the plugin appears in the `plugin` array of `opencode.json` before debugging plugin behavior.

### Plugin Error Display (TUI Toasts vs console.* spam)

Server plugins (registered in `opencode.json#plugin`) receive a `ctx` of shape `{client, project, worktree, directory, experimental_workspace, serverUrl, $}`. **There is no `ctx.logger`, `ctx.toast`, `ctx.notify`, or `ctx.error` field.** Plugins MUST NOT use `console.log`/`console.warn`/`console.info`/`console.error` for user-facing output — that text goes to the server process stderr/stdout and leaks into the TUI viewport or journald as raw spam (this was the root cause of the `[retry-plugin]` quota-error spam regression).

**The proper channel is `ctx.client.tui.showToast`** — it publishes a `tui.toast.show` event that the TUI subscribes to and renders as a real toast popup:

```javascript
await ctx.client.tui.showToast({
  body: {
    title: "Provider quota exhausted",       // optional
    message: "K3 fallback also failed.",        // required
    variant: "error",                        // 'info' | 'success' | 'warning' | 'error'
    duration: 10000,                          // optional, default 5000ms
  },
})
```

Source-of-truth citations (OpenCode tree at `~/src/opencode`):
- SDK method: `packages/sdk/js/src/gen/sdk.gen.ts:1118` (`POST /tui/show-toast`)
- Server handler: `packages/opencode/src/server/routes/instance/httpapi/handlers/tui.ts:79-84`
- Event schema: `packages/schema/src/tui-event.ts:40-50`
- TUI subscription: `packages/tui/src/app.tsx:990-998`
- If no TUI is connected, the event is silently dropped — safe to call unconditionally.

**Automatic channels** (no plugin code needed):
- `session.error` events are auto-toasted by the TUI with `variant=error`, 5s duration (`packages/tui/src/app.tsx:1018-1029`; filters out `MessageAbortedError`). Plugins that propagate errors through the regular session lifecycle do NOT need to call `showToast`.
- `session.status` events with `status.type="retry"` and `status.action` (`packages/schema/src/session-status-event.ts:13-28`) open a `DialogRetryAction` modal (`packages/tui/src/routes/session/index.tsx:364`) with `title/message/label/link`. Use this for actionable retry prompts.

**Diagnostic logging**: keep routine operation (retry attempts, nudges, fallbacks) in the plugin's local log file (e.g. `~/.config/opencode/retry-plugin.log`) — NOT in the TUI, NOT on stderr. The TUI auto-toasts `session.error` events; routine retry activity is already visible as session message activity.

**TUI plugins are a separate system** (loaded via `tui.*` config fields, NOT `opencode.json#plugin`): they run inside the Solid tree and get a `TuiPluginApi` with direct `ui.toast`, `ui.Dialog`, `ui.DialogAlert`, `ui.DialogConfirm`, `ui.DialogPrompt`, `ui.DialogSelect`, `keymap`, `route`, `kv` access (`packages/tui/src/plugin/adapters.tsx:173-285`). Server plugins cannot reach TUI plugin APIs directly — the two systems are disjoint.

Reference: wisdom entry `20260720-104500-tst1` (search wisdom with `~/.sisyphus/scripts/wisdom-search.sh "plugin TUI toast"`).

### Unverified State Rule

If any live/runtime evidence state is unverified, final answers must say `Not verified live: [missing state]`.

When searching for code or understanding codebase structure, use this vanilla discovery protocol:

| Task Type | Primary Tool | Notes |
|-----------|--------------|-------|
| Conceptual/codebase discovery — "how does X work", "where is Y logic" | `codegraph_explore` | Use first when available; it returns relevant source and relationships in one call. |
| Symbol precision — goto definition, references, rename safety | LSP tools | Use `lsp_goto_definition`, `lsp_find_references`, and `lsp_rename` for exact language-server results. |
| Exact text/regex — identifiers, imports, TODOs, config strings | `grep` / `rg` | Use for literal or regex search, especially outside indexed code. |
| File discovery — list files by pattern | `glob` | Use for path patterns such as `**/*.test.ts` or `docs/**/*.md`. |

Prefer codegraph/LSP facts over memory. If a tool is unavailable or returns no useful result, fall back to the next appropriate vanilla tool without bootstrapping any repo-local search service.
## Documentation Sync Requirements

Because this repo IS the live configuration, any change to config files, plugins, skills, scripts, or install targets must keep all repo documentation accurate. Agents making changes must:

1. **MANIFEST.md is the single per-artifact inventory** (paths, install targets, statuses). Update it whenever an artifact is added, removed, renamed, or changes status. Include the Patch Registry row for any new `.sisyphus/patches/` entry.
2. **README.md carries the category summary only** — never a per-artifact inventory. Update README only when a category is added/removed, a category's headline count/purpose changes, or the provider list, agent assignments, install options, or feature descriptions change.
3. **Update relevant docs/*.md** files (docs/configs.md, docs/plugins.md, docs/skills.md, docs/wisdom.md, docs/patches.md, docs/worktree-state-schema.md) when the corresponding component changes. Dated snapshots go to docs/history/ and are not updated after the fact.
4. **Update per-directory READMEs** (configs/opencode/README.md, docker/README.md, or any other directory README) when files in that directory are added, removed, or renamed.
5. **Update install.sh** when new files need symlinking, old files are removed, or install targets change. The ITEMS array must stay in sync with the actual repo contents.

**Do not leave docs stale.** A config change without a doc update is an incomplete change. Verify all references, counts, and paths before finishing.

## Provider Setup

- **Built-in providers** (e.g. `google`, `opencode-go`): Only need an entry in `enabled_providers` array + API key in `auth.json`. No `npm` or `options.baseURL` needed.
- **Custom/OpenAI-compatible providers** (e.g. `deepseek`, `zai-coding-plan`, `kimi-for-coding-oauth`): Need full provider block with `npm: "@ai-sdk/openai-compatible"`, `options.baseURL`, and model definitions.
- **Auth keys**: Stored in `~/.local/share/opencode/auth.json` under the provider ID. Format: `{ "type": "api", "key": "sk-..." }`. Never commit this file.

## Platform support

This config installs on **Linux (native)**, **macOS (native, Homebrew Bash 4.3+ required — stock `/bin/bash` is 3.2 and cannot run the wisdom scripts)**, and **Windows (via WSL only)**. OpenCode resolves config paths against `os.homedir()` on every OS, so install targets (`~/.config/opencode/`, `~/.opencode/`, `~/.local/share/opencode/`, `~/.sisyphus/`) never need platform-specific remapping. On macOS run `brew install bash bun jq python` first. On Windows run the installer **inside WSL** — Git Bash, Cygwin, and native PowerShell are not supported and `install.sh` will exit with a WSL setup link.

## New Machine Setup

```bash
git clone https://github.com/EZotoff/ez-omo-config.git
cd ez-omo-config
./install.sh --symlink
# Set up API keys:
cp auth.json.example ~/.local/share/opencode/auth.json
# Edit auth.json with your provider keys
./scripts/check-prerequisites.sh
```

No manual path updates are needed — `opencode.json` uses relative paths for all local plugins, resolved against the config file's directory by OpenCode.

## Patching OpenCode Binary

When fixing bugs in the OpenCode Go/TypeScript binary, follow this procedure EXACTLY.

### NEVER

- **NEVER replace the live binary with a dev-branch build.** The live binary is version-pinned (e.g. 1.17.9). A dev-branch build has a different version string, different dependencies, and potentially hundreds of unreviewed changes. This breaks the live environment.
- **NEVER build from `origin/dev` or any non-release branch** when the intent is to patch the live version.
- **NEVER use `mv` to hot-swap the binary while servers are running** without coordinating a restart.
- **NEVER use `@latest` for any opencode plugin that has tracked patches.** Pin exact versions in `opencode.json#plugin`. Silent `@latest` resolution on cache refresh is how the 2026-07-13 OMO incident lost 8 of 9 tracked patches. Any new patch registered against a plugin-published package MUST be accompanied by a version pin update in `configs/opencode/opencode.json`.

### ALWAYS

1. **Identify the live version**: `~/.opencode/bin/opencode --version`
2. **Check out the source at that exact version**: First ensure the source tree is clean (`git status --porcelain` empty, `git log --oneline -1` on a known ref). Then `cd ~/src/opencode && git checkout v<VERSION> -b fix/<bug-name>` (use the release tag, not `dev`). A dirty source tree carries uncommitted changes into the fix branch.
3. **Apply the minimal fix** to the checked-out source
4. **Build from that version**: `cd packages/opencode && OPENCODE_VERSION=$(~/.opencode/bin/opencode --version) bun run script/build.ts --single --skip-install --skip-embed-web-ui`. The build script (`generate.ts`) derives the version from the git branch name; without `OPENCODE_VERSION`, a `fix/*` branch produces `0.0.0-fix/...` and the version check in step 5 will fail.
5. **Verify the build version AND patch presence**: `dist/opencode-linux-x64/bin/opencode --version` must show the live version (not `0.0.0-...`). Also confirm the fix is embedded in the built binary — grep the dist for a string unique to the patch (e.g. `grep -c '<patched-symbol>' dist/opencode-linux-x64/bin/opencode`). Minified Bun binaries rename locals, so verify by source + test + built version, not by internal symbol names.
6. **Backup the live binary to the side**: `cp ~/.opencode/bin/opencode ~/.opencode/bin/opencode.backup-<version>-<description>-<timestamp>`
7. **Stop servers (both surfaces)**: Stop `systemctl --user stop opencode.service`. If a non-systemd `opencode serve` process is still running, inspect `pgrep -af 'opencode serve'` and stop only the specific service-owned PID that is holding the live binary. Do not run broad `pkill`/`kill -9` loops; if more processes match than expected, stop and choose manually. Otherwise the swap can fail with `Text file busy` or kill unrelated sessions.
8. **Install the patched binary**: `cp dist/opencode-linux-x64/bin/opencode ~/.opencode/bin/opencode && chmod +x ~/.opencode/bin/opencode`
9. **Restart servers**: `systemctl --user start opencode.service`
10. **Test the live version**: verify the fix works on the real surface (TUI, background tasks, etc.). State explicitly `Not verified live: runtime_loaded, real_project_behavior_proven` until the patched behavior is observed end-to-end in a real session.
11. **Roll back if needed**: `cp ~/.opencode/bin/opencode.backup-<...> ~/.opencode/bin/opencode`

### Multi-Surface Rendering (CRITICAL for patch correctness)

OpenCode has multiple independent rendering paths for the same logical output. A patch that modifies one path may silently stop working when a version update changes which package renders the feature.

**Rendering surfaces**:
- **CLI run** — `packages/opencode/src/cli/cmd/run/` (the `opencode run` scrollback renderer)
- **TUI interactive** — `packages/tui/src/routes/session/` (the interactive SolidJS TUI launched by bare `opencode`)
- **Server API** — event handlers, HTTP routes, plugin triggers

**Rules** (all mandatory for any patch that modifies rendering, UI, or chunk-pipeline code):

1. **`surfaces` frontmatter field is REQUIRED.** List every surface the patch touches (`cli-run`, `tui-interactive`, `server-api`). A patch missing this field WILL be rejected at update-to-latest Phase 4. A patch that only covers `cli-run` may leave `tui-interactive` broken after a version bump that migrates rendering between packages (this happened with the turn-summary-timestamp patch in the v1.17→v1.18 migration).

2. **`runtime_effective` boolean flag is REQUIRED for monkey-patches and ref-callback patches.** Set `runtime_effective: true` only after observing the patched behaviour on the real surface. Bumping `dep_version` or rebuilding the binary does NOT flip this flag — pattern-presence in the binary is not effectiveness. The v1.18.5 link-click regression (see `opencode--link-click-wrapped-osc8.md`) happened because the patch was reapplied verbatim, the patch string survived in the binary, and the monkey-patch hook (`_linkifyMarkdownChunks`) was no longer invoked on the active SolidJS render path.

3. **Monkey-patch reachability trap.** When a patch overrides an internal method (e.g. `el._linkifyMarkdownChunks = ...` via a `ref`), a version bump may silently make that method unreachable even though the source file still contains the override and the binary still contains the string. The SolidJS renderer migration between v1.17 and v1.18 moved chunk-processing off `TextPart`'s `<markdown>` ref. After ANY reapply to a new version, you MUST verify at runtime that the hook is actually invoked — not just that the code compiles and the string is present.

4. **Verification pattern reliability.** `verify-live-patches.sh` greps the binary for `verification_pattern`. Bun minification renames local variables but **preserves JavaScript property keys and string literals**. A `verification_pattern` that is a property key (e.g. `__linkLabelPatch`), a string literal, or any other minification-survivor will report APPLIED even when the surrounding code is unreachable. When choosing a `verification_pattern`, prefer a pattern that disappears if the code path is dead. When that is not possible (binary patches), the patch entry MUST additionally carry a `## Runtime Verification` section with concrete surface-exercise steps, and the `runtime_effective` flag is the only honest signal of effectiveness.

5. **Surface coverage verification.** After building, exercise the feature on EACH listed surface. Send a test prompt via both `opencode run` AND the interactive TUI, and observe the expected behaviour directly. Grep alone is insufficient — code may be present in the bundle but unreachable at runtime. Capture the observation (screenshot, captured output, or explicit human confirmation) in the patch entry before claiming the patch works.

### Skill

Use the `patch-opencode` skill for the full procedure with version detection, source checkout, build, install, and test steps.

### Source repo

- Local source: `~/src/opencode` (remote: `anomalyco/opencode`)
- Fork: `EZotoff/opencode` (for PRs)
- Release tags: `v1.17.9`, `v1.17.8`, etc. (NOT `v0.1.17*` — those are different)
- Build script: `packages/opencode/script/build.ts` (flags: `--single` current platform only, `--skip-install` no global install, `--skip-embed-web-ui` skip web UI bundle)

## Patch-Preservation Safety Infrastructure

Three-layer defense against patch drift (Track B v2):

1. **Regression Corpus** (`tests/regressions/`) — paired `.sh` + `.kill.sh` tests for every bug ever fixed. Run via `bash tests/run_regressions.sh`.
2. **Rewritten Verifier** (`scripts/verify-live-patches.sh`) — verifies every tracked patch against runtime-resolved paths. Exit 0 = all APPLIED, exit 1 = issues found. Supports `--schema-only` mode for frontmatter validation without needing the binary (see layer 5).
3. **inotify Watcher** (`opencode-patch-watcher.service`) — kernel-level detection of writes to `~/.opencode/bin/`. Reactive, not preventive.
4. **Periodic Integrity Check** (`opencode-patch-integrity-check.timer`) — runs `verify-live-patches.sh` every 30 minutes as a backstop for inotify bypass cases.
5. **Schema Enforcement** (`tests/test_patch_entries.sh`) — validates frontmatter completeness for all `status: active` patch entries via `verify-live-patches.sh --schema-only`. Enforces three rules: (a) `target_file` must be present; (b) rendering-path `target_file` (`cli/cmd/run/`, `tui/src/routes/`, `server/routes/`) requires `surfaces`; (c) patches with `surfaces` require `runtime_effective`. This catches metadata destruction at commit time — a cutover commit that deletes the `surfaces` field or collapses a specific `target_file` to a generic value will fail the test suite and block the merge via the review-enforcer plugin. This makes the TEMPLATE.md schema load-bearing, not advisory.

**Prerequisite**: `sudo apt install -y inotify-tools` for the watcher service.

### Cooperation Contract

1. Runtime path writes trigger the inotify watcher automatically. Check `journalctl --user -u opencode-patch-watcher.service` for alerts.
2. Before committing to master, run `bash tests/run_all.sh`. The review-enforcer plugin consumes the regression corpus output.
3. When fixing a bug, add a paired `.sh` + `.kill.sh` to `tests/regressions/`. This is the only durable defense against agent memory resets.
4. Never `kill` the `opencode-patch-watcher.service` process. It is the reactive detection layer.
5. Structural fixes are mandatory for new bash/python tooling: `set -euo pipefail` for bash, `subprocess.run([...])` list-form for Python, no string interpolation into Python source.
6. Cutover commits must not delete `surfaces`, `runtime_effective`, or collapse `target_file` from specific source files to a generic value. The schema validator (layer 5) enforces this structurally — `bash tests/test_patch_entries.sh` must pass before merge. This was added after commit `7b7bb19` destructively edited `opencode--turn-summary-timestamp.md` (deleted `surfaces`, collapsed 7-file `target_file` to `"opencode"`) and the damage went undetected until a manual audit.
7. After any opencode binary upgrade, ALL active patches must be reconciled in the SAME commit/PR. The drift gate (`tests/test_patch_versions.sh`) fails on unresolved VERSION-DRIFT — patches whose `dep_version` doesn't match the live binary AND have no `runtime_effective: false` flag. For each drifted patch: EITHER bump `dep_version` + set `runtime_effective: true` (verified effective), OR set `runtime_effective: false` with a justification (becomes ACKNOWLEDGED-DRIFT, exempt from the gate). This closed loop was added after the v1.17.9→v1.18.5 cutover left 4 patches at `dep_version: 1.17.9-local` for 10+ days with nobody noticing.
