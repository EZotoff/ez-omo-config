---
description: Show current OMO model assignments in markdown tables and flag inconsistent, duplicate, or stale assignments
---

Read these files and do not modify them:

1. `~/.config/opencode/oh-my-openagent.json`
2. `~/.config/opencode/opencode.json`

If both files and required keys are present, output exactly four markdown tables, in this order:

## Agents

Read the `agents` object from `~/.config/opencode/oh-my-openagent.json`.

Use columns:

| Agent | Model | Variant | Fallback Models |
| ----- | ----- | ------- | --------------- |

- Include one row for every key under `agents`.
- `Model` comes from `agents.<name>.model`.
- `Variant` comes from `agents.<name>.variant`.
- `Fallback Models` comes from `agents.<name>.fallback_models`.
- If `variant` or `fallback_models` is missing, show `—`.
- Format fallback model arrays as comma-separated values.

## Categories

Read the `categories` object from `~/.config/opencode/oh-my-openagent.json`.

Use columns:

| Category | Model | Variant | Fallback Models |
| -------- | ----- | ------- | --------------- |

- Include one row for every key under `categories`.
- `Model` comes from `categories.<name>.model`.
- `Variant` comes from `categories.<name>.variant`.
- `Fallback Models` comes from `categories.<name>.fallback_models`.
- If `variant` or `fallback_models` is missing, show `—`.
- Format fallback model arrays as comma-separated values.

## Compaction

Compaction has no pinned model — `agent.compaction.model` is intentionally unset in `~/.config/opencode/opencode.json`, so compaction runs on the triggering session's model (which the chat-level fallback machinery keeps healthy). On compaction-mode provider failures, `provider-connect-retry.mjs` retries compaction through the `compaction_fallback_models` chain in `~/.config/opencode/retry-errors.json`.

Use columns:

| Setting | Value |
| ------- | ----- |
| Compaction model | follows session model |
| Compaction fallback chain | ... |

- Read the chain from `compaction_fallback_models` in `~/.config/opencode/retry-errors.json`; format as comma-separated entries.
- Output exactly these two rows for compaction.

## Small Model

Read the model from `small_model` in `~/.config/opencode/opencode.json`.

Use columns:

| Setting | Model |
| ------- | ----- |
| Small Model | ... |

- Output exactly one row for the small model.

## Consistency Scan

After the four tables, scan every model assignment shown above (agents, categories, compaction chain, small model) and flag issues. Output one row per finding:

| Severity | Location | Finding |
| -------- | -------- | ------- |

- Severity is `ERROR` (broken or wasteful reference) or `WARN` (suspicious, needs operator confirmation).
- Location is the agent, category, or setting name.
- If nothing is found, output a single line: `No consistency issues found.`

Check for all of the following:

1. **Redundant fallbacks** — the primary model repeated inside its own `fallback_models`, or duplicate entries within one chain.
2. **Stale model generations** — a model id for which a newer generation exists on the same provider (e.g. `gemini-3.7-*` when `gemini-3.8-*` is available). Compare against the `provider.<id>.models` blocks in `~/.config/opencode/opencode.json`; for built-in providers (google, openai, opencode-go) cross-check the live catalog (models.dev or the provider's `/v1/models`) before flagging.
3. **Unresolvable references** — model ids absent from the provider's configured models and its built-in catalog, or whose provider is missing from `enabled_providers`.
4. **Provider preference inversions** — a pay-per-token API provider referenced where an enabled gateway/subscription provider serves the same underlying model (e.g. `deepseek/*` API where `opencode-go` or `ollama-cloud` serve the same DeepSeek model).
5. **Context regressions** — a fallback with a materially smaller context window than the primary it backs (token-limit recovery depends on large-context fallbacks; compare `limit.context`).
6. **Variant validity** — a `variant` set on a model that defines no variants, a variant id not in the model's variant list, or a missing `variant` on a reasoning model whose sibling assignments consistently set one.

Do not modify any file while scanning. Findings are advisory output only.

Requirements:

- Do not ask follow-up questions.
- Do not include extra commentary outside the four tables and the Consistency Scan section.
- Do not include unrelated fields such as descriptions or prompt text.
- If a required file or key is missing, output a brief error message naming the missing file or key and do not output placeholder tables.
