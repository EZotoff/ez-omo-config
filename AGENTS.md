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

### Unverified State Rule

If any live/runtime evidence state is unverified, final answers must say `Not verified live: [missing state]`.

When searching for code or understanding codebase structure, follow this strict decision tree:

### Step 1: Check Index Availability

Before any semantic search, verify Vera has indexed the repository:
```bash
test -d .vera && echo "index exists" || echo "no index"
```
If no index exists → run `vera index .` first (see Cold Start below).

### Step 2: Choose the Right Tool

| Task Type | Primary Tool | Example |
|-----------|-------------|---------|
| **Conceptual discovery** — "how does X work", "where is Y logic" | `vera search "query"` | `vera search "JWT validation middleware"` |
| **Exact string/regex** — specific identifiers, TODOs, imports | `vera grep "pattern"` | `vera grep "TODO\|FIXME"` |
| **Symbol precision** — goto definition, find all references | LSP tools | `lsp_goto_definition`, `lsp_find_references` |
| **Bulk file discovery** — list files by pattern | `glob` | `glob "**/*.test.ts"` |
| **Raw text search** — files outside index, find-and-replace | `rg` / `grep` | `rg "old_function_name"` |

### Step 3: Escalation Path

1. **Start with Vera search** for conceptual queries (semantic first protocol)
2. **If Vera returns no relevant results**, try:
   - 2-3 varied phrasings of the query
   - `vera search --deep "query"` (RAG-fusion expansion)
   - `vera search --intent "goal" "query"` (goal-based reranking)
3. **If still no results**, fall back to `rg` / `grep`
4. **For precise symbol navigation**, use LSP tools (never use Vera for goto-definition)

### Step 4: Post-Edit Index Freshness

After making significant edits (refactoring, renaming, adding files):
```bash
vera update .        # Incremental update
# OR
vera watch .         # Start background watcher (if not already running)
```

### Cold Start Protocol

When entering a new repository for the first time:

1. **Check for existing index**:
   ```bash
   test -d .vera && echo "indexed" || echo "cold"
   ```

2. **If cold, index before discovery**:
   ```bash
   vera index .        # Full index (typically 5-30 seconds)
   ```

3. **Verify index created**:
   ```bash
   vera stats          # Show index statistics
   ```

4. **Proceed with semantic search**

### Vera Lifecycle Automation

Vera watcher management is now fully automated. Manual `pgrep` checks and manual `vera watch` invocations are no longer needed.

**Worktree hooks** (`scripts/worktree-post-create.sh` / `scripts/worktree-pre-delete.sh`):
- Automatically bootstrap a Vera index when a worktree is created
- Automatically stop and cleanup the Vera watcher when a worktree is deleted
- State file locations are documented in `docs/worktree-state-schema.md`

**Runtime plugin** (`plugins/vera-runtime.ts`):
- Supervises Vera watchers during active sessions
- Health checks every 60 seconds verify watcher PID
- Restarts watchers if they die unexpectedly
- Fails open: if the `vera` binary is missing, normal operation continues without error

**Manual fallback** (only when automated systems are unavailable):
```bash
vera update .        # One-time incremental update
vera watch . &       # Start background watcher manually
```

### Index Freshness Checklist

Before running semantic search after significant edits:
- [ ] Watcher active? Check `~/.local/share/opencode/worktree-state/<project-id>/vera-watchers/` for PID files
- [ ] If watcher missing: `vera update .` (or `vera watch . &` for continuous monitoring)
- [ ] If index corrupted: `vera repair` → `vera index .`

### Anti-Patterns

| Anti-Pattern | Severity | Why |
|-------------|----------|-----|
| Using `rg` for conceptual discovery | **CRITICAL** | Wastes tokens, returns irrelevant matches, pollutes context |
| Using Vera for goto-definition | **HIGH** | LSP is precise; Vera is fuzzy semantic search |
| Searching without checking index exists | **HIGH** | Will fail or return stale results |
| Starting multiple `vera watch` instances | **MEDIUM** | Wastes resources; check if already running |
| Ignoring `--limit` on Vera search | **MEDIUM** | Default may return too many results; use `--limit 5` for focused queries |

## Documentation Sync Requirements

Because this repo IS the live configuration, any change to config files, plugins, skills, scripts, or install targets must keep all repo documentation accurate. Agents making changes must:

1. **Update MANIFEST.md** if artifact counts, paths, or categories change.
2. **Update README.md** if the artifact inventory, installation options, provider list, agent assignments, or feature descriptions change.
3. **Update relevant docs/*.md** files (docs/configs.md, docs/plugins.md, docs/skills.md, docs/wisdom.md, docs/worktree-state-schema.md) when the corresponding component changes.
4. **Update per-directory READMEs** (configs/opencode/README.md, docker/README.md, or any other directory README) when files in that directory are added, removed, or renamed.
5. **Update install.sh** when new files need symlinking, old files are removed, or install targets change. The ITEMS array must stay in sync with the actual repo contents.

**Do not leave docs stale.** A config change without a doc update is an incomplete change. Verify all references, counts, and paths before finishing.

## Provider Setup

- **Built-in providers** (e.g. `google`, `github-copilot`, `opencode-go`): Only need an entry in `enabled_providers` array + API key in `auth.json`. No `npm` or `options.baseURL` needed.
- **Custom/OpenAI-compatible providers** (e.g. `moonshot`, `kimi-code`, `deepseek`): Need full provider block with `npm: "@ai-sdk/openai-compatible"`, `options.baseURL`, and model definitions.
- **Auth keys**: Stored in `~/.local/share/opencode/auth.json` under the provider ID. Format: `{ "type": "api", "key": "sk-..." }`. Never commit this file.

## New Machine Setup

```bash
git clone https://github.com/EZotoff/ez-omo-config.git
cd ez-omo-config
./install.sh --symlink
# Then update any machine-specific file:// paths in configs/opencode/opencode.json
```
