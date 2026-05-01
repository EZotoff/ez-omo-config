# Vera Skill Integration — Implementation Plan

> **Status**: Draft — Ready for Review
> **Scope**: Integrate Vera (semantic code search) as a skill-based addon into OpenCode/OMO
> **Approach**: Skill-first architecture (NOT MCP)
> **Deferred**: Graphify postponed to later phase

---

## 1. Executive Summary

### Why Vera

Vera is a local-first semantic code search tool (Rust binary, ONNX embeddings) that provides:
- **Hybrid retrieval**: BM25 + vector search + cross-encoder reranking
- **MRR@10: 0.60** (vs 0.35 for vector-only tools like cocoindex-code)
- **Single static binary** — no Python, Node.js, or external databases required
- **Local inference** — no API keys needed, all embeddings computed on-device
- **Fast indexing** — ~8 seconds for multi-MB codebases on consumer hardware (RTX 4080)
- **Token-efficient output** — Markdown codeblocks (40% smaller than JSON)

### Why Skill (Not MCP)

The OMO `skill_mcp` meta-tool wraps ALL MCP tools into a single `skill_mcp` tool with 3 parameters (`mcp_name`, `tool_name`, `arguments`). This adds undesirable indirection:

| Approach | Agent Command | Downsides |
|----------|--------------|-----------|
| **MCP** | `skill_mcp(mcp_name="vera", tool_name="search_code", arguments={"query": "..."})` | Indirection, reduced surface (no --deep, --intent, references, dead-code, watch) |
| **Skill** | `vera search "authentication logic"` | Direct, full CLI surface, natural for agents |

Vera's own design philosophy confirms: *"Keep the Vera skill CLI-centered. Keep the MCP surface small. Skill is primary."*

### Integration Philosophy

**Vera complements, not replaces, existing tools:**
- **Vera search**: Semantic discovery ("how does X work", "where is Y logic")
- **grep/rg**: Exact string matching, bulk find-and-replace
- **LSP**: Precise symbol resolution (goto_definition, find_references)
- **glob**: File discovery by pattern

---

## 2. Installation Strategy

### 2.1 Vera Binary Installation

**Prerequisite**: `vera` must be on PATH before skill installation.

**Recommended install method** (cross-platform, zero runtime deps):
```bash
# Option A: Package manager (recommended)
bunx @vera-ai/cli install        # Bun
npx -y @vera-ai/cli install      # npm
uvx vera-ai install               # Python uv

# Option B: Prebuilt binary from GitHub Releases
# Download for: Linux x86_64/aarch64, macOS x86_64/aarch64, Windows x86_64

# Option C: Build from source (Rust 1.85+)
git clone https://github.com/lemon07r/Vera.git && cd Vera
cargo build --release
cp target/release/vera ~/.local/bin/
```

**Backend setup** (one-time, auto-detects hardware):
```bash
vera setup                       # Interactive wizard
# OR
vera setup --onnx-jina-cuda      # NVIDIA GPU (CUDA 12+)
vera setup --onnx-jina-coreml    # Apple Silicon
vera setup --onnx-jina-rocm      # AMD GPU (Linux)
vera setup --onnx-jina-openvino  # Intel GPU
vera setup --onnx-jina-directml  # Windows DirectX 12
```

**Verification**:
```bash
vera doctor            # Basic health check
vera doctor --probe    # Deep ONNX runtime diagnostics
```

### 2.2 Skill Installation

Vera's skill files are installed via Vera's own CLI (NOT manually created):

```bash
# Global install (recommended — available to all projects)
vera agent install --client opencode

# Project-local install (only for specific project)
vera agent install --client opencode --scope project
```

**Files created** (global scope):
```
~/.config/opencode/skills/vera/
├── SKILL.md                    # Main skill definition
├── references/
│   ├── install.md              # Installation guide
│   ├── query-patterns.md       # Query examples
│   ├── troubleshooting.md      # Error fixes
│   └── mcp.md                  # MCP usage notes (fallback)
├── agents/
│   └── openai.yaml             # OpenAI interface spec
└── .version                    # Vera version stamp
```

**Important**: Vera manages its own skill files. We do NOT commit Vera's skill files to this repo. Instead, we:
1. Document the installation command in our README
2. Add the skill assignment to `oh-my-openagent.json` for relevant agents
3. Add AGENTS.md routing rules for tool selection

### 2.3 Agent Skill Assignment

Update `configs/oh-my-openagent/oh-my-openagent.json` to assign the `vera` skill to agents that perform codebase discovery:

```json
{
  "agents": {
    "explore": {
      "skills": ["wisdom", "vera"],
      "description": "Discovery and exploration agent with semantic search"
    },
    "sisyphus": {
      "skills": ["wisdom", "vera"],
      "description": "Executor with semantic code search capabilities"
    },
    "librarian": {
      "skills": ["wisdom", "knowledge", "vera"],
      "description": "Documentation search with semantic code search"
    }
  }
}
```

**Rationale**:
- `explore`: Primary discovery agent — needs semantic search for unfamiliar codebases
- `sisyphus`: Executor — needs to find relevant code during implementation
- `librarian`: Documentation/code search — benefits from semantic retrieval
- `atlas`, `prometheus`, `oracle`: May benefit but not essential (planning/analysis)
- `frontend-ui-ux`: Less relevant (UI-focused)

---

## 3. AGENTS.md Routing Rules

### 3.1 Tool Selection Decision Tree

Add the following section to `AGENTS.md` (after "Rules for Agents"):

```markdown
## Code Search Tool Selection

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
| **Conceptual discovery** — "how does X work", "where is Y logic", "find authentication flow" | `vera search "query"` | `vera search "JWT validation middleware"` |
| **Exact string/regex** — find specific identifiers, TODOs, imports | `vera grep "pattern"` | `vera grep "TODO\|FIXME"` |
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

### Anti-Patterns

| Anti-Pattern | Severity | Why |
|-------------|----------|-----|
| Using `rg` for conceptual discovery | **CRITICAL** | Wastes tokens, returns irrelevant matches, pollutes context |
| Using Vera for goto-definition | **HIGH** | LSP is precise; Vera is fuzzy semantic search |
| Searching without checking index exists | **HIGH** | Will fail or return stale results |
| Starting multiple `vera watch` instances | **MEDIUM** | Wastes resources; check if already running |
| Ignoring `--limit` on Vera search | **MEDIUM** | Default may return too many results; use `--limit 5` for focused queries |
```

### 3.2 AGENTS.md Snippet Injection

Vera's own CLI can inject a snippet into `AGENTS.md`:

```bash
vera agent install --client opencode
# After install, Vera offers to inject routing rules into AGENTS.md
```

**However**, for our custom config repo, we should manually curate the routing rules (as shown above) rather than relying on Vera's generic snippet. This ensures:
- Consistency with our existing AGENTS.md structure
- Custom rules specific to our agent assignments
- Integration with our existing toolset (LSP, glob, etc.)

---

## 4. Cold Start Handling

### 4.1 The Problem

When an agent starts work in a new repository:
1. No `.vera/` index exists
2. Agent attempts `vera search` → fails with "no index found"
3. Agent wastes time retrying or falls back to inefficient `rg`

### 4.2 Mitigation Strategy

**AGENTS.md Rule** (added to routing rules):
```markdown
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

4. **Start watcher for session**:
   ```bash
   # Check if watcher already running via state file
   WATCHER_STATE_DIR="$HOME/.local/share/opencode/worktree-state/$(basename $(pwd))/vera-watchers"
   WATCHER_STATE_FILE="$WATCHER_STATE_DIR/$(echo $(pwd) | tr '/' '_').json"
   if [ -f "$WATCHER_STATE_FILE" ]; then
     WATCHER_PID=$(python3 -c "import json; print(json.load(open('$WATCHER_STATE_FILE'))['pid'])")
     if [ -d "/proc/$WATCHER_PID" ] && grep -q "vera watch" "/proc/$WATCHER_PID/cmdline" 2>/dev/null; then
       echo "watcher active (pid: $WATCHER_PID)"
     else
       echo "stale state file, starting watcher"
       vera watch . &
     fi
   else
     vera watch . &
   fi
   ```

5. **Proceed with semantic search**
```

### 4.3 Indexing Performance

| Repository Size | Indexing Time (RTX 4080) | Indexing Time (CPU-only) |
|----------------|--------------------------|--------------------------|
| Small (<10K LOC) | ~2-5s | ~5-15s |
| Medium (100K LOC) | ~5-10s | ~20-60s |
| Large (1M LOC) | ~15-30s | ~2-5min |

**Note**: Indexing is a one-time cost per repository. Incremental updates (`vera update`) are much faster.

### 4.4 Worktree Considerations

Each worktree needs its own `.vera/` index:
```bash
# In worktree A
cd /path/to/worktree-a
vera index .

# In worktree B
cd /path/to/worktree-b
vera index .
```

This is acceptable overhead — worktrees are typically created for isolated feature work, and indexing is fast.

---

## 5. Index Freshness Strategy

### 5.1 The Problem

During active editing:
1. Agent refactors code
2. Agent queries Vera → gets stale results
3. Agent makes decisions based on outdated code → errors

### 5.2 Mitigation: Auto-Start Watcher

**Strategy**: Start `vera watch .` automatically at the beginning of each session.

**Implementation options**:

**Option A: AGENTS.md Hook (Recommended)**
Add to AGENTS.md:
```markdown
### Session Start Protocol

At the start of every coding session:

1. **Ensure index exists**: `test -d .vera || vera index .`
2. **Start background watcher** (if not already running):
   ```bash
   # Check state file for existing watcher before starting
   WATCHER_STATE_DIR="$HOME/.local/share/opencode/worktree-state/$(basename $(pwd))/vera-watchers"
   WATCHER_STATE_FILE="$WATCHER_STATE_DIR/$(echo $(pwd) | tr '/' '_').json"
   WATCHER_ACTIVE=false
   if [ -f "$WATCHER_STATE_FILE" ]; then
     WATCHER_PID=$(python3 -c "import json; print(json.load(open('$WATCHER_STATE_FILE'))['pid'])")
     if [ -d "/proc/$WATCHER_PID" ] && grep -q "vera watch" "/proc/$WATCHER_PID/cmdline" 2>/dev/null; then
       WATCHER_ACTIVE=true
     fi
   fi
   $WATCHER_ACTIVE || vera watch . &
   ```
3. **Verify watcher is active**:
   ```bash
   # Verify via state file
   if [ -f "$WATCHER_STATE_FILE" ]; then
     WATCHER_PID=$(python3 -c "import json; print(json.load(open('$WATCHER_STATE_FILE'))['pid'])")
     if [ -d "/proc/$WATCHER_PID" ] && grep -q "vera watch" "/proc/$WATCHER_PID/cmdline" 2>/dev/null; then
       echo "watcher running (pid: $WATCHER_PID)"
     else
       echo "watcher failed to start"
     fi
   else
     echo "watcher failed to start (no state file)"
   fi
   ```
```

**Option B: Plugin-Based Auto-Start (Future Enhancement)**
Create an OpenCode plugin that:
- Detects when agent enters a new workspace
- Checks for `.vera/` index
- Auto-starts `vera watch` in background
- Reports status to agent

This is out of scope for initial implementation but noted for future enhancement.

### 5.3 Watcher Behavior

`vera watch` characteristics:
- **Debounce**: 2 seconds after last file change
- **Scope**: Recursive, watches entire project subtree
- **Exclusions**: `.vera/` directory (internal index files), `.git/`, files matching `.gitignore`
- **Concurrency**: One update at a time; concurrent changes queued to next cycle
- **Resource usage**: Minimal when idle (event-driven)
- **Output**: Progress messages to stderr

**Sample output**:
```
[watch] file changes detected, starting incremental update
[watch] update complete: 3 modified, 1 added, 0 deleted
```

### 5.4 Manual Update Fallback

If watcher is not running or fails:
```bash
vera update .        # Incremental update (fast)
vera index .         # Full reindex (if update fails)
```

**AGENTS.md Rule**:
```markdown
### Index Freshness Checklist

Before running semantic search after significant edits:
- [ ] Watcher running? Check state file: `cat ~/.local/share/opencode/worktree-state/<project-id>/vera-watchers/<workspace-key>.json` and validate PID via `/proc/<pid>/cmdline`
- [ ] If not running: `vera watch . &` (or `vera update .` for one-time sync)
- [ ] If index corrupted: `vera repair` → `vera index .`
```

---

## 6. Edge Case Mitigations

### 6.1 Stale Index During Active Editing (HIGH SEVERITY)

**Problem**: Agent refactors code, queries stale index, gets wrong results.

**Mitigation**:
1. Auto-start `vera watch .` at session start (2s debounce catches most edits)
2. AGENTS.md rule: Agent MUST run `vera update .` after bulk edits (renames, moves)
3. Vera's incremental updates are fast (~1-5s for typical changes)

### 6.2 Cold Start in New Repos (MEDIUM SEVERITY)

**Problem**: No index exists. Agent must index before searching.

**Mitigation**:
1. AGENTS.md cold start protocol (see Section 4)
2. Vera indexing is fast (Rust binary, local ONNX, no API keys)
3. Agent checks for `.vera/` before discovery tasks

### 6.3 Tool Selection Confusion (MEDIUM SEVERITY)

**Problem**: Agent has vera search, grep, glob, LSP tools. Uses wrong tool for task.

**Mitigation**:
1. Clear AGENTS.md decision tree (see Section 3)
2. "Semantic First" protocol: Use Vera for discovery, LSP for precision, grep for exact strings
3. Anti-patterns table with severity ratings

### 6.4 Vera Binary Not on PATH (MEDIUM SEVERITY)

**Problem**: Agent tries `vera search` → "command not found".

**Mitigation**:
1. AGENTS.md prerequisite check:
   ```bash
   which vera || echo "ERROR: vera not installed. Run: bunx @vera-ai/cli install"
   ```
2. Document installation in README.md
3. `vera doctor` verification after install

### 6.5 Index Across Worktrees (LOW SEVERITY)

**Problem**: Each worktree needs its own `.vera/` index.

**Mitigation**:
1. Acceptable overhead — worktrees are isolated by design
2. Indexing is fast (~5-30s)
3. Document in AGENTS.md worktree section

### 6.6 Large Repository Indexing (LOW SEVERITY)

**Problem**: Very large repos (10M+ LOC) may take minutes to index.

**Mitigation**:
1. Vera supports incremental indexing
2. Use `.gitignore` to exclude non-essential files (generated code, vendor dirs)
3. Consider `--scope source` to limit indexing to application code

### 6.7 GPU/ONNX Runtime Failures (LOW SEVERITY)

**Problem**: ONNX runtime fails on certain hardware configurations.

**Mitigation**:
1. `vera doctor --probe` for deep diagnostics
2. `vera repair` to re-fetch missing assets
3. Fallback to API mode (if acceptable for user's security requirements):
   ```bash
   export EMBEDDING_MODEL_BASE_URL=https://api.jina.ai/v1
   export EMBEDDING_MODEL_API_KEY=your-key
   vera setup --api
   ```

### 6.8 Conflicting Watcher Instances (LOW SEVERITY)

**Problem**: Multiple `vera watch` processes running (resource waste).

**Mitigation**:
1. AGENTS.md rule: Check state file before starting (see Section 5.2 for the state-file-based check pattern)
2. Watcher is lightweight; duplicate instances are wasteful but not harmful

---

## 7. Testing & Verification Strategy

### 7.1 Installation Verification

```bash
# 1. Binary available
which vera

# 2. Version check
vera --version

# 3. Health check
vera doctor

# 4. Skill installed
ls ~/.config/opencode/skills/vera/SKILL.md

# 5. Agent config updated
grep -q "vera" ~/.config/opencode/oh-my-openagent.json && echo "skill assigned" || echo "NOT assigned"
```

### 7.2 Functional Testing

```bash
# Test 1: Index a test repository
cd /tmp/test-repo
vera index .
vera stats

# Test 2: Semantic search
vera search "authentication logic" --limit 3

# Test 3: Regex search
vera grep "TODO|FIXME" -i

# Test 4: References
vera references main

# Test 5: Overview
vera overview

# Test 6: Watcher (start and stop via state file)
vera watch . &
WATCHER_PID=$!
echo "Watcher started with PID: $WATCHER_PID"
# Stop via PID (precise, no broad pkill)
kill $WATCHER_PID 2>/dev/null
wait $WATCHER_PID 2>/dev/null
echo "Watcher stopped"
```

### 7.3 Agent Workflow Testing

Create a test scenario:
1. Enter a new repository
2. Verify agent runs cold start protocol
3. Ask agent: "How does the authentication work?"
4. Verify agent uses `vera search` (not `rg`)
5. Make an edit
6. Verify agent handles index freshness
7. Ask agent to find a specific function
8. Verify agent uses LSP for goto-definition

### 7.4 Performance Benchmarking

Compare token usage with/without Vera:
- Task: "Find the payment validation logic"
- Measure: Input tokens consumed during discovery phase
- Target: 70%+ reduction (based on cocoindex-code benchmarks)

---

## 8. Implementation Checklist

### Phase 1: Documentation & Planning
- [x] Research Vera mechanics and CLI commands
- [x] Evaluate skill vs MCP approach
- [x] Create this implementation plan

### Phase 2: Configuration Updates
- [ ] Update `AGENTS.md` with routing rules (Section 3)
- [ ] Update `configs/oh-my-openagent/oh-my-openagent.json` with skill assignments
- [ ] Update `install.sh` ITEMS array (if adding custom Vera wrapper skill)
- [ ] Update `MANIFEST.md` with new artifacts

### Phase 3: Skill Installation (Per-Machine)
- [ ] Install Vera binary: `bunx @vera-ai/cli install`
- [ ] Setup backend: `vera setup`
- [ ] Verify: `vera doctor`
- [ ] Install skill: `vera agent install --client opencode`
- [ ] Verify skill: `ls ~/.config/opencode/skills/vera/SKILL.md`

### Phase 4: Verification
- [ ] Test indexing: `vera index .` in a test repo
- [ ] Test search: `vera search "test query"`
- [ ] Test watcher: `vera watch .`
- [ ] Test agent workflow: Verify agent uses Vera for discovery

### Phase 5: Documentation Updates
- [ ] Update `docs/skills.md` with Vera skill entry
- [ ] Update `README.md` with Vera in artifact inventory
- [ ] Update `skills/README.md` with Vera overview

---

## 9. Rollback Plan

If Vera causes issues:

1. **Remove skill assignment** from `oh-my-openagent.json`
2. **Stop watcher**: Read PID from workspace state file at `~/.local/share/opencode/worktree-state/<project-id>/vera-watchers/<workspace-key>.json`, validate via `/proc/<pid>/cmdline`, then `kill <pid>`
3. **Remove index** (optional): `rm -rf .vera/`
4. **Remove skill files**: `rm -rf ~/.config/opencode/skills/vera/`
5. **Revert AGENTS.md** to pre-Vera version

Agents fall back to existing tools (grep, LSP, glob) automatically.

---

## 10. Future Enhancements (Post-MVP)

1. **Graphify Integration**: When ready, add graph-based structural analysis as complementary skill
2. **Plugin Auto-Start**: OpenCode plugin to auto-detect missing index and start watcher
3. **Hybrid Graph+Vector**: Custom solution if no off-the-shelf tool provides this
4. **Multi-Repo Indexing**: Index multiple related repositories into single search space
5. **CI Integration**: Auto-index on commit hooks

---

## Appendix A: Vera Command Reference

| Command | Purpose | When to Use |
|---------|---------|-------------|
| `vera index <path>` | Full indexing | First time, or after `vera repair` |
| `vera update <path>` | Incremental update | After edits (if not using watcher) |
| `vera watch <path>` | Background watcher | Start of session, auto-updates on changes |
| `vera search <query>` | Semantic search | Discovery, conceptual queries |
| `vera search --deep <query>` | RAG-fusion search | Complex queries needing expansion |
| `vera search --intent "goal" <query>` | Goal-based reranking | When initial search misses |
| `vera grep <pattern>` | Regex search | Exact strings, imports, TODOs |
| `vera references <symbol>` | Caller analysis | Trace symbol usage |
| `vera references --callees <symbol>` | Callee analysis | Find what a symbol calls |
| `vera dead-code` | Dead code detection | Find unused functions |
| `vera overview` | Project summary | Get oriented in new repo |
| `vera stats` | Index statistics | Verify index health |
| `vera doctor` | Diagnostics | Troubleshoot issues |
| `vera repair` | Fix missing assets | After install issues |

## Appendix B: Comparison with Alternatives

| Feature | Vera | cocoindex-code | Serena | opencode-codebase-index |
|---------|------|----------------|--------|------------------------|
| **Approach** | Hybrid BM25+vector+rerank | Vector-only | LSP-based | Hybrid (claims) |
| **MRR@10** | **0.60** | 0.35 | N/A | Not benchmarked |
| **Runtime deps** | None (single binary) | Python/Node | Language servers | Rust + SQLite |
| **Local inference** | Yes (ONNX) | Yes (optional) | N/A | Yes |
| **API keys** | Not required | Not required | N/A | Not required |
| **Cross-encoder** | Yes | No | N/A | Claims yes |
| **Output format** | Markdown | JSON | Structured | JSON |
| **Agent complexity** | Low | Low | **High** (tool looping) | Medium |
| **Setup time** | ~1 minute | ~1 minute | ~10+ minutes | ~5 minutes |

## Appendix C: Resource Requirements

| Component | Disk | RAM | CPU | GPU |
|-----------|------|-----|-----|-----|
| Vera binary | ~50MB | - | - | - |
| ONNX models | ~200MB | - | - | Optional |
| Index (per repo) | ~1.33x source size | ~100MB | Low | Optional |
| Watcher (idle) | - | ~10MB | Near zero | - |
| Watcher (updating) | - | ~200MB | Moderate | Optional |

**Recommended**: CUDA-compatible GPU for best indexing/search performance. CPU-only mode works but is 2-3x slower.
