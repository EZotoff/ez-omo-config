# ez-omo-config — Agent Instructions

## What This Is

This project is the **versioned config store** for OpenCode and Oh-My-OpenCode (OMO).
It is NOT the active config that OpenCode reads at runtime.

## Config Locations

| Purpose | Path | Notes |
|---------|------|-------|
| **Active config** (OpenCode reads this) | `~/.config/opencode/opencode.json` | Machine-local, not git-tracked |
| **Active OMO config** | `~/.config/opencode/oh-my-opencode.json` | Machine-local, not git-tracked |
| **Versioned config store** | `projects/ez-omo-config/configs/opencode/opencode.json` | Git-tracked, portable |
| **Versioned OMO config store** | `projects/ez-omo-config/configs/oh-my-opencode/oh-my-opencode.json` | Git-tracked, portable |
| **Auth / API keys** | `~/.local/share/opencode/auth.json` | Machine-local, NEVER committed |

## Critical Rule: Propagation

**Any change to the active local configs (`~/.config/opencode/`) MUST be propagated to the corresponding file in `projects/ez-omo-config/configs/`.**

The store is the source of truth for what the intended configuration looks like. If you edit only the local config, the change is invisible to version control and will be lost or forgotten.

## Critical Rule: Adaptation (Do NOT Blindly Copy)

When propagating local config changes to the store, you MUST adapt machine-specific values to their portable equivalents. **Never copy local configs to the store verbatim.**

Common machine-specific patterns to watch for:

| Local (machine-specific) | Store (portable) | Example |
|--------------------------|------------------|---------|
| `file:///home/username/omo-hub/some-plugin/index.mjs` | npm package name (e.g. `some-plugin`) | `file:///home/ezotoff/omo-hub/browser-lifecycle-plugin/index.mjs` → `browser-lifecycle-plugin` |
| Absolute paths with `/home/username/...` | `$HOME`-relative or package names | Depends on context |
| Experimental/temporary provider entries | Omit or mark as experimental | Local testing providers |

### How to Propagate Correctly

1. Make your change in the **active local config** (so OpenCode picks it up immediately)
2. Open the corresponding file in `projects/ez-omo-config/configs/`
3. Apply the same logical change, but **replace any machine-specific values** with portable equivalents
4. Validate both files are valid JSON after editing

## Provider Setup

- **Built-in providers** (e.g. `google`, `github-copilot`, `opencode-go`): Only need an entry in `enabled_providers` array + API key in `auth.json`. No `npm` or `options.baseURL` needed.
- **Custom/OpenAI-compatible providers** (e.g. `moonshot`, `kimi-code`, `deepseek`): Need full provider block with `npm: "@ai-sdk/openai-compatible"`, `options.baseURL`, and model definitions.
- **Auth keys**: Stored in `~/.local/share/opencode/auth.json` under the provider ID. Format: `{ "type": "api", "key": "sk-..." }`. Never commit this file.
