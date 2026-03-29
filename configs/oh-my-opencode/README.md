# Oh-My-OpenCode Configuration

This directory contains the `oh-my-opencode.json` configuration file that defines model assignments, agent overrides, and experimental features for the OpenCode system.

## Configuration Overview

The configuration file (`oh-my-opencode.json`) contains 134 lines and defines custom model assignments for 12 agents, 8 category overrides, browser automation settings, and experimental flags.

### Security Notes
- ✅ No hardcoded personal home-directory paths
- ✅ No embedded API keys or secrets
- ✅ Safe for version control

## Agent Overrides (12 Total)

The configuration overrides the default model assignments for the following agents:

| Agent | Model | Variant | Fallback Models |
|-------|-------|---------|-----------------|
| **atlas** | `github-copilot/gpt-5.4` | default | `zai-coding-plan/glm-5` |
| **prometheus** | `github-copilot/claude-opus-4.6` | default | `zai-coding-plan/glm-5` |
| **sisyphus** | `github-copilot/gpt-5.4` | `high` | `zai-coding-plan/glm-5` |
| **librarian** | `github-copilot/gemini-3-flash-preview` | `high` | `google/antigravity-gemini-3-flash` |
| **explore** | `opencode-go/minimax-m2.7` | default | `github-copilot/grok-code-fast-1` |
| **frontend-ui-ux-engineer** | `github-copilot/gemini-3.1-pro-preview` | default | `zai-coding-plan/glm-5` |
| **document-writer** | `moonshot/kimi-k2.5` | default | `zai-coding-plan/glm-5` |
| **multimodal-looker** | `moonshot/kimi-k2.5` | default | (none) |
| **oracle** | `github-copilot/gpt-5.4` | `high` | `github-copilot/claude-opus-4.6` |
| **metis** | `github-copilot/gpt-5.4` | `xhigh` | (none) |
| **momus** | `github-copilot/gpt-5.4` | `high` | `github-copilot/claude-opus-4.6` |
| **hephaestus** | `github-copilot/gpt-5.3-codex` | `xhigh` | (none) |

### Agent Configuration Details

- **atlas** (Orchestrator): GPT-5.4 with wisdom injection protocol, integrated with system-level learnings
- **prometheus** (Planner): Claude Opus 4.6 for deep reasoning and planning
- **sisyphus** (Executor): High-variant GPT-5.4 for focused task execution
- **librarian** (Search/Docs): Gemini 3 Flash Preview with high reasoning for documentation retrieval
- **explore** (Discovery): MiniMax M2.7 for deep exploration, Grok Code Fast 1 fallback
- **frontend-ui-ux-engineer** (Designer): Gemini 3.1 Pro for complex frontend/UX work
- **document-writer** (Writing): Kimi K2.5 for document generation and writing tasks
- **multimodal-looker** (Media Analysis): Kimi K2.5 for image/PDF analysis
- **oracle** (Q&A): GPT-5.4 high-variant with Claude fallback for knowledge queries
- **metis** (Analysis): GPT-5.4 xhigh-variant for in-depth analysis
- **momus** (Critique): GPT-5.4 high-variant with Claude fallback for code review/criticism
- **hephaestus** (Builder/Infrastructure): GPT-5.3 Codex xhigh-variant for infrastructure and deployment

## Category Overrides (8 Total)

Category-level model assignments that apply when tasks don't specify a specific agent:

| Category | Model | Fallback Models | Notes |
|----------|-------|-----------------|-------|
| **visual-engineering** | `github-copilot/gemini-3.1-pro-preview` | `zai-coding-plan/glm-5` | Includes Tailwind CSS & shadcn/ui prompt |
| **artistry** | `github-copilot/gemini-3.1-pro-preview` | `zai-coding-plan/glm-5` | For creative/design tasks |
| **writing** | `moonshot/kimi-k2.5` | `zai-coding-plan/glm-5` | For documentation and content writing |
| **ultrabrain** | `github-copilot/gpt-5.4` | `zai-coding-plan/glm-5` | High-capability reasoning tasks |
| **quick** | `github-copilot/claude-haiku-4.5` | (none) | Fast execution for simple tasks |
| **unspecified-low** | `deepseek/deepseek-chat` | (none) | Default for low-complexity tasks |
| **unspecified-high** | `github-copilot/gpt-5.4` | (none) | Default for high-complexity tasks |
| **deep** | `github-copilot/gpt-5.4` | `zai-coding-plan/glm-5` | Deep analysis and reasoning |

## Browser Automation Configuration

```json
"browser_automation_engine": {
  "provider": "playwright-cli"
}
```

The configuration uses **playwright-cli** as the browser automation provider, enabling automated browser testing, form filling, and web scraping capabilities.

## Runtime Fallback Settings

```json
"runtime_fallback": {
  "enabled": true,
  "retry_on_errors": [404, 429, 500, 502, 503, 504]
}
```

- **Enabled**: Fallback models are automatically used on API errors
- **Retry on Errors**: HTTP status codes 404 (Not Found), 429 (Rate Limit), 500 (Server Error), 502 (Bad Gateway), 503 (Service Unavailable), 504 (Gateway Timeout)

## Experimental Features

The configuration enables several experimental features:

| Feature | Setting | Purpose |
|---------|---------|---------|
| **aggressive_truncation** | `true` | Aggressively truncate verbose tool outputs to save tokens |
| **truncate_all_tool_outputs** | `true` | Apply truncation to all tool outputs |
| **preemptive_compaction** | `false` | Disabled: don't compact context before reaching limit |
| **dynamic_context_pruning** (DCP) | `enabled: true` | Intelligently remove tool outputs based on relevance |
| DCP notification mode | `minimal` | Show only important notifications |

### Dynamic Context Pruning (DCP) Strategy

DCP protects critical tools from pruning:

**Protected Tools**: `task`, `todowrite`, `todoread`, `lsp_rename`, `session_read`, `session_write`, `session_search`

**DCP Strategies**:
- **Deduplication**: Remove duplicate tool outputs within context
- **Supersede Writes**: Replace older outputs with newer versions
- **Purge Errors**: Remove error messages after 5 turns

**Turn Protection**: Critical tools protected for 3 turns after each use

## Git Configuration

```json
"git_master": {
  "commit_footer": false,
  "include_co_authored_by": false
}
```

- Commits do not include footers
- Co-authored-by attribution is disabled

## Usage

This configuration file is automatically loaded by the OpenCode system and defines behavior for:
- Model selection for agents and categories
- Browser automation capabilities
- Fallback strategies for API failures
- Context optimization to maximize reasoning capability within token budgets
- Git workflow preferences

## Version Info

- Configuration Format: Schema from oh-my-opencode project
- Google Auth: Disabled
- Last Updated: March 2026
