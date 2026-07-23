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
4. **No machine-specific paths.** `opencode.json` uses relative paths for all local plugins (e.g. `./provider-connect-retry.mjs`, `../../.opencode/plugin/subagent-loop-guard.ts`), resolved by OpenCode against the config file's directory. No manual path updates are needed on a new machine.
5. **Validate JSON after editing.** Run `python3 -c "import json; json.load(open('path'))"` on changed files.
6. **Server vs TUI restart.** Closing/reopening the TUI does NOT restart the `opencode serve` server process. Plugins, OMO runtime, and in-memory session state are initialized once at server startup. Config changes (plugin array, agent settings) require `systemctl --user restart opencode.service omo-tg.service` to take full effect. Always verify with `ps -eo pid,lstart,etime,args | grep 'opencode serve'` that the server start time actually changed before assuming a restart worked.

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

1. **Update MANIFEST.md** if artifact counts, paths, or categories change.
2. **Update README.md** if the artifact inventory, installation options, provider list, agent assignments, or feature descriptions change.
3. **Update relevant docs/*.md** files (docs/configs.md, docs/plugins.md, docs/skills.md, docs/wisdom.md, docs/worktree-state-schema.md) when the corresponding component changes.
4. **Update per-directory READMEs** (configs/opencode/README.md, docker/README.md, or any other directory README) when files in that directory are added, removed, or renamed.
5. **Update install.sh** when new files need symlinking, old files are removed, or install targets change. The ITEMS array must stay in sync with the actual repo contents.

**Do not leave docs stale.** A config change without a doc update is an incomplete change. Verify all references, counts, and paths before finishing.

## Provider Setup

- **Built-in providers** (e.g. `google`, `opencode-go`): Only need an entry in `enabled_providers` array + API key in `auth.json`. No `npm` or `options.baseURL` needed.
- **Custom/OpenAI-compatible providers** (e.g. `deepseek`, `zai-coding-plan`, `kimi-for-coding-oauth`): Need full provider block with `npm: "@ai-sdk/openai-compatible"`, `options.baseURL`, and model definitions.
- **Auth keys**: Stored in `~/.local/share/opencode/auth.json` under the provider ID. Format: `{ "type": "api", "key": "sk-..." }`. Never commit this file.

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
- **NEVER build from `origin/dev` or any non-release branch** when the intent is to patch the live version. When rebuilding to layer additional patches, branch from the current patch-carrying branch (e.g. `fix/turn-summary-timestamp-v1.17.9`), NOT from a clean release tag — otherwise previously-applied tracked patches are silently dropped.
- **NEVER use `mv` to hot-swap the binary while servers are running** without coordinating a restart.
- **NEVER run `cp <anything> ~/.opencode/bin/opencode` (or `mv`, `install`, `>`) without first running `scripts/verify-live-patches.sh <new-binary>` and confirming every active patch's `verification_pattern` is present in the new binary.** The patch-tracker registry at `.sisyphus/patches/*.md` is the source of truth. An unpatched binary silently regresses features the user spent days building.
- **NEVER use `@latest` for any opencode plugin that has tracked patches.** Pin exact versions in `opencode.json#plugin`. Silent `@latest` resolution on cache refresh is how the 2026-07-13 OMO incident lost 8 of 9 tracked patches. Any new patch registered against a plugin-published package MUST be accompanied by a version pin update in `configs/opencode/opencode.json`.

### ALWAYS

1. **Identify the live version**: `~/.opencode/bin/opencode --version`
2. **Check out the source at that exact version**: First ensure the source tree is clean (`git status --porcelain` empty, `git log --oneline -1` on a known ref). Then `cd ~/src/opencode && git checkout v<VERSION> -b fix/<bug-name>` (use the release tag, not `dev`). A dirty source tree carries uncommitted changes into the fix branch. **When layering on top of existing patches, branch from the patch-carrying branch instead.**
3. **Apply the minimal fix** to the checked-out source
4. **Build from that version**: `cd packages/opencode && OPENCODE_VERSION=$(~/.opencode/bin/opencode --version) bun run script/build.ts --single --skip-install --skip-embed-web-ui`. The build script (`generate.ts`) derives the version from the git branch name; without `OPENCODE_VERSION`, a `fix/*` branch produces `0.0.0-fix/...` and the version check in step 5 will fail.
5. **Verify the build version AND patch presence**: `dist/opencode-linux-x64/bin/opencode --version` must show the live version (not `0.0.0-...`). Also confirm the fix is embedded in the built binary — grep the dist for a string unique to the patch (e.g. `grep -c '<patched-symbol>' dist/opencode-linux-x64/bin/opencode`). Minified Bun binaries rename locals, so verify by source + test + built version, not by internal symbol names.
6. **Run `scripts/verify-live-patches.sh dist/opencode-linux-x64/bin/opencode`** to confirm every active patch in `.sisyphus/patches/*.md` will be preserved by the new binary. Address any `STALE` or `MISSING-TARGET` result before proceeding.
7. **Backup the live binary to the side**: `cp ~/.opencode/bin/opencode ~/.opencode/bin/opencode.backup-<version>-<description>-<timestamp>`
8. **Stop servers (both surfaces)**: Stop `systemctl --user stop omo-tg.service opencode.service`. If a non-systemd `opencode serve` process is still running (e.g. omo-tg spawns its own), inspect `pgrep -af 'opencode serve'` and stop only the specific service-owned PID that is holding the live binary. Do not run broad `pkill`/`kill -9` loops; if more processes match than expected, stop and choose manually. Otherwise the swap can fail with `Text file busy` or kill unrelated sessions.
9. **Install the patched binary**: `cp dist/opencode-linux-x64/bin/opencode ~/.opencode/bin/opencode && chmod +x ~/.opencode/bin/opencode`. If the `cp` fails with `Text file busy` because interactive TUI clients hold the old inode, use the Linux `mv` + `cp` pattern: `mv ~/.opencode/bin/opencode ~/.opencode/bin/opencode.old-<v>-pre-<desc> && cp dist/.../opencode ~/.opencode/bin/opencode`. Running TUI clients keep the old inode; new invocations get the new binary.
10. **Restart servers**: `systemctl --user start omo-tg.service opencode.service`
11. **Test the live version**: verify the fix works on the real surface (TUI, background tasks, etc.). State explicitly `Not verified live: runtime_loaded, real_project_behavior_proven` until the patched behavior is observed end-to-end in a real session.
12. **Roll back if needed**: `cp ~/.opencode/bin/opencode.backup-<...> ~/.opencode/bin/opencode`
13. **For OMO plugin updates specifically**: OMO version advances cannot be applied by file-level patches alone because patches target `packages/omo-opencode/src/...` while runtime loads `dist/index.js`. Any OMO update MUST go through the `update-to-latest` skill (13-phase pipeline). Do NOT rely on `@latest` resolution.

### Skill

Use the `patch-opencode` skill for the full procedure with version detection, source checkout, build, install, and test steps.

### Source repo

- Local source: `~/src/opencode` (remote: `anomalyco/opencode`)
- Fork: `EZotoff/opencode` (for PRs)
- Release tags: `v1.17.9`, `v1.17.8`, etc. (NOT `v0.1.17*` — those are different)
- Build script: `packages/opencode/script/build.ts` (flags: `--single` current platform only, `--skip-install` no global install, `--skip-embed-web-ui` skip web UI bundle)
