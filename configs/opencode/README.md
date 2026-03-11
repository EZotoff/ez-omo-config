# OpenCode Core Configuration

This directory contains the portable OpenCode config bundle copied from the local OpenCode installation.

| File | What it configures | Install target |
|---|---|---|
| `opencode.json` | Main OpenCode configuration: enabled providers, plugins, models, limits, and runtime defaults | `$HOME/.config/opencode/opencode.json` |
| `opencode.jsonc` | Local bash permission restrictions for destructive commands | `$HOME/.opencode/opencode.jsonc` |
| `provider-connect-retry.mjs` | Plugin that retries failed provider connections with bounded backoff | `$HOME/.config/opencode/provider-connect-retry.mjs` |
| `extras/ocx.jsonc` | OCX registry configuration pointer used by the OCX CLI | `$HOME/.opencode/ocx.jsonc` |

## Portability notes

- Hardcoded personal paths were normalized to `$HOME` notation.
- Configuration values and experimental settings were otherwise preserved as-is.
- The copied files were checked for obvious API keys, tokens, and private key material before adding them to the repo.
