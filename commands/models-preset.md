---
description: Show current OMO model assignments in markdown tables
---

Read these files and do not modify them:

1. `~/.config/opencode/oh-my-opencode.json`
2. `~/.config/opencode/opencode.json`

If both files and required keys are present, output exactly three markdown tables, in this order:

## Agents

Read the `agents` object from `~/.config/opencode/oh-my-opencode.json`.

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

Read the `categories` object from `~/.config/opencode/oh-my-opencode.json`.

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

Read the model from `agent.compaction.model` in `~/.config/opencode/opencode.json`.

Use columns:

| Setting | Model |
| ------- | ----- |
| Compaction | ... |

- Output exactly one row for compaction.

Requirements:

- Do not ask follow-up questions.
- Do not include extra commentary before or after the tables.
- Do not include unrelated fields such as descriptions or prompt text.
- If a required file or key is missing, output a brief error message naming the missing file or key and do not output placeholder tables.
