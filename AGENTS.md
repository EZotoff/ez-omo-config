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
4. **Machine-specific values are acceptable.** The store contains `file://` paths with absolute paths (e.g. `file:///home/ezotoff/...`). This is expected — new machines adapt these via `install.sh`.
5. **Validate JSON after editing.** Run `python3 -c "import json; json.load(open('path'))"` on changed files.

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
- **Custom/OpenAI-compatible providers** (e.g. `moonshot`, `kimi-code`, `deepseek`): Need full provider block with `npm: "@ai-sdk/openai-compatible"`, `options.baseURL`, and model definitions.
- **Auth keys**: Stored in `~/.local/share/opencode/auth.json` under the provider ID. Format: `{ "type": "api", "key": "sk-..." }`. Never commit this file.

## New Machine Setup

```bash
git clone https://github.com/EZotoff/ez-omo-config.git
cd ez-omo-config
./install.sh --symlink
# Then update any machine-specific file:// paths in configs/opencode/opencode.json
```

## Patching OpenCode Binary

When fixing bugs in the OpenCode Go/TypeScript binary, follow this procedure EXACTLY.

### NEVER

- **NEVER replace the live binary with a dev-branch build.** The live binary is version-pinned (e.g. 1.17.9). A dev-branch build has a different version string, different dependencies, and potentially hundreds of unreviewed changes. This breaks the live environment.
- **NEVER build from `origin/dev` or any non-release branch** when the intent is to patch the live version.
- **NEVER use `mv` to hot-swap the binary while servers are running** without coordinating a restart.

### ALWAYS

1. **Identify the live version**: `~/.opencode/bin/opencode --version`
2. **Check out the source at that exact version**: First ensure the source tree is clean (`git status --porcelain` empty, `git log --oneline -1` on a known ref). Then `cd ~/src/opencode && git checkout v<VERSION> -b fix/<bug-name>` (use the release tag, not `dev`). A dirty source tree carries uncommitted changes into the fix branch.
3. **Apply the minimal fix** to the checked-out source
4. **Build from that version**: `cd packages/opencode && OPENCODE_VERSION=$(~/.opencode/bin/opencode --version) bun run script/build.ts --single --skip-install --skip-embed-web-ui`. The build script (`generate.ts`) derives the version from the git branch name; without `OPENCODE_VERSION`, a `fix/*` branch produces `0.0.0-fix/...` and the version check in step 5 will fail.
5. **Verify the build version AND patch presence**: `dist/opencode-linux-x64/bin/opencode --version` must show the live version (not `0.0.0-...`). Also confirm the fix is embedded in the built binary — grep the dist for a string unique to the patch (e.g. `grep -c '<patched-symbol>' dist/opencode-linux-x64/bin/opencode`). Minified Bun binaries rename locals, so verify by source + test + built version, not by internal symbol names.
6. **Backup the live binary to the side**: `cp ~/.opencode/bin/opencode ~/.opencode/bin/opencode.backup-<version>-<description>-<timestamp>`
7. **Stop servers (both surfaces)**: Stop `systemctl --user stop omo-tg.service opencode.service`. If a non-systemd `opencode serve` process is still running (e.g. omo-tg spawns its own), inspect `pgrep -af 'opencode serve'` and stop only the specific service-owned PID that is holding the live binary. Do not run broad `pkill`/`kill -9` loops; if more processes match than expected, stop and choose manually. Otherwise the swap can fail with `Text file busy` or kill unrelated sessions.
8. **Install the patched binary**: `cp dist/opencode-linux-x64/bin/opencode ~/.opencode/bin/opencode && chmod +x ~/.opencode/bin/opencode`
9. **Restart servers**: `systemctl --user start omo-tg.service opencode.service`
10. **Test the live version**: verify the fix works on the real surface (TUI, background tasks, etc.). State explicitly `Not verified live: runtime_loaded, real_project_behavior_proven` until the patched behavior is observed end-to-end in a real session.
11. **Roll back if needed**: `cp ~/.opencode/bin/opencode.backup-<...> ~/.opencode/bin/opencode`

### Skill

Use the `patch-opencode` skill for the full procedure with version detection, source checkout, build, install, and test steps.

### Source repo

- Local source: `~/src/opencode` (remote: `anomalyco/opencode`)
- Fork: `EZotoff/opencode` (for PRs)
- Release tags: `v1.17.9`, `v1.17.8`, etc. (NOT `v0.1.17*` — those are different)
- Build script: `packages/opencode/script/build.ts` (flags: `--single` current platform only, `--skip-install` no global install, `--skip-embed-web-ui` skip web UI bundle)
